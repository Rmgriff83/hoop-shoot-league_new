class_name ShotTutorialCopy
extends RefCounted
## The first-shot tutorial's copy and clock (design "Shot Tutorial" 38a,
## 2026-10-24; docs/HOME.md → Shot tutorial), pure and headless: the five
## steps, the result lines for the live shot, the verdict a finished shot maps
## to, and the demo timeline — what the pixel finger does at second `t` of a
## step, in design px relative to the resting ball — which the overlay samples
## every frame and plays on the real ball. Mirrors the design's `demo()`.

const GREEN := Color("#73F28C")
const AMBER := Color("#FFC74D")
const RED := Color("#FF7373")
const GOLD := Color("#F0B84A")

## Where the finger starts its approach (design px, relative to the ball at rest).
const APPROACH_FROM := Vector2(80.0, 140.0)
## The deepest pull of the aim demo and of the flick demo (design px): from the
## lesson's rest point (time_trial_screen.LESSON_REST_Y) to just above the
## bottom edge — the pull a real shot takes, and an arc the band can carry.
const PULL_AIM := 320.0
const PULL_FLICK := 340.0
## The flick demo's nominal arc (the screen throws at the arc its pull showed).
const FLICK_ARC := 45.0

const STEPS := [
	{"id": "how", "title": "HOW TO SHOOT", "body": "Every shot starts from the ball at the bottom of the screen. Here's how to take one."},
	{"id": "pull", "title": "PULL DOWN TO AIM", "body": "Press the ball and drag down. Pull further for a higher arc. The dots show the path; the number is your arc."},
	{"id": "flick", "title": "FLICK UP TO SHOOT", "body": "Then flick up and let go. A faster flick means more power."},
	{"id": "read", "title": "READ YOUR SHOT", "body": "Over 100% is long, under is short.", "legend": true},
	{"id": "turn", "title": "YOUR TURN", "body": "Pull down on the ball, then flick up.", "live": true},
]

## The live step's result lines: verdict → [title, body].
const RESULT := {
	"swish": ["SWISH!", "That's it. You're ready to play."],
	"bank": ["BANK!", "In off the glass. You're ready to play."],
	"rim": ["OFF THE RIM", "So close. Flick a little faster."],
	"short": ["SHORT", "Flick a little faster and try again."],
	"long": ["LONG", "Flick a little softer and try again."],
}

## Step 4's readout cycle: [arc °, power %] every READ_CYCLE_S.
const READ_CYCLE := [[52.0, 100.0], [52.0, 112.0], [44.0, 78.0]]
const READ_CYCLE_S := 1.6
## The legend row: [label, colour].
const LEGEND := [["IN", GREEN], ["CLOSE", AMBER], ["MISS", RED]]

const CTA_NEXT := "NEXT"
const CTA_PLAY := "LET'S PLAY"
const HINT_WAITING := "TAKE A SHOT"
const HINT_FLYING := "..."


static func step_count() -> int:
	return STEPS.size()


static func step(i: int) -> Dictionary:
	return STEPS[clampi(i, 0, STEPS.size() - 1)]


static func is_live(i: int) -> bool:
	return bool(step(i).get("live", false))


static func is_make(verdict: String) -> bool:
	return verdict == "swish" or verdict == "bank"


## The verdict for a finished shot: its ShotClassify type, and — for an air
## ball or a board miss — whether the readout's power said short or long.
static func verdict(outcome_type: String, power_pct: float) -> String:
	match outcome_type:
		ShotClassify.SWISH:
			return "swish"
		ShotClassify.MAKE, ShotClassify.BANK, ShotClassify.SHOOTERS_ROLL:
			return "bank"
		ShotClassify.FRONT_RIM, ShotClassify.BACK_RIM, ShotClassify.SIDE_RIM, ShotClassify.IN_AND_OUT, ShotClassify.ICE_CAUGHT:
			return "rim"
		_:
			return "long" if power_pct > 100.0 else "short"


## The result card for a verdict: {title, body, color}.
static func result(verdict_: String) -> Dictionary:
	var r: Array = RESULT.get(verdict_, RESULT["short"])
	return {"title": str(r[0]), "body": str(r[1]), "color": GREEN if is_make(verdict_) else AMBER}


