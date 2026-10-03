extends RefCounted
## The city's fence scoreboard (Scoreboard = a 32-column LedBoard clock window
## plus DigitPanel HOME / VISITOR / PER windows), its seven-segment digits,
## the glb's windows, and the court binding it as the city's board.


func run(t) -> void:
	_digits(t)
	_board(t)
	_city(t)


func _digits(t) -> void:
	var red := Scoreboard.SCORE_RED
	var d := DigitPanel.new(3, red)
	t.eq(d.width(), 3 * DigitPanel.DIGIT_W + 2 * DigitPanel.GAP, "three digits with gaps")
	t.eq(d.text(), "   ", "blank at first")
	d.flush()
	t.eq(d.lit_count(), 0, "…nothing lit")
	d.set_number(47)
	d.flush()
	t.eq(d.text(), " 47", "right-aligned with a leading blank")
	t.ok(d.lit_count() > 0, "digits light")
	d.set_number(1234)
	t.eq(d.text(), "234", "overflow keeps the low digits")
	var eight := DigitPanel.new(1, red)
	eight.set_number(8)
	eight.flush()
	var one := DigitPanel.new(1, red)
	one.set_number(1)
	one.flush()
	t.ok(eight.lit_count() > 3 * one.lit_count(), "an 8 lights all seven segments, a 1 two (%d vs %d)" % [eight.lit_count(), one.lit_count()])
	t.ok(eight.material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and eight.material.emission_enabled, "lit glass: unshaded, emissive")


func _board(t) -> void:
	var sb := Scoreboard.new()
	t.eq(sb.cols, Scoreboard.CLOCK_COLS, "the clock window is 32 columns")
	t.eq(sb.idle_text(), "", "blank glass until a clock is set")
	sb.set_clock(47.3)
	t.eq(sb.idle_text(), "0:48", "the clock rounds up like a game clock")
	sb.set_clock(125.0)
	t.eq(sb.idle_text(), "2:05", "minutes and seconds")
	sb.set_clock(0.0)
	t.eq(sb.idle_text(), "0:00", "zero")
	sb.clear_clock()
	t.eq(sb.idle_text(), "", "practice: no clock")
	sb.show_score(12, 3)
	sb.advance(0.0)
	t.eq(sb.home.text(), " 12", "HOME is the score")
	t.eq(sb.period.text(), "1", "the tier is not the period")
	sb.set_visitor(35)
	sb.set_period(2)
	sb.advance(0.0)
	t.eq(sb.visitor.text(), " 35", "VISITOR")
	t.eq(sb.period.text(), "2", "PER")
	sb.set_clock(30.0)
	sb.advance(0.0)
	var clock_lit := sb.lit_count()
	t.ok(clock_lit > 0, "the clock shows on the matrix")
	sb.flash("GO!", 1, sb.accent_color)
	t.eq(sb.mode(), "flash", "a message takes the time area")
	sb.advance(LedBoard.FLASH_PERIOD * 2 + 0.01)
	t.eq(sb.mode(), "idle", "…and finishes")
	sb.advance(0.0)
	t.eq(sb.lit_count(), clock_lit, "…and the clock is back")
	t.eq(sb.on_color, Scoreboard.CLOCK_ON, "yellow clock")
	var chain := CosmeticLibrary.get_hoop("chain")
	if chain != null:
		sb.set_palette(chain)
		t.eq(sb.on_color, Scoreboard.CLOCK_ON, "…whatever the hoop's palette")
	sb.free()


func _city(t) -> void:
	var glb: Node = load("res://assets/arena/city/city.glb").instantiate()
	for n in ["ReaderRig", "ScoreTilt", "ScoreBezel", "ScoreHousing", "ScoreVentL5", "ScoreFace", "ScoreClock", "ScoreHome", "ScoreVisitor", "ScorePeriod"]:
		t.ok(glb.find_child(n, true, false) != null, "%s in the city glb" % n)
	t.ok(glb.find_child("LedFace", true, false) == null, "the fence reader board is gone")
	t.ok(glb.find_child("ReaderBracket0", true, false) == null, "…and its fence brackets")
	# Tabletop size, on the ground, to the shooter's right of the pole, by the fence.
	var rig: Node3D = glb.find_child("ReaderRig", true, false)
	var plate: MeshInstance3D = glb.find_child("ScoreBezel", true, false)
	var ps := plate.get_aabb().size
	t.ok(ps.z < 0.8 and ps.y < 0.6, "a tabletop unit (%.2f x %.2f m)" % [ps.z, ps.y])
	t.ok(absf(rig.position.y) < 0.01 and rig.position.z > 1.0 and rig.position.x > 4.8, "on the ground, right of the pole, against the fence (%s)" % str(rig.position))
	var tilt: Node3D = glb.find_child("ScoreTilt", true, false)
	t.ok(absf(tilt.rotation.z) > 0.05 or absf(tilt.rotation.y) > 0.05 or absf(tilt.rotation.x) > 0.05, "the plate leans back")
	t.ok(glb.find_child("AnimationPlayer", true, false).has_animation("ScorePop"), "the board still hops on a make")
	glb.free()
	var root := Node3D.new()
	var court := CourtGeometry.new()
	court.geo = SimGeometry.city()
	court.arena_set = CosmeticLibrary.get_arena("city")
	court.hoop_set = CosmeticLibrary.get_hoop("chain") if CosmeticLibrary.get_hoop("chain") != null else CosmeticLibrary.starter_hoop()
	root.add_child(court)
	court._ready()
	t.ok(court.led is Scoreboard and court.info == court.led, "the city's board is the scoreboard, messages included")
	court.set_clock(30.0)
	court.set_visitor(9)
	court.set_period(2)
	court.led.show_score(7)
	court.led.advance(0.0)
	var sb := court.led as Scoreboard
	t.ok(sb.idle_text() == "0:30" and sb.home.text() == "  7" and sb.visitor.text() == "  9" and sb.period.text() == "2", "clock, scores and period reach the glass")
	var clock: MeshInstance3D = court.find_child("ScoreClock", true, false)
	t.ok(clock != null and clock.material_override == sb.material, "the clock window wears the matrix")
	var home: MeshInstance3D = court.find_child("ScoreHome", true, false)
	t.ok(home != null and home.material_override == sb.home.material, "…and HOME its digits")
	root.free()
