# Google Play listing and app content: Hoop Shoot League 1.0

The Play Console's forms, answered field by field (drafted 2026-11-15, the
Play counterpart of APP_STORE_LISTING.md). Play wants most of this before
it lets you create in-app products, and all of it before a closed test or
production. Character counts are checked against Play's limits. The copy
avoids the trailer's banned words, wager wording, other brands' names and
"Plinko".

Package `com.rossgriffus.hoopshootleague`. Personal developer accounts
created after November 2023 must run a **closed test with 12 testers opted
in for 14 continuous days** before they can apply for production access;
the internal track needs none of this.

## Art (made 2026-11-15)

| Slot | Play's rule | File |
|---|---|---|
| App icon | 512 × 512 PNG, ≤ 1 MB | `marketing/store/play/icon_512.png` (the shipped `assets/icon/icon_1024.png` halved) |
| Feature graphic (required) | 1024 × 500 PNG/JPEG | `marketing/store/play/feature_graphic_1024x500.png` (the splash's wall, neon sign and ball; recipe below) |
| Phone screenshots | 2–8, PNG/JPEG, each side 320–3840 px, **longest side ≤ 2 × the shortest** | `marketing/trailer/store/1080x2160/captioned/01_flick … 06_yours.png`, in that order (`python3 -I tools/trailer/store_shots.py --size=1080x2160`: the 1440 × 3120 frames letterboxed on the app's background colour, since the iPhone sizes are 2.17:1 and Play rejects them) |
| 7" / 10" tablet screenshots | optional unless the listing targets tablets | skip; Play may show a "not optimised for tablets" note, which is fine for a phone game |
| Video | optional, a YouTube URL | the trailer, once it is on YouTube |

The feature graphic, one ffmpeg pass over the splash's own art:

```
ffmpeg -y -i assets/splash/neon_bg.png -i assets/splash/neon_text_on.png -i assets/splash/neon_ball_on.png \
  -filter_complex "[0:v]crop=720:352:0:700,scale=1024:501:flags=neighbor,crop=1024:500[bg];\
[1:v]crop=600:410:20:520,scale=540:369:flags=area[txt];[2:v]scale=400:400:flags=area[ball];\
[bg][txt]overlay=50:66[a];[a][ball]overlay=600:50,format=rgb24" \
  -frames:v 1 marketing/store/play/feature_graphic_1024x500.png
```

## Main store listing (Grow users → Store presence → Main store listing)

| Field | Value |
|---|---|
| App name (30) | `Hoop Shoot League` (17) |
| Short description (80) | `Flick-to-shoot arcade hoops: four courts, a league, cards, ranked online play.` (78) |
| Full description (4000) | below |
| Contact email (required, public) | the address on the support page |
| Website | `https://rossgriffus.com/hoop-shoot/` |
| Privacy policy | set under App content, below |

### Full description

The App Store description with the Game Center line taken out (Play Games
achievements are not built yet; put the line back when they are).

```
Flick the ball. Hear the net. Hoop Shoot League is a pocket-sized arcade basketball game where how you swipe decides the shot: a soft flick drops in, a hard one clangs off the back iron, a flat one rattles out.

FOUR COURTS
Shoot in the Arcade Cage, on the Beach at sunset, in the snowy Park and on a City court. Each has its own hoop, its own net and its own league.

RUN THE LEAGUE
Play a season of head-to-head heats against the league's shooters, with your opponent live in the corner. Make the playoffs, win the final, lift the title, then take on the next court.

PLAY YOUR CARDS
Pick your cards before every heat. Deep Freeze your rival's hoop, pull a near miss in with Magnet, catch fire with Heat Check, or put up a Shield.

SOLO OR ONLINE
Chase your best in 60-second time trials and climb the weekly board, or go online for ranked one-on-one matches against real players, with tiers to climb.

MAKE IT YOURS
Collect balls and nets for your locker, and try your aim on PEGGY, the prize-drop machine. Your opponents see your kit in their window.

- One-finger controls, made for portrait play
- Retro pixel style
- Your progress is backed up with your Google account

Hoop Shoot League is free to play with ads between games. A one-time Remove Ads purchase turns them off for good, and optional ticket packs are available in the Ticket Store.

Music: "Moog_SEM 110bpm" by fonoskop (CC BY 4.0).
```

### Store settings (Store presence → Store settings)

| Field | Value |
|---|---|
| App or game | **Game** |
| Category | **Sports** |
| Tags (up to 5) | Basketball, Arcade, Sports, Multiplayer, Casual |
| Store listing contact details | the email above; phone optional |
| External marketing | your choice (default on) |

## App content (Policy and programs → App content)

Work down the list; each one is a short form.

### 1. Privacy policy

`https://rossgriffus.com/hoop-shoot/privacy/` (live since 2026-11-07).

### 2. Ads

**Yes, my app contains ads.** (AdMob interstitials.)

### 3. App access

**All functionality in my app is available without special access.** No
login, no gated content; the anonymous account is made on first launch.

### 4. Content ratings (the IARC questionnaire)

Email: yours. Category: **Game**. Expect **Everyone / PEGI 3** with the
"In-game purchases" and "Users interact" notices; a Teen result is fine
too, the ads already run for a 13+ audience.

| Question | Answer |
|---|---|
| Violence (any kind) | No |
| Fear / horror | No |
| Sexuality / nudity | No |
| Language (profanity, crude humour) | No (names and hometowns pass the word filter) |
| Controlled substances | No |
| Does the game simulate gambling, or teach or glamorise it? | **No.** PEGGY is an aimed drop machine for cosmetic balls and nets; the odds are shown before a play; nothing of real-world value can be won. |
| Does the app allow users to purchase digital goods or services? | **Yes** |
| Does it contain randomised digital items purchasable with real money (loot boxes), if asked | **Yes** — PEGGY plays cost tickets and tickets can be bought; the odds are disclosed in-game. |
| Does the app share the user's current location with other users? | No |
| Does the app allow users to interact or exchange content with other users? | **Yes** — player names and hometowns are shown to other players in online matches and on boards. |
| Unrestricted communication (chat, voice)? | **No** (there is no chat) |
| Can users share their personal information with others? | No |
| Does the app promote or depict crude humour, discrimination, etc.? | No |
| Is the app a web browser or search engine? | No |

### 5. Target audience and content

- Target age groups: **13–15, 16–17, 18 and over**. Do not tick any
  under-13 group (that puts the app under the Families policy, and the ads
  run as not-child-directed).
- "Could your store listing unintentionally appeal to children?" → **No**.

### 6. News apps — **No.**

### 7. COVID-19 contact tracing and status apps — **No** (not a public health app).

### 8. Data safety

**Does your app collect or share any of the required user data types? Yes.**
**Is all of the user data collected by your app encrypted in transit? Yes**
(HTTPS to the Cloudflare Worker and to Google / RevenueCat).
**Do you provide a way for users to request that their data is deleted?
Yes** — in the app, Settings > PLAYER > DELETE ACCOUNT, described at
`https://rossgriffus.com/hoop-shoot/support/` (use that as the deletion
link if the form asks for a URL).

The types. "Shared" is Play's word for a third party using the data for
its own purposes: AdMob's ad data is, nothing else is. Nothing is optional
for the player (there is no opt-out of the game's own account), nothing is
ephemeral.

| Data type | What it is | Collected | Shared | Purposes |
|---|---|---|---|---|
| Location → **Approximate location** | AdMob estimates it from the IP address | Yes | Yes (Google) | Advertising or marketing, Analytics |
| Personal info → **Name** | **No.** The player name is a game handle, filed under "Other user-generated content". | – | – | – |
| Personal info → **User IDs** | the game's anonymous player id (and the platform id it is linked to) | Yes | No | App functionality, Account management |
| Financial info → **Purchase history** | ticket packs and Remove Ads (RevenueCat, your server) | Yes | No | App functionality |
| App activity → **App interactions** | scores, matches, progress, ranking; ad impressions (AdMob) | Yes | Yes (the AdMob part) | App functionality, Analytics, Advertising or marketing |
| App activity → **Other user-generated content** | player name and hometown | Yes | No | App functionality |
| App info and performance → **Crash logs**, **Diagnostics** | the Mobile Ads SDK's own | Yes | Yes (Google) | Analytics |
| Device or other IDs → **Device or other IDs** | the advertising ID (AdMob); the install's own id | Yes | Yes (the advertising ID) | Advertising or marketing, Analytics, App functionality |

Everything else (contacts, photos, camera, microphone, precise location,
health, messages, files, calendar, browsing history, email, address, phone
number, race, politics, credit score…) → not collected.

Before you submit, open Google's own page "Google Mobile Ads SDK → Play
data safety" and add any type it lists that is missing here.

### 9. Advertising ID

**Does your app use advertising ID? Yes.** Purposes: **Advertising or
marketing**, **Analytics**. (The Mobile Ads SDK declares the
`AD_ID` permission in the manifest; the form must agree with it.)

### 10. Government apps — **No.**

### 11. Financial features — **My app doesn't provide any financial features.**

### 12. Health — **My app does not have any health features.**

## Monetisation (Monetize with Play)

- Monetization setup: the merchant (payments) profile, before any product.
- Products → In-app products: `tickets_300` "300 Tickets" $0.99,
  `tickets_1000` "1,000 Tickets" $2.99, `remove_ads` "Remove Ads" $4.99 —
  ids exactly as in `data/store.json`, each set **Active**. No
  consumable flag exists on Play; RevenueCat consumes the packs.
- Settings → License testing: your Gmail, RESPOND_NORMALLY.
- RevenueCat's Play Store app, service account and RTDN topic:
  docs/BUILD.md → The store plugin, and RevenueCat's own Play guide.

## Testing tracks

- **Internal testing** (now): up to 100 testers by email, no forms needed,
  new builds appear in minutes.
- **Closed testing** (next): needs the App content forms and the store
  listing; 12 opted-in testers for 14 days straight before "Apply for
  production access" appears on the dashboard. Testers join through the
  track's opt-in link; a tester who leaves resets nothing but counts no
  longer.
- Play Games Services, achievements and the Play Games sign-in: a later
  checkpoint (docs/BACKEND.md → Play Games).
