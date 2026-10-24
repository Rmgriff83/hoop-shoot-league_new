/**
 * One 1v1 match (docs/BACKEND.md → Phase 3, Ranked): a Durable Object holding
 * both phones' WebSockets with the Hibernation API. Once both are seated it
 * runs the pre-match step (each phone picks its hand under the room's cap,
 * the lower of the two levels, inside PREMATCH.seconds), hands both the same
 * seed, relays the few small messages between them, keeps the period
 * reports, writes the finished match to D1 — and, for a room the Lobby
 * paired as ranked (`x-ranked`, set by the Worker from `ranked_rooms`),
 * moves both ratings — then tears itself down. It never simulates anything:
 * each phone owns its own shots.
 *
 * Throttling, layer 5: ≤ MAX_PER_S messages/s and ≤ MAX_BYTES each per
 * socket (over → close 1008), WAIT_MS for a peer to arrive, IDLE_MS of
 * silence, LIFETIME_MS hard cap, CLOSE_AFTER_MS once decided.
 */
import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";
import { SLOTS, inventoryOf, validHand, type Inventory } from "./cards";
import { rankedPosition, ratingOf, upsertRatingStatement } from "./db";
import { dayOf, dayStart } from "./days";
import { DROPS, METER_SIZE, meterGain, milestonesReached, nextLossStreak, rarityOdds, settleSpoils } from "./online_drops";
import { applyResult, currentRd, defaultRow, type RatingRow } from "./rank";
import { DIVISIONS, PREMATCH, TICKETS, TIERS } from "./ranked_data";
import { cardOfRarity, cardStatements, grantStatement, meterCard, progressOf, upsertProgressStatement, type Progress } from "./rewards";

export const MAX_PER_S = 5;
export const MAX_BYTES = 2048;
export const WAIT_MS = 60_000;
export const IDLE_MS = 120_000;
export const LIFETIME_MS = 10 * 60_000;
export const CLOSE_AFTER_MS = 60_000;
export const HEAT_SECONDS = 90;
export const OT_SECONDS = 20;
export const BALL_RETURN_S = 1.0;

type Side = "a" | "b";
interface Player {
  id: string; name: string; tag: string; level: number; town?: string; tier: string; division: number;
  /** The pre-match card's stats (design "Pre Match" 37a): the rating shown, the record, the world position (0 = unrated). */
  cons: number; games: number; wins: number; losses: number; position: number;
}
interface Meta {
  area: string;
  created: number;
  status: "waiting" | "prematch" | "playing" | "done";
  seed: number;
  started: number;
  last: number;
  a: Player | null;
  b: Player | null;
  ends: Record<Side, Record<string, { score: number; totals: unknown }>>;
  /** Each side's validated hand (card ids; a played card leaves it). */
  hands: Record<Side, string[]>;
  /** Each side's cards the room relayed (the spoils at the decision; Stage B). */
  played: Record<Side, string[]>;
  /** The Lobby paired this room for ranked play (the Worker says so, never the phone). */
  ranked: boolean;
  /** The card level cap: the lower of the two levels. */
  cap: number;
  /** Each side's ledger at the pre-match step, so a loadout is checked without D1. */
  inv: Record<Side, Inventory | null>;
  ready: Record<Side, boolean>;
  /** A side that reported its period and then dropped: finished, not forfeiting. */
  leftWaiting: Side | null;
  /** Rematch offers after the decision; both → a fresh room for the pair. */
  rematch: Record<Side, boolean>;
  reason: string;
  recorded: boolean;
}
interface Attachment { side: Side; pid: string; win: number; n: number }

const other = (s: Side): Side => (s === "a" ? "b" : "a");
const blank = (): string[] => Array.from({ length: SLOTS }, () => "");
const bandOfPlayer = (p: Player | null) => ({ tier: p?.tier ?? TIERS[0].id, division: p?.division ?? DIVISIONS });

export class MatchRoom extends DurableObject<Env> {
  private async meta(): Promise<Meta | undefined> {
    return this.ctx.storage.get<Meta>("meta");
  }

  private async put(m: Meta): Promise<void> {
    await this.ctx.storage.put("meta", m);
  }

