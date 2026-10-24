/**
 * Ranked Stage B rules (docs/BACKEND.md → Ranked → Stage B), read from the
 * game's own data/online_drops.json so the phone's mirror
 * (core/online/online_drops.gd) and this file never drift. Pure functions
 * only: the room (match_room.ts) and the rewards routes (rewards.ts) decide
 * what to write from what these return. tests/fixtures/online_drops_cases.json
 * pins the derivation and the odds on both sides.
 */
import drops from "../../data/online_drops.json";
import { CARDS, CARD_MIN_TIER } from "./cards";
import { tierIndex, compareRank, type Band, type RatingRow } from "./rank";
import { DIVISIONS, TIERS } from "./ranked_data";

export type Rarity = "common" | "rare" | "epic";
export const RARITIES: readonly Rarity[] = ["common", "rare", "epic"];

const num = (v: unknown) => Number(v);
export const DROPS = {
  weekly_card_target: num(drops.weekly_card_target),
  reference: {
    ranked_per_week: num(drops.reference.ranked_per_week),
    win_rate: num(drops.reference.win_rate),
    close_loss_share: num(drops.reference.close_loss_share),
    login_days_per_week: num(drops.reference.login_days_per_week),
    cards_played_per_match: num(drops.reference.cards_played_per_match),
  },
  meter: {
    win: num(drops.meter.win), close_loss: num(drops.meter.close_loss), loss: num(drops.meter.loss), first_win_day: num(drops.meter.first_win_day),
    close: { margin: num(drops.meter.close.margin), or_ot: Boolean(drops.meter.close.or_ot) },
  },
  rarity_by_tier: Object.fromEntries(
    Object.entries(drops.rarity_by_tier as Record<string, Record<string, number>>).map(([tier, w]) => [tier, { common: num(w.common), rare: num(w.rare), epic: num(w.epic) }]),
  ) as Record<string, Record<Rarity, number>>,
  streak_card: { losses: num(drops.streak_card.losses), card: String(drops.streak_card.card), per_day: num(drops.streak_card.per_day) },
  insurance: { losses: num(drops.insurance.losses) },
  same_opponent_cap_per_day: num(drops.same_opponent_cap_per_day),
  logins: {
    first: String(drops.logins.first),
    schedule: (drops.logins.schedule as [number, string][]).map(([d, r]) => [num(d), r as Rarity] as [number, Rarity]),
    welcome_back_days: num(drops.logins.welcome_back_days),
    welcome_back: String(drops.logins.welcome_back) as Rarity,
  },
  milestones: {
    first_login: String(drops.milestones.first_login) as Rarity,
    first_ranked_match: String(drops.milestones.first_ranked_match) as Rarity,
    first_ranked_win: String(drops.milestones.first_ranked_win) as Rarity,
    first_capture: String(drops.milestones.first_capture) as Rarity,
    tier: String(drops.milestones.tier) as Rarity,
    tier_legend: String(drops.milestones.tier_legend) as Rarity,
    division: String(drops.milestones.division) as Rarity,
    ranked_wins: Object.fromEntries(Object.entries(drops.milestones.ranked_wins as Record<string, string>).map(([n, r]) => [num(n), r as Rarity])) as Record<number, Rarity>,
  },
  shoot_around: { bonus: num(drops.shoot_around.bonus), per_day: num(drops.shoot_around.per_day), after_losses: num(drops.shoot_around.after_losses) },
  ratio_band: (drops.ratio_band as number[]).map(num) as [number, number],
};

// ---- the derivation (the ledger's numbers; the meter's size is never stored) ----------------

export interface Derived {
  points_per_match: number;
  first_win_days: number;
  points_per_week: number;
  streak_cards_per_week: number;
  meter_size: number;
  cards_in_per_match: number;
  ratio: number;
}

/**
 * From the reference player: expected meter points a week (wins, close and
 * plain losses, the first win of each day they play), the streak Ice they
 * fall into, and so the meter size that lands WEEKLY_CARD_TARGET cards a week;
 * cards in per ranked match against cards played, the ratio the test bands.
 */
export function derive(): Derived {
  const r = DROPS.reference;
  const m = DROPS.meter;
  const w = r.win_rate;
  const points_per_match = w * m.win + (1 - w) * (r.close_loss_share * m.close_loss + (1 - r.close_loss_share) * m.loss);
  const first_win_days = r.login_days_per_week * (1 - Math.pow(1 - w, r.ranked_per_week / r.login_days_per_week));
  const points_per_week = r.ranked_per_week * points_per_match + first_win_days * m.first_win_day;
  const streak_cards_per_week = r.ranked_per_week * w * Math.pow(1 - w, DROPS.streak_card.losses);
  const meter_size = Math.round(points_per_week / (DROPS.weekly_card_target - streak_cards_per_week));
  const cards_in_per_match = DROPS.weekly_card_target / r.ranked_per_week;
  return { points_per_match, first_win_days, points_per_week, streak_cards_per_week, meter_size, cards_in_per_match, ratio: cards_in_per_match / r.cards_played_per_match };
}

