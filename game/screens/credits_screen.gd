extends Control
## Credits (design "Credits" 40a, 2026-10-25): attributions for the
## third-party sounds, fonts and models (data/credits.json), reached from
## settings. A full page in the locker / settings style over the arcade
## cage's art under a scrim: the `<` back and the dithered CREDITS, BUILT
## WITH and the tools as gold chips, SOUNDS / FONTS / MODELS as tabs with
## their counts, then one see-through card per credit: what it is used for
## in gold, the title, BY the author with the licence as a chip (teal for an
## open licence, cream for "see the source page"), and the source link, so
## each author's attribution is all there. The list scrolls; a fade at its
## foot hides once the end is in view. The page lays out against the real
## screen (an anchored layer), its head under the top safe area.

const PATH := "res://data/credits.json"
const SECTIONS := ["sounds", "fonts", "models"]
const TOOLS := ["GODOT", "BLENDER", "ASEPRITE"]
const ART := "res://assets/ui/areas/area_cage_tall.png"
const SCRIM := Color(20.0 / 255.0, 16.0 / 255.0, 14.0 / 255.0, 0.62)
const CREAM := RetroTheme.SCENE_TEXT
const GOLD := Color("#F0B84A")
const TEAL := Color("#3F8C7A")
const URL_C := Color("#C9BFA6")
const CHIP_BG := Color(34.0 / 255.0, 28.0 / 255.0, 24.0 / 255.0, 0.55)
const FADE_C := Color(27.0 / 255.0, 22.0 / 255.0, 19.0 / 255.0, 0.95)
## The design's rows, measured from the head's top (44 at 1280).
const LEFT := 36.0
const RIGHT := 42.0
const HEAD_Y := 44.0
const TOOLS_DY := 106.0
const TABS_DY := 178.0
const LIST_DY := 274.0
const BOTTOM := 40.0
const BACK_PX := 72.0
const TAB_H := 68.0
const FADE_H := 120.0

var _tab := "sounds"
var _tabs: Dictionary = {}
var _scroll: ScrollContainer
var _list: VBoxContainer
var _fade: TextureRect


static func load_credits() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {"sounds": []}
	var f := FileAccess.open(PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {"sounds": []}


## Problems with the credits file (empty = fine).
static func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	var doc := load_credits()
	for section in SECTIONS:
		for c in doc.get(section, []):
			for key in ["title", "author", "url", "license"]:
				if str(c.get(key, "")) == "":
					problems.push_back("credit %s missing %s" % [c.get("title", "?"), key])
	return problems


## The one-line attribution an author asks for.
static func attribution_line(c: Dictionary) -> String:
	return "%s by %s -- %s -- License: %s" % [c.get("title", ""), c.get("author", ""), c.get("url", ""), c.get("license", "")]


## An open licence (CC, OFL…) wears the teal chip; "see the source page" the cream one.
static func licence_open(licence: String) -> bool:
	return not licence.to_lower().contains("see the")


## A section's cards as the page shows them: {used, title, author, licence, url, open}
## (the title and the link as written; the rest in capitals).
static func rows(doc: Dictionary, section: String) -> Array:
	var out := []
	for c in doc.get(section, []):
		var lic := str(c.get("license", ""))
		out.push_back({
			"used": str(c.get("used_for", "")).to_upper(),
			"title": str(c.get("title", "")),
			"author": "BY " + str(c.get("author", "")).to_upper(),
			"licence": lic.to_upper(),
			"url": str(c.get("url", "")),
			"open": licence_open(lic),
		})
	return out


func _ready() -> void:
	Sfx.start_music(App.TITLE_MUSIC["id"], App.TITLE_MUSIC["clip"], App.TITLE_MUSIC["gain_db"])
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layer := CanvasLayer.new()
	layer.name = "Page"
	UiLayout.anchor_layer(layer)
	add_child(layer)
	var root := Control.new()
	root.name = "Root"
	UiLayout.screen_fill(root)
	layer.add_child(root)
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = Color("#1B1815")
	UiLayout.full_rect(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	if ResourceLoader.exists(ART):
		var art := TextureRect.new()
		art.name = "Art"
		art.texture = load(ART)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		UiLayout.full_rect(art)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(art)
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = SCRIM
	UiLayout.full_rect(scrim)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(scrim)
	var top := UiLayout.header_top(HEAD_Y)
	var w := 720.0 - LEFT - RIGHT
	# < CREDITS
	var head := HBoxContainer.new()
	head.name = "Head"
	head.position = Vector2(LEFT, top)
	head.size = Vector2(w, BACK_PX + ShadowStyle.OFFSET)
	head.add_theme_constant_override("separation", 24)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(head)
	var back := HomePage.button("<", CREAM, 32, BACK_PX)
	back.name = "Back"
	back.custom_minimum_size.x = BACK_PX + ShadowStyle.OFFSET
	back.pressed.connect(func() -> void: App.leave_credits())
	head.add_child(back)
	var title := RetroTheme.display("CREDITS", 37, CREAM)
	title.name = "Title"
	RetroTheme.on_scene(title)
	RetroTheme.dithered(title)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_vertical = Control.SIZE_FILL
	head.add_child(title)
	# BUILT WITH [GODOT] [BLENDER] [ASEPRITE]
	var tools := HBoxContainer.new()
	tools.name = "Tools"
	tools.position = Vector2(LEFT, top + TOOLS_DY)
	tools.size = Vector2(w, 40 + ShadowStyle.OFFSET)
	tools.add_theme_constant_override("separation", 14)
	tools.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tools)
	var built := _words("BUILT WITH", 18)
	built.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	built.size_flags_vertical = Control.SIZE_FILL
	tools.add_child(built)
	for n in TOOLS:
		var chip := ShadowPanel.new(GOLD, 0.0, 0.35, 12.0)
		chip.name = "Tool" + str(n).capitalize()
		chip.custom_minimum_size = Vector2(0, 40 + ShadowStyle.OFFSET)
		var l := _display(str(n), 16)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(l)
		tools.add_child(chip)
	# SOUNDS 15 · FONTS 3 · MODELS 3
	var doc := load_credits()
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.position = Vector2(LEFT, top + TABS_DY)
	tabs.size = Vector2(w + ShadowStyle.OFFSET, TAB_H + ShadowStyle.OFFSET)
	tabs.add_theme_constant_override("separation", 18)
	tabs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tabs)
	for s in SECTIONS:
		var b := ShadowCard.new(CREAM)
		b.name = "Tab" + str(s).capitalize()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, TAB_H + ShadowStyle.OFFSET)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		UiLayout.full_rect(row)   # inside a Control: no bleed, the offsets below hold
		row.offset_right = -ShadowStyle.OFFSET
		row.offset_bottom = -ShadowStyle.OFFSET
		var name_l := _display(str(s).to_upper(), 18)
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_l.size_flags_vertical = Control.SIZE_FILL
		row.add_child(name_l)
		var count := _words(str((doc.get(s, []) as Array).size()), 17)
		count.name = "Count"
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count.size_flags_vertical = Control.SIZE_FILL
		row.add_child(count)
		b.pressed.connect(show_tab.bind(s))
		tabs.add_child(b)
		_tabs[s] = b
	# The cards.
	var list_top := top + LIST_DY
	var list_h := UiLayout.screen_height() - BOTTOM - list_top
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.position = Vector2(LEFT, list_top)
	_scroll.size = Vector2(720.0 - LEFT - 30.0, list_h)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	root.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.name = "List"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 22)
	_scroll.add_child(_list)
	_scroll.get_v_scroll_bar().value_changed.connect(func(_v: float) -> void: _check_end())
	_scroll.get_v_scroll_bar().changed.connect(_check_end)
	# The fade at the list's foot (gone at the end).
	var grad := Gradient.new()
	grad.set_color(0, Color(FADE_C, 0.0))
	grad.set_color(1, FADE_C)
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	_fade = TextureRect.new()
	_fade.name = "Fade"
	_fade.texture = gt
	_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fade.stretch_mode = TextureRect.STRETCH_SCALE
	_fade.position = Vector2(LEFT, list_top + list_h - FADE_H)
	_fade.size = Vector2(w, FADE_H)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	show_tab("sounds")


