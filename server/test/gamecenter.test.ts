// The Game Center verifier (platform.ts): a real RSA key, a hand-built DER
// certificate served through the cert-fetcher seam, Apple's payload signed
// for real — then every way a proof is refused.
import { SELF, env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { app } from "../src/index";
import { resetMemoryLimits } from "../src/limits";
import { GameCenterVerifier, GC_HOST, GC_MAX_AGE_MS, BadProof, resetCertCache, setCertFetcher } from "../src/platform";

const uuid = () => crypto.randomUUID();
const secret = () => [...crypto.getRandomValues(new Uint8Array(40))].map((b) => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[b % 62]).join("");
let ipCounter = 190_000;
const freshIp = () => `10.${Math.floor(ipCounter / 65536) % 256}.${Math.floor(ipCounter / 256) % 256}.${ipCounter++ % 256}`;

interface Player { playerId: string; secret: string; ip: string }
async function register(ip = freshIp()): Promise<Player> {
  const p = { playerId: uuid(), secret: secret(), ip };
  const res = await SELF.fetch("https://api/v1/register", {
    method: "POST",
    headers: { "content-type": "application/json", "cf-connecting-ip": ip },
    body: JSON.stringify({ playerId: p.playerId, secret: p.secret, clientId: uuid() }),
  });
  expect(res.status).toBe(200);
  return p;
}
const auth = (p: Player) => ({ authorization: `Bearer ${p.playerId}.${p.secret}`, "content-type": "application/json", "cf-connecting-ip": p.ip });
const link = (p: Player, body: unknown) => SELF.fetch("https://api/v1/link", { method: "POST", headers: auth(p), body: JSON.stringify(body) });
const restore = (ip: string, body: unknown) => SELF.fetch("https://api/v1/link/restore", { method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": ip }, body: JSON.stringify(body) });
const me = (p: Player) => SELF.fetch("https://api/v1/me", { headers: auth(p) });

// ---- a certificate, by hand ----------------------------------------------------------------
const b64 = (u: Uint8Array) => btoa(String.fromCharCode(...u));
function tlv(tag: number, body: Uint8Array): Uint8Array {
  let len: number[];
  if (body.length < 0x80) len = [body.length];
  else if (body.length < 0x100) len = [0x81, body.length];
  else len = [0x82, body.length >> 8, body.length & 0xff];
  return new Uint8Array([tag, ...len, ...body]);
}
const cat = (...parts: Uint8Array[]) => {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) {
    out.set(p, at);
    at += p.length;
  }
  return out;
};
const seq = (...parts: Uint8Array[]) => tlv(0x30, cat(...parts));
const ascii = (s: string) => new Uint8Array([...s].map((c) => c.charCodeAt(0)));
const utcTime = (s: string) => tlv(0x17, ascii(s));
const oidSha256Rsa = tlv(0x06, new Uint8Array([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b]));
const name = seq(tlv(0x31, seq(tlv(0x06, new Uint8Array([0x55, 0x04, 0x03])), tlv(0x0c, ascii("gc test")))));

/** A certificate carrying `spki`, valid between the two UTCTimes; the outer signature is noise (no chain check). */
function certificate(spki: Uint8Array, notBefore = "200101000000Z", notAfter = "400101000000Z"): Uint8Array {
  const tbs = seq(
    tlv(0xa0, tlv(0x02, new Uint8Array([2]))), // version v3
    tlv(0x02, new Uint8Array([1])), // serial
    seq(oidSha256Rsa, tlv(0x05, new Uint8Array())),
    name,
    seq(utcTime(notBefore), utcTime(notAfter)),
    name,
    spki,
  );
  return seq(tbs, seq(oidSha256Rsa, tlv(0x05, new Uint8Array())), tlv(0x03, new Uint8Array([0, 1, 2, 3])));
}

interface Apple { pair: CryptoKeyPair; cert: Uint8Array; url: string }
async function apple(url = `https://${GC_HOST}/public-key/gc-prod-9.cer`, validity?: [string, string]): Promise<Apple> {
  const pair = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]);
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", pair.publicKey));
  return { pair, cert: certificate(spki, ...(validity ?? [])), url };
}

