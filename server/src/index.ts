/**
 * Hoop Shoot API (docs/BACKEND.md): the one trusted layer between the game
 * and its data. Anonymous device accounts, per-area time-trial boards, the
 * move-to-new-phone code, the 1v1 rooms and the ranked ladder. Every route
 * is throttled (limits.ts) and every feature has a kill switch (503 → the
 * game shows its device board).
 */
import { Hono } from "hono";
import { claim, grantsOf, rewardsOf } from "./rewards";
import type { Env, PlayerRow } from "./env";
import { authenticate, matchSecret, replaceSecretsStatements, secretsOf, sha256Hex } from "./auth";
import { deleteAccountStatements, link, providersOf } from "./platform_routes";
import { minuteLimit, longLimit, type Verdict } from "./limits";
import {
  AREAS, SCORE_FIELDS, SECRET_RE, TAG_RE, UUID_RE, normalizeName, onlyFields, plausible, validName, weekOf,
  type ScorePayload,
} from "./rules";
import { BLOCKED, randomHandle } from "./handles";
import * as db from "./db";
import { save } from "./save";
import { AREAS as MATCH_AREAS } from "./rules";
import { cleanTown } from "./towns";
export { MatchRoom } from "./match_room";
export { Lobby } from "./lobby";
import { inventoryOf } from "./cards";
import { acceptLevel } from "./level_trust";
import { areasForLevel } from "./rules";
import { defaultRow, type RatingRow } from "./rank";
import { BOARD, LEVEL_TRUST, QUEUE, TIERS } from "./ranked_data";

type Vars = { Bindings: Env; Variables: { player: PlayerRow; cardsGated: boolean } };
export const app = new Hono<Vars>();

const MAX_BODY = 4096;
const BOARD_MAX = 50;
const CODE_TTL_MS = 15 * 60_000;
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

const ip = (c: { req: { header(n: string): string | undefined } }) => c.req.header("cf-connecting-ip") ?? "local";

function throttled(c: any, v: Verdict) {
  c.header("Retry-After", String(v.retryAfter));
  return c.json({ error: "throttled", retryAfter: v.retryAfter }, 429);
}

const off = (c: any) => c.json({ error: "offline" }, 503);
const on = (flag: string | undefined) => (flag ?? "on") === "on";

