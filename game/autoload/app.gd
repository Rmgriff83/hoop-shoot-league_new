extends Node
## Screen routing, run handoff, and the player's live cosmetic selection
## (hoop set + ball set), with coins / ownership persisted by SaveService.
## The M2 seam: when MatchEngine arrives, match screens register here beside
## the time trial with the same pattern.

const TITLE_SCENE := "res://game/screens/title_screen.tscn"
const TIME_TRIAL_SCENE := "res://game/screens/time_trial_screen.tscn"
const RESULTS_SCENE := "res://game/screens/results_screen.tscn"
const HEAT_SCENE := "res://game/screens/heat_screen.tscn"
const HEAT_RESULT_SCENE := "res://game/screens/heat_result_screen.tscn"
const CREDITS_SCENE := "res://game/screens/credits_screen.tscn"
## The intro loop (title + credits); an area's ambience replaces it.
const TITLE_MUSIC := {"id": "title", "clip": "res://assets/music/title_moog.ogg", "gain_db": -15.0}

## Level gating for leagues and areas (docs/PROGRESSION.md: a league's
## `unlock` level, reached by playing the league before it). On.
## Level gates on areas and leagues (docs/PROGRESSION.md). OFF in debug builds
## — the editor and the phone dev APK (tools/android_deploy.sh exports debug)
## can reach every area; a release build gates as designed.
var league_gating: bool = not OS.is_debug_build()
## The league whose dashboard / heat is active ("" outside leagues).
var current_league := ""
## The home screen's last card (page index), so leaving an area returns to it.
var home_card := 0
## A league the home page should open straight into (its id), set by
## to_league_hub() — the heat result's CONTINUE SEASON. Cleared once used.
var home_open_league := ""

## Stats of the run that just ended, for the results screen.
var last_run: Dictionary = {}
var last_run_was_best := false

## Tuning mode: shows the on-device touch tuning strip in the time trial.
## Persisted in SaveService's "tuning" part (device-local).
var tuning_mode := false

## Shot help, in three steps: nothing, just the numbers beside the held ball,
## or the numbers plus the dotted arc. Persisted in SaveService's "settings"
## part. Read directly by the views every frame — nothing in this project's
## settings path uses signals.
const SHOT_HELP_OFF := 0
const SHOT_HELP_NUMBERS := 1
const SHOT_HELP_FULL := 2
const SHOT_HELP_LABELS := ["OFF", "NUMBERS", "NUMBERS + ARC"]
var shot_help := SHOT_HELP_OFF
## The home screen's palette (RetroTheme): cream, or the dark twin. Persisted
## in the settings part as darkMode.
var dark_mode := false
## The live flick tunables, shared by every time trial in this session and
## seeded from the persisted overrides, so adjustments never reset between
## runs (the overlay also persists every adjustment as it happens).
var tuning: FlickTuning = FlickTuning.new()

## Active cosmetic sets. Screens read these when they build; Sfx holds the
## matching sound tables. Selection persists in SaveService's "cosmetics" part.
var hoop_set: HoopSet
var ball_set: BallSet

