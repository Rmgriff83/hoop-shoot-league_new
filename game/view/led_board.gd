class_name LedBoard
extends Node
## The hoop's LED displays, drawn live:
##  • Scoreboard: a 48×8 matrix of round LEDs (192×32 texels, 4 per LED) with a
##    3×5 pixel font. Idle shows the score; events flash or marquee text, queued
##    so they don't clobber each other, then it returns to the score.
##  • Light band: the strip around the backboard frame (NBA buzzer light). A
##    white segment texture tinted by the material colour: off, flashing, solid.
## Pure Image work + two StandardMaterial3Ds; advance(dt) drives the animation
## (called from _process) so it is testable headless.

const COLS := 48
const ROWS := 8
const CELL := 4
const WIDTH := COLS * CELL   # 192
const HEIGHT := ROWS * CELL  # 32
const GLYPH_W := 3
const GLYPH_H := 5
const TOP_MARGIN := 1

const BG := Color8(12, 10, 14)
const OFF := Color8(20, 4, 4)
const RED := Color8(255, 70, 30)
const AMBER := Color8(255, 180, 40)
const YELLOW := Color8(255, 200, 40)
const BAND_RED := Color8(255, 40, 30)
const BAND_OFF := Color8(40, 38, 44)

## 3×5 glyphs, rows top→bottom, '#' = lit.
const FONT := {
	"*": ["...", ".#.", "###", ".#.", "..."],
	"0": ["###", "#.#", "#.#", "#.#", "###"], "1": [".#.", "##.", ".#.", ".#.", "###"],
	"2": ["###", "..#", "###", "#..", "###"], "3": ["###", "..#", "###", "..#", "###"],
	"4": ["#.#", "#.#", "###", "..#", "..#"], "5": ["###", "#..", "###", "..#", "###"],
	"6": ["###", "#..", "###", "#.#", "###"], "7": ["###", "..#", ".#.", ".#.", ".#."],
	"8": ["###", "#.#", "###", "#.#", "###"], "9": ["###", "#.#", "###", "..#", "###"],
	"A": [".#.", "#.#", "###", "#.#", "#.#"], "B": ["##.", "#.#", "##.", "#.#", "##."],
	"C": ["###", "#..", "#..", "#..", "###"], "D": ["##.", "#.#", "#.#", "#.#", "##."],
	"E": ["###", "#..", "##.", "#..", "###"], "F": ["###", "#..", "##.", "#..", "#.."],
	"G": ["###", "#..", "#.#", "#.#", "###"], "H": ["#.#", "#.#", "###", "#.#", "#.#"],
	"I": ["###", ".#.", ".#.", ".#.", "###"], "J": ["..#", "..#", "..#", "#.#", "###"],
	"K": ["#.#", "#.#", "##.", "#.#", "#.#"], "L": ["#..", "#..", "#..", "#..", "###"],
	"M": ["#.#", "###", "###", "#.#", "#.#"], "N": ["##.", "#.#", "#.#", "#.#", "#.#"],
	"O": ["###", "#.#", "#.#", "#.#", "###"], "P": ["###", "#.#", "###", "#..", "#.."],
	"Q": ["###", "#.#", "#.#", "###", "..#"], "R": ["##.", "#.#", "##.", "#.#", "#.#"],
	"S": ["###", "#..", "###", "..#", "###"], "T": ["###", ".#.", ".#.", ".#.", ".#."],
	"U": ["#.#", "#.#", "#.#", "#.#", "###"], "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
	"W": ["#.#", "#.#", "###", "###", "#.#"], "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
	"Y": ["#.#", "#.#", ".#.", ".#.", ".#."], "Z": ["###", "..#", ".#.", "#..", "###"],
	" ": ["...", "...", "...", "...", "..."], "!": [".#.", ".#.", ".#.", "...", ".#."],
	":": ["...", ".#.", "...", ".#.", "..."], "+": ["...", ".#.", "###", ".#.", "..."],
	"-": ["...", "...", "###", "...", "..."], "x": ["...", "#.#", ".#.", "#.#", "..."],
}

## Scoreboard material (LedFace) and band material (BoardBand).
var material: StandardMaterial3D
var band_material: StandardMaterial3D

## Palette (a HoopSet can restyle it). Colours passed as Color.TRANSPARENT to
## the text APIs mean "the set's on colour".
var on_color: Color = RED
var accent_color: Color = AMBER
var band_flash_color: Color = YELLOW
var band_buzzer_color: Color = BAND_RED


func set_palette(set: HoopSet) -> void:
	on_color = set.led_color
	accent_color = set.led_accent
	band_flash_color = set.band_flash_color
	band_buzzer_color = set.band_buzzer_color
	_color = on_color
	_dirty = true


func _resolve(color: Color) -> Color:
	return on_color if color.a == 0.0 else color

var _img: Image
var _tex: ImageTexture
var _dirty := true

