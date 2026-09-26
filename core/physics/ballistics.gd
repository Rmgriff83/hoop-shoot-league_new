class_name Ballistics
extends RefCounted
## Closed-form projectile math for the canonical shot. Used by the flick lab's
## make-band curve, the future AI ideal-shot solver, and as ground truth for
## tests (reproduces the handoff §3 table).
## LaunchParams is a Dictionary: { "angle_deg": float, "speed": float,
## "vz": float (optional, default 0), "backspin": float (optional) }.

## Rim-center drop relative to release: 3.05 − 2.10 = 0.95 m.
const RIM_DROP := SimConstants.RIM_HEIGHT - SimConstants.RELEASE_HEIGHT


## Release speed (m/s) that passes through a point `dist` ahead and `rise`
## above the release, at launch angle `angle_deg`. NAN when unreachable.
static func speed_for_angle(angle_deg: float, dist := SimConstants.SHOT_DIST, rise := RIM_DROP) -> float:
	var th := deg_to_rad(angle_deg)
	var c := cos(th)
	var reach := dist * tan(th) - rise
	if c <= 0.0 or reach <= 0.0:
		return NAN
	var v2 := (SimConstants.G * dist * dist) / (2.0 * c * c * reach)
	return sqrt(v2)


## Time to cover `dist` horizontally.
static func flight_time(angle_deg: float, speed: float, dist := SimConstants.SHOT_DIST) -> float:
	return dist / (speed * cos(deg_to_rad(angle_deg)))


## Apex height above the floor.
static func apex_height(angle_deg: float, speed: float) -> float:
	var vy := speed * sin(deg_to_rad(angle_deg))
	return SimConstants.RELEASE_HEIGHT + (vy * vy) / (2.0 * SimConstants.G)


## Downward entry angle (deg) when crossing the rim plane at `dist`.
static func entry_angle(angle_deg: float, speed: float, dist := SimConstants.SHOT_DIST) -> float:
	var th := deg_to_rad(angle_deg)
	var vx := speed * cos(th)
	var t := dist / vx
	var vy := speed * sin(th) - SimConstants.G * t
	return rad_to_deg(atan2(-vy, vx))


## The perfect shot at this angle: dead-center through the rim. Empty Dictionary
## when the angle can't reach the rim.
static func ideal_launch(angle_deg: float) -> Dictionary:
	var speed := speed_for_angle(angle_deg)
	if is_nan(speed):
		return {}
	return {"angle_deg": angle_deg, "speed": speed}


## Ideal launch for an explicit geometry (arcade distances, moving board).
static func ideal_launch_for(angle_deg: float, geo: SimGeometry) -> Dictionary:
	var speed := speed_for_angle(angle_deg, geo.hoop_x, geo.rise)
	if is_nan(speed):
		return {}
	return {"angle_deg": angle_deg, "speed": speed}


## Analytic arc position at time t (no collisions).
static func arc_point(launch: Dictionary, t: float) -> SimVec3:
	var th: float = deg_to_rad(launch["angle_deg"])
	var vx: float = launch["speed"] * cos(th)
	var vy: float = launch["speed"] * sin(th)
	var vz: float = launch.get("vz", 0.0)
	return SimVec3.new(
		vx * t,
		SimConstants.RELEASE_HEIGHT + vy * t - 0.5 * SimConstants.G * t * t,
		vz * t
	)