## Mode table for the time-trial scene. arena/hoop are cosmetic ids ("" hoop
## = the player's selected set); geo names the SimGeometry recipe; dist its
## hoop distance; endless = no clock/results; board_motion = the figure-8.
const ARCADE_HOOP_DIST := 2.9
## Ids are "<mode>" for the arcade cage (the originals) and "<mode>_beach";
## `location` keys the per-court leaderboards.
const MODES := {
	"trial": {"arena": "cage", "hoop": "", "geo": "arcade", "dist": ARCADE_HOOP_DIST,
		"endless": false, "board_motion": true, "hud_label": "", "led_text": "READY", "location": "cage"},
	"practice": {"arena": "cage", "hoop": "", "geo": "arcade", "dist": ARCADE_HOOP_DIST,
		"endless": true, "board_motion": false, "hud_label": "PRACTICE", "led_text": "PRACTICE", "location": "cage"},
	"beach": {"arena": "beach", "hoop": "street", "geo": "beach", "dist": SimGeometry.BEACH_DIST,
		"endless": true, "board_motion": false, "hud_label": "BEACH", "led_text": "", "location": "beach"},
	"trial_beach": {"arena": "beach", "hoop": "street", "geo": "beach", "dist": SimGeometry.BEACH_DIST,
		"endless": false, "board_motion": false, "hud_label": "", "led_text": "READY", "location": "beach",
		"spot_shuffle": true},
	# The city court (docs/HOME.md): the beach's spot game on a chain-net hoop.
	"city": {"arena": "city", "hoop": "chain", "geo": "city", "dist": SimGeometry.CITY_DIST,
		"endless": true, "board_motion": false, "hud_label": "CITY", "led_text": "", "location": "city"},
	"trial_city": {"arena": "city", "hoop": "chain", "geo": "city", "dist": SimGeometry.CITY_DIST,
		"endless": false, "board_motion": false, "hud_label": "", "led_text": "READY", "location": "city",
		"spot_shuffle": true},
	# Head-to-head heats (core/match/heat.gd): a static hoop, the ball-return
	# wait, an AI opponent in the picture-in-picture court.
	# The last 30 s trigger the location's mechanic for both sides: the cage's
	# sliding board, the beach's spot shuffle.
	"heat": {"arena": "cage", "hoop": "", "geo": "arcade", "dist": ARCADE_HOOP_DIST,
		"endless": false, "board_motion": true, "hud_label": "", "led_text": "READY", "location": "cage",
		"heat": true, "calib_key": "arcade"},
	"heat_beach": {"arena": "beach", "hoop": "street", "geo": "beach", "dist": SimGeometry.BEACH_DIST,
		"endless": false, "board_motion": false, "hud_label": "", "led_text": "READY", "location": "beach",
		"heat": true, "calib_key": "beach", "spot_shuffle": true},
	"heat_city": {"arena": "city", "hoop": "chain", "geo": "city", "dist": SimGeometry.CITY_DIST,
		"endless": false, "board_motion": false, "hud_label": "", "led_text": "READY", "location": "city",
		"heat": true, "calib_key": "city", "spot_shuffle": true},
}
## mode ("trial"/"practice"/"heat") × area ("cage"/"beach"/"city") → MODES id.
const AREA_MODES := {
	"trial": {"cage": "trial", "beach": "trial_beach", "city": "trial_city"},
	"practice": {"cage": "practice", "beach": "beach", "city": "city"},
}
var next_mode := "trial"

## The heat about to be played: {seconds, ot_seconds, ball_return_s, ai (ratings
## dict), err_mult, seed, opponent {id, name, number, nickname, colors},
## league (null for a quick heat)}. Filled by start_heat / the quick-heat default.
var next_heat: Dictionary = {}
## The heat that just ended (Heat.result() + opponent/location), for the result screen.
var last_heat: Dictionary = {}

## Quick-heat stand-in opponent until the roster (M2c) arrives.
const QUICK_OPPONENT := {"id": "ricky", "name": "Ricky Buckets", "number": 7, "nickname": "The Rook",
	"colors": {"primary": "#e0562b", "secondary": "#1b1b24", "accent": "#f6c453"},
	"ratings": {"accuracy": 0.5, "swishRate": 0.45, "pace": 3.6, "composure": 0.5, "streakiness": 0.5, "consistency": 0.7}}


static func mode_config(id: String) -> Dictionary:
	return MODES.get(id, MODES["trial"])


static func geo_for_mode(id: String) -> SimGeometry:
	var cfg := mode_config(id)
	if cfg["geo"] == "beach":
		return SimGeometry.beach(cfg["dist"])
	if cfg["geo"] == "city":
		return SimGeometry.city(cfg["dist"])
	return SimGeometry.arcade(cfg["dist"])


## The hoop a mode plays with: a mode-mandated set (ownership is irrelevant —
## it is the mode's fixture, not a purchase) or the player's selection.
func hoop_for_mode(id: String) -> HoopSet:
	var cfg := mode_config(id)
	if cfg["hoop"] != "":
		var s := CosmeticLibrary.get_hoop(cfg["hoop"])
		if s != null:
			return s
	return hoop_set


