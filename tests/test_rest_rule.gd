extends RefCounted
## The rest-speed rule only ends a ball that is down on the floor (Ross,
## 2026-10-16: a make bounced once and vanished, a miss bounced a couple of
## times). A ball is also near-still at the top of every rebound; that must
## not count. Sweeps makes and misses in the park and the arcade and checks
## where every ball ends, and that makes now live as long as misses after
## their first floor touch.


func run(t) -> void:
	for geo_name in ["park", "arcade"]:
		var geo: SimGeometry = SimGeometry.park() if geo_name == "park" else SimGeometry.arcade()
		var mid_air := 0
		var make_life: Array[float] = []
		var miss_life: Array[float] = []
		for ai in range(44, 60, 2):
			var ideal := Ballistics.ideal_launch_for(float(ai), geo)
			if ideal.is_empty():
				continue
			for k in range(-6, 7):
				for vz in [0.0, 0.25, 0.5]:
					var s := ShotSim.create_shot({"angle_deg": float(ai), "speed": ideal["speed"] * (1.0 + 0.012 * k), "vz": vz}, geo)
					var first_floor := -1.0
					var max_steps := ceili(SimConstants.MAX_SHOT_TIME / SimConstants.SIM_DT) + 1
					for i in max_steps:
						ShotSim.step_shot(s)
						if s.floor_hits > 0 and first_floor < 0.0:
							first_floor = s.t
						if s.settled:
							break
					if not s.settled or first_floor < 0.0:
						continue
					var by_rest := s.floor_hits < 3 and s.t <= SimConstants.MAX_SHOT_TIME and s.slow_time <= SimConstants.DEAD_BALL_S
					if by_rest and s.pos.y >= SimConstants.R_BALL * ShotSim.REST_HEIGHT:
						mid_air += 1
					if s.made:
						make_life.push_back(s.t - first_floor)
					else:
						miss_life.push_back(s.t - first_floor)
		t.eq(mid_air, 0, "%s: no ball ends by the rest rule in mid-air" % geo_name)
		make_life.sort()
		miss_life.sort()
		t.ok(make_life.size() > 20 and miss_life.size() > 20, "%s: makes and misses in the sweep (%d / %d)" % [geo_name, make_life.size(), miss_life.size()])
		if make_life.size() > 20 and miss_life.size() > 20:
			var mk: float = make_life[make_life.size() / 2]
			var ms: float = miss_life[miss_life.size() / 2]
			t.ok(mk > 0.9, "%s: a made ball lives on after its first bounce (median %.2f s floor → gone)" % [geo_name, mk])
			t.ok(mk > ms * 0.6, "%s: …about as long as a miss (miss median %.2f s)" % [geo_name, ms])
	# The rule itself still ends a ball that rolls to a stop on the floor.
	var g := SimGeometry.park()
	var r := ShotSim.create_shot({"angle_deg": 52.0, "speed": Ballistics.ideal_launch_for(52.0, g)["speed"]}, g)
	for i in 400:
		ShotSim.step_shot(r)
	r.floor_hits = 1
	r.pos.y = SimConstants.R_BALL
	r.vel = SimVec3.new(0.3, 0.0, 0.0)
	r.settled = false
	r.resolved = false
	ShotSim.step_shot(r)
	t.ok(r.settled, "a slow ball down on the floor is at rest")
	var a := ShotSim.create_shot({"angle_deg": 52.0, "speed": Ballistics.ideal_launch_for(52.0, g)["speed"]}, g)
	a.floor_hits = 1
	a.pos = SimVec3.new(3.0, 1.1, 0.0)
	a.vel = SimVec3.new(0.3, 0.0, 0.0)
	ShotSim.step_shot(a)
	t.ok(not a.settled, "the same speed a metre up (a rebound's apex) is not")
