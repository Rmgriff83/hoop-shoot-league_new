extends RefCounted
## DetRng: determinism, distribution sanity, forks.


func run(t) -> void:
	var a := DetRng.new(42)
	var b := DetRng.new(42)
	var same := true
	for i in 50:
		if a.next() != b.next():
			same = false
	t.ok(same, "same seed → same stream")
	var c := DetRng.new(43)
	t.ok(c.next() != DetRng.new(42).next(), "different seed → different stream")
	var r := DetRng.new(7)
	var lo := 1.0
	var hi := 0.0
	for i in 2000:
		var u := r.next()
		lo = minf(lo, u)
		hi = maxf(hi, u)
	t.ok(lo >= 0.0 and hi < 1.0 and lo < 0.01 and hi > 0.99, "next() spans [0,1)")
	var sum := 0.0
	var sq := 0.0
	var n := 4000
	for i in n:
		var z := r.normal()
		sum += z
		sq += z * z
	var mean := sum / n
	var var_ := sq / n - mean * mean
	t.close(mean, 0.0, 0.06, "normal() mean ≈ 0 (%.3f)" % mean)
	t.close(var_, 1.0, 0.1, "normal() variance ≈ 1 (%.3f)" % var_)
	var counts := {}
	for i in 3000:
		var k := r.range_i(0, 2)
		counts[k] = int(counts.get(k, 0)) + 1
	t.ok(counts.size() == 3 and int(counts[0]) > 800 and int(counts[2]) > 800, "range_i covers the range evenly")
	var f1 := DetRng.new(5).fork("mood")
	var f2 := DetRng.new(5).fork("mood")
	var f3 := DetRng.new(5).fork("rewards")
	t.ok(f1.next() == f2.next(), "fork is deterministic")
	t.ok(DetRng.new(5).fork("mood").next() != f3.next(), "forks with different labels differ")
	t.eq(r.shuffled([1, 2, 3, 4]).size(), 4, "shuffled keeps the items")
	t.ok(r.pick(["x"]) == "x", "pick from one")
