class_name SimGeometry
extends RefCounted
## Runtime hoop/board geometry. The sim reads geometry from here (frozen onto
## each BallState at launch) instead of constants, because the arcade board
## MOVES in depth as a difficulty mechanic. Ball/rim/tube radii and all
## material tuning stay in SimConstants — collision feel is geometry-independent.
## Scalar float64 fields only (core rule: no Vector3 under core/).

var hoop_x: float
## Lateral rim offset (sim +z = shooter's right). 0.0 for every canonical
## geometry; the arcade figure-8 moving phase slides it. Every collider is
## written relative to it so hoop_z = 0 is numerically identical to before.
var hoop_z: float = 0.0
var hoop_y: float
var release_h: float
var board_half_w: float
var board_bottom: float
var board_top: float

# Derived (same rim-relative relations as the original constants).
var board_x: float
var bracket_x0: float
var bracket_x1: float
var bracket_y0: float
var bracket_y1: float
var net_exit_y: float
var rise: float
## Surface restitution. Regulation keeps SimConstants exactly (golden fixtures);
## the arcade machine's rim is livelier — see ARCADE_RIM_E.
var rim_e: float = SimConstants.E_RIM
var board_e: float = SimConstants.E_BOARD
## Rim friction and spin retained per square hit (regulation: 0.12 / 0.55).
var rim_mu: float = SimConstants.MU_RIM
var rim_spin_decay: float = SimConstants.SPIN_DECAY_RIM
## Gym-rim feel (regulation keeps the original behaviour byte-exact):
## - neck_is_rim: the ring-to-board neck ribbon is part of the rim — rim
##   material + glance forgiveness, and its hits are rim hits (BACK_RIM),
##   not backboard banks.
## - net_catch_depth: how far below the rim plane the ball's centre must be
##   before the net's drag/wall take it. 0 = the moment it crosses the plane
##   (original: no rattle-outs possible); a ball radius = it can still bounce
##   off the inside of the tube and pop out — real rattles.
## - rim_log_impact: softest rim hit (m/s, effective) that counts as a contact
##   event; lower logs the rubs of a rattle-in so it classifies as a roll.
var neck_is_rim: bool = false
var net_catch_depth: float = 0.0
var rim_log_impact: float = 0.4
## Cold streak: the rim is iced over (ShotSim catches would-be makes). Off by
## default so every preset and the golden fixtures are unaffected.
var ice := false
## Card VORTEX (docs/CARDS.md): the rim pulls any ball that has touched iron
## or board through. Off by default, so no preset or fixture sees it.
var vortex := false
## Net material. Regulation / arcade / beach keep SimConstants exactly (the
## golden fixtures run the nylon numbers); the city's CHAIN net is lighter on
## the ball and stiffer at the wall — see CHAIN_NET_DRAG.
var net_drag: float = SimConstants.NET_DRAG
var net_wall_e: float = SimConstants.E_NET_WALL
## Environment colliders (scalar, optional). Walls are the INSIDE faces of an
## axis-aligned enclosure around the court (±INF = no wall; wall_y_max is a
## roof). The pole is a vertical cylinder `pole_off` behind the board face,
## radius pole_r (0 = none), from the floor up to pole_top. Regulation has
## none of these (golden fixtures); the arcade cage and beach fence do.
var wall_x_min: float = -INF
var wall_x_max: float = INF
var wall_z_min: float = -INF
var wall_z_max: float = INF
var wall_y_max: float = INF
var wall_e: float = 0.45
var wall_mu: float = 0.3
var pole_r: float = 0.0
var pole_off: float = 0.3
var pole_top: float = 0.0
## The arcade cabinet's ball-return ramp (the Ramp quad in
## tools/blender/build_cage.py): the floor rises from y 0 at ramp_x0 to
## ramp_h at ramp_x1 (the back wall), full width. ramp_h 0 = a flat floor
## everywhere (regulation, beach, city — the golden fixtures never see it).
## With a ramp the ball is let ROLL instead of being dropped on its third
## floor hit: on the slope it never settles, on the deck in front it rolls
## against deck_roll_decel (m/s²) until it is slower than the rest speed.
## Floor hits softer than floor_log_impact (m/s) are not logged, so a rolling
## ball does not spam contact events (and bounce sounds) every step.
var ramp_x0: float = 0.0
var ramp_x1: float = 0.0
var ramp_h: float = 0.0
## The slope's restitution (the deck keeps E_FLOOR): the cabinet's return
## channel is padded, so a ball dropping onto it does not rocket back at the
## shooter the way a hardwood floor would send it.
var ramp_e: float = SimConstants.E_FLOOR
var deck_roll_decel: float = 0.0
var floor_log_impact: float = 0.0
## The tray lip at the front of the deck (the TrayLip box in build_cage.py):
## a low wall of height lip_h at lip_x that stops a roll-out in front of the
## shooter. -INF = none.
var lip_x: float = -INF
var lip_h: float = 0.0
## Solid props on the court: axis-aligned boxes the ball bounces off (the
## city's floor speaker and tabletop scoreboard). Each is a Dictionary
## {x0, x1, y0, y1, z0, z1} in sim metres (scalars only — no Vector3 under
## core/). Empty everywhere but the city (golden fixtures). prop_e is their
## restitution (wood / plastic: duller than a backboard, livelier than foam).
var props: Array = []
var prop_e: float = 0.5

