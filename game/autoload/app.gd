extends Node
## Screen routing, run handoff, and the player's live cosmetic selection
## (hoop set + ball set), with coins / ownership persisted by SaveService.
## The M2 seam: when MatchEngine arrives, match screens register here beside
## the time trial with the same pattern.

const SPLASH_SCENE := "res://game/screens/splash_screen.tscn"
const TITLE_SCENE := "res://game/screens/title_screen.tscn"
const TIME_TRIAL_SCENE := "res://game/screens/time_trial_screen.tscn"
const RESULTS_SCENE := "res://game/screens/results_screen.tscn"
const HEAT_SCENE := "res://game/screens/heat_screen.tscn"
const HEAT_RESULT_SCENE := "res://game/screens/heat_result_screen.tscn"
const CREDITS_SCENE := "res://game/screens/credits_screen.tscn"
## The intro loop (title + credits); an area's ambience replaces it.
const TITLE_MUSIC := {"id": "title", "clip": "res://assets/music/title_moog.ogg", "gain_db": -15.0}
## Level music (2026-10-16): one shared playlist on every court, toggled by
## the HUD's bottom-left note (Sfx.start_level_music / stop_level_music),
## remembered as the `musicOn` setting — off on a fresh install. The in-world
## radios (the beach boombox, the city speaker) came out with it.
const LEVEL_MUSIC := {"gain_db": -14.0, "tracks": [
	"res://assets/music/title_moog.ogg", "res://assets/music/zero_mass.ogg", "res://assets/music/scarpeta.ogg",
	"res://assets/music/footloose.ogg", "res://assets/music/synthwave_beat.ogg", "res://assets/music/anabell.ogg"]}

