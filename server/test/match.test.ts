import { SELF, env, runDurableObjectAlarm } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { resetMemoryLimits } from "../src/limits";
import { MAX_PER_S } from "../src/match_room";

const uuid = () => crypto.randomUUID();
const secret = () => [...crypto.getRandomValues(new Uint8Array(40))].map((b) => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[b % 62]).join("");
let ipCounter = 90_000;
const freshIp = () => `10.${Math.floor(ipCounter / 65536) % 256}.${Math.floor(ipCounter / 256) % 256}.${ipCounter++ % 256}`;

interface Player { playerId: string; secret: string; ip: string; name: string; tag: string }

async function register(): Promise<Player> {
  const p = { playerId: uuid(), secret: secret(), ip: freshIp() };
  const res = await SELF.fetch("https://api/v1/register", {
    method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": p.ip },
    body: JSON.stringify({ playerId: p.playerId, secret: p.secret, clientId: uuid() }),
  });
  expect(res.status).toBe(200);
  const j = (await res.json()) as { name: string; tag: string };
  return { ...p, name: j.name, tag: j.tag };
}

const auth = (p: Player) => ({ authorization: `Bearer ${p.playerId}.${p.secret}`, "cf-connecting-ip": p.ip, "content-type": "application/json" });

async function lobby(p: Player, action: string, body: Record<string, unknown> = { area: "cage" }) {
  const res = await SELF.fetch(`https://api/v1/match/${action}`, { method: "POST", headers: auth(p), body: JSON.stringify(body) });
  return { status: res.status, json: (await res.json()) as any };
}

/** Open the room socket and collect its messages as they come. */
async function join(p: Player, room: string, area = "cage") {
  const res = await SELF.fetch(`https://api/v1/match/room/${room}?area=${area}`, { headers: { ...auth(p), upgrade: "websocket" } });
  expect(res.status).toBe(101);
  const ws = res.webSocket!;
  const inbox: any[] = [];
  const closes: { code: number; reason: string }[] = [];
  ws.accept();
  ws.addEventListener("message", (e) => inbox.push(JSON.parse(String(e.data))));
  ws.addEventListener("close", (e) => closes.push({ code: e.code, reason: e.reason }));
  const until = async (pred: (m: any) => boolean, ms = 2000) => {
    const t0 = Date.now();
    while (Date.now() - t0 < ms) {
      const hit = inbox.find(pred);
      if (hit) return hit;
      await new Promise((r) => setTimeout(r, 10));
    }
    throw new Error("timeout waiting for " + pred.toString() + " inbox=" + JSON.stringify(inbox));
  };
  const settle = () => new Promise((r) => setTimeout(r, 50));
  return { ws, inbox, closes, until, settle, send: (m: unknown) => ws.send(JSON.stringify(m)) };
}

beforeEach(() => resetMemoryLimits());

describe("lobby", () => {
  it("pairs the next two quick-match players in an area into one room", async () => {
    const a = await register();
    const b = await register();
    const c = await register();
    const qa = await lobby(a, "quick", { area: "beach" });
    expect(qa.status).toBe(200);
    expect(qa.json.host).toBe(true);
    const again = await lobby(a, "quick", { area: "beach" });
    expect(again.json.room).toBe(qa.json.room); // asking twice keeps your place
    const qc = await lobby(c, "quick", { area: "city" }); // another area, another queue
    expect(qc.json.room).not.toBe(qa.json.room);
    const qb = await lobby(b, "quick", { area: "beach" });
    expect(qb.json).toEqual({ room: qa.json.room, host: false });
    const next = await lobby(a, "quick", { area: "beach" }); // the queue is empty again
    expect(next.json.host).toBe(true);
    expect(next.json.room).not.toBe(qa.json.room);
    await lobby(a, "leave", { area: "beach" });
    const after = await lobby(b, "quick", { area: "beach" });
    expect(after.json.host).toBe(true); // a left, so b waits
  });
  it("makes and joins codes", async () => {
    const a = await register();
    const b = await register();
    const made = await lobby(a, "code", { area: "city" });
    expect(made.status).toBe(200);
    expect(made.json.code).toMatch(/^[A-Z2-9]{5}$/);
    const own = await lobby(a, "join", { area: "city", code: made.json.code });
    expect(own.status).toBe(400);
    const joined = await lobby(b, "join", { area: "city", code: made.json.code.toLowerCase() });
    expect(joined.status).toBe(200);
    expect(joined.json).toEqual({ room: made.json.room, area: "city" });
    expect((await lobby(b, "join", { area: "city", code: made.json.code })).status).toBe(404); // one use
    expect((await lobby(b, "join", { area: "city", code: "ZZZZZ" })).status).toBe(404);
    expect((await lobby(b, "quick", { area: "moon" })).status).toBe(400);
    expect((await lobby(b, "join", { area: "cage" })).status).toBe(400); // no code
  });
});