func _ready() -> void:
	var saved := SaveService.get_tuning()
	tuning_mode = bool(saved.get("tuningMode", false))
	shot_help = shot_help_from_saved(SaveService.get_settings().get("shotHelp", SHOT_HELP_OFF))
	dark_mode = bool(SaveService.get_settings().get("darkMode", false))
	tuning.apply_dict(saved.get("fields", {}))
	_resolve_cosmetics()


func _resolve_cosmetics() -> void:
	var c := SaveService.get_cosmetics()
	hoop_set = CosmeticLibrary.get_hoop(c["hoop"].get("selected", ""))
	if hoop_set == null:
		hoop_set = CosmeticLibrary.starter_hoop()
	ball_set = CosmeticLibrary.get_ball(c["ball"].get("selected", ""))
	if ball_set == null:
		ball_set = CosmeticLibrary.starter_ball()
	Sfx.load_hoop_set(hoop_set)
	Sfx.load_ball_set(ball_set)


func set_tuning_mode(on: bool) -> void:
	tuning_mode = on
	SaveService.put_tuning(on, SaveService.get_tuning().get("fields", {}))


## Coerce a saved value into a mode. The setting was a BOOL before it grew a
## middle step, so an older save reads true as the full treatment rather than
## silently resetting to off.
static func shot_help_from_saved(raw: Variant) -> int:
	if raw is bool:
		return SHOT_HELP_FULL if raw else SHOT_HELP_OFF
	if raw is int or raw is float:
		return clampi(int(raw), SHOT_HELP_OFF, SHOT_HELP_FULL)
	return SHOT_HELP_OFF


func set_dark_mode(on: bool) -> void:
	dark_mode = on
	var s := SaveService.get_settings()
	s["darkMode"] = on
	SaveService.put_settings(s)


func set_shot_help(mode: int) -> void:
	shot_help = clampi(mode, SHOT_HELP_OFF, SHOT_HELP_FULL)
	var s := SaveService.get_settings()
	s["shotHelp"] = shot_help
	SaveService.put_settings(s)


## Step to the next setting, wrapping: off → numbers → numbers + arc → off.
func cycle_shot_help() -> void:
	set_shot_help((shot_help + 1) % SHOT_HELP_LABELS.size())


# ---- the player's level (docs/PROGRESSION.md) ----------------------------------
# XP comes only from league matches (_apply_league_heat); the level gates
# cards (Progression.can_use) and areas (area_unlocked).


func progress() -> Dictionary:
	return SaveService.get_progress()


func xp() -> int:
	return int(progress().get("xp", 0))


func level() -> int:
	return Progression.level_for(xp())


func area_unlocked(area: String) -> bool:
	return not league_gating or Progression.area_unlocked(level(), area)


# ---- tickets (global, the locker money) + cosmetics ----------------------------
# docs/ECONOMY.md: tickets are earned by time trials and league heats and
# spent on balls / hoops in the locker; coins (below) are per league.


func tickets() -> int:
	return int(SaveService.get_cosmetics().get("tickets", 0))


func grant_tickets(n: int) -> void:
	if n <= 0:
		return
	var c := SaveService.get_cosmetics()
	c["tickets"] = int(c.get("tickets", 0)) + n
	SaveService.put_cosmetics(c)


func owns(kind: String, id: String) -> bool:
	var c := SaveService.get_cosmetics()
	return c.has(kind) and Array(c[kind].get("owned", [])).has(id)


## Select an owned set of `kind` ("hoop" | "ball"). Takes effect on the next
## screen build (sounds swap immediately). False if unknown or not owned.
func select(kind: String, id: String) -> bool:
	if not owns(kind, id):
		return false
	var c := SaveService.get_cosmetics()
	c[kind]["selected"] = id
	SaveService.put_cosmetics(c)
	_resolve_cosmetics()
	return true


func select_hoop(id: String) -> bool:
	return select("hoop", id)


func select_ball(id: String) -> bool:
	return select("ball", id)


