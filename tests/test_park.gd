extends RefCounted
## The park (Ross's "Park Area Concept", 2026-10-15): the photo's hoop at
## 3.70 m on a slim board with cold steel and a nylon net, the open court
## bounded at the slab's edge by soft snow banks, the drift at the pole's
## foot, the mode table, the spots, the league, and an endless trial on it.


func run(t) -> void:
	_lights(t)
	_geometry(t)
	_shots(t)
	_edge(t)
	_spots(t)
	_modes(t)
	_endless_trial(t)


func _geometry(t) -> void:
	var g := SimGeometry.park()
	t.close(g.hoop_x, 3.70, 1e-12, "park hoop is 3.70 m out (%.4f)" % g.hoop_x)
	t.ok(g.hoop_x > SimGeometry.CITY_DIST, "farther than the city's")
	t.close(g.hoop_y, 2.44, 1e-12, "park rim stays 8 ft")
	t.close(g.release_h, 1.85, 1e-12, "park release is the arcade's")
	t.close(g.board_half_w, 0.70, 1e-12, "the slim 1.40 m park board")
	t.close(g.board_top - g.board_bottom, 1.05, 1e-12, "regulation board height")
	t.close(g.board_bottom, 2.29, 1e-12, "board bottom 0.15 m below the rim")
	t.ok(g.hoop_z == 0.0, "park hoop is centred")
	var a := SimGeometry.arcade()
	var c := SimGeometry.city()
	t.close(g.rim_e, SimGeometry.PARK_RIM_E, 1e-12, "park iron has its own restitution")
	t.ok(g.rim_e > c.rim_e and g.rim_e > SimGeometry.BEACH_RIM_E, "cold steel: livelier than the city's and the beach's (%.3f)" % g.rim_e)
	t.ok(g.rim_mu == a.rim_mu and g.rim_spin_decay == a.rim_spin_decay, "park grip and spin decay match the cage")
	t.ok(g.neck_is_rim == a.neck_is_rim and g.net_catch_depth == a.net_catch_depth and g.rim_log_impact == a.rim_log_impact, "park gym-rim fields = arcade")
	t.ok(g.net_drag == a.net_drag and g.net_wall_e == a.net_wall_e, "the park hangs nylon")
	t.close(g.net_rigidity(), 1.0, 1e-12, "nylon rigidity 1")
	t.ok(g.has_walls() and g.wall_x_min == -7.0 and g.wall_x_max == SimGeometry.PARK_FENCE_X and g.wall_z_max == 6.0 and g.wall_z_min == -6.0 and g.wall_y_max == INF, "the split-rail fence behind the hoop, the slab's edge at the sides, no roof")
	t.close(g.wall_x_max, 6.20, 1e-12, "the fence stands 2.5 m behind the rim")
	t.ok(g.wall_e < SimGeometry.beach().wall_e and g.wall_mu > SimGeometry.beach().wall_mu, "cedar and snow banks: softer and grippier than chain-link (e %.2f, mu %.2f)" % [g.wall_e, g.wall_mu])
	t.close(g.pole_r, 0.07, 1e-12, "the in-ground pole")
	t.close(g.pole_off, 0.17, 1e-12, "…close behind the board")
	t.ok(g.has_props() and g.props.size() == 1, "one prop: the drift at the pole's foot")
	var d: Dictionary = g.props[0]
	t.ok(float(d["x0"]) == 4.05 and float(d["x1"]) == 4.50 and float(d["y1"]) == 0.18 and float(d["z0"]) == -0.40 and float(d["z1"]) == 0.40, "the drift's box")
	t.ok(g.prop_e < 0.5, "snow is a dull bounce (%.2f)" % g.prop_e)
	var moved := g.with_pose(3.9, 0.2)
	t.ok(moved.rim_e == g.rim_e and moved.wall_e == g.wall_e and moved.props.size() == 1 and moved.pole_r == g.pole_r, "with_pose keeps the iron, the banks, the drift and the pole")
	t.ok(not g.magnet and not g.ice, "no magnet, no ice by default")