# Scoreboard state.
var _mode := "idle"          # idle | text | flash | marquee
var _idle_text := "SCORE 0"
var _text := ""
var _color := RED
var _flash_left := 0
var _flash_t := 0.0
var _flash_on := true
var _marquee_x := 0.0
var _marquee_speed := 20.0
var _queue: Array[Dictionary] = []
## Ribbon board: the rotating segment list and which one is sliding now.
var _ticker_items := PackedStringArray()
var _ticker_i := 0
var _ticker_paused := false

# Band state.
var _band_hz := 0.0
var _band_color := YELLOW
var _band_t := 0.0
var _band_solid_left := 0.0
var _band_solid_color := BAND_RED
var _band_lit := false

const FLASH_PERIOD := 0.25


func _init() -> void:
	_img = Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(_img)
	material = StandardMaterial3D.new()
	material.albedo_texture = _tex
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission_texture = _tex
	material.emission_energy_multiplier = 0.6
	band_material = StandardMaterial3D.new()
	band_material.albedo_texture = load("res://assets/textures/hoop_band.png")
	band_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	band_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	band_material.emission_enabled = true
	band_material.emission_energy_multiplier = 0.8
	_set_band_color(BAND_OFF, false)
	_render_frame()


func _process(dt: float) -> void:
	advance(dt)


# ---- scoreboard API ---------------------------------------------------------


## Idle display; replaces whatever the score line was. `mult` >= 2 tags the
## streak tier (SCORE 12 x2) — the lowercase x glyph fits 12 columns to 99.
func show_score(score: int, mult := 1) -> void:
	_idle_text = "SCORE %d" % score if mult < 2 else "SCORE %d x%d" % [score, mult]
	if _mode == "idle":
		_color = on_color
		_dirty = true


## Persistent text (READY, TIME) until the next call; interrupts animations.
func set_text(text: String, color := Color.TRANSPARENT) -> void:
	_queue.clear()
	_mode = "text"
	_text = text
	_color = _resolve(color)
	_dirty = true


## Blink text `times` times, then continue the queue / return to idle.
func flash(text: String, times := 2, color := Color.TRANSPARENT) -> void:
	_enqueue({"kind": "flash", "text": text, "times": times, "color": _resolve(color)})


## Scroll text right→left once (LED columns per second).
func marquee(text: String, cols_per_s := 20.0, color := Color.TRANSPARENT) -> void:
	_enqueue({"kind": "marquee", "text": text, "speed": cols_per_s, "color": _resolve(color)})


func mode() -> String:
	return _mode


## A ribbon board: scroll `items` right→left, one after another, forever.
##
## Distinct from marquee(), which plays ONCE and then pops the queue — a ribbon
## has to keep running. Items advance at the wrap, which is also the only moment
## new content is picked up, so a score that changes mid-slide does not make the
## text jump (see set_ticker_items).
func ticker(items: PackedStringArray, cols_per_s := 9.0, color := Color.TRANSPARENT) -> void:
	_queue.clear()
	_ticker_items = items
	_ticker_i = 0
	if items.is_empty():
		_mode = "idle"
		_dirty = true
		return
	_mode = "ticker"
	_color = _resolve(color)
	_marquee_speed = cols_per_s
	_text = items[0]
	_marquee_x = float(COLS)
	_dirty = true


## Swap the ticker's content WITHOUT restarting the slide in progress. The new
## list takes effect at the next wrap.
func set_ticker_items(items: PackedStringArray) -> void:
	_ticker_items = items
	if _mode != "ticker":
		return
	if items.is_empty():
		_mode = "idle"
		_dirty = true


func ticker_index() -> int:
	return _ticker_i


## Hold the ribbon still. Moving text below the rim competes with the shot, so
## the screen freezes it while a ball is live and lets it run between racks —
## it stops where it is rather than snapping back, so nothing jumps.
func set_ticker_paused(paused: bool) -> void:
	_ticker_paused = paused


func ticker_paused() -> bool:
	return _ticker_paused


func _enqueue(item: Dictionary) -> void:
	if _mode == "idle" or _mode == "text":
		_start(item)
	else:
		_queue.push_back(item)


func _start(item: Dictionary) -> void:
	_text = item["text"]
	_color = item["color"]
	if item["kind"] == "flash":
		_mode = "flash"
		_flash_left = int(item["times"]) * 2
		_flash_t = 0.0
		_flash_on = true
	else:
		_mode = "marquee"
		_marquee_speed = item["speed"]
		_marquee_x = float(COLS)
	_dirty = true


func _finish() -> void:
	if _queue.is_empty():
		_mode = "idle"
		_color = on_color
	else:
		_start(_queue.pop_front())
	_dirty = true


# ---- band API -----------------------------------------------------------------


