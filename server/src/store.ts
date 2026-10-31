/**
 * The ticket store's books (docs/BACKEND.md → Ticket store). RevenueCat's
 * webhook is the only thing that credits a pack (the bball_sim shape): a
 * delivery is claimed once by its event id, a sale becomes a `purchases`
 * row that waits for the phone's CLAIM, and the amount comes from
 * data/store.json by product id — never from the client or the payload.
 * The wallet lives on the phone (cosmetics.tickets, a save part the server
 * never reads into), so the credit travels the /v1/rewards/claim way: the
 * phone asks what is pending, claims it (atomic, once) and grants locally.
 */
import { UUID_RE } from "./rules";
import { packOf } from "./store_data";

/** The part of a RevenueCat event the books read (docs: webhooks → event types and fields). */
export interface RcEvent {
  id: string;
  type: string;
  app_user_id?: unknown;
  original_app_user_id?: unknown;
  aliases?: unknown;
  product_id?: unknown;
  store?: unknown;
  environment?: unknown;
  transaction_id?: unknown;
  purchased_at_ms?: unknown;
  price?: unknown;
  currency?: unknown;
  country_code?: unknown;
}

export interface Outcome { status: 200 | 500; body: Record<string, unknown> }

export interface PendingRow { id: number; product_id: string; tickets: number; purchased_at: number }

const ANON = "$RCAnonymousID:";
const str = (v: unknown, max = 128): string => (typeof v === "string" ? v.slice(0, max) : "");

/**
 * The player an event belongs to: app_user_id, then original_app_user_id,
 * then every alias — RevenueCat's own advice — skipping its anonymous ids.
 * Our app user id is the player id, so only a UUID that exists can match.
 */
export async function resolvePlayer(db: D1Database, ev: RcEvent): Promise<string | null> {
  const candidates: string[] = [];
  for (const v of [ev.app_user_id, ev.original_app_user_id, ...(Array.isArray(ev.aliases) ? ev.aliases : [])]) {
    const s = str(v);
    if (s && !s.startsWith(ANON) && UUID_RE.test(s) && !candidates.includes(s)) candidates.push(s);
  }
  for (const id of candidates) {
    const row = await db.prepare("SELECT id FROM players WHERE id = ?1").bind(id).first<{ id: string }>();
    if (row) return row.id;
  }
  return null;
}

/**
 * One delivery. 200 means done (or already done, or nothing to do); 500 means
 * "retry later" — and the event is NOT recorded then, so the retry can
 * succeed once the cause (an unknown player or product) is fixed. The
 * record and the sale go in one batch: a half-written delivery cannot
 * happen, and a second delivery of the same transaction under a new event
 * id (a restore) is stopped by the (store, transaction_id) key.
 */
export async function handleEvent(db: D1Database, ev: RcEvent, now: number): Promise<Outcome> {
  const seen = await db.prepare("SELECT 1 AS one FROM store_events WHERE id = ?1").bind(ev.id).first();
  if (seen) return { status: 200, body: { status: "already_processed" } };
  const record = db.prepare("INSERT OR IGNORE INTO store_events (id, type, received_at) VALUES (?1, ?2, ?3)").bind(ev.id, ev.type, now);
  const store = str(ev.store) || "UNKNOWN";
  const tx = str(ev.transaction_id);
  switch (ev.type) {
    case "NON_RENEWING_PURCHASE": {
      const pack = packOf(str(ev.product_id));
      if (!pack) return { status: 500, body: { error: "unknown_product", ...where(ev) } };
      if (!tx) return { status: 500, body: { error: "no_transaction", ...where(ev) } };
      const playerId = await resolvePlayer(db, ev);
      if (!playerId) return { status: 500, body: { error: "unknown_player", ...where(ev) } };
      const sale = db
        .prepare(
          `INSERT OR IGNORE INTO purchases (player_id, product_id, store, transaction_id, environment, tickets, price, currency, country, purchased_at, event_id, created_at)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)`,
        )
        .bind(
          playerId, pack.id, store, tx, str(ev.environment) || "PRODUCTION", pack.tickets,
          typeof ev.price === "number" ? ev.price : null, str(ev.currency, 8) || null, str(ev.country_code, 8) || null,
          typeof ev.purchased_at_ms === "number" ? ev.purchased_at_ms : now, ev.id, now,
        );
      const [, r] = await db.batch([record, sale]);
      return { status: 200, body: { status: (r.meta.changes ?? 0) > 0 ? "fulfilled" : "duplicate_transaction" } };
    }
    case "CANCELLATION": {
      // A refund: an unclaimed row is never credited; a claimed one stays (no clawback, Ross 2026-10-31).
      const mark = db.prepare("UPDATE purchases SET refunded_at = ?1 WHERE store = ?2 AND transaction_id = ?3 AND refunded_at IS NULL").bind(now, store, tx);
      const [, r] = await db.batch([record, mark]);
      return { status: 200, body: { status: (r.meta.changes ?? 0) > 0 ? "refunded" : "ignored" } };
    }
    case "TEST":
      await record.run();
      return { status: 200, body: { status: "test" } };
    default:
      await record.run();
      return { status: 200, body: { status: "ignored" } };
  }
}

/** What a failed delivery's log line carries (bball_sim's warning fields). */
function where(ev: RcEvent): Record<string, unknown> {
  return {
    event_id: ev.id, product_id: str(ev.product_id), app_user_id: str(ev.app_user_id), original_app_user_id: str(ev.original_app_user_id),
    aliases: Array.isArray(ev.aliases) ? ev.aliases.map((a) => str(a)) : [], store: str(ev.store), country_code: str(ev.country_code, 8),
  };
}

/** The sales waiting for the phone, oldest first. */
export async function pendingOf(db: D1Database, playerId: string): Promise<PendingRow[]> {
  const r = await db
    .prepare("SELECT id, product_id, tickets, purchased_at FROM purchases WHERE player_id = ?1 AND claimed_at IS NULL AND refunded_at IS NULL ORDER BY purchased_at ASC, id ASC")
    .bind(playerId)
    .all<PendingRow>();
  return r.results ?? [];
}

/** The tickets waiting for the phone (GET /v1/me → pendingTickets). */
export async function pendingTicketsOf(db: D1Database, playerId: string): Promise<number> {
  const r = await db
    .prepare("SELECT COALESCE(SUM(tickets), 0) AS n FROM purchases WHERE player_id = ?1 AND claimed_at IS NULL AND refunded_at IS NULL")
    .bind(playerId)
    .first<{ n: number }>();
  return Number(r?.n ?? 0);
}

export const CLAIM_MAX = 20;

/**
 * The phone takes its tickets: the rows it names become claimed in one
 * statement, and only the rows this call turned are answered — a second
 * call, or a replay, gets nothing to grant.
 */
export async function claimPurchases(db: D1Database, playerId: string, ids: number[], now: number): Promise<PendingRow[]> {
  if (ids.length === 0) return [];
  const marks = ids.map((_, i) => `?${i + 3}`).join(", ");
  const r = await db
    .prepare(
      `UPDATE purchases SET claimed_at = ?1 WHERE player_id = ?2 AND id IN (${marks}) AND claimed_at IS NULL AND refunded_at IS NULL
       RETURNING id, product_id, tickets, purchased_at`,
    )
    .bind(now, playerId, ...ids)
    .all<PendingRow>();
  return r.results ?? [];
}
