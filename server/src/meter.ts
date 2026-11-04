/**
 * Cost meter (docs/BACKEND.md → What a match costs): plain counters of the
 * billable writes the match path makes — Durable Object storage rows
 * (`put`, `deleteAll`, `setAlarm`) and D1 write statements — so
 * `test/cost.test.ts` can pin a whole match's cost and a later change cannot
 * quietly bring the per-message write back. In production they are integers
 * nobody reads; the Worker, the Lobby and the rooms share one isolate in the
 * Vitest pool, so the test reads what every piece counted.
 */
export const meter = { doPut: 0, doDelete: 0, doAlarm: 0, d1: 0 };

export function resetMeter(): void {
  meter.doPut = 0;
  meter.doDelete = 0;
  meter.doAlarm = 0;
  meter.d1 = 0;
}

/** A copy of the counters as they stand. */
export function readMeter(): { doPut: number; doDelete: number; doAlarm: number; d1: number } {
  return { ...meter };
}
