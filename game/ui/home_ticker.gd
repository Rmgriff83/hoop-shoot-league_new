class_name HomeTicker
extends PanelContainer
## The home screen's ticker strip: a flat framed band clipping one label that
## scrolls left and wraps seamlessly (the copy is laid twice around a ★
## seam). `items_from` builds the copy from the save — bests per area, the
## league standing and next opponent, the coin balance — in the body face,
## so every glyph is one the font has (tested).

const SPEED := 80.0   # px/s
const SEP := "  ·  "
const SEAM := "  ★  "
const HEIGHT := 48.0

var _label: Label
var _clip: Control
var _half := 0.0
var _x := 0.0


func _init() -> void:
	name = "Ticker"
	custom_minimum_size = Vector2(0, HEIGHT)
	add_theme_stylebox_override("panel", RetroTheme.flat(RetroTheme.c("panel"), 0, 0.0))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip = Control.new()
	_clip.name = "Clip"
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	_label = UiFont.label("", 16, RetroTheme.c("text"), UiFont.display())
	_label.name = "Text"
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.custom_minimum_size = Vector2(0, HEIGHT - 2 * RetroTheme.BORDER)
	_clip.add_child(_label)


func set_items(items: PackedStringArray) -> void:
	var line := SEP.join(items) if not items.is_empty() else "HOOP SHOOT"
	var font := UiFont.display()
	var fs := UiFont.snap(16)
	_half = font.get_string_size(line + SEAM, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	_label.text = line + SEAM + line + SEAM
	_label.size = Vector2(_half * 2.0, HEIGHT - 2 * RetroTheme.BORDER)
	_x = 0.0
	_label.position = Vector2(0, 0)


func text() -> String:
	return _label.text


func _process(dt: float) -> void:
	if _half <= 0.0:
		return
	_x -= SPEED * dt
	if _x <= -_half:
		_x += _half
	_label.position.x = floorf(_x)


## The copy, from data: bests = [{name, best}], states = App.league_states()
## rows, coins, and the next opponent's name (or "").
static func items_from(bests: Array, states: Array, coins: int, next_up := "") -> PackedStringArray:
	var out := PackedStringArray()
	for b in bests:
		if int(b.get("best", 0)) > 0:
			out.push_back("%s BEST %d" % [str(b.get("name", "")).to_upper(), int(b["best"])])
	for st in states:
		var doc: Dictionary = st.get("doc", {})
		if doc.is_empty() or not bool(st.get("unlocked", true)):
			continue
		var line := ModeCards.league_line(st)
		out.push_back("%s · %s" % [str(st["league"]["name"]).to_upper(), line])
	if next_up != "":
		out.push_back("NEXT UP: %s" % next_up.to_upper())
	out.push_back("%s COINS" % RetroTheme.thousands(coins))
	if out.size() < 3:
		out.push_back("SWISH FOR 2")
		out.push_back("KEEP THE STREAK ALIVE")
	return out
