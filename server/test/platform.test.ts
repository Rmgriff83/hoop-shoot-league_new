import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { app } from "../src/index";
import { resetMemoryLimits } from "../src/limits";
import { MAX_SECRETS } from "../src/auth";

const uuid = () => crypto.randomUUID();
const secret = () => [...crypto.getRandomValues(new Uint8Array(40))].map((b) => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[b % 62]).join("");

interface Player { playerId: string; secret: string; name: string; tag: string; ip: string }

let ipCounter = 170_000;
const freshIp = () => `10.${Math.floor(ipCounter / 65536) % 256}.${Math.floor(ipCounter / 256) % 256}.${ipCounter++ % 256}`;

async function register(ip = freshIp(), extra: Record<string, unknown> = {}): Promise<Player> {
  const p = { playerId: uuid(), secret: secret(), ip };
  const res = await SELF.fetch("https://api/v1/register", {
    method: "POST",
    headers: { "content-type": "application/json", "cf-connecting-ip": ip },
    body: JSON.stringify({ playerId: p.playerId, secret: p.secret, clientId: uuid(), ...extra }),
  });
  expect(res.status).toBe(200);
  const j = (await res.json()) as { name: string; tag: string };
  return { ...p, name: j.name, tag: j.tag };
}

const auth = (p: Player) => ({ authorization: `Bearer ${p.playerId}.${p.secret}`, "content-type": "application/json", "cf-connecting-ip": p.ip });
const anon = (ip: string) => ({ "content-type": "application/json", "cf-connecting-ip": ip });

const link = (p: Player, body: unknown) => SELF.fetch("https://api/v1/link", { method: "POST", headers: auth(p), body: JSON.stringify(body) });
const restore = (ip: string, body: unknown) => SELF.fetch("https://api/v1/link/restore", { method: "POST", headers: anon(ip), body: JSON.stringify(body) });
const me = (p: Player) => SELF.fetch("https://api/v1/me", { headers: auth(p) });

beforeEach(() => resetMemoryLimits());

describe("link", () => {
  it("binds a test identity to the caller, idempotently, and /v1/me lists it", async () => {
    const p = await register();
    const subject = "gc-" + uuid();
    const r1 = await link(p, { provider: "test", proof: { subject, displayName: "Not Our Handle" } });
    expect(r1.status).toBe(200);
    expect(await r1.json()).toEqual({ linked: true, provider: "test" });
    const r2 = await link(p, { provider: "test", proof: { subject } });
    expect(r2.status).toBe(200);
    expect(((await r2.json()) as any).already).toBe(true);
    const m = (await (await me(p)).json()) as any;
    expect(m.providers).toEqual(["test"]);
    expect(m.name).toBe(p.name); // the handle stays ours, never the platform's display name
    const row = await env.DB.prepare("SELECT * FROM player_identities WHERE provider = 'test' AND subject = ?1").bind(subject).first<any>();
    expect(row.player_id).toBe(p.playerId);
    expect(JSON.parse(row.meta).displayName).toBe("Not Our Handle");
  });
  it("re-linking the same provider with another subject replaces the old identity", async () => {
    const p = await register();
    expect((await link(p, { provider: "test", proof: { subject: "a-" + uuid() } })).status).toBe(200);
    const b = "b-" + uuid();
    expect((await link(p, { provider: "test", proof: { subject: b } })).status).toBe(200);
    const rows = await env.DB.prepare("SELECT subject FROM player_identities WHERE player_id = ?1").bind(p.playerId).all<any>();
    expect(rows.results.map((r) => r.subject)).toEqual([b]);
  });
  it("answers 409 with the other account's handle and level, and never merges", async () => {
    const owner = await register(freshIp(), { name: "BRICK BARON" });
    await env.DB.prepare("UPDATE players SET created_at = ?1 WHERE id = ?2").bind(Date.now() - 3 * 3_600_000, owner.playerId).run(); // old enough to be level 7
    await SELF.fetch("https://api/v1/me", { method: "PATCH", headers: auth(owner), body: JSON.stringify({ level: 7 }) });
    const subject = "shared-" + uuid();
    expect((await link(owner, { provider: "test", proof: { subject } })).status).toBe(200);
    const other = await register();
    const res = await link(other, { provider: "test", proof: { subject } });
    expect(res.status).toBe(409);
    const j = (await res.json()) as any;
    expect(j).toEqual({ error: "conflict", provider: "test", name: "BRICK BARON", tag: owner.tag, level: 7 });
    // Nothing moved: the owner keeps the identity, the other has none.
    expect(((await (await me(owner)).json()) as any).providers).toEqual(["test"]);
    expect(((await (await me(other)).json()) as any).providers).toEqual([]);
  });
  it("rejects a bad proof (401), an unknown provider (400), a stray field (400), a missing proof (400)", async () => {
    const p = await register();
    expect((await link(p, { provider: "test", proof: { subject: "x", reject: true } })).status).toBe(401);
    expect((await link(p, { provider: "test", proof: { nope: 1 } })).status).toBe(401);
    expect((await link(p, { provider: "steam", proof: { subject: "x" } })).status).toBe(400);
    expect((await link(p, { provider: "test", proof: { subject: "x" }, extra: 1 })).status).toBe(400);
    expect((await link(p, { provider: "test" })).status).toBe(400);
    expect(((await (await me(p)).json()) as any).providers).toEqual([]);
  });
  it("gamecenter and playgames answer 501 until their verifiers exist", async () => {
    const p = await register();
    const gc = await link(p, { provider: "gamecenter", proof: { publicKeyURL: "https://static.gc.apple.com/x", signature: "", salt: "", timestamp: 1, teamPlayerID: "T:1", bundleID: "b" } });
    expect(gc.status).toBe(501);
    expect(((await gc.json()) as any).error).toBe("not_implemented");
    expect((await link(p, { provider: "playgames", proof: { serverAuthCode: "4/abc", playerId: "g1" } })).status).toBe(501);
    expect((await restore("10.3.1.1", { provider: "playgames", proof: { serverAuthCode: "4/abc" }, newSecret: secret() })).status).toBe(501);
  });
  it("the test verifier is a Vitest-only binding", async () => {
    const p = await register();
    const res = await app.request("/v1/link", { method: "POST", headers: auth(p), body: JSON.stringify({ provider: "test", proof: { subject: "x" } }) }, { ...env, PLATFORM_TEST_VERIFIER: undefined });
    expect(res.status).toBe(400);
  });
  it("throttles links to 5 an hour per player", async () => {
    const p = await register();
    for (let i = 0; i < 5; i++) expect((await link(p, { provider: "test", proof: { subject: "t-" + i + uuid() } })).status).toBe(200);
    const sixth = await link(p, { provider: "test", proof: { subject: "t-6" } });
    expect(sixth.status).toBe(429);
    expect(sixth.headers.get("Retry-After")).toBeTruthy();
  });
  it("FEATURE_PLATFORM off answers 503 on every link route", async () => {
    const p = await register();
    const offEnv = { ...env, FEATURE_PLATFORM: "off" };
    expect((await app.request("/v1/link", { method: "POST", headers: auth(p), body: JSON.stringify({ provider: "test", proof: { subject: "x" } }) }, offEnv)).status).toBe(503);
    expect((await app.request("/v1/link/restore", { method: "POST", headers: anon("10.3.2.1"), body: JSON.stringify({ provider: "test", proof: { subject: "x" }, newSecret: secret() }) }, offEnv)).status).toBe(503);
    expect((await app.request("/v1/link/test", { method: "DELETE", headers: auth(p) }, offEnv)).status).toBe(503);
  });
});

