import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { app } from "../src/index";
import { PART_MAX_BYTES, SAVE_PER_MINUTE } from "../src/save";
import { resetMemoryLimits } from "../src/limits";

const uuid = () => crypto.randomUUID();
const secret = () => [...crypto.getRandomValues(new Uint8Array(40))].map((b) => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[b % 62]).join("");
let ipCounter = 50_000;
const freshIp = () => `10.${Math.floor(ipCounter / 65536) % 256}.${Math.floor(ipCounter / 256) % 256}.${ipCounter++ % 256}`;

interface Player { playerId: string; secret: string; ip: string }

async function register(): Promise<Player> {
  const p = { playerId: uuid(), secret: secret(), ip: freshIp() };
  const res = await SELF.fetch("https://api/v1/register", {
    method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": p.ip },
    body: JSON.stringify({ playerId: p.playerId, secret: p.secret, clientId: uuid() }),
  });
  expect(res.status).toBe(200);
  return p;
}

const auth = (p: Player) => ({ authorization: `Bearer ${p.playerId}.${p.secret}`, "cf-connecting-ip": p.ip });

async function gzip(obj: unknown): Promise<Uint8Array> {
  const stream = new Blob([JSON.stringify(obj)]).stream().pipeThrough(new CompressionStream("gzip"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

async function gunzip(bytes: ArrayBuffer): Promise<unknown> {
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("gzip"));
  return JSON.parse(await new Response(stream).text());
}

async function put(p: Player, part: string, body: Uint8Array, updatedAt: number) {
  const res = await SELF.fetch(`https://api/v1/save/${part}`, {
    method: "PUT", headers: { ...auth(p), "content-type": "application/gzip", "x-updated-at": String(updatedAt) }, body,
  });
  return { status: res.status, json: (await res.json()) as any };
}

beforeEach(() => resetMemoryLimits());

describe("save mirror", () => {
  it("stores a part, lists it, hands it back byte for byte", async () => {
    const p = await register();
    const doc = { updatedAt: 1000, xp: 140, seasonXp: 40, seasonKey: "cage:2" };
    const bytes = await gzip(doc);
    const stored = await put(p, "progress", bytes, 1000);
    expect(stored.status).toBe(200);
    expect(stored.json).toMatchObject({ stored: true, updatedAt: 1000 });
    const manifest = await SELF.fetch("https://api/v1/save", { headers: auth(p) });
    expect(manifest.status).toBe(200);
    const m = (await manifest.json()) as any;
    expect(m.parts.progress).toEqual({ updatedAt: 1000, size: bytes.length });
    expect(m.parts.cards).toBeUndefined();
    const got = await SELF.fetch("https://api/v1/save/progress", { headers: auth(p) });
    expect(got.status).toBe(200);
    expect(got.headers.get("x-updated-at")).toBe("1000");
    expect(got.headers.get("content-type")).toBe("application/gzip");
    const back = await got.arrayBuffer();
    expect(new Uint8Array(back)).toEqual(bytes);
    expect(await gunzip(back)).toEqual(doc);
  });
  it("last writer wins on the part's stamp; a stale push is a 409 with what we hold", async () => {
    const p = await register();
    await put(p, "settings", await gzip({ a: 1 }), 2000);
    const stale = await put(p, "settings", await gzip({ a: 0 }), 1500);
    expect(stale.status).toBe(409);
    expect(stale.json).toMatchObject({ stored: false, updatedAt: 2000 });
    const same = await put(p, "settings", await gzip({ a: 0 }), 2000);
    expect(same.status).toBe(409);
    const newer = await put(p, "settings", await gzip({ a: 2 }), 2500);
    expect(newer.status).toBe(200);
    const got = await SELF.fetch("https://api/v1/save/settings", { headers: auth(p) });
    expect(await gunzip(await got.arrayBuffer())).toEqual({ a: 2 });
  });
  it("refuses unknown parts, bad stamps, non-gzip and oversized bodies", async () => {
    const p = await register();
    expect((await put(p, "account", await gzip({}), 1000)).status).toBe(400);
    expect((await put(p, "tuning", await gzip({}), 1000)).status).toBe(400);
    expect((await put(p, "progress", await gzip({}), 0)).status).toBe(400);
    expect((await put(p, "progress", await gzip({}), Date.now() + 3 * 86_400_000)).status).toBe(400);
    const plain = new TextEncoder().encode(JSON.stringify({ not: "gzip", padding: "x".repeat(40) }));
    expect((await put(p, "progress", plain, 1000)).status).toBe(400);
    const big = new Uint8Array(PART_MAX_BYTES + 1);
    big[0] = 0x1f; big[1] = 0x8b;
    expect((await put(p, "progress", big, 1000)).status).toBe(413);
    expect((await SELF.fetch("https://api/v1/save/progress", { headers: auth(p) })).status).toBe(404);
    expect((await SELF.fetch("https://api/v1/save/nope", { headers: auth(p) })).status).toBe(400);
  });
  it("keeps players apart and needs a bearer", async () => {
    const a = await register();
    const b = await register();
    await put(a, "cards", await gzip({ mine: true }), 1000);
    expect((await SELF.fetch("https://api/v1/save/cards", { headers: auth(b) })).status).toBe(404);
    expect((await SELF.fetch("https://api/v1/save", { headers: { "cf-connecting-ip": freshIp() } })).status).toBe(401);
  });
  it("throttles save calls a minute and honours the kill switch", async () => {
    const p = await register();
    for (let i = 0; i < SAVE_PER_MINUTE; i++) expect((await SELF.fetch("https://api/v1/save", { headers: auth(p) })).status).toBe(200);
    const res = await SELF.fetch("https://api/v1/save", { headers: auth(p) });
    expect(res.status).toBe(429);
    expect(Number(res.headers.get("Retry-After"))).toBeGreaterThan(0);
    const off = await app.request("/v1/save", { headers: auth(p) }, { ...env, FEATURE_SAVE: "off" });
    expect(off.status).toBe(503);
  });
});
