# Economy — one currency and its rulebook

One currency, one wallet, one governed system (since 2026-10-19; before that
tickets and per-league coins — see History). This is the document to read
before adding an item, a mode or a league, or changing a price or a reward.
Cards' own balance (power, rarity, the AI's allowance) is `docs/CARDS.md`.

| | **Tickets** |
|---|---|
| Scope | global — one wallet |
| Earned by | time trials (never practice), league heats, a league title; ranked online matches later (the ranked task) |
| Spent on | **PEGGY plays** (the drop machine wins balls AND nets, docs/LOCKER.md; nothing in the locker is bought outright — hoops only when that counter reopens) and **each league's power-up cards** in its shop (league hub) |
| Lives in | save part `cosmetics` → `tickets` |
| Code | `App.tickets()`, `grant_tickets`, `spend_tickets`, `peggy_insert_ticket()` → `peggy_drop(aim)`, `try_buy("hoop", id)` (balls and nets refuse), `try_buy_card(card, league)` |

**Cards stay per league.** A card bought or dropped in the beach plays only
in the beach: the inventories (`cards` save part, one bucket per league) are
segmented, the wallet is not. Prices are flat per card across leagues. Level
gating is unchanged (`App.can_equip`, the server cap online). League card
buying exists to reduce friction — a frustrated player can buy more and use
them — not to balance the AI (docs/CARDS.md → The area envelope).

## The rule — real money and online cards

Permanent, by decision (Ross, 2026-10-19), also in docs/BACKEND.md:

- **There is no path from real money to online cards, ever.** Future ticket
  packs buy tickets. Tickets never buy online cards. Online cards come only
  from verified server drops and spoils (the next task).
- **Online cards are never tradeable, giftable or sold, and drops are never
  sold.**
- Hence the online shop and the online wallet are gone: `GET /v1/cards`
  returns `{inventory, level}`, there is no buy route, the lobby's deck
  sheet is LOADOUT only, and `App.try_buy_card` refuses the online bucket.

This keeps the "winner takes the played cards" mechanic clear of real-money
gambling under Apple 5.3 and Google Play's gambling policy: nothing of real
value is wagered, won or cashed out.

## Earning

Everything is data. The arithmetic is `core/economy/economy.gd` (`Economy`).

**Time trial** — `data/economy.json` → `tickets.trial`:
`round((base + per_point × score) × location_mult) + new_best`.
Practice never pays: endless modes have no clock to run out, so
`App.finish_run` is never reached. Tickets are granted there and shown on
the results screen (`+N TICKETS`).

**League heat** — `data/leagues.json` → each league's `rewards`:
`win_tickets / loss_tickets / title_tickets`. Granted in
`App._apply_league_heat`, shown on the heat result screen (`+36 · TICKETS ·
WIN · +18 XP`), and the card drop lands in that league's inventory. Quick
heats are gone from the game (a test-only path remains) and pay nothing.
Online matches pay nothing yet (`settled {won, reason}`; the ranked task
refills it).

## The envelope — `core/economy/economy_budget.gd` (`EconomyBudget`)

A **reference player** (`economy.json` → `tickets.reference`): 1.5-minute
trials scoring 24 on the cage, 18 on the beach, 17 in the park, 16 in the
city, 2.5-minute heats, a coin-flip win rate. From that:

- **rate per minute** for every mode (each trial location, each league's
  heats);
- the **grind rate** = the mean trial rate, which the tiers are measured
  against;
- **minutes to afford** = price ÷ grind rate, and the **tier** whose minutes
  band holds it (`entry`, `mid`, `premium`, `grail`);
- the **catalog hours**: every priced locker item (the hoops) plus PEGGY's
  expected tickets to win every ball and every net (`peggy_tickets()`);
- **heats to afford** each card in each league = price ÷ expected tickets
  per heat.

Rules the suite enforces (`EconomyBudget.problems()`, `tests/test_economy.gd`):

1. every mode's rate is inside `rate_band_per_min` — a new mode can be
   neither a firehose nor a dead end;
2. every priced item's minutes fall inside some tier band, and none passes
   the grail ceiling;
3. the whole catalog's hours sit inside `catalog_hours`;
3b. PEGGY: a drop is an *entry* purchase, the roster (balls and nets) is
   payable, a prize costs at most 1.35 drops, every ball is rated and priced
   0, every net is priced 0 with one stock net per kind (docs/LOCKER.md);
4. each card rarity's heats-to-afford **in tickets** is inside its band
   (`economy.json` → `cards.heats_to_afford`), in every league;
