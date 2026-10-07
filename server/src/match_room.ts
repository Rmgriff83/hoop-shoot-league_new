/**
 * One 1v1 match (docs/BACKEND.md → Phase 3): a Durable Object holding both
 * phones' WebSockets with the Hibernation API. It relays the few small
 * messages between them, hands both the same seed, keeps the period
 * reports, writes the finished match to D1 and tears itself down. It never
 * simulates anything — each phone owns its own shots.
 *
 * Throttling, layer 5: ≤ MAX_PER_S messages/s and ≤ MAX_BYTES each per
 * socket (over → close 1008), WAIT_MS for a peer to arrive, IDLE_MS of
 * silence, LIFETIME_MS hard cap, CLOSE_AFTER_MS once decided.
 */
import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";

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
interface Player { id: string; name: string; tag: string }
interface Meta {
  area: string;
  created: number;
  status: "waiting" | "playing" | "done";
  seed: number;
  started: number;
  last: number;
  a: Player | null;
  b: Player | null;
  ends: Record<Side, Record<string, { score: number; totals: unknown }>>;
  reason: string;
  recorded: boolean;
}
interface Attachment { side: Side; pid: string; win: number; n: number }

const other = (s: Side): Side => (s === "a" ? "b" : "a");

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

  /** The Worker forwards an authenticated upgrade with the player in headers. */
  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") return new Response("expected websocket", { status: 426 });
    const player: Player = {
      id: request.headers.get("x-player-id") ?? "",
      name: request.headers.get("x-player-name") ?? "THEM",
      tag: request.headers.get("x-player-tag") ?? "",
    };
    const area = request.headers.get("x-area") ?? "cage";
    const room = request.headers.get("x-room") ?? "";
    if (!player.id) return new Response("who", { status: 400 });
    const now = Date.now();
    let m = await this.meta();
    if (!m) {
      m = { area, created: now, status: "waiting", seed: 0, started: 0, last: now, a: null, b: null, ends: { a: {}, b: {} }, reason: "", recorded: false };
      await this.ctx.storage.setAlarm(now + WAIT_MS);
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
    this.send(server, { t: "joined", side, room, area: m.area, peer, status: m.status });
    if (peer) this.sendSide(other(side), { t: "peer", peer: player });
    if (m.status === "waiting" && m.a && m.b) {
      m.status = "playing";
      m.seed = Math.floor(Math.random() * 2_147_483_647) + 1;
      m.started = now;
      await this.ctx.storage.setAlarm(now + LIFETIME_MS);
      const start = { t: "start", seed: m.seed, area: m.area, seconds: HEAT_SECONDS, ot_seconds: OT_SECONDS, ball_return_s: BALL_RETURN_S };
      for (const ws of this.sockets()) this.send(ws, start);
    } else if (m.status === "playing" && m.seed) {
      // A reconnect mid-match gets the start again (the phone decides what to do with it).
      this.send(server, { t: "start", seed: m.seed, area: m.area, seconds: HEAT_SECONDS, ot_seconds: OT_SECONDS, ball_return_s: BALL_RETURN_S, resumed: true });
    }
    await this.put(m);
    return new Response(null, { status: 101, webSocket: client });
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
    if (!m || m.status !== "playing") return this.send(ws, { t: "error", code: "not_playing" });
    m.last = now;
    switch (msg.t) {
      case "shot":
      case "outcome":
        this.sendSide(other(att.side), { ...msg, from: att.side });
        break;
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
          await this.record(m, a.score, b.score, period, msg.desync ? 1 : 0);
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
    if (!att || !m || m.status === "done") return;
    if (this.sockets(att.side).some((s) => s !== ws)) return; // they reconnected already
    this.sendSide(other(att.side), { t: "peer_left", side: att.side });
    if (m.status === "playing") {
      m.status = "done";
      const played = Date.now() - m.started;
      m.reason = played >= 30_000 ? "forfeit" : "void";
      const latest = (s: Side) => { const ks = Object.keys(m.ends[s]).map(Number); return ks.length ? m.ends[s][String(Math.max(...ks))].score : 0; };
      await this.record(m, latest("a"), latest("b"), 0, 0);
      await this.ctx.storage.setAlarm(Date.now() + CLOSE_AFTER_MS);
      await this.put(m);
    }
  }

  private async record(m: Meta, a: number, b: number, period: number, desync: number): Promise<void> {
    if (m.recorded || !m.a || !m.b) return;
    m.recorded = true;
    try {
      await this.env.DB.prepare(
        "INSERT OR IGNORE INTO matches (room, area, a_id, b_id, a_score, b_score, ot, reason, desync, ended_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
      ).bind(this.ctx.id.toString(), m.area, m.a.id, m.b.id, a, b, period, m.reason, desync, Date.now()).run();
    } catch (e) {
      console.error("record", e);
    }
  }

  /** Nobody came / the match ran too long / time to tear down. */
  async alarm(): Promise<void> {
    const m = await this.meta();
    if (!m) return this.ctx.storage.deleteAll();
    const now = Date.now();
    if (m.status === "waiting") {
      for (const ws of this.sockets()) { this.send(ws, { t: "expired" }); try { ws.close(1000, "expired"); } catch { /* gone */ } }
      await this.ctx.storage.deleteAll();
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