describe("restore", () => {
  it("adds a device secret for a linked identity; the first phone stays signed in", async () => {
    const p = await register();
    const subject = "r-" + uuid();
    expect((await link(p, { provider: "test", proof: { subject } })).status).toBe(200);
    const fresh = secret();
    const res = await restore("10.3.3.1", { provider: "test", proof: { subject }, newSecret: fresh });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ playerId: p.playerId, name: p.name, tag: p.tag });
    // Per-device secrets: both work.
    expect((await me(p)).status).toBe(200);
    expect((await me({ ...p, secret: fresh })).status).toBe(200);
    // Registering the id again with the second phone's secret is the idempotent case, not a stranger.
    const again = await SELF.fetch("https://api/v1/register", {
      method: "POST", headers: anon(freshIp()),
      body: JSON.stringify({ playerId: p.playerId, secret: fresh, clientId: uuid() }),
    });
    expect(again.status).toBe(200);
    expect(((await again.json()) as any).created).toBe(false);
    const stranger = await SELF.fetch("https://api/v1/register", {
      method: "POST", headers: anon(freshIp()),
      body: JSON.stringify({ playerId: p.playerId, secret: secret(), clientId: uuid() }),
    });
    expect(stranger.status).toBe(403);
  });
  it("404 for an identity nobody linked, 400 for a bad secret", async () => {
    expect((await restore("10.3.4.1", { provider: "test", proof: { subject: "nobody-" + uuid() }, newSecret: secret() })).status).toBe(404);
    expect((await restore("10.3.4.2", { provider: "test", proof: { subject: "x" }, newSecret: "short" })).status).toBe(400);
  });
  it(`keeps at most ${MAX_SECRETS} secrets, dropping the oldest`, async () => {
    const p = await register();
    const subject = "cap-" + uuid();
    expect((await link(p, { provider: "test", proof: { subject } })).status).toBe(200);
    const fresh: string[] = [];
    for (let i = 0; i < MAX_SECRETS; i++) {
      const s = secret();
      fresh.push(s);
      expect((await restore(freshIp(), { provider: "test", proof: { subject }, newSecret: s })).status).toBe(200);
    }
    const n = await env.DB.prepare("SELECT COUNT(*) AS n FROM player_secrets WHERE player_id = ?1").bind(p.playerId).first<any>();
    expect(n.n).toBe(MAX_SECRETS);
    expect((await me(p)).status).toBe(401); // the first (oldest) secret went
    expect((await me({ ...p, secret: fresh[fresh.length - 1] })).status).toBe(200);
  });
  it("a transfer claim still replaces every secret (a move), a restore does not", async () => {
    const p = await register();
    const subject = "mv-" + uuid();
    expect((await link(p, { provider: "test", proof: { subject } })).status).toBe(200);
    const second = secret();
    expect((await restore("10.3.5.1", { provider: "test", proof: { subject }, newSecret: second })).status).toBe(200);
    const codeRes = await SELF.fetch("https://api/v1/transfer/code", { method: "POST", headers: auth(p) });
    const { code } = (await codeRes.json()) as { code: string };
    const third = secret();
    const claim = await SELF.fetch("https://api/v1/transfer/claim", { method: "POST", headers: anon("10.3.5.2"), body: JSON.stringify({ code, newSecret: third }) });
    expect(claim.status).toBe(200);
    expect((await me(p)).status).toBe(401);
    expect((await me({ ...p, secret: second })).status).toBe(401);
    expect((await me({ ...p, secret: third })).status).toBe(200);
    // The link survives the move: the new phone can still be found by the platform.
    expect(((await (await me({ ...p, secret: third })).json()) as any).providers).toEqual(["test"]);
  });
  it("throttles restores to 5 an hour per IP", async () => {
    const ip = "10.3.6.1";
    for (let i = 0; i < 5; i++) expect((await restore(ip, { provider: "test", proof: { subject: "none-" + i }, newSecret: secret() })).status).toBe(404);
    expect((await restore(ip, { provider: "test", proof: { subject: "none-6" }, newSecret: secret() })).status).toBe(429);
  });
});

