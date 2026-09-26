class_name ShotSim
extends RefCounted
## Fixed-timestep shot simulator. Deterministic: no RNG in here — aim noise is
## injected upstream (player gesture / AI aim error), physics just resolves it.
## One implementation serves the player, the future live AI, and headless
## resolution. Ported line-faithfully from src/core/physics/shotSim.ts.
## LaunchParams Dictionary: { "angle_deg", "speed", "vz"?, "backspin"?,
##   "rx"?, "ry"?, "rz"?, "bx"?, "bz"?, "roll"? }.
## Without rx/ry/rz the shot leaves the canonical point (0, release_h, 0) along
## +x — byte-identical to the reference sim (golden fixtures depend on it).
## With them, the release origin is that point and the horizontal bearing is
## aimed from it at the hoop axis — unless bx/bz give an explicit bearing (the
## aim-by-pointing flick), which is used as-is. "vz" is lateral to the bearing.


## Cold streak (rim iced over): how long the ice holds a caught ball, how long
## it takes to settle into the hole, where it sits, and the pop-out velocity
## (toward the shooter, who stands at x < hoop_x).
const ICE_HOLD_S := 0.45
const ICE_SETTLE_S := 0.18
const ICE_TOP := 0.02
const ICE_SEAT_H := 0.07
const ICE_POP_VX := -1.6
const ICE_POP_VY := 3.0

static func create_shot(launch: Dictionary, geo: SimGeometry = null) -> BallState:
	var th: float = deg_to_rad(launch["angle_deg"])
	var s := BallState.new()
	s.geo = geo if geo != null else SimGeometry.regulation()
	if launch.has("rx") and launch.has("ry") and launch.has("rz"):
		s.rx = launch["rx"]
		s.ry = launch["ry"]
		s.rz = launch["rz"]
		s.pos = SimVec3.new(s.rx, s.ry, s.rz)
		var dx: float = s.geo.hoop_x - s.rx
		var dz: float = s.geo.hoop_z - s.rz
		var dist := sqrt(dx * dx + dz * dz)
		if dist > 1e-6:
			s.dir_x = dx / dist
			s.dir_z = dz / dist
		if launch.has("bx") and launch.has("bz"):
			var bx: float = launch["bx"]
			var bz: float = launch["bz"]
			var bl := sqrt(bx * bx + bz * bz)
			if bl > 1e-9:
				s.dir_x = bx / bl
				s.dir_z = bz / bl
		var c: float = launch["speed"] * cos(th)
		var vz: float = launch.get("vz", 0.0)
		s.vel = SimVec3.new(
			c * s.dir_x - vz * s.dir_z,
			launch["speed"] * sin(th),
			c * s.dir_z + vz * s.dir_x
		)
	else:
		s.ry = s.geo.release_h
		s.pos = SimVec3.new(0.0, s.geo.release_h, 0.0)
		s.vel = SimVec3.new(
			launch["speed"] * cos(th),
			launch["speed"] * sin(th),
			launch.get("vz", 0.0)
		)
	s.spin = launch.get("backspin", SimConstants.BACKSPIN_DEFAULT)
	s.roll = launch.get("roll", 0.0)
	return s


## Pure ballistic advance (no collision) — position is quadratic in dt.
static func _advance(s: BallState, dt: float) -> void:
	s.pos.x += s.vel.x * dt
	s.pos.z += s.vel.z * dt
	s.pos.y += s.vel.y * dt - 0.5 * SimConstants.G * dt * dt
	s.vel.y -= SimConstants.G * dt
	s.t += dt


## Bisect the sub-interval [0, dt] to land the ball just at first contact.
## Assumes no contact at t=0 and contact at t=dt. Leaves state at contact time
## and returns the contact (remaining time unused by the caller, as in the
## reference).
static func _bisect_to_contact(s: BallState, dt: float) -> Colliders.Contact:
	var start_pos := s.pos.clone()
	var start_vel := s.vel.clone()
	var start_t := s.t
	var lo := 0.0
	var hi := dt
	for i in 10:
		var mid := (lo + hi) / 2.0
		s.pos = start_pos.clone()
		s.vel = start_vel.clone()
		s.t = start_t
		_advance(s, mid)
		if Colliders.find_contact(s.pos, s.geo) != null:
			hi = mid
		else:
			lo = mid
	# Settle just before contact (lo), then report the contact found at hi.
	s.pos = start_pos.clone()
	s.vel = start_vel.clone()
	s.t = start_t
	_advance(s, lo)
	var probe_pos := s.pos.clone()
	var probe_vel := s.vel.clone()
	var probe_t := s.t
	_advance(s, hi - lo)
	var contact := Colliders.find_contact(s.pos, s.geo)
	if contact == null:
		# Numerical edge — keep the advanced state and carry on.
		return Colliders.Contact.new(Colliders.KIND_FLOOR, 0.0, 0.0, 1.0, 0.0, s.pos.x, s.pos.y, s.pos.z)
	s.pos = probe_pos
	s.vel = probe_vel
	s.t = probe_t
	return contact


