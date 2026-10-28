import { SELF, env, runDurableObjectAlarm } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { app, resetBoardCache } from "../src/index";
import { resetMemoryLimits } from "../src/limits";
import { DROP_GRACE_MS } from "../src/match_room";
import { bandOf, conservative, defaultRow, type RatingRow } from "../src/rank";
import { QUEUE, TIERS } from "../src/ranked_data";

const uuid = () => crypto.randomUUID();
const secret = () => [...crypto.getRandomValues(new Uint8Array(40))].map((b) => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[b % 62]).join("");
let ipCounter = 210_000;
const freshIp = () => `10.${Math.floor(ipCounter / 65536) % 256}.${Math.floor(ipCounter / 256) % 256}.${ipCounter++ % 256}`;
const LEGEND = TIERS[TIERS.length - 1].id;

interface Player { playerId: string; secret: string; ip: string; name: string; tag: string }
/** Everyone this file made, so each test starts with an empty ranked queue (the Lobby is one object). */
const known: Player[] = [];

/** A player at `level`: set straight in the row (a fresh account is only believed up to 2). */
async function register(level = 1): Promise<Player> {
  const p = { playerId: uuid(), secret: secret(), ip: freshIp() };
  const res = await SELF.fetch("https://api/v1/register", {
    method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": p.ip },
    body: JSON.stringify({ playerId: p.playerId, secret: p.secret, clientId: uuid() }),
  });
  expect(res.status).toBe(200);
  const j = (await res.json()) as { name: string; tag: string };
  if (level > 1) await env.DB.prepare("UPDATE players SET level = ?1 WHERE id = ?2").bind(level, p.playerId).run();
  const out = { ...p, name: j.name, tag: j.tag };
  known.push(out);
  return out;
}
const auth = (p: Player) => ({ authorization: `Bearer ${p.playerId}.${p.secret}`, "cf-connecting-ip": p.ip, "content-type": "application/json" });

async function ranked(p: Player) {
  const res = await SELF.fetch("https://api/v1/match/ranked", { method: "POST", headers: auth(p), body: "{}" });
  return { status: res.status, json: (await res.json()) as any };
}
const leave = (p: Player) => SELF.fetch("https://api/v1/match/leave", { method: "POST", headers: auth(p), body: JSON.stringify({ ranked: true }) });
async function board(p: Player) {
  const res = await SELF.fetch("https://api/v1/ranked/board", { headers: auth(p) });
  return { status: res.status, json: (await res.json()) as any };
}
const me = async (p: Player) => (await SELF.fetch("https://api/v1/me", { headers: auth(p) })).json() as Promise<any>;
const ratingRow = (p: Player) => env.DB.prepare("SELECT * FROM ratings WHERE player_id = ?1").bind(p.playerId).first<RatingRow>();

/** A ratings row at mu/rd, shown at the rank that earns, plus overrides. */
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

/** Only the clock: the socket helpers below still need real timeouts. */
function advance(ms: number) {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(Date.now() + ms);
}

/** Open the room socket and collect its messages; the pre-match pick is sent by hand. */
async function join(p: Player, room: string, area = "cage", extra: Record<string, string> = {}) {
  const res = await SELF.fetch(`https://api/v1/match/room/${room}?area=${area}`, { headers: { ...auth(p), ...extra, upgrade: "websocket" } });
  expect(res.status).toBe(101);
  const ws = res.webSocket!;
  const inbox: any[] = [];
  ws.accept();
  ws.addEventListener("message", (e) => inbox.push(JSON.parse(String(e.data))));
  const until = async (pred: (m: any) => boolean, ms = 2000) => {
    const t0 = Date.now();
    while (Date.now() - t0 < ms) {
      const hit = inbox.find(pred);
      if (hit) return hit;
      await new Promise((r) => setTimeout(r, 10));
    }
    throw new Error("timeout waiting for " + pred.toString() + " inbox=" + JSON.stringify(inbox));
  };
  const send = (m: unknown) => ws.send(JSON.stringify(m));
  return { ws, inbox, until, send, ready: () => send({ t: "loadout", slots: ["", "", ""], ready: true }), settle: () => new Promise((r) => setTimeout(r, 60)) };
}

