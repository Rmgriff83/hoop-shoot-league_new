class_name Colliders
extends RefCounted
## Analytic colliders. The rim is a true torus: contact = distance from ball
## center to the hoop circle < R_BALL + R_TUBE, via the closed-form
## nearest-point-on-circle test. This is what makes every miss archetype
## (front/back/side rim, in-and-out, shooter's roll, bank) emerge for free.
## Ported line-faithfully from src/core/physics/colliders.ts.

const KIND_RIM := "rim"
const KIND_BOARD := "board"
const KIND_FLOOR := "floor"
const KIND_WALL := "wall"
const KIND_POLE := "pole"
const KIND_PROP := "prop"


class Contact:
	var kind: String
	var depth: float
	## Unit normal pointing from the surface toward the ball center.
	var nx: float
	var ny: float
	var nz: float
	## Contact point on the surface.
	var qx: float
	var qy: float
	var qz: float

	func _init(p_kind: String, p_depth: float, p_nx: float, p_ny: float, p_nz: float, p_qx: float, p_qy: float, p_qz: float) -> void:
		kind = p_kind
		depth = p_depth
		nx = p_nx
		ny = p_ny
		nz = p_nz
		qx = p_qx
		qy = p_qy
		qz = p_qz


static func rim_contact(p: SimVec3, geo: SimGeometry) -> Contact:
	var dx := p.x - geo.hoop_x
	var dz := p.z - geo.hoop_z
	var horiz := sqrt(dx * dx + dz * dz)
	# Nearest point on the hoop circle to the ball center.
	var qx: float
	var qz: float
	if horiz < 1e-9:
		qx = geo.hoop_x + SimConstants.R_RIM
		qz = geo.hoop_z
	else:
		qx = geo.hoop_x + (dx / horiz) * SimConstants.R_RIM
		qz = geo.hoop_z + (dz / horiz) * SimConstants.R_RIM
	var ex := p.x - qx
	var ey := p.y - geo.hoop_y
	var ez := p.z - qz
	var d := sqrt(ex * ex + ey * ey + ez * ez)
	var min_d := SimConstants.R_BALL + SimConstants.R_TUBE
	if d >= min_d:
		return null
	var inv := 0.0 if d < 1e-9 else 1.0 / d
	return Contact.new(KIND_RIM, min_d - d, ex * inv, ey * inv, ez * inv, qx, geo.hoop_y, qz)


## Rim mounting bracket — sloped ribbon between the back rim and the board.
## Reported as 'board' (it's part of the board assembly): same sfx, and a
## bracket-aided make correctly classifies as a BANK.
static func bracket_contact(p: SimVec3, geo: SimGeometry) -> Contact:
	var abx := geo.bracket_x1 - geo.bracket_x0
	var aby := geo.bracket_y1 - geo.bracket_y0
	var t := clampf(
		((p.x - geo.bracket_x0) * abx + (p.y - geo.bracket_y0) * aby) / (abx * abx + aby * aby),
		0.0, 1.0
	)
	var qx := geo.bracket_x0 + abx * t
	var qy := geo.bracket_y0 + aby * t
	var qz := geo.hoop_z + clampf(p.z - geo.hoop_z, -SimConstants.BRACKET_HALF_W, SimConstants.BRACKET_HALF_W)
	var ex := p.x - qx
	var ey := p.y - qy
	var ez := p.z - qz
	var d := sqrt(ex * ex + ey * ey + ez * ez)
	if d >= SimConstants.R_BALL or d < 1e-9:
		return null
	# Gym rim: the neck is welded to the ring — same steel, same feel, a rim hit.
	var kind := KIND_RIM if geo.neck_is_rim else KIND_BOARD
	return Contact.new(kind, SimConstants.R_BALL - d, ex / d, ey / d, ez / d, qx, qy, qz)


## Board plate thickness (m) for edge/top contacts. The front face at board_x
## is what shots hit; the thickness only shapes the rounded top/side edges.
const BOARD_THICKNESS := 0.05


