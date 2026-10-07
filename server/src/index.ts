/**
 * Hoop Shoot API (docs/BACKEND.md): the one trusted layer between the game
 * and its data. Anonymous device accounts, per-area time-trial boards, the
 * move-to-new-phone code. Every route is throttled (limits.ts) and every
 * feature has a kill switch (503 → the game shows its device board).
 */
import { Hono } from "hono";
import type { Env, PlayerRow } from "./env";
import { authenticate, sha256Hex } from "./auth";
import { minuteLimit, longLimit, type Verdict } from "./limits";
import {
  AREAS, SCORE_FIELDS, SECRET_RE, TAG_RE, UUID_RE, normalizeName, onlyFields, plausible, validName, weekOf,
  type ScorePayload,
} from "./rules";
import { BLOCKED, randomHandle } from "./handles";
import * as db from "./db";
import { save } from "./save";
import { AREAS as MATCH_AREAS } from "./rules";
export { MatchRoom } from "./match_room";
export { Lobby } from "./lobby";

type Vars = { Bindings: Env; Variables: { player: PlayerRow } };
export const app = new Hono<Vars>();

const MAX_BODY = 4096;
const BOARD_MAX = 50;
const CODE_TTL_MS = 15 * 60_000;
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

const ip = (c: { req: { header(n: string): string | undefined } }) => c.req.header("cf-connecting-ip") ?? "local";

function throttled(c: any, v: Verdict) {
  c.header("Retry-After", String(v.retryAfter));
  return c.json({ error: "throttled", retryAfter: v.retryAfter }, 429);
}

const off = (c: any) => c.json({ error: "offline" }, 503);
const on = (flag: string | undefined) => (flag ?? "on") === "on";

/** The JSON body, at most MAX_BODY bytes, only the allowed keys; null → already answered. */
async function body(c: any, allowed: readonly string[]): Promise<Record<string, unknown> | null> {
  const text = await c.req.text();
  if (text.length > MAX_BODY) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
  const obj = parsed as Record<string, unknown>;
  return onlyFields(obj, allowed) ? obj : null;
}

/** Layer 2: IP_PER_MINUTE requests a minute per IP, before any route runs. */
export const IP_PER_MINUTE = 60;
app.use("/v1/*", async (c, next) => {
  const lim = await minuteLimit(c.env.RL_IP, `ip:${ip(c)}`, IP_PER_MINUTE);
  if (!lim.allowed) return throttled(c, lim);
  await next();
});

app.get("/v1/health", (c) => c.json({ ok: true }));

// ---- accounts --------------------------------------------------------------------

app.post("/v1/register", async (c) => {
  const lim = await longLimit(c.env.DB, `reg:ip:${ip(c)}`, 5, 3600);
  if (!lim.allowed) return throttled(c, lim);
  const b = await body(c, ["playerId", "secret", "clientId", "name", "tag"]);
  if (!b) return c.json({ error: "bad_request" }, 400);
  const { playerId, secret, clientId } = b as Record<string, string>;
  if (typeof playerId !== "string" || !UUID_RE.test(playerId)) return c.json({ error: "playerId" }, 400);
  if (typeof secret !== "string" || !SECRET_RE.test(secret)) return c.json({ error: "secret" }, 400);
  if (typeof clientId !== "string" || !UUID_RE.test(clientId)) return c.json({ error: "clientId" }, 400);
  const hash = await sha256Hex(secret);
  const existing = await c.env.DB.prepare("SELECT * FROM players WHERE id = ?1").bind(playerId).first<PlayerRow>();
  if (existing) {
    if (existing.secret_hash !== hash) return c.json({ error: "forbidden" }, 403);
    return c.json({ playerId, name: existing.name, tag: existing.tag, created: false });
  }
  let handle = randomHandle();
  if (typeof b.name === "string") {
    const name = normalizeName(b.name);
    if (validName(name, BLOCKED)) handle.name = name;
  }
  if (typeof b.tag === "string" && TAG_RE.test(b.tag)) handle.tag = b.tag;
  const now = Date.now();
  await c.env.DB.prepare(
    "INSERT INTO players (id, secret_hash, name, tag, client_id, created_at, last_seen) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)",
  )
    .bind(playerId, hash, handle.name, handle.tag, clientId, now)
    .run();
  return c.json({ playerId, name: handle.name, tag: handle.tag, created: true });
});

app.get("/v1/me", authenticate, async (c) => {
  const p = c.get("player");
  const lim = await minuteLimit(c.env.RL_ME, `me:${p.id}`, 5);
  if (!lim.allowed) return throttled(c, lim);
  return c.json({ playerId: p.id, name: p.name, tag: p.tag });
});