/** The proof GameKit would hand the phone, signed with `a`'s key over Apple's payload. */
async function proof(a: Apple, teamPlayerID: string, opts: { timestamp?: number; bundle?: string; salt?: Uint8Array; url?: string } = {}) {
  const timestamp = opts.timestamp ?? Date.now();
  const salt = opts.salt ?? crypto.getRandomValues(new Uint8Array(8));
  const enc = new TextEncoder();
  const id = enc.encode(teamPlayerID);
  const bundle = enc.encode(opts.bundle ?? env.APPLE_BUNDLE_ID!);
  const payload = new Uint8Array(id.length + bundle.length + 8 + salt.length);
  payload.set(id, 0);
  payload.set(bundle, id.length);
  new DataView(payload.buffer).setBigUint64(id.length + bundle.length, BigInt(timestamp), false);
  payload.set(salt, id.length + bundle.length + 8);
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "RSASSA-PKCS1-v1_5" }, a.pair.privateKey, payload));
  return { publicKeyURL: opts.url ?? a.url, signature: b64(signature), salt: b64(salt), timestamp, teamPlayerID };
}

let fetches: string[] = [];
let served: Record<string, Uint8Array> = {};
beforeEach(() => {
  resetMemoryLimits();
  resetCertCache();
  fetches = [];
  served = {};
  setCertFetcher(async (url) => {
    fetches.push(url);
    const c = served[url];
    if (!c) throw new BadProof("cert_fetch");
    return c.buffer.slice(c.byteOffset, c.byteOffset + c.byteLength) as ArrayBuffer;
  });
});
afterEach(() => setCertFetcher(null));

describe("the Game Center verifier", () => {
  it("accepts Apple's signature over teamPlayerID ‖ bundle ‖ timestamp ‖ salt and keys on the team player id", async () => {
    const a = await apple();
    served[a.url] = a.cert;
    const v = new GameCenterVerifier(env as any);
    const team = "T:" + uuid();
    expect(await v.verify(await proof(a, team))).toEqual({ subject: team });
    expect(fetches).toEqual([a.url]);
    // The certificate is cached: a second proof fetches nothing.
    await v.verify(await proof(a, team));
    expect(fetches.length).toBe(1);
  });
  it("refuses a tampered signature, another key, another bundle, a reused salt", async () => {
    const a = await apple();
    served[a.url] = a.cert;
    const v = new GameCenterVerifier(env as any);
    const good = await proof(a, "T:1");
    const flipped = Uint8Array.from(atob(good.signature), (c) => c.charCodeAt(0));
    flipped[10] ^= 0xff;
    await expect(v.verify({ ...good, signature: b64(flipped) })).rejects.toBeInstanceOf(BadProof);
    await expect(v.verify({ ...good, teamPlayerID: "T:2" })).rejects.toBeInstanceOf(BadProof);
    await expect(v.verify(await proof(a, "T:1", { bundle: "com.example.other" }))).rejects.toBeInstanceOf(BadProof);
    const other = await apple();
    await expect(v.verify({ ...(await proof(other, "T:1")), publicKeyURL: a.url })).rejects.toBeInstanceOf(BadProof);
  });
  it("refuses any host but Apple's, http, and malformed fields — without fetching", async () => {
    const a = await apple();
    served[a.url] = a.cert;
    const v = new GameCenterVerifier(env as any);
    const good = await proof(a, "T:1");
    for (const bad of [
      { ...good, publicKeyURL: "https://static.gc.apple.com.evil.example/k.cer" },
      { ...good, publicKeyURL: "https://evil.example/static.gc.apple.com" },
      { ...good, publicKeyURL: `http://${GC_HOST}/public-key/gc-prod-9.cer` },
      { ...good, publicKeyURL: "not a url" },
      { ...good, signature: "***" },
      { ...good, salt: "" },
      { ...good, timestamp: "soon" },
      { ...good, timestamp: -5 },
      { ...good, teamPlayerID: "" },
      { ...good, extra: 1 },
      "T:1",
      null,
      [],
    ]) {
      await expect(v.verify(bad)).rejects.toBeInstanceOf(BadProof);
    }
    expect(fetches).toEqual([]);
  });
  it("refuses a stale or far-future timestamp, and an expired certificate", async () => {
    const a = await apple();
    served[a.url] = a.cert;
    const now = Date.now();
    const v = new GameCenterVerifier(env as any, () => now);
    await expect(v.verify(await proof(a, "T:1", { timestamp: now - GC_MAX_AGE_MS - 1000 }))).rejects.toBeInstanceOf(BadProof);
    await expect(v.verify(await proof(a, "T:1", { timestamp: now + 5 * 60_000 }))).rejects.toBeInstanceOf(BadProof);
    expect(fetches).toEqual([]);
    expect(await v.verify(await proof(a, "T:1", { timestamp: now - GC_MAX_AGE_MS + 5000 }))).toEqual({ subject: "T:1" });
    const old = await apple(`https://${GC_HOST}/public-key/gc-prod-1.cer`, ["150101000000Z", "160101000000Z"]);
    served[old.url] = old.cert;
    await expect(v.verify(await proof(old, "T:1"))).rejects.toBeInstanceOf(BadProof);
    served["https://static.gc.apple.com/public-key/junk.cer"] = new Uint8Array([1, 2, 3]);
    await expect(v.verify(await proof(a, "T:1", { url: "https://static.gc.apple.com/public-key/junk.cer" }))).rejects.toBeInstanceOf(BadProof);
  });
  it("takes each signature once (a replay of a restore would be a takeover)", async () => {
    const a = await apple();
    served[a.url] = a.cert;
    const v = new GameCenterVerifier(env as any);
    const pr = await proof(a, "T:once");
    expect(await v.verify(pr)).toEqual({ subject: "T:once" });
    await expect(v.verify(pr)).rejects.toBeInstanceOf(BadProof);
    expect(await v.verify(await proof(a, "T:once"))).toEqual({ subject: "T:once" });
  });
  it("needs APPLE_BUNDLE_ID (a 500, never a silent accept)", async () => {
    const a = await apple();
    served[a.url] = a.cert;
    const v = new GameCenterVerifier({ ...env, APPLE_BUNDLE_ID: undefined } as any);
    await expect(v.verify(await proof(a, "T:1"))).rejects.toThrow(/APPLE_BUNDLE_ID/);
  });
});