## Spend tickets on a set. False if unknown, already owned, or unaffordable.
func try_buy(kind: String, id: String) -> bool:
	if kind == "ball":
		return false   # balls are PEGGY prizes (docs/LOCKER.md), never bought
	var set: CosmeticSet = CosmeticLibrary.get_hoop(id) if kind == "hoop" else CosmeticLibrary.get_ball(id)
	if set == null or owns(kind, id):
		return false
	var c := SaveService.get_cosmetics()
	if int(c.get("tickets", 0)) < set.price_coins:
		return false
	c["tickets"] = int(c.get("tickets", 0)) - set.price_coins
	c[kind]["owned"].push_back(id)
	SaveService.put_cosmetics(c)
	return true


# ---- PEGGY (docs/LOCKER.md) --------------------------------------------------------
## The locker's drop machine. Tickets buy drops; a drop wins a ball the player
## does not own yet. The plates shown come from the drop index, so what is on
## the board is what can be won; the index only moves on a completed drop.

var last_prize: Dictionary = {}


func drop_count() -> int:
	return int(Dictionary(SaveService.get_cosmetics().get("peggy", {})).get("drops", 0))


func spend_tickets(n: int) -> bool:
	if n <= 0:
		return false
	var c := SaveService.get_cosmetics()
	if int(c.get("tickets", 0)) < n:
		return false
	c["tickets"] = int(c.get("tickets", 0)) - n
	SaveService.put_cosmetics(c)
	return true


func owned_ids(kind: String) -> Array:
	var c := SaveService.get_cosmetics()
	var out: Array = Array(Dictionary(c.get(kind, {})).get("owned", [])).duplicate()
	var starter: CosmeticSet = CosmeticLibrary.starter_ball() if kind == "ball" else CosmeticLibrary.starter_hoop()
	if starter != null and not out.has(starter.id):
		out.push_back(starter.id)
	return out


func owned_count(kind: String) -> int:
	return owned_ids(kind).size()


## Hand the player a set without charging (a PEGGY prize). A new ball is
## flagged unseen until the BALLS tab is opened.
func grant_cosmetic(kind: String, id: String) -> bool:
	var set: CosmeticSet = CosmeticLibrary.get_hoop(id) if kind == "hoop" else CosmeticLibrary.get_ball(id)
	if set == null or owns(kind, id):
		return false
	var c := SaveService.get_cosmetics()
	if not c.has(kind):
		c[kind] = {"selected": id, "owned": []}
	c[kind]["owned"].push_back(id)
	SaveService.put_cosmetics(c)
	if kind == "ball":
		var st := SaveService.get_settings()
		var fresh: Array = Array(st.get("newBalls", [])).duplicate()
		if not fresh.has(id):
			fresh.push_back(id)
		st["newBalls"] = fresh
		SaveService.put_settings(st)
	return true


## Balls won but not yet looked at on the BALLS tab (the locker icon's dot).
func unseen_balls() -> Array:
	var out := []
	for id in Array(SaveService.get_settings().get("newBalls", [])):
		if owns("ball", str(id)) and not out.has(id):
			out.push_back(id)
	return out


func mark_balls_seen() -> void:
	var st := SaveService.get_settings()
	if Array(st.get("newBalls", [])).is_empty():
		return
	st["newBalls"] = []
	SaveService.put_settings(st)


func peggy_seed(drop_index: int) -> int:
	return DetRng.hash_seed("%s:peggy:%d" % [SaveService.get_client_id(), drop_index])


func peggy_roster() -> Array:
	return EconomyBudget.peggy_roster()


## The seven plates for the NEXT drop: [{base, rarity, ball_id}].
func peggy_slots() -> Array:
	var rng := DetRng.new(peggy_seed(drop_count())).fork("slots")
	return PeggyPrizes.slots(level(), owned_ids("ball"), peggy_roster(), rng)


## One drop at this aim. {} when the tickets are short; else the prize record
## {slot, base, rarity, ball_id, refund, drop_index, aim, result, owned_after}.
func peggy_drop(aim_x: float) -> Dictionary:
	var plates := peggy_slots()
	if not spend_tickets(PeggyPrizes.DROP_COST):
		return {}
	var index := drop_count()
	var result := PeggyBoard.simulate(aim_x, DetRng.new(peggy_seed(index)).fork("drop").state)
	var plate: Dictionary = plates[int(result["slot"])]
	var refund := PeggyPrizes.refund(plate)
	var id := str(plate.get("ball_id", ""))
	if id != "":
		grant_cosmetic("ball", id)
	elif refund > 0:
		grant_tickets(refund)
	var c := SaveService.get_cosmetics()
	var pg: Dictionary = c.get("peggy", {})
	pg["drops"] = index + 1
	c["peggy"] = pg
	SaveService.put_cosmetics(c)
	last_prize = {"slot": int(result["slot"]), "base": plate.get("base", ""), "rarity": plate.get("rarity", ""),
		"ball_id": id, "refund": refund, "drop_index": index, "aim": aim_x, "result": result,
		"owned_after": owned_count("ball"), "plates": plates}
	return last_prize