## Level gating for leagues and areas (docs/PROGRESSION.md: a league's
## `unlock` level, reached by playing the league before it). On.
## Level gates on areas and leagues (docs/PROGRESSION.md). OFF in debug builds
## — the editor and the phone dev APK (tools/android_deploy.sh exports debug)
## can reach every area — unless the dev LEVEL GATES toggle in Settings turns
## them on (the tuning part's `gates`), to play like a new user would; a
## release build gates as designed, always.
var league_gating: bool = not OS.is_debug_build()
## The league whose dashboard / heat is active ("" outside leagues).
var current_league := ""
## The home screen's last card (page index), so leaving an area returns to it.
var home_card := 0
## The area archive opens in front of the home on a cold launch (docs/HOME.md
## → Area archive); the title consumes this.
var show_archive := true
## A league the home page should open straight into (its id), set by
## to_league_hub() — the heat result's CONTINUE SEASON. Cleared once used.
var home_open_league := ""
## The welcome toast the title shows once after NEW PLAYER (design 35a):
## {name, tag, town}. Cleared once shown.
var pending_welcome := {}
## QA: pretend there is no player yet (the splash shows NEW GAME, the form).
var qa_fresh := false
## QA only (tools/qa_driver.gd --qa-perf): a bot shoots on OUR side of a
## league heat, so both sides play like a real match while the probe measures.
var qa_player_bot: AiRatings = null
## A walkthrough the next screen should run (its id, design 36a), set by
## create_player ("home"); the title consumes it once the home shows.
var pending_walkthrough := ""

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
	# The park (docs/HOME.md, 2026-10-15): the winter court, its own slim park
	# hoop with a cotton net, the spot game.
	"park": {"arena": "park", "hoop": "park", "geo": "park", "dist": SimGeometry.PARK_DIST,
		"endless": true, "board_motion": false, "hud_label": "PARK", "led_text": "", "location": "park"},
	"trial_park": {"arena": "park", "hoop": "park", "geo": "park", "dist": SimGeometry.PARK_DIST,
		"endless": false, "board_motion": false, "hud_label": "", "led_text": "READY", "location": "park",
		"spot_shuffle": true},
	"heat_park": {"arena": "park", "hoop": "park", "geo": "park", "dist": SimGeometry.PARK_DIST,
		"endless": false, "board_motion": false, "hud_label": "", "led_text": "READY", "location": "park",
		"heat": true, "calib_key": "park", "spot_shuffle": true},
}
## mode ("trial"/"practice"/"heat") × area ("cage"/"beach"/"park"/"city") → MODES id.
const AREA_MODES := {
	"trial": {"cage": "trial", "beach": "trial_beach", "park": "trial_park", "city": "trial_city"},
	"practice": {"cage": "practice", "beach": "beach", "park": "park", "city": "city"},
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
	if cfg["geo"] == "park":
		return SimGeometry.park(cfg["dist"])
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
	# The designed 720×1280 band centred on whatever the screen is (docs/HOME.md → Screen vs. design).
	UiLayout.install(get_tree().root)
	# Every move between scenes goes through the loader (design "Loading States" 39a).
	loader = SceneLoader.new()
	loader.name = "SceneLoader"
	add_child(loader)
	var saved := SaveService.get_tuning()
	tuning_mode = bool(saved.get("tuningMode", false))
	if OS.is_debug_build():
		league_gating = bool(saved.get("gates", false))
	shot_help = shot_help_from_saved(SaveService.get_settings().get("shotHelp", SHOT_HELP_OFF))
	dark_mode = bool(SaveService.get_settings().get("darkMode", false))
	music_on = bool(SaveService.get_settings().get("musicOn", false))
	ai_difficulty = AiDifficulty.normalize(SaveService.get_settings().get("aiDifficulty", AiDifficulty.DEFAULT))
	hud_side = hud_side_from_saved(SaveService.get_settings().get("hudSide", "left"))
	tuning.apply_dict(saved.get("fields", {}))
	_resolve_cosmetics()
	# The device account (docs/BACKEND.md): minted locally now, registered
	# with the server when the net allows; nothing waits on it.
	Net.ensure_account.call_deferred()
	Net.save_pulled.connect(_on_save_pulled)


## The cloud mirror brought newer parts (a new phone, or play elsewhere):
## re-read what this autoload caches and let the home page redraw.
func _on_save_pulled(parts: Array) -> void:
	if parts.has(SaveService.SETTINGS_PART):
		shot_help = shot_help_from_saved(SaveService.get_settings().get("shotHelp", SHOT_HELP_OFF))
		dark_mode = bool(SaveService.get_settings().get("darkMode", false))
		music_on = bool(SaveService.get_settings().get("musicOn", false))
		ai_difficulty = AiDifficulty.normalize(SaveService.get_settings().get("aiDifficulty", AiDifficulty.DEFAULT))
		hud_side = hud_side_from_saved(SaveService.get_settings().get("hudSide", "left"))
	if parts.has(SaveService.COSMETICS_PART):
		_resolve_cosmetics()
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("rebuild_chrome"):
		scene.call("rebuild_chrome")


func _resolve_cosmetics() -> void:
	var c := SaveService.get_cosmetics()
	hoop_set = CosmeticLibrary.get_hoop(str(Dictionary(c.get("hoop", {})).get("selected", "")))
	if hoop_set == null:
		hoop_set = CosmeticLibrary.starter_hoop()
	ball_set = CosmeticLibrary.get_ball(str(Dictionary(c.get("ball", {})).get("selected", "")))
	if ball_set == null:
		ball_set = CosmeticLibrary.starter_ball()
	Sfx.load_hoop_set(hoop_set)
	Sfx.load_ball_set(ball_set)


func set_tuning_mode(on: bool) -> void:
	tuning_mode = on
	SaveService.put_tuning(on, SaveService.get_tuning().get("fields", {}))


## Dev builds only: the level gates on or off (a release build ignores this).
func set_league_gating(on: bool) -> void:
	if not OS.is_debug_build():
		return
	league_gating = on
	SaveService.put_tuning_gates(on)
	# A card the gate just closed should not stay as the home's page.
	if on and not area_unlocked(str(AreaArchiveCopy.AREAS[clampi(home_card, 0, AreaArchiveCopy.AREAS.size() - 1)].get("area", "cage"))):
		home_card = 0


## Coerce a saved value into a mode. The setting was a BOOL before it grew a
## middle step, so an older save reads true as the full treatment rather than
## silently resetting to off.
static func shot_help_from_saved(raw: Variant) -> int:
	if raw is bool:
		return SHOT_HELP_FULL if raw else SHOT_HELP_OFF
	if raw is int or raw is float:
		return clampi(int(raw), SHOT_HELP_OFF, SHOT_HELP_FULL)
	return SHOT_HELP_OFF


## Level music on the courts (the HUD's note): remembered across levels and launches.
var music_on := false


func set_music_on(on: bool) -> void:
	music_on = on
	var s := SaveService.get_settings()
	s["musicOn"] = on
	SaveService.put_settings(s)


## AI DIFFICULTY (Ross, 2026-10-19; core/ai/ai_difficulty.gd): one strength on
## every court, scaled by this for every AI the player faces. Remembered
## across launches and synced as the `aiDifficulty` setting.
var ai_difficulty := AiDifficulty.DEFAULT


func set_ai_difficulty(level: String) -> void:
	ai_difficulty = AiDifficulty.normalize(level)
	var s := SaveService.get_settings()
	s["aiDifficulty"] = ai_difficulty
	SaveService.put_settings(s)


## The settings row's tap: easy → normal → hard → easy.
func cycle_ai_difficulty() -> void:
	set_ai_difficulty(AiDifficulty.next(ai_difficulty))


## HUD SIDE (Ross, 2026-10-24): which edge the match toasts slide in from and
## where the music note sits — "left" (the design's layout) or "right".
## Remembered across launches and synced as the `hudSide` setting; the
## screens read it when they build.
var hud_side := "left"


static func hud_side_from_saved(raw: Variant) -> String:
	return "right" if str(raw) == "right" else "left"


func set_hud_side(side: String) -> void:
	hud_side = hud_side_from_saved(side)
	var s := SaveService.get_settings()
	s["hudSide"] = hud_side
	SaveService.put_settings(s)


## The settings row's tap: left ↔ right.
func cycle_hud_side() -> void:
	set_hud_side("right" if hud_side == "left" else "left")


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


## The courts open to this player, in play order.
func unlocked_areas() -> Array:
	var out := []
	for a in ["cage", "beach", "park", "city"]:
		if area_unlocked(a):
			out.push_back(a)
	return out


# ---- tickets (the one currency, global) + cosmetics ----------------------------
# docs/ECONOMY.md: tickets are earned by time trials, league heats and titles
# and spent on PEGGY plays and each league's cards (below).


func tickets() -> int:
	return int(SaveService.get_cosmetics().get("tickets", 0))


func grant_tickets(n: int) -> void:
	if n <= 0:
		return
	var c := SaveService.get_cosmetics()
	c["tickets"] = int(c.get("tickets", 0)) + n
	SaveService.put_cosmetics(c)


func owns(kind: String, id: String) -> bool:
	return owned_ids(kind).has(id)


## Select an owned set of `kind` ("hoop" | "ball"). Takes effect on the next
## screen build (sounds swap immediately). False if unknown or not owned.
func select(kind: String, id: String) -> bool:
	if not owns(kind, id):
		return false
	var c := SaveService.get_cosmetics()
	_ensure_kind(c, kind)
	c[kind]["selected"] = id
	SaveService.put_cosmetics(c)
	_resolve_cosmetics()
	return true


func select_hoop(id: String) -> bool:
	return select("hoop", id)


func select_ball(id: String) -> bool:
	return select("ball", id)


## Spend tickets on a set. False if unknown, already owned, or unaffordable.
## Hoops in the locker (buy for tickets, swap) are off for now (Ross,
## 2026-10-07): the player's hoop stays the starter; modes still mandate
## their own (the beach's street hoop, the city's chain). One flag to bring
## the counter back.
const HOOPS_IN_LOCKER := false


func try_buy(kind: String, id: String) -> bool:
	if kind == "ball" or kind == "net":
		return false   # balls and nets are PEGGY prizes (docs/LOCKER.md), never bought
	if kind == "hoop" and not HOOPS_IN_LOCKER:
		return false   # the hoop counter is closed for now
	var set: CosmeticSet = _set_for(kind, id)
	if set == null or owns(kind, id):
		return false
	var c := SaveService.get_cosmetics()
	if int(c.get("tickets", 0)) < set.price_coins:
		return false
	c["tickets"] = int(c.get("tickets", 0)) - set.price_coins
	_ensure_kind(c, kind)
	c[kind]["owned"].push_back(id)
	SaveService.put_cosmetics(c)
	return true


## The set a kind's id names ("hoop" | "ball" | "net"), null if unknown.
func _set_for(kind: String, id: String) -> CosmeticSet:
	match kind:
		"hoop":
			return CosmeticLibrary.get_hoop(id)
		"ball":
			return CosmeticLibrary.get_ball(id)
		"net":
			return CosmeticLibrary.get_net(id)
	return null


## The sets every save owns for a kind (the starters, the stock nets).
func _starters(kind: String) -> Array:
	match kind:
		"hoop":
			return [CosmeticLibrary.starter_hoop()]
		"ball":
			return [CosmeticLibrary.starter_ball()]
		"net":
			return CosmeticLibrary.stock_nets()
	return []


## A kind's block in a cosmetics doc, created when missing (nets select per area).
func _ensure_kind(c: Dictionary, kind: String) -> void:
	if c.has(kind) and c[kind] is Dictionary:
		return
	c[kind] = SaveService.default_nets() if kind == "net" else {"selected": "", "owned": []}


# ---- PEGGY (docs/LOCKER.md) --------------------------------------------------------
## The drop machine. Tickets only ever buy plays: PLAY feeds a ticket and
## CREDITS the machine (saved, so the credit survives leaving the page), DROP
## spends the credit on a drop that wins a ball or a net the player does not
## own yet. The plates shown come from the drop index, so what is on the
## board is what can be won; the index only moves on a completed drop.

var last_prize: Dictionary = {}


## A ticket is in the machine, waiting for DROP.
func peggy_credit() -> bool:
	return bool(Dictionary(SaveService.get_cosmetics().get("peggy", {})).get("credit", false))


## PLAY: spend a drop's worth of tickets and credit the machine. False when
## a credit is already in or the tickets are short.
func peggy_insert_ticket() -> bool:
	if peggy_credit():
		return false
	if not spend_tickets(PeggyPrizes.DROP_COST):
		return false
	_set_credit(true)
	return true


func _set_credit(on: bool) -> void:
	var c := SaveService.get_cosmetics()
	var pg: Dictionary = c.get("peggy", {})
	pg["credit"] = on
	c["peggy"] = pg
	SaveService.put_cosmetics(c)


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
	for starter in _starters(kind):
		if starter != null and not out.has(starter.id):
			out.push_back(starter.id)
	return out


func owned_count(kind: String) -> int:
	return owned_ids(kind).size()


## Hand the player a set without charging (a PEGGY prize). A new ball or
## net is flagged unseen until the locker is opened.
func grant_cosmetic(kind: String, id: String) -> bool:
	var set: CosmeticSet = _set_for(kind, id)
	if set == null or owns(kind, id):
		return false
	var c := SaveService.get_cosmetics()
	_ensure_kind(c, kind)
	c[kind]["owned"].push_back(id)
	SaveService.put_cosmetics(c)
	if kind == "ball" or kind == "net":
		var st := SaveService.get_settings()
		var fresh: Array = Array(st.get("newBalls", [])).duplicate()
		if not fresh.has(id):
			fresh.push_back(id)
		st["newBalls"] = fresh
		SaveService.put_settings(st)
	return true


# ---- Nets (docs/LOCKER.md → NETS) --------------------------------------------------
## A net is a look for the hoop's KIND of net: "cotton" on the nylon hoops
## (cage, beach), "chain" on the city's steel rim. Bought for tickets in the
## locker (which hangs it on every area of its kind); the pause menu swaps
## it per court. Saved as cosmetics.net {owned, selected: {area: id}}.

## QA / debug: hang this net everywhere it fits, without touching the save.
var net_override: NetSet


## The net kind a mode's hoop hangs.
func net_kind_for_mode(id: String) -> String:
	return NetSet.kind_of_hoop(hoop_for_mode(id))


## The net kind an area hangs (its practice mode's hoop; a later area joins
## AREA_MODES and this follows).
func net_kind_for_area(area: String) -> String:
	var modes: Dictionary = AREA_MODES["practice"]
	return net_kind_for_mode(str(modes.get(area, "practice")))


## The areas that hang a kind of net, in AREA_MODES order.
func net_areas(kind: String) -> Array:
	var out: Array = []
	for area in AREA_MODES["practice"]:
		if net_kind_for_area(str(area)) == kind:
			out.push_back(str(area))
	return out


func _net_doc(c: Dictionary) -> Dictionary:
	return c["net"] if c.has("net") and c["net"] is Dictionary else SaveService.default_nets()


## The net hung on an area: the selection when it is owned — any kind, cotton
## or chain, hangs on any hoop (Ross, 2026-10-16) — else the hoop's own
## kind's stock net. The hoop and the ball's physics stay the area's; the
## net's body, look and sound follow the choice.
func net_set_for(area: String) -> NetSet:
	if net_override != null:
		return net_override
	var sel: Dictionary = _net_doc(SaveService.get_cosmetics()).get("selected", {})
	var ns := CosmeticLibrary.get_net(str(sel.get(area, "")))
	if ns != null and owns("net", ns.id):
		return ns
	return CosmeticLibrary.stock_net(net_kind_for_area(area))


## The net a mode plays with (its area's).
func net_for_mode(id: String) -> NetSet:
	return net_set_for(str(mode_config(id).get("location", "cage")))


## Hang an owned net on one area (the locker's sheet, the pause menu's NET
## row). False for an unknown or unowned net or an unknown area.
func select_net(area: String, id: String) -> bool:
	var ns := CosmeticLibrary.get_net(id)
	if ns == null or not owns("net", id) or not AREA_MODES["practice"].has(area):
		return false
	var c := SaveService.get_cosmetics()
	_ensure_kind(c, "net")
	if not (c["net"].get("selected") is Dictionary):
		c["net"]["selected"] = {}
	c["net"]["selected"][area] = id
	SaveService.put_cosmetics(c)
	return true


## The sheet's EVERYWHERE (and PEGGY's EQUIP): hang an owned net on every area.
func select_net_everywhere(id: String) -> bool:
	var ns := CosmeticLibrary.get_net(id)
	if ns == null or not owns("net", id):
		return false
	var c := SaveService.get_cosmetics()
	_ensure_kind(c, "net")
	if not (c["net"].get("selected") is Dictionary):
		c["net"]["selected"] = {}
	for area in AREA_MODES["practice"]:
		c["net"]["selected"][area] = id
	SaveService.put_cosmetics(c)
	return true


## The areas a net is hung on right now.
func net_in_use_areas(id: String) -> Array:
	var out: Array = []
	for area in AREA_MODES["practice"]:
		var ns := net_set_for(str(area))
		if ns != null and ns.id == id:
			out.push_back(str(area))
	return out


## The area whose unlock page is due (set when a match's XP reaches its
## level; "" when none). The heat screen takes it after the match-end page.
var pending_unlock := ""


func take_pending_unlock() -> String:
	var id := pending_unlock
	pending_unlock = ""
	return id


## Has the player seen a walkthrough (design 36a)? (settings.walkthroughsSeen)
func walkthrough_seen(id: String) -> bool:
	return Array(SaveService.get_settings().get("walkthroughsSeen", [])).has(id)


func mark_walkthrough_seen(id: String) -> void:
	var st := SaveService.get_settings()
	var seen: Array = Array(st.get("walkthroughsSeen", [])).duplicate()
	if seen.has(id):
		return
	seen.push_back(id)
	st["walkthroughsSeen"] = seen
	SaveService.put_settings(st)


## The first-shot tutorial (design 38a, docs/HOME.md → Shot tutorial): once,
## before the first offline match; SKIP counts. settings.shotTutorialSeen.
func shot_tutorial_seen() -> bool:
	return bool(SaveService.get_settings().get("shotTutorialSeen", false))


func mark_shot_tutorial_seen() -> void:
	var st := SaveService.get_settings()
	if bool(st.get("shotTutorialSeen", false)):
		return
	st["shotTutorialSeen"] = true
	SaveService.put_settings(st)


## QA passes that enter a match skip the tutorial unless they ask for it (--qa-tutorial).
var qa_skip_tutorial := false


## Has the player seen an area's unlock page? (settings.unlocksSeen)
func unlock_seen(area: String) -> bool:
	return Array(SaveService.get_settings().get("unlocksSeen", [])).has(area)


func mark_unlock_seen(area: String) -> void:
	var st := SaveService.get_settings()
	var seen: Array = Array(st.get("unlocksSeen", [])).duplicate()
	if seen.has(area):
		return
	seen.push_back(area)
	st["unlocksSeen"] = seen
	SaveService.put_settings(st)


## Prizes (balls and nets) won but not yet looked at in the locker (the
## locker icon's dot). The save key keeps its old name.
func unseen_prizes() -> Array:
	var out := []
	for id in Array(SaveService.get_settings().get("newBalls", [])):
		if (owns("ball", str(id)) or owns("net", str(id))) and not out.has(id):
			out.push_back(id)
	return out


func mark_prizes_seen() -> void:
	var st := SaveService.get_settings()
	if Array(st.get("newBalls", [])).is_empty():
		return
	st["newBalls"] = []
	SaveService.put_settings(st)


# ---- visited areas (docs/HOME.md → Area archive) ------------------------------------
## An open area you have never landed on carries a NEW badge on the home's
## next chevron and on its archive card until you visit it.


func visited_areas() -> Array:
	return Array(SaveService.get_settings().get("visitedAreas", [])).duplicate()


func mark_area_visited(id: String) -> void:
	var st := SaveService.get_settings()
	var seen: Array = Array(st.get("visitedAreas", [])).duplicate()
	if seen.has(id):
		return
	seen.push_back(id)
	st["visitedAreas"] = seen
	SaveService.put_settings(st)


func area_unvisited(id: String) -> bool:
	return area_unlocked(id) and not visited_areas().has(id)


func peggy_seed(drop_index: int) -> int:
	return DetRng.hash_seed("%s:peggy:%d" % [SaveService.get_client_id(), drop_index])


func peggy_roster() -> Array:
	return EconomyBudget.peggy_roster()


## The seven plates for the NEXT drop: [{base, rarity, kind, id}].
func peggy_slots() -> Array:
	var rng := DetRng.new(peggy_seed(drop_count())).fork("slots")
	return PeggyPrizes.slots(level(), owned_ids("ball") + owned_ids("net"), peggy_roster(), rng)


## DROP: one drop at this aim, on the credit PLAY put in. {} without a
## credit; else the prize record {slot, base, rarity, kind, id, refund,
## drop_index, aim, result, owned_after, roster_size, plates}.
func peggy_drop(aim_x: float) -> Dictionary:
	if not peggy_credit():
		return {}
	var plates := peggy_slots()
	var index := drop_count()
	var result := PeggyBoard.simulate(aim_x, DetRng.new(peggy_seed(index)).fork("drop").state)
	var plate: Dictionary = plates[int(result["slot"])]
	var refund := PeggyPrizes.refund(plate)
	var kind := str(plate.get("kind", "ball"))
	var id := str(plate.get("id", ""))
	if id != "":
		grant_cosmetic(kind, id)
	elif refund > 0:
		grant_tickets(refund)
	var c := SaveService.get_cosmetics()
	var pg: Dictionary = c.get("peggy", {})
	pg["drops"] = index + 1
	pg["credit"] = false
	c["peggy"] = pg
	SaveService.put_cosmetics(c)
	var roster_size := 0
	for e in peggy_roster():
		if PeggyPrizes.kind_of(e) == kind:
			roster_size += 1
	last_prize = {"slot": int(result["slot"]), "base": plate.get("base", ""), "rarity": plate.get("rarity", ""),
		"kind": kind, "id": id, "refund": refund, "drop_index": index, "aim": aim_x, "result": result,
		"owned_after": owned_count(kind), "roster_size": roster_size, "plates": plates}
	return last_prize


# ---- online 1v1 (docs/BACKEND.md → Phase 3) -------------------------------------------

## The live room while a match is being arranged or played (a MatchClient,
## or the QA driver's fake peer: anything with `message`/`closed` signals
## and `send`/`close`/`is_open`). Null between matches. (`match` is a
## GDScript keyword, hence `room`.)
var room: Node = null
## How the current lobby attempt was started: ranked | quick | create | join.
var match_how := ""
var match_area := ""
## The pre-match step (docs/BACKEND.md → Ranked, 2026-10-19): the room's
## `matched` ({peer, levels, tiers, cap, seconds}) while both phones pick a
## loadout under the card cap; {} otherwise. The PreMatchPage reads it.
var pre_match: Dictionary = {}
## The ranked queue poll (a SceneTree timer loop) while a rated search runs.
var _ranked_search := 0
## The lobby's face-off reveal (design 37a, 2026-10-18): the room sends the
## tip-off the moment the second phone is in, so both phones hold it this
## long after it lands — the same on both, so they stay in step. Rematches
## and resumed rooms go at once.
const FOUND_HOLD_S := 2.4
## True while a tip-off is being held for the reveal (tests read it).
var tip_off_held := false


## Ask the Lobby, open the room, and play when the other phone arrives.
## `on_state` is told the way: waiting(how, code) / found(peer) / failed(reason).
func start_online(area: String, how: String, code: String, on_state: Callable) -> void:
	cancel_online()
	match_how = how
	match_area = area
	if not Net.enabled or not Net.registered():
		on_state.call("failed", "offline")
		return
	if how == "ranked":
		_search_ranked(on_state)
		return
	var path := "/v1/match/" + ("quick" if how == "quick" else ("code" if how == "create" else "join"))
	var body := {"area": area}
	if how == "join":
		body["code"] = code
	elif how == "quick" and area == "any":
		# ANY court (design 37a): the Lobby pairs us on a court we both own.
		body["areas"] = unlocked_areas()
	var r: Dictionary = await Net.request_json("match", HTTPClient.METHOD_POST, path, body)
	if not r["ok"]:
		var why := "offline"
		if r["code"] == 404:
			why = "not_found"
		elif r["code"] == 400 and str(r["json"].get("error", "")) == "own_code":
			why = "own_code"
		elif r["code"] == 429:
			why = "throttled"
		on_state.call("failed", why)
		return
	# A joiner is told the court the Lobby paired on; an any-court host learns it from the room.
	var court := str(r["json"].get("area", area))
	match_area = court
	if _open_room(str(r["json"].get("room", "")), court, on_state):
		on_state.call("waiting", how, str(r["json"].get("code", "")))
	else:
		on_state.call("failed", "offline")


## RANKED (docs/BACKEND.md → Ranked): one global rated queue. The Lobby pairs
## on a court both own, by rating, widening every few seconds; the phone polls
## `/v1/match/ranked` every `queue.poll_s` until it is paired (or cancels),
## then opens the room like any other.
func _search_ranked(on_state: Callable) -> void:
	_ranked_search += 1
	var my_search := _ranked_search
	match_area = "any"
	on_state.call("waiting", "ranked", "")
	var poll_s := float(RankedRules.queue_cfg().get("poll_s", 4))
	while match_how == "ranked" and my_search == _ranked_search:
		var r: Dictionary = await Net.request_json("match", HTTPClient.METHOD_POST, "/v1/match/ranked", {})
		if match_how != "ranked" or my_search != _ranked_search:
			return
		if not r["ok"]:
			if r["code"] != -1 and r["code"] != 0:
				on_state.call("failed", "throttled" if r["code"] == 429 else "offline")
				match_how = ""
				return
		elif bool(r["json"].get("paired", false)):
			# Paired: open the room; its joined / peer messages carry the other
			# phone's handle for the found card (the queue's record has none).
			var court := str(r["json"].get("area", "cage"))
			match_area = court
			if not _open_room(str(r["json"].get("room", "")), court, on_state):
				on_state.call("failed", "offline")
			return
		await (Engine.get_main_loop() as SceneTree).create_timer(poll_s).timeout


## The pre-match pick: the three slots as the room wants them, ready once
## READY is pressed (the page sends a provisional one on build, so a timeout
## starts with it).
func send_loadout(slots: Array, ready: bool) -> void:
	if room == null or not room.has_method("send"):
		return
	room.send(MatchProtocol.loadout(slots, ready, my_kit(str(pre_match.get("area", match_area)))))


## The kit the other phone's PiP shows us in (docs/LOCKER.md → The kit): our
## ball, the net we hang on this court, and the hoop only where the court
## lets us pick one (the cage: `App.MODES` fixes the others').
func my_kit(area: String) -> Dictionary:
	var modes: Dictionary = AREA_MODES["practice"]
	var mode_id := str(modes.get(area, "practice"))
	var hoop_id := hoop_set.id if hoop_set != null and str(mode_config(mode_id).get("hoop", "")) == "" else ""
	return MatchProtocol.kit(ball_set.id if ball_set != null else "", net_set_for(area).id, hoop_id)


## Open a room and route its messages for the life of the client: the lobby
## states before the tip-off, the payout and the rematch after. False when
## the socket could not open.
func _open_room(room_id: String, area: String, on_state: Callable) -> bool:
	var client := MatchClient.new()
	client.name = "Match"
	add_child(client)
	room = client
	rematch_state = ""
	pre_match = {}
	if not client.open(room_id, area):
		cancel_online()
		return false
	client.message.connect(func(msg: Dictionary) -> void:
		if room != client:
			return
		match str(msg["t"]):
			MatchProtocol.PEER:
				on_state.call("found", _with_area(Dictionary(msg.get("peer", {})), msg))
			MatchProtocol.JOINED:
				if msg.get("peer", null) is Dictionary:
					on_state.call("found", _with_area(Dictionary(msg["peer"]), msg))
			MatchProtocol.MATCHED:
				pre_match = msg.duplicate(true)
				pre_match["side"] = client.side
				on_state.call("matched", pre_match)
			MatchProtocol.PEER_LOADOUT:
				on_state.call("peer_loadout", msg)
			MatchProtocol.START:
				if not pre_match.is_empty() and not bool(msg.get("resumed", false)):
					# The pre-match page runs the count (design "Pre Match" 37a), then tip_off_now().
					pending_start = msg.duplicate(true)
					on_state.call("court", str(msg.get("area", match_area)))
					on_state.call("start", pending_start)
				elif match_how in ["ranked", "quick", "create", "join"] and not bool(msg.get("resumed", false)):
					pre_match = {}
					on_state.call("court", str(msg.get("area", match_area)))
					_hold_tip_off(client, msg)
				else:
					pre_match = {}
					_tip_off(client, msg)
			MatchProtocol.SETTLED:
				settled_online(msg)
			MatchProtocol.REMATCH:
				_set_rematch("both" if rematch_state in ["offered", "both"] else "wanted")
			MatchProtocol.REMATCH_GO:
				_rematch_go(str(msg["room"]), str(msg.get("area", area)), on_state)
			MatchProtocol.EXPIRED:
				cancel_online()
				on_state.call("failed", "expired")
			MatchProtocol.PEER_LEFT:
				if client.start.is_empty():   # they left before the tip-off
					cancel_online()
					on_state.call("failed", "peer_left")
				else:
					_set_rematch("gone")
	)
	client.closed.connect(func(reason: String) -> void:
		if room == client and client.start.is_empty():
			cancel_online()
			on_state.call("failed", "expired" if reason == "expired" else "offline")
	)
	return true


# ---- rematch (docs/BACKEND.md → Phase 3, Rematch) ----------------------------------------------------

## "" | offered | wanted | both | gone — the post-match REMATCH card reads it.
signal rematch_changed(state: String)
var rematch_state := ""


func _set_rematch(state: String) -> void:
	rematch_state = state
	rematch_changed.emit(state)


## Ask the other phone for another go (or accept their ask).
func offer_rematch() -> void:
	if room == null or not room.has_method("send") or not MatchCopy.rematch_active(rematch_state):
		return
	room.send(MatchProtocol.rematch())
	_set_rematch("both" if rematch_state == "wanted" else "offered")


## The found peer with the court it is on: the message's `area` (a joiner's
## `joined`, the room's `peer` on a new Worker), else the court we asked for.
func _with_area(peer: Dictionary, msg: Dictionary) -> Dictionary:
	var a := str(msg.get("area", ""))
	peer["area"] = a if a != "" and a != "any" else match_area
	return peer


## Let the face-off play, then tip off — unless the room went away meanwhile.
func _hold_tip_off(client: MatchClient, start: Dictionary) -> void:
	tip_off_held = true
	await (Engine.get_main_loop() as SceneTree).create_timer(FOUND_HOLD_S).timeout
	tip_off_held = false
	if room != client:
		return
	_tip_off(client, start)


## Both asked: the old room hands us a fresh one; the lobby path from here.
func _rematch_go(room_id: String, area: String, on_state: Callable) -> void:
	var old: Node = room
	room = null
	if old != null and old.has_method("close"):
		old.close("rematch")
	if not (old is MatchClient) and old != null:
		old.queue_free()
	match_how = "rematch"
	match_area = area
	if not _open_room(room_id, area, on_state):
		_set_rematch("gone")


## Both phones are in: the heat on the room's seed, the other phone in the
## opponent slot. The screen takes the client from `room`.
## The room's `start`, held while the pre-match page counts down; the page's
## `go` calls tip_off_now (the room already started: both phones count the
## same seconds, latency apart, as they already do for the tip-off itself).
var pending_start: Dictionary = {}

func tip_off_now() -> void:
	if pending_start.is_empty() or not (room is MatchClient):
		return
	var start := pending_start
	pending_start = {}
	_tip_off(room as MatchClient, start)


func _tip_off(client: MatchClient, start: Dictionary) -> void:
	pending_start = {}
	if match_how == "quick":
		Net.request_json("match", HTTPClient.METHOD_POST, "/v1/match/leave", {"area": match_area})
	pre_match = {}
	online_settle = {}
	rematch_state = ""
	var cfg := MatchProtocol.heat_cfg(start, client.peer, client.side)
	start_heat(str(cfg["mode"]), cfg)


## The room's decision for the match just played ({won, reason, ranked} and,
## rated, {rating, rank, events, peak} — docs/BACKEND.md → Ranked). {} until
## it lands. The post-match page listens; the rank the server sends becomes
## Net.me_rank.
signal online_settled(settle: Dictionary)
var online_settle: Dictionary = {}


func settled_online(msg: Dictionary) -> void:
	if not online_settle.is_empty():
		return   # once (the screen and this autoload both hear the room)
	online_settle = msg.duplicate(true)
	# Stage B (docs/BACKEND.md → Ranked → Stage B): the tickets the server
	# reports are granted here, once; cards the server moved come with the
	# refresh below. The settle's keys ride into last_heat whichever of this
	# and settle_heat lands second.
	if msg.has("tickets") and int(msg["tickets"]) > 0:
		grant_tickets(int(msg["tickets"]))
	_merge_online_settle()
	if bool(msg.get("ranked", false)):
		if msg.get("rank") is Dictionary:
			# The decision's rank carries the tier; the record follows from
			# what we knew plus this result, until the next /v1/me.
			var was: Dictionary = Net.me_rank
			var r: Dictionary = Dictionary(msg["rank"]).duplicate(true)
			var won := bool(msg.get("won", false))
			r["games"] = int(was.get("games", 0)) + 1
			r["wins"] = int(was.get("wins", 0)) + (1 if won else 0)
			r["losses"] = int(was.get("losses", 0)) + (0 if won else 1)
			if msg.get("rating") is Dictionary and Dictionary(msg["rating"]).get("after") is Dictionary:
				r["cons"] = float(Dictionary(msg["rating"]["after"]).get("cons", 0.0))
			Net.set_me_rank(r)
			Net.fetch_me()
	Net.refresh_cards()
	online_settled.emit(online_settle)


## The decision's keys onto the result page's dict, and the bright spots
## against the online store once the result (`sides`) is there too.
const SETTLE_KEYS := ["ranked", "rating", "rank", "events", "peak", "tickets", "pay", "spoils", "meter", "granted", "milestones", "loss_streak"]

func _merge_online_settle() -> void:
	if online_settle.is_empty() or not bool(last_heat.get("online", false)):
		return
	for k in SETTLE_KEYS:
		if online_settle.has(k):
			last_heat[k] = online_settle[k]
	if str(online_settle.get("reason", "")) != "" and not last_heat.has("reason"):
		last_heat["reason"] = online_settle["reason"]
	if last_heat.has("sides") and not last_heat.has("bright"):
		var prog := progress()
		var online: Dictionary = prog.get("online", {}) if prog.get("online") is Dictionary else {}
		last_heat["bright"] = BrightSpots.note(online, last_heat)
		prog["online"] = online
		SaveService.put_progress(prog)


## SHOOT AROUND? (docs/BACKEND.md → Ranked → Stage B): after a losing stretch
## the post-match page offers a time trial with a small ticket bonus, once a
## UTC day (the phone's stamp, `progress.online.shoot_day`).
var _shoot_bonus_pending := false

static func utc_day() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0)


