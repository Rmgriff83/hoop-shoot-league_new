/**
 * What a match costs (docs/BACKEND.md → What a match costs, 2026-11-04): a
 * whole ranked match through the Lobby and a MatchRoom with the meter on —
 * Durable Object storage rows (`put` / `deleteAll` / `setAlarm`) and D1 write
 * statements — pinned so a later change cannot quietly bring back the
 * per-message write. Plus what the discipline must not break: hibernation
 * between messages, the idle rule, a mid-match drop, a card's ledger row.
 */
import { SELF, env, evictDurableObject, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { resetMemoryLimits } from "../src/limits";
import { CLOSE_AFTER_MS, DROP_GRACE_MS, IDLE_MS, LIFETIME_MS } from "../src/match_room";
import { readMeter, resetMeter } from "../src/meter";

const uuid = () => crypto.randomUUID();
const secret = () => [...crypto.getRandomValues(new Uint8Array(40))].map((b) => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[b % 62]).join("");
let ipCounter = 120_000;
const freshIp = () => `10.${Math.floor(ipCounter / 65536) % 256}.${Math.floor(ipCounter / 256) % 256}.${ipCounter++ % 256}`;

interface Player { playerId: string; secret: string; ip: string }

async function register(level = 1): Promise<Player> {
  const p = { playerId: uuid(), secret: secret(), ip: freshIp() };
  const res = await SELF.fetch("https://api/v1/register", {
    method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": p.ip },
    body: JSON.stringify({ playerId: p.playerId, secret: p.secret, clientId: uuid() }),
  });
  expect(res.status).toBe(200);
  if (level > 1) await env.DB.prepare("UPDATE players SET level = ?1 WHERE id = ?2").bind(level, p.playerId).run();
  return p;
}
const auth = (p: Player) => ({ authorization: `Bearer ${p.playerId}.${p.secret}`, "cf-connecting-ip": p.ip, "content-type": "application/json" });
const give = (p: Player, cardId: string, n: number) => env.DB.prepare("INSERT INTO online_cards (player_id, card_id, n) VALUES (?1, ?2, ?3) ON CONFLICT(player_id, card_id) DO UPDATE SET n = ?3").bind(p.playerId, cardId, n).run();

async function call(p: Player, action: string, body: Record<string, unknown> = {}) {
  const res = await SELF.fetch(`https://api/v1/match/${action}`, { method: "POST", headers: auth(p), body: JSON.stringify(body) });
  return { status: res.status, json: (await res.json()) as any };
}
const ranked = (p: Player) => call(p, "ranked");
/** The D1 day counter as it stands for a player (0 = no row yet). */
const dayCount = async (p: Player) => (await env.DB.prepare("SELECT n FROM rl WHERE key = ?1").bind(`match:day:${p.playerId}`).first<{ n: number }>())?.n ?? 0;
const stubOf = (room: string) => env.ROOM.get(env.ROOM.idFromName(room));
const metaOf = (room: string) => runInDurableObject(stubOf(room), (_i: unknown, state: DurableObjectState) => state.storage.get<any>("meta"));

/** Into the room; the pre-match pick answers with `slots`, ready at once. Timeouts run on the real clock (Date may be frozen). */
async function join(p: Player, room: string, slots = ",,", area = "cage") {
  const res = await SELF.fetch(`https://api/v1/match/room/${room}?area=${area}`, { headers: { ...auth(p), upgrade: "websocket" } });
  expect(res.status).toBe(101);
  const ws = res.webSocket!;
  const inbox: any[] = [];
  const closes: { code: number; reason: string }[] = [];
  ws.accept();
  ws.addEventListener("message", (e) => {
    const m = JSON.parse(String(e.data));
    inbox.push(m);
    if (m.t === "matched") ws.send(JSON.stringify({ t: "loadout", slots: slots.split(",").slice(0, 3), ready: true }));
  });
  ws.addEventListener("close", (e) => { closes.push({ code: e.code, reason: e.reason }); });
  const until = async (pred: (m: any) => boolean, ms = 3000) => {
    const t0 = performance.now();
    while (performance.now() - t0 < ms) {
      const hit = inbox.find(pred);
      if (hit) return hit;
      await new Promise((r) => setTimeout(r, 10));
    }
    throw new Error("timeout waiting for " + pred.toString() + " inbox=" + JSON.stringify(inbox.slice(-6)));
  };
  return { ws, inbox, closes, until, send: (m: unknown) => ws.send(JSON.stringify(m)), settle: () => new Promise((r) => setTimeout(r, 80)) };
}

/** Freeze Date at the real now (the sockets, timeouts and the room's alarms stay on the real clock); `tick` moves it on. */
function freeze() {
  vi.useFakeTimers({ toFake: ["Date"] });
}
const tick = (ms: number) => vi.setSystemTime(Date.now() + ms);

/** Two phones seated and tipped off in a casual room. */
async function casual(slotsA = ",,", slotsB = ",,") {
  const a = await register();
  const b = await register();
  const room = uuid();
  const A = await join(a, room, slotsA);
  const B = await join(b, room, slotsB);
  await A.until((m) => m.t === "start");
  await B.until((m) => m.t === "start");
  return { a, b, room, A, B };
}

beforeEach(() => {
  vi.useRealTimers();
  resetMemoryLimits();
  resetMeter();
});
afterEach(() => vi.useRealTimers());

describe("what a match costs", () => {
  it("a full ranked match: ≤ 12 room rows, alarms apart; D1 only where something starts or settles", async () => {
    const a = await register(3);
    const b = await register(3);
    await give(a, "ice", 1);
    await give(b, "fire7", 1);
    resetMeter();
    freeze();
    // a searches alone: three 4 s polls, one queue entry.
    for (let i = 0; i < 3; i++) {
      expect((await ranked(a)).json).toMatchObject({ paired: false, host: true });
      tick(4000);
    }
    expect(await dayCount(a)).toBe(1);
    // b pairs at once; a learns on its next poll.
    expect((await ranked(b)).json.paired).toBe(true);
    const qa = await ranked(a);
    expect(qa.json.paired).toBe(true);
    expect(await dayCount(a)).toBe(1);
    expect(await dayCount(b)).toBe(1);
    const room: string = qa.json.room;
    const A = await join(a, room, "ice,,");
    const B = await join(b, room, "fire7,,");
    await A.until((m) => m.t === "start");
    await B.until((m) => m.t === "start");
    tick(4000); // the pick spent a token: a full bucket for the first burst
    // ~60 messages a side (30 shots, 30 outcomes), in bursts the bucket allows: a burst of 20 lands, then the clock steps 4 s.
    for (let n = 1; n <= 30; n++) {
      A.send({ t: "shot", n, launch: { angle_deg: 50, speed: 7 } });
      B.send({ t: "shot", n, launch: { angle_deg: 51, speed: 7.1 } });
      A.send({ t: "outcome", n, score: n % 3 === 0 ? 0 : 2 });
      B.send({ t: "outcome", n, score: n % 2 === 0 ? 0 : 2 });
      if (n % 10 === 0) {
        expect((await A.until((m) => m.t === "outcome" && m.n === n)).from).toBe("b");
        expect((await B.until((m) => m.t === "outcome" && m.n === n)).from).toBe("a");
        tick(4000);
      }
    }
    expect(A.inbox.filter((m) => m.t === "shot")).toHaveLength(30);
    expect(B.inbox.filter((m) => m.t === "shot")).toHaveLength(30);
    expect(A.closes).toEqual([]);
    expect(B.closes).toEqual([]);
    // One card each, with its ledger row.
    A.send({ t: "card", id: "ice" });
    B.send({ t: "card", id: "fire7" });
    await A.until((m) => m.t === "card_ok");
    await B.until((m) => m.t === "card_ok");
    tick(4000);
    // The buzzer: both report, a takes it.
    A.send({ t: "period_end", period: 0, score: 40, totals: { score: 40, makes: 20 } });
    B.send({ t: "period_end", period: 0, score: 30, totals: { score: 30, makes: 15 } });
    expect(await A.until((m) => m.t === "settled")).toMatchObject({ won: true, reason: "played", ranked: true });
    expect(await B.until((m) => m.t === "settled")).toMatchObject({ won: false, reason: "played", ranked: true });
    // A rematch offer, then the close alarm tears the room down.
    A.send({ t: "rematch" });
    expect((await B.until((m) => m.t === "rematch")).from).toBe("a");
    tick(CLOSE_AFTER_MS + 1);
    expect(await runDurableObjectAlarm(stubOf(room))).toBe(true);
    await A.settle();
    expect(await metaOf(room)).toBeUndefined();
    const cost = readMeter();
    console.log("cost per ranked match:", JSON.stringify(cost));
    // The room: seat ×2, loadout ×2, card ×2, period_end ×2, rematch ×1, teardown ×1 = 10 rows.
    expect(cost.doPut + cost.doDelete).toBeLessThanOrEqual(12);
    // Alarms: wait, pre-match, lifetime, close, the rematch's minute.
    expect(cost.doAlarm).toBeLessThanOrEqual(8);
    // D1: two first-time rating rows, two day counts, ranked_rooms, two card plays (×2), the decision batch.
    expect(cost.d1).toBeLessThanOrEqual(26);
    // Ground truth for the day budget: one count each — the polls, the upgrades and the room counted nothing.
    expect(await dayCount(a)).toBe(1);
    expect(await dayCount(b)).toBe(1);
    const row = await env.DB.prepare("SELECT a_score, b_score, reason, ranked, a_played, b_played FROM matches WHERE room = ?1").bind(env.ROOM.idFromName(room).toString()).first<any>();
    expect(row).toEqual({ a_score: 40, b_score: 30, reason: "played", ranked: 1, a_played: '["ice"]', b_played: '["fire7"]' });
  }, 20_000);

  it("hibernation between messages: the sockets and their activity come back, the idle rule reads them", async () => {
    const { room, A, B } = await casual();
    freeze();
    tick(100_000); // 100 s in: the stored stamp is the tip-off, a's shot is only in its attachment
    A.send({ t: "shot", n: 1, launch: { angle_deg: 50, speed: 7 } });
    await B.until((m) => m.t === "shot");
    const before = readMeter();
    await evictDurableObject(stubOf(room)); // hibernates the sockets, drops the instance
    tick(30_000); // 130 s after the tip-off: idle by the stored stamp alone, 30 s by the attachment
    expect(await runDurableObjectAlarm(stubOf(room))).toBe(true);
    await A.settle();
    expect(A.inbox.filter((m) => m.t === "expired")).toHaveLength(0);
    expect(A.closes).toEqual([]);
    B.send({ t: "shot", n: 1, launch: { angle_deg: 48, speed: 7 } });
    expect((await A.until((m) => m.t === "shot")).from).toBe("b");
    const after = readMeter();
    expect(after.doPut).toBe(before.doPut); // the shots and the alarm wrote no row
    tick(IDLE_MS + 1000); // nothing since b's shot: now it is idle
    expect(await runDurableObjectAlarm(stubOf(room))).toBe(true);
    await A.until((m) => m.t === "expired");
    await B.until((m) => m.t === "expired");
    expect(await metaOf(room)).toBeUndefined();
  }, 15_000);

  it("the idle timeout: a silent room voids on its alarm and writes no match", async () => {
    const { a, room, A, B } = await casual();
    const seated = readMeter();
    freeze();
    tick(LIFETIME_MS + 1);
    expect(await runDurableObjectAlarm(stubOf(room))).toBe(true);
    await A.until((m) => m.t === "expired");
    await B.until((m) => m.t === "expired");
    expect(await metaOf(room)).toBeUndefined();
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM matches WHERE a_id = ?1").bind(a.playerId).first<{ n: number }>()).toEqual({ n: 0 });
    const cost = readMeter();
    expect(cost.doPut).toBe(seated.doPut); // seat ×2 + loadout ×2 only
    expect(cost.doPut).toBeLessThanOrEqual(4);
    expect(cost.doDelete).toBe(1);
  });

  it("a mid-match drop: the grace, then a forfeit for the one who stayed — a handful of rows", async () => {
    const { a, room, A, B } = await casual();
    freeze();
    tick(40_000); // well past the 30 s that makes a drop a forfeit rather than a void
    A.send({ t: "outcome", n: 1, score: 2 });
    await B.until((m) => m.t === "outcome");
    B.ws.close(1000, "bye");
    await A.settle();
    expect(A.inbox.filter((m) => m.t === "peer_left")).toHaveLength(0);
    tick(DROP_GRACE_MS + 1);
    expect(await runDurableObjectAlarm(stubOf(room))).toBe(true);
    expect((await A.until((m) => m.t === "peer_left")).side).toBe("b");
    expect(await A.until((m) => m.t === "settled")).toMatchObject({ won: true, reason: "forfeit" });
    const row = await env.DB.prepare("SELECT reason, winner FROM matches WHERE a_id = ?1").bind(a.playerId).first<any>();
    expect(row).toEqual({ reason: "forfeit", winner: "a" });
    const cost = readMeter();
    expect(cost.doPut).toBeLessThanOrEqual(7); // seat ×2, loadout ×2, the drop, the forfeit
  });

  it("a card play is on disk with its ledger row before the room forgets anything", async () => {
    const a = await register(3);
    const b = await register(3);
    await give(a, "ice", 1);
    const room = uuid();
    const A = await join(a, room, "ice,,");
    const B = await join(b, room);
    await A.until((m) => m.t === "start");
    await B.until((m) => m.t === "start");
    freeze();
    tick(2000);
    A.send({ t: "card", id: "ice" });
    await A.until((m) => m.t === "card_ok");
    expect((await B.until((m) => m.t === "card")).id).toBe("ice");
    await evictDurableObject(stubOf(room));
    const m = await metaOf(room);
    expect(m.hands.a).toEqual(["", ""]);
    expect(m.played.a).toEqual(["ice"]);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM online_ledger WHERE player_id = ?1 AND kind = 'play' AND card_id = 'ice'").bind(a.playerId).first<{ n: number }>()).toEqual({ n: 1 });
    expect(await env.DB.prepare("SELECT n FROM online_cards WHERE player_id = ?1 AND card_id = 'ice'").bind(a.playerId).first<{ n: number }>()).toEqual({ n: 0 });
    // The evicted room still relays and still refuses a second copy.
    A.send({ t: "card", id: "ice" });
    expect((await A.until((m2) => m2.t === "error" && m2.code === "card")).id).toBe("ice");
  });
});

describe("the match day budget", () => {
  it("counts starts only: a fresh ranked search, quick, code, join — never a repeat poll, leave or a room", async () => {
    const a = await register();
    const b = await register();
    freeze();
    for (let i = 0; i < 5; i++) {
      expect((await ranked(a)).status).toBe(200);
      tick(4000);
    }
    expect(await dayCount(a)).toBe(1);
    expect((await call(a, "leave", { area: "any", ranked: true })).status).toBe(200);
    expect(await dayCount(a)).toBe(1);
    expect((await call(a, "quick", { area: "cage" })).status).toBe(200);
    expect(await dayCount(a)).toBe(2);
    expect((await call(a, "leave", { area: "cage" })).status).toBe(200);
    const code = await call(a, "code", { area: "cage" });
    expect(code.status).toBe(200);
    expect(await dayCount(a)).toBe(3);
    const joined = await call(b, "join", { area: "cage", code: code.json.code });
    expect(joined.status).toBe(200);
    expect(await dayCount(b)).toBe(1);
    const A = await join(a, joined.json.room);
    const B = await join(b, joined.json.room);
    await A.until((m) => m.t === "start");
    await B.until((m) => m.t === "start");
    expect(await dayCount(a)).toBe(3);
    expect(await dayCount(b)).toBe(1);
    // Leaving the queue again (ranked) after a search that ended: nothing.
    expect((await call(a, "leave", { area: "any", ranked: true })).status).toBe(200);
    expect(await dayCount(a)).toBe(3);
  });

  it("at the cap a start is refused before anything is queued; a repeat poll still answers", async () => {
    const a = await register();
    freeze();
    expect((await ranked(a)).json.paired).toBe(false); // in the queue, counted once
    await env.DB.prepare("UPDATE rl SET n = 200 WHERE key = ?1").bind(`match:day:${a.playerId}`).run();
    tick(4000);
    expect((await ranked(a)).status).toBe(200); // still searching: the poll is not a start
    expect((await call(a, "quick", { area: "cage" })).status).toBe(429);
    expect((await call(a, "code", { area: "cage" })).status).toBe(429);
    expect((await call(a, "leave", { area: "any", ranked: true })).status).toBe(200);
    const over = await dayCount(a); // (a refused start still counts, as every D1 counter does)
    const refused = await ranked(a); // a fresh search now: refused before anything is queued, with no row written
    expect(refused.status).toBe(429);
    expect(await dayCount(a)).toBe(over);
    const lobby = env.LOBBY.get(env.LOBBY.idFromName("lobby"));
    expect(await runInDurableObject(lobby, (_i: unknown, state: DurableObjectState) => state.storage.get(`rq:${a.playerId}`))).toBeUndefined();
    await env.DB.prepare("UPDATE rl SET n = 199 WHERE key = ?1").bind(`match:day:${a.playerId}`).run();
    expect((await ranked(a)).status).toBe(200); // the last start of the day
    expect(await dayCount(a)).toBe(200);
    tick(4000);
    expect((await ranked(a)).status).toBe(200); // and its polls carry on
  });
});
