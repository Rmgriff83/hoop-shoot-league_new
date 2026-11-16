// The Play Games verifier (platform.ts): Google's token exchange and
// players/me through the google-fetcher seam — the accepted proof, the shape
// refusals (no fetch), every way Google can say no, the replay row, the
// mismatch — then the routes: link, 409, restore, forged.
import { SELF, env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { app } from "../src/index";
import { resetMemoryLimits } from "../src/limits";
import { BadProof, NotImplemented, PG_PLAYER_URL, PG_TOKEN_URL, PlayGamesVerifier, setGoogleFetcher } from "../src/platform";

const uuid = () => crypto.randomUUID();
const secret = () => [...crypto.getRandomValues(new Uint8Array(40))].map((b) => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[b % 62]).join("");
let ipCounter = 200_000;
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

// ---- Google, scripted -------------------------------------------------------------------------
interface Call { url: string; method: string; headers: Record<string, string>; body: string }
let calls: Call[] = [];
/** What the token endpoint answers (status, json) and what players/me answers; per test. */
let tokenReply: { status: number; json: unknown } = { status: 200, json: { access_token: "ya29.test", expires_in: 3599, scope: "https://www.googleapis.com/auth/games_lite", token_type: "Bearer" } };
let playerReply: { status: number; json: unknown } = { status: 200, json: { kind: "games#player", playerId: "g_1234567890", displayName: "Brick B." } };
const json = (r: { status: number; json: unknown }) => new Response(JSON.stringify(r.json), { status: r.status, headers: { "content-type": "application/json" } });

beforeEach(() => {
  resetMemoryLimits();
  calls = [];
  tokenReply = { status: 200, json: { access_token: "ya29.test", expires_in: 3599, scope: "https://www.googleapis.com/auth/games_lite", token_type: "Bearer" } };
  playerReply = { status: 200, json: { kind: "games#player", playerId: "g_1234567890", displayName: "Brick B." } };
  setGoogleFetcher(async (url, init) => {
    const headers: Record<string, string> = {};
    for (const [k, v] of Object.entries((init.headers as Record<string, string>) ?? {})) headers[k.toLowerCase()] = v;
    calls.push({ url, method: init.method ?? "GET", headers, body: typeof init.body === "string" ? init.body : "" });
    if (url === PG_TOKEN_URL) return json(tokenReply);
    if (url === PG_PLAYER_URL) return json(playerReply);
    return new Response("not found", { status: 404 });
  });
});
afterEach(() => setGoogleFetcher(null));

const code = () => "4/0A" + secret().slice(0, 40);
const good = (c = code(), playerId = "g_1234567890") => ({ serverAuthCode: c, playerId });
/** A Google player of its own for a route test (the verifier tests share the default one). */
function somebody(): string {
  const id = "g_" + secret().slice(0, 18);
  playerReply = { status: 200, json: { kind: "games#player", playerId: id, displayName: "Brick B." } };
  return id;
}

describe("the Play Games verifier", () => {
  it("exchanges the code with the Game server credential, reads players/me, and keys the identity on the player id", async () => {
    const v = new PlayGamesVerifier(env as any);
    const c = code();
    expect(await v.verify(good(c))).toEqual({ subject: "g_1234567890", displayName: "Brick B." });
    expect(calls.map((x) => [x.method, x.url])).toEqual([["POST", PG_TOKEN_URL], ["GET", PG_PLAYER_URL]]);
    const form = new URLSearchParams(calls[0].body);
    expect(Object.fromEntries(form)).toEqual({ grant_type: "authorization_code", code: c, client_id: "test-web-client.apps.googleusercontent.com", client_secret: "test-web-secret", redirect_uri: "" });
    expect(calls[0].headers["content-type"]).toBe("application/x-www-form-urlencoded");
    expect(calls[1].headers.authorization).toBe("Bearer ya29.test");
  });
  it("refuses a malformed proof before asking Google", async () => {
    const v = new PlayGamesVerifier(env as any);
    for (const bad of [null, "x", [], {}, { serverAuthCode: code() }, { playerId: "g_1" }, { ...good(), extra: 1 }, { serverAuthCode: "", playerId: "g_1" }, { serverAuthCode: "x".repeat(513), playerId: "g_1" }, { serverAuthCode: "with space", playerId: "g_1" }, { serverAuthCode: code(), playerId: "" }, { serverAuthCode: code(), playerId: "g 1" }, { serverAuthCode: code(), playerId: 12 }]) {
      await expect(v.verify(bad)).rejects.toBeInstanceOf(BadProof);
    }
    expect(calls).toEqual([]);
  });
  it("refuses when Google refuses the code, hands no token, refuses the token, or names another player", async () => {
    const v = new PlayGamesVerifier(env as any);
    tokenReply = { status: 400, json: { error: "invalid_grant" } };
    await expect(v.verify(good())).rejects.toThrow("exchange");
    tokenReply = { status: 200, json: { token_type: "Bearer" } };
    await expect(v.verify(good())).rejects.toThrow("token");
    tokenReply = { status: 200, json: { access_token: "ya29.test" } };
    playerReply = { status: 401, json: { error: { code: 401 } } };
    await expect(v.verify(good())).rejects.toThrow("player");
    playerReply = { status: 200, json: { playerId: "g_somebody_else", displayName: "Not Brick" } };
    await expect(v.verify(good())).rejects.toThrow("player_mismatch");
    playerReply = { status: 200, json: { displayName: "no id" } };
    await expect(v.verify(good())).rejects.toThrow("player");
    playerReply = { status: 200, json: [] };
    await expect(v.verify(good())).rejects.toThrow("player");
  });
  it("takes a code once: the same code again is a replay, and Google is not asked", async () => {
    const v = new PlayGamesVerifier(env as any);
    const c = code();
    await v.verify(good(c));
    const before = calls.length;
    await expect(v.verify(good(c))).rejects.toThrow("replay");
    expect(calls.length).toBe(before);
  });
  it("survives a fetcher that throws (no 500 for a Google outage)", async () => {
    setGoogleFetcher(async () => {
      throw new Error("network");
    });
    const v = new PlayGamesVerifier(env as any);
    await expect(v.verify(good())).rejects.toBeInstanceOf(BadProof);
  });
  it("is not wired without the Google secrets", async () => {
    await expect(new PlayGamesVerifier({ ...env, PLAY_GAMES_CLIENT_SECRET: undefined } as any).verify(good())).rejects.toBeInstanceOf(NotImplemented);
    await expect(new PlayGamesVerifier({ ...env, PLAY_GAMES_CLIENT_ID: undefined } as any).verify(good())).rejects.toBeInstanceOf(NotImplemented);
    expect(calls).toEqual([]);
  });
});

describe("Play Games through the routes", () => {
  it("links, answers 409 to a second account, and restores that account on a new phone with a fresh code", async () => {
    const owner = await register();
    const pid = somebody();
    const res = await link(owner, { provider: "playgames", proof: good(code(), pid) });
    expect(res.status).toBe(200);
    expect((await res.json()) as any).toEqual({ linked: true, provider: "playgames" });
    expect(((await (await me(owner)).json()) as any).providers).toEqual(["playgames"]);
    const other = await register();
    const clash = await link(other, { provider: "playgames", proof: good(code(), pid) });
    expect(clash.status).toBe(409);
    expect(((await clash.json()) as any).provider).toBe("playgames");
    const newSecret = secret();
    const rs = await restore("10.4.1.1", { provider: "playgames", proof: good(code(), pid), newSecret });
    expect(rs.status).toBe(200);
    const j = (await rs.json()) as any;
    expect(j.playerId).toBe(owner.playerId);
    const back = await SELF.fetch("https://api/v1/me", { headers: { authorization: `Bearer ${owner.playerId}.${newSecret}`, "cf-connecting-ip": "10.4.1.1" } });
    expect(back.status).toBe(200);
  });
  it("a forged proof is 401 on both routes, and a mismatched player id too", async () => {
    const p = await register();
    const pid = somebody();
    tokenReply = { status: 400, json: { error: "invalid_grant" } };
    expect((await link(p, { provider: "playgames", proof: good(code(), pid) })).status).toBe(401);
    expect((await restore("10.4.1.2", { provider: "playgames", proof: good(code(), pid), newSecret: secret() })).status).toBe(401);
    tokenReply = { status: 200, json: { access_token: "ya29.test" } };
    expect((await link(p, { provider: "playgames", proof: { serverAuthCode: code(), playerId: "g_not_me" } })).status).toBe(401);
    expect(((await (await me(p)).json()) as any).providers).toEqual([]);
  });
  it("an unknown identity on restore is 404", async () => {
    playerReply = { status: 200, json: { playerId: "g_nobody_yet" } };
    expect((await restore("10.4.1.3", { provider: "playgames", proof: { serverAuthCode: code(), playerId: "g_nobody_yet" }, newSecret: secret() })).status).toBe(404);
  });
  it("unlinks", async () => {
    const p = await register();
    const pid = somebody();
    expect((await link(p, { provider: "playgames", proof: good(code(), pid) })).status).toBe(200);
    const del = await SELF.fetch("https://api/v1/link/playgames", { method: "DELETE", headers: auth(p) });
    expect(del.status).toBe(200);
    expect(((await (await me(p)).json()) as any).providers).toEqual([]);
  });
});