describe("Game Center through the routes", () => {
  it("links, 409s another player's identity, restores the account onto a new phone with remove_ads intact", async () => {
    const a = await apple();
    served[a.url] = a.cert;
    const team = "T:" + uuid();
    const p = await register();
    const r1 = await link(p, { provider: "gamecenter", proof: await proof(a, team) });
    expect(r1.status).toBe(200);
    expect(((await (await me(p)).json()) as any).providers).toEqual(["gamecenter"]);
    // Their remove_ads, on the books.
    await env.DB.prepare("INSERT INTO entitlements (player_id, key, product_id, store, transaction_id, environment, granted_at, event_id, created_at) VALUES (?1, 'remove_ads', 'remove_ads', 'app_store', ?2, 'SANDBOX', 1, ?3, 1)")
      .bind(p.playerId, "tx-" + uuid(), "ev-" + uuid()).run();
    // Another phone, a fresh player, the same Apple account: 409 with the handle.
    const q = await register();
    const r2 = await link(q, { provider: "gamecenter", proof: await proof(a, team) });
    expect(r2.status).toBe(409);
    expect(((await r2.json()) as any).error).toBe("conflict");
    // USE IT: a fresh proof (the link's is spent), a new device secret on the first account.
    const spent = await proof(a, team);
    expect((await restore(q.ip, { provider: "gamecenter", proof: spent, newSecret: secret() })).status).toBe(200);
    expect((await restore(q.ip, { provider: "gamecenter", proof: spent, newSecret: secret() })).status).toBe(401);
    const s2 = secret();
    const r3 = await restore(q.ip, { provider: "gamecenter", proof: await proof(a, team), newSecret: s2 });
    expect(r3.status).toBe(200);
    const j = (await r3.json()) as any;
    expect(j.playerId).toBe(p.playerId);
    const theirs = await me({ ...p, secret: s2, ip: q.ip });
    expect(theirs.status).toBe(200);
    const mj = (await theirs.json()) as any;
    expect(mj.providers).toEqual(["gamecenter"]);
    expect(mj.entitlements).toEqual(["remove_ads"]);
    // A proof for an identity nobody linked: 404, the draft player stays.
    const nobody = await apple();
    served[nobody.url] = nobody.cert;
    expect((await restore(freshIp(), { provider: "gamecenter", proof: await proof(a, "T:nobody"), newSecret: secret() })).status).toBe(404);
  });
  it("a forged proof is 401 proof_rejected on both routes", async () => {
    const a = await apple();
    served[a.url] = a.cert;
    const p = await register();
    const bad = { ...(await proof(a, "T:x")), teamPlayerID: "T:y" };
    expect((await link(p, { provider: "gamecenter", proof: bad })).status).toBe(401);
    expect((await restore(p.ip, { provider: "gamecenter", proof: bad, newSecret: secret() })).status).toBe(401);
  });
});
