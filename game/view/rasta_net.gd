class_name RastaNet
extends RwbNet
## The Rasta net (Ross's design "Rasta Net Model", 2026-10-25): the red,
## white and blue net's build (docs/BLENDER_101.md §31) with the bands red
## through the hook loops and the first row, gold for the next two, green for
## the bottom three, every knot matching its band, green stubs.

const R_RED := "#D8322E"
const R_GOLD := "#F2C21B"
const R_GREEN := "#1F8A3C"


static func rasta_band(k: int) -> Color:
	if k < 1:
		return Color.html(R_RED)
	if k < 3:
		return Color.html(R_GOLD)
	return Color.html(R_GREEN)


func _band(k: int) -> Color:
	return rasta_band(k)