describe("unlink", () => {
  it("drops the identity (idempotent); a later restore is 404", async () => {
    const p = await register();
    const subject = "u-" + uuid();
    expect((await link(p, { provider: "test", proof: { subject } })).status).toBe(200);
    const del = await SELF.fetch("https://api/v1/link/test", { method: "DELETE", headers: auth(p) });
    expect(del.status).toBe(200);
    expect(await del.json()).toEqual({ linked: false, provider: "test" });
    expect((await SELF.fetch("https://api/v1/link/test", { method: "DELETE", headers: auth(p) })).status).toBe(200);
    expect(((await (await me(p)).json()) as any).providers).toEqual([]);
    expect((await restore("10.3.7.1", { provider: "test", proof: { subject }, newSecret: secret() })).status).toBe(404);
    expect((await SELF.fetch("https://api/v1/link/steam", { method: "DELETE", headers: auth(p) })).status).toBe(404);
  });
});

describe("delete account", () => {
  it("removes every row keyed on the player and kills the bearer", async () => {
    const p = await register();
    const subject = "d-" + uuid();
    expect((await link(p, { provider: "test", proof: { subject } })).status).toBe(200);
    await SELF.fetch("https://api/v1/transfer/code", { method: "POST", headers: auth(p) });
    await SELF.fetch("https://api/v1/scores", {
      method: "POST", headers: auth(p),
      body: JSON.stringify({ runId: uuid(), area: "cage", score: 20, makes: 12, attempts: 20, swishes: 6, bestStreak: 7, bonus: 2, iced: 0, playedAt: Date.now(), version: "test" }),
    });
    await SELF.fetch("https://api/v1/match/ranked", { method: "POST", headers: auth(p), body: "{}" }); // makes the ratings row
    await SELF.fetch("https://api/v1/match/leave", { method: "POST", headers: auth(p), body: JSON.stringify({ ranked: true }) });
    const res = await SELF.fetch("https://api/v1/me", { method: "DELETE", headers: auth(p) });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ deleted: true });
    for (const [table, col] of [["players", "id"], ["player_identities", "player_id"], ["player_secrets", "player_id"], ["transfer_codes", "player_id"], ["tt_best", "player_id"], ["tt_week_best", "player_id"], ["seen_runs", "player_id"], ["save_parts", "player_id"], ["online_cards", "player_id"], ["online_ledger", "player_id"], ["ratings", "player_id"], ["online_progress", "player_id"], ["grants", "player_id"]]) {
      const n = await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE ${col} = ?1`).bind(p.playerId).first<any>();
      expect(n.n, table).toBe(0);
    }
    expect((await me(p)).status).toBe(401);
    expect((await restore("10.3.8.1", { provider: "test", proof: { subject }, newSecret: secret() })).status).toBe(404);
  });
  it("is throttled (3 an hour per IP) and has no kill switch", async () => {
    const ip = "10.3.9.1";
    const a = await register(ip);
    const b = await register(ip);
    const c = await register(ip);
    const d = await register(ip);
    expect((await app.request("/v1/me", { method: "DELETE", headers: auth(a) }, { ...env, FEATURE_PLATFORM: "off" })).status).toBe(200);
    expect((await SELF.fetch("https://api/v1/me", { method: "DELETE", headers: auth(b) })).status).toBe(200);
    expect((await SELF.fetch("https://api/v1/me", { method: "DELETE", headers: auth(c) })).status).toBe(200);
    expect((await SELF.fetch("https://api/v1/me", { method: "DELETE", headers: auth(d) })).status).toBe(429);
  });
});