## Blink schedule for the running clock: 0 Hz above 10 s, 1 Hz 10–5 s, 2 Hz under 5 s.
static func band_hz_for(time_left: float) -> float:
	if time_left > 10.0:
		return 0.0
	if time_left > 5.0:
		return 1.0
	return 2.0


func band_off() -> void:
	band_flash(YELLOW, 0.0)


## Flash the band at hz (0 = off). Idempotent per frame — safe to call every tick.
func band_flash(color: Color, hz: float) -> void:
	if hz != _band_hz or color != _band_color:
		_band_hz = hz
		_band_color = color
		if hz <= 0.0:
			_band_t = 0.0
			if _band_solid_left <= 0.0:
				_set_band_color(BAND_OFF, false)


## Solid colour for `seconds`, overriding the flash.
func band_solid(color: Color, seconds: float) -> void:
	_band_solid_color = color
	_band_solid_left = seconds
	_set_band_color(color, true)


func band_lit() -> bool:
	return _band_lit


func _set_band_color(color: Color, lit: bool) -> void:
	_band_lit = lit
	band_material.albedo_color = color
	band_material.emission = color if lit else Color.BLACK


# ---- animation ----------------------------------------------------------------


func advance(dt: float) -> void:
	# Scoreboard.
	match _mode:
		"flash":
			_flash_t += dt
			# A long frame (or a headless test) may span several toggles.
			while _mode == "flash" and _flash_t >= FLASH_PERIOD:
				_flash_t -= FLASH_PERIOD
				_flash_on = not _flash_on
				_flash_left -= 1
				_dirty = true
				if _flash_left <= 0:
					_finish()
		"marquee":
			var prev := int(floor(_marquee_x))
			_marquee_x -= _marquee_speed * dt
			if int(floor(_marquee_x)) != prev:
				_dirty = true
			if _marquee_x < -float(text_cols(_text)):
				_finish()
		"ticker":
			# NB: skip the scroll, do NOT return — the band tick lives below this
			# match and is shared by every board.
			var tprev := int(floor(_marquee_x))
			if not _ticker_paused:
				_marquee_x -= _marquee_speed * dt
			if int(floor(_marquee_x)) != tprev:
				_dirty = true
			if not _ticker_paused and _marquee_x < -float(text_cols(_text)):
				# Wrap: pick up the next item, and any list swapped in meanwhile.
				if _ticker_items.is_empty():
					_mode = "idle"
				else:
					_ticker_i = (_ticker_i + 1) % _ticker_items.size()
					_text = _ticker_items[_ticker_i]
					_marquee_x = float(COLS)
				_dirty = true
	# Band.
	if _band_solid_left > 0.0:
		_band_solid_left -= dt
		if _band_solid_left <= 0.0:
			_set_band_color(BAND_OFF, false)
			_band_t = 0.0
	elif _band_hz > 0.0:
		_band_t += dt
		var lit := fmod(_band_t * _band_hz, 1.0) < 0.5
		if lit != _band_lit:
			_set_band_color(_band_color if lit else BAND_OFF, lit)
	if _dirty:
		_render_frame()


static func text_cols(text: String) -> int:
	return maxi(0, text.length() * (GLYPH_W + 1) - 1)


## Count of lit LEDs in the current frame (for tests / debugging).
func lit_count() -> int:
	var n := 0
	for r in ROWS:
		for c in COLS:
			var px := _img.get_pixel(c * CELL + 1, r * CELL + 1)
			if px != OFF and px != BG:
				n += 1
	return n


func _render_frame() -> void:
	_dirty = false
	_img.fill(BG)
	for r in ROWS:
		for c in COLS:
			_led(c, r, OFF)
	var text := _idle_text
	var x0 := 0
	var draw := true
	match _mode:
		"idle":
			text = _idle_text
		"text":
			text = _text
		"flash":
			text = _text
			draw = _flash_on
		"marquee", "ticker":
			text = _text
			x0 = int(floor(_marquee_x))
	if draw:
		if _mode != "marquee" and _mode != "ticker":
			x0 = maxi(0, (COLS - text_cols(text)) / 2)   # centre static text
		_draw_text(text, x0, _color)
	_tex.update(_img)


func _draw_text(text: String, x0: int, color: Color) -> void:
	var cx := x0
	for ch in text:
		var key := ch if FONT.has(ch) else ch.to_upper()
		if FONT.has(key):
			var rows: Array = FONT[key]
			for gy in GLYPH_H:
				var row: String = rows[gy]
				for gx in GLYPH_W:
					if row[gx] == "#":
						_led(cx + gx, TOP_MARGIN + gy, color)
		cx += GLYPH_W + 1


func _led(col: int, row: int, color: Color) -> void:
	if col < 0 or col >= COLS or row < 0 or row >= ROWS:
		return
	var x := col * CELL
	var y := row * CELL
	for dy in 3:
		for dx in 3:
			_img.set_pixel(x + dx, y + dy, color)