func shoot_around_offered() -> bool:
	var cfg := OnlineDrops.shoot_around_cfg()
	if cfg.is_empty() or online_settle.is_empty():
		return false
	if int(online_settle.get("loss_streak", 0)) < int(cfg.get("after_losses", 2)):
		return false
	var online: Dictionary = progress().get("online", {}) if progress().get("online") is Dictionary else {}
	return int(online.get("shoot_day", -1)) != utc_day()


## The shoot-around's bonus when a trial started from the offer finishes
## (OnlineDrops.shoot_around_cfg), once a UTC day: the day is stamped here.
func take_shoot_bonus() -> int:
	if not _shoot_bonus_pending:
		return 0
	_shoot_bonus_pending = false
	var bonus := int(OnlineDrops.shoot_around_cfg().get("bonus", 0))
	var prog := progress()
	var online: Dictionary = prog.get("online", {}) if prog.get("online") is Dictionary else {}
	online["shoot_day"] = utc_day()
	prog["online"] = online
	SaveService.put_progress(prog)
	return bonus


func start_shoot_around() -> void:
	if not shoot_around_offered():
		return
	_shoot_bonus_pending = true
	var area := str(last_heat.get("location", "cage"))
	cancel_online()
	start_area("trial", area if area_unlocked(area) else "cage")


