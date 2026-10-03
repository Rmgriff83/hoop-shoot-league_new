class_name CourtGeometry
extends Node3D
## Builds every court mesh FROM the injected SimGeometry — the same object the
## sim shoots at, so rendered geometry and physics can never drift. Scene space
## IS canonical shot space: +x toward the hoop, +y up, +z lateral.
## apply_geometry() repositions the hoop assembly — the moving-board difficulty
## mechanic just calls it again with a new pose (depth + lateral).
## The arena (cage + arcade hall) is a static glb; its Crossbar/Trolley ride
## the cage rails to wherever the sim puts the hoop.

@export var debug_markers := false

## The active hoop bundle (model, net feel, LED skin, flourish anims). Set
## before add_child; defaults to the starter set. Model contract: root at the
## rim centre; RimPivot required; LedFace/BoardBand/Backboard/Net optional.
## The Backboard is scaled from the set's authored board size to the live geo.
var hoop_set: HoopSet

## The environment bundle (model + lighting + framing). Set before add_child;
## defaults to the starter arena. Model contract, all optional: `Crossbar`
## (rides the side rails, x), `Trolley` (rides the crossbar, x + z), `Pole`
## (placed behind the board), `Ocean`/`Shore` (BeachFx), `AnimationPlayer`.
var arena_set: ArenaSet
## Rail height and the crossbar/pole x offset behind the board — must match
## tools/blender/build_cage.py and build_beach.py.
const RAIL_Y := 3.5
const CROSSBAR_X_OFF := 0.3

## Set before adding to the tree; defaults to regulation.
## Rim wobble at rigidity 1.0 (the cage) — the values these were tuned at.
const BASE_RIM_STIFFNESS := 320.0
const RIM_DAMPING := 0.28
## Radians of pivot roll per unit of spring value, at rigidity 1.0.
const BASE_RIM_AMP := 0.06

var geo: SimGeometry

var rim_pivot: Node3D
## The rim's procedural wobble, and the rigidity scalars derived from the live
## geometry's restitution (see SimGeometry.rim_rigidity). It used to be two
## copies of these literals in two screens, driving a node owned by this class.
##
## The spring is unit-mass, so its frequency is sqrt(stiffness): a wiggle that
## runs `r` times faster needs r*r the stiffness. Deflection for a given kick
## goes as 1/r, which is the same law the amplitude and the sound volume use.
var _rim_wobble := JuiceSpring.new(0.0, BASE_RIM_STIFFNESS, RIM_DAMPING)
## Multiplies every rim swing, authored or sprung: a stiffer rim moves less.
var _rim_amp := 1.0
## LED scoreboard + backboard light band driver (always present).
var led: LedBoard
## A SECOND, independent board: the cage's league ribbon across the back wall.
## LedBoard allocates its image and materials per instance, so two of them do
## not interfere (the heat screen already runs one per court). Created only if
## the arena model carries a `LeagueFace` mesh, so every other arena is
## unaffected and no ArenaSet field is needed.
var league_led: LedBoard

var _hoop: Node3D               # model root, null when falling back to primitives
var _model_board: Node3D
var _anim: AnimationPlayer      # the glb's animations, null on fallback
## Runtime cord-lattice net driven by the sim's balls (null on fallback).
var net_sim: NetSim
var _board: MeshInstance3D
var _face: MeshInstance3D
var _pole: MeshInstance3D
var _bracket: MeshInstance3D
var _led_quad: MeshInstance3D   # fallback LED surface
var _wall: MeshInstance3D
var _floor: MeshInstance3D
var _arena: Node3D              # arena glb root, null when falling back to primitives
var _interactables: Array[Interactable] = []   # tappable props (ArenaSet.interactables)
var _crossbar: Node3D
var _trolley: Node3D
var _arena_pole: Node3D         # in-ground pole (beach), follows the board
var _scoreboard: Node3D         # ground reader board rig (beach), turns to the shooter
var _led_surfaces := 0          # LedFace/BoardBand meshes bound (hoop or arena)
var _fire: RimFire
var _ice: RimIce              # on-fire flames/smoke/glow on the rim
var _beach_fx: BeachFx          # waves + tide, only when arena_set.ocean
var _arcade_fx: ArcadeFx        # cabinet screens + marquees, only when arena_set.arcade_life
var _city_fx: CityFx            # traffic, window lights, trees, only when arena_set.traffic
var _arena_anim: AnimationPlayer  # the arena glb's clips (one per NLA track), null on fallback


