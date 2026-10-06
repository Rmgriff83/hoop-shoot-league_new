extends RefCounted
## The city court: the beach's street geometry 25 % out with a CHAIN net
## (its own drag and wall restitution, default-preserving everywhere else),
## the mode table, the spots, and an endless trial on it.


func run(t) -> void:
	_geometry(t)
	_shots(t)
	_chain_exits_faster(t)
	_spots(t)
	_modes(t)
	_endless_trial(t)
	_vortex(t)


func _geometry(t) -> void:
	var g := SimGeometry.city()
	t.close(g.hoop_x, 2.9 * 1.25, 1e-12, "city hoop is 25 %% farther than the arcade base (%.4f)" % g.hoop_x)
	t.close(g.hoop_y, 2.44, 1e-12, "city rim stays 8 ft")
	t.close(g.release_h, 1.85, 1e-12, "city release is the arcade's")
	t.close(g.board_half_w, 0.915, 1e-12, "regulation board width")
	t.close(g.board_top - g.board_bottom, 1.05, 1e-12, "regulation board height")
	t.close(g.board_bottom, 2.29, 1e-12, "board bottom 0.15 m below the rim")
	t.ok(g.hoop_z == 0.0, "city hoop is centred")
	var a := SimGeometry.arcade()
	var b := SimGeometry.beach()
	t.close(g.rim_e, SimGeometry.CITY_RIM_E, 1e-12, "city iron has its own restitution")
	t.close(g.rim_e, SimGeometry.BEACH_RIM_E * 1.15, 1e-12, "15 % bouncier than the beach ring")
	t.ok(g.rim_mu == a.rim_mu and g.rim_spin_decay == a.rim_spin_decay, "city grip and spin decay match the cage")
	t.ok(g.neck_is_rim == a.neck_is_rim and g.net_catch_depth == a.net_catch_depth and g.rim_log_impact == a.rim_log_impact, "city gym-rim fields = arcade")
	# The chain net: the only sim fields the city does not share with the beach.
	t.close(g.net_drag, SimGeometry.CHAIN_NET_DRAG, 1e-12, "the chain's drag")
	t.close(g.net_wall_e, SimGeometry.CHAIN_NET_WALL_E, 1e-12, "the chain's wall restitution")
	t.ok(g.net_drag < SimConstants.NET_DRAG, "a chain slows the ball less than nylon (%.2f < %.2f)" % [g.net_drag, SimConstants.NET_DRAG])
	t.ok(g.net_wall_e > SimConstants.E_NET_WALL, "and its wall kicks harder (%.2f > %.2f)" % [g.net_wall_e, SimConstants.E_NET_WALL])
	t.close(g.net_rigidity(), 2.5, 1e-12, "chain rigidity 2.5")
	t.close(b.net_rigidity(), 1.0, 1e-12, "beach net rigidity 1 (nylon)")
	t.close(SimGeometry.regulation().net_rigidity(), 1.0, 1e-12, "regulation net rigidity 1")
	t.ok(b.net_drag == a.net_drag and b.net_wall_e == a.net_wall_e, "the beach still hangs nylon")
	var moved := g.with_pose(3.8, 0.2)
	t.ok(moved.net_drag == g.net_drag and moved.net_wall_e == g.net_wall_e and moved.rim_e == g.rim_e, "with_pose keeps the chain and the iron")
	t.ok(g.with_ice(true).net_drag == g.net_drag, "with_ice keeps the chain")
	t.ok(g.has_walls() and g.wall_x_min == -11.2 and g.wall_x_max == 5.7 and g.wall_z_max == 8.6 and g.wall_y_max == INF, "the fence loop, no roof")
	t.close(g.pole_r, 0.06, 1e-12, "in-ground pole")
	t.ok(not g.vortex, "no vortex by default")


func _shots(t) -> void:
	var g := SimGeometry.city()
	for ang in [52.0, 55.0]:
		var launch := Ballistics.ideal_launch_for(ang, g)
		var out := ShotSim.simulate_shot(launch, false, g)
		t.ok(out["made"], "ideal %.0f° shot is made on the city hoop (%s)" % [ang, out["type"]])
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
				t.eq(first, JSON.stringify(ShotSim.simulate_shot(launch, false, g)), "city sim is deterministic")
	t.ok(pen < 0.02, "no deep penetration on the city hoop (%.4f)" % pen)