app.patch("/v1/me", authenticate, async (c) => {
  const p = c.get("player");
  const lim = await minuteLimit(c.env.RL_ME, `me:${p.id}`, 5);
  if (!lim.allowed) return throttled(c, lim);
  const b = await body(c, ["name"]);
  if (!b || typeof b.name !== "string") return c.json({ error: "bad_request" }, 400);
  const name = normalizeName(b.name);
  if (!validName(name, BLOCKED)) return c.json({ error: "name" }, 400);
  await c.env.DB.prepare("UPDATE players SET name = ?1 WHERE id = ?2").bind(name, p.id).run();
  return c.json({ playerId: p.id, name, tag: p.tag });
});

// ---- scores + boards --------------------------------------------------------------

app.post("/v1/scores", authenticate, async (c) => {
  if (!on(c.env.FEATURE_SUBMIT)) return off(c);
  const p = c.get("player");
  const minute = await minuteLimit(c.env.RL_SCORES, `scores:${p.id}`, 6);
  if (!minute.allowed) return throttled(c, minute);
  const day = await longLimit(c.env.DB, `scores:day:${p.id}`, 120, 86_400);
  if (!day.allowed) return throttled(c, day);
  const b = await body(c, SCORE_FIELDS);
  if (!b) return c.json({ error: "bad_request" }, 400);
  const now = Date.now();
  const why = plausible(b as Partial<ScorePayload>, now);
  if (why) return c.json({ error: "implausible", field: why }, 400);
  const s = b as unknown as ScorePayload;
  const week = weekOf(s.playedAt);
  const seen = await c.env.DB.prepare("INSERT OR IGNORE INTO seen_runs (run_id, player_id, seen_at) VALUES (?1, ?2, ?3)")
    .bind(s.runId, p.id, now)
    .run();
  const fresh = (seen.meta.changes ?? 0) > 0;
  let improved = false;
  if (fresh) {
    improved = await db.upsertBest(c.env.DB, p.id, s);
    await db.upsertWeekBest(c.env.DB, p.id, week, s);
  }
  const best = await db.myBest(c.env.DB, p.id, s.area);
  const wbest = await db.myWeekBest(c.env.DB, p.id, s.area, weekOf(now));
  const rank = best ? await db.rankAllTime(c.env.DB, s.area, best.score, best.played_at) : null;
  const weekRank = wbest ? await db.rankWeek(c.env.DB, s.area, weekOf(now), wbest.score, wbest.played_at) : null;
  return c.json({ accepted: fresh, duplicate: !fresh, improved, best: best?.score ?? null, rank, weekRank });
});

app.get("/v1/leaderboard", authenticate, async (c) => {
  if (!on(c.env.FEATURE_BOARD)) return off(c);
  const p = c.get("player");
  const lim = await minuteLimit(c.env.RL_BOARD, `board:${p.id}`, 20);
  if (!lim.allowed) return throttled(c, lim);
  const area = c.req.query("area") ?? "cage";
  if (!(AREAS as readonly string[]).includes(area)) return c.json({ error: "area" }, 400);
  const period = c.req.query("period") === "week" ? "week" : "all";
  const limit = Math.min(BOARD_MAX, Math.max(1, Number.parseInt(c.req.query("limit") ?? String(BOARD_MAX), 10) || BOARD_MAX));
  const now = Date.now();
  const week = weekOf(now);
  const rows = period === "week" ? await db.boardWeek(c.env.DB, area, week, limit) : await db.boardAllTime(c.env.DB, area, limit);
  const mine = period === "week" ? await db.myWeekBest(c.env.DB, p.id, area, week) : await db.myBest(c.env.DB, p.id, area);
  const myRank = mine
    ? period === "week"
      ? await db.rankWeek(c.env.DB, area, week, mine.score, mine.played_at)
      : await db.rankAllTime(c.env.DB, area, mine.score, mine.played_at)
    : null;
  return c.json({
    area,
    period,
    week,
    rows: rows.map((r, i) => ({ rank: i + 1, name: r.name, tag: r.tag, score: r.score, playedAt: r.played_at, me: r.player_id === p.id })),
    me: mine ? { rank: myRank, score: mine.score, name: p.name, tag: p.tag } : null,
  });
});

// ---- move to a new phone --------------------------------------------------------------

app.post("/v1/transfer/code", authenticate, async (c) => {
  if (!on(c.env.FEATURE_TRANSFER)) return off(c);
  const p = c.get("player");
  const lim = await longLimit(c.env.DB, `xfer:code:${p.id}`, 3, 3600);
  if (!lim.allowed) return throttled(c, lim);
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  const code = [...bytes].map((x) => CODE_ALPHABET[x % CODE_ALPHABET.length]).join("");
  const expiresAt = Date.now() + CODE_TTL_MS;
  await c.env.DB.batch([
    c.env.DB.prepare("DELETE FROM transfer_codes WHERE player_id = ?1").bind(p.id),
    c.env.DB.prepare("INSERT INTO transfer_codes (code, player_id, expires_at) VALUES (?1, ?2, ?3)").bind(code, p.id, expiresAt),
  ]);
  return c.json({ code, expiresAt });
});

