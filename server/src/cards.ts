/**
 * Cards online (docs/BACKEND.md → Cards online): the card list, read from
 * the game's own data file so the two sides cannot drift. The ledger itself
 * is D1 (migrations/0004_online_cards.sql); nothing buys cards any more.
 */
import cardData from "../../data/cards.json";

export interface CardDef { id: string; price: number; level: number; target: string; rarity: string }

export const SLOTS = 3;
export const CARDS: Record<string, CardDef> = Object.fromEntries(
  (cardData.cards as any[]).map((c) => [c.id, { id: c.id, price: Number(c.price), level: Number(c.level ?? 1), target: String(c.target), rarity: String(c.rarity) }]),
);

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
 * when the card exists, the player's level allows it and the ledger holds a
 * copy not already claimed by an earlier slot. Blanks stay blank.
 */
export function validHand(slots: string[], inv: Inventory): string[] {
  const left = { ...inv.inventory };
  const out: string[] = [];
  for (let i = 0; i < SLOTS; i++) {
    const id = slots[i] ?? "";
    const card = CARDS[id];
    if (!card || card.level > inv.level || (left[id] ?? 0) <= 0) { out.push(""); continue; }
    left[id] -= 1;
    out.push(id);
  }
  return out;
}
