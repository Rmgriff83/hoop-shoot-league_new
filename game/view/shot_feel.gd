class_name ShotFeel
extends RefCounted
## The wind-up READS on the held ball (Ross, design "Shot Feel Sandbox" 44a,
## 2026-10-27): the deeper the pull, the further the ball slides back along
## the camera ray toward you — still under the finger, but larger by real
## perspective — it rolls backward with the drag, and a cancelled grab eases
## back. Presentation only: the screen's hand point stays the release origin,
## the arc's and the readout's anchor; the sim never sees any of this. Pure
## maths so the numbers live in one place and test headless. The sandbox's px
## are the band's px (its phone is the 720-wide design frame, the space
## FlickInput measures the pull in).

const PULL_FULL_PX := 270.0      # wind-up for the full effect
const PULL_DEPTH_M := 0.32       # slide back along the camera ray at full pull
const PULL_EXTRA_SCALE := 0.04   # on top of perspective at full pull
const ROLL_WITH_DRAG := 0.6      # × true rolling (Δy / r), about the spot's right
const HELD_SPIN_RPM := 0.0       # idle backspin at full pull while held
const SETTLE_S := 0.08           # a cancelled grab eases back (cubic out)
## The release (Ross, 2026-10-28): the flight ball starts where the held
## ball was drawn and eases to the sim's own pose in this long (cubic out),
## so the first flight frame never snaps. The size itself follows the
## finger's LIVE pull (FlickInput.pull_changed), so the shrink starts the
## instant the flick turns up and most of it is done by lift-off; this only
## finishes what is left. (A latched pull held the ball big through the
## flick, which read as lag whatever this number was.)
const RELEASE_S := 0.08


## The pull as a fraction of the full effect.
static func frac(pull_px: float) -> float:
	return clampf(pull_px / PULL_FULL_PX, 0.0, 1.0)


## EASE OUT: most of the movement comes early in the pull.
static func curve(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)


static func depth(pull_px: float) -> float:
	return PULL_DEPTH_M * curve(frac(pull_px))


static func scale(pull_px: float) -> float:
	return 1.0 + PULL_EXTRA_SCALE * curve(frac(pull_px))


## Where the ball draws: `depth_m` nearer the camera along the camera→hand
## ray, so it stays under the finger.
static func held_pos(cam: Vector3, hand: Vector3, depth_m: float) -> Vector3:
	var to_hand := hand - cam
	var dist := to_hand.length()
	if dist <= 1e-6:
		return hand
	return cam + to_hand / dist * maxf(dist - depth_m, 0.0)


## The roll a drag step adds (radians about the spot's right): the ball turns
## as if it rolled down the palm. `dy_m` = the hand's previous y − its new y,
## positive pulling down. Only the pull rolls it (Ross, 2026-10-28): a step
## back up — the flick itself, or easing the pull — adds nothing, so the ball
## leaves the hand with the roll the pull gave it and the sim's backspin
## carries on the same way instead of the flick unwinding it first.
static func roll_delta(dy_m: float) -> float:
	return ROLL_WITH_DRAG * maxf(dy_m, 0.0) / SimConstants.R_BALL


## The settle's progress 0 → 1 (cubic out) at `k` = t / SETTLE_S.
static func settle(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return 1.0 - (1.0 - k) * (1.0 - k) * (1.0 - k)


## The idle backspin's angle over `dt` at this pull (0 with HELD_SPIN_RPM 0).
static func held_spin_rad(pull_frac: float, dt: float) -> float:
	return HELD_SPIN_RPM * clampf(pull_frac, 0.0, 1.0) * TAU / 60.0 * dt
