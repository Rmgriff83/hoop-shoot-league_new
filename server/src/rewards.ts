/**
 * Ranked Stage B bookkeeping (docs/BACKEND.md → Ranked → Stage B): the
 * per-player `online_progress` row, the `grants` waiting for a CLAIM, the
 * once-a-day login pass, and the rewards routes' bodies. Every card here is
 * one the server witnessed earning: a login day it counted, a milestone its
 * own ratings crossed, a meter its own match results filled. Nothing is
 * bought (docs/ECONOMY.md → The rule).
 */
import { inventoryOf, type Inventory } from "./cards";
import { dayOf } from "./days";
import type { PlayerRow } from "./env";
import { DROPS, METER_SIZE, allMilestoneKeys, hashSeed, loginGrants, pickOfRarity, eligibleCards, rarityOdds, rng, rollCard, type Rarity } from "./online_drops";
import { ratingOf } from "./db";
import { TIERS } from "./ranked_data";

export interface Progress {
  player_id: string;
  meter: number;
  login_days: number;
  last_login_day: number;
  last_seen_day: number;
  first_win_day: number;
  loss_streak_played: number;
  streak_card_day: number;
  updated_at: number;
}

export const defaultProgress = (playerId: string): Progress => ({
  player_id: playerId, meter: 0, login_days: 0, last_login_day: 0, last_seen_day: 0, first_win_day: 0, loss_streak_played: 0, streak_card_day: 0, updated_at: 0,
});

export async function progressOf(db: D1Database, playerId: string): Promise<Progress> {
  const row = await db.prepare("SELECT * FROM online_progress WHERE player_id = ?1").bind(playerId).first<Progress>();
  return row ?? defaultProgress(playerId);
}

/** The whole row, one statement (for a batch with the match row). */
export function upsertProgressStatement(db: D1Database, p: Progress): D1PreparedStatement {
  return db
    .prepare(
      `INSERT INTO online_progress (player_id, meter, login_days, last_login_day, last_seen_day, first_win_day, loss_streak_played, streak_card_day, updated_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
       ON CONFLICT(player_id) DO UPDATE SET
         meter = excluded.meter, login_days = excluded.login_days, last_login_day = excluded.last_login_day, last_seen_day = excluded.last_seen_day,
         first_win_day = excluded.first_win_day, loss_streak_played = excluded.loss_streak_played, streak_card_day = excluded.streak_card_day, updated_at = excluded.updated_at`,
    )
    .bind(p.player_id, p.meter, p.login_days, p.last_login_day, p.last_seen_day, p.first_win_day, p.loss_streak_played, p.streak_card_day, p.updated_at);
}

/** A card into the ledger: one more copy, and the books say why. */
export function cardStatements(db: D1Database, playerId: string, cardId: string, kind: string, room: string | null, now: number): D1PreparedStatement[] {
  return [
    db.prepare("INSERT INTO online_cards (player_id, card_id, n) VALUES (?1, ?2, 1) ON CONFLICT(player_id, card_id) DO UPDATE SET n = n + 1").bind(playerId, cardId),
    db.prepare("INSERT INTO online_ledger (player_id, kind, card_id, coins, room, at) VALUES (?1, ?2, ?3, 0, ?4, ?5)").bind(playerId, kind, cardId, room, now),
  ];
}

/** A grant waiting for its CLAIM; a second insert of the same key does nothing (meta.changes 0). */
export function grantStatement(db: D1Database, playerId: string, key: string, kind: string, cardId: string, now: number): D1PreparedStatement {
  return db.prepare("INSERT OR IGNORE INTO grants (player_id, key, kind, card_id, granted_at) VALUES (?1, ?2, ?3, ?4, ?5)").bind(playerId, key, kind, cardId, now);
}

/** The tier a player's cards are rolled at: the ratings row's, or the first. */
export async function tierOf(db: D1Database, playerId: string): Promise<string> {
  const r = await ratingOf(db, playerId);
  return r?.tier ?? TIERS[0].id;
}

/** A card of `rarity` for a player at (tier, level), from a seeded roll. */
export function cardOfRarity(tier: string, level: number, rarity: Rarity, seed: string): string {
  return pickOfRarity(eligibleCards(tier, level), rarity, rng(hashSeed(seed)));
}

