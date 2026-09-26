extends RefCounted
## Port of tests/ballistics.spec.ts — the handoff §3 table is ground truth.
## If these drift, the feel contract is broken: fix the physics, never the fixtures.

const TABLE := [
	{"angle": 42.0, "speed": 9.14, "apex": 4.01, "time": 1.07, "entry": 32.5},
	{"angle": 45.0, "speed": 9.04, "apex": 4.18, "time": 1.13, "entry": 36.4},
	{"angle": 48.0, "speed": 9.0, "apex": 4.38, "time": 1.2, "entry": 40.3},
	{"angle": 52.0, "speed": 9.03, "apex": 4.68, "time": 1.3, "entry": 45.5},
	{"angle": 55.0, "speed": 9.12, "apex": 4.95, "time": 1.38, "entry": 49.4},
]


func run(t) -> void:
	for row: Dictionary in TABLE:
		var a: float = row["angle"]
		var v := Ballistics.speed_for_angle(a)
		t.ok(not is_nan(v), "speed_for_angle(%d) reachable" % int(a))
		t.close(v, row["speed"], 0.05, "speed at %d°" % int(a))
		t.close(Ballistics.apex_height(a, v), row["apex"], 0.05, "apex at %d°" % int(a))
		t.close(Ballistics.flight_time(a, v), row["time"], 0.05, "flight time at %d°" % int(a))
		t.close(Ballistics.entry_angle(a, v), row["entry"], 0.5, "entry angle at %d°" % int(a))

	for a in range(40, 59):
		var v := Ballistics.speed_for_angle(float(a))
		t.ok(v > 8.9 and v < 9.45, "flat velocity band at %d° (got %.3f)" % [a, v])

	t.ok(is_nan(Ballistics.speed_for_angle(5.0)), "5° unreachable")
	t.ok(is_nan(Ballistics.speed_for_angle(-10.0)), "-10° unreachable")

	var ideal := Ballistics.ideal_launch(48.0)
	t.close(ideal["speed"], 9.0, 0.05, "ideal_launch speed at 48°")
	var p := Ballistics.arc_point(ideal, 0.5)
	t.close(p.x, ideal["speed"] * cos(deg_to_rad(48.0)) * 0.5, 1e-9, "arc_point x at t=0.5")
	t.close(p.z, 0.0, 1e-12, "arc_point z defaults to 0")