func _ready() -> void:
	if geo == null:
		geo = SimGeometry.regulation()
	if hoop_set == null:
		hoop_set = CosmeticLibrary.starter_hoop()
	if arena_set == null:
		arena_set = CosmeticLibrary.starter_arena()
	led = LedBoard.new()
	led.name = "LedBoard"
	if hoop_set != null:
		led.set_palette(hoop_set)
	add_child(led)
	if not _build_arena_model():
		_build_floor()
		_build_pole()
		_build_backdrop()
	if not _build_hoop_model():
		_build_board()
		_build_rim_and_net()
	_add_rim_fire()
	_add_rim_ice()
	_build_lights()
	apply_geometry(geo)
	if debug_markers:
		_build_debug_markers()


## Position the hoop assembly for (possibly new) geometry. Mesh sizes are set
## at build time; only positions move — exactly what the sliding board needs.
func apply_geometry(new_geo: SimGeometry) -> void:
	geo = new_geo
	_apply_rim_rigidity()
	var cy := (geo.board_bottom + geo.board_top) / 2.0
	var h := geo.board_top - geo.board_bottom
	var z := geo.hoop_z
	if _pole != null:
		_pole.position = Vector3(geo.board_x + CROSSBAR_X_OFF, geo.board_top / 2.0, z)
	if _hoop != null:
		_hoop.position = Vector3(geo.hoop_x, geo.hoop_y, z)
		if _model_board != null:
			var mh: float = hoop_set.model_board_h if hoop_set != null else 0.76
			var mw: float = hoop_set.model_board_half_w if hoop_set != null else 0.61
			_model_board.scale = Vector3(1.0, h / mh, geo.board_half_w / mw)
	else:
		_board.position = Vector3(geo.board_x + 0.025, cy, z)
		_face.position = Vector3(geo.board_x - 0.002, cy, z)
		_led_quad.position = Vector3(geo.board_x - 0.002, geo.board_top + 0.12, z)
		rim_pivot.position = Vector3(geo.hoop_x + SimConstants.R_RIM, geo.hoop_y, z)
		_bracket.position = Vector3(
			(geo.bracket_x0 + geo.bracket_x1) / 2.0,
			(geo.bracket_y0 + geo.bracket_y1) / 2.0, z
		)
	# Cage rails: the crossbar slides along the side rails (x only); the trolley
	# slides along the crossbar (z) and carries the hoop's hanger.
	if _crossbar != null:
		_crossbar.position = Vector3(geo.board_x + CROSSBAR_X_OFF, RAIL_Y, 0.0)
	if _trolley != null:
		_trolley.position = Vector3(geo.board_x + CROSSBAR_X_OFF, RAIL_Y, z)
	if _arena_pole != null:
		_arena_pole.position = Vector3(geo.board_x + CROSSBAR_X_OFF, 0.0, z)
	if _floor != null:
		_floor.position = Vector3(geo.hoop_x / 2.0, 0.0, 0.0)
	if _wall != null:
		_wall.position = Vector3(geo.board_x + 2.5, 4.0, 0.0)


