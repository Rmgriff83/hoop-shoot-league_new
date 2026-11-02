# Achievements (Game Center, 2026-11-02)

Ross's forty (`~/Downloads/hoop_shoot_achievements.xlsx` → design
"Achievement Roster"): six categories, 815 of Apple's 1,000 points, four
hidden. Game Center holds them on iOS; Play Games will on Android once that
plugin exists (nothing built yet — see the end).

## The pieces

| Where | What |
|---|---|
| `data/achievements.json` | the roster: `categories` (id, label, colour) and the 40 rows — `key`, `name` (upper case as designed), `category`, `unlock` (the player-facing text), `points`, `hidden`, `source` (`phone` \| `server`), `apple_id` (`hs.ach.<key>`, **permanent once created**), `play_id` (`""` until Play Games) |
| `art/achievements/<key>.png` | the 40 icons, 1024×1024 (from the design project's `export/achievements/`; `art/` is not exported) |
| `core/achievements/achievement_defs.gd` | `AchievementDefs`: the roster read once, `apple_id` ↔ `key`, `MILESTONE_MAP`, `validate()` |
| `core/achievements/achievement_rules.gd` | `AchievementRules`: the thresholds and the pure rule functions, plus `StreakTracker` and `backfill()` |
| `game/autoload/achievements.gd` | `Achievements`: decides, remembers, reports (below) |
| `game/net/platform_backend.gd` | `unlock(id, banner)`, `load_achievements()`, `show_achievements()` — the null backend takes none |
| `game/net/game_center_backend.gd` | the plugin's `award_achievement` / `request_achievements` / `show_game_center` |
| `tools/asc_achievements.mjs` | creates them in App Store Connect (Ross runs it) |
| `tests/test_achievements.gd` | the roster, every rule, the backfill, the autoload over `FakePlatformBackend` |

## The rules

The seven moments the game reports (`Achievements.note_*`) and what they earn:

| Moment | Hook | Earns |
|---|---|---|
| one of the player's shots (`time_trial_screen._on_outcome`; never practice or the tutorial; heats inherit) | `note_shot(made, swish)` | **Nothing But Net** (a swish), **Heating Up** 10 / **On Fire** 25 makes in a row, **Pure** 5 swishes in a row. Streaks reset on GO and on any miss — an iced-out make counts as a miss; a card's streak loan does not count |
| a time trial finished (`App.finish_run`) | `note_run(run)` | **On the Clock**; **Sharpshooter I / II / III** at 20 / 30 / 40 points on any court (Ross, 2026-11-02); **Perfect Run** = `makes == attempts` with at least `PERFECT_RUN_MIN_SHOTS` 10 shots |
| a league heat folded in (`App._apply_league_heat`) | `note_league_heat(ctx)` | **Opening Night** (a win), **Bonus Basketball** (won in OT), **Never Out of It** (won after trailing at the half), **Cage / Beach / Park / City Champion** (the title, by league id), **Hard Way** (the title with AI DIFFICULTY on HARD *at that heat*), and the level's **Beach Bound / Park Regular / City Lights** (`Progression.area_level`: 3 / 4 / 5) and **Hall of Famer** (level 7) |
| a card deployed (`heat_screen._deploy`, after `play_card` accepts) | `note_card(kind, opp_streak)` | **Ace Up the Sleeve**; **Cold Shoulder** when the card is ice and the opponent's streak was ≥ 3 as it landed (read before `play_card`) |
| a PEGGY drop (`App.peggy_drop`) | `note_prize(prize)` | **Drop It** (any prize, not a refund), **Jackpot** (an epic), **Golden Drop** (a legend) |
| an online match settled (`App.settled_online`) | `note_settle(msg, match_how)` | **Run It Back** (won and `match_how == "rematch"`), **Big Steal** (`magnet6` among `spoils.captured`) |
| a weekly time-trial rank (`Net.score_accepted` → `weekRank`; `Net.board_loaded` with period `week` → `me.rank`) | `note_week_rank(rank)` | **Board Member** (≤ 100), **Number One** (1) |

Server milestones (docs/BACKEND.md → Ranked → Stage B) come through
`Platform.milestone_unlocked` and `AchievementDefs.MILESTONE_MAP`:
`first_ranked_win → debut_dub`, `first_capture → spoils`, `tier_starter …
tier_legend` and `ranked_wins_10 / 50 / 100` under their own keys.
`first_login`, `first_ranked_match`, `tier_rookie` and the `division_*`
keys have no achievement. No Worker change was needed.

## How an unlock travels

`Achievements.unlock(key, banner)` — once per key:

1. the key joins `achievements` in the device's **account part** (never
   synced; the record Apple keeps is the durable one) and `unlocked(key)`
   fires;
