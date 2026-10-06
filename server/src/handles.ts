import words from "../../data/handle_words.json";

/** "BRICK BARON" + "42": a handle in the game's tone, from data/handle_words.json. */
export function randomHandle(): { name: string; tag: string } {
  const pick = (list: string[]) => list[Math.floor(Math.random() * list.length)];
  const tag = String(Math.floor(Math.random() * 100)).padStart(2, "0");
  return { name: `${pick(words.first)} ${pick(words.second)}`, tag };
}

export const BLOCKED: readonly string[] = words.blocked;
