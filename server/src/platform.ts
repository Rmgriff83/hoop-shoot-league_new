/**
 * Platform identity proofs (docs/BACKEND.md → Platform identity). The game
 * hands the server a proof it got from Game Center or Play Games; a verifier
 * turns it into the platform's stable player id (`subject`) or throws. Both
 * real verifiers are stubs until the store plugins land — the routes answer
 * 501 — and a `test` verifier exists only in the Vitest env so every flow
 * (link, 409, restore, unlink, delete) is covered now.
 */
import type { Env } from "./env";

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

/**
 * Game Center (iOS). The real check, per Apple's GameKit docs:
 * the game calls `GKLocalPlayer.local.fetchItems(forIdentityVerificationSignature:)`
 * and sends `{publicKeyURL, signature (base64), salt (base64), timestamp,
 * teamPlayerID, gamePlayerID, bundleID}`. The server then
 *   1. fetches the certificate at publicKeyURL — it must be an https URL on an
 *      apple.com host (e.g. static.gc.apple.com), the cert chain valid and not
 *      expired (cache it by URL);
 *   2. rebuilds the payload: UTF-8(teamPlayerID) ‖ UTF-8(bundleID) ‖
 *      timestamp as a big-endian UInt64 ‖ salt bytes;
 *   3. verifies `signature` over that payload with the cert's RSA public key,
 *      SHA-256 (RSASSA-PKCS1-v1_5);
 *   4. rejects a timestamp older than a few minutes (replay) and a bundleID
 *      other than ours.
 * The signed id is the TEAM-scoped player id (teamPlayerID: the same for every
 * game we ship, stable; it changes only if the app moves to another Apple
 * team). gamePlayerID is not covered by the signature — keep it in meta only.
 * The deprecated `playerID` is never used.
 */
class GameCenterVerifier implements ProofVerifier {
  async verify(_proof: unknown): Promise<Verified> {
    throw new NotImplemented("gamecenter");
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
      return new GameCenterVerifier();
    case "playgames":
      return new PlayGamesVerifier();
    case "test":
      return env.PLATFORM_TEST_VERIFIER === "on" ? new TestVerifier() : null;
    default:
      return null;
  }
}

export const isProvider = (v: unknown): v is Provider => v === "gamecenter" || v === "playgames" || v === "test";
