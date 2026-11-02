/**
 * Platform identity proofs (docs/BACKEND.md → Platform identity). The game
 * hands the server a proof it got from Game Center or Play Games; a verifier
 * turns it into the platform's stable player id (`subject`) or throws. Game
 * Center's check is real (2026-11-01); Play Games stays a stub until its
 * plugin lands — its routes answer 501 — and a `test` verifier exists only in
 * the Vitest env so every flow (link, 409, restore, unlink, delete) is
 * covered without a platform.
 */
import type { Env } from "./env";
import { sha256Hex } from "./auth";
import { spkiOf, validityOf } from "./der";

export interface Verified {
  /** The stable platform player id this identity is keyed on. */
  subject: string;
  displayName?: string;
  /** Extra ids worth keeping (Apple's gamePlayerID); stored as JSON in meta, never a proof. */
  meta?: Record<string, string>;
}

export interface ProofVerifier {
  verify(proof: unknown): Promise<Verified>;
}

/** The provider's check is not wired yet → 501. */
export class NotImplemented extends Error {}
/** The proof is malformed or fails the platform's check → 401 proof_rejected. */
export class BadProof extends Error {}

export const PROVIDERS = ["gamecenter", "playgames"] as const;
export type Provider = (typeof PROVIDERS)[number] | "test";

/** Apple's certificate host; a proof pointing anywhere else is refused. */
export const GC_HOST = "static.gc.apple.com";
/** A signature older than this (its own timestamp, ms) is a replay. */
export const GC_MAX_AGE_MS = 10 * 60_000;
/** …and one from further in the future than a clock's drift is forged. */
export const GC_FUTURE_SKEW_MS = 60_000;
/** Used-signature rows older than this are dropped by the cron (db.ts prune). */
export const GC_PROOF_KEEP_MS = 60 * 60_000;
const CERT_TTL_MS = 24 * 3600_000;
const CERT_CACHE_MAX = 16;
const MAX_B64 = 1024;

export type CertFetcher = (url: string) => Promise<ArrayBuffer>;
let certFetcher: CertFetcher | null = null;
/** Tests: a stand-in for fetching Apple's certificate (null restores fetch). */
export function setCertFetcher(f: CertFetcher | null): void {
  certFetcher = f;
}
interface CachedCert { at: number; key: CryptoKey; notBefore: number; notAfter: number }
const certCache = new Map<string, CachedCert>();
export function resetCertCache(): void {
  certCache.clear();
}

async function fetchCert(url: string): Promise<ArrayBuffer> {
  if (certFetcher) return certFetcher(url);
  const r = await fetch(url, { cf: { cacheTtl: 86400, cacheEverything: true } } as RequestInit);
  if (!r.ok) throw new BadProof("cert_fetch");
  return r.arrayBuffer();
}

