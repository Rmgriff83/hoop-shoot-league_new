class_name Scoreboard
extends LedBoard
## The city's fence scoreboard (build_city.py ReaderRig; Ross's 2026-10-03
## reference, a tabletop scoreboard: a yellow clock up top, HOME and VISITOR
## in red below with the PERiod in green between). It IS a LedBoard: the
## 32-column matrix is the clock window, so every message the screens send
## (GO!, SWISH +2, HEATING UP …) flashes or scrolls in the time area and the
## clock comes back after. The score windows are DigitPanels bound to their
## own quads (CourtGeometry binds ScoreClock / ScoreHome / ScoreVisitor /
## ScorePeriod).

const CLOCK_COLS := 32
const CLOCK_ON := Color8(255, 200, 40)
const CLOCK_ACCENT := Color8(255, 150, 30)
const SCORE_RED := Color8(255, 60, 40)
const PERIOD_GREEN := Color8(90, 230, 80)

var home: DigitPanel
var visitor: DigitPanel
var period: DigitPanel


func _init() -> void:
	super(CLOCK_COLS)
	home = DigitPanel.new(3, SCORE_RED)
	visitor = DigitPanel.new(3, SCORE_RED)
	period = DigitPanel.new(1, PERIOD_GREEN)
	on_color = CLOCK_ON
	accent_color = CLOCK_ACCENT
	_color = on_color
	set_idle_text("")   # blank glass until a clock is set (practice stays blank)
	home.set_number(0)
	period.set_number(1)
	_dirty = true


## The hoop set's palette styles the hoop's own board; the scoreboard keeps
## its glass colours. Only the backboard band follows the set.
func set_palette(set: HoopSet) -> void:
	band_flash_color = set.band_flash_color
	band_buzzer_color = set.band_buzzer_color


## HOME is the score. The tier is not the period (it reads on the clock as
## "3 PTS A BASKET"), so `mult` is ignored here.
func show_score(score: int, _mult := 1) -> void:
	home.set_number(score)


## The clock window's idle text, M:SS, rounded up like a real game clock.
func set_clock(seconds: float) -> void:
	var s := maxi(0, int(ceil(seconds - 1e-6)))
	var text := "%d:%02d" % [s / 60, s % 60]
	if text != idle_text():
		set_idle_text(text)


func clear_clock() -> void:
	if idle_text() != "":
		set_idle_text("")


func set_visitor(score: int) -> void:
	visitor.set_number(score)


func clear_visitor() -> void:
	visitor.set_text("")


func set_period(p: int) -> void:
	period.set_number(p)


func advance(dt: float) -> void:
	super(dt)
	home.flush()
	visitor.flush()
	period.flush()
