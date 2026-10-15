class_name RwbNet
extends WoolNet
## The red, white and blue net (docs/BLENDER_101.md §31, Ross's design 26c):
## the classic heavy-duty braided polyester net. The knitted family's build
## with the colour in BANDS top to bottom — red through the hook loops and
## the first row, white for the next two, blue for the bottom three, every
## knot matching its band — a ~10 mm cord that sits factory-even, and short
## blue stubs past the bottom knots (on Tail bones, so they still swing).

const R_CORD_R := 0.0052
const R_KNOT_R := 0.0095
const RED := "#E3343C"
const WHITE := "#F4F3F0"
const BLUE := "#2C3FB8"


## Factory-even: a whisper of jitter, 16–24 mm stubs.
static func layout(rim_r := SimConstants.R_RIM, tube_r := SimConstants.R_TUBE) -> Dictionary:
	return knitted_layout(rim_r, tube_r, 0.02, 0.02, 0.004, 0.016, 0.008)


## The band a row's diagonal (row k → k + 1) and knot k wear.
static func band(k: int) -> Color:
	if k < 1:
		return Color.html(RED)
	if k < 3:
		return Color.html(WHITE)
	return Color.html(BLUE)


func _cord_r() -> float:
	return R_CORD_R


func _knot_r() -> float:
	return R_KNOT_R


func _knot_brightness() -> float:
	return 0.85


## The loops are red (the top band).
func _cord_color(_i: int) -> Color:
	return band(0)


func _diag_color(_i: int, k: int) -> Color:
	return band(k)


func _knot_color(k: int, _i: int) -> Color:
	return band(k)


## The stubs are blue (the bottom band).
func _tail_color(_i: int) -> Color:
	return band(NetSim.COTTON_ROWS)
