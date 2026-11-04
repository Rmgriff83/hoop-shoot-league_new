extends RefCounted
## The game pulse (docs/HOME.md → League post-match, design 6b): GamePulse
## reads a result's score series into the chart's facts — the axis top, the
## margin's extremes, the lead changes, the caption's kind and marker, the
## clock ticks — and builds fixtures from keyframes the way the design does.


const WIN_KT := [0, 15, 30, 45, 60, 75, 90]
const WIN_KY := [0, 4, 8, 11, 16, 24, 31]
const WIN_KO := [0, 7, 13, 18, 21, 23, 24]
const PLAYOFF_KT := [0, 15, 30, 45, 60, 75, 90, 110]
const PLAYOFF_KY := [0, 5, 10, 14, 18, 21, 24, 28]
const PLAYOFF_KO := [0, 6, 9, 15, 17, 22, 24, 27]


func run(t) -> void:
	_keyframes(t)
	_rules(t)
	_ticks(t)


func _keyframes(t) -> void:
	var p := GamePulse.from_keyframes(WIN_KT, WIN_KY, WIN_KO)
	t.eq(float(p["step"]), 2.0, "sampled every 2 s")
	t.eq(p["you"].size(), 46, "46 samples over 90 s (0, 2, …, 90)")
	t.eq(p["opp"].size(), 46, "…both sides")
	t.eq(int(p["you"][0]), 0, "starts at 0")
	t.eq(int(p["you"][-1]), 31, "ends on the final")
	t.eq(int(p["opp"][-1]), 24, "…both")
	t.eq(int(p["you"][15]), 8, "a keyframe lands on its clock (30 s → 8)")
	t.eq(int(p["you"][8]), 4, "linear between (16 s → 4.3 → 4)")
	t.eq(int(p["you"][11]), 6, "…(22 s → 5.9 → 6)")
	var ot := GamePulse.from_keyframes(PLAYOFF_KT, PLAYOFF_KY, PLAYOFF_KO)
	t.eq(ot["you"].size(), 56, "56 samples over 110 s with overtime")
	t.eq(int(ot["you"][-1]), 28, "the OT final")