static func _record_event(s: BallState, c: Colliders.Contact, impact: float) -> void:
	var ev := {
		"kind": c.kind,
		"t": s.t,
		"pos": {"x": s.pos.x, "y": s.pos.y, "z": s.pos.z},
		"normal": {"x": c.nx, "y": c.ny, "z": c.nz},
		"speed": impact,
	}
	if c.kind == Colliders.KIND_RIM:
		# Azimuth of the contact point around the hoop, measured from the shooter's
		# bearing: 0 = front (shooter side), 180 = back. For the canonical lane
		# (dir = 1, 0) this is atan2(|qz|, −(qx − hoop_x)).
		var rel_x: float = c.qx - s.geo.hoop_x
		var rel_z: float = c.qz - s.geo.hoop_z
		var along := -(rel_x * s.dir_x + rel_z * s.dir_z)
		var across := absf(rel_x * s.dir_z - rel_z * s.dir_x)
		ev["azimuth_deg"] = rad_to_deg(atan2(across, along))
	s.events.push_back(ev)


static func _horiz_dist_to_axis(x: float, z: float, hoop_x: float, hoop_z: float) -> float:
	var dx := x - hoop_x
	var dz := z - hoop_z
	return sqrt(dx * dx + dz * dz)


## Rim-plane crossing + make/in-and-out bookkeeping. Call with the pre-step position.
static func _update_cylinder_state(s: BallState, prev_x: float, prev_y: float, prev_z: float) -> void:
	var pos := s.pos
	var vel := s.vel
	# Downward crossing of the rim plane.
	var geo := s.geo
	if prev_y >= geo.hoop_y and pos.y < geo.hoop_y:
		var f := (prev_y - geo.hoop_y) / (prev_y - pos.y)
		var xi := prev_x + (pos.x - prev_x) * f
		var zi := prev_z + (pos.z - prev_z) * f
		if _horiz_dist_to_axis(xi, zi, geo.hoop_x, geo.hoop_z) < SimConstants.R_RIM:
			if geo.ice and not s.ice_caught and _touched_iron(s):
				# Iced over: a ball that has already rattled the rim or board is
				# grabbed by the ice instead of dropping in. A clean entry (a
				# would-be swish) passes through — the swish rule.
				s.ice_caught = true
				s.ice_hold_t = 0.0
				s.ice_catch = SimVec3.new(xi, geo.hoop_y + SimConstants.R_BALL * 0.55, zi)
				s.ice_seat = SimVec3.new(geo.hoop_x, geo.hoop_y + ICE_TOP + ICE_SEAT_H, geo.hoop_z)
				s.pos = SimVec3.new(s.ice_catch.x, s.ice_catch.y, s.ice_catch.z)
				s.vel = SimVec3.new(0.0, 0.0, 0.0)
				s.spin = 0.0
				s.events.push_back({
					"kind": "ice_catch", "t": s.t,
					"pos": {"x": xi, "y": geo.hoop_y, "z": zi},
					"normal": {"x": 0.0, "y": 1.0, "z": 0.0},
					"speed": vel.length(),
				})
				return
			s.in_cylinder = true
			if not s.ever_entered:
				# Presentation event: the ball just dropped into the rim. Same shape
				# as contact events so consumers can treat it uniformly. Physics is
				# unaffected (events are never read by the stepper).
				s.events.push_back({
					"kind": "enter", "t": s.t,
					"pos": {"x": xi, "y": geo.hoop_y, "z": zi},
					"normal": {"x": 0.0, "y": 1.0, "z": 0.0},
					"speed": vel.length(),
				})
			s.ever_entered = true
			if is_nan(s.entry_angle_deg):
				var vh := sqrt(vel.x * vel.x + vel.z * vel.z)
				s.entry_angle_deg = rad_to_deg(atan2(-vel.y, vh))
	# Popped back out the top (the heartbreaker).
	if prev_y < geo.hoop_y and pos.y >= geo.hoop_y and s.in_cylinder:
		s.in_cylinder = false

	# The net only has the ball once its centre is net_catch_depth below the
	# plane (0 for regulation = immediately). Above that it is still level with
	# the tube: the torus can throw it back out — a rattle-out.
	var in_net := geo.net_catch_depth <= 0.0 or pos.y < geo.hoop_y - geo.net_catch_depth
	if s.in_cylinder and not s.made and in_net:
		# Net drag while threading the cylinder.
		var k := exp(-SimConstants.NET_DRAG * SimConstants.SIM_DT)
		vel.x *= k
		vel.y *= k
		vel.z *= k
		# The net catches balls rattling sideways below the plane and funnels them down.
		var hd := _horiz_dist_to_axis(pos.x, pos.z, geo.hoop_x, geo.hoop_z)
		var max_r := SimConstants.R_RIM - SimConstants.R_BALL * 0.15
		if hd > max_r and pos.y < geo.hoop_y:
			var nx := (geo.hoop_x - pos.x) / hd
			var nz := (geo.hoop_z - pos.z) / hd
			var v_out := -(vel.x * nx + vel.z * nz)
			if v_out > 0.0:
				vel.x += (1.0 + SimConstants.E_NET_WALL) * v_out * nx
				vel.z += (1.0 + SimConstants.E_NET_WALL) * v_out * nz
	if s.in_cylinder and not s.made:
		if pos.y < geo.hoop_y - SimConstants.MAKE_DEPTH:
			s.made = true
			s.resolved = true