static func board_contact(p: SimVec3, geo: SimGeometry) -> Contact:
	var inside_face := (
		p.y >= geo.board_bottom and p.y <= geo.board_top and absf(p.z - geo.hoop_z) <= geo.board_half_w
	)
	if inside_face:
		# Front-face half-space — the reference's exact formula (golden fixtures).
		var depth := p.x + SimConstants.R_BALL - geo.board_x
		# Only the front face matters; ignore once well past the plane (can't happen in play).
		if depth <= 0.0 or depth > SimConstants.R_BALL:
			return null
		return Contact.new(KIND_BOARD, depth, -1.0, 0.0, 0.0, geo.board_x, p.y, p.z)
	# Off the face rectangle (above the top, beside a side, below the bottom): the
	# board is a thin box, and the contact is with the nearest point on its edge.
	# This keeps depth continuous as a ball crosses the top edge — the reference's
	# hard cutoff produced an instant deep contact there that pinned balls on the
	# rim of the board forever (sim time stalled, no timeout could fire).
	var qx := clampf(p.x, geo.board_x, geo.board_x + BOARD_THICKNESS)
	var qy := clampf(p.y, geo.board_bottom, geo.board_top)
	var qz := geo.hoop_z + clampf(p.z - geo.hoop_z, -geo.board_half_w, geo.board_half_w)
	var ex := p.x - qx
	var ey := p.y - qy
	var ez := p.z - qz
	var d := sqrt(ex * ex + ey * ey + ez * ez)
	if d >= SimConstants.R_BALL or d < 1e-9:
		return null
	return Contact.new(KIND_BOARD, SimConstants.R_BALL - d, ex / d, ey / d, ez / d, qx, qy, qz)


## The floor: flat at y 0, plus the arcade's ball-return ramp where the
## geometry has one (the deeper of the two wins at the crease). Without a
## geometry, or without a ramp, this is the original flat floor exactly.
static func floor_contact(p: SimVec3, geo: SimGeometry = null) -> Contact:
	var depth := SimConstants.R_BALL - p.y
	var best: Contact = null
	if depth > 0.0:
		best = Contact.new(KIND_FLOOR, depth, 0.0, 1.0, 0.0, p.x, 0.0, p.z)
	if geo != null and geo.has_ramp():
		var c := ramp_contact(p, geo)
		if c != null and (best == null or c.depth > best.depth):
			best = c
	return best


## The ball-return ramp: an inclined plane from the deck at ramp_x0 up to
## ramp_h at ramp_x1, full width. Its normal leans toward the shooter, so a
## ball that lands on it bounces and rolls down the slope. It is floor
## material (E_FLOOR / MU_FLOOR, ground torque), and its hits are floor hits.
static func ramp_contact(p: SimVec3, geo: SimGeometry) -> Contact:
	var run := geo.ramp_x1 - geo.ramp_x0
	var len := sqrt(run * run + geo.ramp_h * geo.ramp_h)
	var nx := -geo.ramp_h / len
	var ny := run / len
	# Signed distance from the plane through (ramp_x0, 0). In front of the
	# crease the plane runs below the deck, so a ball on the deck is clear.
	var d := (p.x - geo.ramp_x0) * nx + p.y * ny
	var depth := SimConstants.R_BALL - d
	if depth <= 0.0 or p.x > geo.ramp_x1 + SimConstants.R_BALL:
		return null
	return Contact.new(KIND_FLOOR, depth, nx, ny, 0.0, p.x - nx * d, p.y - ny * d, p.z)


## The in-ground pole behind the board: a vertical cylinder from the floor to
## pole_top. Null when the geometry has no pole.
static func pole_contact(p: SimVec3, geo: SimGeometry) -> Contact:
	if geo.pole_r <= 0.0 or p.y > geo.pole_top:
		return null
	var px := geo.board_x + geo.pole_off
	var dx := p.x - px
	var dz := p.z - geo.hoop_z
	var d := sqrt(dx * dx + dz * dz)
	var min_d := SimConstants.R_BALL + geo.pole_r
	if d >= min_d or d < 1e-9:
		return null
	var nx := dx / d
	var nz := dz / d
	return Contact.new(KIND_POLE, min_d - d, nx, 0.0, nz, px + nx * geo.pole_r, p.y, geo.hoop_z + nz * geo.pole_r)


## The enclosure's inside faces (cage mesh / fence) and roof. Returns the
## deepest penetrated face, or null.
static func wall_contact(p: SimVec3, geo: SimGeometry) -> Contact:
	var r := SimConstants.R_BALL
	var best: Contact = null
	var depth: float
	depth = p.x + r - geo.wall_x_max
	if depth > 0.0:
		best = Contact.new(KIND_WALL, depth, -1.0, 0.0, 0.0, geo.wall_x_max, p.y, p.z)
	depth = geo.wall_x_min + r - p.x
	if depth > 0.0 and (best == null or depth > best.depth):
		best = Contact.new(KIND_WALL, depth, 1.0, 0.0, 0.0, geo.wall_x_min, p.y, p.z)
	depth = p.z + r - geo.wall_z_max
	if depth > 0.0 and (best == null or depth > best.depth):
		best = Contact.new(KIND_WALL, depth, 0.0, 0.0, -1.0, p.x, p.y, geo.wall_z_max)
	depth = geo.wall_z_min + r - p.z
	if depth > 0.0 and (best == null or depth > best.depth):
		best = Contact.new(KIND_WALL, depth, 0.0, 0.0, 1.0, p.x, p.y, geo.wall_z_min)
	depth = p.y + r - geo.wall_y_max
	if depth > 0.0 and (best == null or depth > best.depth):
		best = Contact.new(KIND_WALL, depth, 0.0, -1.0, 0.0, p.x, geo.wall_y_max, p.z)
	var lip := lip_contact(p, geo)
	if lip != null and (best == null or lip.depth > best.depth):
		best = lip
	return best