## A ball dropped into the ring reaches the bottom of a chain net sooner
## than a nylon one, and both still score.
func _chain_exits_faster(t) -> void:
	var times := {}
	for pair in [["city", SimGeometry.city()], ["beach", SimGeometry.beach()]]:
		var g: SimGeometry = pair[1]
		var s := ShotSim.create_shot({"angle_deg": -89.0, "speed": 0.5, "rx": g.hoop_x, "ry": g.hoop_y + 0.25, "rz": 0.0, "bx": 1.0, "bz": 0.0}, g)
		var steps := 0
		while s.pos.y > g.hoop_y - 0.6 and steps < int(3.0 / SimConstants.SIM_DT):
			ShotSim.step_shot(s)
			steps += 1
		times[pair[0]] = s.t
		t.ok(s.made, "a dropped ball scores on the %s hoop" % pair[0])
	t.ok(float(times["city"]) < float(times["beach"]), "the chain lets it through sooner (%.3f s < %.3f s)" % [times["city"], times["beach"]])


## Every city spot sits on the key's arc, and an ideal shot from each scores.
func _spots(t) -> void:
	var g := SimGeometry.city()
	var spots: Array = CosmeticLibrary.get_arena("city").spots()
	t.eq(spots.size(), 5, "five city spots")
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


func _modes(t) -> void:
	var app = Engine.get_main_loop().root.get_node_or_null("App")
	if app == null:
		t.ok(true, "(App autoload absent — mode table checks skipped)")
		return
	for id in ["city", "trial_city", "heat_city"]:
		t.ok(app.MODES.has(id), "mode table has %s" % id)
	t.eq(app.AREA_MODES["trial"]["city"], "trial_city", "trial × city → trial_city")
	t.eq(app.AREA_MODES["practice"]["city"], "city", "practice × city → city")
	var c: Dictionary = app.mode_config("city")
	t.ok(c["arena"] == "city" and c["hoop"] == "chain" and c["geo"] == "city" and c["location"] == "city", "city mode: city arena, chain hoop, city geometry")
	t.close(float(c["dist"]), SimGeometry.CITY_DIST, 1e-12, "city mode distance")
	t.ok(c["endless"] and not c["board_motion"], "city practice is endless and static")
	t.eq(c["hud_label"], "CITY", "city HUD label")
	var tc: Dictionary = app.mode_config("trial_city")
	t.ok(not tc["endless"] and tc["spot_shuffle"], "the city trial is timed and shuffles spots")
	var hc: Dictionary = app.mode_config("heat_city")
	t.ok(hc["heat"] and hc["calib_key"] == "city" and hc["spot_shuffle"], "city heats calibrate on the city and shuffle spots")
	t.close(app.geo_for_mode("city").net_drag, SimGeometry.CHAIN_NET_DRAG, 1e-12, "geo_for_mode(city) hangs the chain")
	t.close(app.geo_for_mode("city").board_half_w, 0.915, 1e-12, "geo_for_mode(city) is the regulation board")
	t.eq(ResultsCopy.board_name("city"), "CITY", "the city board name")
	var league := LeagueData.league("city")
	t.ok(not league.is_empty() and league["arena"] == "city" and league["hoop"] == "chain" and league["mode"] == "heat_city", "the city league plays the city")
	t.eq(LeagueData.team_ids(league).size(), 8, "eight city teams")
	var chain = app.hoop_for_mode("city")
	t.ok(chain != null and chain.id == "chain" and chain.net_kind == "chain", "city mode resolves the chain hoop regardless of ownership")