## Instance the arena from arena_set. False if the glb is missing (primitive
## floor/pole/wall then run). Every contract node is optional.
func _build_arena_model() -> bool:
	var path := arena_set.model_path if arena_set != null else ""
	var scene: PackedScene = load(path) if path != "" and ResourceLoader.exists(path) else null
	if scene == null:
		return false
	var inst: Node = scene.instantiate()
	if not (inst is Node3D):
		inst.free()
		push_warning("CourtGeometry: %s has no Node3D root, using primitives" % path)
		return false
	_arena = inst
	_arena.name = "Arena"
	add_child(_arena)
	_crossbar = _arena.find_child("Crossbar", true, false) as Node3D
	_trolley = _arena.find_child("Trolley", true, false) as Node3D
	_arena_pole = _arena.find_child("Pole", true, false) as Node3D
	_scoreboard = _arena.find_child("ScoreboardRig", true, false) as Node3D
	_arena_anim = _arena.find_child("AnimationPlayer", true, false)
	# An arena may host the scoreboard itself (the beach's ground cabinet).
	var aface := _arena.find_child("LedFace", true, false)
	if aface is MeshInstance3D:
		(aface as MeshInstance3D).material_override = led.material
		_led_surfaces += 1
	var aband := _arena.find_child("BoardBand", true, false)
	if aband is MeshInstance3D:
		(aband as MeshInstance3D).material_override = led.band_material
		_led_surfaces += 1
	var lface := _arena.find_child("LeagueFace", true, false)
	if lface is MeshInstance3D:
		league_led = LedBoard.new()
		league_led.name = "LeagueLed"
		if hoop_set != null:
			league_led.set_palette(hoop_set)
		add_child(league_led)
		(lface as MeshInstance3D).material_override = league_led.material
	# Lit-from-within surfaces (marquees, neon, the sky) glow independent of the sun.
	for n in arena_set.emissive_nodes:
		_unshade(n)
	_build_interactables(arena_set)
	if arena_set.ocean:
		_beach_fx = BeachFx.new()
		_beach_fx.name = "BeachFx"
		if _beach_fx.setup(_arena):
			add_child(_beach_fx)
		else:
			_beach_fx.free()
			_beach_fx = null
	if arena_set.arcade_life:
		_arcade_fx = ArcadeFx.new()
		_arcade_fx.name = "ArcadeFx"
		if _arcade_fx.setup(_arena):
			add_child(_arcade_fx)
		else:
			_arcade_fx.free()
			_arcade_fx = null
	if arena_set.traffic:
		_city_fx = CityFx.new()
		_city_fx.name = "CityFx"
		if _city_fx.setup(_arena):
			add_child(_city_fx)
		else:
			_city_fx.free()
			_city_fx = null
	return true