/** Two players through the queue into one ranked room, both seated and ready. */
async function rankedPair(a: Player, b: Player) {
  const qa = await ranked(a);
  const qb = await ranked(b);
  expect(qb.json.paired).toBe(true);
  const room = qa.json.room as string;
  const A = await join(a, room);
  const B = await join(b, room);
  await A.until((m) => m.t === "matched");
  await B.until((m) => m.t === "matched");
  A.ready();
  B.ready();
  const sa = await A.until((m) => m.t === "start");
  expect(sa.ranked).toBe(true);
  await B.until((m) => m.t === "start");
  return { room, A, B };
}

beforeEach(async () => {
  vi.useRealTimers();
  resetMemoryLimits();
  resetBoardCache();
  for (const p of known) await leave(p);
  resetMemoryLimits();
});
afterEach(() => vi.useRealTimers());

describe("the ranked queue", () => {
  it("pairs two close players at once, on a court both own", async () => {
    const a = await register();
    const b = await register();
    const qa = await ranked(a);
    expect(qa.status).toBe(200);
    expect(qa.json).toMatchObject({ host: true, paired: false, waited: 0 });
    expect(qa.json.room).toMatch(/^[0-9a-f-]{36}$/);
    expect(await ratingRow(a)).toMatchObject({ games: 0, tier: "rookie", division: 2 }); // the row is made on the first call
    const qb = await ranked(b);
    expect(qb.json).toEqual({ room: qa.json.room, host: false, paired: true, area: "cage", opponent: { playerId: a.playerId, level: 1, tier: "rookie", division: 2 } });
    const again = await ranked(a); // the host learns on its next poll
    expect(again.json).toEqual({ room: qa.json.room, host: true, paired: true, area: "cage", opponent: { playerId: b.playerId, level: 1, tier: "rookie", division: 2 } });
    const row = await env.DB.prepare("SELECT * FROM ranked_rooms WHERE room = ?1").bind(qa.json.room).first<any>();
    expect(row).toMatchObject({ area: "cage", a_id: a.playerId, b_id: b.playerId });
    // Both are out of the queue: a third waits alone, and a's next poll is a fresh room.
    const c = await register();
    expect((await ranked(c)).json.paired).toBe(false);
    const fresh = await ranked(a);
    expect(fresh.json.paired).toBe(true); // c was waiting
    expect(fresh.json.room).not.toBe(qa.json.room);
  });
  it("picks a court both own", async () => {
    const a = await register(5); // every court
    const b = await register(3); // cage + beach
    await ranked(a);
    const qb = await ranked(b);
    expect(qb.json.paired).toBe(true);
    expect(["cage", "beach"]).toContain(qb.json.area);
    expect(qb.json.opponent.level).toBe(5);
  });
  it("a far pair waits for the window to widen", async () => {
    const a = await register();
    const b = await register();
    await setRating(a, 1700, 100); // cons 1500
    await setRating(b, 1500, 100); // cons 1300: 200 apart, the window opens at window0
    expect(QUEUE.window0).toBeLessThan(200);
    const qa = await ranked(a);
    expect(qa.json.paired).toBe(false);
    expect((await ranked(b)).json.paired).toBe(false);
    advance(3 * QUEUE.step_s * 1000); // window0 + 3·step ≥ 200
    expect(QUEUE.window0 + 3 * QUEUE.step).toBeGreaterThanOrEqual(200);
    const qb = await ranked(b);
    expect(qb.json).toMatchObject({ room: qa.json.room, host: false, paired: true });
    expect((await ranked(a)).json).toMatchObject({ room: qa.json.room, host: true, paired: true, opponent: { playerId: b.playerId, tier: "allstar", division: 3 } });
  });
  it("after cap_s anyone on a common court will do", async () => {
    const a = await register();
    const b = await register();
    await setRating(a, 2100, 50); // cons 2000
    await setRating(b, 1100, 50); // cons 1000: never inside any window
    const qa = await ranked(a);
    expect((await ranked(b)).json.paired).toBe(false);
    advance((QUEUE.cap_s - 1) * 1000);
    expect((await ranked(b)).json.paired).toBe(false);
    advance(1000);
    const qb = await ranked(b);
    expect(qb.json).toMatchObject({ room: qa.json.room, paired: true, host: false });
    expect(qb.json.opponent.tier).toBe(LEGEND);
  });
  it("never pairs without a common court", async () => {
    // Straight at the Lobby: the Worker always sends the cage, so only here can courts be disjoint.
    const stub = env.LOBBY.get(env.LOBBY.idFromName("lobby"));
    const ask = async (playerId: string, areas: string[]) => {
      const res = await stub.fetch("https://lobby/ranked", { method: "POST", body: JSON.stringify({ playerId, level: 5, mu: 1500, rd: 350, cons: 800, tier: "rookie", division: 2, areas, lean: false }) });
      return (await res.json()) as any;
    };
    const x = uuid();
    const y = uuid();
    expect((await ask(x, ["beach"])).paired).toBe(false);
    expect((await ask(y, ["park"])).paired).toBe(false);
    advance((QUEUE.cap_s + 1) * 1000);
    expect((await ask(y, ["park"])).paired).toBe(false);
    expect((await ask(x, ["beach"])).paired).toBe(false);
    expect((await ask(uuid(), ["park", "city"])).paired).toBe(true); // a common court pairs at once (y waited past the cap)
    for (const id of [x, y]) await stub.fetch("https://lobby/leave", { method: "POST", body: JSON.stringify({ playerId: id, ranked: true }) });
  });
  it("leave removes the entry", async () => {
    const a = await register();
    const b = await register();
    await ranked(a);
    expect((await leave(a)).status).toBe(200);
    expect((await ranked(b)).json).toMatchObject({ host: true, paired: false });
  });
  it("drops a stale entry", async () => {
    const a = await register();
    const b = await register();
    const qa = await ranked(a);
    advance((QUEUE.ttl_s + 1) * 1000);
    expect((await ranked(b)).json).toMatchObject({ host: true, paired: false }); // a's entry is gone
    const qa2 = await ranked(a); // a comes back: a fresh place in line, and b is right there
    expect(qa2.json.paired).toBe(true);
    expect(qa2.json.room).not.toBe(qa.json.room);
  });
  it("a leaning player searches lower", async () => {
    const below = QUEUE.lean.below;
    // Without the lean: 150 apart, outside the opening window.
    const c = await register();
    const d = await register();
    await setRating(d, 1250, 50); // cons 1150
    await setRating(c, 1400, 50); // cons 1300
    await ranked(d);
    expect((await ranked(c)).json.paired).toBe(false);
    await leave(c);
    await leave(d);
    // On a losing streak: c searches as if `below` lower, 50 from d.
    const a = await register();
    const b = await register();
    await setRating(b, 1250, 50);
    await setRating(a, 1400, 50, { loss_streak: QUEUE.lean.losses, games: 3, losses: 3 });
    expect(1300 - below - 1150).toBeLessThanOrEqual(QUEUE.window0);
    await ranked(b);
    expect((await ranked(a)).json.paired).toBe(true);
    // Long away does the same.
    const e = await register();
    const f = await register();
    await setRating(f, 1250, 50);
    await setRating(e, 1400, 50, { games: 1, wins: 1, updated_at: Date.now() - (QUEUE.lean.away_days + 1) * 86_400_000 });
    await ranked(f);
    expect((await ranked(e)).json.paired).toBe(true);
  });
  it("has a kill switch", async () => {
    const a = await register();
    const offEnv = { ...env, FEATURE_RANKED: "off" };
    expect((await app.request("/v1/match/ranked", { method: "POST", headers: auth(a), body: "{}" }, offEnv)).status).toBe(503);
    expect((await app.request("/v1/ranked/board", { headers: auth(a) }, offEnv)).status).toBe(503);
    expect((await app.request("/v1/match/quick", { method: "POST", headers: auth(a), body: JSON.stringify({ area: "cage" }) }, offEnv)).status).toBe(200); // casual stays up
    await leave(a);
    await SELF.fetch("https://api/v1/match/leave", { method: "POST", headers: auth(a), body: JSON.stringify({ area: "cage" }) });
  });
});

