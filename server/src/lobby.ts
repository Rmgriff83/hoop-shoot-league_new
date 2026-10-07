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

interface Waiting { room: string; playerId: string; at: number }
interface Code { room: string; area: string; playerId: string; at: number }

export class Lobby extends DurableObject<Env> {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const body = (await request.json().catch(() => ({}))) as Record<string, string>;
    const playerId = body.playerId ?? "";
    const area = body.area ?? "cage";
    const now = Date.now();
    if (!playerId) return Response.json({ error: "who" }, { status: 400 });
    switch (url.pathname) {
      case "/quick": {
        const key = `q:${area}`;
        const w = await this.ctx.storage.get<Waiting>(key);
        if (w && w.playerId === playerId) return Response.json({ room: w.room, host: true });
        if (w && now - w.at < QUEUE_TTL_MS) {
          await this.ctx.storage.delete(key);
          return Response.json({ room: w.room, host: false });
        }
        const room = crypto.randomUUID();
        await this.ctx.storage.put(key, { room, playerId, at: now } satisfies Waiting);
        return Response.json({ room, host: true });
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
        const code = (body.code ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
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