func _unshade(node_name: String) -> void:
	if _arena == null:
		return
	var mi := _arena.find_child(node_name, true, false) as MeshInstance3D
	if mi == null:
		return
	for i in mi.get_surface_override_material_count():
		var m := mi.get_active_material(i)
		if m is BaseMaterial3D:
			(m as BaseMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			(m as BaseMaterial3D).disable_fog = true  # a sky/marquee is not "far away"


## The net texture is a lattice with transparent holes. Blender 5.2 can't
## export glTF "mask" mode any more, so the glb says "blend"; scissor it here
## (crisp holes, correct depth against the ball) whatever the export said.
func _force_scissor(mi: MeshInstance3D) -> void:
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		if m is BaseMaterial3D:
			var b := m as BaseMaterial3D
			b.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			b.alpha_scissor_threshold = 0.5
			b.cull_mode = BaseMaterial3D.CULL_DISABLED


## Instance the Blender hoop and wire its named parts. False if the glb is
## missing (the primitive builders then run instead).
func _build_hoop_model() -> bool:
	if hoop_set == null or hoop_set.model_path == "":
		return false
	var scene: PackedScene = load(hoop_set.model_path)
	if scene == null:
		return false
	var inst: Node = scene.instantiate()
	var pivot := inst.find_child("RimPivot", true, false)
	var face := inst.find_child("LedFace", true, false)
	var band := inst.find_child("BoardBand", true, false)
	if not (inst is Node3D) or pivot == null:
		inst.free()
		push_warning("CourtGeometry: %s lacks RimPivot, using primitives" % hoop_set.model_path)
		return false
	_hoop = inst
	_hoop.name = "Hoop"
	add_child(_hoop)
	rim_pivot = pivot
	_model_board = inst.find_child("Backboard", true, false)
	_anim = inst.find_child("AnimationPlayer", true, false)
	if _anim != null:
		# Godot calls _process parents-first, so the screen that owns this court
		# runs BEFORE this descendant player would. Scaling the rim's swing there
		# would rescale last frame's pose and then be overwritten. Driving the
		# player ourselves from step_rim() makes the order explicit.
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_apply_rim_rigidity()
	# The net is simulated at runtime from the real ball; the glb's Swish clip
	# stays available for authored flourishes but its Net tracks no longer apply.
	var net_mi: MeshInstance3D = inst.find_child("Net", true, false)
	if net_mi != null:
		_force_scissor(net_mi)
		net_sim = NetSim.new()
		net_sim.name = "NetSim"
		net_sim.configure(hoop_set)
		if (hoop_set.net_kind == "chain") != (geo.net_rigidity() > 1.0):
			push_warning("CourtGeometry: hoop %s hangs a %s net on a geometry whose net rigidity is %.2f" % [hoop_set.id, hoop_set.net_kind, geo.net_rigidity()])
		add_child(net_sim)
		if not net_sim.setup(net_mi):
			net_sim.queue_free()
			net_sim = null
		else:
			_strip_blend_shape_tracks()
			# A chain hoop draws its springs as runs of steel links, not a surface.
			net_sim.set_chain(hoop_set.net_kind == "chain")
	# LED surfaces are optional (a street hoop has none: the HUD keeps score).
	if face is MeshInstance3D:
		(face as MeshInstance3D).material_override = led.material
		_led_surfaces += 1
	if band is MeshInstance3D:
		(band as MeshInstance3D).material_override = led.band_material
		_led_surfaces += 1
	if _led_surfaces == 0:
		led.set_process(false)  # nothing to draw on: skip the per-frame image render
	return true


## The swish kick: the sim's rim-plane `enter` contact → the net's cords.
func net_kick(pos: Vector3, vel: Vector3) -> void:
	if net_sim != null:
		net_sim.kick(pos, vel)


## Advance the runtime net with the sim's in-flight balls (call every frame).
func step_net(dt: float, balls: Array[BallState]) -> void:
	if net_sim == null:
		return
	var descs: Array = []
	for s in balls:
		descs.push_back(NetSim.ball_from_state(s))
	net_sim.step(dt, descs)


## NetSim swaps the Net for a dynamic ArrayMesh with no blend shapes, which
## leaves the glb's authored Swish clip pointing at 'Grab'/'SnapUp'. Nothing
## plays those tracks — the net is simulated — but AnimationMixer rebuilds its
## caches across the WHOLE library the first time step_rim() advances a clip and
## complains about every one of them, once per court. Drop the dead tracks.
func _strip_blend_shape_tracks() -> void:
	if _anim == null:
		return
	for lib_name in _anim.get_animation_library_list():
		var lib: AnimationLibrary = _anim.get_animation_library(lib_name)
		if lib == null:
			continue
		for anim_name in lib.get_animation_list():
			var anim: Animation = lib.get_animation(anim_name)
			if anim == null:
				continue
			for i in range(anim.get_track_count() - 1, -1, -1):
				if anim.track_get_type(i) == Animation.TYPE_BLEND_SHAPE:
					anim.remove_track(i)


## Recompute the rigidity scalars. Safe to call before the hoop model exists.
func _apply_rim_rigidity() -> void:
	var r: float = geo.rim_rigidity() if geo != null else 1.0
	_rim_amp = 1.0 / r
	_rim_wobble.stiffness = BASE_RIM_STIFFNESS * r * r
	if _anim != null:
		_anim.speed_scale = r


## The rim's reaction to being hit at `speed` m/s: the set's authored clip if it
## has one, otherwise the procedural wobble. Both are scaled by rigidity — the
## clip through speed_scale here and its swing through _rim_amp in step_rim().
func rim_react(speed: float) -> void:
	var name_: String = hoop_set.miss_anim if hoop_set != null else ""
	if name_ != "" and _anim != null and _anim.has_animation(name_):
		_play_anim(name_)
		return
	_rim_wobble.kick(minf(speed / 7.0, 1.0) * 3.0)


## A small nudge with no rim contact — the pivot still bobs on a clean swish.
func rim_nudge() -> void:
	_rim_wobble.kick(1.0)


## Advance the rim (call every frame, next to step_net). An authored clip owns
## the hinge while it runs; the spring has it the rest of the time.
func step_rim(dt: float) -> void:
	_rim_wobble.step(dt)
	if rim_pivot == null:
		return
	if _anim != null and _anim.is_playing():
		_anim.advance(dt)
		# The clip writes the pivot's rotation absolutely from a zero rest pose,
		# so scaling in place cannot compound — next frame it writes fresh.
		rim_pivot.rotation *= _rim_amp
	else:
		# The full vector, not just .z: a clip that keyed x/y leaves them set
		# when it stops, and writing only .z would freeze that residue forever.
		rim_pivot.rotation = Vector3(0.0, 0.0, _rim_wobble.value * BASE_RIM_AMP * _rim_amp)


## Play the set's authored make flourish (hoop_set.make_anim), if it names one.
## No-op on the primitive fallback, an empty name, or a missing animation.
func play_make() -> void:
	_play_anim(hoop_set.make_anim if hoop_set != null else "")


## Play the set's streak flourish (hoop_set.streak_anim), if it names one.
func play_streak() -> void:
	_play_anim(hoop_set.streak_anim if hoop_set != null else "")


## Flames/smoke/glow rig on the ring, under the pivot so it rides with the rim.
func _add_rim_fire() -> void:
	if rim_pivot == null:
		return
	_fire = RimFire.new()
	_fire.name = "RimFire"
	var rim_mi: MeshInstance3D = (_hoop.find_child("Rim", true, false) if _hoop != null else rim_pivot.find_child("Rim", true, false)) as MeshInstance3D
	var at := Vector3(-SimConstants.R_RIM, 0.0, 0.0)
	if rim_mi != null and rim_mi.get_parent() == rim_pivot:
		at = Vector3(rim_mi.position.x, rim_mi.position.y, rim_mi.position.z)
	_fire.position = at + Vector3(0.0, 0.02, 0.0)
	rim_pivot.add_child(_fire)
	_fire.setup(rim_mi)


## On-fire state: lit with a streak level, or out (with smoke).
func set_fire(lit: bool, level := 0) -> void:
	if _fire == null:
		return
	if lit:
		_fire.ignite(level)
		play_streak()
	else:
		_fire.extinguish()


func fire_lit() -> bool:
	return _fire != null and _fire.is_lit()


func _add_rim_ice() -> void:
	if rim_pivot == null:
		return
	_ice = RimIce.new()
	_ice.name = "RimIce"
	var rim_mi: MeshInstance3D = (_hoop.find_child("Rim", true, false) if _hoop != null else rim_pivot.find_child("Rim", true, false)) as MeshInstance3D
	var at := Vector3(-SimConstants.R_RIM, 0.0, 0.0)
	if rim_mi != null and rim_mi.get_parent() == rim_pivot:
		at = Vector3(rim_mi.position.x, rim_mi.position.y, rim_mi.position.z)
	_ice.position = at + Vector3(0.0, 0.012, 0.0)
	rim_pivot.add_child(_ice)
	_ice.setup(rim_mi)


## Cold streak: ice the rim over, or break it (`by` = "make" / "hits"; "" = clear instantly).
func set_ice(on: bool, by := "") -> void:
	if _ice == null:
		return
	if on:
		_ice.freeze()
	elif by == "":
		_ice.clear()
	else:
		_ice.shatter(by)


func ice_crack(hits_left: int) -> void:
	if _ice != null:
		_ice.crack(hits_left)


## The ice grabbed a would-be make: fissures spread until the pop.
func ice_grab() -> void:
	if _ice != null:
		_ice.grab()


func iced() -> bool:
	return _ice != null and _ice.is_iced()


## Is one of the hoop's authored clips driving the model right now?
func flourish_playing() -> bool:
	return _anim != null and _anim.is_playing()


## Yaw (rad, about +y) that points a -x-facing front toward `to` from `from`.
## Tappable props from the arena set (see Interactable / InteractableKinds).
func _build_interactables(arena_set: ArenaSet) -> void:
	if arena_set.interactables.is_empty():
		return
	var root := Node3D.new()
	root.name = "Interactables"
	add_child(root)
	for row in arena_set.interactables:
		var node := _arena.find_child(str(row.get("node", "")), true, false)
		var it := InteractableKinds.make(str(row.get("kind", "")))
		if node == null or not (node is Node3D) or it == null:
			push_warning("CourtGeometry: interactable %s on %s not built" % [row.get("kind", "?"), row.get("node", "?")])
			if it != null:
				it.free()
			continue
		it.name = "%s_%s" % [row.get("kind", "prop"), row.get("node", "")]
		root.add_child(it)
		it.setup(node as Node3D, row)
		_interactables.push_back(it)


## The interactable under a screen point (nearest along the camera ray), or null.
func pick_interactable(cam: Camera3D, screen_pos: Vector2) -> Interactable:
	if cam == null or _interactables.is_empty():
		return null
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var best: Interactable = null
	var best_d := INF
	for it in _interactables:
		var d := it.hit(origin, dir)
		if d >= 0.0 and d < best_d:
			best_d = d
			best = it
	return best


func interactables() -> Array[Interactable]:
	return _interactables


## Leaving the area: every prop puts itself back (the radio goes quiet).
func leave_interactables() -> void:
	for it in _interactables:
		it.on_leave()


static func yaw_toward(from: Vector3, to: Vector3) -> float:
	return atan2(to.z - from.z, -(to.x - from.x))


## Turn the ground reader board (if the arena has one) to face the shooter.
func face_scoreboard(shooter: Vector3) -> void:
	if _scoreboard == null:
		return
	_scoreboard.rotation.y = yaw_toward(_scoreboard.global_position, shooter)


## Run the league ribbon board across the back wall. A no-op on an arena with
## no `LeagueFace`, so callers need not know which arena they are in.
func set_ticker(items: PackedStringArray) -> void:
	if league_led == null:
		return
	if league_led.mode() == "ticker":
		league_led.set_ticker_items(items)   # swap content without a jump
	else:
		league_led.ticker(items)


## Freeze / run the league ribbon (see LedBoard.set_ticker_paused).
func set_ticker_paused(paused: bool) -> void:
	if league_led != null:
		league_led.set_ticker_paused(paused)


## The cage's string lights surge. Replaces the marquee sign's MarqueePulse
## clip, which went with the sign; a no-op on any arena without string lights.
func flare_lights() -> void:
	if _arcade_fx != null:
		_arcade_fx.flare()


## Play one of the arena's authored clips (an NLA track in cage.blend, e.g.
## "CageShake"). Silently ignored if the arena or clip is missing.
func play_arena(name_: String) -> void:
	if name_ == "" or _arena_anim == null or not _arena_anim.has_animation(name_):
		return
	_arena_anim.stop()
	_arena_anim.play(name_)


func _play_anim(name_: String) -> void:
	if name_ == "" or _anim == null or not _anim.has_animation(name_):
		return
	_anim.stop()
	_anim.play(name_)


func _build_pole() -> void:
	var pole := CylinderMesh.new()
	pole.top_radius = 0.06
	pole.bottom_radius = 0.06
	pole.height = geo.board_top
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.28, 0.31, 0.38)
	_pole = _add_mesh(pole, pole_mat, "Pole")


