# Ads and Remove Ads (2026-11-01)

Interstitials between games for everyone who does not own **remove_ads**,
through AdMob; the purchase that turns them off, through RevenueCat. Ross's
outline ("Hoop Shoot — Remove Ads and Ads Integration", 2026-11-01) is the
spec; the calls he made: $4.99, rewarded ads later, app-ads.txt on
rossgriffus.com, iOS first, the ad before the results screen, a 2-minute gap
plus a new-player grace, a 13+ audience, only remove_ads removes ads.

## The rule

- **Owners never see an interstitial, and the ads SDK never starts for
  them** — no consent form, no tracking prompt, no memory or frame time
  spent. `Ads.owner()` = `Store.owns("remove_ads")`.
- **Ticket packs do not remove ads.** Only the remove_ads product does.
- **No path from ads to online cards**, as for money (docs/ECONOMY.md).
- Rewarded ads ("watch to double your tickets") are a later pass; the
  facade leaves the seam (an `AdsBackend` grows `load_rewarded` /
  `show_rewarded`; owners may opt in — Ross).

## The pieces

| Piece | Where |
|---|---|
| Policy (headless) | `core/ads/ad_policy.gd` — `should_show(ctx)`, `upsell_due(n, every)` |
| Facade (autoload `Ads`) | `game/ads/ads.gd` — `before_results(then)`, `start_if_needed()`, `due()`, `take_upsell()` |
| Null backend | `game/ads/ads_backend.gd` — desktop, headless, QA, phone deploys, owners |
| AdMob backend | `game/ads/admob_backend.gd` — the vendored `Admob` node (addons/AdmobPlugin) |
| The nudge | `game/ads/ads_upsell.gd` — the results screens' side toast |
| Numbers and ids | `data/ads.json` — `policy {grace_matches 6, min_gap_s 120, upsell_every 5}`, per-store `app_id` / `interstitial` |
| The purchase | `Store.owns` / `Store.restore` (game/net/store.gd), the Ticket Store tile, Settings → RESTORE PURCHASES |
| Fake + QA | `tests/fake_ads_backend.gd`, `--qa-ads` (ads_interstitial / ads_results / ads_upsell / ads_owner) |
| Tests | `tests/test_ads.gd`, `tests/test_ticket_store.gd` (entitlements), `server/test/store.test.ts` |

## When an ad plays

Both results moves in `App` — `finish_run` (time trials) and
`to_heat_result` (league, quick and online heats) — go through
`Ads.before_results(then)`. The policy says **no** for an owner, without a
started network or a loaded interstitial, during the player's first
`grace_matches` (6) results, and within `min_gap_s` (120 s) of the last ad;
then `then` runs at once. Otherwise the interstitial goes up with the
game's sound off (the buses, not the settings), and `then` runs when it
closes — or after `GUARD_S` (8 s) if the network never reports back. The
grace counts results in the synced settings (`adMatches`), so it follows
the player across phones. Every `upsell_every` (5) ads the next results
screen's side toast says TIRED OF ADS? · REMOVE THEM IN THE TICKET STORE.

## The start (AdMob)

`Ads.start_if_needed()` at launch and on `Net.account_ready`: for a
non-owner with a live plugin and real ids, `AdMobBackend.start(cfg)` builds
the `Admob` node (real ids, content rating PG, not child-directed, ATT
text) and runs **UMP consent** (`update_consent_info` → REQUIRED →
`load_consent_form` / `show_consent_form`; the form exists only where the
law asks, the EEA/UK) → on iOS the **tracking prompt**
(`request_tracking_authorization`, granted or denied) → `initialize()` →
the first `load_interstitial_ad`. A failed load retries after 30 s; a
close reloads at once. Placeholder ids in `data/ads.json` (`REPLACE_ME`)
mean `platform_cfg()` is empty and nothing starts — today's state until
Ross's AdMob app exists.

## Remove ads (the purchase)

`remove_ads` is an App Store **non-consumable** ($4.99) attached to the
RevenueCat entitlement `remove_ads` (`data/store.json → entitlements`).
`Store.owns(key)` is the union of two sources, cached in the synced
settings (`entitlements`) so an owner never sees ads offline — a
hand-edited cache hides ads for free; the stakes are low and Ross accepted
that:

1. the SDK's active entitlements (`customer_info` after `configure`, a
   sheet, a restore, and `customer_info_changed` any time);
2. the Worker's books (`GET /v1/me → entitlements`, from the webhook:
   docs/BACKEND.md → Ticket store → Entitlements).

A revoke (a refund) comes through either and clears the key. The Ticket
Store's tile runs ask → busy → **OWNED** on the SDK's word (or `slow` until
the webhook lands it); **RESTORE PURCHASES** (the tile's row and
Settings → MORE; App Store Review 3.1.1) wraps the SDK's restore — from a
tap only, the OS may ask for a sign-in — and ends RESTORED / NOTHING TO
RESTORE / RESTORE FAILED. A reinstalled phone has a new player id: the
restore moves the receipt to it (RevenueCat's default "transfer to new App
User ID") and a `TRANSFER` webhook moves the Worker's row.

## Ross's setup

1. **App Store Connect:** Non-Consumable `remove_ads`, $4.99 tier,
   localisation + the review screenshot; the app's marketing URL
   `https://rossgriffus.com`.
2. **RevenueCat:** product `remove_ads`, entitlement `remove_ads` attached;
   restore behaviour left at "Transfer to new App User ID".
3. **Worker first** (docs/BACKEND.md): migration 0011 + `wrangler deploy`
   before the product goes live.
4. **AdMob:** account, the iOS app linked to the listing, one interstitial
   unit; the app id and unit id into `data/ads.json`; Privacy & messaging →
   a GDPR consent message; `https://rossgriffus.com/app-ads.txt` with the
   line AdMob gives (`google.com, pub-…, DIRECT, f08c47fec0942fa0`).
5. **App Privacy** (App Store Connect): tracking yes (ATT), the ads data
   types. The plugin injects `GADApplicationIdentifier`,
   `NSUserTrackingUsageDescription` and the SKAdNetwork list into the plist
   at export (docs/BUILD.md → The ads plugin).
6. **TestFlight:** buy remove_ads → OWNED, no ad after the next game; a
   sandbox refund → ads back on relaunch; delete + reinstall → ads →
   RESTORE PURCHASES → OWNED and a `TRANSFER` 200 in the delivery log;
   consent + tracking prompts once; an interstitial before results after the
   grace. For the first round, Google's test unit ids go in `data/ads.json`.
   The real interstitial unit replaced the test unit on 2026-11-07 for the
   App Store release. Add your own phones as test devices in AdMob
   (Settings → Test devices) so their impressions never count.
7. Later: the Play Console → the Android AdMob app, `goog_` key, the Play
   non-consumable.