5. every league row carries the three ticket reward keys (`LeagueData.validate`);
6. (cards' own power / price curve: `CardBudget`, `docs/CARDS.md`).

The ledger prints all of it and exits non-zero on a break:

    godot --headless --path . -s tools/economy_ledger.gd

## Shipped numbers (2026-10-19)

| Mode | pays | rate |
|---|---|---|
| trial, cage | 5 + 0.40/pt (×1.0), +10 new best | 15 a trial, ~10 tickets/min |
| trial, beach | same ×1.25 | 15 a trial, ~10 tickets/min |
| trial, park | same ×1.4 (avg 17) | 17 a trial, ~11 tickets/min |
| trial, city | same ×1.5 (avg 16) | 17 a trial, ~11 tickets/min |
| heat, cage | 36 / 16 / title 150 tickets | 26 a heat, ~10.4 tickets/min |
| heat, beach | 40 / 18 / title 180 | 29 a heat, ~11.6 tickets/min |
| heat, park | 43 / 20 / title 200 | 31.5 a heat, ~12.6 tickets/min |
| heat, city | 47 / 21 / title 220 | 34 a heat, ~13.6 tickets/min |

Rate band 6–14/min. With one wallet the heats carry it and a trial pays a
bit less than a heat a minute (Ross's call; trials dropped ~15 % from 6 +
0.45/pt). Tiers in minutes of trials: entry 15–40, mid 40–70, premium
70–115, grail 115–170. At the ~10.7/min grind rate a PEGGY drop (300
tickets) is an entry purchase (~28 min), the 54 winnable prizes cost
~15,600 tickets (~24 h, no drop wasted), the hoops (300 / 400) sit at 28 /
37 min, and the whole catalog is ~25.5 hours — something new every few
sessions, the legends behind level 5. Nets were priced 400–1000 on a counter
until 2026-10-15; now they are prizes.

**Cards** (`data/cards.json`, `price = round10(150 · power^1.3)` ±20 %): ice
**80**, fire7 **140**, magnet6 **290** tickets. Heats to afford in the cage
3.1 / 5.4 / 11.2 (bands common 1.5–4.5, rare 3–8, epic 6–14), in the city
2.4 / 4.1 / 8.5 — about what the coin prices (100 / 170 / 390 at 35 coins a
cage heat) took. A season (18 heats + a fifth of a title) is ~500 tickets in
the cage, ~660 in the city: a drop and a half, or six commons, or a mix.

## Adding an item (a hoop)

1. Author its `.tres` with `price_coins` (the field name is historical; it
   is tickets — 63 `.tres` files and the hoop pipeline carry it, so it stays).
2. Run the ledger: it must land in a tier and keep the catalog inside its
   hours. Too cheap or too dear → move the price, not the tiers.
3. The suite (`test_economy.gd` covers every registered set automatically;
   `test_cosmetics.gd` checks the set loads).

A ball or a net is a PEGGY prize, not a priced item (price 0; a net's
`stock` flag marks the free pair): docs/LOCKER.md → Adding a ball. The
ledger's roster line and `peggy_tickets()` pick a new one up automatically.

## Adding a mode

1. Decide what it pays and where the grant lives (`App.finish_run` for a
   timed solo mode, `_apply_league_heat` for league games).
2. Put its numbers in data (`economy.json` for solo modes, the league row
   for league games) and its rate in `EconomyBudget.rates()`.
3. The ledger: the new rate must sit in the band. Practice-style endless
   modes pay nothing by construction.

## Adding a league

The three reward keys on its row. Tickets per heat should scale with
difficulty (the harder league pays more per heat) while the rate stays in
band, and its heats-to-afford per rarity must stay in band. Then the ledger,
then `docs/CARDS.md`'s envelope for its card allowance (reported, not gated).

## Changing the scale

`economy.json` holds the bands, the tiers, the card bands and the reference
player. Move them only when the design intent moves (say, real play data
shows the average trial scores 32, not 24) — then re-read the ledger, since
every item's tier and every mode's rate shift together.

## Not a currency: the level

XP (docs/PROGRESSION.md) is earned only by league matches and cannot be
bought; it gates which cards you can *play* and which areas open. Tickets
buy things; the level decides what you can use. That split is what keeps an
in-app purchase from buying power.

## Save and migration

- `cosmetics.tickets` is the wallet; a legacy doc with the pre-2026-09
  `coins` key loads as `tickets: 0` (the old balance is wiped).
- `cards` v4 (`CardDefs.DOC_VERSION`): `{leagues: {id: {inventory,
  loadout}}}`. A v3 doc (`{coins, inventory, loadout}` per league) migrates
  in place: the coin balances are **wiped, not converted** (dev saves only,
  by decision — no real players yet), inventory and loadout kept. v1 / v2
  docs (one global inventory) are wiped. `CardDefs.migrate` runs on load,
  on `put_cards`, on a mirror restore and on the online cache.
- `progress` (the level: `{xp, seasonXp, seasonKey}`) needs no migration;
  new keys default on read.
- `docs/BACKEND.md` lists the parts. The server's `online_wallet` table is
  dropped by migration 0006 (Ross applies it; `online_cards` and
  `online_ledger` stay).

## History

- 2026-09-25 → 2026-10-18: two currencies — tickets (global, PEGGY / locker)
  and coins (one wallet per league, that league's shop, 50 / 20 / 300 in the
  cage up to 66 / 27 / 440 in the city), plus a third online wallet paid by
  online matches (50 × an upset multiplier, 20 flat) and spent in an online
  shop. Removed 2026-10-19: one wallet is simpler to earn, to price and to
  sell packs for, and the online shop was a real-money path to online cards.