func _shots(t) -> void:
	var g := SimGeometry.park()
	for ang in [52.0, 55.0]:
		var launch := Ballistics.ideal_launch_for(ang, g)
		var out := ShotSim.simulate_shot(launch, false, g)
		t.ok(out["made"], "ideal %.0f° shot is made on the park hoop (%s)" % [ang, out["type"]])
		var short := launch.duplicate()
		short["speed"] = launch["speed"] * 0.94
		t.ok(not ShotSim.simulate_shot(short, false, g)["made"], "6 %% short misses at %.0f°" % ang)
	var pen := 0.0
	var first := ""
	for a in range(40, 66, 5):
		var ideal: float = Ballistics.speed_for_angle(a, g.hoop_x, g.rise)
		for k in range(-4, 5, 2):
			var launch := {"angle_deg": float(a), "speed": ideal * (1.0 + 0.02 * k)}
			var out := ShotSim.simulate_shot(launch, false, g)
			pen = maxf(pen, out["max_penetration"])
			if first == "":
				first = JSON.stringify(out)
				t.eq(first, JSON.stringify(ShotSim.simulate_shot(launch, false, g)), "park sim is deterministic")
	t.ok(pen < 0.02, "no deep penetration on the park hoop (%.4f)" % pen)


## A ball never leaves the slab: the banks stop it, and a hard line drive
## past the pole comes back off the drift or the bank, not the thin air.
func _edge(t) -> void:
	var g := SimGeometry.park()
	var max_x := -INF
	var max_z := 0.0
	for a in [30.0, 40.0, 48.0]:
		var ideal: float = Ballistics.speed_for_angle(a, g.hoop_x, g.rise)
		for k in [1.08, 1.15, 1.25]:
			var s := ShotSim.create_shot({"angle_deg": a, "speed": ideal * k, "vz": 0.4}, g)
			for i in int(6.0 / SimConstants.SIM_DT):
				if s.settled:
					break
				ShotSim.step_shot(s)
				max_x = maxf(max_x, s.pos.x)
				max_z = maxf(max_z, absf(s.pos.z))
	t.ok(max_x <= g.wall_x_max + 1e-6, "the ball never passes the fence (%.2f)" % max_x)
	t.ok(max_z <= g.wall_z_max + 1e-6, "…or its sides (%.2f)" % max_z)


## Every park spot sits on the key's arc, and an ideal shot from each scores.
func _spots(t) -> void:
	var g := SimGeometry.park()
	var spots: Array = CosmeticLibrary.get_arena("park").spots()
	t.eq(spots.size(), 5, "five park spots")
	var key_d := Vector2(g.hoop_x, g.hoop_z).length()
	for sp in spots:
		var pos: Vector3 = sp["pos"]
		var d := Vector2(g.hoop_x - pos.x, g.hoop_z - pos.z).length()
		t.close(d, key_d, 0.01, "%s is the key's distance from the hoop (%.3f vs %.3f)" % [sp["name"], d, key_d])
		var dx := g.hoop_x - pos.x
		var dz := g.hoop_z - pos.z
		var launch := {"angle_deg": 52.0, "speed": Ballistics.speed_for_angle(52.0, d, g.rise),
			"rx": pos.x, "ry": g.release_h, "rz": pos.z, "bx": dx / d, "bz": dz / d}
		t.ok(ShotSim.simulate_shot(launch, false, g)["made"], "an ideal shot from %s scores" % sp["name"])
		t.ok(pos.x > g.wall_x_min and absf(pos.z) < g.wall_z_max, "%s stands on the slab" % sp["name"])