static func _update_resolution(s: BallState) -> void:
	var pos := s.pos
	# Dead-ball safety net: a ball resting anywhere off the floor (wedged,
	# balanced on the rim, whatever) is eventually dead — no rest state may
	# ever stall a rack.
	#
	# The budget is DEAD_BALL_S rather than the old half second so that a ball
	# balanced on the ring gets to topple off under its own weight instead of
	# blinking out of existence in mid-air at rim height. Measured: rim
	# balances shed themselves within ~0.85 s, so the cap is rarely reached,
	# and scoring is unaffected either way — the outcome is decided at
	# `resolved`, which these balls reach long before they stop moving.
	#
	# EXCEPT while the ball is threading the ring on its way down. The net drag
	# bleeds a softly-dropped ball below 0.4 m/s inside the cylinder, so this
	# rule used to kill it MID-DROP: a hang that was about to fall through
	# vanished in mid-air and scored as a miss. A descending ball inside the
	# cylinder cannot stall a rack — it reaches MAKE_DEPTH, pops back out the
	# top, or runs out MAX_SHOT_TIME below, which still applies unconditionally.
	var speed := s.vel.length()
	var threading := s.in_cylinder and s.vel.y <= 0.0
	if speed < 0.4 and pos.y > SimConstants.R_BALL * 1.5 and not threading:
		s.slow_time += SimConstants.SIM_DT
	else:
		s.slow_time = 0.0
	if s.slow_time > SimConstants.DEAD_BALL_S:
		s.settled = true
		s.resolved = true
		return
	if not s.resolved:
		# Provably dead: below the rim plane, outside the cylinder, heading down —
		# nothing (floor bounce included, e² capped) can climb back to 3.05 m.
		if pos.y < s.geo.hoop_y - 0.4 and not s.in_cylinder and s.vel.y < 0.0:
			s.resolved = true
		if s.floor_hits > 0:
			s.resolved = true
	# abs(z) bound added for first-person lateral shots (not in the 2D-era
	# reference): wide lateral bricks must resolve like long/short ones do.
	# Inside an enclosure the walls keep the ball on the court, so only the
	# time/bounce rules apply; open geometry culls far strays as before.
	var far := false
	if not s.geo.has_walls():
		far = (pos.x < s.rx - 3.0 or pos.x > s.geo.hoop_x + 3.0
			or minf(absf(pos.z - s.geo.hoop_z), absf(pos.z - s.rz)) > 4.0)
	if (
		s.floor_hits >= 3
		or s.t > SimConstants.MAX_SHOT_TIME
		or far
		or (s.floor_hits > 0 and s.vel.length() < 0.6)
	):
		s.settled = true
		s.resolved = true


## Resolve a contact in place: partial impulse, event log, projection out of penetration.
static func _resolve_in_place(s: BallState, contact: Colliders.Contact) -> void:
	var impact := Colliders.resolve_contact(s, contact)
	if not is_nan(impact):
		# Only meaningful hits become events — soft partial-impulse grazes (< ~0.4 m/s
		# effective) are one physical "rub" and would spam the log/sfx as dozens of hits.
		if impact > s.geo.rim_log_impact or contact.kind != Colliders.KIND_RIM:
			_record_event(s, contact, impact)
		if contact.kind == Colliders.KIND_FLOOR:
			s.floor_hits += 1
	# Project out of any residual penetration — graze-scaled impulses leave inward
	# velocity; this keeps the ball sliding on the tube surface, never through it.
	# Iterated because the ball can wedge into two colliders at once (back rim +
	# board corner): popping out of one must not leave it inside the other.
	for i in 4:
		var residual := Colliders.find_contact(s.pos, s.geo)
		if residual == null:
			break
		s.pos.x += residual.nx * (residual.depth + 1e-4)
		s.pos.y += residual.ny * (residual.depth + 1e-4)
		s.pos.z += residual.nz * (residual.depth + 1e-4)


