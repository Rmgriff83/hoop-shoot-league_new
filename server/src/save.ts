/**
 * The cloud save mirror (docs/BACKEND.md → Phase 2): gzipped whole-part
 * snapshots of the game's save parts, one row per player per part, merged
 * part-level last-writer-wins on the part's own updatedAt. The server never
 * reads inside a part — it is bytes with a timestamp.
 */
import { Hono } from "hono";
import type { Env, PlayerRow } from "./env";
import { authenticate } from "./auth";
import { minuteLimit, longLimit } from "./limits";

/** Parts that sync. `account` (the secret) and `tuning` (a dev scratchpad) never do. */
export const SYNC_PARTS = ["time_trial_scores", "cosmetics", "settings", "campaign", "liveGames", "cards", "progress"] as const;
/** Gzipped bytes per part; the biggest real part (50 heats) is a few KB. */
export const PART_MAX_BYTES = 256 * 1024;
/** A part stamped further ahead of our clock than this is a broken phone clock. */
export const FUTURE_SLACK_MS = 24 * 3600 * 1000;
export const SAVE_PER_MINUTE = 30;
export const SAVE_PER_DAY = 400;

type Vars = { Bindings: Env; Variables: { player: PlayerRow } };
export const save = new Hono<Vars>();

const isPart = (p: string): p is (typeof SYNC_PARTS)[number] => (SYNC_PARTS as readonly string[]).includes(p);
const isGzip = (b: Uint8Array) => b.length >= 18 && b[0] === 0x1f && b[1] === 0x8b;

function throttled(c: any, retryAfter: number) {
  c.header("Retry-After", String(retryAfter));
  return c.json({ error: "throttled", retryAfter }, 429);
}

save.use("/*", authenticate, async (c, next) => {
  if ((c.env.FEATURE_SAVE ?? "on") !== "on") return c.json({ error: "offline" }, 503);
  const p = c.get("player");
  const minute = await minuteLimit(c.env.RL_SAVE, `save:${p.id}`, SAVE_PER_MINUTE);
  if (!minute.allowed) return throttled(c, minute.retryAfter);
  const day = await longLimit(c.env.DB, `save:day:${p.id}`, SAVE_PER_DAY, 86_400);
  if (!day.allowed) return throttled(c, day.retryAfter);
  await next();
});

/** The manifest: what the server holds for this player, by part. */
save.get("/", async (c) => {
  const p = c.get("player");
  const res = await c.env.DB.prepare("SELECT part, updated_at, size FROM save_parts WHERE player_id = ?1").bind(p.id).all<{ part: string; updated_at: number; size: number }>();
  const parts: Record<string, { updatedAt: number; size: number }> = {};
  for (const r of res.results) parts[r.part] = { updatedAt: r.updated_at, size: r.size };
  return c.json({ parts, now: Date.now() });
});

/** One part's bytes, with its stamp in X-Updated-At. */
save.get("/:part", async (c) => {
  const p = c.get("player");
  const part = c.req.param("part");
  if (!isPart(part)) return c.json({ error: "part" }, 400);
  const row = await c.env.DB.prepare("SELECT updated_at, body FROM save_parts WHERE player_id = ?1 AND part = ?2").bind(p.id, part).first<{ updated_at: number; body: ArrayBuffer | number[] }>();
  if (!row) return c.json({ error: "not_found" }, 404);
  const bytes = row.body instanceof ArrayBuffer ? new Uint8Array(row.body) : Uint8Array.from(row.body);
  return new Response(bytes, {
    headers: { "content-type": "application/gzip", "x-updated-at": String(row.updated_at), "cache-control": "no-store" },
  });
});

/**
 * Store a part when it is newer than what we hold (last writer wins on the
 * part's updatedAt); 409 with the stored stamp when ours is newer or equal,
 * so the phone pulls instead.
 */
save.put("/:part", async (c) => {
  const p = c.get("player");
  const part = c.req.param("part");
  if (!isPart(part)) return c.json({ error: "part" }, 400);
  const updatedAt = Number.parseInt(c.req.header("x-updated-at") ?? "", 10);
  const now = Date.now();
  if (!Number.isInteger(updatedAt) || updatedAt <= 0 || updatedAt > now + FUTURE_SLACK_MS) return c.json({ error: "updatedAt" }, 400);
  const declared = Number.parseInt(c.req.header("content-length") ?? "0", 10);
  if (declared > PART_MAX_BYTES) return c.json({ error: "too_large", max: PART_MAX_BYTES }, 413);
  const bytes = new Uint8Array(await c.req.arrayBuffer());
  if (bytes.length > PART_MAX_BYTES) return c.json({ error: "too_large", max: PART_MAX_BYTES }, 413);
  if (!isGzip(bytes)) return c.json({ error: "not_gzip" }, 400);
  const res = await c.env.DB.prepare(
    `INSERT INTO save_parts (player_id, part, updated_at, size, body, stored_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
     ON CONFLICT(player_id, part) DO UPDATE SET
       updated_at = excluded.updated_at, size = excluded.size, body = excluded.body, stored_at = excluded.stored_at
     WHERE excluded.updated_at > save_parts.updated_at`,
  )
    .bind(p.id, part, updatedAt, bytes.length, bytes, now)
    .run();
  if ((res.meta.changes ?? 0) > 0) return c.json({ stored: true, updatedAt, now });
  const held = await c.env.DB.prepare("SELECT updated_at FROM save_parts WHERE player_id = ?1 AND part = ?2").bind(p.id, part).first<{ updated_at: number }>();
  return c.json({ stored: false, updatedAt: held?.updated_at ?? null, now }, 409);
});
