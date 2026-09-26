extends Control
## Results: the finished run's stat line, NEW BEST callout, top-10 leaderboard,
## Run it back / Title.

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.15, 0.17, 0.26)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.position = Vector2(-300, -480)
	vbox.size = Vector2(600, 960)
	vbox.add_theme_constant_override("separation", 12)
	add_child(vbox)

	var run := App.last_run

	if App.last_run_was_best:
		vbox.add_child(_label("🎉 NEW BEST!", 40, Color(1.0, 0.85, 0.3)))
	vbox.add_child(_label("SCORE  %d" % run.get("score", 0), 72, Color(1.0, 0.81, 0.54)))
	var stats := "%d/%d makes   ✨%d swishes   🔥%d streak" % [
		run.get("makes", 0), run.get("attempts", 0),
		run.get("swishes", 0), run.get("bestStreak", 0),
	]
	if int(run.get("bonus", 0)) > 0:
		stats += "   +%d streak bonus" % int(run["bonus"])
	if int(run.get("iced", 0)) > 0:
		stats += "   🧊%d iced" % int(run["iced"])
	vbox.add_child(_label(stats, 24, Color(0.85, 0.88, 0.95)))

	vbox.add_child(_spacer(24))
	var loc: String = run.get("location", "cage")
	vbox.add_child(_label("— LEADERBOARD · %s —" % ("BEACH" if loc == "beach" else "ARCADE"), 26, Color(0.62, 0.68, 0.85)))

	var top := SaveService.top_scores(10, loc)
	for i in top.size():
		var d: Dictionary = top[i]
		var mine: bool = d.get("id", "") == run.get("id", "-")
		var row := _label(
			"%2d.  %3d pts   %d✨  %d🔥%s" % [
				i + 1, d["score"], d.get("swishes", 0), d.get("bestStreak", 0),
				"   ◀ this run" if mine else "",
			], 22,
			Color(1.0, 0.85, 0.3) if mine else Color(0.8, 0.83, 0.92))
		vbox.add_child(row)

	vbox.add_child(_spacer(30))

	var again := Button.new()
	again.text = "  RUN IT BACK 🏀  "
	again.add_theme_font_size_override("font_size", 32)
	again.custom_minimum_size = Vector2(0, 76)
	again.pressed.connect(func() -> void: App.start_mode(App.next_mode))
	vbox.add_child(again)

	var title_btn := Button.new()
	title_btn.text = "Title"
	title_btn.add_theme_font_size_override("font_size", 24)
	title_btn.custom_minimum_size = Vector2(0, 56)
	title_btn.pressed.connect(App.to_title)
	vbox.add_child(title_btn)


func _label(text: String, size_: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size_)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
