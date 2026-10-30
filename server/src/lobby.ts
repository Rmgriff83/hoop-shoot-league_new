/**
 * The matchmaker (docs/BACKEND.md → Phase 3, Ranked): one Durable Object for
 * the whole game, holding at most one waiting player per area, the live
 * room codes, and the ranked queue. Quick match pairs the next two players
 * in an area into one room id; a code names a room a friend can join; the
 * ranked queue pairs by rating inside a window that widens with the wait
 * (data/ranked.json → queue), on a court both own — the lobby's court picker
 * is a PREFERENCE there (Ross, 2026-10-29: both on the beach landed on the
 * cage): the same pick wins, one pick over an ANY wins, otherwise random
 * among the common courts (`pickCourt`) — and remembers the room for the
 * Worker (`ranked_rooms`). Entries expire; the room itself decides fullness
 * and timeouts.
 */
import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";
import { DIVISIONS, QUEUE, TIERS } from "./ranked_data";

export const QUEUE_TTL_MS = 60_000;
export const CODE_TTL_MS = 10 * 60_000;
export const CODE_LEN = 5;
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

interface Waiting { room: string; playerId: string; at: number; areas?: string[] }
const AREAS = ["cage", "beach", "park", "city"];
interface Code { room: string; area: string; playerId: string; at: number }

/** What the game shows of the other player on the face-off card. */
interface Opponent { playerId: string; level: number; tier: string; division: number }
/** `rq:<playerId>` — a player in the ranked queue (the Worker verified every number). */
interface RankedWaiting extends Opponent { room: string; mu: number; rd: number; cons: number; areas: string[]; pref: string; at: number; lean: boolean }
/** `paired:<playerId>` — someone took this host's room; told on the host's next poll. */
interface Paired { room: string; area: string; opponent: Opponent; at: number }

const opponentOf = (w: RankedWaiting): Opponent => ({ playerId: w.playerId, level: w.level, tier: w.tier, division: w.division });
/** A leaning player (losing streak, long away) searches as if rated `below` lower. */
const searchCons = (w: RankedWaiting): number => (w.lean ? w.cons - QUEUE.lean.below : w.cons);

/**
 * The court a ranked pair plays on, from the courts both own (`common`, never
 * empty) and what each picked in the lobby ("any" or a court): the same
 * pick when both own it; a pick over an "any" when the other owns it; else
 * one of the common courts at random. Never blocks a pairing.
 */
export function pickCourt(a: string, b: string, common: string[], random: () => number = Math.random): string {
  // A pick the other side does not own is no pick at all.
  const pa = common.includes(a) ? a : "any";
  const pb = common.includes(b) ? b : "any";
  if (pa !== "any" && pa === pb) return pa;
  if (pa !== "any" && pb === "any") return pa;
  if (pb !== "any" && pa === "any") return pb;
  return common[Math.floor(random() * common.length)];
}

