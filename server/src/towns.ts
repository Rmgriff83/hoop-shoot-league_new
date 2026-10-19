/**
 * The hometown a phone brings to a match room (design "Online Lobby" 37a,
 * 2026-10-18): shown on the other phone's face-off card. Typed by the
 * player, so it is cleaned the way the client does (core/net/towns.gd
 * Towns.normalize): upper-case A–Z, 0–9 and single spaces, at most 16.
 */
export const TOWN_MAX = 16;

export function cleanTown(raw: string | undefined | null): string {
  if (typeof raw !== "string") return "";
  return raw.toUpperCase().replace(/[^A-Z0-9 ]/g, "").split(" ").filter((p) => p !== "").join(" ").slice(0, TOWN_MAX).trim();
}
