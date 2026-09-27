# Economy — the two currencies and their rulebook

Two currencies, two wallets, one governed system. This is the document to
read before adding an item, a mode or a league, or changing a price or a
reward. Cards' own balance (power, rarity, AI parity) is `docs/CARDS.md`.

| | **Tickets** | **Coins** |
|---|---|---|
| Scope | global | **one wallet per league** |
| Earned by | time trials (never practice), league heats, a league title | that league's heats and title |
| Spent on | balls and hoops at the **locker** (home page) | that league's power-up cards in its **shop** (league hub) |
| Lives in | save part `cosmetics` → `tickets` | save part `cards` v3 → `leagues[id].coins`, beside that league's `inventory` / `loadout` |
| Code | `App.tickets()`, `grant_tickets`, `try_buy(kind, id)` | `App.league_coins(id)`, `grant_league_coins(n, id)`, `try_buy_card(card, id)` |

**Why segmented:** coins earned in the easy league can never buy cards for
the hard league, and cards dropped or bought in a league play only there.
Multiplayer inherits the same shape later. **Why two:** cosmetics are a
long-term chase paid by every timed mode; cards are a league's own economy.
**Real money later** buys the currencies themselves (ticket / coin packs),
so earn rates are tuned for an average player to buy steadily without being
starved, while a pack is an honest shortcut.

## Earning

Everything is data. The arithmetic is `core/economy/economy.gd` (`Economy`).

**Time trial** — `data/economy.json` → `tickets.trial`:
`round((base + per_point × score) × location_mult) + new_best`.
Practice never pays: endless modes have no clock to run out, so
`App.finish_run` is never reached. Tickets are granted there and shown on
the results screen (`+N TICKETS`).

**League heat** — `data/leagues.json` → each league's `rewards`:
`win_coins / loss_coins / title_coins` and `win_tickets / loss_tickets /
title_tickets`. Granted in `App._apply_league_heat` (coins to that league,
tickets globally), shown on the heat result screen, and the card drop lands
in that league's inventory. Quick heats are gone from the game (a test-only
path remains) and pay nothing.

## The envelope — `core/economy/economy_budget.gd` (`EconomyBudget`)

A **reference player** (`economy.json` → `tickets.reference`): 1.5-minute
trials scoring 24 on the cage and 18 on the beach, 2.5-minute heats, a
coin-flip win rate. From that:

- **rate per minute** for every ticket-paying mode (each trial location, each
  league's heats);
- the **grind rate** = the mean trial rate, which the tiers are measured
  against;
- **minutes to afford** = price ÷ grind rate, and the **tier** whose minutes
  band holds it (`entry`, `mid`, `premium`, `grail`);
- the **catalog hours**: every priced locker item, summed;
- **heats to afford** each card in each league = price ÷ expected coins per
  heat.

Rules the suite enforces (`EconomyBudget.problems()`, `tests/test_economy.gd`):

1. every ticket-paying mode's rate is inside `rate_band_per_min` — a new mode
   can be neither a firehose nor a dead end;
2. every priced item's minutes fall inside some tier band, and none passes
   the grail ceiling;
3. the whole catalog's hours sit inside `catalog_hours`;
4. each card rarity's heats-to-afford is inside its band, in every league;
5. every league row carries all six reward keys (`LeagueData.validate`);
6. (cards' own power / price curve: `CardBudget`, `docs/CARDS.md`).

The ledger prints all of it and exits non-zero on a break:

    godot --headless --path . -s tools/economy_ledger.gd

## Shipped numbers (2026-09-25)

| Mode | pays | rate |
|---|---|---|
| trial, cage | 6 + 0.45/pt (×1.0), +10 new best | ~11 tickets/min |
| trial, beach | same ×1.25 | ~12 tickets/min |
| heat, cage | 50 / 20 / 300 coins · 28 / 11 / 80 tickets | ~8 tickets/min + 35 coins/heat |
| heat, beach | 60 / 25 / 400 coins · 35 / 14 / 100 tickets | ~10 tickets/min + 42 coins/heat |

Rate band 6–14/min. Tiers in minutes of trials: entry 15–40, mid 40–70,
premium 70–115, grail 115–170. At the ~12/min grind rate the 21 balls and
the street hoop (250–1500 tickets) span entry to grail and the whole catalog
is ~22 hours — something new every few sessions, the top shelf a real chase.
Cards: a common (100 coins) every ~3 cage heats, a rare (150) every ~4.5,
plus the drops.

## Adding an item (a ball or a hoop)

1. Author its `.tres` with `price_coins` (the field name is historical; it
   is tickets).
2. Run the ledger: it must land in a tier and keep the catalog inside its
   hours. Too cheap or too dear → move the price, not the tiers.
3. The suite (`test_economy.gd` covers every registered set automatically;
   `test_cosmetics.gd` checks the set loads and that `classic` stays the only
   free ball).

## Adding a mode

1. Decide what it pays and where the grant lives (`App.finish_run` for a
   timed solo mode, `_apply_league_heat` for league games).
2. Put its numbers in data (`economy.json` for solo modes, the league row
   for league games) and its rate in `EconomyBudget.rates()`.
3. The ledger: the new rate must sit in the band. Practice-style endless
   modes pay nothing by construction.

## Adding a league

The six reward keys on its row. Coins should scale with difficulty (the
harder league pays more per heat) and its heats-to-afford per rarity must
stay in band; tickets per heat must keep the rate in band. Then the ledger,
then `docs/CARDS.md`'s parity check for its card allowance.

## Changing the scale

`economy.json` holds the bands, the tiers and the reference player. Move
them only when the design intent moves (say, real play data shows the
average trial scores 32, not 24) — then re-read the ledger, since every
item's tier and every mode's rate shift together.

## Not a currency: the level

XP (docs/PROGRESSION.md) is earned only by league matches and cannot be
bought; it gates which cards you can *play* and which areas open. Coins and
tickets buy things; the level decides what you can use. That split is what
keeps an in-app purchase from buying power.

## Save and migration

- `cosmetics.tickets` replaced `cosmetics.coins`; a legacy doc with `coins`
  loads as `tickets: 0` (the old balance is wiped).
- `cards` v3 (`CardDefs.DOC_VERSION`): `{leagues: {id: {coins, inventory,
  loadout}}}`; v1 / v2 docs (one global inventory) are wiped by
  `CardDefs.migrate`. Dev saves only, by decision.
- `progress` (the level: `{xp, seasonXp, seasonKey}`) needs no migration;
  new keys default on read.
- `docs/SYNC.md` lists the parts.