func _pixel_material(texture_path: String, transparent := false, unshaded := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(texture_path)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 1.0
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _add_mesh(mesh: Mesh, mat: Material, name_: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	return mi


func _build_floor() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(14.0, 8.0)
	var mat := _pixel_material("res://assets/textures/court_floor.png")
	mat.uv1_scale = Vector3(7.0, 4.0, 1.0)
	_floor = _add_mesh(plane, mat, "Floor")


func _build_board() -> void:
	var h := geo.board_top - geo.board_bottom
	var board := BoxMesh.new()
	board.size = Vector3(0.05, h, geo.board_half_w * 2.0)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.78, 0.8, 0.84)
	body_mat.roughness = 1.0
	_board = _add_mesh(board, body_mat, "Backboard")
	# Textured front face (the collider plane) — shows the shooter square
	# exactly where physics says it is.
	var face := QuadMesh.new()
	face.size = Vector2(geo.board_half_w * 2.0, h)
	_face = _add_mesh(face, _pixel_material("res://assets/textures/backboard.png"), "BackboardFace")
	_face.rotation.y = -PI / 2.0  # quad faces -x, toward the shooter
	# Fallback LED scoreboard surface above the board (the model has a proper housing).
	var led_quad := QuadMesh.new()
	led_quad.size = Vector2(geo.board_half_w * 1.8, 0.16)
	_led_quad = _add_mesh(led_quad, led.material, "LedFace")
	_led_quad.rotation.y = -PI / 2.0


func _build_rim_and_net() -> void:
	# Pivot at the board edge of the rim so wobble rotates the way a real rim
	# flexes (hinged at the mount).
	rim_pivot = Node3D.new()
	rim_pivot.name = "RimPivot"
	add_child(rim_pivot)

	var torus := TorusMesh.new()
	torus.inner_radius = SimConstants.R_RIM - SimConstants.R_TUBE
	torus.outer_radius = SimConstants.R_RIM + SimConstants.R_TUBE
	torus.rings = 32
	torus.ring_segments = 12
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	rim.mesh = torus
	rim.material_override = _pixel_material("res://assets/textures/rim.png")
	rim.position = Vector3(-SimConstants.R_RIM, 0.0, 0.0)  # ring center, relative to pivot
	rim_pivot.add_child(rim)

	# Cosmetic net: tapering open cylinder below the rim, alpha-scissor cords.
	var net := CylinderMesh.new()
	net.top_radius = SimConstants.R_RIM
	net.bottom_radius = 0.10
	net.height = 0.42
	net.cap_top = false
	net.cap_bottom = false
	net.radial_segments = 12
	var net_mi := MeshInstance3D.new()
	net_mi.name = "Net"
	net_mi.mesh = net
	net_mi.material_override = _pixel_material("res://assets/textures/net.png", true, true)
	net_mi.position = Vector3(-SimConstants.R_RIM, -0.21, 0.0)
	rim_pivot.add_child(net_mi)

	# Bracket ribbon visual (the physics collider between back rim and board).
	var bracket := BoxMesh.new()
	bracket.size = Vector3(geo.bracket_x1 - geo.bracket_x0, 0.03, 0.12)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.85, 0.35, 0.25)
	_bracket = _add_mesh(bracket, bmat, "Bracket")
	_bracket.rotation.z = atan2(
		geo.bracket_y1 - geo.bracket_y0,
		geo.bracket_x1 - geo.bracket_x0
	)