app.post("/v1/transfer/claim", async (c) => {
  if (!on(c.env.FEATURE_TRANSFER)) return off(c);
  const lim = await longLimit(c.env.DB, `xfer:claim:ip:${ip(c)}`, 5, 3600);
  if (!lim.allowed) return throttled(c, lim);
  const b = await body(c, ["code", "newSecret"]);
  if (!b || typeof b.code !== "string" || typeof b.newSecret !== "string") return c.json({ error: "bad_request" }, 400);
  if (!SECRET_RE.test(b.newSecret)) return c.json({ error: "secret" }, 400);
  const code = b.code.toUpperCase().replace(/[^A-Z0-9]/g, "");
  const row = await c.env.DB.prepare("SELECT * FROM transfer_codes WHERE code = ?1").bind(code).first<{ code: string; player_id: string; expires_at: number }>();
  if (!row) return c.json({ error: "not_found" }, 404);
  if (row.expires_at < Date.now()) {
    await c.env.DB.prepare("DELETE FROM transfer_codes WHERE code = ?1").bind(code).run();
    return c.json({ error: "expired" }, 410);
  }
  const hash = await sha256Hex(b.newSecret);
  await c.env.DB.batch([
    c.env.DB.prepare("UPDATE players SET secret_hash = ?1 WHERE id = ?2").bind(hash, row.player_id),
    c.env.DB.prepare("DELETE FROM transfer_codes WHERE player_id = ?1").bind(row.player_id),
  ]);
  const p = await c.env.DB.prepare("SELECT id, name, tag FROM players WHERE id = ?1").bind(row.player_id).first<PlayerRow>();
  if (!p) return c.json({ error: "not_found" }, 404);
  return c.json({ playerId: p.id, name: p.name, tag: p.tag });
});

// ---- the cloud save mirror (save.ts) ----------------------------------------------------
app.route("/v1/save", save);

// ---- 1v1 rooms (match_room.ts, lobby.ts) ---------------------------------------------------

const MATCH_PER_MINUTE = 20;
const MATCH_PER_DAY = 200;
const ROOM_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

app.use("/v1/match/*", authenticate, async (c, next) => {
  if (!on(c.env.FEATURE_MATCH)) return off(c);
  const p = c.get("player");
  const minute = await minuteLimit(c.env.RL_MATCH, `match:${p.id}`, MATCH_PER_MINUTE);
  if (!minute.allowed) return throttled(c, minute);
  const day = await longLimit(c.env.DB, `match:day:${p.id}`, MATCH_PER_DAY, 86_400);
  if (!day.allowed) return throttled(c, day);
  await next();
});

/** Quick match / make a code / join a code / leave the queue: the Lobby decides. */
app.post("/v1/match/:action{quick|code|join|leave}", async (c) => {
  const p = c.get("player");
  const b = await body(c, ["area", "code"]);
  if (!b) return c.json({ error: "bad_request" }, 400);
  const area = typeof b.area === "string" ? b.area : "cage";
  if (!(MATCH_AREAS as readonly string[]).includes(area)) return c.json({ error: "area" }, 400);
  const action = c.req.param("action");
  if (action === "join" && typeof b.code !== "string") return c.json({ error: "code" }, 400);
  const stub = c.env.LOBBY.get(c.env.LOBBY.idFromName("lobby"));
  const res = await stub.fetch(`https://lobby/${action}`, {
    method: "POST",
    body: JSON.stringify({ playerId: p.id, area, code: b.code ?? "" }),
  });
  return new Response(res.body, { status: res.status, headers: { "content-type": "application/json" } });
});

/** The room's WebSocket: authenticated here, the player handed on in headers. */
app.get("/v1/match/room/:id", async (c) => {
  if (c.req.header("upgrade")?.toLowerCase() !== "websocket") return c.json({ error: "websocket" }, 426);
  const id = c.req.param("id");
  if (!ROOM_RE.test(id)) return c.json({ error: "room" }, 400);
  const p = c.get("player");
  const area = c.req.query("area") ?? "cage";
  if (!(MATCH_AREAS as readonly string[]).includes(area)) return c.json({ error: "area" }, 400);
  const headers = new Headers(c.req.raw.headers);
  headers.set("x-player-id", p.id);
  headers.set("x-player-name", p.name);
  headers.set("x-player-tag", p.tag);
  headers.set("x-area", area);
  headers.set("x-room", id);
  headers.delete("authorization");
  const stub = c.env.ROOM.get(c.env.ROOM.idFromName(id));
  return stub.fetch(new Request(c.req.raw.url, { headers, method: "GET" }));
});

app.notFound((c) => c.json({ error: "not_found" }, 404));
app.onError((err, c) => {
  console.error(err);
  return c.json({ error: "server" }, 500);
});

export default {
  fetch: app.fetch,
  async scheduled(_ctrl: ScheduledController, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(db.prune(env.DB, Date.now()));
  },
};
