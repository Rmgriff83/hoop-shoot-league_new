## HomeLayout (design "Store and Locker" 32a, 2026-10-24): the home rows on
## any screen height — the top row and the ticker on the edges, the card
## block 74 px above the bottom, the middle in the design's proportions.


func run(t) -> void:
	var at := {1280: HomeLayout.compute(1280.0), 1560: HomeLayout.compute(1560.0), 1604: HomeLayout.compute(1604.0)}
	for h in at:
		var l: Dictionary = at[h]
		t.eq(float(l["top_y"]), 32.0, "%d: the top row 32 px under the top edge" % h)
		t.eq(float(l["ticker_y"]), float(h) - 48.0, "%d: the ticker on the bottom edge" % h)
		t.eq(float(l["cards_bottom"]), float(h) - 74.0, "%d: the cards end 74 px above the bottom" % h)
		t.eq(float(l["cards_top"]), float(h) - 74.0 - 389.0, "%d: the card block is 389 tall" % h)
		t.ok(float(l["zone_y"]) < float(l["chevron_y"]) and float(l["chevron_y"]) < float(l["area_top"]) and float(l["area_top"]) < float(l["cards_top"]), "%d: zone < chevrons < area top < cards" % h)
		t.eq(float(l["wash_y"]), float(l["area_top"]), "%d: the wash starts at the area's top" % h)
		t.eq(float(l["wash_y"]) + float(l["wash_h"]), float(l["ticker_y"]), "%d: …and ends at the ticker" % h)
		t.eq(float(l["area_bottom"]), float(l["cards_bottom"]), "%d: the area ends with the cards" % h)
		t.eq(float(l["chip_y"]), float(l["zone_y"]) + 182.0, "%d: the season chip under the zone" % h)
		t.ok(float(l["strip_y"]) < float(l["area_top"]) and float(l["loadout_y"]) < float(l["float_y"]), "%d: the floating rows sit above the area" % h)
		for k in l:
			t.ok(is_equal_approx(float(l[k]), roundf(float(l[k]))), "%d: %s is whole pixels" % [h, k])
	# The 1560 design, exactly.
	var d: Dictionary = at[1560]
	t.eq(float(d["zone_y"]), 200.0, "1560: the area zone at 200 (design)")
	t.eq(float(d["chevron_y"]), 660.0, "1560: the chevrons at 660 (design)")
	t.eq(float(d["area_top"]), 921.0, "1560: the card area from 921 (design)")
	t.eq(float(d["cards_top"]), 1097.0, "1560: the league card at 1097")
	t.eq(float(d["ticker_y"]), 1512.0, "1560: the ticker at 1512")
	# The 9:16 band keeps today's board and card block.
	var b: Dictionary = at[1280]
	t.eq(float(b["board_y"]), 440.0, "1280: the hoop board where it was")
	t.eq(float(b["cards_top"]), 817.0, "1280: the league card where it was")
	t.eq(float(b["ticker_y"]), 1232.0, "1280: the ticker where it was")
	t.eq(float(b["zone_y"]), 170.0, "1280: the zone a touch higher than before (180)")
	# The moto.
	var m: Dictionary = at[1604]
	t.eq(float(m["zone_y"]), 205.0, "1604: zone 205")
	t.eq(float(m["chevron_y"]), 685.0, "1604: chevrons 685")
	t.eq(float(m["area_top"]), 957.0, "1604: area top 957")
	t.eq(float(m["cards_top"]), 1141.0, "1604: cards 1141")
