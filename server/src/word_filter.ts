/**
 * The word filter the game runs over a typed name or hometown, run again
 * here over the same file (core/net/word_filter.gd is the twin; the two
 * share data/word_filter_cases.json as their verdict table). `cleanTyping`
 * keeps A–Z, 0–9 and single spaces. `blockedWord` finds a word from
 * data/blocked_words.json in the cleaned text: anywhere inside a word or
 * across a space (FUCKVILLE, FU CK), with digits read as letters (SH1T,
 * 80085) and stretched letters squeezed (FUUUCK); `whole` words match a
 * whole word only (ASS, never CLASS) and `allow` words are innocent despite
 * what they contain (SCUNTHORPE).
 */
import lists from "../../data/blocked_words.json";

const BLOCKED: readonly string[] = lists.blocked;
const WHOLE: readonly string[] = lists.whole;
const ALLOW: readonly string[] = lists.allow;
const LEET: Record<string, string> = { "0": "O", "1": "I", "2": "Z", "3": "E", "4": "A", "5": "S", "6": "G", "7": "T", "8": "B", "9": "G" };

const squeeze = (tok: string) => tok.replace(/(.)\1+/g, "$1");
const leet = (tok: string) => tok.replace(/[0-9]/g, (d) => LEET[d]);
const SINGLE_BLOCKED = BLOCKED.filter((w) => squeeze(w) === w);
const SINGLE_WHOLE = WHOLE.filter((w) => squeeze(w) === w);

/** Upper-case, A–Z 0–9 and single spaces, no leading space, at most `maxLen` (a trailing space may stay). */
export function cleanTyping(raw: string, maxLen: number): string {
  return raw.toUpperCase().replace(/[^A-Z0-9 ]/g, "").replace(/ {2,}/g, " ").replace(/^ /, "").slice(0, maxLen);
}

function find(tokens: string[], blocked: readonly string[], whole: readonly string[]): string {
  const squash = tokens.join("");
  for (const w of blocked) if (squash.includes(w)) return w;
  for (const w of whole) if (tokens.includes(w) || squash === w) return w;
  return "";
}

/** The blocked word the text carries, or "" when it is clean. */
export function blockedWord(text: string): string {
  const tokens = cleanTyping(text, 1 << 20).split(" ").filter((t) => t !== "" && !ALLOW.includes(t));
  if (tokens.length === 0) return "";
  const asLeet = tokens.map(leet);
  return find(tokens, BLOCKED, WHOLE) || find(asLeet, BLOCKED, WHOLE) || find(asLeet.map(squeeze), SINGLE_BLOCKED, SINGLE_WHOLE);
}