## Leave the lobby / the room (a cancel, a back, a finished match).
func cancel_online() -> void:
	if room != null:
		if room.has_method("close"):
			room.close("bye")   # a MatchClient drains its queue and frees itself
		if not (room is MatchClient):
			room.queue_free()
		room = null
	rematch_state = ""
	pre_match = {}
	if match_how == "quick" and match_area != "" and Net.enabled and Net.registered():
		Net.request_json("match", HTTPClient.METHOD_POST, "/v1/match/leave", {"area": match_area})
	elif match_how == "ranked" and Net.enabled and Net.registered():
		_ranked_search += 1   # stops the poll loop
		Net.request_json("match", HTTPClient.METHOD_POST, "/v1/match/leave", {"area": "any", "ranked": true})
	match_how = ""


# ---- routing -------------------------------------------------------------------

## The scene mover (game/ui/scene_loader.gd): threaded loads, the busy
## button, the loading screen past 0.4 s (design "Loading States" 39a / 39b).
var loader: SceneLoader


## Move to `path` through the loader: `kind` and the area pick the loading
## screen's words and art (LoadingCopy.dest), and the area's arena and hoop
## models load on threads with the scene.
func _move(path: String, kind: String, area: String, extra := "") -> void:
	var arena := CosmeticLibrary.get_arena(area)
	var name_ := str(arena.display_name) if arena != null else area.to_upper()
	var extras: Array = []
	if arena != null and arena.model_path != "":
		extras.push_back(arena.model_path)
	var mode := str(AREA_MODES["practice"].get(area, "practice"))
	var hoop := hoop_for_mode(mode)
	if hoop != null and hoop.model_path != "":
		extras.push_back(hoop.model_path)
	if ball_set != null and ball_set.model_path != "":
		extras.push_back(ball_set.model_path)
	var art := "res://assets/ui/areas/area_%s_tall.png" % area if arena != null else ""
	if loader == null:
		get_tree().change_scene_to_file(path)
		return
	loader.go(path, LoadingCopy.dest(kind, name_, extra), art, extras)


