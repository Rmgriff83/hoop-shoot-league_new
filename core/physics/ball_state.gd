class_name BallState
extends RefCounted
## Mutable state of one simulated ball in canonical shot space.
## Ported from src/core/physics/types.ts BallState.
## Events are Dictionaries: { "kind": String, "t": float, "pos": {x,y,z},
## "normal": {x,y,z}, "speed": float, "azimuth_deg": float (rim only) }.

var t := 0.0
var pos := SimVec3.new()
var vel := SimVec3.new()
## Hoop/board geometry the ball collides with. ShotSim never changes it (a
## bare simulate_shot is a fixed hoop); the TimeTrial rules re-point it at the
## live pose every step during the moving phase, so the ball meets the rim
## where the player sees it. Still deterministic — the pose is a pure function
## of move time.
var geo: SimGeometry
## Release origin (where the shooter let go). Defaults to the canonical
## (0, release_h, 0); the game passes the finger's world point instead.
var rx := 0.0
var ry := 0.0
var rz := 0.0
## Horizontal launch bearing (unit vector in the x/z plane) from the release
## origin toward the hoop axis. (1, 0) = the canonical +x lane.
var dir_x := 1.0
var dir_z := 0.0
## Scalar backspin, rad/s, about the horizontal axis perpendicular to the
## bearing: (−dir_z, 0, dir_x), i.e. world z for the canonical lane. Positive
## = backspin. The one 2D approximation kept from the reference: no spin about
## the travel axis from lateral flicks — negligible at |vz| ≤ 1.2 vs ~9 m/s.
var spin := 0.0
## Roll about the travel axis (dir_x, 0, dir_z), rad/s, from a curled flick.
## Presentational only: a spiral spin bends nothing (no air forces here, and
## it wouldn't in life either), so colliders ignore it.
var roll := 0.0
## Ball center is below rim plane inside the cylinder.
var in_cylinder := false
var ever_entered := false
var entry_angle_deg := NAN
var made := false
## Outcome is determined (made, or provably dead) — headless sims may stop here.
var resolved := false
## Ball is fully at rest / off-court — rendering may stop too.
var settled := false
var floor_hits := 0
## Seconds spent nearly motionless while airborne — dead-ball safety net.
var slow_time := 0.0
## Consecutive steps in which sim time failed to advance (a contact the
## bisection can't step past). Second safety net: MAX_SHOT_TIME can't fire if
## t never moves.
var stall_steps := 0
var events: Array[Dictionary] = []
var max_penetration := 0.0
## Cold streak: caught by the rim ice on a would-be make, held, then popped out.
var ice_caught := false
var ice_popped := false
var ice_hold_t := 0.0
var ice_catch := SimVec3.new()
var ice_seat := SimVec3.new()
## Card VORTEX (docs/CARDS.md): the rim's pull took the ball — it glides to
## the axis from `vortex_from` (at its own height when already inside the
## ring, else to a hover above the plane), then is released straight down.
var vortex_caught := false
var vortex_released := false
var vortex_below := false
var vortex_t := 0.0
var vortex_from := SimVec3.new()
