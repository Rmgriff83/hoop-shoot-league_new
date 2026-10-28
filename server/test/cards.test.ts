import { SELF, env, runDurableObjectAlarm } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { resetMemoryLimits } from "../src/limits";
import { DROP_GRACE_MS } from "../src/match_room";
import { CARDS, validHand } from "../src/cards";

const uuid = () => crypto.randomUUID();
const secret = () => [...crypto.getRandomValues(new Uint8Array(40))].map((b) => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[b % 62]).join("");
let ipCounter = 130_000;
const freshIp = () => `10.${Math.floor(ipCounter / 65536) % 256}.${Math.floor(ipCounter / 256) % 256}.${ipCounter++ % 256}`;

interface Player { playerId: string; secret: string; ip: string }

/** A player at `level`: set straight in the row, since a fresh account is only believed up to level 2 (level_trust.ts). */
async function register(level = 1): Promise<Player> {
  const p = { playerId: uuid(), secret: secret(), ip: freshIp() };
  const res = await SELF.fetch("https://api/v1/register", {
    method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": p.ip },
    body: JSON.stringify({ playerId: p.playerId, secret: p.secret, clientId: uuid(), level }),
  });
  expect(res.status).toBe(200);
  if (level > 1) await env.DB.prepare("UPDATE players SET level = ?1 WHERE id = ?2").bind(level, p.playerId).run();
  return p;
}
const auth = (p: Player) => ({ authorization: `Bearer ${p.playerId}.${p.secret}`, "cf-connecting-ip": p.ip, "content-type": "application/json" });
/** Straight into the ledger: nothing on the server hands out cards yet (drops come later). */
const give = (p: Player, cardId: string, n: number) => env.DB.prepare("INSERT INTO online_cards (player_id, card_id, n) VALUES (?1, ?2, ?3) ON CONFLICT(player_id, card_id) DO UPDATE SET n = ?3").bind(p.playerId, cardId, n).run();
async function cards(p: Player) {
  const res = await SELF.fetch("https://api/v1/cards", { headers: auth(p) });
  return { status: res.status, json: (await res.json()) as any };
}
/** Into the room; the pre-match pick is answered with `slots`, ready at once. */
async function join(p: Player, room: string, slots = "") {
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
  const until = async (pred: (m: any) => boolean, ms = 2000) => {
    const t0 = Date.now();
    while (Date.now() - t0 < ms) {
      const hit = inbox.find(pred);
      if (hit) return hit;
      await new Promise((r) => setTimeout(r, 10));
    }
    throw new Error("timeout; inbox=" + JSON.stringify(inbox));
  };
  return { ws, inbox, until, send: (m: unknown) => ws.send(JSON.stringify(m)), settle: () => new Promise((r) => setTimeout(r, 60)) };
}

beforeEach(() => resetMemoryLimits());
afterEach(() => vi.useRealTimers());

/** The room allows MAX_PER_S messages a second and the loadout is one of them: step into the next second. */
const nextSecond = () => new Promise((r) => setTimeout(r, 1005 - (Date.now() % 1000)));

describe("the card list", () => {
  it("reads the cards and keeps a hand honest", () => {
    expect(Object.keys(CARDS).sort()).toEqual(["fire7", "ice", "magnet6"]);
    expect(CARDS.magnet6.level).toBe(5);
    const inv = { inventory: { ice: 1, fire7: 2 }, level: 3 };
    expect(validHand(["ice", "ice", "fire7"], inv)).toEqual(["ice", "", "fire7"]); // one ice owned
    expect(validHand(["magnet6", "fire7", "fire7"], inv)).toEqual(["", "fire7", "fire7"]); // level 5 card at level 3
    expect(validHand(["nope", "", "ice"], inv)).toEqual(["", "", "ice"]);
    expect(validHand([], inv)).toEqual(["", "", ""]);
  });
});

describe("the cards route", () => {
  it("reads an empty ledger and then what the ledger holds", async () => {
    const p = await register(3);
    expect((await cards(p)).json).toEqual({ inventory: {}, level: 3 });
    await give(p, "ice", 2);
    await give(p, "fire7", 1);
    expect((await cards(p)).json).toEqual({ inventory: { ice: 2, fire7: 1 }, level: 3 });
  });
  it("lets the level be reported, as far as the account's age allows", async () => {
    const p = await register();
    const early = await SELF.fetch("https://api/v1/me", { method: "PATCH", headers: auth(p), body: JSON.stringify({ level: 7 }) });
    expect(((await early.json()) as any).level).toBe(2); // brand new: 1 + the grace level
    await env.DB.prepare("UPDATE players SET created_at = ?1 WHERE id = ?2").bind(Date.now() - 3 * 3_600_000, p.playerId).run();
    const res = await SELF.fetch("https://api/v1/me", { method: "PATCH", headers: auth(p), body: JSON.stringify({ level: 7 }) });
    expect(((await res.json()) as any).level).toBe(7);
    expect((await cards(p)).json.level).toBe(7);
    expect((await SELF.fetch("https://api/v1/me", { method: "PATCH", headers: auth(p), body: JSON.stringify({ level: 0 }) })).status).toBe(400);
  });
});

