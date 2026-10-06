import type { RateLimiter } from "./env";

/**
 * Throttling, layer 3 (docs/BACKEND.md): minute buckets on the Workers Rate
 * Limiting binding when it exists (production), an in-isolate fixed window
 * when it does not (dev, tests); hour/day windows as D1 counters.
 */
export interface Verdict {
  allowed: boolean;
  retryAfter: number; // seconds
}

const memory = new Map<string, { win: number; n: number }>();

export async function minuteLimit(binding: RateLimiter | undefined, key: string, limit: number, now = Date.now()): Promise<Verdict> {
  if (binding) {
    const { success } = await binding.limit({ key });
    return { allowed: success, retryAfter: success ? 0 : 60 };
  }
  const win = Math.floor(now / 60_000);
  const cur = memory.get(key);
  const n = cur && cur.win === win ? cur.n + 1 : 1;
  memory.set(key, { win, n });
  if (memory.size > 10_000) memory.clear(); // never let the fallback grow without bound
  return { allowed: n <= limit, retryAfter: n <= limit ? 0 : 60 - (Math.floor(now / 1000) % 60) };
}

export async function longLimit(db: D1Database, key: string, limit: number, periodSec: number, now = Date.now()): Promise<Verdict> {
  const win = Math.floor(now / 1000 / periodSec);
  const row = await db
    .prepare(
      `INSERT INTO rl (key, win, n) VALUES (?1, ?2, 1)
       ON CONFLICT(key) DO UPDATE SET n = CASE WHEN rl.win = ?2 THEN rl.n + 1 ELSE 1 END, win = ?2
       RETURNING n`,
    )
    .bind(key, win)
    .first<{ n: number }>();
  const n = row?.n ?? 1;
  const until = (win + 1) * periodSec;
  return { allowed: n <= limit, retryAfter: n <= limit ? 0 : Math.max(1, until - Math.floor(now / 1000)) };
}

/** Test hook: forget the in-memory minute windows. */
export function resetMemoryLimits(): void {
  memory.clear();
}
