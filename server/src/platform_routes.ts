/**
 * /v1/link — bind a platform identity (Game Center, Play Games) to the
 * anonymous account, restore an account from one on a new phone, or unlink.
 * Behind FEATURE_PLATFORM; throttled like the transfer routes; bodies ≤ 4 KB
 * and only the listed fields. Accounts are never merged: an identity already
 * on another player answers 409 with that account's name/tag/level and the
 * game asks the player which account to keep.
 */
import { Hono } from "hono";
import type { Env, PlayerRow } from "./env";
import { addSecretStatements, authenticate, secretsOf, sha256Hex } from "./auth";
import { longLimit, type Verdict } from "./limits";
import { SECRET_RE, onlyFields } from "./rules";
import { BadProof, NotImplemented, isProvider, verifierFor } from "./platform";

type Vars = { Bindings: Env; Variables: { player: PlayerRow } };
export const link = new Hono<Vars>();

const MAX_BODY = 4096;
const ip = (c: { req: { header(n: string): string | undefined } }) => c.req.header("cf-connecting-ip") ?? "local";
const on = (flag: string | undefined) => (flag ?? "on") === "on";

function throttled(c: any, v: Verdict) {
  c.header("Retry-After", String(v.retryAfter));
  return c.json({ error: "throttled", retryAfter: v.retryAfter }, 429);
}

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

interface IdentityRow { provider: string; subject: string; player_id: string; linked_at: number; meta: string | null }

/** Runs the provider's verifier; on failure answers and returns null. */
async function verified(c: any, provider: unknown, proof: unknown) {
  if (!isProvider(provider)) return { res: c.json({ error: "provider" }, 400), id: null };
  const v = verifierFor(c.env, provider);
  if (!v) return { res: c.json({ error: "provider" }, 400), id: null };
  try {
    return { res: null, id: await v.verify(proof) };
  } catch (e) {
    if (e instanceof NotImplemented) return { res: c.json({ error: "not_implemented", provider }, 501), id: null };
    if (e instanceof BadProof) return { res: c.json({ error: "proof_rejected" }, 401), id: null };
    throw e;
  }
}

link.use("/*", async (c, next) => {
  if (!on(c.env.FEATURE_PLATFORM)) return c.json({ error: "offline" }, 503);
  await next();
});

// POST /v1/link {provider, proof} — bind to the caller.
link.post("/", authenticate, async (c) => {
  const p = c.get("player");
  const lim = await longLimit(c.env.DB, `plat:link:${p.id}`, 5, 3600);
  if (!lim.allowed) return throttled(c, lim);
  const b = await body(c, ["provider", "proof"]);
  if (!b || typeof b.provider !== "string" || b.proof === undefined) return c.json({ error: "bad_request" }, 400);
  const { res, id } = await verified(c, b.provider, b.proof);
  if (!id) return res;
  const provider = b.provider;
  const held = await c.env.DB.prepare("SELECT * FROM player_identities WHERE provider = ?1 AND subject = ?2").bind(provider, id.subject).first<IdentityRow>();
  if (held && held.player_id === p.id) return c.json({ linked: true, provider, already: true });
  if (held) {
    // Someone else's account: never merged — the game offers to switch to it.
    const other = await c.env.DB.prepare("SELECT name, tag, level FROM players WHERE id = ?1").bind(held.player_id).first<PlayerRow>();
    if (other) return c.json({ error: "conflict", provider, name: other.name, tag: other.tag, level: other.level ?? 1 }, 409);
    // The row outlived its player (should not happen: deletion clears it); take it over.
    await c.env.DB.prepare("DELETE FROM player_identities WHERE provider = ?1 AND subject = ?2").bind(provider, id.subject).run();
  }
  const meta = id.meta || id.displayName ? JSON.stringify({ ...(id.meta ?? {}), ...(id.displayName ? { displayName: id.displayName } : {}) }) : null;
  // One identity per provider per player: a re-link with another subject replaces the old one.
  await c.env.DB.batch([
    c.env.DB.prepare("DELETE FROM player_identities WHERE player_id = ?1 AND provider = ?2").bind(p.id, provider),
    c.env.DB.prepare("INSERT INTO player_identities (provider, subject, player_id, linked_at, meta) VALUES (?1, ?2, ?3, ?4, ?5)").bind(provider, id.subject, p.id, Date.now(), meta),
  ]);
  return c.json({ linked: true, provider });
});

