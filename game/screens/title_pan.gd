class_name TitlePan
extends RefCounted
## The home screen's slow camera pan over an area: a fixed look target (the
## hoop, roughly) and a camera that trucks back and forth along `drift`
## around `cam_pos` on a sine, with a faint vertical bob. Pure math, so the
## pose at any second is testable and a QA screenshot reproduces. The five
## numbers per area live on its ArenaSet (`title_*`, docs/HOME.md).

const BOB_M := 0.06
## The bob runs three times per truck: not a metronome on it, and the whole
## loop still closes exactly at one period.
const BOB_RATIO := 1.0 / 3.0


static func spec_of(arena: ArenaSet) -> Dictionary:
	return {"cam_pos": arena.title_cam_pos, "look_at": arena.title_look_at, "drift": arena.title_drift,
		"period_s": maxf(arena.title_period_s, 1.0), "fov": arena.title_fov}


## → {pos: Vector3, look: Vector3} at time t (seconds since the card opened).
static func pose(spec: Dictionary, t: float) -> Dictionary:
	var period := maxf(float(spec.get("period_s", 28.0)), 1.0)
	var cam: Vector3 = spec.get("cam_pos", Vector3(-1.65, 2.0, -0.55))
	var drift: Vector3 = spec.get("drift", Vector3(0.05, 0.0, 0.5))
	var pos := cam + drift * sin(TAU * t / period)
	pos.y += BOB_M * sin(TAU * t / (period * BOB_RATIO))
	return {"pos": pos, "look": spec.get("look_at", Vector3(2.9, 1.55, 0.2))}
