class_name HudCopy
extends RefCounted
## The solo-mode HUD's copy (design "Solo Modes HUD", docs/HOME.md → HUD),
## pure and headless: which toast chip a call draws as, the clock's text
## and its last-ten-seconds colour, the BEST chip, the shot-help value.

const HOT_SECONDS := 10.0
## The toasts' seconds (designs 4a / 5a: toastSlide is 2.8 s).
const TOAST_S := 2.8
const SHOOTING_TOAST_S := 1.6
const POP_CREAM := Color("#F1E8D0")
const POP_GOLD := Color("#F0B84A")
const POP_ORANGE := Color("#E8703A")


## The rim pop for a make (design 5a): `+N` alone in cream, `+N` under
## SWISH in gold, `+N` under BUZZER BEATER in orange. {number, word, color}.
static func rim_pop(outcome_type: String, pts: int, buzzer := false) -> Dictionary:
	if buzzer:
		return {"number": "+%d" % pts, "word": "BUZZER BEATER", "color": POP_ORANGE}
	if outcome_type == ShotClassify.SWISH:
		return {"number": "+%d" % pts, "word": "SWISH", "color": POP_GOLD}
	return {"number": "+%d" % pts, "word": "", "color": POP_CREAM}


## The HEATING UP pop. No screen pops it any more (Ross, 2026-10-24: the
## cage hoop starting to move keeps its LED marquee and the light flare, not
## a message at the rim); kept for the LED copy and the tests that pin it.
static func heat_pop() -> Dictionary:
	return {"number": "", "word": "HEATING UP", "color": POP_ORANGE}


static func fire_pop() -> Dictionary:
	return {"number": "", "word": "ON FIRE", "color": POP_ORANGE}


static func in_out_pop() -> Dictionary:
	return {"number": "", "word": "IN AND OUT", "color": POP_CREAM}


## Every call the screens send to Hud.banner, as the toast chip the designs
## draw it with (4a / 5a, 2026-10-24: a chip sliding in from the edge —
## title over sub beside an icon): {kind: big|small, pre, title, sub, icon,
## color, seconds, stay}. GO! → the big orange GO (up GO_TOAST_S); TIME! →
## the orange chip with the stopwatch (Hud.time_toast adds the score); the
## 30S MODE notes → `30S MODE` over `ON · SPOTS SHUFFLE` / `ON · HOOP ON THE
## MOVE` / `OFF`; `NEXT: <spot> IN n` → NEXT SPOT over `<spot> IN n` in gold,
## staying (the screen re-sends each second and the text swaps); `NOW
## SHOOTING: <spot>` → NEW SPOT over `MOVE TO <spot>` in gold for a moment;
## anything else → a chip with the text upper-cased in the colour given.
static func toast_for(text: String, color: Color) -> Dictionary:
	var clean := ascii(text).strip_edges()
	var upper := clean.to_upper()
	var out := {"kind": "small", "pre": "", "title": upper, "sub": "", "icon": "", "color": color, "seconds": TOAST_S, "stay": false}
	if upper == "GO!" or upper == "GO":
		out["kind"] = "big"
		out["title"] = "GO"
		out["color"] = POP_ORANGE
		out["seconds"] = Hud.GO_TOAST_S
	elif upper == "TIME!":
		out["color"] = POP_ORANGE
		out["icon"] = "icon_stopwatch"
	elif upper.begins_with("30S MODE"):
		out["title"] = "30S MODE"
		if upper.contains("OFF"):
			out["sub"] = "OFF"
		elif upper.contains("HOOP"):
			out["sub"] = "ON · HOOP ON THE MOVE"
		else:
			out["sub"] = "ON · SPOTS SHUFFLE"
		out["color"] = POP_ORANGE
		out["icon"] = "icon_stopwatch"
	elif upper.begins_with("NEXT: "):
		out["title"] = "NEXT SPOT"
		out["sub"] = upper.trim_prefix("NEXT: ")
		out["color"] = POP_GOLD
		out["icon"] = "icon_stopwatch"
		out["stay"] = true
	elif upper.begins_with("NOW SHOOTING: "):
		out["title"] = "NEW SPOT"
		out["sub"] = "MOVE TO %s" % upper.trim_prefix("NOW SHOOTING: ")
		out["color"] = POP_GOLD
		out["icon"] = "icon_stopwatch"
		out["seconds"] = SHOOTING_TOAST_S
	return out


## The buzzer's toast (design 5a): TIME! over `SCORE n` (`· NEW BEST` when it is).
static func time_toast(score: int, new_best: bool) -> Dictionary:
	return {"kind": "small", "pre": "", "title": "TIME!", "sub": ("SCORE %d · NEW BEST" % score) if new_best else ("SCORE %d" % score),
		"icon": "icon_stopwatch", "color": POP_ORANGE, "seconds": TOAST_S, "stay": false}


## The card-played toast (design 4a): the card's name over PLAYED ON YOU /
## PLAYED ON <the opponent's first name>, the badge for the side it landed on.
static func deal_toast(card_name: String, on_you: bool, opp_short: String) -> Dictionary:
	return {"title": card_name.to_upper(), "sub": "PLAYED ON %s" % ("YOU" if on_you else opp_short.to_upper()), "target": "self" if on_you else "opp"}


static func ascii(text: String) -> String:
	var out := ""
	for ch in text:
		var code := ch.unicode_at(0)
		if code >= 32 and code < 127:
			out += ch
	return out.replace("  ", " ")


## `41.7`, or `OT1 41.7` in an overtime period.
static func clock_text(time_left: float, ot := 0) -> String:
	var t := "%.1f" % maxf(time_left, 0.0)
	return ("OT%d %s" % [ot, t]) if ot > 0 else t


static func clock_hot(time_left: float) -> bool:
	return time_left <= HOT_SECONDS


## The BEST chip: `BEST 29` until the score passes it, then `NEW BEST 31`.
## With no best yet: `BEST -` until the first point, then `NEW BEST`.
static func best_chip(best: int, score: int) -> Dictionary:
	if score > best and score > 0:
		return {"label": "NEW BEST", "val": str(score)}
	return {"label": "BEST", "val": str(best) if best > 0 else "-"}


## The card-deal caption as [left, right]: the card's name then who it lands
## on — YOU, or the opponent's first name. `by_ai`: the opponent played it.
static func deal_caption(card_name: String, on_you: bool, opp_short: String) -> Array:
	return [card_name.to_upper(), "YOU" if on_you else opp_short.to_upper()]


## The countdown toast's small line (design 4a: "STARTS IN" over the digit).
static func countdown_pre() -> String:
	return "STARTS IN"


## The overtime toast: {title, sub} — OVERTIME (or OVERTIME n) over `20S ON THE CLOCK`.
static func ot_toast(n: int, seconds: int) -> Dictionary:
	return {"title": "OVERTIME" if n <= 1 else "OVERTIME %d" % n, "sub": "%dS ON THE CLOCK" % seconds}


## The overtime break card: {sub, title, note}.
static func ot_break(you: int, opp: int, n: int, seconds: int, spots: bool) -> Dictionary:
	return {"sub": "TIED %d-%d" % [you, opp], "title": "OVERTIME" if n <= 1 else "OVERTIME %d" % n,
		"note": ("%d SECONDS · BOTH SHOOTERS BACK TO THE KEY" % seconds) if spots else ("%d SECONDS" % seconds)}


static func shot_help_value(mode: int) -> String:
	return str(App.SHOT_HELP_LABELS[clampi(mode, 0, App.SHOT_HELP_LABELS.size() - 1)])