// POST /v1/link/restore {provider, proof, newSecret} — a new phone joins a linked account.
link.post("/restore", async (c) => {
  const lim = await longLimit(c.env.DB, `plat:restore:ip:${ip(c)}`, 5, 3600);
  if (!lim.allowed) return throttled(c, lim);
  const b = await body(c, ["provider", "proof", "newSecret"]);
  if (!b || typeof b.provider !== "string" || b.proof === undefined || typeof b.newSecret !== "string") return c.json({ error: "bad_request" }, 400);
  if (!SECRET_RE.test(b.newSecret)) return c.json({ error: "secret" }, 400);
  const { res, id } = await verified(c, b.provider, b.proof);
  if (!id) return res;
  const held = await c.env.DB.prepare("SELECT * FROM player_identities WHERE provider = ?1 AND subject = ?2").bind(b.provider, id.subject).first<IdentityRow>();
  if (!held) return c.json({ error: "not_found" }, 404);
  const player = await c.env.DB.prepare("SELECT id, name, tag FROM players WHERE id = ?1").bind(held.player_id).first<PlayerRow>();
  if (!player) return c.json({ error: "not_found" }, 404);
  const hash = await sha256Hex(b.newSecret);
  const count = (await secretsOf(c.env.DB, player.id)).length;
  // ADDS a device secret: the phone that linked stays signed in (per-device secrets).
  await c.env.DB.batch(addSecretStatements(c.env.DB, player.id, hash, b.provider, Date.now(), count));
  return c.json({ playerId: player.id, name: player.name, tag: player.tag });
});

// DELETE /v1/link/:provider — unlink (idempotent).
link.delete("/:provider{gamecenter|playgames|test}", authenticate, async (c) => {
  const p = c.get("player");
  const lim = await longLimit(c.env.DB, `plat:unlink:${p.id}`, 5, 3600);
  if (!lim.allowed) return throttled(c, lim);
  const provider = c.req.param("provider");
  await c.env.DB.prepare("DELETE FROM player_identities WHERE player_id = ?1 AND provider = ?2").bind(p.id, provider).run();
  return c.json({ linked: false, provider });
});

/** The providers linked to a player, for GET /v1/me. */
export async function providersOf(db: D1Database, playerId: string): Promise<string[]> {
  const r = await db.prepare("SELECT provider FROM player_identities WHERE player_id = ?1 ORDER BY provider").bind(playerId).all<{ provider: string }>();
  return (r.results ?? []).map((x) => x.provider);
}

/** Account deletion (Apple 5.1.1(v)): every row keyed on the player, in one batch. */
export function deleteAccountStatements(db: D1Database, playerId: string): D1PreparedStatement[] {
  return [
    "DELETE FROM player_identities WHERE player_id = ?1",
    "DELETE FROM player_secrets WHERE player_id = ?1",
    "DELETE FROM transfer_codes WHERE player_id = ?1",
    "DELETE FROM save_parts WHERE player_id = ?1",
    "DELETE FROM tt_best WHERE player_id = ?1",
    "DELETE FROM tt_week_best WHERE player_id = ?1",
    "DELETE FROM seen_runs WHERE player_id = ?1",
    "DELETE FROM online_wallet WHERE player_id = ?1",
    "DELETE FROM online_cards WHERE player_id = ?1",
    "DELETE FROM online_ledger WHERE player_id = ?1",
    "DELETE FROM players WHERE id = ?1",
  ].map((sql) => db.prepare(sql).bind(playerId));
}
