/**
 * Pure rules shared (by hand) with the game: core/net/score_payload.gd mirrors
 * `plausible` and tests/test_score_payload.gd asserts the same verdicts, so a
 * change here is a change there.
 */
export const AREAS = ["cage", "beach", "city"] as const;
export type Area = (typeof AREAS)[number];

/** A time trial is 60 s with a ball return; nobody gets more shots off than this. */
export const MAX_ATTEMPTS = 80;
/** The hottest make pays 4 + 1 for the swish (core/match/streak_rules.gd). */
export const MAX_POINTS_PER_MAKE = 5;
/** A run's playedAt may sit this far from the server clock (offline outbox, phone clocks). */
export const PLAYED_AT_SLACK_MS = 2 * 24 * 3600 * 1000;
export const NAME_MIN = 3;
export const NAME_MAX = 24;
export const NAME_RE = /^[A-Z0-9]+( [A-Z0-9]+)*$/;
export const TAG_RE = /^[0-9]{2}$/;
export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
export const SECRET_RE = /^[A-Za-z0-9_-]{32,96}$/;

export interface ScorePayload {
  runId: string;
  area: string;
  score: number;
  makes: number;
  attempts: number;
  swishes: number;
  bestStreak: number;
  bonus: number;
  iced: number;
  playedAt: number;
  version: string;
}

export const SCORE_FIELDS = [
  "runId", "area", "score", "makes", "attempts", "swishes", "bestStreak", "bonus", "iced", "playedAt", "version",
] as const;

const isCount = (v: unknown): v is number => Number.isInteger(v) && (v as number) >= 0;

/** The reason a payload is not a real run, or null when it passes. */
export function plausible(p: Partial<ScorePayload>, now: number): string | null {
  if (typeof p.runId !== "string" || !UUID_RE.test(p.runId)) return "runId";
  if (typeof p.area !== "string" || !(AREAS as readonly string[]).includes(p.area)) return "area";
  for (const k of ["score", "makes", "attempts", "swishes", "bestStreak", "bonus", "iced"] as const) {
    if (!isCount(p[k])) return k;
  }
  if (typeof p.version !== "string" || p.version.length > 32) return "version";
  if (!isCount(p.playedAt)) return "playedAt";
  const s = p as ScorePayload;
  if (s.attempts > MAX_ATTEMPTS) return "attempts";
  if (s.makes > s.attempts) return "makes";
  if (s.swishes > s.makes) return "swishes";
  if (s.bestStreak > s.makes) return "bestStreak";
  if (s.score > s.makes * MAX_POINTS_PER_MAKE) return "score";
  if (s.bonus > s.score) return "bonus";
  if (Math.abs(s.playedAt - now) > PLAYED_AT_SLACK_MS) return "playedAt";
  return null;
}

/** Weeks since Monday 1970-01-05 UTC, so every week starts on a Monday. */
export function weekOf(ms: number): number {
  return Math.floor((Math.floor(ms / 86_400_000) - 4) / 7);
}

/** Upper-case, single spaces, trimmed — what the player typed, tidied. */
export function normalizeName(raw: string): string {
  return raw.trim().toUpperCase().replace(/\s+/g, " ");
}

export function validName(name: string, blocked: readonly string[]): boolean {
  if (name.length < NAME_MIN || name.length > NAME_MAX || !NAME_RE.test(name)) return false;
  const tokens = name.split(" ");
  const squashed = name.replace(/ /g, "");
  for (const b of blocked) {
    if (tokens.includes(b)) return false;
    if (b.length >= 5 && squashed.includes(b)) return false;
  }
  return true;
}

/** Only the listed keys, nothing else — a stray field is a 400, not a shrug. */
export function onlyFields(body: Record<string, unknown>, allowed: readonly string[]): boolean {
  return Object.keys(body).every((k) => allowed.includes(k));
}