export const METER_SIZE = derive().meter_size;

// ---- the pool and the odds ---------------------------------------------------------------------

/** The cards a player at (tier, level) may be dealt: level and the card's minimum tier both allow it. */
export function eligibleCards(tierId: string, level: number): string[] {
  const ti = tierIndex(tierId);
  return Object.keys(CARDS)
    .filter((id) => CARDS[id].level <= level && tierIndex(CARD_MIN_TIER[id] ?? TIERS[0].id) <= ti)
    .sort();
}

/** The rarity odds shown in the game: the tier's weights over the rarities the pool holds, renormalised. */
export function rarityOdds(tierId: string, level: number): Record<Rarity, number> {
  const weights = DROPS.rarity_by_tier[tierId] ?? DROPS.rarity_by_tier[TIERS[0].id];
  const present = new Set(eligibleCards(tierId, level).map((id) => CARDS[id].rarity));
  let sum = 0;
  for (const r of RARITIES) if (present.has(r)) sum += weights[r];
  const out: Record<Rarity, number> = { common: 0, rare: 0, epic: 0 };
  if (sum <= 0) return out;
  for (const r of RARITIES) out[r] = present.has(r) ? weights[r] / sum : 0;
  return out;
}

/** mulberry32: a tiny seeded generator, so a grant replays the same. */
export function rng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** FNV-1a of a string, for a seed. */
export function hashSeed(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193); }
  return h >>> 0;
}

/** One card by the tier's rarity odds from the pool; "" when the pool is empty. */
export function rollCard(tierId: string, level: number, next: () => number): string {
  const pool = eligibleCards(tierId, level);
  if (pool.length === 0) return "";
  const odds = rarityOdds(tierId, level);
  let u = next();
  let rarity: Rarity = "common";
  for (const r of RARITIES) {
    if (u < odds[r]) { rarity = r; break; }
    u -= odds[r];
    rarity = r;
  }
  return pickOfRarity(pool, rarity, next);
}

/** A card of `rarity` from the pool (falling back down the rarities, then to anything). */
export function pickOfRarity(pool: string[], rarity: Rarity, next: () => number): string {
  const order = RARITIES.slice(0, RARITIES.indexOf(rarity) + 1).reverse();
  for (const r of order) {
    const of = pool.filter((id) => CARDS[id].rarity === r);
    if (of.length) return of[Math.floor(next() * of.length) % of.length];
  }
  return pool.length ? pool[Math.floor(next() * pool.length) % pool.length] : "";
}

// ---- the meter -----------------------------------------------------------------------------------

export interface MeterCase { won: boolean; margin: number; period: number; firstWinToday: boolean }

/** Points a ranked result adds: a win, a close loss (by ≤ margin or decided in OT), a plain loss, plus the day's first win. */
export function meterGain(c: MeterCase): number {
  const m = DROPS.meter;
  let gain: number;
  if (c.won) gain = m.win;
  else if (Math.abs(c.margin) <= m.close.margin || (m.close.or_ot && c.period > 0)) gain = m.close_loss;
  else gain = m.loss;
  if (c.won && c.firstWinToday) gain += m.first_win_day;
  return gain;
}

// ---- spoils ----------------------------------------------------------------------------------------

export type Side = "a" | "b";
export interface Spoils { captured: string[]; lost: string[]; insured: string | null }

/**
 * Who takes what: the loser's played cards go to the winner (the winner's own
 * are spent — never returned); a forfeit hands the leaver's to the one who
 * stayed; a void moves nothing. With insurance (a loser on a long streak)
 * the loser keeps ONE played card — the highest rarity, ties to the first
 * played — and the winner takes the rest.
 */
export function settleSpoils(winner: Side | null, reason: string, played: Record<Side, string[]>, insured: boolean): Record<Side, Spoils> {
  const none = (): Spoils => ({ captured: [], lost: [], insured: null });
  const out: Record<Side, Spoils> = { a: none(), b: none() };
  if (winner === null || !(reason === "played" || reason === "forfeit")) return out;
  const loser: Side = winner === "a" ? "b" : "a";
  let lost = [...played[loser]];
  let kept: string | null = null;
  if (insured && lost.length) {
    let best = 0;
    for (let i = 1; i < lost.length; i++) if (RARITIES.indexOf(CARDS[lost[i]]?.rarity as Rarity) > RARITIES.indexOf(CARDS[lost[best]]?.rarity as Rarity)) best = i;
    kept = lost[best];
    lost = lost.filter((_, i) => i !== best);
  }
  out[winner].captured = lost;
  out[loser].lost = lost;
  out[loser].insured = kept;
  return out;
}

