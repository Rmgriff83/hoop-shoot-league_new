#!/usr/bin/env node
// Create the Play Games achievements from data/achievements.json and write
// Google's generated ids back into its `play_id` column (docs/ACHIEVEMENTS.md
// → Play Games). The twin of tools/asc_achievements.mjs for the Play Games
// Services Publishing API. Zero dependencies (Node ≥ 20: fetch + RS256 in
// crypto). Idempotent: a row whose `play_id` is set is checked, not created;
// a row without one whose player-facing name already exists in the project
// adopts that achievement's id; the rest are inserted.
//
//   node tools/play_achievements.mjs --dry-run      # the plan, no credentials needed
//   node tools/play_achievements.mjs                 # create what is missing, write the ids
//   node tools/play_achievements.mjs --only cage_champion,hard_way
//   node tools/play_achievements.mjs --icons         # only write the 512 px icons (below)
//
// Credentials: a Google service account linked to the Play Console (Users and
// permissions → the account) with the account-level permissions **"Edit
// Google Play Games Services projects"** and "View app information and
// download bulk reports", in a Cloud project where the **Google Play Game
// Services Publishing API** is enabled. By default the one RevenueCat uses
// (~/.config/hoop_shoot/revenuecat/play_service_account.json);
// ~/.config/hoop_shoot/play.env (never in the repo) can point elsewhere:
//   PLAY_SA_JSON=/Users/you/.config/hoop_shoot/playgames/service_account.json
// The game (application) id is data/play_games.json's `game_id`.
//
// Icons: Google's imageConfigurations.upload is deprecated ("attempting to use
// this API causes errors"), so icons are the one by-hand step: this script
// writes 512×512 copies of art/achievements/<key>.png to
// ~/.config/hoop_shoot/playgames/icons/ (sips, macOS) and Ross uploads them in
// Play Console → Play Games Services → Achievements → each row → Icon.
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ROSTER = path.join(ROOT, "data", "achievements.json");
const PLAY_CFG = path.join(ROOT, "data", "play_games.json");
const ICONS = path.join(ROOT, "art", "achievements");
const ICONS_OUT = path.join(os.homedir(), ".config", "hoop_shoot", "playgames", "icons");
const ENV_PATH = path.join(os.homedir(), ".config", "hoop_shoot", "play.env");
const DEFAULT_SA = path.join(os.homedir(), ".config", "hoop_shoot", "revenuecat", "play_service_account.json");
const API = "https://www.googleapis.com/games/v1configuration";
const SCOPE = "https://www.googleapis.com/auth/androidpublisher";
const LOCALE = "en-US";
// Google's limits: 5–200 XP per achievement in steps of 5, 1,000 in all, at
// least five achievements before the project can publish.
const POINT_MIN = 5, POINT_MAX = 200, POINT_STEP = 5, TOTAL_MAX = 1000, MIN_COUNT = 5;

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
const iconsOnly = args.includes("--icons");
const onlyArg = args.find((a) => a.startsWith("--only"));
const only = onlyArg ? (onlyArg.includes("=") ? onlyArg.split("=")[1] : args[args.indexOf(onlyArg) + 1] || "").split(",").filter(Boolean) : null;