# ---- routing -------------------------------------------------------------------


func to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(TITLE_SCENE)


func start_mode(id: String) -> void:
	next_mode = id if MODES.has(id) else "trial"
	if mode_config(next_mode).get("heat", false):
		if next_heat.is_empty() or next_heat.get("mode", "") != next_mode:
			next_heat = quick_heat_config(next_mode)
		get_tree().change_scene_to_file(HEAT_SCENE)
		return
	get_tree().change_scene_to_file(TIME_TRIAL_SCENE)


## TEST-ONLY. Quick heats left the game (2026-09-25): heats are league games.
## This one-off against the stand-in opponent stays for the QA driver and
## tests (start_mode("heat") without a league). No cards outside leagues, no
## rewards.
func quick_heat_config(mode_id: String) -> Dictionary:
	var cfg := mode_config(mode_id)
	return {
		"mode": mode_id, "seconds": Heat.DEFAULT_SECONDS, "ot_seconds": Heat.DEFAULT_OT_SECONDS,
		"ball_return_s": Heat.DEFAULT_BALL_RETURN_S, "ai": QUICK_OPPONENT["ratings"], "err_mult": 1.0,
		"seed": int(Time.get_ticks_usec() % 2147483647), "opponent": QUICK_OPPONENT,
		"calib_key": cfg.get("calib_key", "regulation"), "league": null,
		"player_cards": [], "player_slots": [null, null, null], "ai_cards": [],
	}


## Play a configured heat (a league game or a rematch).
func start_heat(mode_id: String, cfg: Dictionary) -> void:
	next_heat = cfg.duplicate(true)
	next_heat["mode"] = mode_id
	next_mode = mode_id
	get_tree().change_scene_to_file(HEAT_SCENE)


## Settle a finished heat: the league apply, payouts, XP and the card roll
## into `last_heat` (with the before/after snapshot the match-end page plays,
## `league_end`). The heat screen shows MatchEndOverlay from this, then
## to_heat_result(); finish_heat does both for the quick-heat path.
func settle_heat(result: Dictionary) -> Dictionary:
	last_heat = result.duplicate(true)
	last_heat["opponent"] = next_heat.get("opponent", QUICK_OPPONENT)
	last_heat["mode"] = next_mode
	last_heat["location"] = mode_config(next_mode).get("location", "cage")
	last_heat["league"] = next_heat.get("league", null)
	if last_heat["league"] != null:
		_apply_league_heat(last_heat)
	return last_heat


func to_heat_result() -> void:
	get_tree().change_scene_to_file(HEAT_RESULT_SCENE)


func finish_heat(result: Dictionary) -> void:
	settle_heat(result)
	to_heat_result()


# ---- power-up cards + coins: one bucket per league --------------------------------
# docs/ECONOMY.md. Every call takes the league (default: the one being played,
# App.current_league). Coins earned in a league are spent there; the cards
# bought or dropped there stay there.


func _league_for(league := "") -> String:
	if league != "":
		return league
	return current_league if current_league != "" else "cage"


## The whole cards doc (every league's bucket).
func cards_doc() -> Dictionary:
	return SaveService.get_cards()


## A copy of one league's bucket {coins, inventory, loadout}.
func cards_bucket(league := "") -> Dictionary:
	return CardDefs.league_doc(cards_doc(), _league_for(league)).duplicate(true)


func league_coins(league := "") -> int:
	return CardDefs.coins(cards_doc(), _league_for(league))


func grant_league_coins(n: int, league := "") -> void:
	if n <= 0:
		return
	var d := cards_doc()
	var b := CardDefs.league_doc(d, _league_for(league))
	b["coins"] = int(b.get("coins", 0)) + n
	SaveService.put_cards(d)


