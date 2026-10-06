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

const SEEN_EVERY_MS = 3600_000;

type Vars = { Bindings: Env; Variables: { player: PlayerRow } };

/** Loads the player for a bearer token, 401 otherwise; touches last_seen hourly at most. */
export async function authenticate(c: Context<Vars>, next: Next) {
  const parsed = parseBearer(c.req.header("authorization"));
  if (!parsed) return c.json({ error: "unauthorized" }, 401);
  const row = await c.env.DB.prepare("SELECT * FROM players WHERE id = ?1").bind(parsed.playerId).first<PlayerRow>();
  if (!row) return c.json({ error: "unauthorized" }, 401);
  const hash = await sha256Hex(parsed.secret);
  if (!timingSafeEqual(hash, row.secret_hash)) return c.json({ error: "unauthorized" }, 401);
  const now = Date.now();
  if (now - row.last_seen > SEEN_EVERY_MS) {
    c.executionCtx.waitUntil(c.env.DB.prepare("UPDATE players SET last_seen = ?1 WHERE id = ?2").bind(now, row.id).run());
  }
  c.set("player", row);
  await next();
}