## The tray lip: a thin box LIP_T deep behind lip_x, lip_h tall, full width.
## Contact with its nearest point (like the board's edge), so a ball rolling
## into its face is stopped and one dropping onto its top edge is deflected,
## never flung. Null without a lip.
const LIP_T := 0.06
static func lip_contact(p: SimVec3, geo: SimGeometry) -> Contact:
	if geo.lip_x == -INF or geo.lip_h <= 0.0:
		return null
	var qx := clampf(p.x, geo.lip_x - LIP_T, geo.lip_x)
	var qy := clampf(p.y, 0.0, geo.lip_h)
	var ex := p.x - qx
	var ey := p.y - qy
	var d := sqrt(ex * ex + ey * ey)
	if d >= SimConstants.R_BALL:
		return null
	if d < 1e-9:
		return Contact.new(KIND_WALL, SimConstants.R_BALL, 1.0, 0.0, 0.0, geo.lip_x, p.y, p.z)
	return Contact.new(KIND_WALL, SimConstants.R_BALL - d, ex / d, ey / d, 0.0, qx, qy, p.z)


## The court's solid props (geo.props: the speaker, the scoreboard): the deepest
## box the ball overlaps, contact with its nearest point so faces, edges and
## corners all push the right way. A centre caught inside a box is pushed
## out through its nearest face. Null without props or clear of them.
static func prop_contact(p: SimVec3, geo: SimGeometry) -> Contact:
	var best: Contact = null
	for b in geo.props:
		var qx := clampf(p.x, b["x0"], b["x1"])
		var qy := clampf(p.y, b["y0"], b["y1"])
		var qz := clampf(p.z, b["z0"], b["z1"])
		var ex := p.x - qx
		var ey := p.y - qy
		var ez := p.z - qz
		var d := sqrt(ex * ex + ey * ey + ez * ez)
		var c: Contact = null
		if d >= SimConstants.R_BALL:
			continue
		if d < 1e-9:
			# Inside: out through the nearest face.
			var dx: float = minf(p.x - b["x0"], b["x1"] - p.x)
			var dy: float = minf(p.y - b["y0"], b["y1"] - p.y)
			var dz: float = minf(p.z - b["z0"], b["z1"] - p.z)
			if dx <= dy and dx <= dz:
				var sx := 1.0 if b["x1"] - p.x < p.x - b["x0"] else -1.0
				c = Contact.new(KIND_PROP, SimConstants.R_BALL + dx, sx, 0.0, 0.0, b["x1"] if sx > 0.0 else b["x0"], p.y, p.z)
			elif dy <= dz:
				var sy := 1.0 if b["y1"] - p.y < p.y - b["y0"] else -1.0
				c = Contact.new(KIND_PROP, SimConstants.R_BALL + dy, 0.0, sy, 0.0, p.x, b["y1"] if sy > 0.0 else b["y0"], p.z)
			else:
				var sz := 1.0 if b["z1"] - p.z < p.z - b["z0"] else -1.0
				c = Contact.new(KIND_PROP, SimConstants.R_BALL + dz, 0.0, 0.0, sz, p.x, p.y, b["z1"] if sz > 0.0 else b["z0"])
		else:
			c = Contact.new(KIND_PROP, SimConstants.R_BALL - d, ex / d, ey / d, ez / d, qx, qy, qz)
		if best == null or c.depth > best.depth:
			best = c
	return best


## A floor contact on the ramp's slope (its normal leans; the deck's is up).
static func is_ramp(c: Contact) -> bool:
	return c.kind == KIND_FLOOR and c.ny < 1.0


static func find_contact(p: SimVec3, geo: SimGeometry) -> Contact:
	var c := rim_contact(p, geo)
	if c != null:
		return c
	c = bracket_contact(p, geo)
	if c != null:
		return c
	c = board_contact(p, geo)
	if c != null:
		return c
	c = pole_contact(p, geo)
	if c != null:
		return c
	c = prop_contact(p, geo)
	if c != null:
		return c
	c = wall_contact(p, geo)
	if c != null:
		return c
	return floor_contact(p, geo)


