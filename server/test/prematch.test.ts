import { SELF, env, runDurableObjectAlarm } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { CARD_MIN_TIER, validHand } from "../src/cards";
import { resetMemoryLimits } from "../src/limits";
import { PREMATCH } from "../src/ranked_data";

const uuid = () => crypto.randomUUID();
const secret = () => [...crypto.getRandomValues(new Uint8Array(40))].map((b) => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[b % 62]).join("");
let ipCounter = 250_000;
const freshIp = () => `10.${Math.floor(ipCounter / 65536) % 256}.${Math.floor(ipCounter / 256) % 256}.${ipCounter++ % 256}`;

interface Player { playerId: string; secret: string; ip: string; name: string; tag: string }

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
  return { ...p, name: j.name, tag: j.tag };
}
const auth = (p: Player) => ({ authorization: `Bearer ${p.playerId}.${p.secret}`, "cf-connecting-ip": p.ip, "content-type": "application/json" });
const give = (p: Player, cardId: string, n: number) => env.DB.prepare("INSERT INTO online_cards (player_id, card_id, n) VALUES (?1, ?2, ?3) ON CONFLICT(player_id, card_id) DO UPDATE SET n = ?3").bind(p.playerId, cardId, n).run();

/** Open the room socket and collect its messages; the pick is sent by hand. */
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
  const send = (m: unknown) => ws.send(JSON.stringify(m));
  const loadout = (slots: string[], ready: boolean) => send({ t: "loadout", slots, ready });
  return { ws, inbox, closes, until, send, loadout, settle: () => new Promise((r) => setTimeout(r, 60)) };
}

beforeEach(() => resetMemoryLimits());

describe("validHand with a cap and a tier", () => {
  it("holds a card under the cap and the player's own level, and under its tier", () => {
    const inv = { inventory: { ice: 1, fire7: 1, magnet6: 1 }, level: 9 };
    expect(validHand(["ice", "fire7", "magnet6"], inv)).toEqual(["ice", "fire7", "magnet6"]); // the old two-arg call: no cap, top tier
    expect(validHand(["ice", "fire7", "magnet6"], inv, 3, "rookie")).toEqual(["ice", "fire7", ""]); // magnet6 is level 5
    expect(validHand(["ice", "fire7", "magnet6"], inv, 1, "rookie")).toEqual(["ice", "", ""]);
    expect(validHand(["ice", "fire7", "magnet6"], { ...inv, level: 4 }, 9, "rookie")).toEqual(["ice", "fire7", ""]); // own level, not just the cap
    const was = CARD_MIN_TIER.fire7;
    CARD_MIN_TIER.fire7 = "pro";
    try {
      expect(validHand(["fire7"], inv, 9, "starter")).toEqual(["", "", ""]);
      expect(validHand(["fire7"], inv, 9, "pro")).toEqual(["fire7", "", ""]);
      expect(validHand(["fire7"], inv, 9, "legend")).toEqual(["fire7", "", ""]);
    } finally {
      if (was === undefined) delete CARD_MIN_TIER.fire7; else CARD_MIN_TIER.fire7 = was;
    }
  });
});