/**
 * A new distinct UTC login day (auth.ts calls this once a day per player,
 * off the request): count it, hand out what the schedule says, and remember
 * the day. Cumulative days, never a streak.
 */
export async function loginDay(db: D1Database, player: PlayerRow, now: number): Promise<void> {
  const today = dayOf(now);
  const [p, tier] = await Promise.all([progressOf(db, player.id), tierOf(db, player.id)]);
  if (p.last_login_day === today) return;
  const after = p.login_days + 1;
  const stmts: D1PreparedStatement[] = [];
  for (const g of loginGrants(after, p.last_seen_day, today)) {
    const card = g.card ?? cardOfRarity(tier, player.level ?? 1, g.rarity ?? "common", `${player.id}:${g.key}`);
    if (card) stmts.push(grantStatement(db, player.id, g.key, g.kind, card, now));
  }
  p.login_days = after;
  p.last_login_day = today;
  p.last_seen_day = today;
  p.updated_at = now;
  stmts.push(upsertProgressStatement(db, p));
  stmts.push(db.prepare("UPDATE players SET login_day = ?1 WHERE id = ?2").bind(today, player.id));
  await db.batch(stmts);
}

export interface GrantRow { key: string; kind: string; card_id: string; granted_at: number; claimed_at: number | null }

export async function grantsOf(db: D1Database, playerId: string): Promise<GrantRow[]> {
  const r = await db.prepare("SELECT key, kind, card_id, granted_at, claimed_at FROM grants WHERE player_id = ?1 ORDER BY granted_at ASC, key ASC").bind(playerId).all<GrantRow>();
  return r.results ?? [];
}

/** GET /v1/rewards: what waits for a CLAIM, what is unlocked, the meter and its odds, the login count. */
export async function rewardsOf(db: D1Database, player: PlayerRow) {
  const [p, grants, rating] = await Promise.all([progressOf(db, player.id), grantsOf(db, player.id), ratingOf(db, player.id)]);
  const tier = rating?.tier ?? TIERS[0].id;
  const level = player.level ?? 1;
  return {
    pending: grants.filter((g) => g.claimed_at === null).map((g) => ({ key: g.key, kind: g.kind, card: g.card_id, granted_at: g.granted_at })),
    unlocked: grants.filter((g) => g.kind === "milestone").map((g) => g.key),
    all_milestones: allMilestoneKeys(),
    login_days: p.login_days,
    meter: { progress: p.meter, size: METER_SIZE, odds: rarityOdds(tier, level) },
    loss_streak: p.loss_streak_played,
    tier,
    next_login_card: nextLoginCard(p.login_days),
  };
}

/** The next schedule day above the count (0 when the schedule is spent). */
export function nextLoginCard(loginDays: number): number {
  for (const [n] of DROPS.logins.schedule) if (n > loginDays) return n;
  return 0;
}

export type ClaimResult = { ok: true; card: string; inventory: Inventory } | { ok: false; status: 404 | 409 };

/** POST /v1/rewards/claim: the grant becomes a card in the ledger, once. */
export async function claim(db: D1Database, player: PlayerRow, key: string, now: number): Promise<ClaimResult> {
  const g = await db.prepare("SELECT key, kind, card_id, granted_at, claimed_at FROM grants WHERE player_id = ?1 AND key = ?2").bind(player.id, key).first<GrantRow>();
  if (!g) return { ok: false, status: 404 };
  if (g.claimed_at !== null) return { ok: false, status: 409 };
  await db.batch([
    db.prepare("UPDATE grants SET claimed_at = ?1 WHERE player_id = ?2 AND key = ?3 AND claimed_at IS NULL").bind(now, player.id, key),
    ...cardStatements(db, player.id, g.card_id, g.kind, null, now),
  ]);
  return { ok: true, card: g.card_id, inventory: await inventoryOf(db, player.id) };
}

/** A fresh card for a full meter or the streak, rolled by the player's tier and level. */
export function meterCard(tier: string, level: number, seed: string): string {
  return rollCard(tier, level, rng(hashSeed(seed)));
}
