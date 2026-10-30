extends RefCounted
## The 120-tall top row (designs "Solo Modes HUD" 5a / "League Match HUD"
## 4a, Ross's 2026-10-26 pass): the pause and the clock / PRACTICE card 120
## tall with the icon over the figure, SCORE 120 tall, the side cards 60, the
## BEST and TOP chips 60 tall hung off the row (22 / 14 px gaps) on every
## screen, TOP reading the area's all-time global top score.


func run(t) -> void:
	t.eq(Hud.ROW_H, 120.0, "the top row is 120 tall")
	t.eq(Hud.CLOCK_SIZE, Vector2(150, 120), "the clock card 150×120")
	t.eq(Hud.SCORE_SIZE, Vector2(164, 120), "the score card 164×120")
	t.eq(Hud.BOX_SIZE, Vector2(344, 120), "the heat's score box 344×120 (4a, 2026-10-30)")
	t.eq(Hud.BOX_POS.x + Hud.BOX_SIZE.x + 18.0, Hud.HEAT_CLOCK_POS.x, "…18 left of the clock card at the right end")
	t.eq(UiLayout.hud_map(Hud.TOAST_Y, 1560.0, 108.0, 62.0), 1090.0, "the toasts centre at 1090 on the design's iPhone")
	var hs := load("res://game/screens/heat_screen.gd")
	t.eq(UiLayout.hud_map(hs.PIP_Y, 1560.0, 108.0, 62.0), 256.0, "the opponent window's top at 256 on it")
	var off := IconButton.new("pause", Hud.ROW_H)
	off.disabled = true
	t.ok(off.disabled, "the pause can be the dimmed online one")
	off.free()
	t.eq(Hud.BEST_POS.y - (Hud.SCORE_POS.y + Hud.SCORE_SIZE.y), 22.0, "BEST 22 px under the score card")
	t.eq(Hud.TOP_POS.y - (Hud.BEST_POS.y + Hud.BEST_SIZE.y), 14.0, "TOP 14 px under BEST")
	var hud := Hud.new()
	hud._ready()
	var best: Control = hud.find_child("BestChip", true, false)
	var top: Control = hud.find_child("TopChip", true, false)
	t.ok(best != null and top != null, "both chips built")
	t.ok(not top.visible, "no TOP chip until BEST shows")
	hud.set_best(29)
	hud.set_top(47)
	t.ok(top.visible and hud.top_text() == "TOP 47", "TOP shows with BEST, reading the global top")
	hud.set_top(-1)
	t.eq(hud.top_text(), "TOP -", "no board in hand: a dash")
	t.eq(best.position.y, UiLayout.hud_top() + 142.0, "BEST hangs 142 under the top row's y on this screen")
	t.eq(top.position.y, UiLayout.hud_top() + 216.0, "TOP hangs 216 under it")
	t.eq(UiLayout.hud_map(32.0, 1560.0, 108.0, 62.0) + 142.0, 256.0, "(the design's BEST at 256 on its iPhone)")
	t.eq(UiLayout.hud_map(32.0, 1560.0, 108.0, 62.0) + 216.0, 330.0, "(…and TOP at 330)")
	hud.set_heat(true, "OLLIE")
	t.ok(not top.visible and not best.visible, "a heat hides both chips")
	hud.free()
	# The pause glyph grows with the button: 6×20 bars on 56, 12×40 on 120.
	var small := IconButton.new("pause")
	var big := IconButton.new("pause", Hud.ROW_H)
	t.ok(small.size == Vector2(56, 56) and big.size == Vector2(120, 120), "a 56 and a 120 px pause")
	small.free()
	big.free()
	# The practice rail sits under the 30S row, the heat's under the tall row.
	var tt := load("res://game/screens/time_trial_screen.gd")
	t.eq(tt.SPOT_RAIL_Y, 266.0, "the practice spot rail at 266 (381 on the 1560 frame)")
	t.eq(UiLayout.hud_map(tt.SPOT_RAIL_Y, 1560.0, 108.0, 62.0), 381.0, "…which the design's iPhone shows at 381")
	t.ok(tt.SPOT_RAIL_Y_HEAT >= 32.0 + 120.0 + 20.0, "a heat's picker clears the 120 px row")