static func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## What the demo shows at second `t` of `step_i` (the design's demo()):
## {finger: Vector2 (design px from the ball at rest) or null, press: bool,
##  holding: bool (the ball is pressed), pull: float (px pulled down),
##  flick: bool (the finger is on its way up), release: bool (let go this
##  loop — the flick demo shoots once per loop), ripple: {s, op} or null,
##  loop: float (seconds into the loop; wraps), alpha: finger alpha}.
static func demo(step_i: int, t: float) -> Dictionary:
	var out := {"finger": null, "press": false, "holding": false, "pull": 0.0, "flick": false, "release": false, "ripple": null, "loop": 0.0, "alpha": 1.0}
	match step_i:
		0:
			var p := fmod(t, 1.4)
			out["loop"] = p
			out["finger"] = Vector2(6.0, 10.0 + sin(t * 4.0) * 6.0)
			out["ripple"] = {"s": 60.0 + p / 1.4 * 120.0, "op": 1.0 - p / 1.4}
		1, 4:
			var p := fmod(t, 2.6)
			out["loop"] = p
			var appr := _ease(p / 0.4)
			var pressed := p >= 0.45 and p < 2.3
			var pull := 0.0
			if p >= 0.5 and p < 1.7:
				pull = _ease((p - 0.5) / 1.2) * PULL_AIM
			elif p >= 1.7 and p < 2.3:
				pull = PULL_AIM
			elif p >= 2.3:
				pull = PULL_AIM * (1.0 - _ease((p - 2.3) / 0.3))
			out["finger"] = APPROACH_FROM * (1.0 - appr) + Vector2(0.0, pull)
			out["press"] = pressed
			out["holding"] = pressed
			out["pull"] = pull if pressed else 0.0
			if step_i == 4:
				out["alpha"] = 0.6
		2:
			var p := fmod(t, 3.8)
			out["loop"] = p
			var appr := _ease(p / 0.35)
			var pull := 0.0
			if p >= 0.4 and p < 1.2:
				pull = _ease((p - 0.4) / 0.8) * PULL_FLICK
			elif p >= 1.2:
				pull = PULL_FLICK
			if p < 1.5:
				out["finger"] = APPROACH_FROM * (1.0 - appr) + Vector2(0.0, pull)
				out["press"] = p >= 0.38
				out["holding"] = p >= 0.38
				out["pull"] = pull if p >= 0.38 else 0.0
			elif p < 1.66:
				var k := (p - 1.5) / 0.16
				out["finger"] = Vector2(0.0, PULL_FLICK - k * (PULL_FLICK + 110.0))
				out["press"] = true
				out["holding"] = true
				out["flick"] = true
				out["pull"] = PULL_FLICK
			else:
				var k := minf(1.0, (p - 1.66) / 0.3)
				out["finger"] = Vector2(0.0, -110.0 - k * 60.0) if k < 1.0 else null
				out["release"] = true
				out["alpha"] = 1.0 - k
		3:
			out["loop"] = fmod(t, READ_CYCLE_S * READ_CYCLE.size())
	return out


## Step 4's readout at second `t`: [arc, pct].
static func read_sample(t: float) -> Array:
	return READ_CYCLE[int(floor(t / READ_CYCLE_S)) % READ_CYCLE.size()]


## Every word the overlay can show, for the glyph check.
static func strings() -> PackedStringArray:
	var out := PackedStringArray()
	for s in STEPS:
		out.push_back(str(s["title"]))
		out.push_back(str(s["body"]))
	for k in RESULT:
		out.push_back(str(RESULT[k][0]))
		out.push_back(str(RESULT[k][1]))
	for l in LEGEND:
		out.push_back(str(l[0]))
	out.push_back(CTA_NEXT)
	out.push_back(CTA_PLAY)
	out.push_back(HINT_WAITING)
	out.push_back(HINT_FLYING)
	out.push_back("SKIP")
	out.push_back("%d / %d" % [STEPS.size(), STEPS.size()])
	return out