describe("the board and me", () => {
  it("orders by cons, knows my position, and caches the rows", async () => {
    const a = await register();
    const b = await register();
    const c = await register();
    await setRating(a, 2900, 30, { games: 10, wins: 9, losses: 1 });
    await setRating(b, 2800, 30);
    await setRating(c, 2700, 30);
    const first = await board(a);
    expect(first.status).toBe(200);
    expect(first.json.rows.slice(0, 3)).toEqual([
      { position: 1, playerId: a.playerId, name: a.name, tag: a.tag, tier: LEGEND, division: 1, games: 10, wins: 9, losses: 1 },
      { position: 2, playerId: b.playerId, name: b.name, tag: b.tag, tier: LEGEND, division: 1, games: 0, wins: 0, losses: 0 },
      { position: 3, playerId: c.playerId, name: c.name, tag: c.tag, tier: LEGEND, division: 1, games: 0, wins: 0, losses: 0 },
    ]);
    expect(first.json.me).toEqual({ position: 1, tier: LEGEND, division: 1, mu: 2900, rd: 30, cons: 2840, games: 10, wins: 9, losses: 1, peak: { tier: LEGEND, division: 1 } });
    expect((await board(c)).json.me.position).toBe(3);
    // A newcomer on top does not show until the cache turns over; `me` is always live.
    const d = await register();
    await setRating(d, 3000, 30);
    const cached = await board(a);
    expect(cached.json.rows[0].playerId).toBe(a.playerId);
    expect(cached.json.me.position).toBe(2);
    resetBoardCache();
    expect((await board(a)).json.rows[0].playerId).toBe(d.playerId);
    // Nobody rated: me is null.
    const e = await register();
    expect((await board(e)).json.me).toBeNull();
  });
  it("/v1/me carries the rank line", async () => {
    const a = await register();
    expect((await me(a)).rank).toBeNull();
    await ranked(a);
    expect((await me(a)).rank).toEqual({ tier: "rookie", division: 2, games: 0, wins: 0, losses: 0, cons: 800 });
    await setRating(a, 3950, 30, { games: 4, wins: 4 }); // above anyone this file rated
    expect((await me(a)).rank).toEqual({ tier: LEGEND, division: 1, games: 4, wins: 4, losses: 0, cons: 3890, position: 1 });
  });
});

