import { SELF, env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { app } from "../src/index";
import { resetMemoryLimits } from "../src/limits";
import { ENTITLEMENTS, PACKS, entitlementOf, packOf } from "../src/store_data";
import { sameSecret } from "../src/store_routes";

const uuid = () => crypto.randomUUID();
const secret = () => [...crypto.getRandomValues(new Uint8Array(40))].map((b) => "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"[b % 62]).join("");

interface Player { playerId: string; secret: string; name: string; tag: string; ip: string }

let ipCounter = 190_000;
const freshIp = () => `10.${Math.floor(ipCounter / 65536) % 256}.${Math.floor(ipCounter / 256) % 256}.${ipCounter++ % 256}`;

async function register(ip = freshIp()): Promise<Player> {
  const p = { playerId: uuid(), secret: secret(), ip };
  const res = await SELF.fetch("https://api/v1/register", {
    method: "POST",
    headers: { "content-type": "application/json", "cf-connecting-ip": ip },
    body: JSON.stringify({ playerId: p.playerId, secret: p.secret, clientId: uuid() }),
  });
  expect(res.status).toBe(200);
  const j = (await res.json()) as { name: string; tag: string };
  return { ...p, name: j.name, tag: j.tag };
}

const auth = (p: Player) => ({ authorization: `Bearer ${p.playerId}.${p.secret}`, "content-type": "application/json", "cf-connecting-ip": p.ip });

const AUTH = "test-auth";
let txCounter = 1000;

/** A NON_RENEWING_PURCHASE as RevenueCat sends it (docs → sample events), for `p`. */
function sale(p: Player | string, over: Record<string, unknown> = {}) {
  const id = typeof p === "string" ? p : p.playerId;
  return {
    api_version: "1.0",
    event: {
      id: uuid(), type: "NON_RENEWING_PURCHASE", app_id: "app1", event_timestamp_ms: Date.now(),
      product_id: "tickets_300", period_type: "NORMAL", purchased_at_ms: Date.now() - 1000, expiration_at_ms: null,
      environment: "SANDBOX", entitlement_id: null, entitlement_ids: [], presented_offering_id: null,
      transaction_id: `tx-${txCounter++}`, original_transaction_id: "o", is_family_share: false, country_code: "US",
      app_user_id: id, aliases: [`$RCAnonymousID:${uuid()}`], original_app_user_id: id,
      currency: "USD", price: 0.99, price_in_purchased_currency: 0.99, store: "APP_STORE", takehome_percentage: 0.85,
      subscriber_attributes: {}, offer_code: null, ...over,
    },
  };
}

const hook = (payload: unknown, header: string | null = AUTH, ip = freshIp()) =>
  SELF.fetch("https://api/v1/store/webhook", {
    method: "POST",
    headers: { "content-type": "application/json", "cf-connecting-ip": ip, ...(header === null ? {} : { authorization: header }) },
    body: typeof payload === "string" ? payload : JSON.stringify(payload),
  });

const pending = async (p: Player) => {
  const res = await SELF.fetch("https://api/v1/store/pending", { headers: auth(p) });
  return { status: res.status, json: (await res.json()) as any };
};
const claim = async (p: Player, ids: unknown) => {
  const res = await SELF.fetch("https://api/v1/store/claim", { method: "POST", headers: auth(p), body: JSON.stringify({ ids }) });
  return { status: res.status, json: (await res.json()) as any };
};
const rows = (p: Player) => env.DB.prepare("SELECT * FROM purchases WHERE player_id = ?1 ORDER BY id").bind(p.playerId).all<any>().then((r) => r.results ?? []);
const events = () => env.DB.prepare("SELECT id, type FROM store_events").all<any>().then((r) => r.results ?? []);

beforeEach(() => resetMemoryLimits());

describe("packs", () => {
  it("come from data/store.json: 300 for $0.99, 1000 for $2.99 (best)", () => {
    expect(PACKS.map((p) => [p.id, p.tickets, p.priceUsd, p.best])).toEqual([["tickets_300", 300, "$0.99", false], ["tickets_1000", 1000, "$2.99", true]]);
    expect(packOf("tickets_1000")?.tickets).toBe(1000);
    expect(packOf("tokens_1000")).toBeUndefined();
  });
  it("the header check is exact, in constant time", () => {
    expect(sameSecret("abc", "abc")).toBe(true);
    expect(sameSecret("abc", "abd")).toBe(false);
    expect(sameSecret("abc", "abcd")).toBe(false);
    expect(sameSecret("", "")).toBe(false);
  });
});

describe("webhook", () => {
  it("needs the dashboard's Authorization header", async () => {
    const p = await register();
    expect((await hook(sale(p), null)).status).toBe(401);
    expect((await hook(sale(p), "wrong")).status).toBe(401);
    expect(await rows(p)).toHaveLength(0);
  });
  it("rejects a body without an event id or type", async () => {
    expect((await hook("{not json")).status).toBe(400);
    expect((await hook({ event: { type: "TEST" } })).status).toBe(400);
    expect((await hook({ event: { id: "x" } })).status).toBe(400);
    expect((await hook({ nope: 1 })).status).toBe(400);
  });
  it("answers the dashboard's TEST event and records it", async () => {
    const id = uuid();
    const res = await hook({ api_version: "1.0", event: { id, type: "TEST", app_user_id: uuid() } });
    expect(res.status).toBe(200);
    expect(((await res.json()) as any).status).toBe("test");
    expect((await events()).some((e) => e.id === id && e.type === "TEST")).toBe(true);
  });
  it("a sale becomes a pending purchase worth the pack from data/store.json", async () => {
    const p = await register();
    const ev = sale(p, { product_id: "tickets_1000", price: 2.99, country_code: "CA", currency: "CAD" });
    const res = await hook(ev);
    expect(res.status).toBe(200);
    expect(((await res.json()) as any).status).toBe("fulfilled");
    const r = await rows(p);
    expect(r).toHaveLength(1);
    expect(r[0]).toMatchObject({ product_id: "tickets_1000", tickets: 1000, store: "APP_STORE", environment: "SANDBOX", price: 2.99, currency: "CAD", country: "CA", claimed_at: null, refunded_at: null });
    expect(r[0].transaction_id).toBe(ev.event.transaction_id);
    expect(r[0].event_id).toBe(ev.event.id);
    const pend = await pending(p);
    expect(pend.status).toBe(200);
    expect(pend.json.tickets).toBe(1000);
    expect(pend.json.pending).toEqual([{ id: r[0].id, productId: "tickets_1000", tickets: 1000, purchasedAt: ev.event.purchased_at_ms }]);
    const me = (await (await SELF.fetch("https://api/v1/me", { headers: auth(p) })).json()) as any;
    expect(me.pendingTickets).toBe(1000);
  });
  it("the same delivery again is already processed; the same transaction under a new event id is a duplicate", async () => {
    const p = await register();
    const ev = sale(p);
    expect(((await (await hook(ev)).json()) as any).status).toBe("fulfilled");
    expect(((await (await hook(ev)).json()) as any).status).toBe("already_processed");
    const again = sale(p, { transaction_id: ev.event.transaction_id });
    expect(((await (await hook(again)).json()) as any).status).toBe("duplicate_transaction");
    expect(await rows(p)).toHaveLength(1);
    expect((await events()).filter((e) => e.id === ev.event.id || e.id === again.event.id)).toHaveLength(2);
    // Another store's transaction with the same id is its own sale.
    const play = sale(p, { transaction_id: ev.event.transaction_id, store: "PLAY_STORE" });
    expect(((await (await hook(play)).json()) as any).status).toBe("fulfilled");
    expect(await rows(p)).toHaveLength(2);
  });
  it("an unknown product or player is a 500 (RevenueCat retries) and nothing is recorded", async () => {
    const p = await register();
    const bad = sale(p, { product_id: "tokens_6500" });
    const r1 = await hook(bad);
    expect(r1.status).toBe(500);
    expect(((await r1.json()) as any).error).toBe("unknown_product");
    const ghost = sale(uuid());
    const r2 = await hook(ghost);
    expect(r2.status).toBe(500);
    expect(((await r2.json()) as any).error).toBe("unknown_player");
    const noTx = sale(p, { transaction_id: "" });
    expect((await hook(noTx)).status).toBe(500);
    const ids = (await events()).map((e) => e.id);
    expect(ids).not.toContain(bad.event.id);
    expect(ids).not.toContain(ghost.event.id);
    expect(ids).not.toContain(noTx.event.id);
    expect(await rows(p)).toHaveLength(0);
    // Fixed later (the player registers): the retry lands.
    const late = await register();
    const ev = sale(uuid(), { aliases: [`$RCAnonymousID:${uuid()}`, late.playerId] });
    expect(((await (await hook(ev)).json()) as any).status).toBe("fulfilled");
    expect(await rows(late)).toHaveLength(1);
  });
  it("finds the player through original_app_user_id or the aliases, never an anonymous id", async () => {
    const p = await register();
    const anon = `$RCAnonymousID:${uuid()}`;
    const ev = sale(anon, { original_app_user_id: p.playerId, aliases: [anon] });
    expect(((await (await hook(ev)).json()) as any).status).toBe("fulfilled");
    expect(await rows(p)).toHaveLength(1);
  });
  it("a refund marks the sale; an unclaimed refund is never pending, a claimed one stays", async () => {
    const p = await register();
    const a = sale(p);
    const b = sale(p);
    await hook(a);
    await hook(b);
    const before = await pending(p);
    expect(before.json.pending).toHaveLength(2);
    const bId = before.json.pending[1].id;
    expect((await claim(p, [bId])).json.tickets).toBe(300);
    const refund = (ev: ReturnType<typeof sale>) => hook({ api_version: "1.0", event: { ...ev.event, id: uuid(), type: "CANCELLATION", cancel_reason: "CUSTOMER_SUPPORT", price: -0.99 } });
    expect(((await (await refund(a)).json()) as any).status).toBe("refunded");
    expect(((await (await refund(b)).json()) as any).status).toBe("refunded");
    expect(((await (await refund(a)).json()) as any).status).toBe("ignored");   // already marked
    const r = await rows(p);
    expect(r[0].refunded_at).not.toBeNull();
    expect(r[1].refunded_at).not.toBeNull();
    expect(r[1].claimed_at).not.toBeNull();
    expect((await pending(p)).json.pending).toHaveLength(0);
    expect((await claim(p, [r[0].id])).json.claimed).toHaveLength(0);
    const me = (await (await SELF.fetch("https://api/v1/me", { headers: auth(p) })).json()) as any;
    expect(me.pendingTickets).toBe(0);
  });
  it("other event types are recorded and ignored", async () => {
    const p = await register();
    const ev = sale(p, { type: "BILLING_ISSUE" });
    expect(((await (await hook(ev)).json()) as any).status).toBe("ignored");
    expect(await rows(p)).toHaveLength(0);
    expect((await events()).some((e) => e.id === ev.event.id)).toBe(true);
  });
  it("is off with FEATURE_IAP, so RevenueCat keeps the delivery", async () => {
    const p = await register();
    const res = await app.request("/v1/store/webhook", { method: "POST", headers: { authorization: AUTH, "content-type": "application/json" }, body: JSON.stringify(sale(p)) }, { ...env, FEATURE_IAP: "off" });
    expect(res.status).toBe(503);
    const pend = await app.request("/v1/store/pending", { headers: auth(p) }, { ...env, FEATURE_IAP: "off" });
    expect(pend.status).toBe(503);
  });
  it("with no secret configured, every delivery is refused", async () => {
    const p = await register();
    const res = await app.request("/v1/store/webhook", { method: "POST", headers: { authorization: "", "content-type": "application/json" }, body: JSON.stringify(sale(p)) }, { ...env, REVENUECAT_WEBHOOK_AUTH: "" });
    expect(res.status).toBe(401);
  });
});

describe("pending and claim", () => {
  it("need the bearer", async () => {
    const ip = freshIp();
    expect((await SELF.fetch("https://api/v1/store/pending", { headers: { "cf-connecting-ip": ip } })).status).toBe(401);
    expect((await SELF.fetch("https://api/v1/store/claim", { method: "POST", headers: { "cf-connecting-ip": ip, "content-type": "application/json" }, body: "{\"ids\":[1]}" })).status).toBe(401);
  });
  it("a claim turns the rows once; a replay and another player get nothing", async () => {
    const p = await register();
    const other = await register();
    await hook(sale(p));
    await hook(sale(p, { product_id: "tickets_1000" }));
    const pend = await pending(p);
    const ids = pend.json.pending.map((r: any) => r.id);
    expect(pend.json.tickets).toBe(1300);
    const theft = await claim(other, ids);
    expect(theft.json.claimed).toHaveLength(0);
    expect(theft.json.tickets).toBe(0);
    const first = await claim(p, ids);
    expect(first.status).toBe(200);
    expect(first.json.tickets).toBe(1300);
    expect(first.json.claimed.map((r: any) => r.productId)).toEqual(["tickets_300", "tickets_1000"]);
    const replay = await claim(p, ids);
    expect(replay.json.claimed).toHaveLength(0);
    expect(replay.json.tickets).toBe(0);
    expect((await pending(p)).json.pending).toHaveLength(0);
    for (const r of await rows(p)) expect(r.claimed_at).not.toBeNull();
  });
  it("checks the ids", async () => {
    const p = await register();
    expect((await claim(p, [])).status).toBe(400);
    expect((await claim(p, ["1"])).status).toBe(400);
    expect((await claim(p, [0])).status).toBe(400);
    expect((await claim(p, Array.from({ length: 21 }, (_, i) => i + 1))).status).toBe(400);
    expect((await claim(p, [999_999])).json.claimed).toHaveLength(0);
  });
  it("account deletion takes the purchases with it", async () => {
    const p = await register();
    await hook(sale(p));
    expect(await rows(p)).toHaveLength(1);
    expect((await SELF.fetch("https://api/v1/me", { method: "DELETE", headers: auth(p) })).status).toBe(200);
    expect(await rows(p)).toHaveLength(0);
  });
});

const ents = (p: Player) => env.DB.prepare("SELECT * FROM entitlements WHERE player_id = ?1 ORDER BY id").bind(p.playerId).all<any>().then((r) => r.results ?? []);
const me = async (p: Player) => (await (await SELF.fetch("https://api/v1/me", { headers: auth(p) })).json()) as any;
/** A RevenueCat TRANSFER: no transaction, no app_user_id, only the ids the entitlements leave and reach. */
const transfer = (from: string[], to: string[]) => ({
  api_version: "1.0",
  event: { id: uuid(), type: "TRANSFER", app_id: "app1", event_timestamp_ms: Date.now(), store: "APP_STORE", environment: "SANDBOX", transferred_from: from, transferred_to: to },
});

describe("entitlements (remove_ads)", () => {
  it("come from data/store.json: remove_ads for $4.99, its own key", () => {
    expect(ENTITLEMENTS.map((e) => [e.id, e.key, e.priceUsd])).toEqual([["remove_ads", "remove_ads", "$4.99"]]);
    expect(entitlementOf("remove_ads")?.key).toBe("remove_ads");
    expect(entitlementOf("tickets_300")).toBeUndefined();
    expect(packOf("remove_ads")).toBeUndefined();
  });
  it("a sale is owned, not credited: a row, /v1/me lists the key, nothing pending", async () => {
    const p = await register();
    expect((await me(p)).entitlements).toEqual([]);
    const ev = sale(p, { product_id: "remove_ads", price: 4.99, entitlement_ids: ["remove_ads"] });
    expect(((await (await hook(ev)).json()) as any).status).toBe("granted");
    const r = await ents(p);
    expect(r).toHaveLength(1);
    expect([r[0].key, r[0].product_id, r[0].store, r[0].transaction_id, r[0].environment, r[0].event_id]).toEqual(["remove_ads", "remove_ads", "APP_STORE", ev.event.transaction_id, "SANDBOX", ev.event.id]);
    expect(r[0].revoked_at).toBeNull();
    expect(await rows(p)).toHaveLength(0);
    expect((await pending(p)).json.pending).toHaveLength(0);
    const m = await me(p);
    expect(m.entitlements).toEqual(["remove_ads"]);
    expect(m.pendingTickets).toBe(0);
  });
  it("the same event again is already processed; the same transaction under a new id is a duplicate", async () => {
    const p = await register();
    const ev = sale(p, { product_id: "remove_ads" });
    expect(((await (await hook(ev)).json()) as any).status).toBe("granted");
    expect(((await (await hook(ev)).json()) as any).status).toBe("already_processed");
    const again = sale(p, { product_id: "remove_ads", transaction_id: ev.event.transaction_id });
    expect(((await (await hook(again)).json()) as any).status).toBe("duplicate_transaction");
    expect(await ents(p)).toHaveLength(1);
    expect((await me(p)).entitlements).toEqual(["remove_ads"]);
  });
  it("needs a transaction and a known player, like a pack (500, nothing recorded)", async () => {
    const p = await register();
    const noTx = sale(p, { product_id: "remove_ads", transaction_id: "" });
    expect((await hook(noTx)).status).toBe(500);
    const ghost = sale(uuid(), { product_id: "remove_ads" });
    const res = await hook(ghost);
    expect(res.status).toBe(500);
    expect(((await res.json()) as any).error).toBe("unknown_player");
    expect((await events()).some((e) => e.id === ghost.event.id || e.id === noTx.event.id)).toBe(false);
    expect(await ents(p)).toHaveLength(0);
  });
  it("a refund revokes it (tickets are never clawed back, an entitlement is)", async () => {
    const p = await register();
    const ev = sale(p, { product_id: "remove_ads" });
    await hook(ev);
    expect((await me(p)).entitlements).toEqual(["remove_ads"]);
    const refund = { api_version: "1.0", event: { ...ev.event, id: uuid(), type: "CANCELLATION", cancel_reason: "CUSTOMER_SUPPORT" } };
    expect(((await (await hook(refund)).json()) as any).status).toBe("revoked");
    expect((await ents(p))[0].revoked_at).not.toBeNull();
    expect((await me(p)).entitlements).toEqual([]);
    // A second refund of the same transaction has nothing left to do.
    const again = { api_version: "1.0", event: { ...ev.event, id: uuid(), type: "CANCELLATION" } };
    expect(((await (await hook(again)).json()) as any).status).toBe("ignored");
  });
  it("a TRANSFER moves the live rows to the new player (a restore on a reinstalled phone)", async () => {
    const a = await register();
    const b = await register();
    const ev = sale(a, { product_id: "remove_ads" });
    await hook(ev);
    const tr = transfer([a.playerId, `$RCAnonymousID:${uuid()}`], [b.playerId]);
    const res = await hook(tr);
    expect(res.status).toBe(200);
    expect(((await res.json()) as any)).toEqual({ status: "transferred", moved: 1 });
    expect(await ents(a)).toHaveLength(0);
    expect((await ents(b)).map((r) => [r.key, r.transaction_id])).toEqual([["remove_ads", ev.event.transaction_id]]);
    expect((await me(a)).entitlements).toEqual([]);
    expect((await me(b)).entitlements).toEqual(["remove_ads"]);
    expect(((await (await hook(tr)).json()) as any).status).toBe("already_processed");
    // Tickets stay where they were claimed from.
    const t = sale(a);
    await hook(t);
    await hook(transfer([a.playerId], [b.playerId]));
    expect(await rows(a)).toHaveLength(1);
    expect(await rows(b)).toHaveLength(0);
  });
  it("a TRANSFER to a player the server has not met is retried; one with nothing to move is ignored", async () => {
    const a = await register();
    await hook(sale(a, { product_id: "remove_ads" }));
    const ghost = transfer([a.playerId], [uuid()]);
    const res = await hook(ghost);
    expect(res.status).toBe(500);
    expect(((await res.json()) as any).error).toBe("unknown_player");
    expect((await events()).some((e) => e.id === ghost.event.id)).toBe(false);
    expect(await ents(a)).toHaveLength(1);
    const b = await register();
    const nothing = transfer([uuid(), `$RCAnonymousID:${uuid()}`], [b.playerId]);
    expect(((await (await hook(nothing)).json()) as any).status).toBe("ignored");
    expect((await events()).some((e) => e.id === nothing.event.id)).toBe(true);
    // A revoked row does not travel.
    const ev2 = sale(a, { product_id: "remove_ads" });
    await hook(ev2);
    await hook({ api_version: "1.0", event: { ...ev2.event, id: uuid(), type: "CANCELLATION" } });
    const c = await register();
    const r = await (await hook(transfer([a.playerId], [c.playerId]))).json() as any;
    expect(r.moved).toBe(1);   // the first, live row; not the revoked second
    expect((await me(c)).entitlements).toEqual(["remove_ads"]);
  });
  it("account deletion drops the rows", async () => {
    const p = await register();
    await hook(sale(p, { product_id: "remove_ads" }));
    expect(await ents(p)).toHaveLength(1);
    const res = await SELF.fetch("https://api/v1/me", { method: "DELETE", headers: auth(p) });
    expect(res.status).toBe(200);
    expect(await ents(p)).toHaveLength(0);
  });
});
