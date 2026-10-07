/**
 * Cards online (docs/BACKEND.md → Cards online): the card list and the
 * online payout rule, read from the game's own data files so the two sides
 * cannot drift. The ledger itself is D1 (migrations/0004_online_cards.sql).
 */
import cardData from "../../data/cards.json";
import economy from "../../data/economy.json";

export interface CardDef { id: string; price: number; level: number; target: string; rarity: string }

export const SLOTS = 3;
export const CARDS: Record<string, CardDef> = Object.fromEntries(
  (cardData.cards as any[]).map((c) => [c.id, { id: c.id, price: Number(c.price), level: Number(c.level ?? 1), target: String(c.target), rarity: String(c.rarity) }]),
);

const online = (economy as any).online ?? {};
export const ONLINE = {
  winCoins: Number(online.win_coins ?? 50),
  lossCoins: Number(online.loss_coins ?? 20),
  upsetPerLevel: Number(online.upset_per_level ?? 0.15),
  multMin: Number(online.mult_min ?? 0.5),
  multMax: Number(online.mult_max ?? 2.5),
};

/**
 * What a result pays in online coins: the winner's base scaled by the upset
 * (a lower level beating a higher one earns more), the loser's flat.
 */
export function onlineCoins(won: boolean, myLevel: number, theirLevel: number): { coins: number; mult: number } {
  if (!won) return { coins: ONLINE.lossCoins, mult: 1 };
  const raw = 1 + ONLINE.upsetPerLevel * (theirLevel - myLevel);
  const mult = Math.min(ONLINE.multMax, Math.max(ONLINE.multMin, raw));
  return { coins: Math.round(ONLINE.winCoins * mult), mult: Math.round(mult * 100) / 100 };
}

export interface Inventory { coins: number; inventory: Record<string, number>; level: number }

export async function inventoryOf(db: D1Database, playerId: string): Promise<Inventory> {
  const [wallet, rows, player] = await Promise.all([
    db.prepare("SELECT coins FROM online_wallet WHERE player_id = ?1").bind(playerId).first<{ coins: number }>(),
    db.prepare("SELECT card_id, n FROM online_cards WHERE player_id = ?1 AND n > 0").bind(playerId).all<{ card_id: string; n: number }>(),
    db.prepare("SELECT level FROM players WHERE id = ?1").bind(playerId).first<{ level: number }>(),
  ]);
  const inventory: Record<string, number> = {};
  for (const r of rows.results) inventory[r.card_id] = r.n;
  return { coins: wallet?.coins ?? 0, inventory, level: player?.level ?? 1 };
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

/** Pay coins into a wallet with a ledger line. */
export function payStatements(db: D1Database, playerId: string, coins: number, room: string, now: number): D1PreparedStatement[] {
  if (coins <= 0) return [];
  return [
    db.prepare("INSERT INTO online_wallet (player_id, coins) VALUES (?1, ?2) ON CONFLICT(player_id) DO UPDATE SET coins = online_wallet.coins + ?2").bind(playerId, coins),
    db.prepare("INSERT INTO online_ledger (player_id, kind, card_id, coins, room, at) VALUES (?1, 'reward', NULL, ?2, ?3, ?4)").bind(playerId, coins, room, now),
  ];
}