## The home's area (the card the home opens on).
func home_area() -> String:
	var areas: Array = AreaArchiveCopy.AREAS
	return str(areas[clampi(home_card, 0, areas.size() - 1)]["area"])


## Home. `kind`: "home" (from a page), "continue" (the splash), "new" (a new player).
func to_title(kind := "home") -> void:
	get_tree().paused = false
	cancel_online()   # leaving a post-match page closes the room
	_move(TITLE_SCENE, kind, home_area())


## The splash (docs/HOME.md → Splash): the first screen, and where the area
## archive's back leads.
func to_splash() -> void:
	get_tree().paused = false
	_move(SPLASH_SCENE, "splash", "")


## Anything played yet? The splash reads CONTINUE over a save, NEW GAME on
## a fresh install.
func has_save() -> bool:
	return xp() > 0 or not SaveService.top_scores(1).is_empty() or not visited_areas().is_empty()


# ---- the new player (design "New Game Flow" 35a, 2026-10-17; docs/HOME.md) -------------


## Has this install been through NEW PLAYER (or does it predate it)? The
## splash shows NEW GAME until then, and registration waits for it so the
## chosen name goes up in the register call itself.
func player_created() -> bool:
	if qa_fresh:
		return false
	return bool(SaveService.get_settings().get("playerCreated", false)) or has_save()


