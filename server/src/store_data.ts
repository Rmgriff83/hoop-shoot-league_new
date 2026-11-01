/**
 * The ticket packs (docs/ECONOMY.md → Ticket packs), read from the game's
 * own data/store.json so the phone and the server never drift. The webhook
 * credits what this table says for a product id — never an amount from the
 * client or from RevenueCat's payload.
 */
import store from "../../data/store.json";

export interface Pack { id: string; tickets: number; priceUsd: string; best: boolean }

export const PACKS: readonly Pack[] = (store.packs as Array<Record<string, unknown>>).map((p) => ({
  id: String(p.id),
  tickets: Number(p.tickets),
  priceUsd: String(p.priceUsd),
  best: Boolean(p.best ?? false),
}));

export const packOf = (id: string): Pack | undefined => PACKS.find((p) => p.id === id);

/** A one-time purchase the player owns (remove_ads): the key is the RevenueCat entitlement. */
export interface Entitlement { id: string; key: string; priceUsd: string }

export const ENTITLEMENTS: readonly Entitlement[] = ((store as { entitlements?: Array<Record<string, unknown>> }).entitlements ?? []).map((e) => ({
  id: String(e.id),
  key: String(e.key),
  priceUsd: String(e.priceUsd),
}));

export const entitlementOf = (id: string): Entitlement | undefined => ENTITLEMENTS.find((e) => e.id === id);
