class_name FlickTuning
extends Resource
## Flick-feel tunables (defaults baked from Ross's on-device pass of 2026-09-14,
## the set he called "improved even more"; re-baked 2026-09-23 after a RESET
## on the phone wiped the device copy).
## Live-editable from the tuning overlay (keyboard on
## desktop; the touch strip on device when Tuning mode is on) and persisted by
## SaveService's "tuning" part. Bake values you settle on back into these
## defaults — the persisted part is a device-local scratchpad, not the source
## of truth.

## Field names in overlay order. Also the persistence whitelist.
const FIELDS: Array[String] = [
	"angle_low", "angle_high", "pull_full_frac",
	"flick_min_sh", "flick_max_sh",
	"side_dead_deg", "side_gain", "backspin_per_mps",
	"roll_dead", "roll_gain", "roll_max", "dead_zone_px",
	"travel_full_frac", "az_gain", "vz_max",
]

## ---- Wind-up model (the game) ------------------------------------------------

## Arc with NO wind-up: a quick flick straight from the pickup. Kept usable so
## a hurried shot is a shot, not a line drive.
@export var angle_low := 19.0
## Arc at a full pull-back.
@export var angle_high := 69.0
## Pull-back distance (fraction of viewport height) that reaches angle_high.
@export var pull_full_frac := 0.46
## Flick speed (screen-heights/sec) that maps to u=0 on the power curve.
@export var flick_min_sh := 2.15
## Flick speed (screen-heights/sec) that maps to u=1 (V_MAX).
@export var flick_max_sh := 4.6
## Sideways forgiveness: the release tilt off vertical is reduced — tilts within
## side_dead_deg are ignored as thumb wobble; beyond that, side_gain of the
## remainder carries (1.0 = full physical carry, which QA found unforgiving).
@export var side_dead_deg := 1.0
@export var side_gain := 0.7
## Backspin (rad/s) = backspin_per_mps × launch speed (m/s): a harder throw
## spins faster. 2.5 × the ideal arcade speed ≈ the reference's fixed 15 rad/s.
@export var backspin_per_mps := 3.7
## Visual roll (about the travel axis) from a curled gesture, forgiven like
## sideways aim: curl (rad/s) inside roll_dead is thumb wobble and ignored; the
## remainder × roll_gain, clamped to roll_max. Keeps a slightly hooked flick
## from corkscrewing the ball.
@export var roll_dead := 3.0
@export var roll_gain := 0.4
@export var roll_max := 12.0
## Minimum total finger travel (px) before a release counts as a gesture.
@export var dead_zone_px := 15.0

## ---- Legacy drag-length model only (flick lab, tests) -------------------------

## Upward travel (fraction of viewport height) that reaches angle_high.
@export var travel_full_frac := 0.45
## Sub-unity lateral gain: tilt forgiveness (1.0 = full tilt transfers).
@export var az_gain := 0.2
## Lateral velocity clamp, m/s.
@export var vz_max := 1.2


static func defaults() -> FlickTuning:
	return FlickTuning.new()


func to_dict() -> Dictionary:
	var d := {}
	for k in FIELDS:
		d[k] = float(get(k))
	return d


## Apply persisted values; unknown keys and non-numbers are ignored.
func apply_dict(d: Dictionary) -> void:
	for k in FIELDS:
		if d.has(k) and (d[k] is float or d[k] is int):
			set(k, float(d[k]))