describe("cards in a room", () => {
  it("deals the ledger's hands, relays a play once, decrements, and settles", async () => {
    const a = await register(1);
    const b = await register(9);
    await give(a, "ice", 2);
    await give(b, "fire7", 1);
    const room = uuid();
    const A = await join(a, room, "ice,ice,fire7"); // owns two ice, no fire7
    const B = await join(b, room, ",magnet6,fire7"); // magnet6 is level 5 (b is 9: fine) but unowned; fire7 is level 3, over the cap of 1
    const sa = await A.until((m) => m.t === "start");
    expect(sa.hands).toEqual({ a: ["ice", "ice", ""], b: ["", "", ""] });
    expect(sa.cap).toBe(1);
    expect(sa.levels).toEqual({ a: 1, b: 9 });
    const sb = await B.until((m) => m.t === "start");
    expect(sb.hands).toEqual(sa.hands);
    await nextSecond();
    // a plays an ice: b gets it, a gets the receipt, the ledger drops one.
    A.send({ t: "card", id: "ice" });
    expect(await B.until((m) => m.t === "card")).toMatchObject({ id: "ice", from: "a" });
    expect((await A.until((m) => m.t === "card_ok")).id).toBe("ice");
    A.send({ t: "card", id: "ice" });
    await A.until((m) => m.t === "card_ok" && A.inbox.filter((x) => x.t === "card_ok").length === 2);
    A.send({ t: "card", id: "ice" }); // a third: not in hand any more
    expect((await A.until((m) => m.t === "error" && m.code === "card")).id).toBe("ice");
    A.send({ t: "card", id: "fire7" }); // never dealt
    await A.until((m) => m.t === "error" && m.code === "card" && m.id === "fire7");
    await A.settle();
    const left = await env.DB.prepare("SELECT n FROM online_cards WHERE player_id = ?1 AND card_id = 'ice'").bind(a.playerId).first<{ n: number }>();
    expect(left?.n).toBe(0);
    // The level-1 player beats the level-9 player; nothing is paid.
    A.send({ t: "period_end", period: 0, score: 12, totals: {} });
    B.send({ t: "period_end", period: 0, score: 9, totals: {} });
    expect(await A.until((m) => m.t === "settled")).toEqual({ t: "settled", won: true, reason: "played", ranked: false });
    expect(await B.until((m) => m.t === "settled")).toEqual({ t: "settled", won: false, reason: "played", ranked: false });
    const ledgerA = await env.DB.prepare("SELECT kind, card_id, coins FROM online_ledger WHERE player_id = ?1 ORDER BY id").bind(a.playerId).all<any>();
    expect(ledgerA.results).toEqual([{ kind: "play", card_id: "ice", coins: 0 }, { kind: "play", card_id: "ice", coins: 0 }]);
    // The winner's own played cards never come back (Ross, 2026-10-26): the route the phone re-reads after the settle agrees.
    expect((await cards(a)).json).toEqual({ inventory: {}, level: 1 });
    expect((await cards(b)).json).toEqual({ inventory: { fire7: 1 }, level: 9 });
  });
  it("settles a void without an error and the stayer wins a forfeit", async () => {
    // A void: the leaver goes in the first seconds.
    const c = await register(2);
    const d = await register(2);
    const room = uuid();
    const C = await join(c, room);
    const D = await join(d, room);
    await C.until((m) => m.t === "start");
    D.ws.close(1000, "bye");
    await new Promise((r) => setTimeout(r, 80));
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(Date.now() + DROP_GRACE_MS + 1); // the grace to come back runs out
    expect(await runDurableObjectAlarm(env.ROOM.get(env.ROOM.idFromName(room)))).toBe(true);
    expect(await C.until((m) => m.t === "settled")).toMatchObject({ won: false, reason: "void" });
    vi.useRealTimers();
    expect(C.inbox.some((m) => m.t === "error")).toBe(false);
    // A forfeit: the reporter leaves a tie, the stayer takes it.
    const e = await register(2);
    const f = await register(2);
    const room2 = uuid();
    const E = await join(e, room2);
    const F = await join(f, room2);
    await E.until((m) => m.t === "start");
    E.send({ t: "period_end", period: 0, score: 5, totals: {} });
    await F.until((m) => m.t === "period_end");
    E.ws.close(1000, "bye");
    await new Promise((r) => setTimeout(r, 80));
    F.send({ t: "period_end", period: 0, score: 5, totals: {} });
    expect(await F.until((m) => m.t === "settled")).toMatchObject({ won: true, reason: "forfeit" });
  });
  it("throttles the cards route", async () => {
    const p = await register();
    for (let i = 0; i < 20; i++) expect((await cards(p)).status).toBe(200);
    expect((await cards(p)).status).toBe(429);
  });
});
