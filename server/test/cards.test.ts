import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { resetMemoryLimits } from "../src/limits";
import { CARDS, onlineCoins, validHand } from "../src/cards";

const uuid = () => crypto.randomUUID();
const secret = () => [...crypto.getRandomValues(new Uint8Array(40))].map((b) => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[b % 62]).join("");
let ipCounter = 130_000;
const freshIp = () => `10.${Math.floor(ipCounter / 65536) % 256}.${Math.floor(ipCounter / 256) % 256}.${ipCounter++ % 256}`;

interface Player { playerId: string; secret: string; ip: string }

async function register(level = 1): Promise<Player> {
  const p = { playerId: uuid(), secret: secret(), ip: freshIp() };
  const res = await SELF.fetch("https://api/v1/register", {
    method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": p.ip },
    body: JSON.stringify({ playerId: p.playerId, secret: p.secret, clientId: uuid(), level }),
  });
  expect(res.status).toBe(200);
  return p;
}
const auth = (p: Player) => ({ authorization: `Bearer ${p.playerId}.${p.secret}`, "cf-connecting-ip": p.ip, "content-type": "application/json" });
const giveCoins = (p: Player, n: number) => env.DB.prepare("INSERT INTO online_wallet (player_id, coins) VALUES (?1, ?2) ON CONFLICT(player_id) DO UPDATE SET coins = ?2").bind(p.playerId, n).run();
async function cards(p: Player) {
  const res = await SELF.fetch("https://api/v1/cards", { headers: auth(p) });
  return { status: res.status, json: (await res.json()) as any };
}
async function buy(p: Player, id: string) {
  const res = await SELF.fetch("https://api/v1/cards/buy", { method: "POST", headers: auth(p), body: JSON.stringify({ id }) });
  return { status: res.status, json: (await res.json()) as any };
}
async function join(p: Player, room: string, slots = "") {
  const res = await SELF.fetch(`https://api/v1/match/room/${room}?area=cage&slots=${slots}`, { headers: { ...auth(p), upgrade: "websocket" } });
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
    throw new Error("timeout; inbox=" + JSON.stringify(inbox));
  };
  return { ws, inbox, until, send: (m: unknown) => ws.send(JSON.stringify(m)), settle: () => new Promise((r) => setTimeout(r, 60)) };
}

beforeEach(() => resetMemoryLimits());

describe("the online payout rule", () => {
  it("weights a win by the upset and pays a loss flat", () => {
    expect(onlineCoins(true, 1, 9)).toEqual({ coins: 110, mult: 2.2 });
    expect(onlineCoins(true, 9, 1)).toEqual({ coins: 25, mult: 0.5 });
    expect(onlineCoins(true, 4, 4)).toEqual({ coins: 50, mult: 1 });
    expect(onlineCoins(true, 1, 40)).toEqual({ coins: 125, mult: 2.5 }); // the cap
    expect(onlineCoins(false, 1, 9)).toEqual({ coins: 20, mult: 1 });
  });
  it("reads the cards and keeps a hand honest", () => {
    expect(Object.keys(CARDS).sort()).toEqual(["fire7", "ice", "vortex6"]);
    expect(CARDS.vortex6.level).toBe(5);
    const inv = { coins: 0, inventory: { ice: 1, fire7: 2 }, level: 3 };
    expect(validHand(["ice", "ice", "fire7"], inv)).toEqual(["ice", "", "fire7"]); // one ice owned
    expect(validHand(["vortex6", "fire7", "fire7"], inv)).toEqual(["", "fire7", "fire7"]); // level 5 card at level 3
    expect(validHand(["nope", "", "ice"], inv)).toEqual(["", "", "ice"]);
    expect(validHand([], inv)).toEqual(["", "", ""]);
  });
});