## Has this ball touched the rim or board so far? (A clean entry has not.)
static func _touched_iron(s: BallState) -> bool:
	for ev in s.events:
		if ev["kind"] == Colliders.KIND_RIM or ev["kind"] == Colliders.KIND_BOARD:
			return true
	return false


## Cold streak hold: the caught ball settles into the ice's hole, sits for
## ICE_HOLD_S, then pops back out toward the shooter as the ice breaks (or at
## once if the ice is already gone). Deterministic, no RNG.
static func _step_ice_hold(s: BallState) -> void:
	s.t += SimConstants.SIM_DT
	s.ice_hold_t += SimConstants.SIM_DT
	var k := clampf(s.ice_hold_t / ICE_SETTLE_S, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	s.pos.x = s.ice_catch.x + (s.ice_seat.x - s.ice_catch.x) * k
	s.pos.y = s.ice_catch.y + (s.ice_seat.y - s.ice_catch.y) * k
	s.pos.z = s.ice_catch.z + (s.ice_seat.z - s.ice_catch.z) * k
	if s.ice_hold_t >= ICE_HOLD_S or not s.geo.ice:
		s.ice_popped = true
		s.vel = SimVec3.new(ICE_POP_VX, ICE_POP_VY, 0.0)
		s.spin = 0.0
		s.events.push_back({
			"kind": "ice_pop", "t": s.t,
			"pos": {"x": s.pos.x, "y": s.pos.y, "z": s.pos.z},
			"normal": {"x": 0.0, "y": 1.0, "z": 0.0},
			"speed": ICE_POP_VY,
		})


## Advance one fixed SIM_DT step. Deep first-touches bisect to the contact
## moment (fast flight → precise impact points); shallow penetrations — the
## common rubbing/rolling case with graze-scaled impulses — resolve in place,
## which keeps contact-heavy stretches cheap.
static func step_shot(s: BallState) -> void:
	if s.settled:
		return
	if s.ice_caught and not s.ice_popped:
		_step_ice_hold(s)
		return
	var prev_x := s.pos.x
	var prev_y := s.pos.y
	var prev_z := s.pos.z
	var t0 := s.t
	_advance(s, SimConstants.SIM_DT)
	var hit := Colliders.find_contact(s.pos, s.geo)
	if hit != null:
		if hit.depth > 0.006:
			# Deep hit mid-flight: rewind (undo gravity + time) and bisect to first touch.
			s.pos.x = prev_x
			s.pos.y = prev_y
			s.pos.z = prev_z
			s.vel.y += SimConstants.G * SimConstants.SIM_DT
			s.t -= SimConstants.SIM_DT
			var was_touching_at_start := Colliders.find_contact(s.pos, s.geo) != null
			if was_touching_at_start:
				# Started the step in contact — bisection's precondition fails; step and resolve in place.
				_advance(s, SimConstants.SIM_DT)
				var c := Colliders.find_contact(s.pos, s.geo)
				_resolve_in_place(s, c if c != null else hit)
			else:
				var contact := _bisect_to_contact(s, SimConstants.SIM_DT)
				_resolve_in_place(s, contact)
		else:
			_resolve_in_place(s, hit)
	_update_cylinder_state(s, prev_x, prev_y, prev_z)
	# Tunneling invariant: after resolution the ball must sit outside every collider.
	var residual := Colliders.find_contact(s.pos, s.geo)
	if residual != null and residual.depth > s.max_penetration:
		s.max_penetration = residual.depth
	_update_resolution(s)
	# Stall guard: a bisected contact that keeps landing at fraction ~0 makes no
	# time progress, so MAX_SHOT_TIME would never fire. A quarter second of
	# frozen time is a dead ball.
	if s.t - t0 < SimConstants.SIM_DT * 0.01:
		s.stall_steps += 1
		if s.stall_steps > 60:
			s.settled = true
			s.resolved = true
	else:
		s.stall_steps = 0


## Run a launch to completion and classify it. fast=true stops as soon as the
## outcome is decided (headless league/AI resolution).
static func simulate_shot(launch: Dictionary, fast := false, geo: SimGeometry = null) -> Dictionary:
	var s := create_shot(launch, geo)
	var max_steps := ceili(SimConstants.MAX_SHOT_TIME / SimConstants.SIM_DT) + 1
	for i in max_steps:
		step_shot(s)
		if s.settled:
			break
		if fast and s.resolved:
			break
	return ShotClassify.classify_shot(s)
