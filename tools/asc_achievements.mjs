#!/usr/bin/env node
// Create the Game Center achievements in App Store Connect from
// data/achievements.json (docs/ACHIEVEMENTS.md → App Store Connect).
// Zero dependencies (Node ≥ 20: fetch + ES256 in crypto). Idempotent: an
// achievement whose vendor id (`apple_id`) already exists is left alone
// except for the pieces it is missing (its localization, its icon).
//
//   node tools/asc_achievements.mjs --dry-run      # the plan, no key needed
//   node tools/asc_achievements.mjs                 # create what is missing
//   node tools/asc_achievements.mjs --only cage_champion,hard_way
//
// Needs ~/.config/hoop_shoot/asc.env (never in the repo):
//   ASC_KEY_ID=ABC123DEFG           # App Store Connect → Users and Access → Integrations → Team Keys
//   ASC_ISSUER_ID=xxxxxxxx-...      # the issuer id shown above the keys
//   ASC_KEY_PATH=/Users/you/.config/hoop_shoot/AuthKey_ABC123DEFG.p8
//   ASC_APP_ID=1234567890           # the app's numeric Apple ID (App Information → General)
// The key needs the App Manager role (Developer can read but not create).
// After it runs: App Store Connect → the app → Game Center → the next app
// version's "Game Center" box → add the achievements → submit with that
// version (the API creates and uploads; review submission is the UI's).
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import crypto from "node:crypto";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const ROSTER = path.join(ROOT, "data", "achievements.json");
const ICONS = path.join(ROOT, "art", "achievements");
const ENV_PATH = path.join(os.homedir(), ".config", "hoop_shoot", "asc.env");
const API = "https://api.appstoreconnect.apple.com";
const LOCALE = "en-US";

const args = process.argv.slice(2);
const dryRun = args.includes("--dry-run");
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
  const rows = doc.achievements.map((a) => {
    const icon = path.join(ICONS, `${a.key}.png`);
    const size = fs.existsSync(icon) ? fs.statSync(icon).size : 0;
    return { ...a, icon, size };
  });
  const seen = new Set();
  for (const r of rows) {
    if (!/^hs\.ach\.[a-z0-9_]+$/.test(r.apple_id)) throw new Error(`${r.key}: bad apple_id ${r.apple_id}`);
    if (seen.has(r.apple_id)) throw new Error(`duplicate apple_id ${r.apple_id}`);
    seen.add(r.apple_id);
    if (r.points < 1 || r.points > 100) throw new Error(`${r.key}: points ${r.points}`);
    if (!r.size) throw new Error(`${r.key}: icon missing at ${r.icon}`);
  }
  const total = rows.reduce((n, r) => n + r.points, 0);
  if (total > 1000) throw new Error(`points total ${total} over Apple's 1000`);
  return only ? rows.filter((r) => only.includes(r.key)) : rows;
}

// ---- JWT (ES256) --------------------------------------------------------------
function b64url(buf) {
  return Buffer.from(buf).toString("base64").replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}
function derToJose(der) {
  // DER ECDSA signature → raw r||s (64 bytes) for JWS.
  let i = 2;
  if (der[0] !== 0x30) throw new Error("bad DER");
  if (der[1] & 0x80) i = 2 + (der[1] & 0x7f);
  const take = () => {
    if (der[i++] !== 0x02) throw new Error("bad DER int");
    let len = der[i++];
    let v = der.subarray(i, i + len);
    i += len;
    while (v.length > 32 && v[0] === 0) v = v.subarray(1);
    return Buffer.concat([Buffer.alloc(32 - v.length), v]);
  };
  return Buffer.concat([take(), take()]);
}
function makeToken(env) {
  const key = fs.readFileSync(env.ASC_KEY_PATH, "utf8");
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: env.ASC_KEY_ID, typ: "JWT" }));
  const payload = b64url(JSON.stringify({ iss: env.ASC_ISSUER_ID, iat: now, exp: now + 19 * 60, aud: "appstoreconnect-v1" }));
  const sig = crypto.sign("sha256", Buffer.from(`${header}.${payload}`), { key, dsaEncoding: "der" });
  return `${header}.${payload}.${b64url(derToJose(sig))}`;
}

