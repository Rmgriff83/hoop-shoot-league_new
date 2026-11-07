# App Store listing: Hoop Shoot League 1.0

The text to paste into App Store Connect, field by field (drafted 2026-11-06).
Character counts are checked against Apple's limits. The copy avoids the
trailer's banned words, wager wording, other brands' names and "Plinko".

## App Information (App Store Connect → your app → General → App Information)

| Field | Value |
|---|---|
| Name (30) | `Hoop Shoot League` (17) |
| Subtitle (30) | `Flick-to-shoot arcade hoops` (27) |
| Primary category | Games → **Sports** |
| Secondary category | Games → **Arcade** |
| Content rights | **Yes, it contains third-party content, and I have the rights to use it.** (The CC BY music, the licensed art packs and sounds; all credited in CREDITS.) |
| Privacy Policy URL | `https://rossgriffus.com/hoop-shoot/privacy/` |
| User Privacy Choices URL | leave empty (optional) |

### Age rating questionnaire

Answer it as follows. Expect **9+**. A 13+ result is fine too: the ads are
already set up for a 13+ audience.

| Question | Answer |
|---|---|
| Violence (cartoon, realistic, graphic, prolonged) | None |
| Sexual content / nudity | None |
| Profanity or crude humour | None (names and hometowns pass the word filter) |
| Alcohol, tobacco, drugs | None |
| Mature / suggestive themes, horror / fear | None |
| Medical / treatment information | None |
| Gambling (real money) | No |
| Simulated gambling | **None.** PEGGY is an aimed drop machine for cosmetics. Nothing pays out tickets or money beyond its own small refund. |
| Contests | No |
| Loot boxes / paid random items (if asked) | **Yes.** PEGGY plays cost tickets, and tickets can be bought. See "PEGGY odds" at the end. |
| Unrestricted web access | No |
| User-generated content | **Yes.** Player names and hometowns are shown to other players. They are word-filtered and there is no chat. |
| Messaging and chat | No |
| Advertising | Yes |
| Parental controls / age assurance | No |
| Made for Kids | **No** |

## Pricing and Availability

- Price: **Free**. Availability: all countries, or pick yours.
- In-app purchases (already set up): `tickets_300` $0.99, `tickets_1000`
  $2.99, `remove_ads` $4.99 (non-consumable).

## App Privacy (App Store Connect → App Privacy)

**Do you or your third-party partners collect data from this app? Yes.**

