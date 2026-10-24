/**
 * Ranked Stage B in the room (docs/BACKEND.md → Ranked → Stage B): spoils,
 * insurance, the same-opponent cap, the meter, the streak Ice, milestones,
 * tickets, the kill switch, rated rematches — plus the pure rules against
 * tests/fixtures/online_drops_cases.json (shared with the game).
 */
import { SELF, env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import fixture from "../../tests/fixtures/online_drops_cases.json";
import { resetBoardCache } from "../src/index";
import { resetMemoryLimits } from "../src/limits";
import { DROPS, METER_SIZE, derive, meterGain, milestonesReached, nextLossStreak, rarityOdds, rollCard, rng, settleSpoils } from "../src/online_drops";
import { bandOf, conservative, defaultRow, type RatingRow } from "../src/rank";
import { QUEUE, TICKETS } from "../src/ranked_data";

const uuid = () => crypto.randomUUID();
const secret = () => [...crypto.getRandomValues(new Uint8Array(40))].map((b) => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[b % 62]).join("");
let ipCounter = 310_000;
const freshIp = () => `10.${Math.floor(ipCounter / 65536) % 256}.${Math.floor(ipCounter / 256) % 256}.${ipCounter++ % 256}`;

interface Player { playerId: string; secret: string; ip: string }
const known: Player[] = [];

async function register(level = 1): Promise<Player> {
  const p = { playerId: uuid(), secret: secret(), ip: freshIp() };
  const res = await SELF.fetch("https://api/v1/register", {
    method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": p.ip },
    body: JSON.stringify({ playerId: p.playerId, secret: p.secret, clientId: uuid() }),
  });
  expect(res.status).toBe(200);
  if (level > 1) await env.DB.prepare("UPDATE players SET level = ?1 WHERE id = ?2").bind(level, p.playerId).run();
  known.push(p);
  return p;
}
const auth = (p: Player) => ({ authorization: `Bearer ${p.playerId}.${p.secret}`, "cf-connecting-ip": p.ip, "content-type": "application/json" });
const give = (p: Player, cardId: string, n: number) => env.DB.prepare("INSERT INTO online_cards (player_id, card_id, n) VALUES (?1, ?2, ?3) ON CONFLICT(player_id, card_id) DO UPDATE SET n = ?3").bind(p.playerId, cardId, n).run();
const count = async (p: Player, cardId: string) => (await env.DB.prepare("SELECT n FROM online_cards WHERE player_id = ?1 AND card_id = ?2").bind(p.playerId, cardId).first<{ n: number }>())?.n ?? 0;
const progress = (p: Player) => env.DB.prepare("SELECT * FROM online_progress WHERE player_id = ?1").bind(p.playerId).first<any>();
const ledger = async (p: Player, kind: string) => (await env.DB.prepare("SELECT COUNT(*) AS n FROM online_ledger WHERE player_id = ?1 AND kind = ?2").bind(p.playerId, kind).first<{ n: number }>())!.n;
const grants = async (p: Player) => (await env.DB.prepare("SELECT key, kind, card_id, claimed_at FROM grants WHERE player_id = ?1 ORDER BY key").bind(p.playerId).all<any>()).results;
async function ranked(p: Player) {
  const res = await SELF.fetch("https://api/v1/match/ranked", { method: "POST", headers: auth(p), body: "{}" });
  return { status: res.status, json: (await res.json()) as any };
}
const leave = (p: Player) => SELF.fetch("https://api/v1/match/leave", { method: "POST", headers: auth(p), body: JSON.stringify({ ranked: true }) });
async function setRating(p: Player, mu: number, rd: number, over: Partial<RatingRow> = {}) {
  const cons = conservative(mu, rd);
  const band = bandOf(cons);
  const r: RatingRow = { ...defaultRow(p.playerId, Date.now()), mu, rd, cons, tier: band.tier, division: band.division, peak_tier: band.tier, peak_division: band.division, ...over };
  await env.DB.prepare(
    `INSERT OR REPLACE INTO ratings (player_id, mu, rd, vol, cons, games, wins, losses, win_streak, loss_streak, tier, division, peak_tier, peak_division, shield_left, updated_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)`,
  ).bind(r.player_id, r.mu, r.rd, r.vol, r.cons, r.games, r.wins, r.losses, r.win_streak, r.loss_streak, r.tier, r.division, r.peak_tier, r.peak_division, r.shield_left, r.updated_at).run();
  return r;
}
const setProgress = (p: Player, over: Record<string, number>) => {
  const row = { meter: 0, login_days: 0, last_login_day: 0, last_seen_day: 0, first_win_day: 0, loss_streak_played: 0, streak_card_day: 0, updated_at: 0, ...over };
  return env.DB.prepare(
    `INSERT OR REPLACE INTO online_progress (player_id, meter, login_days, last_login_day, last_seen_day, first_win_day, loss_streak_played, streak_card_day, updated_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)`,
  ).bind(p.playerId, row.meter, row.login_days, row.last_login_day, row.last_seen_day, row.first_win_day, row.loss_streak_played, row.streak_card_day, row.updated_at).run();
};

/** Into the room; the pre-match pick answers with `slots`, ready at once. */
async function join(p: Player, room: string, slots = ",,") {
  const res = await SELF.fetch(`https://api/v1/match/room/${room}?area=cage`, { headers: { ...auth(p), upgrade: "websocket" } });
  expect(res.status).toBe(101);
  const ws = res.webSocket!;
  const inbox: any[] = [];
  ws.accept();
  ws.addEventListener("message", (e) => {
    const m = JSON.parse(String(e.data));
    inbox.push(m);
    if (m.t === "matched") ws.send(JSON.stringify({ t: "loadout", slots: slots.split(",").slice(0, 3), ready: true }));
  });
  const until = async (pred: (m: any) => boolean, ms = 2500) => {
    const t0 = Date.now();
    while (Date.now() - t0 < ms) {
      const hit = inbox.find(pred);
      if (hit) return hit;
      await new Promise((r) => setTimeout(r, 10));
    }
    throw new Error("timeout; inbox=" + JSON.stringify(inbox));
  };
  return { ws, inbox, until, send: (m: unknown) => ws.send(JSON.stringify(m)), settle: () => new Promise((r) => setTimeout(r, 80)) };
}

/**
 * Two players through the queue into one ranked room, tipped off. A pair
 * whose ratings drifted apart (after a first match) is outside the opening
 * window, so the clock jumps past cap_s and the Lobby takes the best available.
 */
async function rankedPair(a: Player, b: Player, slotsA = ",,", slotsB = ",,") {
  const qa = await ranked(a);
  let qb = await ranked(b);
  if (!qb.json.paired) {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(Date.now() + (QUEUE.cap_s + 1) * 1000);
    qb = await ranked(b);
  }
  expect(qb.json.paired).toBe(true);
  const room = qa.json.room as string;
  const A = await join(a, room, slotsA);
  const B = await join(b, room, slotsB);
  await A.until((m) => m.t === "start");
  await B.until((m) => m.t === "start");
  return { room, A, B };
}

/** Both report the period; the higher score takes it. */
async function decide(A: any, B: any, sa: number, sb: number, period = 0) {
  A.send({ t: "period_end", period, score: sa, totals: {} });
  B.send({ t: "period_end", period, score: sb, totals: {} });
  const a = await A.until((m: any) => m.t === "settled");
  const b = await B.until((m: any) => m.t === "settled");
  return { a, b };
}

const nextSecond = () => new Promise((r) => setTimeout(r, 1005 - (Date.now() % 1000)));

beforeEach(async () => {
  vi.useRealTimers();
  resetMemoryLimits();
  resetBoardCache();
  for (const p of known) await leave(p);
  resetMemoryLimits();
});
afterEach(() => vi.useRealTimers());

describe("the rules (pure)", () => {
  it("derives the meter from the reference player, as the fixture pins", () => {
    const d = derive();
    const f = fixture.derive;
    expect(d.points_per_match).toBeCloseTo(f.points_per_match, 3);
    expect(d.first_win_days).toBeCloseTo(f.first_win_days, 3);
    expect(d.points_per_week).toBeCloseTo(f.points_per_week, 3);
    expect(d.streak_cards_per_week).toBeCloseTo(f.streak_cards_per_week, 3);
    expect(d.meter_size).toBe(f.meter_size);
    expect(METER_SIZE).toBe(f.meter_size);
    expect(d.ratio).toBeCloseTo(f.ratio, 3);
    expect(d.ratio).toBeGreaterThanOrEqual(DROPS.ratio_band[0]);
    expect(d.ratio).toBeLessThanOrEqual(DROPS.ratio_band[1]);
  });
  it("shows the odds the fixture pins, per tier and level", () => {
    for (const c of fixture.odds) {
      const o = rarityOdds(c.tier, c.level);
      expect(o.common, `${c.tier} ${c.level}`).toBeCloseTo(c.common, 3);
      expect(o.rare, `${c.tier} ${c.level}`).toBeCloseTo(c.rare, 3);
      expect(o.epic, `${c.tier} ${c.level}`).toBeCloseTo(c.epic, 3);
    }
  });
  it("rolls only cards the level and tier allow, deterministically", () => {
    const seen = new Set<string>();
    for (let i = 0; i < 200; i++) seen.add(rollCard("rookie", 5, rng(i)));
    expect([...seen].sort()).toEqual(["fire7", "ice"]); // the magnet waits a tier
    expect(rollCard("pro", 5, rng(7))).toBe(rollCard("pro", 5, rng(7)));
    expect(rollCard("rookie", 1, rng(3))).toBe("ice");
  });
  it("meter: a win, a close loss, a plain loss, the first win of the day", () => {
    expect(meterGain({ won: true, margin: 9, period: 0, firstWinToday: false })).toBe(DROPS.meter.win);
    expect(meterGain({ won: true, margin: 9, period: 0, firstWinToday: true })).toBe(DROPS.meter.win + DROPS.meter.first_win_day);
    expect(meterGain({ won: false, margin: -2, period: 0, firstWinToday: false })).toBe(DROPS.meter.close_loss);
    expect(meterGain({ won: false, margin: -9, period: 1, firstWinToday: false })).toBe(DROPS.meter.close_loss);
    expect(meterGain({ won: false, margin: -9, period: 0, firstWinToday: true })).toBe(DROPS.meter.loss);
  });
  it("spoils: the loser's played to the winner, insurance keeps the best one, a void moves nothing", () => {
    const played = { a: ["ice"], b: ["ice", "fire7"] };
    const s = settleSpoils("a", "played", played, false);
    expect(s.a).toEqual({ captured: ["ice", "fire7"], lost: [], insured: null });
    expect(s.b).toEqual({ captured: [], lost: ["ice", "fire7"], insured: null });
    const ins = settleSpoils("a", "played", played, true);
    expect(ins.b.insured).toBe("fire7");
    expect(ins.a.captured).toEqual(["ice"]);
    expect(settleSpoils("b", "forfeit", played, false).b.captured).toEqual(["ice"]);
    expect(settleSpoils(null, "void", played, false).a.captured).toEqual([]);
  });
  it("the played-loss streak: a loss counts, a win resets, the leaver's forfeit does neither", () => {
    expect(nextLossStreak(2, false, "played", false)).toBe(3);
    expect(nextLossStreak(2, true, "played", false)).toBe(0);
    expect(nextLossStreak(2, false, "forfeit", true)).toBe(2);
    expect(nextLossStreak(2, true, "forfeit", false)).toBe(0);
  });
  it("milestones by peak: every band crossed, the first match / win / capture, the win counts", () => {
    const before = { ...defaultRow("x", 0), tier: "rookie", division: 3, peak_tier: "rookie", peak_division: 3 };
    const after = { ...before, games: 1, wins: 1, tier: "starter", division: 2, peak_tier: "starter", peak_division: 2 };
    const keys = milestonesReached(before, after, true, 1).map((h) => h.key);
    expect(keys).toEqual(["first_ranked_match", "first_ranked_win", "first_capture", "division_rookie_2", "division_rookie_1", "tier_starter", "division_starter_3", "division_starter_2"]);
    const w9 = { ...before, games: 20, wins: 9, peak_tier: "starter", peak_division: 2, tier: "starter", division: 2 };
    expect(milestonesReached(w9, { ...w9, games: 21, wins: 10 }, true, 0).map((h) => h.key)).toEqual(["ranked_wins_10"]);
    expect(milestonesReached(w9, { ...w9, games: 21, losses: 1, tier: "starter", division: 3 }, false, 0)).toEqual([]);
  });
});

describe("the decision pays (room)", () => {
  it("spoils: the winner takes the loser's played cards, never their own; tickets and the meter move", async () => {
    const a = await register(3);
    const b = await register(3);
    await give(a, "ice", 2);
    await give(b, "fire7", 1);
    await give(b, "ice", 1);
    const { room, A, B } = await rankedPair(a, b, "ice,,", "fire7,ice,");
    await nextSecond();
    A.send({ t: "card", id: "ice" });
    B.send({ t: "card", id: "fire7" });
    B.send({ t: "card", id: "ice" });
    await A.until((m) => m.t === "card_ok");
    await B.until((m) => m.t === "card_ok" && m.id === "ice");
    await nextSecond();
    const { a: sa, b: sb } = await decide(A, B, 30, 20);
    expect(sa.won).toBe(true);
    expect(sa.pay).toBe(true);
    expect(sa.spoils).toEqual({ captured: ["fire7", "ice"], lost: [], insured: null });
    expect(sb.spoils).toEqual({ captured: [], lost: ["fire7", "ice"], insured: null });
    expect(sa.tickets).toBe(TICKETS.win);
    expect(sb.tickets).toBe(TICKETS.loss);
    expect(sa.meter).toMatchObject({ before: 0, after: DROPS.meter.win + DROPS.meter.first_win_day, size: METER_SIZE });
    expect(sb.meter.after).toBe(DROPS.meter.loss);
    expect(sa.meter.odds.common).toBeGreaterThan(0);
    // (A first win from a fresh 1500/350 rating also jumps the peak a division or two: those keys ride along.)
    expect(sa.milestones).toEqual(expect.arrayContaining(["first_capture", "first_ranked_match", "first_ranked_win"]));
    expect(sb.milestones).toEqual(["first_ranked_match"]);
    expect(sb.loss_streak).toBe(1);
    // The ledger: a's ice was spent (1 left), then two captures; b's two played are gone.
    expect(await count(a, "ice")).toBe(2);
    expect(await count(a, "fire7")).toBe(1);
    expect(await count(b, "fire7")).toBe(0);
    expect(await count(b, "ice")).toBe(0);
    expect(await ledger(a, "capture")).toBe(2);
    const row = await env.DB.prepare("SELECT pay, a_played, b_played FROM matches WHERE room = ?1").bind(env.ROOM.idFromName(room).toString()).first<any>();
    expect(row).toEqual({ pay: 1, a_played: '["ice"]', b_played: '["fire7","ice"]' });
    expect((await grants(b)).map((g: any) => g.key)).toEqual(["first_ranked_match"]);
    expect((await grants(a)).map((g: any) => g.key)).toEqual(expect.arrayContaining(["first_capture", "first_ranked_match", "first_ranked_win"]));
  });

  it("insurance: a loser on a long streak keeps the best played card; the streak Ice lands once a day", async () => {
    const a = await register(3);
    const b = await register(3);
    await give(b, "fire7", 1);
    await give(b, "ice", 1);
    await setProgress(b, { loss_streak_played: 3 });
    const { A, B } = await rankedPair(a, b, ",,", "fire7,ice,");
    await nextSecond();
    B.send({ t: "card", id: "fire7" });
    B.send({ t: "card", id: "ice" });
    await B.until((m) => m.t === "card_ok" && m.id === "ice");
    await nextSecond();
    const { a: sa, b: sb } = await decide(A, B, 30, 20);
    expect(sb.spoils).toEqual({ captured: [], lost: ["ice"], insured: "fire7" });
    expect(sa.spoils.captured).toEqual(["ice"]);
    expect(await count(b, "fire7")).toBe(1);
    expect(await ledger(b, "insured")).toBe(1);
    // The 4th straight played loss: a guaranteed Ice, booked as `streak`.
    expect(sb.loss_streak).toBe(4);
    expect(sb.granted).toEqual([{ why: "loss_streak", card: "ice" }]);
    expect(await ledger(b, "streak")).toBe(1);
    expect((await progress(b)).streak_card_day).toBeGreaterThan(0);
    // A 5th loss the same day: no second Ice.
    await leave(a); await leave(b);
    const again = await rankedPair(a, b);
    const { b: sb2 } = await decide(again.A, again.B, 30, 20);
    expect(sb2.loss_streak).toBe(5);
    expect(sb2.granted).toEqual([]);
    expect(await ledger(b, "streak")).toBe(1);
  });

  it("the same-opponent cap: the third ranked game of the day is rated but pays no spoils or meter", async () => {
    const a = await register(3);
    const b = await register(3);
    await give(b, "ice", 3);
    for (let i = 0; i < 2; i++) {
      const { A, B } = await rankedPair(a, b);
      const { a: sa } = await decide(A, B, 30, 20);
      expect(sa.pay).toBe(true);
      await leave(a); await leave(b);
    }
    const { A, B } = await rankedPair(a, b, ",,", "ice,,");
    await nextSecond();
    B.send({ t: "card", id: "ice" });
    await B.until((m) => m.t === "card_ok");
    await nextSecond();
    const meterBefore = (await progress(a)).meter;
    const { a: sa, b: sb } = await decide(A, B, 30, 20);
    expect(sa.pay).toBe(false);
    expect(sa.rating.delta).toBeGreaterThan(0);
    expect(sa.spoils.captured).toEqual([]);
    expect(sb.spoils.lost).toEqual([]);
    expect(sa.meter.after).toBe(meterBefore);
    expect(sa.tickets).toBe(TICKETS.win);
    expect(await ledger(a, "capture")).toBe(0);
    expect(await count(b, "ice")).toBe(2); // played one, lost none
  });

  it("a full meter grants a card by the tier's odds and carries the rest", async () => {
    const a = await register(5);
    const b = await register(5);
    await setProgress(a, { meter: METER_SIZE - 1 });
    const { A, B } = await rankedPair(a, b);
    const { a: sa } = await decide(A, B, 30, 20);
    expect(sa.granted.length).toBe(1);
    expect(sa.granted[0].why).toBe("meter");
    expect(["ice", "fire7"]).toContain(sa.granted[0].card); // rookie: the magnet waits a tier
    expect(sa.meter.after).toBe(METER_SIZE - 1 + DROPS.meter.win + DROPS.meter.first_win_day - METER_SIZE);
    expect(await count(a, sa.granted[0].card)).toBe(1);
    expect(await ledger(a, "meter")).toBe(1);
  });

  it("the first win of the day pays its bonus once", async () => {
    const a = await register(2);
    const b = await register(2);
    const r1 = await rankedPair(a, b);
    const { a: s1 } = await decide(r1.A, r1.B, 30, 20);
    expect(s1.meter.after).toBe(DROPS.meter.win + DROPS.meter.first_win_day);
    await leave(a); await leave(b);
    const r2 = await rankedPair(a, b);
    const { a: s2 } = await decide(r2.A, r2.B, 30, 20);
    const gain = s2.meter.after - s2.meter.before + (s2.granted.some((g: any) => g.why === "meter") ? METER_SIZE : 0);
    expect(gain).toBe(DROPS.meter.win);
  });

  it("a forfeit: the leaver's played cards go to the one who stayed; the leaver's streak does not move", async () => {
    const a = await register(3);
    const b = await register(3);
    await give(b, "ice", 1);
    await setProgress(b, { loss_streak_played: 1 });
    const { A, B } = await rankedPair(a, b, ",,", "ice,,");
    await nextSecond();
    B.send({ t: "card", id: "ice" });
    await B.until((m) => m.t === "card_ok");
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(Date.now() + 31_000);
    B.ws.close(1000, "bye");
    const sa = await A.until((m) => m.t === "settled", 3000);
    expect(sa.reason).toBe("forfeit");
    expect(sa.won).toBe(true);
    expect(sa.spoils.captured).toEqual(["ice"]);
    expect(sa.tickets).toBe(TICKETS.win);
    expect(await count(a, "ice")).toBe(1);
    expect((await progress(b)).loss_streak_played).toBe(1);
  });

  it("a void writes no spoils, no meter, no tickets", async () => {
    const a = await register(3);
    const b = await register(3);
    const { A, B } = await rankedPair(a, b);
    B.ws.close(1000, "bye"); // under 30 s played
    const sa = await A.until((m) => m.t === "settled", 3000);
    expect(sa.reason).toBe("void");
    expect(sa.spoils).toBeUndefined();
    expect(sa.tickets).toBeUndefined();
    expect(await progress(a)).toBeNull();
  });

  it("milestones are idempotent across decisions, and the rank keys follow the peak", async () => {
    const a = await register(3);
    const b = await register(3);
    await setRating(a, 1500, 60, { games: 9, wins: 9 });
    await setRating(b, 1500, 60, { games: 9, wins: 0, losses: 9 });
    const r1 = await rankedPair(a, b);
    const { a: s1 } = await decide(r1.A, r1.B, 30, 20);
    expect(s1.milestones).toContain("ranked_wins_10");
    const n1 = (await grants(a)).length;
    await leave(a); await leave(b);
    const r2 = await rankedPair(a, b);
    const { a: s2 } = await decide(r2.A, r2.B, 30, 20);
    expect(s2.milestones).not.toContain("ranked_wins_10");
    expect(s2.milestones).not.toContain("first_ranked_match");
    expect((await grants(a)).length).toBeGreaterThanOrEqual(n1);
    expect((await grants(a)).filter((g: any) => g.key === "ranked_wins_10").length).toBe(1);
  });

  it("a rematch of a ranked match is ranked too", async () => {
    const a = await register(3);
    const b = await register(3);
    const { A, B } = await rankedPair(a, b);
    await decide(A, B, 30, 20);
    await nextSecond();
    A.send({ t: "rematch" });
    B.send({ t: "rematch" });
    const go = await A.until((m) => m.t === "rematch_go");
    const first = A.inbox.find((m) => m.t === "start");
    const row = await env.DB.prepare("SELECT area, a_id, b_id FROM ranked_rooms WHERE room = ?1").bind(go.room).first<any>();
    expect(row).toEqual({ area: first.area, a_id: a.playerId, b_id: b.playerId });
    const A2 = await join(a, go.room);
    const B2 = await join(b, go.room);
    const start = await A2.until((m) => m.t === "start");
    expect(start.ranked).toBe(true);
    await B2.until((m) => m.t === "start");
  });

  it("card_ok only after the ledger moved: an unknown card is refused and never relayed", async () => {
    const a = await register(3);
    const b = await register(3);
    const { A, B } = await rankedPair(a, b);
    await nextSecond();
    A.send({ t: "card", id: "fire7" });
    const err = await A.until((m) => m.t === "error" && m.code === "card");
    expect(err.id).toBe("fire7");
    await B.settle();
    expect(B.inbox.some((m) => m.t === "card")).toBe(false);
  });
});