2. with a signed-in platform, `Platform.backend.unlock(apple_id, banner)`
   reports it complete (GameKit shows its own banner; there is no in-game
   toast). The plugin's completion answer comes back through the event
   queue; an error re-parks the key (`Platform.achievement_failed`);
3. without one (desktop, Android, signed out, the plugin refusing) the key
   waits in `achievementsPending` with its banner flag.

On every platform sign-in (`Platform.signed_in`): the earned list is read
back (`load_achievements` → `{ok, earned}`), Apple's keys are adopted into
the cache (no award, no signal), anything held here that Apple lacks is
parked for a quiet re-report, and the pending queue is flushed. A reinstall
and the sandbox's "reset achievements" both recover that way; a failed read
(`ok` false) re-reports nothing.

**Backfill**: once per device (`account.achievementsBackfilled`; again after
a save pull), `AchievementRules.backfill(state)` grants what the records
already earn, banners off: the level's areas and the Hall, Champions
(`career.championships`), Opening Night (`career.totals.wins`), Heating Up /
On Fire (`career.highs.streak` and the runs' `bestStreak`), On the Clock,
Nothing But Net, the Sharpshooter tiers and a Perfect Run (the saved runs),
Drop It / Jackpot / Golden Drop (owned PEGGY-roster balls and nets, starters
excluded), and the mirrored milestones. Not recoverable (nothing was kept):
Pure, Ace Up the Sleeve, Cold Shoulder, Hard Way, Bonus Basketball, Never
Out of It, Run It Back, Big Steal, the board ranks (those come with the
next score reply or weekly board fetch).

The rewards page's head shows **ACHIEVEMENTS** (`Achievements.can_show()`:
a signed-in platform with a sheet) and opens Apple's Game Center sheet on
the achievements view.

## App Store Connect

Apple needs each achievement created once (ids are permanent, 100 points
each / 1,000 in all, 1024×1024 icons). The v2 API does it all but review
submission:

```
node tools/asc_achievements.mjs --dry-run     # the plan: 40 creates, no key
node tools/asc_achievements.mjs               # create what is missing
```

The script (Node ≥ 20, no packages) reads `~/.config/hoop_shoot/asc.env`
(`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` to the `.p8`, `ASC_APP_ID`
— an App Manager key; never in the repo), mints an ES256 JWT, finds the
app's `gameCenterDetail`, lists the existing achievements by vendor id and
for each missing row: `POST /v2/gameCenterAchievements` (an inline
version), `POST /v2/gameCenterAchievementLocalizations` (en-US; the title
in title case, the unlock text before and after), `POST
/v2/gameCenterAchievementImages` → the `uploadOperations` PUTs → `PATCH
uploaded` → polls `assetDeliveryState` to COMPLETE. Idempotent: a re-run
fills only what a row lacks. **Then, in App Store Connect by hand**: the app
→ Game Center → attach the achievements to the next version and submit it
with that version (sandbox and TestFlight players earn them from the moment
they exist, before review).

## Play Games (not built)

`play_id` sits empty per row. When Android lands: Play Console (or the
Publishing API `achievementConfigurations.insert`) **generates** the ids —
they cannot be chosen like Apple's — with 5–200 XP each and 1,000 in all
(our 815 / max 60 fit), 512×512 icons, and at least five achievements before
Play Games can publish. A `PlayGamesBackend` then maps `key → play_id` where
`GameCenterBackend` maps `apple_id`; nothing in `Achievements` changes.