function readEnv(p) {
  if (!fs.existsSync(p)) return {};
  const out = {};
  for (const line of fs.readFileSync(p, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*?)\s*$/);
    if (m) out[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
  return out;
}

function loadRoster() {
  const doc = JSON.parse(fs.readFileSync(ROSTER, "utf8"));
  const rows = doc.achievements.map((a, i) => {
    const icon = path.join(ICONS, `${a.key}.png`);
    const size = fs.existsSync(icon) ? fs.statSync(icon).size : 0;
    return { ...a, icon, size, rank: i + 1 };
  });
  const seen = new Set();
  for (const r of rows) {
    if (!/^[a-z0-9_]+$/.test(r.key)) throw new Error(`bad key ${r.key}`);
    if (seen.has(r.key)) throw new Error(`duplicate key ${r.key}`);
    seen.add(r.key);
    if (r.points < POINT_MIN || r.points > POINT_MAX || r.points % POINT_STEP) throw new Error(`${r.key}: points ${r.points} (Play wants ${POINT_MIN}–${POINT_MAX} in steps of ${POINT_STEP})`);
    if (!r.size) throw new Error(`${r.key}: icon missing at ${r.icon}`);
    if (typeof r.play_id !== "string") throw new Error(`${r.key}: play_id must be a string`);
  }
  const total = rows.reduce((n, r) => n + r.points, 0);
  if (total > TOTAL_MAX) throw new Error(`points total ${total} over Play's ${TOTAL_MAX}`);
  if (rows.length < MIN_COUNT) throw new Error(`Play wants at least ${MIN_COUNT} achievements`);
  return only ? rows.filter((r) => only.includes(r.key)) : rows;
}

function gameId() {
  const j = JSON.parse(fs.readFileSync(PLAY_CFG, "utf8"));
  const id = String(j.game_id ?? "");
  if (!/^\d+$/.test(id)) throw new Error(`data/play_games.json game_id is not set (${id || "empty"})`);
  return id;
}

// "NOTHING BUT NET" → "Nothing But Net" for the player-facing name; the
// roster keeps the design's upper case as the reference name.
function titleCase(s) {
  return s.split(" ").map((w) => {
    if (/^[IVX]+$/.test(w)) return w;                 // Sharpshooter I / II / III
    if (/^\d/.test(w)) return w;                        // 10 Ranked Wins
    if (w === "MVP") return w;
    if (w.includes("-")) return w.split("-").map(titleCase).join("-");
    const lower = w.toLowerCase();
    if (["of", "the"].includes(lower)) return lower;
    return lower[0].toUpperCase() + lower.slice(1);
  }).join(" ").replace(/^./, (c) => c.toUpperCase());
}

// ---- the service account's token (RS256 JWT bearer) --------------------------
const b64url = (buf) => Buffer.from(buf).toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
let token = "";
let tokenUntil = 0;
let sa = null;
async function auth() {
  if (token && Date.now() < tokenUntil - 60_000) return token;
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({ iss: sa.client_email, scope: SCOPE, aud: sa.token_uri, iat: now, exp: now + 3600 }));
  const sig = crypto.sign("sha256", Buffer.from(`${header}.${claims}`), sa.private_key);
  const res = await fetch(sa.token_uri, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${header}.${claims}.${b64url(sig)}` }).toString(),
  });
  const j = await res.json().catch(() => ({}));
  if (!res.ok || !j.access_token) throw new Error(`token: ${res.status} ${JSON.stringify(j).slice(0, 300)}`);
  token = j.access_token;
  tokenUntil = Date.now() + (j.expires_in ?? 3600) * 1000;
  return token;
}

// ---- the API ------------------------------------------------------------------
async function api(method, p, body) {
  const url = p.startsWith("http") ? p : API + p;
  const res = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${await auth()}`, "Content-Type": "application/json", Accept: "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = null; }
  if (!res.ok) {
    const detail = json?.error?.message ?? text.slice(0, 400);
    const hint = res.status === 403 ? " (the service account needs 'Edit Google Play Games Services projects' in Play Console → Users and permissions, and the Google Play Game Services Publishing API enabled in the Cloud project; changes take a few minutes)" : "";
    throw new Error(`${method} ${p} → ${res.status} ${detail}${hint}`);
  }
  return json;
}

async function existingAchievements(appId) {
  const out = [];
  let pageToken = "";
  do {
    const q = new URLSearchParams({ maxResults: "200" });
    if (pageToken) q.set("pageToken", pageToken);
    const j = await api("GET", `/applications/${appId}/achievements?${q}`);
    out.push(...(j.items ?? []));
    pageToken = j.nextPageToken ?? "";
  } while (pageToken);
  return out;
}

const nameOf = (a) => (a?.draft?.name?.translations ?? a?.published?.name?.translations ?? []).find((t) => t.locale === LOCALE)?.value ?? "";

function bundle(value) {
  return { kind: "gamesConfiguration#localizedStringBundle", translations: [{ kind: "gamesConfiguration#localizedString", locale: LOCALE, value }] };
}

async function createAchievement(appId, row) {
  return api("POST", `/applications/${appId}/achievements`, {
    kind: "gamesConfiguration#achievementConfiguration",
    achievementType: "STANDARD",
    initialState: row.hidden ? "HIDDEN" : "REVEALED",
    draft: { kind: "gamesConfiguration#achievementConfigurationDetail", name: bundle(titleCase(row.name)), description: bundle(row.unlock), pointValue: row.points },
  });
}

/** Write one row's play_id into data/achievements.json, keeping the file's layout. */
function writePlayId(key, id) {
  const src = fs.readFileSync(ROSTER, "utf8");
  const re = new RegExp(`("key": "${key}"[\\s\\S]*?"play_id": )"[^"]*"`);
  if (!re.test(src)) throw new Error(`${key}: cannot find its play_id slot in data/achievements.json`);
  fs.writeFileSync(ROSTER, src.replace(re, `$1"${id}"`));
}

/** 512 × 512 copies for the Play Console's icon slot (sips: macOS). */
function writeIcons(rows) {
  fs.mkdirSync(ICONS_OUT, { recursive: true });
  let n = 0;
  for (const r of rows) {
    const out = path.join(ICONS_OUT, `${r.key}.png`);
    if (fs.existsSync(out) && fs.statSync(out).mtimeMs >= fs.statSync(r.icon).mtimeMs) continue;
    execFileSync("sips", ["-z", "512", "512", r.icon, "--out", out], { stdio: "ignore" });
    n++;
  }
  console.log(`icons: ${n} written, ${rows.length - n} already current → ${ICONS_OUT}`);
}

async function main() {
  const rows = loadRoster();
  const total = rows.reduce((n, r) => n + r.points, 0);
  console.log(`${rows.length} achievements, ${total} XP, ${rows.filter((r) => r.hidden).length} hidden, ${rows.filter((r) => r.play_id).length} with a play_id already`);
  if (iconsOnly) {
    writeIcons(rows);
    return;
  }
  if (dryRun) {
    for (const r of rows) console.log(`  ${r.key.padEnd(22)} ${String(r.points).padStart(3)} XP ${r.hidden ? "hidden  " : "revealed"} "${titleCase(r.name)}" — ${r.unlock}${r.play_id ? ` [${r.play_id}]` : ""}`);
    console.log("dry run: nothing created. Run without --dry-run with the service account in place.");
    return;
  }
  const env = readEnv(ENV_PATH);
  const saPath = env.PLAY_SA_JSON || DEFAULT_SA;
  if (!fs.existsSync(saPath)) throw new Error(`no service account JSON at ${saPath} (PLAY_SA_JSON in ${ENV_PATH})`);
  sa = JSON.parse(fs.readFileSync(saPath, "utf8"));
  if (!sa.client_email || !sa.private_key || !sa.token_uri) throw new Error(`${saPath} is not a service account key`);
  const appId = gameId();
  console.log(`Play Games project ${appId}, as ${sa.client_email}`);
  const have = await existingAchievements(appId);
  console.log(`${have.length} achievements already in the project`);
  const byId = new Map(have.map((a) => [a.id, a]));
  const byName = new Map(have.map((a) => [nameOf(a), a]));
  let created = 0, adopted = 0, kept = 0;
  const drift = [];
  for (const row of rows) {
    let ach = row.play_id ? byId.get(row.play_id) : null;
    if (row.play_id && !ach) throw new Error(`${row.key}: play_id ${row.play_id} is not in the project (deleted in Play Console?) — clear it to recreate`);
    if (!ach) {
      ach = byName.get(titleCase(row.name));
      if (ach) {
        adopted++;
        console.log(`= ${row.key} adopts ${ach.id} ("${nameOf(ach)}" was already there)`);
      }
    } else {
      kept++;
      console.log(`= ${row.key} ${ach.id}`);
    }
    if (!ach) {
      ach = await createAchievement(appId, row);
      created++;
      console.log(`+ ${row.key} created ${ach.id}`);
    }
    if (ach.id !== row.play_id) writePlayId(row.key, ach.id);
    const d = ach.draft ?? {};
    const desc = (d.description?.translations ?? []).find((t) => t.locale === LOCALE)?.value ?? "";
    if (d.pointValue !== row.points || desc !== row.unlock || ach.initialState !== (row.hidden ? "HIDDEN" : "REVEALED")) drift.push(`${row.key}: project has ${d.pointValue} XP / ${ach.initialState} / "${desc}"`);
  }
  console.log(`done: ${created} created, ${adopted} adopted, ${kept} already linked; ids written to data/achievements.json.`);
  if (drift.length) console.log(`differs from the roster (fix in Play Console or the roster):\n  ${drift.join("\n  ")}`);
  writeIcons(rows);
  console.log("Next (Play Console, by hand): Play Games Services → Achievements → each row → upload its icon from the folder above; then commit data/achievements.json and build.");
}

main().catch((e) => {
  console.error(e.message ?? e);
  process.exit(1);
});
