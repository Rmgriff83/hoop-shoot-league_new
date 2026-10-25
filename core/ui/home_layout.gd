class_name HomeLayout
extends RefCounted
## The home screen's rows on any screen height (design "Store and Locker"
## 32a, 2026-10-24, drawn at 720×1560; docs/HOME.md → Screen vs. design),
## pure and headless. The top row sits 32 px under the screen's top edge and
## the ticker on its bottom edge; the card block (the league card and the
## TIME TRIAL / PRACTICE pair) ends 74 px above the bottom; everything
## between — the area zone, the chevrons, the hoop board, the card area's
## wash — keeps its proportion of the space between the top row and the
## card block, measured on the 1560 design. So an iPhone matches the design
## exactly, the moto (1604) nearly, and a 9:16 screen keeps the proportions.
## All y's are screen coordinates (0 = the screen's top), whole pixels.

const TOP_Y := 32.0           # the top row (LVL, the locker ball, the tickets, the menu)
const BAND_TOP := 92.0        # the top row's bottom: where the middle starts
const TICKER_H := 48.0        # HomeTicker.HEIGHT
const BOTTOM := 74.0          # the card block ends this far above the screen's bottom
const CARDS_H := 389.0        # league 270 + 5 + gap 15 + pair 94 + 5 (shadows in)
## The design's middle, 1560 tall: the card block's top (921) less the top row's bottom.
const MID_1560 := 1005.0
const ZONE_1560 := 200.0      # the stars + area name zone
const CHEVRON_1560 := 660.0   # the < > chevrons
const AREA_1560 := 921.0      # the card area's top (the wash starts here)
## The hoop board keeps today's 1280 proportion (440 of a 725 middle).
const BOARD_1280 := 440.0
const MID_1280 := 725.0
## Offsets kept from today's design: the season chip under the zone, the
## floating league rows above the card area.
const CHIP_DROP := 182.0
const STRIP_UP := 81.0
const FLOAT_UP := 169.0
const LOADOUT_UP := 197.0


## The rows for a screen `h` px tall: {top_y, zone_y, chip_y, chevron_y,
## board_y, area_top, area_bottom, cards_top, cards_bottom, wash_y, wash_h,
## strip_y, float_y, loadout_y, ticker_y}.
static func compute(h: float) -> Dictionary:
	var ticker_y := h - TICKER_H
	var cards_bottom := h - BOTTOM
	var cards_top := cards_bottom - CARDS_H
	var mid := cards_top - BAND_TOP
	var zone_y := roundf(BAND_TOP + mid * (ZONE_1560 - BAND_TOP) / MID_1560)
	var chevron_y := roundf(BAND_TOP + mid * (CHEVRON_1560 - BAND_TOP) / MID_1560)
	var area_top := roundf(BAND_TOP + mid * (AREA_1560 - BAND_TOP) / MID_1560)
	var board_y := roundf(BAND_TOP + mid * (BOARD_1280 - BAND_TOP) / MID_1280)
	return {
		"top_y": TOP_Y,
		"zone_y": zone_y,
		"chip_y": zone_y + CHIP_DROP,
		"chevron_y": chevron_y,
		"board_y": board_y,
		"area_top": area_top,
		"area_bottom": cards_bottom,
		"cards_top": cards_top,
		"cards_bottom": cards_bottom,
		"wash_y": area_top,
		"wash_h": ticker_y - area_top,
		"strip_y": area_top - STRIP_UP,
		"float_y": area_top - FLOAT_UP,
		"loadout_y": area_top - LOADOUT_UP,
		"ticker_y": ticker_y,
	}