## The player's hometown (a synced setting; shown on the NEW PLAYER card and
## editable in Settings → PLAYER).
func hometown() -> String:
	return str(SaveService.get_settings().get("hometown", ""))


func set_hometown(town: String) -> void:
	var s := SaveService.get_settings()
	s["hometown"] = town
	SaveService.put_settings(s)


## LET'S PLAY: the name and tag onto the account (unregistered: the register
## call carries them; registered: a rename), the hometown and the created
## flag into the settings, then straight onto the Arcade Cage campaign home
## with a welcome toast.
func create_player(name: String, tag: String, town: String, go := true) -> void:
	var a := Net.account()
	if not a.has("playerId"):
		a = {"playerId": SaveService.uuid4(), "secret": Net._new_secret(), "name": name, "tag": tag, "registered": false}
	else:
		a["name"] = name
		if not bool(a.get("registered", false)):
			a["tag"] = tag
	SaveService.put_account(a)
	set_hometown(town)
	var s := SaveService.get_settings()
	s["playerCreated"] = true
	SaveService.put_settings(s)
	qa_fresh = false
	pending_welcome = {"name": name, "tag": str(a.get("tag", tag)), "town": town}
	home_card = 0
	show_archive = false
	home_open_league = ""   # the cards, not the open league: the walkthrough points at them
	enter_league("cage")
	pending_walkthrough = "home"
	if bool(a.get("registered", false)):
		Net.rename(name)
	else:
		Net.ensure_account()
	if go:
		to_title("new")