## Show a section: the tab turns gold, the cards refill, the list goes back to the top.
func show_tab(section: String) -> void:
	_tab = section
	for s in _tabs:
		var b: ShadowCard = _tabs[s]
		b.color = GOLD if s == section else CREAM
		b.queue_redraw()
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for r in rows(load_credits(), section):
		_list.add_child(_card(r))
	_scroll.scroll_vertical = 0
	_check_end.call_deferred()


func tab() -> String:
	return _tab


func card_count() -> int:
	return _list.get_child_count() if _list != null else 0


## Whether the fade at the foot shows (more below).
func fade_shown() -> bool:
	return _fade != null and _fade.visible


func _check_end() -> void:
	if _scroll == null or _fade == null:
		return
	var bar := _scroll.get_v_scroll_bar()
	_fade.visible = bar.value + bar.page < bar.max_value - 4.0


func _card(r: Dictionary) -> Control:
	var p := ShadowPanel.new(CREAM, 20.0, 0.24, 22.0)
	p.name = "Credit"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(col)
	var used := _words(str(r["used"]), 17, GOLD)
	used.name = "Used"
	used.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(used)
	var title := _display(str(r["title"]), 21)
	title.name = "CreditTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	title.add_theme_constant_override("line_spacing", 7)
	col.add_child(title)
	var by := HFlowContainer.new()
	by.add_theme_constant_override("h_separation", 14)
	by.add_theme_constant_override("v_separation", 10)
	by.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(by)
	var author := _words(str(r["author"]), 20)
	author.name = "Author"
	author.custom_minimum_size.y = 30
	author.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	by.add_child(author)
	var chip := PanelContainer.new()
	chip.name = "Licence"
	var sb := StyleBoxFlat.new()
	sb.bg_color = CHIP_BG
	sb.border_color = TEAL if bool(r["open"]) else CREAM
	sb.set_border_width_all(2)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	chip.add_theme_stylebox_override("panel", sb)
	chip.custom_minimum_size = Vector2(0, 30)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lic := _words(str(r["licence"]), 15)
	lic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A chip hugs its words; one too long for the card's width wraps across it.
	var font := lic.get_theme_font("font")
	var fs := lic.get_theme_font_size("font_size")
	var room := 720.0 - LEFT - 30.0 - 44.0 - 2.0 * ShadowStyle.OFFSET - 20.0
	if font != null and font.get_string_size(lic.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		lic.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lic.custom_minimum_size.x = room
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
	chip.add_child(lic)
	by.add_child(chip)
	var url := UiFont.label(str(r["url"]), 16, URL_C, UiFont.body())
	url.name = "Url"
	RetroTheme.on_scene(url)
	url.add_theme_color_override("font_color", URL_C)
	url.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	url.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(url)
	return p


## Bold body words, cream outlined (or `color`).
func _words(text: String, size_: int, color := CREAM) -> Label:
	var l := RetroTheme.caps(text, size_, color)
	RetroTheme.on_scene(l)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _display(text: String, size_: int) -> Label:
	var l := RetroTheme.display(text, size_, CREAM)
	RetroTheme.on_scene(l)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