func _rules(t) -> void:
	t.eq(GamePulse.analyse({}), {}, "nothing → nothing")
	t.eq(GamePulse.analyse({"step": 2.0, "you": [0], "opp": [0]}), {}, "one sample is no pulse")
	# The design's regular-season win: behind all the way until the last 15 s — a comeback.
	var a := GamePulse.analyse(GamePulse.from_keyframes(WIN_KT, WIN_KY, WIN_KO))
	t.ok(bool(a["won"]), "won")
	t.close(float(a["duration"]), 90.0, 1e-9, "90 s")
	t.ok(not bool(a["ot"]), "no overtime")
	t.eq(int(a["max"]), 40, "the axis top: the higher final + 3, up to a ten (31 → 40)")
	t.eq(str(a["kind"]), "comeback", "down 7 at the hour → a comeback")
	t.eq(int(a["lo"]), -7, "the deficit")
	t.eq(str(a["mark_text"]), "-7", "…marked")
	t.close(float(a["mark_t"]), float(a["mark_i"]) * 2.0, 1e-9, "the marker's clock")
	t.ok(float(a["mark_t"]) >= 30.0 and float(a["mark_t"]) <= 46.0, "…around the half (%.0f)" % float(a["mark_t"]))
	t.eq(HeatCopy.pulse_caption(a)["text"], "COMEBACK · DOWN 7 AT %s" % GamePulse.fmt(float(a["mark_t"])), "the caption")
	t.eq(HeatCopy.pulse_caption(a)["color"], HeatCopy.BUTTER, "…in butter")
	# Led by eight, lost: slipped away.
	var s := GamePulse.analyse(GamePulse.from_keyframes(WIN_KT, [0, 9, 16, 22, 26, 30, 33], [0, 3, 8, 14, 22, 30, 36]))
	t.eq(str(s["kind"]), "slipped", "a lead of 8 that was lost")
	t.eq(int(s["hi"]), 8, "the lead")
	t.eq(str(s["mark_text"]), "+8", "…marked")
	t.eq(HeatCopy.pulse_caption(s)["text"], "LED BY 8 · SLIPPED AWAY", "the caption")
	t.eq(HeatCopy.pulse_caption(s)["color"], HeatCopy.BAD, "…in red")
	# Traded the lead, settled in overtime.
	var c := GamePulse.analyse(GamePulse.from_keyframes(PLAYOFF_KT, PLAYOFF_KY, PLAYOFF_KO))
	t.ok(bool(c["ot"]), "overtime")
	t.eq(str(c["kind"]), "changes", "lead changes")
	t.ok(int(c["changes"]) >= 2, "…at least two (%d)" % int(c["changes"]))
	t.eq(int(c["mark_i"]), -1, "no marker")
	t.eq(HeatCopy.pulse_caption(c)["text"], "%d LEAD CHANGES · WON IN OT" % int(c["changes"]), "the caption, won in OT")
	var cl := GamePulse.analyse(GamePulse.from_keyframes(PLAYOFF_KT, PLAYOFF_KO, PLAYOFF_KY))
	t.eq(HeatCopy.pulse_caption(cl)["text"], "%d LEAD CHANGES · LOST IN OT" % int(cl["changes"]), "…or lost in OT")
	# Never behind, never close: wire to wire; its mirror: a chase.
	var w := GamePulse.analyse(GamePulse.from_keyframes(WIN_KT, [0, 6, 12, 17, 22, 32, 41], [0, 3, 8, 12, 16, 24, 37]))
	t.eq(str(w["kind"]), "wire", "led wire to wire")
	t.eq(HeatCopy.pulse_caption(w)["text"], "LED WIRE TO WIRE", "the caption")
	var ch := GamePulse.analyse(GamePulse.from_keyframes(WIN_KT, [0, 3, 8, 12, 16, 24, 37], [0, 6, 12, 17, 22, 32, 41]))
	t.eq(str(ch["kind"]), "chased", "chased all game")
	t.eq(HeatCopy.pulse_caption(ch)["text"], "CHASED ALL GAME", "the caption")
	# A big deficit that was NOT overturned is a chase, not a comeback; a lead kept is wire to wire.
	var big := GamePulse.analyse({"step": 2.0, "you": [0, 2, 4, 20], "opp": [0, 8, 16, 24]})
	t.eq(str(big["kind"]), "chased", "down 12 and still lost: a chase")
	t.eq(int(big["max"]), 30, "axis 24 + 3 → 30")
	t.eq(GamePulse.analyse({"step": 2.0, "you": [0, 2], "opp": [0, 1]})["max"], 10, "the axis never drops under 10")


func _ticks(t) -> void:
	t.eq(GamePulse.fmt(0.0), "0:00", "0:00")
	t.eq(GamePulse.fmt(64.0), "1:04", "1:04")
	t.eq(GamePulse.fmt(110.0), "1:50", "1:50")
	t.eq(GamePulse.ticks(90.0), ["0:00", "0:30", "1:00", "1:30"], "thirds of regulation")
	t.eq(GamePulse.ticks(110.0), ["0:00", "0:45", "1:30", "1:50"], "with overtime: the half, the buzzer, the end")
	t.eq(GamePulse.ticks(20.0), ["0:00", "0:07", "0:13", "0:20"], "a short heat (tests, a forfeit): thirds of what was played")
	var display := UiFont.display()
	var bold := UiFont.body_bold()
	for s in HeatCopy.pulse_strings():
		for ch in s:
			t.ok(display.has_char(ch.unicode_at(0)) and bold.has_char(ch.unicode_at(0)), "glyph '%s' in both faces" % ch)
