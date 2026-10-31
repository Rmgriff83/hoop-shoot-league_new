class_name HomeLayout
extends RefCounted
## The home screen's rows on any screen height (design "Home League Context
## v2", 2026-10-30, drawn at 720×1560 with the top row at 118 under an
## iPhone's notch; docs/HOME.md → Screen vs. design), pure and headless. The
## top row sits 32 px under the screen's top edge (or on the safe line) and
## the ticker on its bottom edge; the card block (the league card and the
## TIME TRIAL / PRACTICE pair) ends 74 px above the bottom; the area zone,
## the chevrons, the board and the card area keep their proportion of the
## space between the top row and the card block, measured on the design. So
## an iPhone matches the design exactly, the moto (1604) nearly, and a 9:16
## screen keeps the proportions. All y's are screen coordinates (0 = the
## screen's top), whole pixels.

const TOP_Y := 32.0           # the top row (LVL, the locker ball, the tickets, the menu)
const ROW_H := 60.0           # the top row's height: the middle starts under it
const WASH_UNDER := 24.0      # the top wash runs this far under the row
const TICKER_H := 48.0        # HomeTicker.HEIGHT
const BOTTOM := 74.0          # the card block ends this far above the screen's bottom
const CARDS_H := 446.0        # league 310 + gap 20 + pair 110 + the 6 px shadow room
## The design's rows (the top row at DESIGN_TOP, the card block from DESIGN_CARDS).
const DESIGN_TOP := 118.0
const DESIGN_CARDS := 1040.0
const ZONE_D := 277.0         # the stars + area name zone
const CHEVRON_D := 697.0      # the < > chevrons
const BOARD_D := 747.0        # the time-trial board mid-court (Ross, 2026-10-30: 50 px under the chevrons)
const AREA_D := 922.0         # the card area's top (the tabs when the league is open)
## Offsets kept from the design: the season chip under the zone, BACK TO HOME
## under the chip, the wash a little under the area's top, the floating
## league rows above the area.
const CHIP_DROP := 182.0
const BACK_DROP := 181.0
const BACK_H := 64.0
const WASH_DROP := 14.0
const FLOAT_UP := 155.0
const LOADOUT_UP := 198.0
const FLOAT_GAP := 20.0       # BACK TO HOME stays this far above the CARDS float
const TROPHY_UP := 43.0       # the trophies overhang the league card's top
const BOARD_GAP := 0.0        # the board may run down to them


## The rows for a screen `h` px tall with the top row at `top_y` (TOP_Y, or
## the top safe area when that is lower): {top_y, wash_top_h, zone_y, chip_y,
## back_y, back_inline, chevron_y, board_y, board_max_h, area_top,
## area_bottom, cards_top, cards_bottom, wash_y, wash_h, float_y, loadout_y,
## ticker_y}. `back_inline`: no room for BACK TO HOME under the chip (a short
## screen) — it sits on the chip's row instead, at chip_y.
static func compute(h: float, top_y := TOP_Y) -> Dictionary:
	var band_top := top_y + ROW_H
	var design_band := DESIGN_TOP + ROW_H
	var ticker_y := h - TICKER_H
	var cards_bottom := h - BOTTOM
	var cards_top := cards_bottom - CARDS_H
	var k := (cards_top - band_top) / (DESIGN_CARDS - design_band)
	var at := func(y: float) -> float: return roundf(band_top + (y - design_band) * k)
	var zone_y: float = at.call(ZONE_D)
	var area_top: float = at.call(AREA_D)
	var board_y: float = at.call(BOARD_D)
	var chip_y := zone_y + CHIP_DROP
	var loadout_y := area_top - LOADOUT_UP
	var back_y := chip_y + BACK_DROP
	var inline := back_y + BACK_H + FLOAT_GAP > loadout_y
	if inline:
		back_y = chip_y
	return {
		"top_y": top_y,
		"wash_top_h": band_top + WASH_UNDER,
		"zone_y": zone_y,
		"chip_y": chip_y,
		"back_y": back_y,
		"back_inline": inline,
		"chevron_y": at.call(CHEVRON_D),
		"board_y": board_y,
		"board_max_h": cards_top - TROPHY_UP - BOARD_GAP - board_y,
		"area_top": area_top,
		"area_bottom": cards_bottom,
		"cards_top": cards_top,
		"cards_bottom": cards_bottom,
		"wash_y": area_top + WASH_DROP,
		"wash_h": ticker_y - area_top - WASH_DROP,
		"float_y": area_top - FLOAT_UP,
		"loadout_y": loadout_y,
		"ticker_y": ticker_y,
	}
