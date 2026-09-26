class_name ModeCards
extends RefCounted
## The home screen's mode cards: ShadowCards (see-through, the card's colour
## as a hard offset shadow) with their own label stack in cream + ink outline
## (title left, small-caps sub-line): the full-width orange LEAGUE card with
## a ">" and the league status line, and the gold TIME TRIAL / teal PRACTICE
## pair. `league_line` is the pure
## status text (tested on its own).


## A card: title (display), sub-line (small caps), optional chevron.
static func card(title: String, sub: String, fill: Color, title_size := 24, chevron := false) -> Button:
	var b := ShadowCard.new(fill)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22 + int(ShadowCard.OFFSET))
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18 + int(ShadowCard.OFFSET))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var col := VBoxContainer.new()
	col.name = "Text"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var t := RetroTheme.on_scene(UiFont.label(title, title_size, RetroTheme.SCENE_TEXT))
	t.name = "Title"
	col.add_child(t)
	var s := RetroTheme.on_scene(UiFont.label(sub, 16, RetroTheme.SCENE_TEXT, UiFont.body_bold()))
	s.name = "Sub"
	s.visible = sub != ""
	col.add_child(s)
	if chevron:
		var ch := RetroTheme.on_scene(UiFont.label(">", 24, RetroTheme.SCENE_TEXT))
		ch.name = "Chevron"
		ch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(ch)
	return b


static func league_card(state: Dictionary) -> Button:
	var b := card("LEAGUE", league_line(state), RetroTheme.c("orange"), 32, true)
	b.name = "LeagueCard"
	b.custom_minimum_size = Vector2(0, 128)
	if not state.is_empty() and not bool(state.get("unlocked", true)):
		b.disabled = true
	return b


static func trial_card(best: int) -> Button:
	var b := card("TIME\nTRIAL", ("BEST %d" % best) if best > 0 else "NO RUNS YET", RetroTheme.c("gold"), 24)
	b.name = "TrialCard"
	b.custom_minimum_size = Vector2(0, 152)
	return b


static func practice_card() -> Button:
	var b := card("PRACTICE", "NO CLOCK", RetroTheme.c("teal"), 24)
	b.name = "PracticeCard"
	b.custom_minimum_size = Vector2(0, 152)
	return b


static func sub_text(b: Button) -> String:
	var s: Label = b.find_child("Sub", true, false)
	return s.text if s != null else ""


## The league card's status line from an App.league_states() row
## ({league, unlocked, doc}): the season, where you are in it, your place.
static func league_line(state: Dictionary) -> String:
	if state.is_empty():
		return "NEW LEAGUE"
	var cfg: Dictionary = state.get("league", {})
	if not bool(state.get("unlocked", true)):
		var rule: Dictionary = cfg.get("unlock", {})
		var parent := LeagueData.league(str(rule.get("league", "")))
		return "LOCKED · TOP %d IN THE %s" % [int(rule.get("min_finish", 4)), str(parent.get("name", "LEAGUE")).to_upper()]
	var doc: Dictionary = state.get("doc", {})
	if doc.is_empty():
		return "NEW LEAGUE"
	var season: Dictionary = doc["season"]
	var year := int(doc.get("year", season.get("year", 1)))
	var head := "SEASON %d" % year
	match str(season["phase"]):
		Season.PHASE_REGULAR:
			var day := int(season["currentDay"])
			var place := _place(cfg, season)
			if day <= 1 and place == 0:
				return "%s · DAY 1 · TIP OFF" % head
			return "%s · DAY %d · %s PLACE" % [head, day, TickerText.ordinal(place)] if place > 0 else "%s · DAY %d" % [head, day]
		Season.PHASE_PLAYOFFS:
			var mine := Season.player_series(season, Campaign.PLAYER)
			if mine.is_empty():
				return "%s · PLAYOFFS · OUT" % head
			var high: bool = mine["highSeedId"] == Campaign.PLAYER
			var w := int(mine["highWins"] if high else mine["lowWins"])
			var l := int(mine["lowWins"] if high else mine["highWins"])
			return "%s · %s %d-%d" % [head, "FINAL" if str(mine.get("round", "")) == "final" else "SEMIS", w, l]
		_:
			if str(season.get("championId", "")) == Campaign.PLAYER:
				return "%s · CHAMPIONS" % head
			var summary := Campaign.season_summary(doc, cfg)
			return "%s · DONE · %s PLACE" % [head, TickerText.ordinal(int(summary["finish"]))]


## The player's standings seed (0 before any game).
static func _place(cfg: Dictionary, season: Dictionary) -> int:
	var played := false
	for g in season.get("schedule", []):
		if g.get("played", false):
			played = true
			break
	if not played:
		return 0
	for row in Standings.table(LeagueData.team_ids(cfg), season["schedule"], int(season["seed"])):
		if row["teamId"] == Campaign.PLAYER:
			return int(row["seed"])
	return 0