## Arcade rim feel (regulation E_RIM 0.32, MU_RIM 0.12, SPIN_DECAY_RIM 0.55).
## Tuned with Ross on-device 2026-09-12: livelier bounce, less grab, spin
## survives contacts longer. The backboard keeps its SimConstants values.
## The cage's ball-return ramp (2026-10-03): flat deck to x 3.5, then a
## 0.9 m rise to the back wall at 4.4 — build_cage.py RAMP_X0 / RAMP_TOP_Y.
## The deck in front rolls like a rubber mat (2 m/s²: a 2 m/s roll stops in
## a metre) and only floor hits above 0.35 m/s log a bounce.
## The back wall the ball bounces off: the peaks of the egg-crate foam over
## the panel (build_cage.py PAD_FACE_X − PAD_DEPTH = 4.31), not the panel
## itself at 4.4. The ramp still runs to the panel behind the foam.
const ARCADE_BACK_X := 4.31
const ARCADE_RAMP_X0 := 3.5
const ARCADE_RAMP_H := 0.9
const ARCADE_RAMP_E := 0.35
const ARCADE_DECK_ROLL_DECEL := 2.0
const ARCADE_FLOOR_LOG_IMPACT := 0.35
## The tray lip (build_cage.py DECK_X0 / TrayLip 0.45 tall) catches the
## roll-out at the shooter's feet.
const ARCADE_LIP_X := -0.4
const ARCADE_LIP_H := 0.45
## The front console the shooter leans on (build_cage.py CONSOLE_X0/X1/Y0/Y1).
const ARCADE_CONSOLE_X0 := 0.2
const ARCADE_CONSOLE_X1 := 0.8
const ARCADE_CONSOLE_Y0 := 0.3
const ARCADE_CONSOLE_Y1 := 1.0
const ARCADE_RIM_E := 0.38
const ARCADE_RIM_MU := 0.08
const ARCADE_RIM_SPIN_DECAY := 0.70
## Gym rim on the arcade machine: one-piece ring + neck, net catches only once
## the ball is fully through the ring, soft rubs logged.
const ARCADE_NET_CATCH_DEPTH := SimConstants.R_BALL
const ARCADE_RIM_LOG_IMPACT := 0.2
## The beach ring is the unforgiving one: 33 % livelier than the cage's, so it
## kicks bricks out further and drops fewer rattles. Everything you see and
## hear follows from this one number — see rim_rigidity().
const BEACH_RIM_E := ARCADE_RIM_E * 1.33
## The city park ring is bouncier still: 15 % over the beach's (Ross, 2026-10-05).
const CITY_RIM_E := BEACH_RIM_E * 1.15
## Beach practice hoop distance: 17.5 % farther than the arcade base pose.
const BEACH_DIST := 2.9 * 1.175
## Chain net (the city court): steel links weigh ~10x nylon and neither drape
## nor grip, so the ball keeps more of its speed through the funnel (drag
## 2.6 → 1.6: it sheds ~40 % less speed per second and exits sooner) and a
## sideways rattle meets a stiff ring of links that throws it back at the
## axis harder (wall e 0.08 → 0.20). The catch depth stays the gym rim's: a
## chain hangs from the same ring, and a rattle-out is still a rattle-out.
const CHAIN_NET_DRAG := 1.6
const CHAIN_NET_WALL_E := 0.20
## City court hoop distance: 25 % farther than the arcade base pose.
const CITY_DIST := 2.9 * 1.25