func _modes(t) -> void:
	var app = Engine.get_main_loop().root.get_node_or_null("App")
	if app == null:
		t.ok(true, "(App autoload absent — mode table checks skipped)")
		return
	for id in ["park", "trial_park", "heat_park"]:
		t.ok(app.MODES.has(id), "mode table has %s" % id)
	t.eq(app.AREA_MODES["trial"]["park"], "trial_park", "trial × park → trial_park")
	t.eq(app.AREA_MODES["practice"]["park"], "park", "practice × park → park")
	var c: Dictionary = app.mode_config("park")
	t.ok(c["arena"] == "park" and c["hoop"] == "park" and c["geo"] == "park" and c["location"] == "park", "park mode: park arena, park hoop, park geometry")
	t.close(float(c["dist"]), SimGeometry.PARK_DIST, 1e-12, "park mode distance")
	t.ok(c["endless"] and not c["board_motion"], "park practice is endless and static")
	t.eq(c["hud_label"], "PARK", "park HUD label")
	var tc: Dictionary = app.mode_config("trial_park")
	t.ok(not tc["endless"] and tc["spot_shuffle"], "the park trial is timed and shuffles spots")
	var hc: Dictionary = app.mode_config("heat_park")
	t.ok(hc["heat"] and hc["calib_key"] == "park" and hc["spot_shuffle"], "park heats calibrate on the park and shuffle spots")
	t.close(app.geo_for_mode("park").board_half_w, 0.70, 1e-12, "geo_for_mode(park) is the slim board")
	t.close(app.geo_for_mode("park").hoop_x, 3.70, 1e-12, "geo_for_mode(park) is 3.70 m out")
	t.eq(ResultsCopy.board_name("park"), "PARK", "the park board name")
	t.ok(ResultsCopy.run_sub("park").ends_with("SAME PARK"), "RUN IT BACK's park word")
	var league := LeagueData.league("park")
	t.ok(not league.is_empty() and league["arena"] == "park" and league["hoop"] == "park" and league["mode"] == "heat_park", "the park league plays the park")
	t.eq(LeagueData.team_ids(league).size(), 8, "eight park teams")
	var hoop = app.hoop_for_mode("park")
	t.ok(hoop != null and hoop.id == "park" and hoop.net_kind == "nylon", "park mode resolves the park hoop regardless of ownership")
	t.ok(ScorePayload.AREAS.has("park"), "a park run is a valid leaderboard area")
	t.ok(FileAccess.file_exists("res://assets/ai/calibration_park.json"), "the AI is calibrated on the park hoop")


func _endless_trial(t) -> void:
	var tt := TimeTrial.new(SimGeometry.park())
	tt.endless = true
	for i in int(3.0 / SimConstants.SIM_DT):
		tt.tick(SimConstants.SIM_DT)
	t.eq(tt.phase, TimeTrial.PHASE_RUNNING, "park trial runs")
	t.ok(not tt.moving, "park hoop never moves")
	t.ok(tt.pickup(), "pickup on the park court")
	t.ok(tt.release(Ballistics.ideal_launch_for(55.0, tt.geo)), "release on the park court")
	for i in int(2.5 / SimConstants.SIM_DT):
		tt.tick(SimConstants.SIM_DT)
	t.eq(tt.makes, 1, "ideal park shot scores")
	t.close(tt.geo.hoop_x, SimGeometry.PARK_DIST, 1e-12, "park hoop stayed put")


## The park's sun from its ArenaSet: 20 m shadows; the court puts the area's
## render scale on its viewport only when it is in a tree.
func _lights(t) -> void:
	var court := CourtGeometry.new()
	court.geo = SimGeometry.park()
	court.arena_set = CosmeticLibrary.get_arena("park")
	court.hoop_set = CosmeticLibrary.get_hoop("park")
	court._ready()
	var sun: DirectionalLight3D = court.find_child("Sun", true, false)
	t.ok(sun != null and sun.shadow_enabled and absf(sun.directional_shadow_max_distance - 20.0) < 1e-9, "the park's sun shadows reach 20 m")
	var beach := CourtGeometry.new()
	beach.geo = SimGeometry.beach()
	beach.arena_set = CosmeticLibrary.get_arena("beach")
	beach.hoop_set = CosmeticLibrary.starter_hoop()
	beach._ready()
	var bsun: DirectionalLight3D = beach.find_child("Sun", true, false)
	t.ok(bsun != null and absf(bsun.directional_shadow_max_distance - 30.0) < 1e-9, "the beach keeps 30 m")
	court.free()
	beach.free()
