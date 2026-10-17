import type { Context, Next } from "hono";
import type { Env, PlayerRow } from "./env";
import { UUID_RE } from "./rules";

export async function sha256Hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** `Authorization: Bearer <playerId>.<secret>` → the two halves, or null. */
export function parseBearer(header: string | undefined): { playerId: string; secret: string } | null {
  if (!header || !header.startsWith("Bearer ")) return null;
  const token = header.slice(7).trim();
  const dot = token.indexOf(".");
  if (dot < 0) return null;
  const playerId = token.slice(0, dot);
  const secret = token.slice(dot + 1);
  if (!UUID_RE.test(playerId) || secret.length < 16 || secret.length > 128) return null;
  return { playerId, secret };
}

// ---- per-device secrets (migration 0005) ------------------------------------------------
// A player holds up to MAX_SECRETS secrets, one per device: registration makes
// the first, a platform restore ADDS one (the other phone stays signed in), the
// transfer code REPLACES them all (a move), unlink/delete revoke.

export const MAX_SECRETS = 5;

interface SecretRow { secret_hash: string; created_at: number; last_seen: number }

export async function secretsOf(db: D1Database, playerId: string): Promise<SecretRow[]> {
  const r = await db.prepare("SELECT secret_hash, created_at, last_seen FROM player_secrets WHERE player_id = ?1 ORDER BY created_at ASC").bind(playerId).all<SecretRow>();
  return r.results ?? [];
}

/** The stored row whose hash matches, scanning every row (constant-time per row). */
export function matchSecret(rows: SecretRow[], hash: string): SecretRow | null {
  let found: SecretRow | null = null;
  for (const r of rows) if (timingSafeEqual(hash, r.secret_hash)) found = r;
  return found;
}

/** Add a secret for a device; past MAX_SECRETS the oldest goes. Returns the statements for a batch. */
export function addSecretStatements(db: D1Database, playerId: string, hash: string, label: string, now: number, held: number): D1PreparedStatement[] {
  const out: D1PreparedStatement[] = [];
  if (held >= MAX_SECRETS) {
    out.push(db.prepare(
      "DELETE FROM player_secrets WHERE player_id = ?1 AND secret_hash IN (SELECT secret_hash FROM player_secrets WHERE player_id = ?1 ORDER BY created_at ASC LIMIT ?2)",
    ).bind(playerId, held - MAX_SECRETS + 1));
  }
  out.push(db.prepare(
    "INSERT OR REPLACE INTO player_secrets (player_id, secret_hash, created_at, last_seen, label) VALUES (?1, ?2, ?3, ?3, ?4)",
  ).bind(playerId, hash, now, label));
  return out;
}

/** The transfer claim: every other device's secret dies, this one is the only one. */
export function replaceSecretsStatements(db: D1Database, playerId: string, hash: string, label: string, now: number): D1PreparedStatement[] {
  return [
    db.prepare("DELETE FROM player_secrets WHERE player_id = ?1").bind(playerId),
    db.prepare("INSERT INTO player_secrets (player_id, secret_hash, created_at, last_seen, label) VALUES (?1, ?2, ?3, ?3, ?4)").bind(playerId, hash, now, label),
    db.prepare("UPDATE players SET secret_hash = ?1 WHERE id = ?2").bind(hash, playerId),
  ];
}

const SEEN_EVERY_MS = 3600_000;

type Vars = { Bindings: Env; Variables: { player: PlayerRow } };

/** Loads the player for a bearer token, 401 otherwise; touches last_seen hourly at most. */
export async function authenticate(c: Context<Vars>, next: Next) {
  const parsed = parseBearer(c.req.header("authorization"));
  if (!parsed) return c.json({ error: "unauthorized" }, 401);
  const row = await c.env.DB.prepare("SELECT * FROM players WHERE id = ?1").bind(parsed.playerId).first<PlayerRow>();
  if (!row) return c.json({ error: "unauthorized" }, 401);
  const hash = await sha256Hex(parsed.secret);
  const hit = matchSecret(await secretsOf(c.env.DB, row.id), hash);
  if (!hit) return c.json({ error: "unauthorized" }, 401);
  const now = Date.now();
  if (now - row.last_seen > SEEN_EVERY_MS || now - hit.last_seen > SEEN_EVERY_MS) {
    c.executionCtx.waitUntil(c.env.DB.batch([
      c.env.DB.prepare("UPDATE players SET last_seen = ?1 WHERE id = ?2").bind(now, row.id),
      c.env.DB.prepare("UPDATE player_secrets SET last_seen = ?1 WHERE player_id = ?2 AND secret_hash = ?3").bind(now, row.id, hit.secret_hash),
    ]));
  }
  c.set("player", row);
  await next();
}