## Restitution per surface. Rim/board come from the geometry so an arcade
## machine can bounce differently from the regulation spec (whose golden
## fixtures depend on SimConstants exactly — regulation() carries those values).
static func _material_e(kind: String, geo: SimGeometry) -> float:
	match kind:
		KIND_RIM: return geo.rim_e
		KIND_BOARD: return geo.board_e
		KIND_POLE: return geo.board_e
		KIND_WALL: return geo.wall_e
		KIND_PROP: return geo.prop_e
		_: return SimConstants.E_FLOOR


static func _material_mu(kind: String, geo: SimGeometry) -> float:
	match kind:
		KIND_RIM: return geo.rim_mu
		KIND_WALL, KIND_PROP: return geo.wall_mu
		KIND_BOARD: return SimConstants.MU_BOARD
		_: return SimConstants.MU_FLOOR


## Fraction of spin RETAINED after a square hit (κ-scaled).
static func _material_spin_decay(kind: String, geo: SimGeometry) -> float:
	match kind:
		KIND_RIM: return geo.rim_spin_decay
		KIND_BOARD: return SimConstants.SPIN_DECAY_BOARD
		# Reference quirk preserved: floor uses SPIN_DECAY_RIM (the constant).
		_: return SimConstants.SPIN_DECAY_RIM


## Impulse response: restitution along the normal, friction against tangential
## slip (including backspin surface velocity — this is shooter's touch: backspin
## deadens the ball off the front rim), then spin decay.
## Mutates vel/spin. Returns impact speed for sfx, or NAN if already separating.
static func resolve_contact(state: BallState, c: Contact) -> float:
	var v := state.vel
	var vn := v.x * c.nx + v.y * c.ny + v.z * c.nz
	if vn >= 0.0:
		return NAN
	var impact := absf(vn)

	# Rim contacts scale by "commitment": κ = how head-on the ball's path is to
	# the tube (impact parameter). A real ball deforms — a tangential kiss off
	# the tube top transfers almost nothing and the ball rubs on in, while a
	# head-on catch gets the full clang. Without this, zero-depth grazes off the
	# front rim launch balls over the hoop (rigid-body over-reaction).
	var kappa := 1.0
	if c.kind == KIND_RIM:
		var speed := v.length()
		if speed > 1e-6:
			var cos_in := -vn / speed  # 1 = dead head-on into the tube
			kappa = cos_in * cos_in

	# Normal restitution (the ramp's slope has its own, softer bounce).
	var e := state.geo.ramp_e if is_ramp(c) else _material_e(c.kind, state.geo)
	var j := (1.0 + e * kappa) * kappa * vn
	v.x -= j * c.nx
	v.y -= j * c.ny
	v.z -= j * c.nz

	# Surface velocity from spin ω = w·(ax, 0, az) at the contact offset
	# r = −R_BALL·n, i.e. s = −R·(ω × n). The spin axis is perpendicular to the
	# launch bearing: (ax, az) = (−dir_z, dir_x), which is world z (0, 1) for the
	# canonical lane — there every term collapses to the reference's 2D form.
	var w := state.spin
	var ax := -state.dir_z
	var az := state.dir_x
	var sx := w * SimConstants.R_BALL * az * c.ny * SimConstants.SPIN_KICK
	var sy := -w * SimConstants.R_BALL * (az * c.nx - ax * c.nz) * SimConstants.SPIN_KICK
	var sz := -w * SimConstants.R_BALL * ax * c.ny * SimConstants.SPIN_KICK
	# Relative slip at the contact point, tangential part only.
	var rx := v.x + sx
	var ry := v.y + sy
	var rz := v.z + sz
	var rn := rx * c.nx + ry * c.ny + rz * c.nz
	rx -= rn * c.nx
	ry -= rn * c.ny
	rz -= rn * c.nz
	var mu := _material_mu(c.kind, state.geo) * kappa
	v.x -= mu * rx
	v.y -= mu * ry
	v.z -= mu * rz

	state.spin *= 1.0 - (1.0 - _material_spin_decay(c.kind, state.geo)) * kappa

	# Floor friction also TORQUES the ball. Above, the contact slip only ever
	# bled the ball's PATH (v -= mu * r) while spin merely decayed, so a ball
	# landed with backspin and kept spinning the way it was thrown. Real ground
	# friction drives it toward rolling instead.
	#
	# FLOOR ONLY, deliberately: every other surface stays byte-identical, and a
	# shot is already `resolved` the moment floor_hits > 0, so nothing here can
	# move a score. Rolling means the contact point is stationary, w = -v_t/R
	# about the same axis `spin` already uses.
	if c.kind == KIND_FLOOR:
		var v_t := v.x * state.dir_x + v.z * state.dir_z
		var w_roll := -v_t / SimConstants.R_BALL
		state.spin += (w_roll - state.spin) * SimConstants.FLOOR_SPIN_GRIP
	return impact * kappa