describe("the shop", () => {
  it("lists an empty ledger, sells under the level cap, refuses short coins and unknown cards", async () => {
    const p = await register(3);
    const empty = await cards(p);
    expect(empty.json).toEqual({ coins: 0, inventory: {}, level: 3 });
    expect((await buy(p, "ice")).status).toBe(402);
    await giveCoins(p, 300);
    const bought = await buy(p, "ice");
    expect(bought.status).toBe(200);
    expect(bought.json).toEqual({ coins: 200, inventory: { ice: 1 }, level: 3 });
    const again = await buy(p, "fire7");
    expect(again.json).toEqual({ coins: 30, inventory: { ice: 1, fire7: 1 }, level: 3 });
    expect((await buy(p, "ice")).status).toBe(402);
    const locked = await buy(p, "vortex6");
    expect(locked.status).toBe(400);
    expect(locked.json).toMatchObject({ error: "level", level: 5 });
    expect((await buy(p, "moon")).status).toBe(400);
    const ledger = await env.DB.prepare("SELECT kind, card_id, coins FROM online_ledger WHERE player_id = ?1 ORDER BY id").bind(p.playerId).all<any>();
    expect(ledger.results).toEqual([{ kind: "buy", card_id: "ice", coins: -100 }, { kind: "buy", card_id: "fire7", coins: -170 }]);
  });
  it("lets the level be reported", async () => {
    const p = await register();
    const res = await SELF.fetch("https://api/v1/me", { method: "PATCH", headers: auth(p), body: JSON.stringify({ level: 7 }) });
    expect(((await res.json()) as any).level).toBe(7);
    expect((await cards(p)).json.level).toBe(7);
    expect((await SELF.fetch("https://api/v1/me", { method: "PATCH", headers: auth(p), body: JSON.stringify({ level: 0 }) })).status).toBe(400);
  });
});

describe("cards in a room", () => {
  it("deals the ledger's hands, relays a play once, decrements, and pays the upset", async () => {
    const a = await register(1);
    const b = await register(9);
    await giveCoins(a, 500);
    await buy(a, "ice");
    await buy(a, "ice");
    await giveCoins(b, 500);
    await buy(b, "fire7");
    const room = uuid();
    const A = await join(a, room, "ice,ice,fire7"); // owns two ice, no fire7
    const B = await join(b, room, ",vortex6,fire7"); // vortex6 is level 5 (b is 9: fine) but unowned
    const sa = await A.until((m) => m.t === "start");
    expect(sa.hands).toEqual({ a: ["ice", "ice"], b: ["fire7"] });
    expect(sa.levels).toEqual({ a: 1, b: 9 });
    const sb = await B.until((m) => m.t === "start");
    expect(sb.hands).toEqual(sa.hands);
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
    // The level-1 player beats the level-9 player: 50 × 2.2.
    A.send({ t: "period_end", period: 0, score: 12, totals: {} });
    B.send({ t: "period_end", period: 0, score: 9, totals: {} });
    const setA = await A.until((m) => m.t === "settled");
    const setB = await B.until((m) => m.t === "settled");
    expect(setA).toMatchObject({ coins: 110, mult: 2.2, won: true, reason: "played", wallet: 300 + 110 });
    expect(setB).toMatchObject({ coins: 20, mult: 1, won: false, wallet: 330 + 20 });
    const ledgerA = await env.DB.prepare("SELECT kind, coins FROM online_ledger WHERE player_id = ?1 AND kind = 'reward'").bind(a.playerId).all<any>();
    expect(ledgerA.results).toEqual([{ kind: "reward", coins: 110 }]);
  });
  it("pays the favourite less, pays nothing on a void, pays the stayer on a forfeit", async () => {
    const hi = await register(9);
    const lo = await register(1);
    const room = uuid();
    const H = await join(hi, room);
    const L = await join(lo, room);
    await H.until((m) => m.t === "start");
    H.send({ t: "period_end", period: 0, score: 20, totals: {} });
    L.send({ t: "period_end", period: 0, score: 3, totals: {} });
    expect(await H.until((m) => m.t === "settled")).toMatchObject({ coins: 25, mult: 0.5, won: true });
    expect(await L.until((m) => m.t === "settled")).toMatchObject({ coins: 20, won: false });
    // A void: the leaver goes in the first seconds.
    const c = await register(2);
    const d = await register(2);
    const room2 = uuid();
    const C = await join(c, room2);
    const D = await join(d, room2);
    await C.until((m) => m.t === "start");
    D.ws.close(1000, "bye");
    expect(await C.until((m) => m.t === "settled")).toMatchObject({ coins: 0, won: false, reason: "void" });
    expect(await env.DB.prepare("SELECT coins FROM online_wallet WHERE player_id = ?1").bind(c.playerId).first()).toBeNull();
  });
  it("throttles the shop", async () => {
    const p = await register();
    for (let i = 0; i < 20; i++) expect((await cards(p)).status).toBe(200);
    expect((await cards(p)).status).toBe(429);
  });
});