describe("the pre-match step", () => {
  it("deals `matched` to both once the second seat is taken, capped at the lower level", async () => {
    const a = await register(7);
    const b = await register(3);
    const room = uuid();
    const A = await join(a, room, "park");
    expect(await A.until((m) => m.t === "joined")).toMatchObject({ side: "a", status: "waiting", ranked: false });
    await A.settle();
    expect(A.inbox.some((m) => m.t === "matched")).toBe(false);
    const B = await join(b, room, "park");
    const ma = await A.until((m) => m.t === "matched");
    const mb = await B.until((m) => m.t === "matched");
    expect(ma).toMatchObject({
      t: "matched", area: "park", cap: 3, seconds: PREMATCH.seconds, countdown_s: PREMATCH.countdown_s, ranked: false, levels: { a: 7, b: 3 },
      tiers: { a: { tier: "rookie", division: 2 }, b: { tier: "rookie", division: 2 } },
      stats: { a: { games: 0, wins: 0, losses: 0, position: 0 }, b: { games: 0, wins: 0, losses: 0, position: 0 } },
      peer: { id: b.playerId, name: b.name, tag: b.tag, level: 3, town: "", tier: "rookie", division: 2, cons: Math.round(ma.peer.cons), games: 0, wins: 0, losses: 0, position: 0 },
    });
    expect(ma.stats.a.cons).toBeGreaterThan(0); // a fresh rating's conservative value, rounded
    expect(mb.peer.id).toBe(a.playerId);
    expect(mb.cap).toBe(3);
    await A.settle();
    expect(A.inbox.some((m) => m.t === "start")).toBe(false); // nobody is ready
  });
  it("keeps a loadout only as far as the ledger, the cap and the level allow, and starts when both are ready", async () => {
    const a = await register(7);
    const b = await register(3);
    await give(a, "ice", 1);
    await give(a, "fire7", 2);
    await give(a, "magnet6", 1);
    await give(b, "fire7", 1);
    await give(b, "ice", 1);
    const room = uuid();
    const A = await join(a, room);
    const B = await join(b, room);
    await A.until((m) => m.t === "matched");
    A.loadout(["ice", "ice", "magnet6"], false); // one ice owned; magnet6 (level 5) is over the cap of 3
    expect(await A.until((m) => m.t === "loadout_ok")).toEqual({ t: "loadout_ok", hand: ["ice", "", ""], ready: false });
    await B.until((m) => m.t === "matched");
    // The other phone sees the validated pick as it stands (design "Pre Match" 37a).
    expect(await B.until((m) => m.t === "peer_loadout")).toEqual({ t: "peer_loadout", slots: ["ice", "", ""], ready: false, from: "a" });
    A.loadout(["fire7", "nope", "fire7"], true); // the last word counts
    await A.until((m) => m.t === "loadout_ok" && m.ready);
    await B.until((m) => m.t === "matched");
    B.loadout(["magnet6", "fire7", "ice"], true); // magnet6 is over b's own level; fire7 (level 3) fits the cap exactly
    const sa = await A.until((m) => m.t === "start");
    const sb = await B.until((m) => m.t === "start");
    expect(sa.hands).toEqual({ a: ["fire7", "", "fire7"], b: ["", "fire7", "ice"] });
    expect(sa).toMatchObject({ cap: 3, levels: { a: 7, b: 3 }, ranked: false, tiers: { a: { tier: "rookie", division: 2 } }, countdown_s: PREMATCH.countdown_s });
    expect(A.inbox.filter((m) => m.t === "peer_loadout").length).toBe(1); // b's one pick
    expect(sb.seed).toBe(sa.seed);
    expect(sb.hands).toEqual(sa.hands);
  });
  it("tips off on the alarm with the last loadout when a side never readies", async () => {
    const a = await register(3);
    const b = await register(3);
    await give(b, "ice", 1);
    const room = uuid();
    const A = await join(a, room);
    const B = await join(b, room);
    await A.until((m) => m.t === "matched");
    await B.until((m) => m.t === "matched");
    A.loadout(["", "", ""], true);
    B.loadout(["ice", "", ""], false);
    await B.until((m) => m.t === "loadout_ok");
    await A.settle();
    expect(A.inbox.some((m) => m.t === "start")).toBe(false);
    expect(await runDurableObjectAlarm(env.ROOM.get(env.ROOM.idFromName(room)))).toBe(true);
    const sa = await A.until((m) => m.t === "start");
    expect(sa.hands).toEqual({ a: ["", "", ""], b: ["ice", "", ""] });
    await B.until((m) => m.t === "start");
    // Play goes on from here as usual.
    A.send({ t: "shot", n: 1, launch: { angle_deg: 50, speed: 7 } });
    expect((await B.until((m) => m.t === "shot")).from).toBe("a");
  });
  it("refuses a bad loadout shape, and a loadout outside the pick", async () => {
    const a = await register();
    const b = await register();
    const room = uuid();
    const A = await join(a, room);
    await A.until((m) => m.t === "joined");
    A.loadout(["", "", ""], true); // alone: not the pick yet
    expect((await A.until((m) => m.t === "error")).code).toBe("not_prematch");
    const B = await join(b, room);
    await A.until((m) => m.t === "matched");
    A.send({ t: "loadout", slots: "ice", ready: true });
    await A.until((m) => m.t === "error" && m.code === "loadout");
    A.send({ t: "loadout", slots: ["ice"] });
    await A.until((m) => m.t === "error" && m.code === "loadout" && A.inbox.filter((x) => x.code === "loadout").length === 2);
    A.send({ t: "loadout", slots: ["", "", "", ""], ready: true });
    await A.until((m) => m.t === "error" && m.code === "loadout" && A.inbox.filter((x) => x.code === "loadout").length === 3);
    await B.until((m) => m.t === "matched");
    A.loadout(["", "", ""], true);
    B.loadout(["", "", ""], true);
    await A.until((m) => m.t === "start");
    B.loadout(["", "", ""], true); // too late: the hand is dealt
    expect(await B.until((m) => m.t === "error")).toMatchObject({ code: "not_prematch" });
  });
  it("re-sends the card to a phone that comes back during the pick", async () => {
    const a = await register();
    const b = await register();
    const room = uuid();
    const A = await join(a, room);
    const B = await join(b, room);
    await A.until((m) => m.t === "matched");
    await B.until((m) => m.t === "matched");
    const A2 = await join(a, room); // the same player again: the old socket is replaced
    expect(await A2.until((m) => m.t === "joined")).toMatchObject({ side: "a", status: "prematch" });
    expect(await A2.until((m) => m.t === "matched")).toMatchObject({ cap: 1, peer: { id: b.playerId } });
    A2.loadout(["", "", ""], true);
    B.loadout(["", "", ""], true);
    await A2.until((m) => m.t === "start");
    await B.until((m) => m.t === "start");
    expect(A.inbox.some((m) => m.t === "start")).toBe(false); // the replaced socket is out
  });
  it("a drop during the pick ends the room with nothing written", async () => {
    const a = await register();
    const b = await register();
    const room = uuid();
    const A = await join(a, room);
    const B = await join(b, room);
    await A.until((m) => m.t === "matched");
    await B.until((m) => m.t === "matched");
    B.ws.close(1000, "bye");
    expect((await A.until((m) => m.t === "peer_left")).side).toBe("b");
    A.loadout(["", "", ""], true);
    expect((await A.until((m) => m.t === "error")).code).toBe("not_prematch");
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM matches WHERE a_id = ?1").bind(a.playerId).first<{ n: number }>()).toEqual({ n: 0 });
    // The pre-match alarm now just closes the room.
    expect(await runDurableObjectAlarm(env.ROOM.get(env.ROOM.idFromName(room)))).toBe(true);
    await new Promise((r) => setTimeout(r, 80));
    expect(A.closes).toEqual([{ code: 1000, reason: "over" }]);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM matches WHERE a_id = ?1").bind(a.playerId).first<{ n: number }>()).toEqual({ n: 0 });
  });
});
