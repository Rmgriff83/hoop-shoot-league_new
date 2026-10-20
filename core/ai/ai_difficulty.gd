class_name AiDifficulty
extends RefCounted
## The global AI DIFFICULTY setting (Ross, 2026-10-19): one strength for every
## court — the leagues' rosters all measure the same as the arcade cage
## (docs/LEAGUE.md → One strength, four courts) — scaled by this setting for
## every AI the player faces. EASY / NORMAL / HARD shift the opponent's
## accuracy rating, the one rating the per-hoop calibration maps straight to
## its make share, so the step is the same on every court. NORMAL carries a
## small lift over the roster as authored (Ross, 2026-10-19 evening: "bring
## up the bar of easy, and all the levels accordingly, a little").
## Applied to the player's league heats and quick heats
## only: AI-vs-AI season games (QuickSim) ignore it, so the standings are the
## same on every setting. Headless: dictionaries in, dictionaries out.

const LEVELS := ["easy", "normal", "hard"]
const DEFAULT := "normal"
## The accuracy shift per level (rating points; sized by tools/league_lab.gd).
const SHIFT := {"easy": -0.05, "normal": 0.02, "hard": 0.09}
const LABELS := {"easy": "EASY", "normal": "NORMAL", "hard": "HARD"}


## A saved / typed value → a level; anything unknown is NORMAL.
static func normalize(value: Variant) -> String:
	var s := str(value).to_lower()
	return s if LEVELS.has(s) else DEFAULT


## The next level on the settings row: easy → normal → hard → easy.
static func next(level: String) -> String:
	return LEVELS[(LEVELS.find(normalize(level)) + 1) % LEVELS.size()]


## The setting's accuracy shift.
static func shift(level: String) -> float:
	return float(SHIFT[normalize(level)])


## A copy of a shooter's ratings dict with the level's shift on "accuracy"
## (clamped to AiMood's 0.05..0.97).
static func apply(ratings: Dictionary, level: String) -> Dictionary:
	var out := ratings.duplicate(true)
	var d := shift(level)
	if d != 0.0:
		out["accuracy"] = clampf(float(ratings.get("accuracy", 0.5)) + d, 0.05, 0.97)
	return out


## The settings row's word.
static func label(level: String) -> String:
	return str(LABELS[normalize(level)])
