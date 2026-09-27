class_name HudCopy
extends RefCounted
## The solo-mode HUD's copy (design "Solo Modes HUD", docs/HOME.md → HUD),
## pure and headless: how a banner splits into its two lines, the clock's
## text and its last-ten-seconds colour, the BEST chip, the shot-help value.

## A banner line longer than this is a note (drawn small, one line).
const NOTE_OVER := 12
const HOT_SECONDS := 10.0


## A banner as [top, bottom]: a trailing `+N` is the bottom line (`SWISH +2`
## → SWISH / +2), a bare `+N` sits on top, two words split (`HEATING UP`),
## three words break after the second (`IN AND OUT` → IN AND / OUT), a
## single word stays on top. Non-ASCII glyphs (the old emoji) are dropped.
static func split_banner(text: String) -> Array:
	var clean := ascii(text).strip_edges()
	var words := clean.split(" ", false)
	if words.is_empty():
		return ["", ""]
	if words.size() == 1:
		return [words[0], ""]
	var last: String = words[words.size() - 1]
	if last.begins_with("+") and last.length() > 1 and last.substr(1).is_valid_int():
		return [" ".join(words.slice(0, words.size() - 1)), last]
	if words.size() == 2:
		return [words[0], words[1]]
	return [" ".join(words.slice(0, 2)), " ".join(words.slice(2))]


## Too long for the big banner: draw it as a note.
static func is_note(text: String) -> bool:
	var parts := split_banner(text)
	return str(parts[0]).length() > NOTE_OVER or str(parts[1]).length() > NOTE_OVER


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


## The overtime break card: {sub, title, note}.
static func ot_break(you: int, opp: int, n: int, seconds: int, spots: bool) -> Dictionary:
	return {"sub": "TIED %d-%d" % [you, opp], "title": "OVERTIME" if n <= 1 else "OVERTIME %d" % n,
		"note": ("%d SECONDS · BOTH SHOOTERS BACK TO THE KEY" % seconds) if spots else ("%d SECONDS" % seconds)}


static func shot_help_value(mode: int) -> String:
	return str(App.SHOT_HELP_LABELS[clampi(mode, 0, App.SHOT_HELP_LABELS.size() - 1)])