describe("ranked rooms", () => {
  it("moves both ratings at the decision and tells each phone", async () => {
    const a = await register();
    const b = await register();
    const qa = await ranked(a);
    expect((await ranked(b)).json.paired).toBe(true);
    const room = qa.json.room as string;
    const A = await join(a, room, "beach"); // the client's court is ignored: the row says cage
    expect(await A.until((m) => m.t === "joined")).toMatchObject({ area: "cage", ranked: true });
    const B = await join(b, room);
    const ma = await A.until((m) => m.t === "matched");
    expect(ma).toMatchObject({ ranked: true, cap: 1, tiers: { a: { tier: "rookie", division: 2 }, b: { tier: "rookie", division: 2 } } });
    await B.until((m) => m.t === "matched");
    A.ready();
    B.ready();
    expect(await A.until((m) => m.t === "start")).toMatchObject({ ranked: true, area: "cage", cap: 1 });
    await B.until((m) => m.t === "start");
    A.send({ t: "period_end", period: 0, score: 12, totals: {} });
    B.send({ t: "period_end", period: 0, score: 9, totals: {} });
    const sa = await A.until((m) => m.t === "settled");
    const sb = await B.until((m) => m.t === "settled");
    expect(sa).toMatchObject({ won: true, reason: "played", ranked: true, rating: { before: { mu: 1500, rd: 350, cons: 800 } }, peak: {} });
    expect(sa.rating.after.mu).toBeGreaterThan(1500);
    expect(sa.rating.delta).toBeCloseTo(sa.rating.after.mu - 1500, 9);
    expect(sa.rating.after.cons).toBeGreaterThan(800);
    expect(sa.events).toContain("promoted"); // a first win over an equal lifts a new player out of ROOKIE II
    expect(sa.rank).toEqual({ tier: sa.rank.tier, division: sa.rank.division });
    expect(sb).toMatchObject({ won: false, reason: "played", ranked: true });
    expect(sb.rating.after.mu).toBeLessThan(1500);
    expect(sb.rating.after.cons).toBeLessThan(800);
    expect(Array.isArray(sb.events)).toBe(true);
    const ra = await ratingRow(a);
    const rb = await ratingRow(b);
    expect(ra).toMatchObject({ games: 1, wins: 1, losses: 0, win_streak: 1, tier: sa.rank.tier, division: sa.rank.division, mu: sa.rating.after.mu });
    expect(rb).toMatchObject({ games: 1, wins: 0, losses: 1, loss_streak: 1, mu: sb.rating.after.mu });
    expect(ra!.cons).toBeGreaterThan(rb!.cons);
    const row = await env.DB.prepare("SELECT * FROM matches WHERE room = ?1").bind(env.ROOM.idFromName(room).toString()).first<any>();
    expect(row).toMatchObject({ area: "cage", ranked: 1, winner: "a", a_level: 1, b_level: 1, cap: 1, a_mu_before: 1500, b_mu_before: 1500, a_mu_after: ra!.mu, b_mu_after: rb!.mu, reason: "played" });
  });
  it("a forfeit is a loss for the leaver", async () => {
    const a = await register();
    const b = await register();
    const { A, B } = await rankedPair(a, b);
    A.send({ t: "period_end", period: 0, score: 5, totals: {} });
    await B.until((m) => m.t === "period_end");
    A.ws.close(1000, "bye"); // reported, then gone: a tie with nobody to play overtime
    await new Promise((r) => setTimeout(r, 80));
    B.send({ t: "period_end", period: 0, score: 5, totals: {} });
    const sb = await B.until((m) => m.t === "settled");
    expect(sb).toMatchObject({ won: true, reason: "forfeit", ranked: true });
    expect(sb.rating.after.mu).toBeGreaterThan(1500);
    expect(await ratingRow(a)).toMatchObject({ games: 1, losses: 1, loss_streak: 1 });
    expect(await ratingRow(b)).toMatchObject({ games: 1, wins: 1, win_streak: 1 });
    const row = await env.DB.prepare("SELECT ranked, winner, reason FROM matches WHERE a_id = ?1").bind(a.playerId).first<any>();
    expect(row).toEqual({ ranked: 1, winner: "b", reason: "forfeit" });
  });
  it("a void changes neither row", async () => {
    const a = await register();
    const b = await register();
    const { room, A, B } = await rankedPair(a, b);
    B.ws.close(1000, "bye"); // seconds in: void
    await new Promise((r) => setTimeout(r, 80));
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(Date.now() + DROP_GRACE_MS + 1); // the grace to come back runs out
    expect(await runDurableObjectAlarm(env.ROOM.get(env.ROOM.idFromName(room)))).toBe(true);
    const sa = await A.until((m) => m.t === "settled");
    expect(sa).toEqual({ t: "settled", won: false, reason: "void", ranked: true });
    expect(await ratingRow(a)).toMatchObject({ games: 0, mu: 1500 });
    expect(await ratingRow(b)).toMatchObject({ games: 0, mu: 1500 });
    const row = await env.DB.prepare("SELECT ranked, winner, reason, a_mu_before FROM matches WHERE a_id = ?1").bind(a.playerId).first<any>();
    expect(row).toEqual({ ranked: 1, winner: null, reason: "void", a_mu_before: null });
  });
  it("a casual room settles without a rating, and the headers can't be spoofed", async () => {
    const a = await register();
    const b = await register();
    const room = uuid();
    const A = await join(a, room, "beach", { "x-ranked": "1", "x-player-tier": LEGEND, "x-player-division": "1", "x-player-level": "50" });
    expect(await A.until((m) => m.t === "joined")).toMatchObject({ area: "beach", ranked: false });
    const B = await join(b, room, "beach");
    const ma = await A.until((m) => m.t === "matched");
    expect(ma).toMatchObject({ ranked: false, cap: 1, levels: { a: 1, b: 1 }, tiers: { a: { tier: "rookie", division: 2 } } });
    await B.until((m) => m.t === "matched");
    A.ready();
    B.ready();
    expect(await A.until((m) => m.t === "start")).toMatchObject({ ranked: false });
    await B.until((m) => m.t === "start");
    A.send({ t: "period_end", period: 0, score: 3, totals: {} });
    B.send({ t: "period_end", period: 0, score: 7, totals: {} });
    expect(await A.until((m) => m.t === "settled")).toEqual({ t: "settled", won: false, reason: "played", ranked: false });
    expect(await B.until((m) => m.t === "settled")).toEqual({ t: "settled", won: true, reason: "played", ranked: false });
    expect(await ratingRow(a)).toBeNull();
    const row = await env.DB.prepare("SELECT * FROM matches WHERE a_id = ?1").bind(a.playerId).first<any>();
    expect(row).toMatchObject({ area: "beach", ranked: 0, winner: "b", a_level: 1, b_level: 1, cap: 1, a_mu_before: null, b_mu_after: null });
  });
  it("only the paired two may enter a ranked room", async () => {
    const a = await register();
    const b = await register();
    const c = await register();
    const qa = await ranked(a);
    expect((await ranked(b)).json.paired).toBe(true);
    const res = await SELF.fetch(`https://api/v1/match/room/${qa.json.room}?area=cage`, { headers: { ...auth(c), upgrade: "websocket" } });
    expect(res.status).toBe(403);
  });
});
