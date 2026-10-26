class_name LoadingCopy
extends RefCounted
## The loading states' words and clocks (design "Loading States" 39a / 39b,
## 2026-10-25; docs/HOME.md → Loading), pure and headless: the tips, the
## LOADING dots, the stage line for a progress, the tip on show at a time,
## and the destination copy for each kind of move.

## The loader only raises the screen when a load runs past this (s), and
## keeps it up at least this long so it never flashes.
const SHOW_AFTER_S := 0.4
const MIN_SHOW_S := 0.6
const TIP_S := 2.2
const DOTS_S := 1.2
const TIPS := [
	"SWISHES SCORE 2. EVERYTHING ELSE IS 1.",
	"HIT 3 IN A ROW TO HEAT UP. KEEP IT GOING TO CATCH FIRE.",
	"A SHORT, STRAIGHT FLICK GOES IN MORE THAN A HARD ONE.",
	"WIN TICKETS IN EVERY MATCH. SPEND THEM ON PEGGY.",
	"LEVEL UP TO OPEN NEW COURTS.",
]


## The animated dots after LOADING: "", ".", "..", "..." over DOTS_S.
static func dots(t: float) -> String:
	return ".".repeat(int(floor(fposmod(t, DOTS_S) / DOTS_S * 4.0)) % 4)


## The stage on show at `pct` (0 … 100): the stages in quarters (the design's /26).
static func stage_for(stages: Array, pct: int) -> String:
	if stages.is_empty():
		return ""
	return str(stages[mini(stages.size() - 1, pct / 26)])


## The tip on show at second `t` of the screen (a new one every TIP_S), offset by `skip`.
static func tip_at(t: float, skip := 0) -> String:
	return str(TIPS[(int(floor(t / TIP_S)) + skip) % TIPS.size()])


## What the loader does at second `t` of a move: "wait" (loading, screen not
## needed yet), "show" (raise the screen), "hold" (loaded, but the screen has
## not been up MIN_SHOW_S), "finish" (change the scene now).
static func next_step(t: float, loaded: bool, shown_for: float) -> String:
	if shown_for < 0.0:
		if loaded:
			return "finish"
		return "show" if t >= SHOW_AFTER_S else "wait"
	if not loaded:
		return "wait"
	return "finish" if shown_for >= MIN_SHOW_S else "hold"


## The destination's copy: {dest, sub, stages, busy, tip_skip}. `busy` is
## the line under the pressed button's LOADING ("" → the button's own name:
## only the splash's CONTINUE / LET'S PLAY say what they are doing). `area` is the
## area's display name (ARCADE CAGE), `extra` a detail line (the league and
## opponent for a match).
static func dest(kind: String, area: String, extra := "") -> Dictionary:
	var a := area.to_upper()
	var build := "BUILDING THE %s" % _short(a)
	match kind:
		"new":
			return {"dest": a, "sub": "YOUR FIRST COURT", "busy": "SETTING UP YOUR GAME", "tip_skip": 0,
				"stages": ["CREATING YOUR PLAYER", build, "RACKING THE BALLS", "HANGING THE NET"]}
		"continue":
			return {"dest": a, "sub": "WHERE YOU LEFT OFF", "busy": "LOADING YOUR SAVE", "tip_skip": 0,
				"stages": ["READING YOUR SAVE", build, "RACKING THE BALLS", "HANGING THE NET"]}
		"heat":
			return {"dest": a, "sub": extra, "busy": "", "tip_skip": 1,
				"stages": [build, "LOADING %s" % (extra.get_slice("VS ", 1) if extra.contains("VS ") else "THE OPPONENT"), "SHUFFLING CARDS", "SETTING THE CLOCK"]}
		"trial", "practice":
			return {"dest": a, "sub": extra, "busy": "", "tip_skip": 2,
				"stages": [build, "RACKING THE BALLS", "HANGING THE NET", "SETTING THE CLOCK"]}
		"results", "postmatch":
			return {"dest": "RESULTS" if kind == "results" else "POST-MATCH", "sub": a, "busy": "", "tip_skip": 3,
				"stages": ["ADDING UP THE SCORE", "COUNTING TICKETS", build, "SETTING THE BOARD"]}
		"splash":
			return {"dest": "HOOP SHOOT LEAGUE", "sub": "", "busy": "", "tip_skip": 4,
				"stages": ["WARMING THE NEON", "HANGING THE SIGN", "SETTING THE LIGHTS", "READY"]}
		"credits":
			return {"dest": "CREDITS", "sub": "", "busy": "", "tip_skip": 4, "stages": ["ROLLING THE CREDITS"]}
	return {"dest": a, "sub": "HOME", "busy": "", "tip_skip": 4,
		"stages": [build, "RACKING THE BALLS", "HANGING THE NET", "TURNING ON THE LIGHTS"]}


## ARCADE CAGE → CAGE, BEACH → BEACH, CITY COURT → COURT: the word a stage line uses.
static func _short(area: String) -> String:
	var parts := area.split(" ", false)
	return parts[parts.size() - 1] if not parts.is_empty() else area