/** The JSON body, at most MAX_BODY bytes, only the allowed keys; null → already answered. */
async function body(c: any, allowed: readonly string[]): Promise<Record<string, unknown> | null> {
  const text = await c.req.text();
  if (text.length > MAX_BODY) return null;
  let parsed: unknown;
  try {
    parsed = text === "" ? {} : JSON.parse(text);
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
  const obj = parsed as Record<string, unknown>;
  return onlyFields(obj, allowed) ? obj : null;
}

/** Layer 2: IP_PER_MINUTE requests a minute per IP, before any route runs. */
export const IP_PER_MINUTE = 60;
app.use("/v1/*", async (c, next) => {
  const lim = await minuteLimit(c.env.RL_IP, `ip:${ip(c)}`, IP_PER_MINUTE);
  if (!lim.allowed) return throttled(c, lim);
  await next();
});

app.get("/v1/health", (c) => c.json({ ok: true }));

// ---- accounts --------------------------------------------------------------------

app.post("/v1/register", async (c) => {
  const lim = await longLimit(c.env.DB, `reg:ip:${ip(c)}`, 5, 3600);
  if (!lim.allowed) return throttled(c, lim);
  const b = await body(c, ["playerId", "secret", "clientId", "name", "tag", "level"]);
  if (!b) return c.json({ error: "bad_request" }, 400);
  const { playerId, secret, clientId } = b as Record<string, string>;
  if (typeof playerId !== "string" || !UUID_RE.test(playerId)) return c.json({ error: "playerId" }, 400);
  if (typeof secret !== "string" || !SECRET_RE.test(secret)) return c.json({ error: "secret" }, 400);
  if (typeof clientId !== "string" || !UUID_RE.test(clientId)) return c.json({ error: "clientId" }, 400);
  const hash = await sha256Hex(secret);
  const existing = await c.env.DB.prepare("SELECT * FROM players WHERE id = ?1").bind(playerId).first<PlayerRow>();
  if (existing) {
    // A known id with a secret this player holds (any device) is a repeat; any other secret is a stranger.
    if (!matchSecret(await secretsOf(c.env.DB, playerId), hash)) return c.json({ error: "forbidden" }, 403);
    return c.json({ playerId, name: existing.name, tag: existing.tag, created: false });
  }
  let handle = randomHandle();
  if (typeof b.name === "string") {
    const name = normalizeName(b.name);
    if (validName(name, BLOCKED)) handle.name = name;
  }
  if (typeof b.tag === "string" && TAG_RE.test(b.tag)) handle.tag = b.tag;
  const now = Date.now();
  // The level the phone claims, trusted only as far as a brand-new account could have earned (level_trust.ts).
  const level = validLevel(b.level) ? acceptLevel(1, b.level, now, now) : 1;
  await c.env.DB.batch([
    c.env.DB.prepare(
      "INSERT INTO players (id, secret_hash, name, tag, client_id, created_at, last_seen, level) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6, ?7)",
    ).bind(playerId, hash, handle.name, handle.tag, clientId, now, level),
    c.env.DB.prepare("INSERT INTO player_secrets (player_id, secret_hash, created_at, last_seen, label) VALUES (?1, ?2, ?3, ?3, 'first')").bind(playerId, hash, now),
  ]);
  return c.json({ playerId, name: handle.name, tag: handle.tag, created: true });
});

app.get("/v1/me", authenticate, async (c) => {
  const p = c.get("player");
  const lim = await minuteLimit(c.env.RL_ME, `me:${p.id}`, 5);
  if (!lim.allowed) return throttled(c, lim);
  const [providers, rating, grants] = await Promise.all([providersOf(c.env.DB, p.id), db.ratingOf(c.env.DB, p.id), grantsOf(c.env.DB, p.id)]);
  return c.json({
    playerId: p.id, name: p.name, tag: p.tag, level: p.level ?? 1, providers, rank: rating ? await rankOf(c.env.DB, rating) : null,
    // Stage B: the milestone keys the server has witnessed (the Platform facade's mirror) and what waits for a CLAIM.
    milestones: grants.filter((g) => g.kind === "milestone").map((g) => g.key),
    pending: grants.filter((g) => g.claimed_at === null).length,
  });
});

/** The rank line the game shows (me.rank): legend carries its world position instead of a division. */
async function rankOf(d: D1Database, r: RatingRow) {
  const out: Record<string, unknown> = { tier: r.tier, division: r.division, games: r.games, wins: r.wins, losses: r.losses, cons: r.cons };
  if (r.tier === LEGEND) out.position = await db.rankedPosition(d, r.cons, r.updated_at);
  return out;
}
const LEGEND = TIERS[TIERS.length - 1].id;

/**
 * Account deletion (Apple 5.1.1(v): an app that creates accounts — ours does,
 * silently — must let the player delete it in-app, data and all). No kill
 * switch: the owner can always leave. Match history keeps the room rows (the
 * other player's record of the game). Afterwards the bearer is dead and the
 * game wipes its local save and mints a fresh identity on the next launch.
 */
app.delete("/v1/me", authenticate, async (c) => {
  const p = c.get("player");
  const perIp = await longLimit(c.env.DB, `me:del:ip:${ip(c)}`, 3, 3600);
  if (!perIp.allowed) return throttled(c, perIp);
  const perPlayer = await longLimit(c.env.DB, `me:del:${p.id}`, 2, 3600);
  if (!perPlayer.allowed) return throttled(c, perPlayer);
  await c.env.DB.batch(deleteAccountStatements(c.env.DB, p.id));
  return c.json({ deleted: true });
});

/** The game's level (docs/PROGRESSION.md), reported so the online card cap can hold; believed as far as level_trust.ts allows. */
const validLevel = (v: unknown): v is number => Number.isInteger(v) && (v as number) >= 1 && (v as number) <= LEVEL_TRUST.max_level;

app.patch("/v1/me", authenticate, async (c) => {
  const p = c.get("player");
  const lim = await minuteLimit(c.env.RL_ME, `me:${p.id}`, 5);
  if (!lim.allowed) return throttled(c, lim);
  const b = await body(c, ["name", "level"]);
  if (!b || (b.name === undefined && b.level === undefined)) return c.json({ error: "bad_request" }, 400);
  let name = p.name;
  if (b.name !== undefined) {
    if (typeof b.name !== "string") return c.json({ error: "name" }, 400);
    name = normalizeName(b.name);
    if (!validName(name, BLOCKED)) return c.json({ error: "name" }, 400);
  }
  let level = p.level ?? 1;
  if (b.level !== undefined) {
    if (!validLevel(b.level)) return c.json({ error: "level" }, 400);
    level = acceptLevel(level, b.level, p.created_at, Date.now()); // lowered or capped is not an error: the answer says what held
  }
  await c.env.DB.prepare("UPDATE players SET name = ?1, level = ?2 WHERE id = ?3").bind(name, level, p.id).run();
  return c.json({ playerId: p.id, name, tag: p.tag, level });
});

// ---- cards online (cards.ts): the ledger the rooms trust ---------------------------------------

const CARDS_PER_MINUTE = 20;
const CARDS_PER_DAY = 200;

const cardsGate = async (c: any, next: any) => {
  if (c.get("cardsGated")) return next(); // both /v1/cards and /v1/cards/* match the bare path
  c.set("cardsGated", true);
  if (!on(c.env.FEATURE_CARDS)) return off(c);
  const p = c.get("player");
  const minute = await minuteLimit(c.env.RL_CARDS, `cards:${p.id}`, CARDS_PER_MINUTE);
  if (!minute.allowed) return throttled(c, minute);
  const day = await longLimit(c.env.DB, `cards:day:${p.id}`, CARDS_PER_DAY, 86_400);
  if (!day.allowed) return throttled(c, day);
  await next();
};
app.use("/v1/cards", authenticate, cardsGate);
app.use("/v1/cards/*", authenticate, cardsGate);

/** Your online inventory and level. */
app.get("/v1/cards", async (c) => {
  const p = c.get("player");
  return c.json(await inventoryOf(c.env.DB, p.id));
});

// ---- rewards (rewards.ts, docs/BACKEND.md → Ranked → Stage B) ----------------------------------

const dropsGate = async (c: any, next: any) => {
  if (!on(c.env.FEATURE_DROPS)) return off(c);
  const p = c.get("player");
  const minute = await minuteLimit(c.env.RL_CARDS, `cards:${p.id}`, CARDS_PER_MINUTE);
  if (!minute.allowed) return throttled(c, minute);
  await next();
};
app.use("/v1/rewards", authenticate, dropsGate);
app.use("/v1/rewards/*", authenticate, dropsGate);

/** What waits for a CLAIM, what is unlocked, the meter and its odds, the login count. */
app.get("/v1/rewards", async (c) => {
  const p = c.get("player");
  return c.json(await rewardsOf(c.env.DB, p));
});

/** A pending grant becomes a card in the ledger, once; answers the inventory so the phone refreshes in one call. */
app.post("/v1/rewards/claim", async (c) => {
  const p = c.get("player");
  const b = await body(c, ["key"]);
  if (!b || typeof b.key !== "string" || b.key.length > 64) return c.json({ error: "bad_request" }, 400);
  const r = await claim(c.env.DB, p, b.key, Date.now());
  if (!r.ok) return c.json({ error: r.status === 404 ? "not_found" : "claimed" }, r.status);
  return c.json({ claimed: b.key, card: r.card, ...r.inventory });
});

// ---- scores + boards --------------------------------------------------------------

app.post("/v1/scores", authenticate, async (c) => {
  if (!on(c.env.FEATURE_SUBMIT)) return off(c);
  const p = c.get("player");
  const minute = await minuteLimit(c.env.RL_SCORES, `scores:${p.id}`, 6);
  if (!minute.allowed) return throttled(c, minute);
  const day = await longLimit(c.env.DB, `scores:day:${p.id}`, 120, 86_400);
  if (!day.allowed) return throttled(c, day);
  const b = await body(c, SCORE_FIELDS);
  if (!b) return c.json({ error: "bad_request" }, 400);
  const now = Date.now();
  const why = plausible(b as Partial<ScorePayload>, now);
  if (why) return c.json({ error: "implausible", field: why }, 400);
  const s = b as unknown as ScorePayload;
  const week = weekOf(s.playedAt);
  const seen = await c.env.DB.prepare("INSERT OR IGNORE INTO seen_runs (run_id, player_id, seen_at) VALUES (?1, ?2, ?3)")
    .bind(s.runId, p.id, now)
    .run();
  const fresh = (seen.meta.changes ?? 0) > 0;
  let improved = false;
  if (fresh) {
    improved = await db.upsertBest(c.env.DB, p.id, s);
    await db.upsertWeekBest(c.env.DB, p.id, week, s);
  }
  const best = await db.myBest(c.env.DB, p.id, s.area);
  const wbest = await db.myWeekBest(c.env.DB, p.id, s.area, weekOf(now));
  const rank = best ? await db.rankAllTime(c.env.DB, s.area, best.score, best.played_at) : null;
  const weekRank = wbest ? await db.rankWeek(c.env.DB, s.area, weekOf(now), wbest.score, wbest.played_at) : null;
  return c.json({ accepted: fresh, duplicate: !fresh, improved, best: best?.score ?? null, rank, weekRank });
});

app.get("/v1/leaderboard", authenticate, async (c) => {
  if (!on(c.env.FEATURE_BOARD)) return off(c);
  const p = c.get("player");
  const lim = await minuteLimit(c.env.RL_BOARD, `board:${p.id}`, 20);
  if (!lim.allowed) return throttled(c, lim);
  const area = c.req.query("area") ?? "cage";
  if (!(AREAS as readonly string[]).includes(area)) return c.json({ error: "area" }, 400);
  const period = c.req.query("period") === "week" ? "week" : "all";
  const limit = Math.min(BOARD_MAX, Math.max(1, Number.parseInt(c.req.query("limit") ?? String(BOARD_MAX), 10) || BOARD_MAX));
  const now = Date.now();
  const week = weekOf(now);
  const rows = period === "week" ? await db.boardWeek(c.env.DB, area, week, limit) : await db.boardAllTime(c.env.DB, area, limit);
  const mine = period === "week" ? await db.myWeekBest(c.env.DB, p.id, area, week) : await db.myBest(c.env.DB, p.id, area);
  const myRank = mine
    ? period === "week"
      ? await db.rankWeek(c.env.DB, area, week, mine.score, mine.played_at)
      : await db.rankAllTime(c.env.DB, area, mine.score, mine.played_at)
    : null;
  return c.json({
    area,
    period,
    week,
    rows: rows.map((r, i) => ({ rank: i + 1, name: r.name, tag: r.tag, score: r.score, playedAt: r.played_at, me: r.player_id === p.id })),
    me: mine ? { rank: myRank, score: mine.score, name: p.name, tag: p.tag } : null,
  });
});

// ---- move to a new phone --------------------------------------------------------------

app.post("/v1/transfer/code", authenticate, async (c) => {
  if (!on(c.env.FEATURE_TRANSFER)) return off(c);
  const p = c.get("player");
  const lim = await longLimit(c.env.DB, `xfer:code:${p.id}`, 3, 3600);
  if (!lim.allowed) return throttled(c, lim);
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  const code = [...bytes].map((x) => CODE_ALPHABET[x % CODE_ALPHABET.length]).join("");
  const expiresAt = Date.now() + CODE_TTL_MS;
  await c.env.DB.batch([
    c.env.DB.prepare("DELETE FROM transfer_codes WHERE player_id = ?1").bind(p.id),
    c.env.DB.prepare("INSERT INTO transfer_codes (code, player_id, expires_at) VALUES (?1, ?2, ?3)").bind(code, p.id, expiresAt),
  ]);
  return c.json({ code, expiresAt });
});

app.post("/v1/transfer/claim", async (c) => {
  if (!on(c.env.FEATURE_TRANSFER)) return off(c);
  const lim = await longLimit(c.env.DB, `xfer:claim:ip:${ip(c)}`, 5, 3600);
  if (!lim.allowed) return throttled(c, lim);
  const b = await body(c, ["code", "newSecret"]);
  if (!b || typeof b.code !== "string" || typeof b.newSecret !== "string") return c.json({ error: "bad_request" }, 400);
  if (!SECRET_RE.test(b.newSecret)) return c.json({ error: "secret" }, 400);
  const code = b.code.toUpperCase().replace(/[^A-Z0-9]/g, "");
  const row = await c.env.DB.prepare("SELECT * FROM transfer_codes WHERE code = ?1").bind(code).first<{ code: string; player_id: string; expires_at: number }>();
  if (!row) return c.json({ error: "not_found" }, 404);
  if (row.expires_at < Date.now()) {
    await c.env.DB.prepare("DELETE FROM transfer_codes WHERE code = ?1").bind(code).run();
    return c.json({ error: "expired" }, 410);
  }
  const hash = await sha256Hex(b.newSecret);
  // A move: every other device's secret dies with the claim (per-device secrets, auth.ts).
  await c.env.DB.batch([
    ...replaceSecretsStatements(c.env.DB, row.player_id, hash, "transfer", Date.now()),
    c.env.DB.prepare("DELETE FROM transfer_codes WHERE player_id = ?1").bind(row.player_id),
  ]);
  const p = await c.env.DB.prepare("SELECT id, name, tag FROM players WHERE id = ?1").bind(row.player_id).first<PlayerRow>();
  if (!p) return c.json({ error: "not_found" }, 404);
  return c.json({ playerId: p.id, name: p.name, tag: p.tag });
});

// ---- the cloud save mirror (save.ts) ----------------------------------------------------
app.route("/v1/save", save);

// ---- platform identities (platform_routes.ts): link / restore / unlink ------------------
app.route("/v1/link", link);

// ---- 1v1 rooms (match_room.ts, lobby.ts) ---------------------------------------------------

const MATCH_PER_MINUTE = 30; // a 4 s ranked poll for the 30 s cap, with room to spare
const MATCH_PER_DAY = 200;
const ROOM_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

app.use("/v1/match/*", authenticate, async (c, next) => {
  if (!on(c.env.FEATURE_MATCH)) return off(c);
  const p = c.get("player");
  const minute = await minuteLimit(c.env.RL_MATCH, `match:${p.id}`, MATCH_PER_MINUTE);
  if (!minute.allowed) return throttled(c, minute);
  const day = await longLimit(c.env.DB, `match:day:${p.id}`, MATCH_PER_DAY, 86_400);
  if (!day.allowed) return throttled(c, day);
  await next();
});

/**
 * Quick match / make a code / join a code / leave the queue: the Lobby decides.
 * `area` may be "any" for quick / leave (design "Online Lobby" 37a): then
 * `areas` lists the courts this phone owns and the Lobby picks one on pairing.
 * `leave` with `ranked: true` leaves the ranked queue instead.
 */
app.post("/v1/match/:action{quick|code|join|leave}", async (c) => {
  const p = c.get("player");
  const b = await body(c, ["area", "code", "areas", "ranked"]);
  if (!b) return c.json({ error: "bad_request" }, 400);
  const action = c.req.param("action");
  const area = typeof b.area === "string" ? b.area : "cage";
  const anyOk = area === "any" && (action === "quick" || action === "leave");
  if (!anyOk && !(MATCH_AREAS as readonly string[]).includes(area)) return c.json({ error: "area" }, 400);
  let areas: string[] = [];
  if (b.areas !== undefined) {
    if (!Array.isArray(b.areas) || b.areas.some((a) => !(MATCH_AREAS as readonly string[]).includes(a as string))) return c.json({ error: "areas" }, 400);
    areas = b.areas as string[];
  }
  if (area === "any" && areas.length === 0) areas = ["cage"];
  if (action === "join" && typeof b.code !== "string") return c.json({ error: "code" }, 400);
  const stub = c.env.LOBBY.get(c.env.LOBBY.idFromName("lobby"));
  const res = await stub.fetch(`https://lobby/${action}`, {
    method: "POST",
    body: JSON.stringify({ playerId: p.id, area, code: b.code ?? "", areas, ranked: action === "leave" && b.ranked === true }),
  });
  return new Response(res.body, { status: res.status, headers: { "content-type": "application/json" } });
});

/**
 * The ranked queue (docs/BACKEND.md → Ranked): polled every QUEUE.poll_s
 * seconds until `paired`. Everything the Lobby matches on comes from here —
 * the verified level (→ the courts owned), the ratings row (made on the
 * first call), and `lean` (a losing streak or a long time away widens the
 * search downward). The Lobby remembers the pair in `ranked_rooms`, which is
 * what makes the room ranked when the phones connect.
 */
app.post("/v1/match/ranked", async (c) => {
  if (!on(c.env.FEATURE_RANKED)) return off(c);
  const p = c.get("player");
  const b = await body(c, []);
  if (!b) return c.json({ error: "bad_request" }, 400);
  const now = Date.now();
  let r = await db.ratingOf(c.env.DB, p.id);
  if (!r) {
    r = defaultRow(p.id, now);
    await db.upsertRatingStatement(c.env.DB, r).run();
  }
  const level = p.level ?? 1;
  const away = r.games > 0 && now - r.updated_at >= QUEUE.lean.away_days * 86_400_000;
  const lean = r.loss_streak >= QUEUE.lean.losses || away;
  const stub = c.env.LOBBY.get(c.env.LOBBY.idFromName("lobby"));
  const res = await stub.fetch("https://lobby/ranked", {
    method: "POST",
    body: JSON.stringify({ playerId: p.id, level, mu: r.mu, rd: r.rd, cons: r.cons, tier: r.tier, division: r.division, areas: areasForLevel(level), lean }),
  });
  return new Response(res.body, { status: res.status, headers: { "content-type": "application/json" } });
});

/**
 * The room's WebSocket: authenticated here, the player handed on in headers
 * (every x-* the room reads is set here, so no client header gets through).
 * A room the Lobby paired as ranked is in `ranked_rooms`: then `x-ranked` is
 * 1, the court is the row's and only its two players may enter; any other
 * room is casual with the client's court. Hands come later, through the
 * room's pre-match `loadout`.
 */
app.get("/v1/match/room/:id", async (c) => {
  if (c.req.header("upgrade")?.toLowerCase() !== "websocket") return c.json({ error: "websocket" }, 426);
  const id = c.req.param("id");
  if (!ROOM_RE.test(id)) return c.json({ error: "room" }, 400);
  const p = c.get("player");
  let area = c.req.query("area") ?? "cage";
  // "any": the host of an any-court queue; the room takes the joiner's court.
  if (area !== "any" && !(MATCH_AREAS as readonly string[]).includes(area)) return c.json({ error: "area" }, 400);
  const [ranked, inv, rating] = await Promise.all([
    c.env.DB.prepare("SELECT area, a_id, b_id FROM ranked_rooms WHERE room = ?1").bind(id).first<{ area: string; a_id: string; b_id: string }>(),
    inventoryOf(c.env.DB, p.id),
    db.ratingOf(c.env.DB, p.id),
  ]);
  if (ranked) {
    if (ranked.a_id !== p.id && ranked.b_id !== p.id) return c.json({ error: "forbidden" }, 403);
    area = ranked.area;
  }
  const band = rating ?? defaultRow(p.id, Date.now());
  const headers = new Headers(c.req.raw.headers);
  headers.set("x-player-id", p.id);
  headers.set("x-player-name", p.name);
  headers.set("x-player-tag", p.tag);
  headers.set("x-player-level", String(inv.level));
  headers.set("x-player-town", cleanTown(c.req.query("town")));
  headers.set("x-player-tier", band.tier);
  headers.set("x-player-division", String(band.division));
  // The pre-match card's stats (design "Pre Match" 37a): the rating shown, the record, the world position.
  headers.set("x-player-cons", String(Math.round(band.cons)));
  headers.set("x-player-games", String(band.games));
  headers.set("x-player-wins", String(band.wins));
  headers.set("x-player-losses", String(band.losses));
  // The rated streak tagged over RECORD (design "Pre Match" 37a, 2026-10-25).
  headers.set("x-player-win-streak", String(band.win_streak ?? 0));
  headers.set("x-player-loss-streak", String(band.loss_streak ?? 0));
  headers.set("x-player-position", String(rating ? await db.rankedPosition(c.env.DB, rating.cons, rating.updated_at) : 0));
  headers.set("x-ranked", ranked ? "1" : "0");
  headers.set("x-area", area);
  headers.set("x-room", id);
  headers.delete("authorization");
  const stub = c.env.ROOM.get(c.env.ROOM.idFromName(id));
  return stub.fetch(new Request(c.req.raw.url, { headers, method: "GET" }));
});

// ---- the ranked board (rank.ts, db.ts) ---------------------------------------------------------

/** The top rows, held for BOARD.cache_s so a lobby full of phones costs one query. */
let boardCache: { at: number; rows: db.BoardRow[] } | null = null;
/** Test hook: forget the memoised rows. */
export function resetBoardCache(): void {
  boardCache = null;
}

app.get("/v1/ranked/board", authenticate, async (c) => {
  if (!on(c.env.FEATURE_RANKED)) return off(c);
  const p = c.get("player");
  const lim = await minuteLimit(c.env.RL_BOARD, `rboard:${p.id}`, 20);
  if (!lim.allowed) return throttled(c, lim);
  const now = Date.now();
  if (!boardCache || now - boardCache.at >= BOARD.cache_s * 1000) boardCache = { at: now, rows: await db.rankedBoard(c.env.DB, BOARD.top) };
  const mine = await db.ratingOf(c.env.DB, p.id);
  const me = mine
    ? {
        position: await db.rankedPosition(c.env.DB, mine.cons, mine.updated_at),
        tier: mine.tier, division: mine.division, mu: mine.mu, rd: mine.rd, cons: mine.cons,
        games: mine.games, wins: mine.wins, losses: mine.losses, peak: { tier: mine.peak_tier, division: mine.peak_division },
      }
    : null;
  return c.json({
    rows: boardCache.rows.map((r, i) => ({ position: i + 1, playerId: r.player_id, name: r.name, tag: r.tag, tier: r.tier, division: r.division, games: r.games, wins: r.wins, losses: r.losses })),
    me,
  });
});

app.notFound((c) => c.json({ error: "not_found" }, 404));
app.onError((err, c) => {
  console.error(err);
  return c.json({ error: "server" }, 500);
});

export default {
  fetch: app.fetch,
  async scheduled(_ctrl: ScheduledController, env: Env, ctx: ExecutionContext) {
    ctx.waitUntil(db.prune(env.DB, Date.now()));
  },
};