func start_mode(id: String) -> void:
	next_mode = id if MODES.has(id) else "trial"
	if mode_config(next_mode).get("heat", false):
		if next_heat.is_empty() or next_heat.get("mode", "") != next_mode:
			next_heat = quick_heat_config(next_mode)
		_move(HEAT_SCENE, "heat", str(mode_config(next_mode).get("location", "cage")), _heat_line(next_heat))
		return
	var cfg := mode_config(next_mode)
	var endless := bool(cfg.get("endless", false))
	_move(TIME_TRIAL_SCENE, "practice" if endless else "trial", str(cfg.get("location", "cage")),
		"PRACTICE · NO CLOCK" if endless else "TIME TRIAL · %d S" % int(TimeTrial.TIME_TRIAL_SECONDS))


## A match's line on the loading screen: `LEAGUE · SEASON 2 · DAY 4 · VS OLLIE`.
func _heat_line(cfg: Dictionary) -> String:
	var parts := PackedStringArray()
	var league = cfg.get("league")
	if league is Dictionary and not (league as Dictionary).is_empty():
		parts.append("LEAGUE")
		var lid := str(league.get("id", ""))
		var kick := HeatCopy.kicker({"league": league}, league_doc(lid) if lid != "" else {})
		if kick != "":
			parts.append(kick)
	var opp = cfg.get("opponent")
	var first := str((opp as Dictionary).get("name", "")).get_slice(" ", 0).to_upper() if opp is Dictionary else ""
	if first != "":
		parts.append("VS %s" % first)
	return " · ".join(parts)


## TEST-ONLY. Quick heats left the game (2026-09-25): heats are league games.
## This one-off against the stand-in opponent stays for the QA driver and
## tests (start_mode("heat") without a league). No cards outside leagues, no
## rewards.
func quick_heat_config(mode_id: String) -> Dictionary:
	var cfg := mode_config(mode_id)
	return {
		"mode": mode_id, "seconds": Heat.DEFAULT_SECONDS, "ot_seconds": Heat.DEFAULT_OT_SECONDS,
		"ball_return_s": Heat.DEFAULT_BALL_RETURN_S, "ai": AiDifficulty.apply(QUICK_OPPONENT["ratings"], ai_difficulty), "err_mult": 1.0,
		"seed": int(Time.get_ticks_usec() % 2147483647), "opponent": QUICK_OPPONENT,
		"calib_key": cfg.get("calib_key", "regulation"), "league": null,
		"player_cards": [], "player_slots": [null, null, null], "ai_cards": [],
	}


## Play a configured heat (a league game or a rematch).
func start_heat(mode_id: String, cfg: Dictionary) -> void:
	next_heat = cfg.duplicate(true)
	next_heat["mode"] = mode_id
	next_mode = mode_id
	_move(HEAT_SCENE, "heat", str(mode_config(mode_id).get("location", "cage")), _heat_line(next_heat))


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
	last_heat["online"] = bool(next_heat.get("remote", false))
	if last_heat["online"]:
		last_heat["their_level"] = int(next_heat.get("their_level", 1))
		last_heat["ranked"] = bool(next_heat.get("ranked", false))
		_merge_online_settle()
	if last_heat["league"] != null:
		_apply_league_heat(last_heat)
		Net.push_save()
	return last_heat


func to_heat_result() -> void:
	_move(HEAT_RESULT_SCENE, "postmatch", str(last_heat.get("location", "cage")))


func finish_heat(result: Dictionary) -> void:
	settle_heat(result)
	to_heat_result()


# ---- power-up cards: one bucket per league --------------------------------------
# docs/ECONOMY.md. Every call takes the league (default: the one being played,
# App.current_league). Cards are bought with the global tickets, and the cards
# bought or dropped in a league stay there.


func _league_for(league := "") -> String:
	if league != "":
		return league
	return current_league if current_league != "" else "cage"


## The whole cards doc (every league's bucket).
func cards_doc() -> Dictionary:
	return SaveService.get_cards()


## A copy of one league's bucket {inventory, loadout}.
func cards_bucket(league := "") -> Dictionary:
	return CardDefs.league_doc(cards_doc(), _league_for(league)).duplicate(true)


func card_count(id: String, league := "") -> int:
	return CardDefs.count(cards_bucket(league), id)


func add_card(id: String, n := 1, league := "") -> void:
	var d := cards_doc()
	CardDefs.add(CardDefs.league_doc(d, _league_for(league)), id, n)
	SaveService.put_cards(d)


## A card waits for its level (Ross, 2026-10-14; docs/PROGRESSION.md): it
## cannot be equipped or bought below it — a drop can still hand you one
## early. The same rule everywhere: the league hub, the online deck, the
## server's shop and dealt hand.
func can_equip(id: String) -> bool:
	var card := CardDefs.get_card(id)
	return not card.is_empty() and Progression.can_use(level(), card)


func equip_card(slot: int, id: String, league := "") -> bool:
	if not can_equip(id):
		return false
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


