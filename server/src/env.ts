/** The Workers Rate Limiting binding (periods of 10 or 60 s). */
export interface RateLimiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface Env {
  DB: D1Database;
  /** Kill switches: anything but "on" answers 503 and the game treats it as offline. */
  FEATURE_SUBMIT?: string;
  FEATURE_BOARD?: string;
  FEATURE_TRANSFER?: string;
  FEATURE_SAVE?: string;
  FEATURE_MATCH?: string;
  /** Per-IP wall on every /v1 route (layer 2: a workers.dev host has no WAF). */
  RL_IP?: RateLimiter;
  /** Per-player minute buckets; absent locally, where limits.ts falls back to memory. */
  RL_SCORES?: RateLimiter;
  RL_BOARD?: RateLimiter;
  RL_ME?: RateLimiter;
  RL_SAVE?: RateLimiter;
  RL_MATCH?: RateLimiter;
  /** Phase 3: one MatchRoom per 1v1, one Lobby for the game. */
  ROOM: DurableObjectNamespace;
  LOBBY: DurableObjectNamespace;
}

export interface PlayerRow {
  id: string;
  secret_hash: string;
  name: string;
  tag: string;
  client_id: string;
  created_at: number;
  last_seen: number;
  flags: number;
}
