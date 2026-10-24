/**
 * Ranked Stage B off the court (docs/BACKEND.md → Ranked → Stage B): the
 * once-a-day login pass (cumulative days, the schedule, welcome back), the
 * rewards routes (pending grants, CLAIM once), what /v1/me adds, the kill switch.
 */
import { SELF, env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { DAY_MS, dayOf } from "../src/days";
import { resetMemoryLimits } from "../src/limits";
import { DROPS, METER_SIZE, allMilestoneKeys, loginGrants } from "../src/online_drops";
import { loginDay, nextLoginCard } from "../src/rewards";

const uuid = () => crypto.randomUUID();
const secret = () => [...crypto.getRandomValues(new Uint8Array(40))].map((b) => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[b % 62]).join("");
let ipCounter = 330_000;
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
const playerRow = (p: Player) => env.DB.prepare("SELECT * FROM players WHERE id = ?1").bind(p.playerId).first<any>();
const progress = (p: Player) => env.DB.prepare("SELECT * FROM online_progress WHERE player_id = ?1").bind(p.playerId).first<any>();
const grants = async (p: Player) => (await env.DB.prepare("SELECT key, kind, card_id, claimed_at FROM grants WHERE player_id = ?1 ORDER BY key").bind(p.playerId).all<any>()).results;
async function rewards(p: Player) {
  const res = await SELF.fetch("https://api/v1/rewards", { headers: auth(p) });
  return { status: res.status, json: (await res.json()) as any };
}
async function claim(p: Player, key: string) {
  const res = await SELF.fetch("https://api/v1/rewards/claim", { method: "POST", headers: auth(p), body: JSON.stringify({ key }) });
  return { status: res.status, json: (await res.json()) as any };
}
const me = async (p: Player) => (await SELF.fetch("https://api/v1/me", { headers: auth(p) })).json() as Promise<any>;
/** The login pass as auth.ts runs it, at `now`. */
const pass = async (p: Player, now: number) => loginDay(env.DB, await playerRow(p), now);

beforeEach(() => { vi.useRealTimers(); resetMemoryLimits(); });
afterEach(() => vi.useRealTimers());

describe("the login pass", () => {
  it("counts distinct UTC days (never a streak) and hands out the schedule", async () => {
    const p = await register();
    const day0 = dayOf(Date.now());
    const t = (d: number) => (day0 + d) * DAY_MS + 1000;
    await pass(p, t(0));
    let pr = await progress(p);
    expect(pr.login_days).toBe(1);
    expect(pr.last_login_day).toBe(day0);
    expect((await playerRow(p)).login_day).toBe(day0);
    // The first login: the Ice (a milestone) and the day-1 schedule card.
    expect((await grants(p)).map((g: any) => [g.key, g.kind, g.card_id])).toEqual([["first_login", "milestone", DROPS.logins.first], ["login_day_1", "login", "ice"]]);
    // The same day again: nothing moves.
    await pass(p, t(0) + 3600_000);
    expect((await progress(p)).login_days).toBe(1);
    // Skip a day: day 2 still counts as the SECOND login day (cumulative), day 3 brings the next card.
    await pass(p, t(2));
    expect((await progress(p)).login_days).toBe(2);
    await pass(p, t(4));
    pr = await progress(p);
    expect(pr.login_days).toBe(3);
    expect((await grants(p)).map((g: any) => g.key)).toContain("login_day_3");
    expect(nextLoginCard(3)).toBe(7);
    expect(nextLoginCard(30)).toBe(0);
  });

  it("a welcome-back card waits after a long gap", async () => {
    const p = await register();
    const day0 = dayOf(Date.now());
    await pass(p, day0 * DAY_MS + 1000);
    const back = (day0 + DROPS.logins.welcome_back_days) * DAY_MS + 1000;
    await pass(p, back);
    const keys = (await grants(p)).map((g: any) => g.key);
    expect(keys).toContain(`welcome_back_${day0 + DROPS.logins.welcome_back_days}`);
    expect(loginGrants(5, day0, day0 + 2).some((g) => g.kind === "welcome_back")).toBe(false);
  });

  it("runs from an authenticated request once the player's last_seen is stale", async () => {
    const p = await register();
    await env.DB.prepare("UPDATE players SET last_seen = 0 WHERE id = ?1").bind(p.playerId).run();
    const res = await SELF.fetch("https://api/v1/me", { headers: auth(p) });
    expect(res.status).toBe(200);
    for (let i = 0; i < 30 && !(await progress(p)); i++) await new Promise((r) => setTimeout(r, 25));
    expect((await progress(p))?.login_days).toBe(1);
  });
});

describe("GET /v1/rewards and the CLAIM", () => {
  it("lists what waits, the unlocked milestones, the meter and its odds; a claim moves one card, once", async () => {
    const p = await register(3);
    await pass(p, Date.now());
    const r = await rewards(p);
    expect(r.status).toBe(200);
    expect(r.json.pending.map((g: any) => g.key)).toEqual(["first_login", "login_day_1"]);
    expect(r.json.unlocked).toEqual(["first_login"]);
    expect(r.json.all_milestones).toEqual(allMilestoneKeys());
    expect(r.json.login_days).toBe(1);
    expect(r.json.meter).toMatchObject({ progress: 0, size: METER_SIZE });
    expect(r.json.meter.odds.common).toBeCloseTo(0.8163, 3); // rookie at level 3: ice + fire7
    expect(r.json.loss_streak).toBe(0);
    expect(r.json.next_login_card).toBe(3);
    const c = await claim(p, "first_login");
    expect(c.status).toBe(200);
    expect(c.json.claimed).toBe("first_login");
    expect(c.json.card).toBe("ice");
    expect(c.json.inventory).toEqual({ ice: 1 });
    expect((await claim(p, "first_login")).status).toBe(409);
    expect((await claim(p, "nope")).status).toBe(404);
    const again = await rewards(p);
    expect(again.json.pending.map((g: any) => g.key)).toEqual(["login_day_1"]);
    const n = await env.DB.prepare("SELECT COUNT(*) AS n FROM online_ledger WHERE player_id = ?1 AND kind = 'milestone'").bind(p.playerId).first<any>();
    expect(n.n).toBe(1);
  });

  it("GET /v1/me carries the milestone keys and the pending count", async () => {
    const p = await register();
    await pass(p, Date.now());
    const m = await me(p);
    expect(m.milestones).toEqual(["first_login"]);
    expect(m.pending).toBe(2);
  });

  it("the kill switch closes the rewards routes", async () => {
    const p = await register();
    const saved = (env as any).FEATURE_DROPS;
    (env as any).FEATURE_DROPS = "off";
    try {
      expect((await rewards(p)).status).toBe(503);
      expect((await claim(p, "x")).status).toBe(503);
    } finally {
      (env as any).FEATURE_DROPS = saved;
    }
  });
});
