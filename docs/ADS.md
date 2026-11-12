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
| Policy (headless) | `core/ads/ad_policy.gd` — `reason(ctx)` (owner / not_started / not_loaded / grace / gap / "" = show), `should_show(ctx)`, `upsell_due(n, every)` |
| Facade (autoload `Ads`) | `game/ads/ads.gd` — `count_result()`, `gate(then, where)`, `before_results(then)` (both), `after_practice(play_s, then)`, `start_if_needed()`, `due()`, `take_upsell()`, `last_reason` |
| Practice clock (headless) | `core/ads/practice_clock.gd` — a session's live play time (`tick`, `suspend` / `resume`) |
| Null backend | `game/ads/ads_backend.gd` — desktop, headless, QA, phone deploys, owners |
| AdMob backend | `game/ads/admob_backend.gd` — the vendored `Admob` node (addons/AdmobPlugin) |
| The nudge | `game/ads/ads_upsell.gd` — the results screens' side toast |
| Numbers and ids | `data/ads.json` — `policy {grace_matches 3, min_gap_s 120, upsell_every 5, practice_min_s 300}`, per-store `app_id` / `interstitial` |
| The purchase | `Store.owns` / `Store.restore` (game/net/store.gd), the Ticket Store tile, Settings → RESTORE PURCHASES |
| Fake + QA | `tests/fake_ads_backend.gd`, `--qa-ads` (ads_interstitial / ads_results / ads_upsell / ads_owner) |
| Tests | `tests/test_ads.gd`, `tests/test_ticket_store.gd` (entitlements), `server/test/store.test.ts` |

## When an ad plays

Two moves in the facade, apart since Ross's 2026-11-12 policy:
`Ads.count_result()` counts a finished result toward the grace, and
`Ads.gate(then, where)` asks the policy and plays the ad. The policy says
**no** for an owner, without a started network or a loaded interstitial,
during the player's first `grace_matches` (**3**, was 6) results, and
within `min_gap_s` (120 s) of the last ad; then `then` runs at once.
Otherwise the interstitial goes up with the game's sound off (the buses,
not the settings), and `then` runs when it closes — or after `GUARD_S`
(8 s) if the network never reports back. The policy decides BEFORE the
count: the grace is the results before this one. The grace counts results
in the synced settings (`adMatches`), so it follows the player across
phones. Every `upsell_every` (5) ads the next results screen's side toast
says TIRED OF ADS? · REMOVE THEM IN THE TICKET STORE.

- **Time trials and the AI heats (league and quick):** `Ads.before_results
  (then)` = count + gate, before the results screen — `App.finish_run`, and
  `App.to_heat_result` for a heat that is not online. The Area Unlock page's
  GO THERE goes through it too (`heat_screen._after_match_end`), as LATER
  does through `to_heat_result`.
- **Online heats** (ranked, quick, a code, a rematch): the result is counted
  at the buzzer and the post-match page comes **at once** — the room is
  still open with its 60 s rematch window, and an ad would eat it (and
  land its loss of focus on an open room). The ad plays on the way **out**,
  through `App.leave_online(then)`: the room closes FIRST, then the gate,
  then the destination. The ways out: HOME, SHOOT AROUND?, the room ending
  under the player (the window expiring, them leaving, a rematch that
  failed to open — the card reads THEY LEFT; the ad plays right then, over
  the page, once, and HOME after it gates nothing: `heat_result_screen.
  watch_room`), and a rematch's room failing before the tip-off (the
  pre-match page's "failed"). A rematch that **goes** shows no ad; a chain
  of rematches gets one, when the player finally leaves. The Android back
  button is not handled anywhere (Godot's default quits the app, on every
  screen); nothing to gate there, by Ross's call.
- **Practice** (endless, no results): one chance at an ad on QUIT when the
  session's live play ran `practice_min_s` (300 s) or more —
  `Ads.after_practice(play_s, then)` from `time_trial_screen._quit_to_title`.
  `PracticeClock` counts only live frames: the tree's pause (the pause
  menu) stops them, the app in the background suspends it
  (`NOTIFICATION_APPLICATION_PAUSED` / `FOCUS_OUT`), the first-shot lesson
  and a held match are skipped, and a frame over 0.25 s counts as 0.25 s.
  Under the threshold it is `practice_short`; above it the normal policy
  applies and a no (nothing loaded, the gap) is simply skipped. A practice
  exit is never a result: the grace does not move. The clock is the
  screen's, so a new session starts at zero.

**Why the last gate did what it did:** `Ads.last_reason` — `shown`,
`failed` (it went up and never played), `owner`, `not_started`,
`not_loaded`, `grace`, `gap`, `practice_short` — for the QA driver and the
log: a debug build `push_warning`s `ads: <reason> (<where>)` at every gate.
Nothing user-facing.

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
   consent + tracking prompts once; an interstitial before the results of
   the 4th result (three of grace); an online match → no ad before the
   post-match page, REMATCH? live for its minute, the ad on HOME (and the
   other phone's card reads THEY LEFT only after our ad went up — the room
   closes first); a rematch that goes → no ad; a 5-minute practice → an ad
   on QUIT, a short one none; the debug log's `ads: <reason>` line at each.
   For the first round, Google's test unit ids go in `data/ads.json`.
   The real interstitial unit replaced the test unit on 2026-11-07 for the
   App Store release. Add your own phones as test devices in AdMob
   (Settings → Test devices) so their impressions never count.
7. Later: the Play Console → the Android AdMob app, `goog_` key, the Play
   non-consumable.
