import type { ScorePayload } from "./rules";

export interface BestRow {
  player_id: string;
  area: string;
  score: number;
  makes: number;
  attempts: number;
  swishes: number;
  best_streak: number;
  played_at: number;
  run_id: string;
  name?: string;
  tag?: string;
}

/** 1 + the rows strictly better: higher score, or the same score played earlier. */
export async function rankAllTime(db: D1Database, area: string, score: number, playedAt: number): Promise<number> {
  const row = await db
    .prepare("SELECT COUNT(*) AS n FROM tt_best WHERE area = ?1 AND (score > ?2 OR (score = ?2 AND played_at < ?3))")
    .bind(area, score, playedAt)
    .first<{ n: number }>();
  return (row?.n ?? 0) + 1;
}

export async function rankWeek(db: D1Database, area: string, week: number, score: number, playedAt: number): Promise<number> {
  const row = await db
    .prepare(
      "SELECT COUNT(*) AS n FROM tt_week_best WHERE area = ?1 AND week = ?2 AND (score > ?3 OR (score = ?3 AND played_at < ?4))",
    )
    .bind(area, week, score, playedAt)
    .first<{ n: number }>();
  return (row?.n ?? 0) + 1;
}

export async function boardAllTime(db: D1Database, area: string, limit: number): Promise<BestRow[]> {
  const res = await db
    .prepare(
      `SELECT b.*, p.name, p.tag FROM tt_best b JOIN players p ON p.id = b.player_id
       WHERE b.area = ?1 ORDER BY b.score DESC, b.played_at ASC LIMIT ?2`,
    )
    .bind(area, limit)
    .all<BestRow>();
  return res.results;
}

export async function boardWeek(db: D1Database, area: string, week: number, limit: number): Promise<BestRow[]> {
  const res = await db
    .prepare(
      `SELECT b.*, p.name, p.tag FROM tt_week_best b JOIN players p ON p.id = b.player_id
       WHERE b.area = ?1 AND b.week = ?2 ORDER BY b.score DESC, b.played_at ASC LIMIT ?3`,
    )
    .bind(area, week, limit)
    .all<BestRow>();
  return res.results;
}

export async function myBest(db: D1Database, playerId: string, area: string): Promise<BestRow | null> {
  return db.prepare("SELECT * FROM tt_best WHERE player_id = ?1 AND area = ?2").bind(playerId, area).first<BestRow>();
}

export async function myWeekBest(db: D1Database, playerId: string, area: string, week: number): Promise<BestRow | null> {
  return db
    .prepare("SELECT * FROM tt_week_best WHERE player_id = ?1 AND area = ?2 AND week = ?3")
    .bind(playerId, area, week)
    .first<BestRow>();
}

/** Writes only when the run beats the stored best (fewer D1 writes; worse runs cost nothing). */
export async function upsertBest(db: D1Database, playerId: string, p: ScorePayload): Promise<boolean> {
  const res = await db
    .prepare(
      `INSERT INTO tt_best (player_id, area, score, makes, attempts, swishes, best_streak, played_at, run_id)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
       ON CONFLICT(player_id, area) DO UPDATE SET
         score = excluded.score, makes = excluded.makes, attempts = excluded.attempts, swishes = excluded.swishes,
         best_streak = excluded.best_streak, played_at = excluded.played_at, run_id = excluded.run_id
       WHERE excluded.score > tt_best.score OR (excluded.score = tt_best.score AND excluded.played_at < tt_best.played_at)`,
    )
    .bind(playerId, p.area, p.score, p.makes, p.attempts, p.swishes, p.bestStreak, p.playedAt, p.runId)
    .run();
  return (res.meta.changes ?? 0) > 0;
}

export async function upsertWeekBest(db: D1Database, playerId: string, week: number, p: ScorePayload): Promise<boolean> {
  const res = await db
    .prepare(
      `INSERT INTO tt_week_best (player_id, area, week, score, makes, attempts, swishes, best_streak, played_at, run_id)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
       ON CONFLICT(player_id, area, week) DO UPDATE SET
         score = excluded.score, makes = excluded.makes, attempts = excluded.attempts, swishes = excluded.swishes,
         best_streak = excluded.best_streak, played_at = excluded.played_at, run_id = excluded.run_id
       WHERE excluded.score > tt_week_best.score OR (excluded.score = tt_week_best.score AND excluded.played_at < tt_week_best.played_at)`,
    )
    .bind(playerId, p.area, week, p.score, p.makes, p.attempts, p.swishes, p.bestStreak, p.playedAt, p.runId)
    .run();
  return (res.meta.changes ?? 0) > 0;
}

/** Nightly housekeeping: old run ids, dead codes, stale counters, weeks nobody looks at. */
export async function prune(db: D1Database, now: number): Promise<void> {
  const day = 86_400_000;
  await db.batch([
    db.prepare("DELETE FROM seen_runs WHERE seen_at < ?1").bind(now - 30 * day),
    db.prepare("DELETE FROM transfer_codes WHERE expires_at < ?1").bind(now),
    db.prepare("DELETE FROM rl WHERE win < ?1").bind(Math.floor(now / 1000 / 86_400) - 2),
    db.prepare("DELETE FROM tt_week_best WHERE played_at < ?1").bind(now - 8 * 7 * day),
    db.prepare("DELETE FROM online_ledger WHERE at < ?1").bind(now - 90 * day),
  ]);
}