func _build_backdrop() -> void:
	var wall := QuadMesh.new()
	wall.size = Vector2(16.0, 8.0)
	var mat := _pixel_material("res://assets/textures/crowd_wall.png", false, true)
	mat.uv1_scale = Vector3(4.0, 4.0, 1.0)
	_wall = _add_mesh(wall, mat, "CrowdWall")
	_wall.rotation.y = -PI / 2.0  # quad faces -x, toward the camera


func _build_lights() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	if _arena != null and arena_set != null:
		# The arena bundle says how it is lit.
		sun.rotation = arena_set.sun_rotation_deg * (PI / 180.0)
		sun.light_energy = arena_set.sun_energy
		sun.light_color = arena_set.sun_color
		if arena_set.sun_shadows:
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = 30.0
		env.background_color = arena_set.background_color
		env.ambient_light_color = arena_set.ambient_color
		env.ambient_light_energy = arena_set.ambient_energy
		if arena_set.fill_energy > 0.0:
			var fill := DirectionalLight3D.new()
			fill.name = "Fill"
			fill.rotation = arena_set.fill_rotation_deg * (PI / 180.0)
			fill.light_energy = arena_set.fill_energy
			fill.light_color = arena_set.fill_color
			add_child(fill)
		if arena_set.fog_enabled:
			env.fog_enabled = true
			env.fog_light_color = arena_set.fog_color
			env.fog_density = arena_set.fog_density
			env.fog_sky_affect = 0.0
	else:
		# Primitive fallback court: the old bright gym.
		sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-30.0), 0.0)
		sun.light_energy = 1.1
		env.background_color = Color(0.15, 0.17, 0.26)
		env.ambient_light_color = Color(0.7, 0.72, 0.8)
		env.ambient_light_energy = 0.7
	add_child(sun)
	var we := WorldEnvironment.new()
	we.name = "Env"
	we.environment = env
	add_child(we)


## Small unshaded spheres at sim-critical points — visual/physics drift check.
func _build_debug_markers() -> void:
	var points := {
		"MarkRelease": Vector3(0.0, geo.release_h, 0.0),
		"MarkRimCenter": Vector3(geo.hoop_x, geo.hoop_y, geo.hoop_z),
		"MarkRimFront": Vector3(geo.hoop_x - SimConstants.R_RIM, geo.hoop_y, geo.hoop_z),
		"MarkRimBack": Vector3(geo.hoop_x + SimConstants.R_RIM, geo.hoop_y, geo.hoop_z),
		"MarkBoardBottom": Vector3(geo.board_x, geo.board_bottom, geo.hoop_z),
	}
	for name_: String in points:
		var ball := SphereMesh.new()
		ball.radius = 0.03
		ball.height = 0.06
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 1.0, 0.4)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var mi := _add_mesh(ball, mat, name_)
		mi.position = points[name_]