func _init(p_hoop_x: float, p_hoop_y: float, p_release_h: float,
		p_board_half_w: float, p_board_bottom: float, p_board_top: float,
		p_hoop_z: float = 0.0) -> void:
	hoop_x = p_hoop_x
	hoop_z = p_hoop_z
	hoop_y = p_hoop_y
	release_h = p_release_h
	board_half_w = p_board_half_w
	board_bottom = p_board_bottom
	board_top = p_board_top
	board_x = hoop_x + SimConstants.BOARD_OFFSET
	bracket_x0 = hoop_x + SimConstants.R_RIM - 0.01
	bracket_x1 = board_x
	bracket_y0 = hoop_y
	bracket_y1 = hoop_y + 0.15
	net_exit_y = hoop_y - 0.6
	rise = hoop_y - release_h
	rim_e = SimConstants.E_RIM
	board_e = SimConstants.E_BOARD
	rim_mu = SimConstants.MU_RIM
	rim_spin_decay = SimConstants.SPIN_DECAY_RIM


## Clone at a new hoop pose (distance + lateral offset), preserving rim
## height / release / board dimensions / materials. The moving-board mechanic
## slides the pose through this; derived fields (board_x, brackets, rise)
## re-derive in _init.
func with_pose(dist: float, lateral: float) -> SimGeometry:
	var g := SimGeometry.new(dist, hoop_y, release_h, board_half_w, board_bottom, board_top, lateral)
	g.ice = ice
	g.vortex = vortex
	g.net_drag = net_drag
	g.net_wall_e = net_wall_e
	g.rim_e = rim_e
	g.board_e = board_e
	g.rim_mu = rim_mu
	g.rim_spin_decay = rim_spin_decay
	g.neck_is_rim = neck_is_rim
	g.net_catch_depth = net_catch_depth
	g.rim_log_impact = rim_log_impact
	g.wall_x_min = wall_x_min
	g.wall_x_max = wall_x_max
	g.wall_z_min = wall_z_min
	g.wall_z_max = wall_z_max
	g.wall_y_max = wall_y_max
	g.wall_e = wall_e
	g.wall_mu = wall_mu
	g.pole_r = pole_r
	g.pole_off = pole_off
	g.pole_top = pole_top
	g.ramp_x0 = ramp_x0
	g.ramp_x1 = ramp_x1
	g.ramp_h = ramp_h
	g.ramp_e = ramp_e
	g.deck_roll_decel = deck_roll_decel
	g.floor_log_impact = floor_log_impact
	g.lip_x = lip_x
	g.lip_h = lip_h
	g.props = props.duplicate(true)
	g.prop_e = prop_e
	return g


## Clone with the rim iced over (or not), same pose. While iced a ball that
## would drop through the rim is caught by the ice instead and popped back
## out (ShotSim) — the cold-streak mechanic.
func with_ice(on: bool) -> SimGeometry:
	var g := with_pose(hoop_x, hoop_z)
	g.ice = on
	return g


## Clone with the VORTEX card on (or off), same pose: ShotSim pulls a ball
## that has touched iron or board through the ring.
func with_vortex(on: bool) -> SimGeometry:
	var g := with_pose(hoop_x, hoop_z)
	g.vortex = on
	return g