  private sockets(side?: Side): WebSocket[] {
    return side ? this.ctx.getWebSockets(side) : this.ctx.getWebSockets();
  }

  private send(ws: WebSocket, msg: unknown): void {
    try {
      ws.send(JSON.stringify(msg));
    } catch {
      /* closing */
    }
  }

  private sendSide(side: Side, msg: unknown): void {
    for (const ws of this.sockets(side)) this.send(ws, msg);
  }

  private levels(m: Meta) {
    return { a: m.a?.level ?? 1, b: m.b?.level ?? 1 };
  }

  private tiers(m: Meta) {
    return { a: bandOfPlayer(m.a), b: bandOfPlayer(m.b) };
  }

  /** Each side's pre-match stats: rating shown, record, world position. */
  private stats(m: Meta) {
    const of = (p: Player | null) => ({ cons: p?.cons ?? 0, games: p?.games ?? 0, wins: p?.wins ?? 0, losses: p?.losses ?? 0, position: p?.position ?? 0 });
    return { a: of(m.a), b: of(m.b) };
  }

  /** The pre-match card: who you face, both levels, tiers and stats, the cap, the clock, the count after both READY. */
  private matched(m: Meta, side: Side) {
    return {
      t: "matched", peer: m[other(side)], area: m.area, levels: this.levels(m), tiers: this.tiers(m), stats: this.stats(m), cap: m.cap,
      seconds: PREMATCH.seconds, countdown_s: PREMATCH.countdown_s, ranked: m.ranked,
    };
  }

  private start(m: Meta, resumed = false) {
    return {
      t: "start", seed: m.seed, area: m.area, seconds: HEAT_SECONDS, ot_seconds: OT_SECONDS, ball_return_s: BALL_RETURN_S,
      hands: m.hands, levels: this.levels(m), ranked: m.ranked, cap: m.cap, tiers: this.tiers(m), countdown_s: PREMATCH.countdown_s,
      ...(resumed ? { resumed: true } : {}),
    };
  }

