extends Control
## Credits: attributions for third-party sounds, fonts and models (data/credits.json) — the
## plain text each author asks for, plus the tools. Reached from the title.

const PATH := "res://data/credits.json"


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
	for section in ["sounds", "fonts", "models"]:
		for c in doc.get(section, []):
			for key in ["title", "author", "url", "license"]:
				if str(c.get(key, "")) == "":
					problems.push_back("credit %s missing %s" % [c.get("title", "?"), key])
	return problems


## The one-line attribution an author asks for.
static func attribution_line(c: Dictionary) -> String:
	return "%s by %s -- %s -- License: %s" % [c.get("title", ""), c.get("author", ""), c.get("url", ""), c.get("license", "")]


func _ready() -> void:
	Sfx.start_music(App.TITLE_MUSIC["id"], App.TITLE_MUSIC["clip"], App.TITLE_MUSIC["gain_db"])
	var bg := ColorRect.new()
	bg.color = Color(0.15, 0.17, 0.26)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 24.0
	scroll.offset_right = -24.0
	scroll.offset_top = 24.0
	scroll.offset_bottom = -24.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(vbox)
	vbox.add_child(_label("CREDITS", 48, Color(1.0, 0.81, 0.54)))
	vbox.add_child(_label("Hoop Shoot is built with Godot, Blender and Aseprite.", 20, Color(0.62, 0.68, 0.85)))
	vbox.add_child(_spacer(12))
	vbox.add_child(_label("— SOUNDS —", 24, Color(0.62, 0.68, 0.85)))
	for c in load_credits().get("sounds", []):
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 2)
		block.add_child(_label(str(c.get("used_for", "")), 18, Color(0.42, 0.85, 0.64)))
		var line := _label(attribution_line(c), 20, Color(0.92, 0.93, 0.97))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		block.add_child(line)
		vbox.add_child(block)
	var fonts: Array = load_credits().get("fonts", [])
	if not fonts.is_empty():
		vbox.add_child(_spacer(12))
		vbox.add_child(_label("— FONTS —", 24, Color(0.62, 0.68, 0.85)))
		for c in fonts:
			var block := VBoxContainer.new()
			block.add_theme_constant_override("separation", 2)
			block.add_child(_label(str(c.get("used_for", "")), 18, Color(0.42, 0.85, 0.64)))
			var line := _label(attribution_line(c), 20, Color(0.92, 0.93, 0.97))
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			block.add_child(line)
			vbox.add_child(block)
	var models: Array = load_credits().get("models", [])
	if not models.is_empty():
		vbox.add_child(_spacer(12))
		vbox.add_child(_label("— MODELS —", 24, Color(0.62, 0.68, 0.85)))
		for c in models:
			var block := VBoxContainer.new()
			block.add_theme_constant_override("separation", 2)
			block.add_child(_label(str(c.get("used_for", "")), 18, Color(0.42, 0.85, 0.64)))
			var line := _label(attribution_line(c), 20, Color(0.92, 0.93, 0.97))
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			block.add_child(line)
			vbox.add_child(block)
	vbox.add_child(_spacer(20))
	var back := Button.new()
	back.text = "◀ back"
	back.add_theme_font_size_override("font_size", 24)
	back.custom_minimum_size = Vector2(0, 60)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(App.to_title)
	vbox.add_child(back)


func _label(text: String, size_: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", size_)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
