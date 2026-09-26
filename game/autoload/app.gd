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
const LEAGUE_HUB_SCENE := "res://game/screens/league_hub_screen.tscn"
const CREDITS_SCENE := "res://game/screens/credits_screen.tscn"
## The intro loop (title + credits); an area's ambience replaces it.
const TITLE_MUSIC := {"id": "title", "clip": "res://assets/music/title_moog.ogg", "gain_db": -15.0}

## Location gating for leagues (data/leagues.json `unlock` rules). Off for now:
## every league is open; the rules are evaluated and shown, never enforced.
const LEAGUE_GATING := false
## The league whose dashboard / heat is active ("" outside leagues).
var current_league := ""
## The home screen's last card (page index), so leaving an area returns to it.
var home_card := 0

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
}
## mode ("trial"/"practice"/"heat") × area ("cage"/"beach") → MODES id.
const AREA_MODES := {
	"trial": {"cage": "trial", "beach": "trial_beach"},
	"practice": {"cage": "practice", "beach": "beach"},
	"heat": {"cage": "heat", "beach": "heat_beach"},
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


# ---- cosmetics: selection, coins, purchase (API only; the shop UI comes later) ----


func coins() -> int:
	return int(SaveService.get_cosmetics().get("coins", 0))


func grant_coins(n: int) -> void:
	var c := SaveService.get_cosmetics()
	c["coins"] = int(c.get("coins", 0)) + n
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


## Spend coins on a set. False if unknown, already owned, or unaffordable.
func try_buy(kind: String, id: String) -> bool:
	var set: CosmeticSet = CosmeticLibrary.get_hoop(id) if kind == "hoop" else CosmeticLibrary.get_ball(id)
	if set == null or owns(kind, id):
		return false
	var c := SaveService.get_cosmetics()
	if int(c.get("coins", 0)) < set.price_coins:
		return false
	c["coins"] = int(c.get("coins", 0)) - set.price_coins
	c[kind]["owned"].push_back(id)
	SaveService.put_cosmetics(c)
	return true


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


## A one-off heat against the stand-in opponent at this mode's court. The seed
## comes from the clock (quick heats are not replays); leagues pass their own.
func quick_heat_config(mode_id: String) -> Dictionary:
	var cfg := mode_config(mode_id)
	return {
		"mode": mode_id, "seconds": Heat.DEFAULT_SECONDS, "ot_seconds": Heat.DEFAULT_OT_SECONDS,
		"ball_return_s": Heat.DEFAULT_BALL_RETURN_S, "ai": QUICK_OPPONENT["ratings"], "err_mult": 1.0,
		"seed": int(Time.get_ticks_usec() % 2147483647), "opponent": QUICK_OPPONENT,
		"calib_key": cfg.get("calib_key", "regulation"), "league": null,
		"player_cards": loadout_hand(), "player_slots": loadout_slots(), "ai_cards": [],
	}


## Play a configured heat (a league game or a rematch).
func start_heat(mode_id: String, cfg: Dictionary) -> void:
	next_heat = cfg.duplicate(true)
	next_heat["mode"] = mode_id
	next_mode = mode_id
	get_tree().change_scene_to_file(HEAT_SCENE)


func finish_heat(result: Dictionary) -> void:
	last_heat = result.duplicate(true)
	last_heat["opponent"] = next_heat.get("opponent", QUICK_OPPONENT)
	last_heat["mode"] = next_mode
	last_heat["location"] = mode_config(next_mode).get("location", "cage")
	last_heat["league"] = next_heat.get("league", null)
	if last_heat["league"] != null:
		_apply_league_heat(last_heat)
	get_tree().change_scene_to_file(HEAT_RESULT_SCENE)


# ---- power-up cards ----------------------------------------------------------


func cards_doc() -> Dictionary:
	return SaveService.get_cards()


func card_count(id: String) -> int:
	return CardDefs.count(cards_doc(), id)


func add_card(id: String, n := 1) -> void:
	var d := cards_doc()
	CardDefs.add(d, id, n)
	SaveService.put_cards(d)


func equip_card(slot: int, id: String) -> bool:
	var d := cards_doc()
	if not CardDefs.equip(d, slot, id):
		return false
	SaveService.put_cards(d)
	return true


func unequip_card(slot: int) -> void:
	var d := cards_doc()
	CardDefs.unequip(d, slot)
	SaveService.put_cards(d)


## A deployed card leaves the inventory at once (abandoning a heat is no refund).
func consume_card(id: String) -> bool:
	var d := cards_doc()
	if not CardDefs.consume(d, id):
		return false
	SaveService.put_cards(d)
	return true


## The same for a known loadout slot (the tray plays by slot).
func consume_slot(slot: int, id: String) -> bool:
	var d := cards_doc()
	if not CardDefs.consume_slot(d, slot, id):
		return false
	SaveService.put_cards(d)
	return true


## Buy a card with coins. False if unknown or unaffordable.
func try_buy_card(id: String) -> bool:
	var card := CardDefs.get_card(id)
	if card.is_empty():
		return false
	var c := SaveService.get_cosmetics()
	var price := int(card.get("price", 0))
	if int(c.get("coins", 0)) < price:
		return false
	c["coins"] = int(c.get("coins", 0)) - price
	SaveService.put_cosmetics(c)
	add_card(id)
	return true


## The equipped hand for the next heat (the ids in the three slots).
func loadout_hand() -> Array:
	return CardDefs.loadout_ids(cards_doc())


## The three slots as saved (null = empty) — the heat screen's tray order.
func loadout_slots() -> Array:
	return CardDefs.loadout_slots(cards_doc())


# ---- leagues ------------------------------------------------------------------


func league_cfg(id := "") -> Dictionary:
	return LeagueData.league(id if id != "" else current_league)


## Every league with its open/locked state for the title's area page.
func league_states() -> Array:
	var campaigns: Dictionary = SaveService.get_campaign().get("leagues", {})
	var out := []
	for l in LeagueData.leagues():
		var ok := Campaign.unlock_ok(l, campaigns)
		out.push_back({"league": l, "unlocked": ok or not LEAGUE_GATING, "rule_met": ok,
			"doc": campaigns.get(l["id"], {})})
	return out


func league_doc(id := "") -> Dictionary:
	return SaveService.league_doc(id if id != "" else current_league)


func save_league_doc(doc: Dictionary, id := "") -> void:
	SaveService.put_league_doc(id if id != "" else current_league, doc)


## Enter a league: create its campaign on first visit, then open the dashboard.
func start_league(id: String) -> void:
	var cfg := LeagueData.league(id)
	if cfg.is_empty():
		return
	current_league = id
	if league_doc(id).is_empty():
		var seed_v := int(Time.get_ticks_usec() % 2147483647)
		save_league_doc(Campaign.new_doc(cfg, seed_v, Time.get_unix_time_from_system() * 1000.0), id)
	to_league_hub()


func to_credits() -> void:
	get_tree().change_scene_to_file(CREDITS_SCENE)


func to_league_hub() -> void:
	get_tree().change_scene_to_file(LEAGUE_HUB_SCENE)


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
		"player_cards": loadout_hand(), "player_slots": loadout_slots(),
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
	Campaign.apply_live_result(doc, cfg, result, int(Time.get_unix_time_from_system() * 1000.0))
	save_league_doc(doc)
	var you: Dictionary = result.get("sides", {}).get("player", {})
	SaveService.put_live_game({
		"leagueId": cfg["id"], "opponentId": result.get("opponent", {}).get("id", ""),
		"playerScore": int(result.get("player_score", 0)), "oppScore": int(result.get("ai_score", 0)),
		"won": bool(result.get("won", false)), "ot": int(result.get("ot", 0)),
		"swishes": int(you.get("swishes", 0)), "bestStreak": int(you.get("bestStreak", 0)),
	})
	var rewards: Dictionary = cfg.get("rewards", {})
	var coins := int(rewards.get("win_coins", 50)) if result.get("won", false) else int(rewards.get("loss_coins", 20))
	if doc["season"].get("championId", "") == Campaign.PLAYER and doc["season"]["phase"] == Season.PHASE_DONE:
		coins += int(rewards.get("title_coins", 300))
	grant_coins(coins)
	last_heat["coins"] = coins
	# Card drop, seeded by the campaign so a replayed season rolls the same.
	var league: Dictionary = result.get("league", {})
	var drop := CardRewards.roll(bool(result.get("won", false)), bool(league.get("playoff", false)),
		QuickSim.seed_from([doc["season"]["seed"], "drop", int(doc["career"]["totals"]["games"])]))
	if drop != "":
		add_card(drop)
	last_heat["card_drop"] = drop


## The title's two-step pick: mode, then area.
func start_area(mode: String, area: String) -> void:
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
	get_tree().change_scene_to_file(RESULTS_SCENE)
