## CssEase (design "Home League Context v2", 2026-10-30): the prototypes'
## CSS timing — beziers, steps, per-interval keyframes and the named runs.


func run(t) -> void:
	# Beziers: exact ends, the snap curve fast early, ease-in slow early.
	t.eq(CssEase.bezier(CssEase.SNAP, 0.0), 0.0, "bezier: 0 at the start")
	t.eq(CssEase.bezier(CssEase.SNAP, 1.0), 1.0, "bezier: 1 at the end")
	t.ok(CssEase.bezier(CssEase.SNAP, 0.25) > 0.6, "the snap curve is most of the way there at 25 %")
	t.ok(CssEase.bezier(CssEase.EASE_IN, 0.5) < 0.5 and CssEase.bezier(CssEase.EASE_OUT, 0.5) > 0.5, "ease-in starts slow, ease-out fast")
	t.close(CssEase.bezier(Vector4(0.0, 0.0, 1.0, 1.0), 0.3), 0.3, 1e-4, "a linear bezier is the identity")
	# steps(n, end).
	t.eq(CssEase.steps(6, 0.1), 0.0, "steps: holds the start value through the first step")
	t.close(CssEase.steps(6, 0.5), 0.5, 1e-6, "steps: 3 of 6 at half way")
	t.eq(CssEase.steps(6, 1.0), 1.0, "steps: the end value at the end")
	# Keyframes ease per interval: halfway through each interval is the same eased fraction.
	var keys := [[0.0, 0.0], [0.5, 10.0], [1.0, 0.0]]
	var e := CssEase.bezier(CssEase.EASE, 0.5)
	t.close(float(CssEase.keyframes(keys, 0.25, CssEase.EASE)), 10.0 * e, 1e-4, "keyframes: the first interval eases on its own")
	t.close(float(CssEase.keyframes(keys, 0.75, CssEase.EASE)), 10.0 * (1.0 - e), 1e-4, "keyframes: …and so does the second")
	# twinkle: hidden until 62 %, shown by 70 %, gone by 86 %; stepped.
	var S := CssEase.TWINKLE_S
	t.eq(CssEase.twinkle(0.3 * S).x, 0.0, "twinkle: hidden early")
	t.eq(CssEase.twinkle(0.62 * S).x, 0.0, "twinkle: still hidden at 62 %")
	t.close(CssEase.twinkle(0.70 * S).x, 1.0, 1e-4, "twinkle: full at 70 %")
	t.close(CssEase.twinkle(0.70 * S).y, 1.0, 1e-4, "twinkle: full size at 70 %")
	t.close(CssEase.twinkle(0.78 * S).z, 45.0, 1e-3, "twinkle: a 45° turn at 78 %")
	t.close(CssEase.twinkle(0.86 * S).x, 0.0, 1e-4, "twinkle: gone at 86 %")
	t.eq(CssEase.twinkle(0.95 * S).x, 0.0, "twinkle: hidden to the end")
	var a1 := CssEase.twinkle(0.6201 * S).x
	var a2 := CssEase.twinkle(0.6299 * S).x
	t.eq(a1, a2, "twinkle: steps(6) holds inside a sixth of the interval")
	t.close(CssEase.twinkle(1.70 * S).x, 1.0, 1e-4, "twinkle loops")
	# tabDot, cntBump, slotGrow.
	t.close(CssEase.tab_dot(0.0), 1.0, 1e-6, "tabDot: full size at the start")
	t.close(CssEase.tab_dot(0.8), 0.8, 1e-4, "tabDot: smallest half way")
	t.close(CssEase.cnt_bump(0.35 * CssEase.BUMP_S), 1.6, 1e-4, "cntBump: 1.6 at 35 %")
	t.close(CssEase.cnt_bump(CssEase.BUMP_S), 1.0, 1e-6, "cntBump: back to 1")
	t.eq(CssEase.slot_grow(0.0), Vector2(0, -28), "slotGrow: shut, the gap pulled in")
	t.eq(CssEase.slot_grow(CssEase.GROW_S), Vector2(96, 0), "slotGrow: open")
	# cardFly: from, the apex at 45 %, to.
	var from := Vector2(100, 1200)
	var to := Vector2(36, 740)
	var f0 := CssEase.card_fly(0.0, from, to, 1.25)
	t.eq(f0["pos"], from, "cardFly: starts on the shop art")
	t.close(float(f0["scale"]), 1.25, 1e-6, "cardFly: at the shop art's scale")
	var fm := CssEase.card_fly(0.45 * CssEase.FLY_S, from, to, 1.25)
	t.ok((fm["pos"] as Vector2).is_equal_approx(Vector2(108, 650)), "cardFly: the apex 40 right of the middle, 90 over the higher end")
	t.close(float(fm["rot"]), -10.0, 1e-4, "cardFly: tipped −10° at the apex")
	var f1 := CssEase.card_fly(CssEase.FLY_S, from, to, 1.25)
	t.eq(f1["pos"], to, "cardFly: lands on the slot")
	t.close(float(f1["scale"]), 1.0, 1e-6, "cardFly: at the slot's size")
	# lbIn.
	t.eq(CssEase.lb_in(0.0), Vector2(80, 0), "lbIn: 80 px right, clear")
	t.eq(CssEase.lb_in(CssEase.LB_IN_S), Vector2(0, 1), "lbIn: in place, opaque")