func card_count(id: String, league := "") -> int:
	return CardDefs.count(cards_bucket(league), id)


func add_card(id: String, n := 1, league := "") -> void:
	var d := cards_doc()
	CardDefs.add(CardDefs.league_doc(d, _league_for(league)), id, n)
	SaveService.put_cards(d)


func equip_card(slot: int, id: String, league := "") -> bool:
	var d := cards_doc()
	if not CardDefs.equip(CardDefs.league_doc(d, _league_for(league)), slot, id):
		return false
	SaveService.put_cards(d)
	return true


func unequip_card(slot: int, league := "") -> void:
	var d := cards_doc()
	CardDefs.unequip(CardDefs.league_doc(d, _league_for(league)), slot)
	SaveService.put_cards(d)


## A deployed card leaves the inventory at once (abandoning a heat is no refund).
func consume_card(id: String, league := "") -> bool:
	var d := cards_doc()
	if not CardDefs.consume(CardDefs.league_doc(d, _league_for(league)), id):
		return false
	SaveService.put_cards(d)
	return true


## The same for a known loadout slot (the tray plays by slot).
func consume_slot(slot: int, id: String, league := "") -> bool:
	var d := cards_doc()
	if not CardDefs.consume_slot(CardDefs.league_doc(d, _league_for(league)), slot, id):
		return false
	SaveService.put_cards(d)
	return true


## Buy a card with the league's coins. False if unknown or unaffordable.
func try_buy_card(id: String, league := "") -> bool:
	var card := CardDefs.get_card(id)
	if card.is_empty():
		return false
	var d := cards_doc()
	var b := CardDefs.league_doc(d, _league_for(league))
	var price := int(card.get("price", 0))
	if int(b.get("coins", 0)) < price:
		return false
	b["coins"] = int(b.get("coins", 0)) - price
	CardDefs.add(b, id)
	SaveService.put_cards(d)
	return true


## The equipped hand for the next heat (the ids in the three slots).
func loadout_hand(league := "") -> Array:
	return CardDefs.loadout_ids(cards_bucket(league))


## The three slots as saved (null = empty) — the heat screen's tray order.
func loadout_slots(league := "") -> Array:
	return CardDefs.loadout_slots(cards_bucket(league))


# ---- leagues ------------------------------------------------------------------


func league_cfg(id := "") -> Dictionary:
	return LeagueData.league(id if id != "" else current_league)


## Every league with its open/locked state for the title's area page.
func league_states() -> Array:
	var campaigns: Dictionary = SaveService.get_campaign().get("leagues", {})
	var lvl := level()
	var out := []
	for l in LeagueData.leagues():
		var ok := Progression.league_unlocked(lvl, l)
		out.push_back({"league": l, "unlocked": ok or not league_gating, "rule_met": ok,
			"doc": campaigns.get(l["id"], {})})
	return out


func league_doc(id := "") -> Dictionary:
	return SaveService.league_doc(id if id != "" else current_league)


func save_league_doc(doc: Dictionary, id := "") -> void:
	SaveService.put_league_doc(id if id != "" else current_league, doc)


## Make a league current (creating its campaign on first visit) — no scene
## change: the home page opens the league in place (LeagueContext).
func enter_league(id: String) -> bool:
	var cfg := LeagueData.league(id)
	if cfg.is_empty() or not (Progression.league_unlocked(level(), cfg) or not league_gating):
		return false
	current_league = id
	if league_doc(id).is_empty():
		var seed_v := int(Time.get_ticks_usec() % 2147483647)
		save_league_doc(Campaign.new_doc(cfg, seed_v, Time.get_unix_time_from_system() * 1000.0), id)
	return true


## Enter a league and go to the home page with it open.
func start_league(id: String) -> void:
	if enter_league(id):
		to_league_hub()


func to_credits() -> void:
	get_tree().change_scene_to_file(CREDITS_SCENE)


## The "dashboard" is the home page with the current league open in context.
func to_league_hub() -> void:
	home_open_league = current_league
	to_title()