## Buy a card for a league with tickets; it goes into that league's bucket.
## False if unknown, level-locked or unaffordable. Online cards are never
## bought (docs/ECONOMY.md → The rule): the online bucket refuses.
func try_buy_card(id: String, league := "") -> bool:
	var card := CardDefs.get_card(id)
	if card.is_empty() or _league_for(league) == Net.ONLINE_BUCKET or not can_equip(id):
		return false
	var price := int(card.get("price", 0))
	if not spend_tickets(price):
		return false
	var d := cards_doc()
	var b := CardDefs.league_doc(d, _league_for(league))
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
	_move(CREDITS_SCENE, "credits", "")


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
		"ai": AiDifficulty.apply(shooter.get("ratings", {}), ai_difficulty), "err_mult": float(cfg.get("err_mult", 1.0)),
		"seed": QuickSim.seed_from([season["seed"], season["year"], tag, int(doc["career"]["totals"]["games"])]),
		"opponent": shooter, "calib_key": cfg.get("calib_key", "regulation"),
		"league": {"id": cfg["id"], "game": tag, "playoff": season["phase"] == Season.PHASE_PLAYOFFS},
		"player_cards": loadout_hand(cfg["id"]), "player_slots": loadout_slots(cfg["id"]),
		# The opponent's season hand (its fixed allowance, less what it has
		# already played on you), not a fresh authored list every meeting.
		"ai_cards": Season.card_hand(season, opp_id),
		"player_bot": qa_player_bot,
	}


## The opponent's season hand for the pre-match page's THEIR LOADOUT (the
## same hand league_heat_config deals; the season remembers it).
func _ai_hand_for(season: Dictionary, cfg: Dictionary, opp_id: String) -> Array:
	if season.is_empty():
		return []
	Season.ensure_card_hands(season, cfg)
	var out := []
	for id in Season.card_hand(season, opp_id):
		if str(id) != "":
			out.push_back(str(id))
	return out


## PLAY HEAT from the dashboard: the pre-match pick first (docs/CARDS.md §
## Drops, 2026-10-19 — the same page as online: this league's cards, only
## those at or under your level, a short clock falling back to the last
## loadout), then play_league_heat. A scene without the page plays at once.
func start_league_heat() -> void:
	var cfg := league_cfg()
	var doc := league_doc()
	if league_heat_config(doc, cfg).is_empty():
		return
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("open_league_pre_match"):
		scene.call("open_league_pre_match", league_pre_match_info(doc, cfg))
	else:
		play_league_heat()


## What the pre-match page shows before a league heat: the next opponent as
## the "peer" (its name, the league as its place, its record as its line),
## the cap at your level, the league's bucket, the short clock.
func league_pre_match_info(doc: Dictionary, cfg: Dictionary) -> Dictionary:
	var opp_id := Campaign.next_opponent(doc)
	var shooter := LeagueData.shooter(opp_id)
	var season: Dictionary = doc.get("season", {})
	var rows := Standings.compute(LeagueData.team_ids(cfg), season.get("schedule", []) if season.get("schedule") is Array else [])
	var row: Dictionary = rows.get(opp_id, {"w": 0, "l": 0})
	var rec := [int(row.get("w", 0)), int(row.get("l", 0))]
	var mine: Dictionary = rows.get(LeagueData.PLAYER_ID, {"w": 0, "l": 0})
	# The stats on the cards (design "Pre Match" 37a: RECORD · SEED · AVG PTS) from the table.
	var table := Standings.table(LeagueData.team_ids(cfg), season.get("schedule", []) if season.get("schedule") is Array else [], int(season.get("seed", 0)))
	var opp_row := {}
	var my_row := {}
	for r in table:
		if str(r.get("teamId", "")) == opp_id:
			opp_row = r
		elif str(r.get("teamId", "")) == LeagueData.PLAYER_ID:
			my_row = r
	return {
		"peer": {"id": opp_id, "name": str(shooter.get("name", "THEM")), "tag": "%02d" % int(shooter.get("number", 0)),
			"town": str(shooter.get("hometown", shooter.get("town", ""))).to_upper(),
			"place_text": "%s · %s" % [str(cfg.get("name", "LEAGUE")).to_upper(), str(shooter.get("nickname", "")).to_upper()],
			"online_text": "%d-%d THIS SEASON" % [int(rec[0]), int(rec[1])]},
		"you": {"online_text": "%d-%d THIS SEASON" % [int(mine.get("w", 0)), int(mine.get("l", 0))]},
		"league_stats": {"opp": MatchCopy.league_stats(opp_row), "you": MatchCopy.league_stats(my_row)},
		"cap": level(), "seconds": float(CardDefs.prematch_seconds("league")), "bucket": str(cfg["id"]),
		"countdown_s": float(RankedRules.prematch_cfg().get("countdown_s", 10)),
		"ai_hand": _ai_hand_for(season, cfg, opp_id),
		"side": "a", "league": true,
	}


## The heat itself, with the loadout as picked.
func play_league_heat() -> void:
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
	# Payout (docs/ECONOMY.md): tickets, the one wallet.
	var title: bool = doc["season"].get("championId", "") == Campaign.PLAYER and doc["season"]["phase"] == Season.PHASE_DONE
	var pay := Economy.heat_rewards(cfg, bool(result.get("won", false)), title)
	grant_tickets(int(pay["tickets"]))
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
	# A level that opens an area queues the Area Unlock page (docs/HOME.md →
	# Area unlock); the heat screen shows it after the match-end page.
	if int(xp_info["level_after"]) > int(xp_info["level_before"]):
		Net.report_level(int(xp_info["level_after"]))   # the online card cap follows the level
	var opened := AreaUnlockCopy.crossed(int(xp_info["level_before"]), int(xp_info["level_after"]))
	if opened != "" and not unlock_seen(opened):
		pending_unlock = opened
	# Card drop (docs/CARDS.md § Drops): seeded by the campaign so a replayed
	# season rolls the same; it lands in this league's inventory. The loss
	# streak lives on the league doc for the same reason.
	var league: Dictionary = result.get("league", {})
	var won := bool(result.get("won", false))
	var streak := CardRewards.next_loss_streak(int(doc.get("lossStreak", 0)), won)
	doc["lossStreak"] = streak
	save_league_doc(doc)
	var half: Dictionary = result.get("half", {}) if result.get("half") is Dictionary else {}
	var ctx := {
		"won": won, "playoff": bool(league.get("playoff", false)), "level": int(xp_info["level_before"]),
		"difficulty": ai_difficulty, "margin": int(result.get("player_score", 0)) - int(result.get("ai_score", 0)),
		"ot": int(result.get("ot", 0)), "trailing_at_half": not half.is_empty() and int(half.get("player", 0)) < int(half.get("ai", 0)),
		"loss_streak": streak,
	}
	var drop := CardRewards.roll(ctx, QuickSim.seed_from([doc["season"]["seed"], "drop", int(doc["career"]["totals"]["games"])]))
	if str(drop["id"]) != "":
		add_card(str(drop["id"]), 1, cfg["id"])
	last_heat["card_drop"] = str(drop["id"])
	last_heat["drop_reason"] = str(drop["reason"])
	last_heat["bright"] = BrightSpots.note(doc, result)
	save_league_doc(doc)


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
	var shoot := take_shoot_bonus()
	if shoot > 0:
		earned += shoot
		last_run["shoot_bonus"] = shoot   # (`bonus` is the run's streak points)
	grant_tickets(earned)
	last_run["tickets"] = earned
	# The global board (docs/BACKEND.md): queued in the outbox, sent when the
	# net allows — the results page never waits on it.
	Net.queue_run(last_run)
	Net.push_save()
	_move(RESULTS_SCENE, "results", str(last_run.get("location", "cage")))
