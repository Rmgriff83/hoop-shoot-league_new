extends SceneTree
## Headless test runner: godot --headless --path . -s tests/run_tests.gd
## Discovers tests/test_*.gd, calls run(t) on each, exits 1 on any failure.

const TESTS_DIR := "res://tests"


class T:
	var failures: Array[String] = []
	var count := 0
	var current_file := ""

	func ok(cond: bool, msg: String) -> void:
		count += 1
		if not cond:
			failures.append("%s: %s" % [current_file, msg])

	func eq(a: Variant, b: Variant, msg: String) -> void:
		ok(a == b, "%s (got %s, want %s)" % [msg, str(a), str(b)])

	func close(a: float, b: float, tol: float, msg: String) -> void:
		ok(absf(a - b) <= tol, "%s (got %.6f, want %.6f ±%.6f)" % [msg, a, b, tol])


func _initialize() -> void:
	var t := T.new()
	var dir := DirAccess.open(TESTS_DIR)
	if dir == null:
		printerr("cannot open " + TESTS_DIR)
		quit(1)
		return
	var files: Array[String] = []
	for f in dir.get_files():
		if f.begins_with("test_") and (f.ends_with(".gd") or f.ends_with(".gd.remap")):
			files.append(f.trim_suffix(".remap"))
	files.sort()
	for f in files:
		t.current_file = f
		var before := t.failures.size()
		var script: GDScript = load(TESTS_DIR + "/" + f)
		# A test file that fails to PARSE used to be silently skipped: the run
		# still reported zero failures, which hides a compile error in anything
		# the test imports — a broken view script can pass the whole suite.
		# A parse error yields an INVALID GDScript, not null, so a null check
		# alone misses it; can_instantiate() is the one that actually catches it.
		if script == null or not script.can_instantiate():
			t.failures.push_back("%s: failed to load (parse error in it or something it imports)" % f)
			print("[FAIL] %s" % f)
			continue
		var inst: Object = script.new()
		inst.run(t)
		print("[%s] %s" % ["PASS" if t.failures.size() == before else "FAIL", f])
	print("---")
	print("%d assertions, %d failures" % [t.count, t.failures.size()])
	for msg in t.failures:
		printerr("  FAIL " + msg)
	quit(1 if t.failures.size() > 0 else 0)