## The heat config for the player's next league game: the opponent's card and
## ratings, the league's format, a seed that replays (season seed + game).
func league_heat_config(doc: Dictionary, cfg: Dictionary) -> Dictionary:
	var opp_id := Campaign.next_opponent(doc)
	if opp_id == "":
		return {}
	var shooter := LeagueData.shooter(opp_id)
	var season: Dictionary = doc["season"]
	Season.ensure_card_hands(season, cfg)
	var tag: String = "d%d" % int(season["currentDay"]) if season["phase"] == Season.PHASE_REGULAR \
		else "po-%s" % str(Season.player_series(season, Campaign.PLAYER).get("id", ""))
	return {
		"seconds": float(cfg.get("heat_seconds", Heat.DEFAULT_SECONDS)),
		"ot_seconds": float(cfg.get("ot_seconds", Heat.DEFAULT_OT_SECONDS)),
		"ball_return_s": float(cfg.get("ball_return_s", Heat.DEFAULT_BALL_RETURN_S)),
		"ai": shooter.get("ratings", {}), "err_mult": float(cfg.get("err_mult", 1.0)),
		"seed": QuickSim.seed_from([season["seed"], season["year"], tag, int(doc["career"]["totals"]["games"])]),
		"opponent": shooter, "calib_key": cfg.get("calib_key", "regulation"),
		"league": {"id": cfg["id"], "game": tag, "playoff": season["phase"] == Season.PHASE_PLAYOFFS},
		"player_cards": loadout_hand(cfg["id"]), "player_slots": loadout_slots(cfg["id"]),
		# The opponent's season hand (its fixed allowance, less what it has
		# already played on you), not a fresh authored list every meeting.
		"ai_cards": Season.card_hand(season, opp_id),
	}


## PLAY HEAT from the dashboard.
func start_league_heat() -> void:
	var cfg := league_cfg()
	var doc := league_doc()
	var heat_cfg := league_heat_config(doc, cfg)
	if heat_cfg.is_empty():
		return
	start_heat(str(cfg.get("mode", "heat")), heat_cfg)


func _apply_league_heat(result: Dictionary) -> void:
	var cfg := league_cfg()
	var doc := league_doc()
	if doc.is_empty() or cfg.is_empty():
		return
	var league_end := _league_end_before(doc, cfg, result)
	Campaign.apply_live_result(doc, cfg, result, int(Time.get_unix_time_from_system() * 1000.0))
	save_league_doc(doc)
	_league_end_after(league_end, doc, cfg)
	last_heat["league_end"] = league_end
	var you: Dictionary = result.get("sides", {}).get("player", {})
	SaveService.put_live_game({
		"leagueId": cfg["id"], "opponentId": result.get("opponent", {}).get("id", ""),
		"playerScore": int(result.get("player_score", 0)), "oppScore": int(result.get("ai_score", 0)),
		"won": bool(result.get("won", false)), "ot": int(result.get("ot", 0)),
		"swishes": int(you.get("swishes", 0)), "bestStreak": int(you.get("bestStreak", 0)),
	})
	# Payout (docs/ECONOMY.md): this league's coins, global tickets.
	var title: bool = doc["season"].get("championId", "") == Campaign.PLAYER and doc["season"]["phase"] == Season.PHASE_DONE
	var pay := Economy.heat_rewards(cfg, bool(result.get("won", false)), title)
	grant_league_coins(int(pay["coins"]), cfg["id"])
	grant_tickets(int(pay["tickets"]))
	last_heat["coins"] = int(pay["coins"])
	last_heat["tickets"] = int(pay["tickets"])
	# The level (docs/PROGRESSION.md): the match's XP into the league's band;
	# the title straight to its cap.
	var prog := progress()
	var xp_info := Progression.apply_match(prog, result, cfg, int(doc.get("year", 1)))
	if title:
		var jump := Progression.apply_title(prog, cfg)
		xp_info["gained"] = int(xp_info["gained"]) + int(jump["gained"])
		xp_info["level_after"] = int(jump["level_after"])
		xp_info["title"] = true
	SaveService.put_progress(prog)
	last_heat["xp"] = xp_info
	# Card drop, seeded by the campaign so a replayed season rolls the same;
	# it lands in this league's inventory.
	var league: Dictionary = result.get("league", {})
	var drop := CardRewards.roll(bool(result.get("won", false)), bool(league.get("playoff", false)),
		QuickSim.seed_from([doc["season"]["seed"], "drop", int(doc["career"]["totals"]["games"])]))
	if drop != "":
		add_card(drop, 1, cfg["id"])
	last_heat["card_drop"] = drop