func _endless_trial(t) -> void:
	var tt := TimeTrial.new(SimGeometry.city())
	tt.endless = true
	for i in int(3.0 / SimConstants.SIM_DT):
		tt.tick(SimConstants.SIM_DT)
	t.eq(tt.phase, TimeTrial.PHASE_RUNNING, "city trial runs")
	t.ok(not tt.moving, "city hoop never moves")
	t.ok(tt.pickup(), "pickup on the city court")
	t.ok(tt.release(Ballistics.ideal_launch_for(55.0, tt.geo)), "release on the city court")
	for i in int(2.5 / SimConstants.SIM_DT):
		tt.tick(SimConstants.SIM_DT)
	t.eq(tt.makes, 1, "ideal city shot scores")
	t.close(tt.geo.hoop_x, SimGeometry.CITY_DIST, 1e-12, "city hoop stayed put")


## The Vortex card on the city rim: every touched miss becomes a 1-point
## make through one `vortex_pull`; clean swishes stay swishes; airballs stay
## airballs; the ice rule wins; nothing tunnels; all of it deterministic.
func _vortex(t) -> void:
	var g := SimGeometry.city()
	var v := g.with_vortex(true)
	t.ok(v.vortex and not g.vortex, "with_vortex clones the city geometry")
	var pulled := 0
	var checked := 0
	var pen := 0.0
	for a in range(48, 57, 2):
		var ideal: float = Ballistics.speed_for_angle(a, g.hoop_x, g.rise)
		for k in range(-6, 7):
			var launch := {"angle_deg": float(a), "speed": ideal * (1.0 + 0.02 * k)}
			var plain := ShotSim.simulate_shot(launch, false, g)
			var touched: bool = int(plain["rim_contacts"]) + int(plain["board_contacts"]) > 0
			if plain["made"] and plain["type"] == ShotClassify.SWISH:
				var sw := ShotSim.simulate_shot(launch, false, v)
				checked += 1
				t.ok(sw["type"] == ShotClassify.SWISH and int(sw["points"]) == 2 and not sw["vortex"], "a clean swish is still a swish under the vortex")
			elif not plain["made"] and touched:
				var out := ShotSim.simulate_shot(launch, false, v)
				pulled += 1
				pen = maxf(pen, out["max_penetration"])
				var kinds := []
				for ev in out["events"]:
					kinds.push_back(ev["kind"])
				var pull_i: int = kinds.find("vortex_pull")
				var enter_i: int = kinds.rfind("enter")
				t.ok(out["made"] and out["vortex"] and int(out["points"]) == 1 and out["type"] != ShotClassify.SWISH,
					"a touched miss at %d° x%.2f is pulled in for 1 (%s)" % [a, 1.0 + 0.02 * k, out["type"]])
				t.ok(pull_i >= 0 and kinds.count("vortex_pull") == 1 and enter_i > pull_i, "one pull, then the entry")
				if pulled == 1:
					t.eq(JSON.stringify(out), JSON.stringify(ShotSim.simulate_shot(launch, false, v)), "the pull is deterministic")
	t.ok(pulled >= 3, "the sweep found touched misses to pull (%d)" % pulled)
	t.ok(checked >= 1, "and clean swishes to leave alone (%d)" % checked)
	t.ok(pen < 0.02, "no deep penetration under the vortex (%.4f)" % pen)
	var short := Ballistics.ideal_launch_for(52.0, g)
	short["speed"] = short["speed"] * 0.8
	var air := ShotSim.simulate_shot(short, false, v)
	t.ok(not air["made"] and air["type"] == ShotClassify.AIRBALL and not air["vortex"], "an airball never scores")
	# The ice rule wins: iced and spinning, a touched ball is caught, not pulled.
	var both := v.with_ice(true)
	var caught := 0
	for a in range(48, 57, 2):
		var ideal: float = Ballistics.speed_for_angle(a, g.hoop_x, g.rise)
		for k in range(-6, 7):
			var out := ShotSim.simulate_shot({"angle_deg": float(a), "speed": ideal * (1.0 + 0.02 * k)}, false, both)
			t.ok(not out["vortex"], "no pull on an iced rim")
			if out["type"] == ShotClassify.ICE_CAUGHT:
				caught += 1
	t.ok(caught >= 1, "the ice caught touched balls instead (%d)" % caught)