  /** The Worker forwards an authenticated upgrade with the player in headers. */
  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") return new Response("expected websocket", { status: 426 });
    const player: Player = {
      id: request.headers.get("x-player-id") ?? "",
      name: request.headers.get("x-player-name") ?? "THEM",
      tag: request.headers.get("x-player-tag") ?? "",
      level: Number.parseInt(request.headers.get("x-player-level") ?? "1", 10) || 1,
      town: request.headers.get("x-player-town") ?? "",
      tier: request.headers.get("x-player-tier") ?? TIERS[0].id,
      division: Number.parseInt(request.headers.get("x-player-division") ?? String(DIVISIONS), 10) || DIVISIONS,
      cons: Number.parseInt(request.headers.get("x-player-cons") ?? "0", 10) || 0,
      games: Number.parseInt(request.headers.get("x-player-games") ?? "0", 10) || 0,
      wins: Number.parseInt(request.headers.get("x-player-wins") ?? "0", 10) || 0,
      losses: Number.parseInt(request.headers.get("x-player-losses") ?? "0", 10) || 0,
      position: Number.parseInt(request.headers.get("x-player-position") ?? "0", 10) || 0,
    };
    if (!TIERS.some((t) => t.id === player.tier)) player.tier = TIERS[0].id;
    const ranked = request.headers.get("x-ranked") === "1";
    const area = request.headers.get("x-area") ?? "cage";
    const room = request.headers.get("x-room") ?? "";
    if (!player.id) return new Response("who", { status: 400 });
    const now = Date.now();
    let m = await this.meta();
    if (!m) {
      m = {
        area, created: now, status: "waiting", seed: 0, started: 0, last: now, a: null, b: null, ends: { a: {}, b: {} },
        hands: { a: blank(), b: blank() }, played: { a: [], b: [] }, ranked, cap: 0, inv: { a: null, b: null }, ready: { a: false, b: false },
        leftWaiting: null, rematch: { a: false, b: false }, reason: "", recorded: false,
      };
      await this.ctx.storage.setAlarm(now + WAIT_MS);
    } else if (m.area === "any" && area !== "any") {
      // An any-court host: the room takes the court the Lobby paired on, which the joiner brings.
      m.area = area;
    }
    if (m.status === "done") return new Response("over", { status: 410 });
    let side: Side;
    if (m.a?.id === player.id) side = "a";
    else if (m.b?.id === player.id) side = "b";
    else if (!m.a) { side = "a"; m.a = player; }
    else if (!m.b) { side = "b"; m.b = player; }
    else return new Response("full", { status: 409 });
    // A reconnect replaces the old socket.
    for (const old of this.sockets(side)) { try { old.close(1000, "replaced"); } catch { /* gone */ } }
    const pair = new WebSocketPair();
    const [client, server] = [pair[0], pair[1]];
    this.ctx.acceptWebSocket(server, [side]);
    server.serializeAttachment({ side, pid: player.id, win: 0, n: 0 } satisfies Attachment);
    m.last = now;
    const peer = m[other(side)];
    this.send(server, { t: "joined", side, room, area: m.area, peer, status: m.status, ranked: m.ranked });
    // The court rides along: an any-court host learns here where it plays.
    if (peer) this.sendSide(other(side), { t: "peer", peer: player, area: m.area });
    if (m.status === "waiting" && m.a && m.b) {
      // Both seated: the pre-match step. Each ledger is read once, here.
      m.status = "prematch";
      m.cap = Math.min(m.a.level, m.b.level);
      const [ia, ib] = await Promise.all([inventoryOf(this.env.DB, m.a.id), inventoryOf(this.env.DB, m.b.id)]);
      m.inv = { a: ia, b: ib };
      m.hands = { a: blank(), b: blank() };
      m.ready = { a: false, b: false };
      await this.ctx.storage.setAlarm(now + (PREMATCH.seconds + PREMATCH.grace_s) * 1000);
      for (const s of ["a", "b"] as Side[]) this.sendSide(s, this.matched(m, s));
    } else if (m.status === "prematch") {
      // Back during the pick: the card again, with the clock as it stands.
      this.send(server, this.matched(m, side));
    } else if (m.status === "playing" && m.seed) {
      // A reconnect mid-match gets the start again (the phone decides what to do with it).
      this.send(server, this.start(m, true));
    }
    await this.put(m);
    return new Response(null, { status: 101, webSocket: client });
  }

  /** Tip-off: both ready, or the pre-match clock ran out. A side that never picked plays blank. */
  private async startMatch(m: Meta, now: number): Promise<void> {
    m.status = "playing";
    m.seed = Math.floor(Math.random() * 2_147_483_647) + 1;
    m.started = now;
    m.last = now;
    await this.ctx.storage.setAlarm(now + LIFETIME_MS);
    const start = this.start(m);
    for (const ws of this.sockets()) this.send(ws, start);
  }

  async webSocketMessage(ws: WebSocket, raw: string | ArrayBuffer): Promise<void> {
    const att = ws.deserializeAttachment() as Attachment;
    const text = typeof raw === "string" ? raw : new TextDecoder().decode(raw);
    if (text.length > MAX_BYTES) return ws.close(1008, "too big");
    const now = Date.now();
    const win = Math.floor(now / 1000);
    if (att.win === win) att.n += 1; else { att.win = win; att.n = 1; }
    ws.serializeAttachment(att);
    if (att.n > MAX_PER_S) return ws.close(1008, "too fast");
    let msg: any;
    try { msg = JSON.parse(text); } catch { return this.send(ws, { t: "error", code: "json" }); }
    if (!msg || typeof msg.t !== "string") return this.send(ws, { t: "error", code: "shape" });
    if (msg.t === "ping") return this.send(ws, { t: "pong", now });
    const m = await this.meta();
    if (!m) return this.send(ws, { t: "error", code: "not_playing" });
    if (msg.t === "rematch") {
      // Only on the post-match page: both offers → a fresh room for the same pair.
      if (m.status !== "done") return this.send(ws, { t: "error", code: "not_done" });
      if (!m.rematch) m.rematch = { a: false, b: false };
      m.rematch[att.side] = true;
      m.last = now;
      this.sendSide(other(att.side), { t: "rematch", from: att.side });
      if (m.rematch.a && m.rematch.b) {
        const room = crypto.randomUUID();
        if (m.ranked && m.a && m.b) {
          // A rematch of a ranked match stays ranked (Ross, 2026-10-23): the Worker reads this row at the upgrade.
          try {
            await this.env.DB.prepare("INSERT OR IGNORE INTO ranked_rooms (room, area, a_id, b_id, created_at) VALUES (?1, ?2, ?3, ?4, ?5)").bind(room, m.area, m.a.id, m.b.id, now).run();
          } catch (e) {
            console.error("rematch ranked_rooms", e);
          }
        }
        for (const s of this.sockets()) this.send(s, { t: "rematch_go", room, area: m.area });
        await this.ctx.storage.setAlarm(now + 5_000);
      } else {
        await this.ctx.storage.setAlarm(now + CLOSE_AFTER_MS); // the offer buys another minute
      }
      await this.put(m);
      return;
    }
    if (msg.t === "loadout") {
      // The pre-match pick: three slots, kept only as far as the ledger, the cap and the tier allow.
      if (m.status !== "prematch") return this.send(ws, { t: "error", code: "not_prematch" });
      const slots = msg.slots;
      const ok = Array.isArray(slots) && slots.length <= SLOTS && slots.every((s: unknown) => typeof s === "string") && typeof msg.ready === "boolean";
      if (!ok) return this.send(ws, { t: "error", code: "loadout" });
      const player = m[att.side];
      const inv = m.inv[att.side] ?? { inventory: {}, level: player?.level ?? 1 };
      m.hands[att.side] = validHand(slots as string[], inv, m.cap, player?.tier ?? TIERS[0].id);
      m.ready[att.side] = msg.ready;
      m.last = now;
      this.send(ws, { t: "loadout_ok", hand: m.hands[att.side], ready: m.ready[att.side] });
      // The other phone watches the pick fill in (design "Pre Match" 37a: THEIR LOADOUT, their READY chip).
      this.sendSide(other(att.side), { t: "peer_loadout", slots: m.hands[att.side], ready: m.ready[att.side], from: att.side });
      if (m.ready.a && m.ready.b) await this.startMatch(m, now);
      await this.put(m);
      return;
    }
    if (m.status !== "playing") return this.send(ws, { t: "error", code: "not_playing" });
    m.last = now;
    switch (msg.t) {
      case "shot":
      case "outcome":
        this.sendSide(other(att.side), { ...msg, from: att.side });
        break;
      case "card": {
        // Only a card the ledger put in this hand, once; the copy leaves the ledger now.
        const id = typeof msg.id === "string" ? msg.id : "";
        const hand = m.hands[att.side];
        const at = hand.indexOf(id);
        if (at < 0) { this.send(ws, { t: "error", code: "card", id }); break; }
        hand.splice(at, 1);
        const pid = att.side === "a" ? m.a?.id : m.b?.id;
        try {
          await this.env.DB.batch([
            this.env.DB.prepare("UPDATE online_cards SET n = n - 1 WHERE player_id = ?1 AND card_id = ?2 AND n > 0").bind(pid, id),
            this.env.DB.prepare("INSERT INTO online_ledger (player_id, kind, card_id, coins, room, at) VALUES (?1, 'play', ?2, 0, ?3, ?4)").bind(pid, id, this.ctx.id.toString(), now),
          ]);
        } catch (e) {
          // The ledger did not move: the card is still theirs, and nothing was relayed.
          console.error("card ledger", e);
          hand.splice(at, 0, id);
          this.send(ws, { t: "error", code: "card", id });
          break;
        }
        if (!m.played) m.played = { a: [], b: [] };
        m.played[att.side].push(id);
        this.send(ws, { t: "card_ok", id });
        this.sendSide(other(att.side), { t: "card", id, from: att.side });
        break;
      }
      case "period_end": {
        const period = Number.isInteger(msg.period) ? msg.period : 0;
        const score = Number.isInteger(msg.score) ? msg.score : 0;
        m.ends[att.side][String(period)] = { score, totals: msg.totals ?? {} };
        this.sendSide(other(att.side), { ...msg, from: att.side });
        const a = m.ends.a[String(period)];
        const b = m.ends.b[String(period)];
        if (a && b && a.score !== b.score) {
          m.status = "done";
          m.reason = "played";
          await this.record(m, a.score, b.score, period, msg.desync ? 1 : 0, a.score > b.score ? "a" : "b");
          await this.ctx.storage.setAlarm(now + CLOSE_AFTER_MS);
        } else if (a && b && m.leftWaiting) {
          // A tie, and one of them already left: no overtime to play — the one who stayed takes it.
          m.status = "done";
          m.reason = "forfeit";
          await this.record(m, a.score, b.score, period, 0, other(m.leftWaiting));
          await this.ctx.storage.setAlarm(now + CLOSE_AFTER_MS);
        }
        break;
      }
      default:
        this.send(ws, { t: "error", code: "unknown" });
    }
    await this.put(m);
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string): Promise<void> {
    await this.gone(ws, reason);
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    await this.gone(ws, "error");
  }

  /** A phone dropped: tell the other; a match in play ends by forfeit. */
  private async gone(ws: WebSocket, reason: string): Promise<void> {
    if (reason === "replaced") return;
    const att = ws.deserializeAttachment() as Attachment | null;
    const m = await this.meta();
    if (!att || !m) return;
    if (this.sockets(att.side).some((s) => s !== ws)) return; // they reconnected already
    if (m.status === "done") {
      // Off the post-match page: the other phone's REMATCH reads THEY LEFT.
      this.sendSide(other(att.side), { t: "peer_left", side: att.side });
      return;
    }
    if (m.status === "playing") {
      // Reported this period and then went? They are finished, not forfeiting:
      // the other phone's report still decides it.
      const mine = Object.keys(m.ends[att.side]).length;
      const theirs = Object.keys(m.ends[other(att.side)]).length;
      if (mine > theirs) {
        m.leftWaiting = att.side;
        m.last = Date.now();
        await this.put(m);
        return;
      }
    }
    this.sendSide(other(att.side), { t: "peer_left", side: att.side });
    if (m.status === "prematch") {
      // Gone before the tip-off: nothing was played, nothing is written; the pre-match alarm closes the room.
      m.status = "done";
      m.reason = "void";
      await this.put(m);
      return;
    }
    if (m.status === "playing") {
      m.status = "done";
      const played = Date.now() - m.started;
      m.reason = played >= 30_000 ? "forfeit" : "void";
      const latest = (s: Side) => { const ks = Object.keys(m.ends[s]).map(Number); return ks.length ? m.ends[s][String(Math.max(...ks))].score : 0; };
      await this.record(m, latest("a"), latest("b"), 0, 0, m.reason === "forfeit" ? other(att.side) : null);
      await this.ctx.storage.setAlarm(Date.now() + CLOSE_AFTER_MS);
      await this.put(m);
    }
  }

  /**
   * The match is decided: write it and tell each phone how it went. A ranked
   * room with a winner (played or forfeit, no desync) moves both ratings in
   * the same batch; a void, a desync or a casual room leaves them alone.
   */
  private async record(m: Meta, a: number, b: number, period: number, desync: number, winner: Side | null): Promise<void> {
    if (m.recorded || !m.a || !m.b) return;
    m.recorded = true;
    const now = Date.now();
    const room = this.ctx.id.toString();
    const db = this.env.DB;
    const rated = m.ranked && winner !== null && !desync && (m.reason === "played" || m.reason === "forfeit");
    const settled: Record<Side, Record<string, unknown>> = {
      a: { t: "settled", won: winner === "a", reason: m.reason, ranked: m.ranked },
      b: { t: "settled", won: winner === "b", reason: m.reason, ranked: m.ranked },
    };
    if (desync) { settled.a.desync = true; settled.b.desync = true; }
    const stmts: D1PreparedStatement[] = [];
    let mus: Record<Side, { before: number | null; after: number | null }> = { a: { before: null, after: null }, b: { before: null, after: null } };
    let rows: Record<Side, RatingRow> | null = null;
    const played: Record<Side, string[]> = m.played ?? { a: [], b: [] };
    let pay = 1;
    // Where each side's milestone grants sit in the batch: a key is NEW only when its INSERT OR IGNORE changed a row.
    const grantAt: Record<Side, { key: string; at: number }[]> = { a: [], b: [] };
    try {
      if (rated) {
        const [ra, rb] = await Promise.all([ratingOf(db, m.a.id), ratingOf(db, m.b.id)]);
        const before: Record<Side, RatingRow> = { a: ra ?? defaultRow(m.a.id, now), b: rb ?? defaultRow(m.b.id, now) };
        // Each side meets the other's rating as it stood BEFORE this match, widened for idle time.
        const opp = (s: Side) => ({ mu: before[other(s)].mu, rd: currentRd(before[other(s)], now) });
        const applied = {
          a: applyResult(before.a, opp("a"), winner === "a" ? "win" : "loss", now),
          b: applyResult(before.b, opp("b"), winner === "b" ? "win" : "loss", now),
        };
        rows = { a: applied.a.row, b: applied.b.row };
        mus = { a: { before: applied.a.before.mu, after: applied.a.after.mu }, b: { before: applied.b.before.mu, after: applied.b.after.mu } };
        stmts.push(upsertRatingStatement(db, rows.a), upsertRatingStatement(db, rows.b));
        for (const s of ["a", "b"] as Side[]) {
          const r = applied[s];
          settled[s].rating = { before: r.before, after: r.after, delta: r.after.mu - r.before.mu };
          settled[s].rank = { tier: r.row.tier, division: r.row.division };
          settled[s].events = r.events;
          settled[s].peak = { tier: r.row.peak_tier, division: r.row.peak_division };
        }
        if ((this.env.FEATURE_DROPS ?? "on") === "on") {
          // Stage B (docs/BACKEND.md → Ranked → Stage B): spoils, the meter, the streak Ice, milestones, tickets.
          const today = dayOf(now);
          const pairRow = await db
            .prepare("SELECT COUNT(*) AS n FROM matches WHERE ranked = 1 AND pay = 1 AND ended_at >= ?1 AND ((a_id = ?2 AND b_id = ?3) OR (a_id = ?3 AND b_id = ?2))")
            .bind(dayStart(today), m.a.id, m.b.id)
            .first<{ n: number }>();
          pay = (pairRow?.n ?? 0) < DROPS.same_opponent_cap_per_day ? 1 : 0;
          const [pa, pb] = await Promise.all([progressOf(db, m.a.id), progressOf(db, m.b.id)]);
          const progress: Record<Side, Progress> = { a: pa, b: pb };
          const loser: Side = winner === "a" ? "b" : "a";
          const insured = progress[loser].loss_streak_played >= DROPS.insurance.losses;
          const spoils = pay ? settleSpoils(winner, m.reason, played, insured) : settleSpoils(null, m.reason, played, false);
          for (const s of ["a", "b"] as Side[]) {
            const pid = m[s]!.id;
            const level = m[s]!.level;
            const won = winner === s;
            const row = rows[s];
            const p = progress[s];
            const sp = spoils[s];
            const granted: { why: string; card: string }[] = [];
            for (const id of sp.captured) stmts.push(...cardStatements(db, pid, id, "capture", room, now));
            if (sp.insured) stmts.push(...cardStatements(db, pid, sp.insured, "insured", room, now));
            const meterBefore = p.meter;
            if (pay) {
              const firstWinToday = won && p.first_win_day !== today;
              p.meter += meterGain({ won, margin: s === "a" ? a - b : b - a, period, firstWinToday });
              if (firstWinToday) p.first_win_day = today;
              if (p.meter >= METER_SIZE) {
                const card = meterCard(row.tier, level, `${room}:${s}:${row.games}`);
                if (card) {
                  p.meter -= METER_SIZE;
                  stmts.push(...cardStatements(db, pid, card, "meter", room, now));
                  granted.push({ why: "meter", card });
                }
              }
            }
            const leaver = m.reason === "forfeit" && !won;
            p.loss_streak_played = nextLossStreak(p.loss_streak_played, won, m.reason, leaver);
            if (p.loss_streak_played >= DROPS.streak_card.losses && p.streak_card_day !== today) {
              p.streak_card_day = today;
              stmts.push(...cardStatements(db, pid, DROPS.streak_card.card, "streak", room, now));
              granted.push({ why: "loss_streak", card: DROPS.streak_card.card });
            }
            for (const h of milestonesReached(before[s], row, won, sp.captured.length)) {
              grantAt[s].push({ key: h.key, at: stmts.length });
              stmts.push(grantStatement(db, pid, h.key, "milestone", cardOfRarity(row.tier, level, h.rarity, `${pid}:${h.key}`), now));
            }
            p.updated_at = now;
            stmts.push(upsertProgressStatement(db, p));
            settled[s].pay = pay === 1;
            settled[s].tickets = won ? TICKETS.win : TICKETS.loss;
            settled[s].spoils = sp;
            settled[s].meter = { before: meterBefore, after: p.meter, size: METER_SIZE, odds: rarityOdds(row.tier, level) };
            settled[s].granted = granted;
            settled[s].loss_streak = p.loss_streak_played;
            settled[s].milestones = [];
          }
        }
      }
      const matchStmt = db
        .prepare(
          `INSERT OR IGNORE INTO matches (room, area, a_id, b_id, a_score, b_score, ot, reason, desync, ended_at, ranked, winner, a_level, b_level, cap, a_mu_before, a_mu_after, b_mu_before, b_mu_after, pay, a_played, b_played)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22)`,
        )
        .bind(room, m.area, m.a.id, m.b.id, a, b, period, m.reason, desync, now, m.ranked ? 1 : 0, winner, m.a.level, m.b.level, m.cap, mus.a.before, mus.a.after, mus.b.before, mus.b.after, pay, JSON.stringify(played.a), JSON.stringify(played.b));
      const results = await db.batch([matchStmt, ...stmts]);
      for (const s of ["a", "b"] as Side[]) {
        if (!grantAt[s].length) continue;
        settled[s].milestones = grantAt[s].filter(({ at }) => ((results[at + 1]?.meta as { changes?: number } | undefined)?.changes ?? 0) > 0).map(({ key }) => key);
      }
      if (rows) {
        // Legend shows where it stands in the world rather than a division.
        const legend = TIERS[TIERS.length - 1].id;
        for (const s of ["a", "b"] as Side[]) {
          if (rows[s].tier === legend) (settled[s].rank as Record<string, unknown>).position = await rankedPosition(db, rows[s].cons, rows[s].updated_at);
        }
      }
    } catch (e) {
      console.error("record", e);
    }
    for (const side of ["a", "b"] as Side[]) this.sendSide(side, settled[side]);
  }

  /** Nobody came / the pick ran out / the match ran too long / time to tear down. */
  async alarm(): Promise<void> {
    const m = await this.meta();
    if (!m) return this.ctx.storage.deleteAll();
    const now = Date.now();
    if (m.status === "waiting") {
      for (const ws of this.sockets()) { this.send(ws, { t: "expired" }); try { ws.close(1000, "expired"); } catch { /* gone */ } }
      await this.ctx.storage.deleteAll();
      return;
    }
    if (m.status === "prematch") {
      // The clock ran out: tip off with whatever each side last sent.
      await this.startMatch(m, now);
      await this.put(m);
      return;
    }
    if (m.status === "playing") {
      if (now - m.last > IDLE_MS || now - m.started > LIFETIME_MS) {
        m.status = "done";
        m.reason = "void";
        for (const ws of this.sockets()) { this.send(ws, { t: "expired" }); try { ws.close(1000, "expired"); } catch { /* gone */ } }
        await this.ctx.storage.deleteAll();
        return;
      }
      await this.ctx.storage.setAlarm(now + IDLE_MS);
      return;
    }
    for (const ws of this.sockets()) { try { ws.close(1000, "over"); } catch { /* gone */ } }
    await this.ctx.storage.deleteAll();
  }
}