| Data type | Collected by | Linked to the user? | Used for tracking? | Purposes |
|---|---|---|---|---|
| **Contact Info → Name**: no | | | | (the player name is a game handle, filed under "Other User Content" below) |
| **User Content → Other User Content** (player name, hometown) | your server | Yes | No | App Functionality |
| **Identifiers → User ID** (the game's player id, Game Center id) | your server, RevenueCat | Yes | No | App Functionality |
| **Identifiers → Device ID** (the advertising identifier) | AdMob | No | **Yes** | Third-Party Advertising |
| **Purchases → Purchase History** | RevenueCat, your server | Yes | No | App Functionality |
| **Usage Data → Product Interaction** (scores, matches, progress) | your server | Yes | No | App Functionality |
| **Usage Data → Advertising Data** | AdMob | No | **Yes** | Third-Party Advertising |
| **Location → Coarse Location** (from the IP address) | AdMob | No | **Yes** | Third-Party Advertising |
| **Diagnostics → Crash Data, Performance Data** | AdMob | No | No | Analytics |
| **Gameplay content** (your saved progress) | your server | Yes | No | App Functionality |

Before you submit, check this against Google's own page for the AdMob SDK
("Google Mobile Ads SDK: App Store data disclosure"). If Google lists a
type not here (for example Other Diagnostic Data), add it.

## Version 1.0 page

### Promotional text (170; editable any time without review)

```
Flick to shoot on four courts, run the league, play power-up cards and climb the ranked ladder against real players.
```
(116)

### Description (4000)

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
- 40 Game Center achievements
- Your progress follows you to a new phone

Hoop Shoot League is free to play with ads between games. A one-time Remove Ads purchase turns them off for good, and optional ticket packs are available in the Ticket Store.

Music: "Moog_SEM 110bpm" by fonoskop (CC BY 4.0).
```

### Keywords (100; commas, no spaces)

```
basketball,arcade,flick,swish,hoops,court,ranked,pvp,multiplayer,retro,pixel,trick shot,free throw
```
(98. The words in the name and subtitle are indexed already, so they are not repeated here.)

### URLs and copyright

| Field | Value |
|---|---|
| Support URL (required) | `https://rossgriffus.com/hoop-shoot/support/` |
| Marketing URL | `https://rossgriffus.com/hoop-shoot/` |
| Copyright | `2026 Ross Griffus` |
| Version | `1.0.0` (project.godot) |

### Screenshots (6.9" iPhone slot, 1290 × 2796)

These are made by `python3 -I tools/trailer/store_shots.py` from the
trailer's App Store clips and saved to `marketing/trailer/store/`. There are
two sets: `captioned/` (recommended) and `clean/`. Upload them in this
order; the first three show in search results.

1. `01_flick`: EVERY FLICK COUNTS
2. `02_courts`: FOUR COURTS (the four courts in a grid)
3. `03_league`: RUN THE LEAGUE (champions)
4. `04_cards`: PLAY YOUR CARDS (the card pick)
5. `05_online`: SOLO OR ONLINE (the ranked face-off)
6. `06_yours`: MAKE IT YOURS (the locker)

The app is iPhone only (`targeted_device_family=0`), so no iPad
screenshots are needed. Apple scales the 6.9" set down for smaller phones.

If App Store Connect calls a set an invalid size, the slot wants another
size: `python3 -I tools/trailer/store_shots.py --size=1320x2868` (6.9"),
`--size=1284x2778` or `--size=1242x2688` (6.5"), `--size=1206x2622` or
`--size=1179x2556` (6.1" / 6.3"), each written to
`marketing/trailer/store/<W>x<H>/` (all made 2026-11-07). The 6.1" / 6.3"
slot takes the 886 x 1920 app preview too.

### Game Center

Attach the 40 achievements (`hs.ach.*`) in the version's Game Center
section.

### In-App Purchases and Subscriptions

Attach `tickets_300`, `tickets_1000` and `remove_ads`. A first in-app
purchase can only be reviewed together with an app version.

### App Review Information

- Sign-in required: **No** (accounts are anonymous and created on first
  launch).
- Contact: your name, phone and email.
- Notes:

```
Hoop Shoot League needs no sign-in: an anonymous player account is created on the first launch after the player enters a name.

How to play: swipe up on the ball to shoot. The league matches and the 60-second TIME TRIAL, both on the home screen, work without another player.

Online ranked matches pair two real players. If no one else is searching, matchmaking keeps waiting; the rest of the game does not depend on it.

In-app purchases: the Ticket Store (tap the tickets counter at the top of the home screen) sells two ticket packs and Remove Ads. RESTORE PURCHASES is in the Ticket Store and in Settings > MORE.

Ads: interstitials appear between games after a new player's first 6 results, never during play. The tracking permission prompt appears before ads start.

Account deletion: Settings > PLAYER > DELETE ACCOUNT (tap twice) deletes the online account and its data.

PEGGY (Locker > PLAY PEGGY) is a prize-drop machine for cosmetic balls and nets: the player aims the drop, every prize plate's rarity is shown, the odds of each rarity are shown under PLAY before the player spends anything, and plates only hold items the player does not own yet. Nothing of real-world value can be won.
```

### Version Release

**Manually release this version.** You choose launch day after approval.

## PEGGY odds (done 2026-11-06)

Guideline 3.1.1 asks that random items sold for money show their odds
before purchase. A PEGGY play costs 300 tickets, and tickets can be bought,
so the PEGGY page shows a line under PLAY, e.g. `ODDS FROM THE CENTRE` /
`RARE 13% · COMMON 87%`. It is worked out from the plates currently on the
board and `PeggyBoard.CENTRE_ODDS` (the board's measured odds from the
centre). The line is in the build after Build 498.