## What the match-end page (game/ui/match_end_overlay.gd) needs from the
## campaign, captured BEFORE the result is folded in: your record, your
## place, your titles, and in the playoffs your series and the other semi.
func _league_end_before(doc: Dictionary, cfg: Dictionary, result: Dictionary) -> Dictionary:
	var season: Dictionary = doc.get("season", {})
	var league: Dictionary = result.get("league", {}) if result.get("league", null) is Dictionary else {}
	var out := {
		"year": LeagueSummary.year_of(doc), "league_name": str(cfg.get("name", "LEAGUE")).to_upper(),
		"record_before": LeagueSummary.record(season), "place_before": LeagueSummary.place(cfg, season),
		"titles_before": int(Dictionary(doc.get("career", {})).get("championships", 0)),
		"playoff": bool(league.get("playoff", false)), "round": "", "series_id": "", "best_of": 0,
		"series_before": [0, 0], "series_after": [0, 0], "decided": false, "series_won": false,
		"other_semi": [], "final_opp": "", "teams": LeagueData.team_ids(cfg).size(),
	}
	if out["playoff"]:
		var mine := Season.player_series(season, Campaign.PLAYER)
		if not mine.is_empty():
			out["round"] = str(mine.get("round", ""))
			out["series_id"] = str(mine.get("id", ""))
			out["best_of"] = int(mine.get("bestOf", 0))
			out["series_before"] = LeagueSummary.series_record(mine)
			var other := LeagueSummary.other_semi(season, mine)
			if not other.is_empty():
				out["other_semi"] = [str(other["highSeedId"]), str(other["lowSeedId"])]
	return out


## …and AFTER: the new record and place, the titles, how the series stands.
func _league_end_after(out: Dictionary, doc: Dictionary, cfg: Dictionary) -> void:
	var season: Dictionary = doc.get("season", {})
	out["record_after"] = LeagueSummary.record(season)
	out["place_after"] = LeagueSummary.place(cfg, season)
	out["titles_after"] = int(Dictionary(doc.get("career", {})).get("championships", 0))
	out["phase"] = str(season.get("phase", ""))
	if not bool(out["playoff"]):
		return
	for s in season.get("series", []):
		if str(s.get("id", "")) == str(out["series_id"]):
			out["series_after"] = LeagueSummary.series_record(s)
			out["decided"] = str(s.get("winnerId", "")) != ""
			out["series_won"] = str(s.get("winnerId", "")) == Campaign.PLAYER
		elif str(s.get("round", "")) == "final" and out["round"] != "final":
			if s["highSeedId"] == Campaign.PLAYER or s["lowSeedId"] == Campaign.PLAYER:
				out["final_opp"] = LeagueSummary.opponent_in(s)


## The title's two-step pick: mode, then area. A locked area is refused.
func start_area(mode: String, area: String) -> void:
	if not area_unlocked(area):
		return
	var table: Dictionary = AREA_MODES.get(mode, AREA_MODES["trial"])
	start_mode(table.get(area, table["cage"]))


func start_time_trial() -> void:
	start_mode("trial")


## Endless practice on the arcade court: shoot forever, tune live, exit any time.
func start_practice() -> void:
	start_mode("practice")


## Endless practice on the beach: street hoop, farther, facing the ocean.
func start_beach() -> void:
	start_mode("beach")


func finish_run(run: Dictionary) -> void:
	last_run_was_best = SaveService.is_best(run["score"], run.get("location", "cage"))
	last_run = SaveService.put_score(run)
	# Tickets for the run (docs/ECONOMY.md). Practice never gets here: endless
	# modes have no clock to run out.
	var earned := Economy.trial_tickets(run, last_run_was_best)
	grant_tickets(earned)
	last_run["tickets"] = earned
	get_tree().change_scene_to_file(RESULTS_SCENE)