## Does this geometry have an enclosure at all?
func has_walls() -> bool:
	return wall_x_max < INF or wall_x_min > -INF or wall_z_max < INF or wall_z_min > -INF


func has_ramp() -> bool:
	return ramp_h > 0.0 and ramp_x1 > ramp_x0


func has_props() -> bool:
	return not props.is_empty()


## Height of the floor surface at x (the ramp's slope, 0 on the deck).
func floor_height(x: float) -> float:
	if not has_ramp() or x <= ramp_x0:
		return 0.0
	return ramp_h * (minf(x, ramp_x1) - ramp_x0) / (ramp_x1 - ramp_x0)


## Clone at a new hoop distance, keeping the current lateral offset.
func with_distance(dist: float) -> SimGeometry:
	return with_pose(dist, hoop_z)


## The original game's regulation three-pointer — matches SimConstants exactly.
## Default everywhere so the fidelity fixtures (golden grid) stay byte-valid.
static func regulation() -> SimGeometry:
	return SimGeometry.new(
		SimConstants.HOOP_X, SimConstants.RIM_HEIGHT, SimConstants.RELEASE_HEIGHT,
		SimConstants.BOARD_HALF_W, SimConstants.BOARD_BOTTOM, SimConstants.BOARD_TOP
	)


## Bar-machine pop-a-shot: 8 ft rim, standing quick-toss release, junior
## 1.22×0.76 m board whose bottom sits 0.15 m below the rim (regulation
## relation). `dist` is the moving-board difficulty knob.
static func arcade(dist := 2.6) -> SimGeometry:
	var rim_h := 2.44
	var b_bottom := rim_h - 0.15
	var g := _arcade_feel(SimGeometry.new(dist, rim_h, 1.85, 0.61, b_bottom, b_bottom + 0.76))
	# The cage (tools/blender/build_cage.py): mesh walls at z ±1.26, front lip at
	# x -1.8, back mesh at 4.4, mesh roof at 3.9. The z bound MUST track
	# CAGE_HALF_W in that script — the ball has to bounce where the fence is
	# drawn, or it rebounds off thin air.
	g.wall_x_min = -1.8
	g.wall_x_max = ARCADE_BACK_X
	g.wall_z_min = -1.26
	g.wall_z_max = 1.26
	g.wall_y_max = 3.9
	# The ball-return ramp under the hoop (RAMP_X0 / RAMP_TOP_Y in that
	# script): a miss that drops behind the rim lands on the slope and rolls
	# back down toward the shooter.
	g.ramp_x0 = ARCADE_RAMP_X0
	g.ramp_x1 = 4.4
	g.ramp_h = ARCADE_RAMP_H
	g.ramp_e = ARCADE_RAMP_E
	g.deck_roll_decel = ARCADE_DECK_ROLL_DECEL
	g.floor_log_impact = ARCADE_FLOOR_LOG_IMPACT
	g.lip_x = ARCADE_LIP_X
	g.lip_h = ARCADE_LIP_H
	# The front console (build_cage.py CONSOLE_*): a low flick bounces off its
	# top; returning balls roll under it (it starts 0.3 m up).
	g.props.push_back(_box(ARCADE_CONSOLE_X0, ARCADE_CONSOLE_X1, ARCADE_CONSOLE_Y0, ARCADE_CONSOLE_Y1, -1.2, 1.2))
	return g


## Beach street hoop: the arcade's 8 ft rim, release and rim feel on a
## regulation 1.83 × 1.05 m board (bottom 0.15 m below the rim). Static.
static func beach(dist := BEACH_DIST) -> SimGeometry:
	var rim_h := 2.44
	var b_bottom := rim_h - 0.15
	var g := _arcade_feel(SimGeometry.new(dist, rim_h, 1.85, SimConstants.BOARD_HALF_W, b_bottom, b_bottom + 1.05))
	# Bouncier iron than the cage — the only rim field the beach does not share.
	g.rim_e = BEACH_RIM_E
	# The fence enclosure (tools/blender/build_beach.py) and the in-ground pole.
	g.wall_x_min = -11.2
	g.wall_x_max = 5.7
	g.wall_z_min = -8.6
	g.wall_z_max = 8.6
	g.pole_r = 0.06
	g.pole_off = 0.3
	g.pole_top = g.board_top + 0.05
	return g