/** The played-loss streak: a played loss counts, a win resets, the leaver's own forfeit does neither. */
export function nextLossStreak(before: number, won: boolean, reason: string, leaver: boolean): number {
  if (won) return 0;
  if (reason === "forfeit" && leaver) return before;
  return before + 1;
}

// ---- milestones ---------------------------------------------------------------------------------------

/** Every band from the first tier's lowest division up to legend, in order. */
export function bandsInOrder(): Band[] {
  const out: Band[] = [];
  for (const t of TIERS) {
    if (t.id === TIERS[TIERS.length - 1].id) { out.push({ tier: t.id, division: 1 }); continue; }
    for (let d = DIVISIONS; d >= 1; d--) out.push({ tier: t.id, division: d });
  }
  return out;
}

export interface MilestoneHit { key: string; rarity: Rarity }

/**
 * The keys a decision may unlock, by what the server itself witnessed: the
 * first ranked match / win / capture, the win counts crossed, and every
 * band between the old peak (exclusive) and the new peak (inclusive) — peak,
 * so it cannot be farmed. Idempotence is the grants table's (INSERT OR IGNORE).
 */
export function milestonesReached(before: RatingRow, after: RatingRow, won: boolean, captured: number): MilestoneHit[] {
  const hits: MilestoneHit[] = [];
  const ms = DROPS.milestones;
  if (before.games === 0) hits.push({ key: "first_ranked_match", rarity: ms.first_ranked_match });
  if (won && before.wins === 0) hits.push({ key: "first_ranked_win", rarity: ms.first_ranked_win });
  if (captured > 0) hits.push({ key: "first_capture", rarity: ms.first_capture });
  for (const n of Object.keys(ms.ranked_wins).map(Number).sort((x, y) => x - y)) {
    if (before.wins < n && after.wins >= n) hits.push({ key: `ranked_wins_${n}`, rarity: ms.ranked_wins[n] });
  }
  const oldPeak: Band = { tier: before.peak_tier, division: before.peak_division };
  const newPeak: Band = { tier: after.peak_tier, division: after.peak_division };
  if (compareRank(newPeak, oldPeak) > 0) {
    const legend = TIERS[TIERS.length - 1].id;
    for (const band of bandsInOrder()) {
      if (compareRank(band, oldPeak) <= 0 || compareRank(band, newPeak) > 0) continue;
      const lowest = band.tier === legend ? 1 : DIVISIONS;
      if (band.division === lowest) hits.push({ key: `tier_${band.tier}`, rarity: band.tier === legend ? ms.tier_legend : ms.tier });
      if (band.tier !== legend) hits.push({ key: `division_${band.tier}_${band.division}`, rarity: ms.division });
    }
  }
  return hits;
}

/** Every milestone key the game can show (the locked list on the rewards page), in display order. */
export function allMilestoneKeys(): string[] {
  const out = ["first_login", "first_ranked_match", "first_ranked_win", "first_capture"];
  for (const n of Object.keys(DROPS.milestones.ranked_wins).map(Number).sort((x, y) => x - y)) out.push(`ranked_wins_${n}`);
  const legend = TIERS[TIERS.length - 1].id;
  for (const band of bandsInOrder()) {
    const lowest = band.tier === legend ? 1 : DIVISIONS;
    if (band.division === lowest) out.push(`tier_${band.tier}`);
    if (band.tier !== legend) out.push(`division_${band.tier}_${band.division}`);
  }
  return out;
}

// ---- logins ----------------------------------------------------------------------------------------------

export interface LoginGrant { key: string; kind: "login" | "welcome_back" | "milestone"; rarity: Rarity | null; card: string | null }

/** What a new distinct login day earns: the first-login card, the schedule's card at this count, a welcome-back card after a long gap. */
export function loginGrants(loginDaysAfter: number, lastSeenDay: number, today: number): LoginGrant[] {
  const out: LoginGrant[] = [];
  const lg = DROPS.logins;
  if (loginDaysAfter === 1) out.push({ key: "first_login", kind: "milestone", rarity: null, card: lg.first });
  for (const [n, rarity] of lg.schedule) if (n === loginDaysAfter) out.push({ key: `login_day_${n}`, kind: "login", rarity, card: null });
  if (lastSeenDay > 0 && today - lastSeenDay >= lg.welcome_back_days) out.push({ key: `welcome_back_${today}`, kind: "welcome_back", rarity: lg.welcome_back, card: null });
  return out;
}
