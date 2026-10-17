/**
 * The matchmaker (docs/BACKEND.md → Phase 3): one Durable Object for the
 * whole game, holding at most one waiting player per area and the live
 * room codes. Quick match pairs the next two players in an area into one
 * room id; a code names a room a friend can join. Entries expire; the
 * room itself decides fullness and timeouts.
 */
import { DurableObject } from "cloudflare:workers";
import type { Env } from "./env";

export const QUEUE_TTL_MS = 60_000;
export const CODE_TTL_MS = 10 * 60_000;
export const CODE_LEN = 5;
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

interface Waiting { room: string; playerId: string; at: number; areas?: string[] }
const AREAS = ["cage", "beach", "park", "city"];
interface Code { room: string; area: string; playerId: string; at: number }

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
      case "/leave": {
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