describe("match room", () => {
  it("seats two phones, starts them on one seed, relays shots, records the result", async () => {
    const a = await register();
    const b = await register();
    const room = uuid();
    const A = await join(a, room, "beach");
    const ja = await A.until((m) => m.t === "joined");
    expect(ja).toMatchObject({ side: "a", area: "beach", peer: null, status: "waiting" });
    const B = await join(b, room, "beach");
    const jb = await B.until((m) => m.t === "joined");
    expect(jb.side).toBe("b");
    expect(jb.peer).toMatchObject({ id: a.playerId, name: a.name, tag: a.tag });
    const peer = await A.until((m) => m.t === "peer");
    expect(peer.peer.id).toBe(b.playerId);
    const sa = await A.until((m) => m.t === "start");
    const sb = await B.until((m) => m.t === "start");
    expect(sa.seed).toBe(sb.seed);
    expect(sa).toMatchObject({ area: "beach", seconds: 90, ot_seconds: 20, ball_return_s: 1 });
    // A shot from a reaches b, tagged with its side, and not a itself.
    A.send({ t: "shot", n: 1, launch: { angle_deg: 50.5, speed: 7.2 } });
    const shot = await B.until((m) => m.t === "shot");
    expect(shot).toMatchObject({ from: "a", n: 1, launch: { angle_deg: 50.5, speed: 7.2 } });
    await A.settle();
    expect(A.inbox.filter((m) => m.t === "shot")).toHaveLength(0);
    B.send({ t: "outcome", n: 1, score: 2 });
    expect((await A.until((m) => m.t === "outcome")).score).toBe(2);
    // Ping / pong and an unknown message.
    A.send({ t: "ping" });
    await A.until((m) => m.t === "pong");
    A.send({ t: "dance" });
    expect((await A.until((m) => m.t === "error")).code).toBe("unknown");
    // Both periods reported, scores differ → recorded.
    A.send({ t: "period_end", period: 0, score: 12, totals: { score: 12, makes: 8 } });
    expect((await B.until((m) => m.t === "period_end")).from).toBe("a");
    B.send({ t: "period_end", period: 0, score: 9, totals: { score: 9, makes: 7 } });
    await A.until((m) => m.t === "period_end");
    await A.settle();
    const row = await env.DB.prepare("SELECT * FROM matches WHERE a_id = ?1").bind(a.playerId).first<any>();
    expect(row).toMatchObject({ area: "beach", b_id: b.playerId, a_score: 12, b_score: 9, ot: 0, reason: "played" });
    // Afterwards the room is done: another message is refused.
    A.send({ t: "shot", n: 2, launch: { angle_deg: 50, speed: 7 } });
    expect((await A.until((m) => m.t === "error" && m.code === "not_playing")).code).toBe("not_playing");
  });
  it("a tie keeps the room open for overtime", async () => {
    const a = await register();
    const b = await register();
    const room = uuid();
    const A = await join(a, room);
    const B = await join(b, room);
    await A.until((m) => m.t === "start");
    A.send({ t: "period_end", period: 0, score: 5, totals: {} });
    B.send({ t: "period_end", period: 0, score: 5, totals: {} });
    await A.until((m) => m.t === "period_end");
    await A.settle();
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM matches WHERE a_id = ?1").bind(a.playerId).first<{ n: number }>()).toEqual({ n: 0 });
    A.send({ t: "period_end", period: 1, score: 7, totals: {} });
    B.send({ t: "period_end", period: 1, score: 6, totals: {} });
    await B.until((m) => m.t === "period_end" && m.period === 1);
    await A.settle();
    const row = await env.DB.prepare("SELECT * FROM matches WHERE a_id = ?1").bind(a.playerId).first<any>();
    expect(row).toMatchObject({ a_score: 7, b_score: 6, ot: 1 });
  });
  it("refuses a third phone and a bad room id", async () => {
    const a = await register();
    const b = await register();
    const c = await register();
    const room = uuid();
    await join(a, room);
    await join(b, room);
    const res = await SELF.fetch(`https://api/v1/match/room/${room}?area=cage`, { headers: { ...auth(c), upgrade: "websocket" } });
    expect(res.status).toBe(409);
    expect((await SELF.fetch("https://api/v1/match/room/not-a-room", { headers: { ...auth(c), upgrade: "websocket" } })).status).toBe(400);
    expect((await SELF.fetch(`https://api/v1/match/room/${room}`, { headers: auth(c) })).status).toBe(426);
    expect((await SELF.fetch(`https://api/v1/match/room/${room}`, { headers: { upgrade: "websocket", "cf-connecting-ip": freshIp() } })).status).toBe(401);
  });
  it("tells the other phone when one leaves, and records a forfeit or a void", async () => {
    const a = await register();
    const b = await register();
    const room = uuid();
    const A = await join(a, room);
    const B = await join(b, room);
    await A.until((m) => m.t === "start");
    A.send({ t: "outcome", n: 1, score: 3 });
    await B.until((m) => m.t === "outcome");
    B.ws.close(1000, "bye"); // gone before any report
    const left = await A.until((m) => m.t === "peer_left");
    expect(left.side).toBe("b");
    await A.settle();
    const row = await env.DB.prepare("SELECT * FROM matches WHERE a_id = ?1").bind(a.playerId).first<any>();
    expect(row).toMatchObject({ reason: "void", a_score: 0, b_score: 0 }); // seconds in → void
  });
  it("a phone that reported its buzzer and then left is finished, not a forfeit", async () => {
    const a = await register();
    const b = await register();
    const room = uuid();
    const A = await join(a, room);
    const B = await join(b, room);
    await A.until((m) => m.t === "start");
    A.send({ t: "period_end", period: 0, score: 12, totals: {} });
    await B.until((m) => m.t === "period_end");
    A.ws.close(1000, "bye"); // the winner's phone goes home
    await new Promise((r) => setTimeout(r, 80));
    expect(B.inbox.filter((m) => m.t === "peer_left")).toHaveLength(0); // no false forfeit
    B.send({ t: "period_end", period: 0, score: 9, totals: {} });
    const settled = await B.until((m) => m.t === "settled");
    expect(settled).toMatchObject({ won: false, reason: "played" });
    const row = await env.DB.prepare("SELECT * FROM matches WHERE a_id = ?1").bind(a.playerId).first<any>();
    expect(row).toMatchObject({ a_score: 12, b_score: 9, reason: "played" });
    // A tie with the reporter gone: no overtime to play, the stayer takes it.
    const c = await register();
    const d = await register();
    const room2 = uuid();
    const C = await join(c, room2);
    const D = await join(d, room2);
    await C.until((m) => m.t === "start");
    C.send({ t: "period_end", period: 0, score: 5, totals: {} });
    await D.until((m) => m.t === "period_end");
    C.ws.close(1000, "bye");
    await new Promise((r) => setTimeout(r, 80));
    D.send({ t: "period_end", period: 0, score: 5, totals: {} });
    expect(await D.until((m) => m.t === "settled")).toMatchObject({ won: true, reason: "forfeit" });
  });
  it("closes a room nobody joined when the alarm fires", async () => {
    const a = await register();
    const room = uuid();
    const A = await join(a, room);
    await A.until((m) => m.t === "joined");
    const id = env.ROOM.idFromName(room);
    const ran = await runDurableObjectAlarm(env.ROOM.get(id));
    expect(ran).toBe(true);
    await A.until((m) => m.t === "expired");
    await A.settle();
    expect(A.closes.length).toBe(1);
  });
  it("closes a phone that floods", async () => {
    const a = await register();
    const b = await register();
    const room = uuid();
    const A = await join(a, room);
    await join(b, room);
    await A.until((m) => m.t === "start");
    for (let i = 0; i <= MAX_PER_S; i++) A.send({ t: "ping" });
    await new Promise((r) => setTimeout(r, 100));
    expect(A.closes).toEqual([{ code: 1008, reason: "too fast" }]);
    // The flood ended that match (a dropped phone forfeits); a fresh pair for the size cap.
    const room2 = uuid();
    const C = await join(a, room2);
    await join(b, room2);
    await C.until((m) => m.t === "start");
    C.send(JSON.stringify({ t: "ping", pad: "x".repeat(3000) }));
    await new Promise((r) => setTimeout(r, 100));
    expect(C.closes).toEqual([{ code: 1008, reason: "too big" }]);
  });
  it("throttles lobby calls", async () => {
    const a = await register();
    for (let i = 0; i < 20; i++) expect((await lobby(a, "leave")).status).toBe(200);
    expect((await lobby(a, "leave")).status).toBe(429);
  });
});
