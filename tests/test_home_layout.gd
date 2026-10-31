## HomeLayout (design "Home League Context v2", 2026-10-30): the home rows on
## any screen height — the top row and the ticker on the edges, the card
## block 74 px above the bottom, the middle in the design's proportions.


func run(t) -> void:
	var at := {1280: HomeLayout.compute(1280.0), 1560: HomeLayout.compute(1560.0), 1604: HomeLayout.compute(1604.0)}
	for h in at:
		var l: Dictionary = at[h]
		t.eq(float(l["top_y"]), 32.0, "%d: the top row 32 px under the top edge" % h)
		t.eq(float(l["ticker_y"]), float(h) - 48.0, "%d: the ticker on the bottom edge" % h)
		t.eq(float(l["cards_bottom"]), float(h) - 74.0, "%d: the cards end 74 px above the bottom" % h)
		t.eq(float(l["cards_top"]), float(h) - 74.0 - 446.0, "%d: the card block is 446 tall" % h)
		t.ok(float(l["zone_y"]) < float(l["chevron_y"]) and float(l["chevron_y"]) < float(l["area_top"]) and float(l["area_top"]) < float(l["cards_top"]), "%d: zone < chevrons < area top < cards" % h)
		t.eq(float(l["wash_y"]), float(l["area_top"]) + 14.0, "%d: the wash starts just under the area's top" % h)
		t.eq(float(l["wash_y"]) + float(l["wash_h"]), float(l["ticker_y"]), "%d: …and ends at the ticker" % h)
		t.eq(float(l["area_bottom"]), float(l["cards_bottom"]), "%d: the area ends with the cards" % h)
		t.eq(float(l["chip_y"]), float(l["zone_y"]) + 182.0, "%d: the season chip under the zone" % h)
		t.ok(float(l["loadout_y"]) < float(l["float_y"]) and float(l["float_y"]) < float(l["area_top"]), "%d: the floating rows sit above the area" % h)
		t.ok(float(l["board_y"]) + float(l["board_max_h"]) <= float(l["cards_top"]) - 35.0, "%d: the board's room ends at the trophies" % h)
		if not bool(l["back_inline"]):
			t.ok(float(l["back_y"]) + 64.0 + 20.0 <= float(l["loadout_y"]), "%d: BACK TO HOME clears the CARDS float" % h)
		else:
			t.eq(float(l["back_y"]), float(l["chip_y"]), "%d: a short screen puts BACK on the chip's row" % h)
		for key in l:
			if l[key] is float:
				t.ok(is_equal_approx(float(l[key]), roundf(float(l[key]))), "%d: %s is whole pixels" % [h, key])
	t.ok(bool(at[1280]["back_inline"]), "1280: no room under the chip, BACK sits beside it")
	t.ok(not bool(at[1560]["back_inline"]), "1560: BACK TO HOME under the chip")
	t.ok(float(at[1280]["board_max_h"]) > 120.0, "1280: the board still has room for its header and a row")
	# The design, exactly (the top row at 118 on an iPhone).
	var n: Dictionary = HomeLayout.compute(1560.0, 118.0)
	t.eq(float(n["top_y"]), 118.0, "notch: the top row at the safe line")
	t.eq(float(n["zone_y"]), 277.0, "notch: the zone at 277 (design)")
	t.eq(float(n["chip_y"]), 459.0, "notch: the season chip at 459 (design)")
	t.eq(float(n["back_y"]), 640.0, "notch: BACK TO HOME at 640 (design)")
	t.eq(float(n["chevron_y"]), 697.0, "notch: the chevrons at 697 (design)")
	t.eq(float(n["board_y"]), 757.0, "notch: the board at 757 (Ross: 60 px under the design's 697)")
	t.eq(float(n["loadout_y"]), 724.0, "notch: YOUR CARDS floats at 724 (design)")
	t.eq(float(n["float_y"]), 767.0, "notch: the other floats at 767 (design)")
	t.eq(float(n["area_top"]), 922.0, "notch: the area from 922 (design)")
	t.eq(float(n["wash_y"]), 936.0, "notch: the wash from 936 (design)")
	t.eq(float(n["cards_top"]), 1040.0, "notch: the league card at 1040 (design)")
	t.eq(float(n["ticker_y"]), 1512.0, "notch: the ticker stays on the bottom edge")
	t.eq(float(n["wash_top_h"]), 118.0 + 60.0 + 24.0, "notch: the top wash runs under the row")
	t.ok(float(n["board_max_h"]) >= 244.0, "notch: the whole board fits (header, three rows, YOU)")