## City court: the beach's street geometry (8 ft rim, arcade release, a
## regulation board, iron 15 % livelier than the beach's) 25 % out, inside a
## fence, with a CHAIN net.
static func city(dist := CITY_DIST) -> SimGeometry:
	var rim_h := 2.44
	var b_bottom := rim_h - 0.15
	var g := _chain_feel(_arcade_feel(SimGeometry.new(dist, rim_h, 1.85, SimConstants.BOARD_HALF_W, b_bottom, b_bottom + 1.05)))
	g.rim_e = CITY_RIM_E
	# The fence enclosure (tools/blender/build_city.py) and the in-ground pole.
	g.wall_x_min = -11.2
	g.wall_x_max = 5.7
	g.wall_z_min = -8.6
	g.wall_z_max = 8.6
	g.pole_r = 0.06
	g.pole_off = 0.3
	g.pole_top = g.board_top + 0.05
	# The props the ball can hit (2026-10-03): the floor speaker to the
	# shooter's left of the pole's base and the tabletop scoreboard on the
	# ground to its right, against the fence — the boxes build_city.py draws
	# (Speakers at ENC_X1 − 1.15 / z −1.75, 0.46 × 0.92 × 0.52 — one cabinet
	# since 2026-10-05;
	# ReaderRig at ENC_X1 − 0.45 / z 1.45, plate + wedge 0.45 deep, 0.56 tall,
	# 0.76 wide). Move them there and here together.
	g.props.push_back(_box(4.32, 4.78, 0.0, 0.92, -1.75 - 0.26, -1.75 + 0.26))
	g.props.push_back(_box(5.20, 5.65, 0.0, 0.56, 1.45 - 0.38, 1.45 + 0.38))
	return g


static func _box(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> Dictionary:
	return {"x0": x0, "x1": x1, "y0": y0, "y1": y1, "z0": z0, "z1": z1}


## How rigid this net is, relative to the shipped nylon, from its own wall
## restitution (a net that returns more energy at the wall flexes less —
## chain links). 1.0 everywhere but the city; presentation (the visible
## chain, the clatter) is checked against it so what you see follows the
## physics.
func net_rigidity() -> float:
	return net_wall_e / SimConstants.E_NET_WALL


## How rigid this ring is, relative to the shipped arcade rim, derived from its
## own restitution — a bouncier rim returns more energy because it flexes less,
## which is what rigid steel does. Presentation reads this so what you see and
## hear follows the physics instead of being authored against it: the wiggle
## runs FASTER and SHALLOWER and the iron rings TIGHTER and QUIETER as it rises.
##
## Anchored at the cage (1.0), not regulation, so the mode people actually play
## keeps exactly the feel it was tuned to and only a livelier rim moves.
func rim_rigidity() -> float:
	return rim_e / ARCADE_RIM_E


## The arcade machine's rim/net feel, shared by arcade() and beach().
static func _arcade_feel(g: SimGeometry) -> SimGeometry:
	g.rim_e = ARCADE_RIM_E
	g.rim_mu = ARCADE_RIM_MU
	g.rim_spin_decay = ARCADE_RIM_SPIN_DECAY
	g.neck_is_rim = true
	g.net_catch_depth = ARCADE_NET_CATCH_DEPTH
	g.rim_log_impact = ARCADE_RIM_LOG_IMPACT
	return g


## The chain net's feel (city()).
static func _chain_feel(g: SimGeometry) -> SimGeometry:
	g.net_drag = CHAIN_NET_DRAG
	g.net_wall_e = CHAIN_NET_WALL_E
	return g
