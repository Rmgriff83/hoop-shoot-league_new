class_name BoardPreview
extends Button
## The leaderboard on the home (design "Home League Context v2" 3a,
## 2026-10-17): the area's time-trial top five mid-court — rank, name,
## points in bold 22 cream with the ink outline — and, after a gap, YOUR row
## in the warm gold, right where the ranks icon's board used to live. A tap
## opens the full board (RanksPage). Slides off left and fades while the
## league is open (the title drives that from _apply_area).

const WIDTH := 440.0
const ROW_H := 30.0
const ROW_GAP := 22.0
const YOU_GAP := 10.0
const TOP := 5
const YOU := Color("#FFCE8A")
const CREAM := RetroTheme.SCENE_TEXT

var _col: VBoxContainer


func _init() -> void:
	name = "BoardPreview"
	flat = true
	focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	size = Vector2(WIDTH, 0)
	_col = VBoxContainer.new()
	_col.name = "Rows"
	_col.add_theme_constant_override("separation", int(ROW_GAP))
	_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_col.set_anchors_preset(Control.PRESET_TOP_WIDE)
	add_child(_col)


## Rows as RanksCopy makes them ({rank "#n", name, score, me}); the first
## TOP non-me rows, then the player's row (from `me` or the list) with its gap.
func set_rows(rows: Array, me: Dictionary = {}) -> void:
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	var shown := 0
	var you := {}
	for r in rows:
		if bool(r.get("me", false)) and you.is_empty():
			you = r
		if shown < TOP:
			_col.add_child(_row(str(r["rank"]).trim_prefix("#"), str(r["name"]), str(r["score"]), bool(r.get("me", false))))
			shown += 1
	if you.is_empty() and not me.is_empty():
		you = {"rank": "#%d" % int(me.get("rank", 0)), "name": "YOU", "score": str(int(me.get("score", 0))), "me": true}
	if shown == 0:
		var empty := RetroTheme.caps("TIME TRIAL · NO RUNS YET", 16, CREAM)
		empty.name = "Empty"
		RetroTheme.on_scene(empty)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_col.add_child(empty)
	if not you.is_empty() and shown >= TOP and int(str(you["rank"]).trim_prefix("#")) > TOP:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, YOU_GAP)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_col.add_child(gap)
		_col.add_child(_row(str(you["rank"]).trim_prefix("#"), "YOU", str(you["score"]), true))
	size.y = _col.get_combined_minimum_size().y
	custom_minimum_size = size


func row_count() -> int:
	var n := 0
	for c in _col.get_children():
		if c.name.begins_with("Row"):
			n += 1
	return n


func _row(rank: String, who: String, pts: String, mine: bool) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.name = "Row" + rank
	h.add_theme_constant_override("separation", 12)
	h.custom_minimum_size = Vector2(0, ROW_H)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := YOU if mine else CREAM
	var n := RetroTheme.caps(rank, 22, col)
	n.name = "Rank"
	n.custom_minimum_size = Vector2(56, 0)
	RetroTheme.on_scene(n)
	h.add_child(n)
	var w := RetroTheme.caps(who, 22, col)
	w.name = "Name"
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	RetroTheme.on_scene(w)
	h.add_child(w)
	var p := RetroTheme.display(pts, 20, col)
	p.name = "Pts"
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	RetroTheme.on_scene(p)
	h.add_child(p)
	for l in [n, w, p]:
		(l as Label).vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		(l as Label).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(l as Label).add_theme_color_override("font_color", col)
	return h
