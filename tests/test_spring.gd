extends RefCounted
## Spring behavior: settles to target, kick adds velocity, framerate-independent.


func run(t) -> void:
	# Settles to target.
	var s := JuiceSpring.new(0.0, 170.0, 1.0)
	s.target = 1.0
	for i in 300:
		s.step(1.0 / 60.0)
	t.close(s.value, 1.0, 1e-3, "settles to target")
	t.ok(s.is_settled(), "reports settled")

	# Kick adds velocity and decays back.
	var w := JuiceSpring.new(0.0, 320.0, 0.28)
	w.kick(4.2)
	var peak := 0.0
	for i in 240:
		peak = maxf(peak, absf(w.step(1.0 / 60.0)))
	t.ok(peak > 0.05, "kick produces visible motion (peak %.3f)" % peak)
	for i in 600:
		w.step(1.0 / 60.0)
	t.close(w.value, 0.0, 1e-3, "wobble decays to rest")

	# Framerate independence: 60 Hz vs 240 Hz paths agree within tolerance.
	var a := JuiceSpring.new(0.0, 170.0, 0.8)
	var b := JuiceSpring.new(0.0, 170.0, 0.8)
	a.target = 1.0
	b.target = 1.0
	for i in 60:
		a.step(1.0 / 60.0)
	for i in 240:
		b.step(1.0 / 240.0)
	t.close(a.value, b.value, 0.02, "60Hz vs 240Hz agree after 1s")

	# Underdamped overshoots; critically damped does not.
	var u := JuiceSpring.new(0.0, 170.0, 0.5)
	u.target = 1.0
	var overshoot := 0.0
	for i in 600:
		overshoot = maxf(overshoot, u.step(1.0 / 120.0))
	t.ok(overshoot > 1.01, "underdamped overshoots (%.3f)" % overshoot)

	var cd := JuiceSpring.new(0.0, 170.0, 1.0)
	cd.target = 1.0
	var cd_max := 0.0
	for i in 600:
		cd_max = maxf(cd_max, cd.step(1.0 / 120.0))
	t.ok(cd_max < 1.005, "critically damped stays under target (%.4f)" % cd_max)

	# Spring3 channels are independent.
	var s3 := JuiceSpring.Spring3.new(0.0, 0.0, 0.0, 170.0, 1.0)
	s3.set_target(1.0, 2.0, 3.0)
	for i in 300:
		s3.step(1.0 / 60.0)
	t.close(s3.x.value, 1.0, 1e-3, "Spring3 x")
	t.close(s3.y.value, 2.0, 1e-3, "Spring3 y")
	t.close(s3.z.value, 3.0, 1e-3, "Spring3 z")