export class Lobby extends DurableObject<Env> {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    const playerId = String(body.playerId ?? "");
    const area = String(body.area ?? "cage");
    const mine = Array.isArray(body.areas) ? (body.areas as string[]).filter((a) => AREAS.includes(a)) : [];
    const now = Date.now();
    if (!playerId) return Response.json({ error: "who" }, { status: 400 });
    switch (url.pathname) {
      case "/quick": {
        // A live waiter in a queue, or null (stale ones are dropped).
        const waiting = async (key: string): Promise<Waiting | null> => {
          const w = await this.ctx.storage.get<Waiting>(key);
          if (!w) return null;
          if (now - w.at >= QUEUE_TTL_MS) { await this.ctx.storage.delete(key); return null; }
          return w;
        };
        const pair = async (key: string, w: Waiting, picked: string) => {
          await this.ctx.storage.delete(key);
          return Response.json({ room: w.room, host: false, area: picked });
        };
        const key = `q:${area}`;
        const w = await waiting(key);
        if (w && w.playerId === playerId) return Response.json({ room: w.room, host: true, area });
        if (area !== "any") {
          // Someone on this court, else someone happy with any court that includes it.
          if (w) return pair(key, w, area);
          const anyW = await waiting("q:any");
          if (anyW && anyW.playerId !== playerId && (anyW.areas ?? []).includes(area)) return pair("q:any", anyW, area);
        } else {
          // Any court I own: the first waiter on one of them, else another any-court player.
          for (const a of mine) {
            const wa = await waiting(`q:${a}`);
            if (wa && wa.playerId !== playerId) return pair(`q:${a}`, wa, a);
          }
          if (w && w.playerId !== playerId) {
            const common = (w.areas ?? []).filter((a) => mine.includes(a));
            const picked = common.length ? common[Math.floor(Math.random() * common.length)] : "cage";
            return pair(key, w, picked);
          }
        }
        const room = crypto.randomUUID();
        await this.ctx.storage.put(key, { room, playerId, at: now, areas: area === "any" ? mine : [area] } satisfies Waiting);
        return Response.json({ room, host: true, area });
      }
      case "/ranked": {
        const ttl = QUEUE.ttl_s * 1000;
        const live = (w: { at: number }) => now - w.at < ttl;
        // Someone already took my room while I was polling: go and host it.
        const pairedKey = `paired:${playerId}`;
        const paired = await this.ctx.storage.get<Paired>(pairedKey);
        if (paired) {
          await this.ctx.storage.delete(pairedKey);
          if (live(paired)) return Response.json({ room: paired.room, host: true, paired: true, area: paired.area, opponent: paired.opponent });
        }
        const myKey = `rq:${playerId}`;
        const old = await this.ctx.storage.get<RankedWaiting>(myKey);
        const me: RankedWaiting = {
          room: old && live(old) ? old.room : crypto.randomUUID(),
          playerId,
          level: Number(body.level) || 1,
          mu: Number(body.mu) || 0,
          rd: Number(body.rd) || 0,
          cons: Number(body.cons) || 0,
          tier: typeof body.tier === "string" ? body.tier : TIERS[0].id,
          division: Number(body.division) || DIVISIONS,
          areas: mine,
          pref: typeof body.pref === "string" && mine.includes(body.pref) ? body.pref : "any",
          at: old && live(old) ? old.at : now, // asking again keeps my place in line
          lean: body.lean === true,
        };
        // The closest live waiter inside the window, which widens with the longer wait;
        // past cap_s anyone on a common court will do.
        let best: { w: RankedWaiting; common: string[] } | null = null;
        let bestDist = Number.POSITIVE_INFINITY;
        const all = await this.ctx.storage.list<RankedWaiting>({ prefix: "rq:" });
        for (const [key, w] of all) {
          if (w.playerId === playerId) continue;
          if (!live(w)) { await this.ctx.storage.delete(key); continue; }
          const common = me.areas.filter((a) => (w.areas ?? []).includes(a));
          if (common.length === 0) continue;
          const waitMe = (now - me.at) / 1000;
          const waitThem = (now - w.at) / 1000;
          const window = QUEUE.window0 + QUEUE.step * Math.floor(Math.max(waitMe, waitThem) / QUEUE.step_s);
          const dist = Math.abs(searchCons(me) - searchCons(w));
          const ok = dist <= window || waitMe >= QUEUE.cap_s || waitThem >= QUEUE.cap_s;
          if (ok && dist < bestDist) { best = { w, common }; bestDist = dist; }
        }
        if (best) {
          const picked = pickCourt(me.pref, best.w.pref ?? "any", best.common);
          await this.ctx.storage.delete([`rq:${best.w.playerId}`, myKey]);
          await this.ctx.storage.put(`paired:${best.w.playerId}`, { room: best.w.room, area: picked, opponent: opponentOf(me), at: now } satisfies Paired);
          try {
            await this.env.DB.prepare("INSERT OR IGNORE INTO ranked_rooms (room, area, a_id, b_id, created_at) VALUES (?1, ?2, ?3, ?4, ?5)")
              .bind(best.w.room, picked, best.w.playerId, playerId, now).run();
          } catch (e) {
            console.error("ranked_rooms", e);
          }
          return Response.json({ room: best.w.room, host: false, paired: true, area: picked, opponent: opponentOf(best.w) });
        }
        await this.ctx.storage.put(myKey, me);
        return Response.json({ room: me.room, host: true, paired: false, waited: Math.floor((now - me.at) / 1000) });
      }
      case "/leave": {
        if (body.ranked === true) {
          await this.ctx.storage.delete([`rq:${playerId}`, `paired:${playerId}`]);
          return Response.json({ ok: true });
        }
        const key = `q:${area}`;
        const w = await this.ctx.storage.get<Waiting>(key);
        if (w && w.playerId === playerId) await this.ctx.storage.delete(key);
        return Response.json({ ok: true });
      }
      case "/code": {
        const bytes = crypto.getRandomValues(new Uint8Array(CODE_LEN));
        const code = [...bytes].map((x) => CODE_ALPHABET[x % CODE_ALPHABET.length]).join("");
        const room = crypto.randomUUID();
        await this.ctx.storage.put(`c:${code}`, { room, area, playerId, at: now } satisfies Code);
        return Response.json({ code, room, area, expiresAt: now + CODE_TTL_MS });
      }
      case "/join": {
        const code = String(body.code ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
        const c = await this.ctx.storage.get<Code>(`c:${code}`);
        if (!c || now - c.at > CODE_TTL_MS) return Response.json({ error: "not_found" }, { status: 404 });
        if (c.playerId === playerId) return Response.json({ error: "own_code" }, { status: 400 });
        await this.ctx.storage.delete(`c:${code}`);
        return Response.json({ room: c.room, area: c.area });
      }
      default:
        return Response.json({ error: "not_found" }, { status: 404 });
    }
  }
}