/** Apple's signing key from the certificate at `url`, cached a day per URL. */
async function appleKey(url: string, now: number): Promise<CachedCert> {
  const hit = certCache.get(url);
  if (hit && now - hit.at < CERT_TTL_MS) return hit;
  const der = new Uint8Array(await fetchCert(url));
  let entry: CachedCert;
  try {
    const { notBefore, notAfter } = validityOf(der);
    const key = await crypto.subtle.importKey("spki", spkiOf(der), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
    entry = { at: now, key, notBefore, notAfter };
  } catch {
    throw new BadProof("cert");
  }
  if (certCache.size >= CERT_CACHE_MAX) certCache.clear();
  certCache.set(url, entry);
  return entry;
}

function b64(v: unknown, what: string): Uint8Array {
  if (typeof v !== "string" || v.length === 0 || v.length > MAX_B64) throw new BadProof(what);
  try {
    return Uint8Array.from(atob(v), (ch) => ch.charCodeAt(0));
  } catch {
    throw new BadProof(what);
  }
}

/**
 * Game Center (iOS), live 2026-11-01. The game calls
 * `GKLocalPlayer.local.fetchItems(forIdentityVerificationSignature:)` (the
 * vendored godot-ios-plugins GameCenter plugin) and sends `{publicKeyURL,
 * signature (base64), salt (base64), timestamp (ms, as GameKit gave it),
 * teamPlayerID}`. Here:
 *   1. the URL must be https on GC_HOST (Apple's own host over TLS stands in
 *      for a chain check — Workers have no X.509 library; the certificate's
 *      validity dates are checked, and it is cached a day per URL);
 *   2. the timestamp must be within GC_MAX_AGE_MS of now (GC_FUTURE_SKEW_MS
 *      ahead at most);
 *   3. `signature` must verify (RSASSA-PKCS1-v1_5, SHA-256) over
 *      UTF-8(teamPlayerID) ‖ UTF-8(APPLE_BUNDLE_ID) ‖ timestamp as a
 *      big-endian UInt64 ‖ salt — the bundle id is ours, never the client's;
 *   4. the signature is taken once (platform_proofs): /v1/link/restore has no
 *      bearer, so a replay inside the window would be an account takeover.
 * The signed id is the TEAM-scoped player id (teamPlayerID: the same for every
 * game we ship, stable; it changes only if the app moves to another Apple
 * team). gamePlayerID is not covered by the signature and the plugin does not
 * hand it over; the deprecated `playerID` is never used.
 */
export class GameCenterVerifier implements ProofVerifier {
  constructor(private env: Env, private now: () => number = Date.now) {}

  async verify(proof: unknown): Promise<Verified> {
    if (!proof || typeof proof !== "object" || Array.isArray(proof)) throw new BadProof("proof");
    const p = proof as Record<string, unknown>;
    for (const k of Object.keys(p)) {
      if (!["publicKeyURL", "signature", "salt", "timestamp", "teamPlayerID"].includes(k)) throw new BadProof("field");
    }
    const subject = p.teamPlayerID;
    if (typeof subject !== "string" || subject.length < 1 || subject.length > 128) throw new BadProof("teamPlayerID");
    if (typeof p.publicKeyURL !== "string" || p.publicKeyURL.length > 512) throw new BadProof("publicKeyURL");
    let url: URL;
    try {
      url = new URL(p.publicKeyURL);
    } catch {
      throw new BadProof("publicKeyURL");
    }
    if (url.protocol !== "https:" || url.hostname !== GC_HOST) throw new BadProof("host");
    const ts = typeof p.timestamp === "number" ? p.timestamp : typeof p.timestamp === "string" && /^\d{1,19}$/.test(p.timestamp) ? Number(p.timestamp) : NaN;
    if (!Number.isSafeInteger(ts) || ts <= 0) throw new BadProof("timestamp");
    const now = this.now();
    if (ts < now - GC_MAX_AGE_MS || ts > now + GC_FUTURE_SKEW_MS) throw new BadProof("stale");
    const signature = b64(p.signature, "signature");
    const salt = b64(p.salt, "salt");
    const bundle = this.env.APPLE_BUNDLE_ID;
    if (!bundle) throw new Error("APPLE_BUNDLE_ID is not set");

    const cert = await appleKey(url.toString(), now);
    if (now < cert.notBefore || now > cert.notAfter) throw new BadProof("cert_expired");
    const enc = new TextEncoder();
    const idBytes = enc.encode(subject);
    const bundleBytes = enc.encode(bundle);
    const payload = new Uint8Array(idBytes.length + bundleBytes.length + 8 + salt.length);
    payload.set(idBytes, 0);
    payload.set(bundleBytes, idBytes.length);
    new DataView(payload.buffer).setBigUint64(idBytes.length + bundleBytes.length, BigInt(ts), false);
    payload.set(salt, idBytes.length + bundleBytes.length + 8);
    const ok = await crypto.subtle.verify({ name: "RSASSA-PKCS1-v1_5" }, cert.key, signature, payload);
    if (!ok) throw new BadProof("signature");

    // Once only.
    const hash = await sha256Hex(p.signature as string);
    try {
      await this.env.DB.prepare("INSERT INTO platform_proofs (sig_hash, seen_at) VALUES (?1, ?2)").bind(hash, now).run();
    } catch (e) {
      if (String((e as Error)?.message ?? e).includes("UNIQUE")) throw new BadProof("replay");
      throw e;
    }
    return { subject };
  }
}

/**
 * Play Games Services v2 (Android). The real check, per Google's "Server-side
 * access to Play Games Services":
 *   1. the game calls `GamesSignInClient.requestServerSideAccess(WEB_CLIENT_ID,
 *      false)` and sends the single-use server auth code plus the player id it
 *      sees locally;
 *   2. the server POSTs https://oauth2.googleapis.com/token with
 *      `grant_type=authorization_code`, `code`, the Game-server credential's
 *      web `client_id` and `client_secret` (Worker secrets, never in the repo),
 *      an empty `redirect_uri`, and gets an access token (scope games_lite);
 *   3. GET https://www.googleapis.com/games/v1/players/me with that token →
 *      `playerId`, which must equal the id the client claimed.
 * The id is the next-generation PER-GAME Play Games player id: stable for this
 * PGS project across devices. The cross-game `developer_player_key` changes on
 * a developer-account transfer and is never a key here.
 */
class PlayGamesVerifier implements ProofVerifier {
  async verify(_proof: unknown): Promise<Verified> {
    throw new NotImplemented("playgames");
  }
}

/** Vitest only (env.PLATFORM_TEST_VERIFIER === "on"): the proof IS the identity. */
class TestVerifier implements ProofVerifier {
  async verify(proof: unknown): Promise<Verified> {
    if (!proof || typeof proof !== "object" || Array.isArray(proof)) throw new BadProof("proof");
    const p = proof as Record<string, unknown>;
    if (typeof p.subject !== "string" || p.subject.length < 1 || p.subject.length > 128) throw new BadProof("subject");
    if (p.reject === true) throw new BadProof("rejected");
    const out: Verified = { subject: p.subject };
    if (typeof p.displayName === "string") out.displayName = p.displayName;
    return out;
  }
}

/** The verifier for a provider, or null for a name we do not know (400). */
export function verifierFor(env: Env, provider: unknown): ProofVerifier | null {
  switch (provider) {
    case "gamecenter":
      return new GameCenterVerifier(env);
    case "playgames":
      return new PlayGamesVerifier();
    case "test":
      return env.PLATFORM_TEST_VERIFIER === "on" ? new TestVerifier() : null;
    default:
      return null;
  }
}

export const isProvider = (v: unknown): v is Provider => v === "gamecenter" || v === "playgames" || v === "test";
