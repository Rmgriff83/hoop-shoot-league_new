/**
 * /v1/store — the ticket store's three routes (docs/BACKEND.md → Ticket
 * store). The webhook takes RevenueCat's deliveries with no bearer: its
 * only key is the Authorization header value set in the RevenueCat
 * dashboard (REVENUECAT_WEBHOOK_AUTH, a Worker secret), compared in constant
 * time. `pending` and `claim` are the phone's, behind the usual bearer.
 * Behind FEATURE_IAP: off answers 503, which RevenueCat retries, so nothing
 * is lost while the switch is down.
 */
import { Hono } from "hono";
import type { Env, PlayerRow } from "./env";
import { authenticate } from "./auth";
import { minuteLimit, type Verdict } from "./limits";
import { onlyFields } from "./rules";
import { CLAIM_MAX, claimPurchases, handleEvent, pendingOf, type RcEvent } from "./store";

type Vars = { Bindings: Env; Variables: { player: PlayerRow } };
export const store = new Hono<Vars>();

const MAX_BODY = 4096;
/** A RevenueCat event with its attributes and experiments runs a few KB; 64 KB is room. */
const MAX_EVENT = 65_536;
const on = (flag: string | undefined) => (flag ?? "on") === "on";
const off = (c: any) => c.json({ error: "offline" }, 503);

function throttled(c: any, v: Verdict) {
  c.header("Retry-After", String(v.retryAfter));
  return c.json({ error: "throttled", retryAfter: v.retryAfter }, 429);
}

async function body(c: any, allowed: readonly string[]): Promise<Record<string, unknown> | null> {
  const text = await c.req.text();
  if (text.length > MAX_BODY) return null;
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
  const obj = parsed as Record<string, unknown>;
  return onlyFields(obj, allowed) ? obj : null;
}

/** Equal strings, in time that does not depend on where they differ. */
export function sameSecret(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  if (ab.byteLength !== bb.byteLength || ab.byteLength === 0) return false;
  return crypto.subtle.timingSafeEqual(ab, bb);
}

store.use("/*", async (c, next) => {
  if (!on(c.env.FEATURE_IAP)) return off(c);
  await next();
});

// POST /v1/store/webhook — RevenueCat's deliveries (no bearer; the header is the key).
store.post("/webhook", async (c) => {
  const expected = c.env.REVENUECAT_WEBHOOK_AUTH ?? "";
  const given = c.req.header("authorization") ?? "";
  if (!expected || !sameSecret(expected, given)) return c.json({ error: "unauthorized" }, 401);
  const text = await c.req.text();
  if (text.length > MAX_EVENT) return c.json({ error: "bad_request" }, 400);
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    return c.json({ error: "bad_request" }, 400);
  }
  const ev = (parsed as { event?: unknown } | null)?.event as RcEvent | undefined;
  if (!ev || typeof ev !== "object" || typeof ev.id !== "string" || !ev.id || ev.id.length > 128 || typeof ev.type !== "string" || !ev.type) {
    return c.json({ error: "bad_request" }, 400);
  }
  const r = await handleEvent(c.env.DB, ev, Date.now());
  if (r.status !== 200) console.warn("store webhook failed", JSON.stringify(r.body));
  return c.json(r.body, r.status);
});

store.use("/pending", authenticate);
store.use("/claim", authenticate);

// GET /v1/store/pending — the sales waiting for this phone.
store.get("/pending", async (c) => {
  const p = c.get("player");
  const lim = await minuteLimit(undefined, `store:${p.id}`, 30);
  if (!lim.allowed) return throttled(c, lim);
  const rows = await pendingOf(c.env.DB, p.id);
  return c.json({
    pending: rows.map((r) => ({ id: r.id, productId: r.product_id, tickets: r.tickets, purchasedAt: r.purchased_at })),
    tickets: rows.reduce((n, r) => n + r.tickets, 0),
  });
});

// POST /v1/store/claim {ids} — the phone takes its tickets, once.
store.post("/claim", async (c) => {
  const p = c.get("player");
  const lim = await minuteLimit(undefined, `store:claim:${p.id}`, 30);
  if (!lim.allowed) return throttled(c, lim);
  const b = await body(c, ["ids"]);
  const ids = b?.ids;
  if (!Array.isArray(ids) || ids.length === 0 || ids.length > CLAIM_MAX || !ids.every((v) => Number.isInteger(v) && (v as number) > 0)) {
    return c.json({ error: "bad_request" }, 400);
  }
  const rows = await claimPurchases(c.env.DB, p.id, ids as number[], Date.now());
  return c.json({
    claimed: rows.map((r) => ({ id: r.id, productId: r.product_id, tickets: r.tickets })),
    tickets: rows.reduce((n, r) => n + r.tickets, 0),
  });
});
