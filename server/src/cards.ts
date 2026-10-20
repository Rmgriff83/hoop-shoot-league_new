/**
 * Cards online (docs/BACKEND.md → Cards online): the card list, read from
 * the game's own data file so the two sides cannot drift. The ledger itself
 * is D1 (migrations/0004_online_cards.sql); nothing buys cards any more.
 */
import cardData from "../../data/cards.json";
import drops from "../../data/online_drops.json";
import { tierIndex } from "./rank";
import { TIERS } from "./ranked_data";

export interface CardDef { id: string; price: number; level: number; target: string; rarity: string }

export const SLOTS = 3;
export const CARDS: Record<string, CardDef> = Object.fromEntries(
  (cardData.cards as any[]).map((c) => [c.id, { id: c.id, price: Number(c.price), level: Number(c.level ?? 1), target: String(c.target), rarity: String(c.rarity) }]),
);

/** The lowest tier a card may be brought into a ranked room at (data/online_drops.json; unlisted → the first tier). */
export const CARD_MIN_TIER: Record<string, string> = { ...(drops.card_min_tier as Record<string, string>) };

export interface Inventory { inventory: Record<string, number>; level: number }

export async function inventoryOf(db: D1Database, playerId: string): Promise<Inventory> {
  const [rows, player] = await Promise.all([
    db.prepare("SELECT card_id, n FROM online_cards WHERE player_id = ?1 AND n > 0").bind(playerId).all<{ card_id: string; n: number }>(),
    db.prepare("SELECT level FROM players WHERE id = ?1").bind(playerId).first<{ level: number }>(),
  ]);
  const inventory: Record<string, number> = {};
  for (const r of rows.results) inventory[r.card_id] = r.n;
  return { inventory, level: player?.level ?? 1 };
}

/**
 * The hand a phone may bring into a room: its three slots, each kept only
 * when the card exists, the player's level and the room's cap (the lower of
 * the two levels) allow it, the player's tier may carry it, and the ledger
 * holds a copy not already claimed by an earlier slot. Blanks stay blank.
 */
export function validHand(slots: string[], inv: Inventory, cap: number = inv.level, tierId: string = TIERS[TIERS.length - 1].id): string[] {
  const left = { ...inv.inventory };
  const out: string[] = [];
  const tier = tierIndex(tierId);
  for (let i = 0; i < SLOTS; i++) {
    const id = slots[i] ?? "";
    const card = CARDS[id];
    if (!card || card.level > inv.level || card.level > cap || (left[id] ?? 0) <= 0) { out.push(""); continue; }
    if (tier < tierIndex(CARD_MIN_TIER[id] ?? TIERS[0].id)) { out.push(""); continue; }
    left[id] -= 1;
    out.push(id);
  }
  return out;
}