// ---- the API ------------------------------------------------------------------
let token = "";
let tokenAt = 0;
let env = {};
function auth() {
  if (!token || Date.now() - tokenAt > 15 * 60 * 1000) {
    token = makeToken(env);
    tokenAt = Date.now();
  }
  return token;
}
async function api(method, p, body) {
  const url = p.startsWith("http") ? p : API + p;
  const res = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${auth()}`, "Content-Type": "application/json", Accept: "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = null; }
  if (!res.ok) {
    const detail = json?.errors?.map((e) => `${e.code ?? e.status}: ${e.title} — ${e.detail ?? ""}`).join("; ") ?? text.slice(0, 400);
    throw new Error(`${method} ${p} → ${res.status} ${detail}`);
  }
  return json;
}
async function listAll(p) {
  const out = [];
  let next = p;
  while (next) {
    const j = await api("GET", next);
    out.push(...(j.data ?? []));
    next = j.links?.next ?? null;
  }
  return out;
}

async function gameCenterDetailId(appId) {
  const j = await api("GET", `/v1/apps/${appId}/gameCenterDetail`);
  if (!j?.data?.id) throw new Error("the app has no Game Center detail: turn Game Center on in App Store Connect first");
  return j.data.id;
}

async function existingAchievements(detailId) {
  const rows = await listAll(`/v1/gameCenterDetails/${detailId}/gameCenterAchievementsV2?limit=200&filter[archived]=false`);
  const byVendor = new Map();
  for (const a of rows) byVendor.set(a.attributes.vendorIdentifier, a);
  return byVendor;
}

async function versionOf(achievementId) {
  const vs = await listAll(`/v2/gameCenterAchievements/${achievementId}/versions?limit=50`);
  if (vs.length) return vs[vs.length - 1];
  return null;
}

async function createAchievement(detailId, row) {
  const body = {
    data: {
      type: "gameCenterAchievements",
      attributes: { referenceName: row.name, vendorIdentifier: row.apple_id, points: row.points, showBeforeEarned: !row.hidden, repeatable: false },
      relationships: {
        gameCenterDetail: { data: { type: "gameCenterDetails", id: detailId } },
        versions: { data: [{ type: "gameCenterAchievementVersions", id: "${version}" }] },
      },
    },
    included: [{ type: "gameCenterAchievementVersions", id: "${version}" }],
  };
  const j = await api("POST", "/v2/gameCenterAchievements", body);
  return j.data;
}

async function localizationOf(versionId) {
  const ls = await listAll(`/v2/gameCenterAchievementVersions/${versionId}/localizations?limit=50`);
  return ls.find((l) => l.attributes.locale === LOCALE) ?? null;
}

async function createLocalization(versionId, row) {
  const j = await api("POST", "/v2/gameCenterAchievementLocalizations", {
    data: {
      type: "gameCenterAchievementLocalizations",
      attributes: { locale: LOCALE, name: titleCase(row.name), beforeEarnedDescription: row.unlock, afterEarnedDescription: row.unlock },
      relationships: { version: { data: { type: "gameCenterAchievementVersions", id: versionId } } },
    },
  });
  return j.data;
}

async function imageOf(localizationId) {
  try {
    const j = await api("GET", `/v2/gameCenterAchievementLocalizations/${localizationId}/image`);
    return j?.data ?? null;
  } catch (e) {
    if (/404/.test(String(e.message))) return null;
    throw e;
  }
}

async function uploadImage(localizationId, row) {
  const bytes = fs.readFileSync(row.icon);
  const made = await api("POST", "/v2/gameCenterAchievementImages", {
    data: {
      type: "gameCenterAchievementImages",
      attributes: { fileName: `${row.key}.png`, fileSize: bytes.length },
      relationships: { localization: { data: { type: "gameCenterAchievementLocalizations", id: localizationId } } },
    },
  });
  const img = made.data;
  for (const op of img.attributes.uploadOperations ?? []) {
    const headers = {};
    for (const h of op.requestHeaders ?? []) headers[h.name] = h.value;
    const chunk = bytes.subarray(op.offset, op.offset + op.length);
    const res = await fetch(op.url, { method: op.method, headers, body: chunk });
    if (!res.ok) throw new Error(`${row.key}: icon chunk upload → ${res.status} ${await res.text()}`);
  }
  await api("PATCH", `/v2/gameCenterAchievementImages/${img.id}`, { data: { type: "gameCenterAchievementImages", id: img.id, attributes: { uploaded: true } } });
  for (let i = 0; i < 30; i++) {
    const j = await api("GET", `/v2/gameCenterAchievementImages/${img.id}`);
    const st = j.data.attributes.assetDeliveryState;
    if (st?.state === "COMPLETE") return j.data;
    if (st?.state === "FAILED") throw new Error(`${row.key}: icon processing failed: ${JSON.stringify(st.errors)}`);
    await new Promise((r) => setTimeout(r, 2000));
  }
  console.warn(`  ${row.key}: icon still processing (check App Store Connect)`);
  return img;
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

async function main() {
  const rows = loadRoster();
  const total = rows.reduce((n, r) => n + r.points, 0);
  console.log(`${rows.length} achievements, ${total} points, ${rows.filter((r) => r.hidden).length} hidden; icons ${(rows.reduce((n, r) => n + r.size, 0) / 1024).toFixed(0)} KiB`);
  if (dryRun) {
    for (const r of rows) console.log(`  ${r.apple_id.padEnd(26)} ${String(r.points).padStart(3)} pts ${r.hidden ? "hidden " : "shown  "} "${titleCase(r.name)}" — ${r.unlock} [${(r.size / 1024).toFixed(1)} KiB]`);
    console.log("dry run: nothing created. Put the key in ~/.config/hoop_shoot/asc.env and run without --dry-run.");
    return;
  }
  env = readEnv(ENV_PATH);
  for (const k of ["ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH", "ASC_APP_ID"]) if (!env[k]) throw new Error(`${k} missing from ${ENV_PATH}`);
  const detailId = await gameCenterDetailId(env.ASC_APP_ID);
  console.log(`Game Center detail ${detailId}`);
  const have = await existingAchievements(detailId);
  console.log(`${have.size} achievements already in App Store Connect`);
  let created = 0, localized = 0, imaged = 0;
  for (const row of rows) {
    let ach = have.get(row.apple_id);
    if (!ach) {
      ach = await createAchievement(detailId, row);
      created++;
      console.log(`+ ${row.apple_id} created (${ach.id})`);
    } else {
      console.log(`= ${row.apple_id} exists (${ach.id})`);
    }
    let version = await versionOf(ach.id);
    if (!version) throw new Error(`${row.key}: no version on ${ach.id} (archived in App Store Connect?)`);
    let loc = await localizationOf(version.id);
    if (!loc) {
      loc = await createLocalization(version.id, row);
      localized++;
      console.log(`  + ${LOCALE} localization`);
    }
    const img = await imageOf(loc.id);
    if (!img) {
      await uploadImage(loc.id, row);
      imaged++;
      console.log(`  + icon ${row.key}.png`);
    }
  }
  console.log(`done: ${created} created, ${localized} localized, ${imaged} icons uploaded.`);
  console.log("Next (App Store Connect, by hand): the app → Game Center → attach the achievements to the next version and submit it. Sandbox/TestFlight players earn them from now.");
}

main().catch((e) => {
  console.error(e.message ?? e);
  process.exit(1);
});
