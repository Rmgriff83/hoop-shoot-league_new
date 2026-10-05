extends RefCounted
## The league heat's chrome helpers that need no scene: the tray column's
## slot layout (design 4a — cards from the bottom slot up, dashed empties in
## the slots above) and the dashed slot control.


func run(t) -> void:
	var HeatScreen = load("res://game/screens/heat_screen.gd")
	var spots: Array = HeatScreen.tray_layout(3, 376.0, 112.0, 120.0, 36.0)
	t.eq(spots.size(), 3, "a position per slot")
	t.ok(spots[0].y > spots[1].y and spots[1].y > spots[2].y, "slot 0 is the lowest")
	t.close(spots[0].y - spots[1].y, 120.0, 1e-6, "the slot pitch")
	t.close((spots[0].y + 112.0 + spots[2].y) / 2.0, 376.0, 1e-6, "the stack is centred on the tray's centre")
	t.close(spots[0].x, 36.0, 1e-6, "at the left margin")
	var two: Array = HeatScreen.tray_layout(2, 376.0, 112.0, 120.0, 36.0)
	t.close(two[1].y, 376.0 - (2 * 112.0 + 8.0) / 2.0, 1e-6, "two slots: the design's slotTop (260)")
	var d := ModeCards.Dashed.new(Vector2(84, 112), 2.0, 0.0)
	t.eq(d.size, Vector2(84, 112), "a dashed empty is card-sized")
	var chip := ModeCards.Dashed.new(Vector2(40, 40), 2.0, 3.0)
	t.eq(chip.size, Vector2(43, 43), "the opponent's empty chip carries its 3 px shadow")
	d.free()
	chip.free()
