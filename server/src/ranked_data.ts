/**
 * Ranked online numbers (docs/BACKEND.md → Ranked), read from the game's own
 * data/ranked.json so the phone and the server never drift. Nothing numeric
 * about ranked play lives anywhere else in this code.
 */
import ranked from "../../data/ranked.json";

export interface Tier { id: string; name: string; from: number }

export const GLICKO = {
  mu0: Number(ranked.glicko.mu0),
  rd0: Number(ranked.glicko.rd0),
  vol0: Number(ranked.glicko.vol0),
  tau: Number(ranked.glicko.tau),
  rd_max: Number(ranked.glicko.rd_max),
  period_days: Number(ranked.glicko.period_days),
};
export const RD_K = Number(ranked.conservative.rd_k);
/** Lowest first; the last one (legend) shows the global position instead of a division. */
export const TIERS: readonly Tier[] = (ranked.tiers as Tier[]).map((t) => ({ id: String(t.id), name: String(t.name), from: Number(t.from) }));
export const DIVISIONS = Number(ranked.divisions);
export const SHIELD = Number(ranked.shield_matches);
export const QUEUE = {
  window0: Number(ranked.queue.window0),
  step: Number(ranked.queue.step),
  step_s: Number(ranked.queue.step_s),
  cap_s: Number(ranked.queue.cap_s),
  poll_s: Number(ranked.queue.poll_s),
  ttl_s: Number(ranked.queue.ttl_s),
  lean: {
    losses: Number(ranked.queue.lean.losses),
    away_days: Number(ranked.queue.lean.away_days),
    below: Number(ranked.queue.lean.below),
  },
};
export const PREMATCH = { seconds: Number(ranked.prematch.seconds), grace_s: Number(ranked.prematch.grace_s), countdown_s: Number((ranked.prematch as any).countdown_s ?? 10) };
export const LEVEL_TRUST = {
  max_levels_per_hour: Number(ranked.level_trust.max_levels_per_hour),
  grace_levels: Number(ranked.level_trust.grace_levels),
  max_level: Number(ranked.level_trust.max_level),
};
export const BOARD = { top: Number(ranked.board.top), cache_s: Number(ranked.board.cache_s) };
export const TICKETS = { win: Number(ranked.tickets.win), loss: Number(ranked.tickets.loss) };
