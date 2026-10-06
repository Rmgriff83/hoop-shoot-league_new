import { SELF, env, createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import worker, { app } from "../src/index";
import { longLimit, resetMemoryLimits } from "../src/limits";
import { plausible, weekOf, normalizeName, validName } from "../src/rules";

const uuid = () => crypto.randomUUID();
const secret = () => [...crypto.getRandomValues(new Uint8Array(40))].map((b) => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[b % 62]).join("");

interface Player { playerId: string; secret: string; name: string; tag: string }

async function register(ip = "10.0.0." + Math.floor(Math.random() * 250), extra: Record<string, unknown> = {}): Promise<Player> {
  const p = { playerId: uuid(), secret: secret() };
  const res = await SELF.fetch("https://api/v1/register", {
    method: "POST",
    headers: { "content-type": "application/json", "cf-connecting-ip": ip },
    body: JSON.stringify({ ...p, clientId: uuid(), ...extra }),
  });
  expect(res.status).toBe(200);
  const j = (await res.json()) as { name: string; tag: string };
  return { ...p, name: j.name, tag: j.tag };
}

const auth = (p: Player) => ({ authorization: `Bearer ${p.playerId}.${p.secret}`, "content-type": "application/json" });

function run(area = "cage", score = 20, over: Record<string, unknown> = {}) {
  return {
    runId: uuid(), area, score, makes: 12, attempts: 20, swishes: 6, bestStreak: 7, bonus: 2, iced: 0,
    playedAt: Date.now(), version: "test", ...over,
  };
}

async function submit(p: Player, body: Record<string, unknown>) {
  const res = await SELF.fetch("https://api/v1/scores", { method: "POST", headers: auth(p), body: JSON.stringify(body) });
  return { status: res.status, json: (await res.json()) as any, retry: res.headers.get("Retry-After") };
}

async function board(p: Player, area = "cage", period = "all", limit?: number) {
  const q = new URLSearchParams({ area, period });
  if (limit !== undefined) q.set("limit", String(limit));
  const res = await SELF.fetch("https://api/v1/leaderboard?" + q, { headers: auth(p) });
  return { status: res.status, json: (await res.json()) as any };
}

beforeEach(() => resetMemoryLimits());

describe("rules", () => {
  it("weeks start on a Monday", () => {
    const mon = Date.UTC(2026, 0, 5); // Monday
    expect(weekOf(mon)).toBe(weekOf(mon + 6 * 86_400_000));
    expect(weekOf(mon + 7 * 86_400_000)).toBe(weekOf(mon) + 1);
    expect(weekOf(mon - 1)).toBe(weekOf(mon) - 1);
  });
  it("plausibility catches each rule", () => {
    const now = Date.now();
    expect(plausible(run(), now)).toBeNull();
    expect(plausible(run("cage", 20, { area: "moon" }), now)).toBe("area");
    expect(plausible(run("cage", 20, { attempts: 81 }), now)).toBe("attempts");
    expect(plausible(run("cage", 20, { makes: 21 }), now)).toBe("makes");
    expect(plausible(run("cage", 20, { swishes: 13 }), now)).toBe("swishes");
    expect(plausible(run("cage", 20, { bestStreak: 13 }), now)).toBe("bestStreak");
    expect(plausible(run("cage", 61), now)).toBe("score");
    expect(plausible(run("cage", 20, { bonus: 21 }), now)).toBe("bonus");
    expect(plausible(run("cage", 20, { playedAt: now - 3 * 86_400_000 }), now)).toBe("playedAt");
    expect(plausible(run("cage", 20, { score: -1 }), now)).toBe("score");
    expect(plausible(run("cage", 20, { score: 1.5 }), now)).toBe("score");
    expect(plausible(run("cage", 20, { runId: "nope" }), now)).toBe("runId");
  });
  it("names are tidied and checked", () => {
    expect(normalizeName("  brick   baron ")).toBe("BRICK BARON");
    expect(validName("BRICK BARON", ["FUCK"])).toBe(true);
    expect(validName("AB", [])).toBe(false);
    expect(validName("A".repeat(25), [])).toBe(false);
    expect(validName("BRICK-BARON", [])).toBe(false);
    expect(validName("FUCK BARON", ["FUCK"])).toBe(false);
    expect(validName("FU CK BARON", ["FUCK"])).toBe(true); // short words only match whole tokens
    expect(validName("NIG GER", ["NIGGER"])).toBe(false); // long ones match squashed too
  });
});

describe("register", () => {
  it("creates once, is idempotent, refuses a wrong secret", async () => {
    const p = await register("10.1.0.1");
    expect(p.name).toMatch(/^[A-Z]+ [A-Z]+$/);
    expect(p.tag).toMatch(/^\d{2}$/);
    const again = await SELF.fetch("https://api/v1/register", {
      method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": "10.1.0.1" },
      body: JSON.stringify({ playerId: p.playerId, secret: p.secret, clientId: uuid() }),
    });
    expect(again.status).toBe(200);
    expect(((await again.json()) as any).name).toBe(p.name);
    const wrong = await SELF.fetch("https://api/v1/register", {
      method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": "10.1.0.1" },
      body: JSON.stringify({ playerId: p.playerId, secret: secret(), clientId: uuid() }),
    });
    expect(wrong.status).toBe(403);
  });
  it("takes a valid chosen name, ignores a bad one, rejects stray fields", async () => {
    const ok = await register("10.1.0.2", { name: "swish kid", tag: "07" });
    expect(ok.name).toBe("SWISH KID");
    expect(ok.tag).toBe("07");
    const bad = await register("10.1.0.2", { name: "x" });
    expect(bad.name).toMatch(/^[A-Z]+ [A-Z]+$/);
    const stray = await SELF.fetch("https://api/v1/register", {
      method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": "10.1.0.2" },
      body: JSON.stringify({ playerId: uuid(), secret: secret(), clientId: uuid(), admin: true }),
    });
    expect(stray.status).toBe(400);
  });
  it("throttles an IP to 5 an hour", async () => {
    for (let i = 0; i < 5; i++) await register("10.1.0.3");
    const res = await SELF.fetch("https://api/v1/register", {
      method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": "10.1.0.3" },
      body: JSON.stringify({ playerId: uuid(), secret: secret(), clientId: uuid() }),
    });
    expect(res.status).toBe(429);
    expect(Number(res.headers.get("Retry-After"))).toBeGreaterThan(0);
  });
  it("refuses an oversized body", async () => {
    const res = await SELF.fetch("https://api/v1/register", {
      method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": "10.1.0.4" },
      body: JSON.stringify({ playerId: uuid(), secret: secret(), clientId: uuid(), name: "A".repeat(5000) }),
    });
    expect(res.status).toBe(400);
  });
});

describe("auth", () => {
  it("rejects a missing, malformed or wrong bearer", async () => {
    const p = await register();
    expect((await SELF.fetch("https://api/v1/me")).status).toBe(401);
    expect((await SELF.fetch("https://api/v1/me", { headers: { authorization: "Bearer junk" } })).status).toBe(401);
    expect((await SELF.fetch("https://api/v1/me", { headers: { authorization: `Bearer ${p.playerId}.${secret()}` } })).status).toBe(401);
    const ok = await SELF.fetch("https://api/v1/me", { headers: auth(p) });
    expect(ok.status).toBe(200);
    expect(((await ok.json()) as any).name).toBe(p.name);
  });
  it("renames with validation", async () => {
    const p = await register();
    const ok = await SELF.fetch("https://api/v1/me", { method: "PATCH", headers: auth(p), body: JSON.stringify({ name: "glass  wizard" }) });
    expect(ok.status).toBe(200);
    expect(((await ok.json()) as any).name).toBe("GLASS WIZARD");
    const bad = await SELF.fetch("https://api/v1/me", { method: "PATCH", headers: auth(p), body: JSON.stringify({ name: "fuck" }) });
    expect(bad.status).toBe(400);
    const limit = await SELF.fetch("https://api/v1/me", { method: "PATCH", headers: auth(p), body: JSON.stringify({ name: "A".repeat(30) }) });
    expect(limit.status).toBe(400);
  });
});

describe("scores + boards", () => {
  it("accepts a run, ranks it, dedupes a resend, keeps the best", async () => {
    const p = await register();
    const r = run("beach", 20);
    const first = await submit(p, r);
    expect(first.status).toBe(200);
    expect(first.json).toMatchObject({ accepted: true, improved: true, best: 20 });
    expect(first.json.rank).toBeGreaterThanOrEqual(1);
    expect(first.json.weekRank).toBeGreaterThanOrEqual(1);
    const dup = await submit(p, r);
    expect(dup.json).toMatchObject({ accepted: false, duplicate: true, best: 20 });
    const worse = await submit(p, run("beach", 15));
    expect(worse.json).toMatchObject({ accepted: true, improved: false, best: 20 });
    const better = await submit(p, run("beach", 30, { makes: 14, attempts: 22, swishes: 8 }));
    expect(better.json).toMatchObject({ improved: true, best: 30 });
    const b = await board(p, "beach");
    const mine = b.json.rows.find((r: any) => r.me);
    expect(mine).toMatchObject({ score: 30, name: p.name });
    expect(b.json.me).toMatchObject({ rank: mine.rank, score: 30 });
    const other = await board(p, "city");
    expect(other.json.rows).toHaveLength(0);
    expect(other.json.me).toBeNull();
  });
  it("rejects an implausible run with the field", async () => {
    const p = await register();
    const res = await submit(p, run("cage", 99));
    expect(res.status).toBe(400);
    expect(res.json).toMatchObject({ error: "implausible", field: "score" });
    const stray = await submit(p, { ...run(), hack: 1 });
    expect(stray.status).toBe(400);
  });
  it("orders by score then earlier playedAt, and ranks the caller", async () => {
    const a = await register();
    const b = await register();
    const c = await register();
    const now = Date.now();
    await submit(a, run("cage", 20, { playedAt: now - 5000 }));
    await submit(b, run("cage", 20, { playedAt: now - 9000 })); // same score, earlier → ahead
    await submit(c, run("cage", 25, { makes: 13, attempts: 21, swishes: 7 }));
    const view = await board(a, "cage");
    const ours = view.json.rows.filter((r: any) => [a.name, b.name, c.name].includes(r.name));
    expect(ours.map((r: any) => r.score)).toEqual([25, 20, 20]);
    expect(ours[1].name).toBe(b.name);
    expect(ours[2].me).toBe(true);
    expect(view.json.me.rank).toBe(ours[2].rank);
    expect(ours[1].rank).toBe(ours[2].rank - 1);
    const top1 = await board(a, "cage", "all", 1);
    expect(top1.json.rows).toHaveLength(1);
    expect(top1.json.me.rank).toBe(view.json.me.rank); // my rank survives a short list
    const huge = await board(a, "cage", "all", 9999);
    expect(huge.json.rows.length).toBeLessThanOrEqual(50);
  });
  it("keeps a week board apart from all time", async () => {
    const p = await register();
    const now = Date.now();
    await submit(p, run("city", 20, { playedAt: now }));
    const wk = await board(p, "city", "week");
    expect(wk.json.period).toBe("week");
    expect(wk.json.week).toBe(weekOf(now));
    expect(wk.json.rows.find((r: any) => r.me).score).toBe(20);
    // A run from last week (still within the 2-day slack only if the week just turned,
    // so write the row directly) does not show on this week's board.
    await env.DB.prepare(
      "INSERT INTO tt_week_best (player_id, area, week, score, makes, attempts, swishes, best_streak, played_at, run_id) VALUES (?1,'city',?2,40,20,30,10,9,?3,?4)",
    ).bind(p.playerId, weekOf(now) - 1, now - 8 * 86_400_000, uuid()).run();
    const again = await board(p, "city", "week");
    expect(again.json.rows.filter((r: any) => r.me).map((r: any) => r.score)).toEqual([20]);
    const all = await board(p, "city", "all");
    expect(all.json.rows.find((r: any) => r.me).score).toBe(20);
  });
  it("throttles a player to 6 submissions a minute", async () => {
    const p = await register();
    for (let i = 0; i < 6; i++) expect((await submit(p, run("cage", 10 + i, { makes: 12 }))).status).toBe(200);
    const seventh = await submit(p, run());
    expect(seventh.status).toBe(429);
    expect(Number(seventh.retry)).toBeGreaterThan(0);
  });
  it("throttles board reads to 20 a minute", async () => {
    const p = await register();
    for (let i = 0; i < 20; i++) expect((await board(p)).status).toBe(200);
    expect((await board(p)).status).toBe(429);
  });
  it("counts long windows in D1", async () => {
    const now = Date.now();
    for (let i = 0; i < 3; i++) expect((await longLimit(env.DB, "t:x", 3, 3600, now)).allowed).toBe(true);
    const v = await longLimit(env.DB, "t:x", 3, 3600, now);
    expect(v.allowed).toBe(false);
    expect(v.retryAfter).toBeGreaterThan(0);
    expect(v.retryAfter).toBeLessThanOrEqual(3600);
    // The next window starts over.
    expect((await longLimit(env.DB, "t:x", 3, 3600, now + 3600_000)).allowed).toBe(true);
  });
  it("kill switches answer 503", async () => {
    const p = await register();
    const res = await app.request("/v1/scores", { method: "POST", headers: auth(p), body: JSON.stringify(run()) }, { ...env, FEATURE_SUBMIT: "off" });
    expect(res.status).toBe(503);
    const b = await app.request("/v1/leaderboard?area=cage", { headers: auth(p) }, { ...env, FEATURE_BOARD: "off" });
    expect(b.status).toBe(503);
  });
});

describe("transfer", () => {
  it("moves a player to a new secret once, within the window", async () => {
    const p = await register();
    const codeRes = await SELF.fetch("https://api/v1/transfer/code", { method: "POST", headers: auth(p) });
    expect(codeRes.status).toBe(200);
    const { code } = (await codeRes.json()) as { code: string };
    expect(code).toMatch(/^[A-Z2-9]{8}$/);
    const fresh = secret();
    const claim = await SELF.fetch("https://api/v1/transfer/claim", {
      method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": "10.2.0.1" },
      body: JSON.stringify({ code: code.toLowerCase(), newSecret: fresh }),
    });
    expect(claim.status).toBe(200);
    expect(((await claim.json()) as any).playerId).toBe(p.playerId);
    // The old secret is dead, the new one lives, the code is spent.
    expect((await SELF.fetch("https://api/v1/me", { headers: auth(p) })).status).toBe(401);
    expect((await SELF.fetch("https://api/v1/me", { headers: auth({ ...p, secret: fresh }) })).status).toBe(200);
    const spent = await SELF.fetch("https://api/v1/transfer/claim", {
      method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": "10.2.0.1" },
      body: JSON.stringify({ code, newSecret: secret() }),
    });
    expect(spent.status).toBe(404);
  });
  it("refuses an expired code and throttles codes to 3 an hour", async () => {
    const p = await register();
    const codeRes = await SELF.fetch("https://api/v1/transfer/code", { method: "POST", headers: auth(p) });
    const { code } = (await codeRes.json()) as { code: string };
    await env.DB.prepare("UPDATE transfer_codes SET expires_at = ?1 WHERE code = ?2").bind(Date.now() - 1, code).run();
    const claim = await SELF.fetch("https://api/v1/transfer/claim", {
      method: "POST", headers: { "content-type": "application/json", "cf-connecting-ip": "10.2.0.2" },
      body: JSON.stringify({ code, newSecret: secret() }),
    });
    expect(claim.status).toBe(410);
    expect((await SELF.fetch("https://api/v1/transfer/code", { method: "POST", headers: auth(p) })).status).toBe(200);
    expect((await SELF.fetch("https://api/v1/transfer/code", { method: "POST", headers: auth(p) })).status).toBe(200);
    expect((await SELF.fetch("https://api/v1/transfer/code", { method: "POST", headers: auth(p) })).status).toBe(429);
  });
});

describe("cron", () => {
  it("prunes old run ids and dead codes", async () => {
    const p = await register();
    const old = Date.now() - 40 * 86_400_000;
    await env.DB.prepare("INSERT INTO seen_runs (run_id, player_id, seen_at) VALUES (?1, ?2, ?3)").bind(uuid(), p.playerId, old).run();
    await env.DB.prepare("INSERT INTO seen_runs (run_id, player_id, seen_at) VALUES (?1, ?2, ?3)").bind(uuid(), p.playerId, Date.now()).run();
    await env.DB.prepare("INSERT INTO transfer_codes (code, player_id, expires_at) VALUES ('DEADCODE', ?1, ?2)").bind(p.playerId, old).run();
    const ctx = createExecutionContext();
    await worker.scheduled(createScheduledController({ cron: "17 4 * * *" }), env, ctx);
    await waitOnExecutionContext(ctx);
    const runs = await env.DB.prepare("SELECT COUNT(*) AS n FROM seen_runs WHERE player_id = ?1").bind(p.playerId).first<{ n: number }>();
    expect(runs?.n).toBe(1);
    const codes = await env.DB.prepare("SELECT COUNT(*) AS n FROM transfer_codes WHERE player_id = ?1").bind(p.playerId).first<{ n: number }>();
    expect(codes?.n).toBe(0);
  });
});
