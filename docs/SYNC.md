# Local → Cloud Sync

Superseded 2026-10-06 by `docs/BACKEND.md` (Cloudflare Workers + D1, anonymous
device accounts, per-area leaderboards, the 1v1 plan). What survives from the
original design: local-first (`user://save/` is the truth while playing),
UUIDv4 ids and `updatedAt` on every doc and part, the persisted outbox
(`SaveService.mark_dirty` / `dirty_parts`, now also `pendingScores`), whole-part
gzipped snapshots for the phase-2 save mirror, and the rule that leaderboard
submission and part sync never share a code path.
