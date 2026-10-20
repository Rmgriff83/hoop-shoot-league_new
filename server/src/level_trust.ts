/**
 * How far a phone's reported level is believed (docs/BACKEND.md → Ranked):
 * it never goes down, and it may not outrun what an account could have
 * earned in its lifetime — grace levels plus so many an hour since creation.
 */
import { LEVEL_TRUST } from "./ranked_data";

export function acceptLevel(current: number, reported: unknown, createdAt: number, now: number): number {
  if (!Number.isInteger(reported) || (reported as number) < 1 || (reported as number) > LEVEL_TRUST.max_level) return current;
  const hours = Math.max(0, now - createdAt) / 3_600_000;
  const cap = Math.min(LEVEL_TRUST.max_level, 1 + LEVEL_TRUST.grace_levels + Math.floor(hours * LEVEL_TRUST.max_levels_per_hour));
  return Math.max(current, Math.min(reported as number, cap));
}
