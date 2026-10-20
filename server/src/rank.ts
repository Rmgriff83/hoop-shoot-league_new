/**
 * The visible rank (docs/BACKEND.md → Ranked): a conservative rating
 * (mu − rd_k·rd) maps to a tier and a division; a promotion earns a shield,
 * the peak tier is a floor. Mirrored by hand in the game
 * (tests/fixtures/ranked_ladder.json is the shared truth).
 */
import { inflate, periodsBetween, rateOne } from "./glicko";
import { DIVISIONS, GLICKO, RD_K, SHIELD, TIERS } from "./ranked_data";

export interface Band { tier: string; division: number }

/** The `ratings` table row (migrations/0007_ranked.sql). */
export interface RatingRow {
  player_id: string;
  mu: number;
  rd: number;
  vol: number;
  cons: number;
  games: number;
  wins: number;
  losses: number;
  win_streak: number;
  loss_streak: number;
  tier: string;
  division: number;
  peak_tier: string;
  peak_division: number;
  shield_left: number;
  updated_at: number;
}

export const conservative = (mu: number, rd: number): number => mu - RD_K * rd;

export function tierIndex(id: string): number {
  const i = TIERS.findIndex((t) => t.id === id);
  return i < 0 ? 0 : i;
}

/** Tier then division; > 0 when a outranks b. */
export function compareRank(a: Band, b: Band): number {
  const dt = tierIndex(a.tier) - tierIndex(b.tier);
  if (dt !== 0) return dt;
  return b.division - a.division; // division 1 is the top
}

/** Where a conservative rating sits: below the first tier is its lowest division; legend is always I. */
export function bandOf(cons: number): Band {
  let i = 0;
  for (let k = 0; k < TIERS.length; k++) if (cons >= TIERS[k].from) i = k;
  const tier = TIERS[i];
  if (i === TIERS.length - 1) return { tier: tier.id, division: 1 };
  if (cons < tier.from) return { tier: tier.id, division: DIVISIONS };
  const width = (TIERS[i + 1].from - tier.from) / DIVISIONS;
  const step = Math.floor((cons - tier.from) / width);
  return { tier: tier.id, division: Math.max(1, Math.min(DIVISIONS, DIVISIONS - step)) };
}

export function defaultRow(playerId: string, now: number): RatingRow {
  const cons = conservative(GLICKO.mu0, GLICKO.rd0);
  const band = bandOf(cons);
  return {
    player_id: playerId, mu: GLICKO.mu0, rd: GLICKO.rd0, vol: GLICKO.vol0, cons,
    games: 0, wins: 0, losses: 0, win_streak: 0, loss_streak: 0,
    tier: band.tier, division: band.division, peak_tier: band.tier, peak_division: band.division,
    shield_left: 0, updated_at: now,
  };
}

/** A row's deviation as it stands now, widened by the time since its last match. */
export function currentRd(row: RatingRow, now: number): number {
  return inflate(row.rd, row.vol, periodsBetween(row.updated_at, now));
}

export interface Applied {
  row: RatingRow;
  events: string[];
  before: { mu: number; rd: number; cons: number };
  after: { mu: number; rd: number; cons: number };
}

/**
 * One ranked match for `row` against `opp` (the opponent's rating BEFORE its
 * own update, rd already widened for idle time). Void and desync never come
 * here; a forfeit is a loss for the leaver and a win for the stayer.
 */
export function applyResult(row: RatingRow, opp: { mu: number; rd: number }, outcome: "win" | "loss", now: number): Applied {
  const events: string[] = [];
  const before = { mu: row.mu, rd: row.rd, cons: row.cons };
  // 1. Idle inflation, then the Glicko-2 period with this one result.
  const rated = rateOne({ mu: row.mu, rd: currentRd(row, now), vol: row.vol }, opp, outcome === "win" ? 1 : 0);
  const out: RatingRow = { ...row, mu: rated.mu, rd: rated.rd, vol: rated.vol, updated_at: now };
  // 2. The tallies.
  out.games += 1;
  if (outcome === "win") { out.wins += 1; out.win_streak += 1; out.loss_streak = 0; }
  else { out.losses += 1; out.loss_streak += 1; out.win_streak = 0; }
  // 3. The visible rank: up at once (with a shield), down only past the shield and never under the peak tier.
  out.cons = conservative(out.mu, out.rd);
  const cand = bandOf(out.cons);
  const cur: Band = { tier: out.tier, division: out.division };
  const peak: Band = { tier: out.peak_tier, division: out.peak_division };
  const cmp = compareRank(cand, cur);
  let promoted = false;
  if (cmp > 0) {
    out.tier = cand.tier; out.division = cand.division;
    out.shield_left = SHIELD;
    promoted = true;
    events.push("promoted");
    if (compareRank(cand, peak) > 0) { out.peak_tier = cand.tier; out.peak_division = cand.division; }
  } else if (cmp < 0) {
    if (out.shield_left > 0) {
      events.push("shielded");
    } else if (tierIndex(cand.tier) < tierIndex(out.peak_tier)) {
      const floor: Band = { tier: out.peak_tier, division: DIVISIONS };
      if (compareRank(floor, cur) !== 0) { out.tier = floor.tier; out.division = floor.division; events.push("floored"); }
    } else {
      out.tier = cand.tier; out.division = cand.division;
      events.push("demoted");
    }
  }
  if (!promoted) out.shield_left = Math.max(0, out.shield_left - 1);
  return { row: out, events, before, after: { mu: out.mu, rd: out.rd, cons: out.cons } };
}
