extends SceneTree
## Performance ledger (docs/PERFORMANCE.md): reads a --qa-perf dump
## (user://qa/perf.json, or the one pulled off the phone) and judges every
## area × mode against data/perf_budget.json — the cage's league heat on
## Ross's phone plus the headroom. Prints the table and the gaps; exits 1 on
## a break, 2 with no baseline yet.
##   godot --headless --path . -s tools/perf_ledger.gd -- --in=build/qa/phone/perf.json
##   … -- --in=<dump> --set-baseline     copies the dump's cage heat_pip row (and the
##                                        device) into data/perf_budget.json first


func _initialize() -> void:
	var path := "user://qa/perf.json"
	var set_baseline := false
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--in="):
			path = str(a).trim_prefix("--in=")
		elif str(a) == "--set-baseline":
			set_baseline = true
	if not FileAccess.file_exists(path):
		print("no dump at %s (run --qa-perf first)" % path)
		quit(2)
		return
	var dump: Variant = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
	if not (dump is Dictionary) or not (dump.get("runs") is Array):
		print("not a --qa-perf dump: %s" % path)
		quit(2)
		return
	var dev: Dictionary = dump.get("device", {})
	if set_baseline:
		var picked := {}
		for r in dump["runs"]:
			if str(r.get("area", "")) == str(PerfBudget.baseline().get("area", "cage")) and str(r.get("mode", "")) == str(PerfBudget.baseline().get("mode", "heat_pip")):
				picked = r
				break
		if picked.is_empty():
			print("no %s %s row in the dump to take as the baseline" % [PerfBudget.baseline().get("area", "cage"), PerfBudget.baseline().get("mode", "heat_pip")])
			quit(2)
			return
		var doc := PerfBudget.doc().duplicate(true)
		var measured := picked.duplicate(true)
		measured.erase("hitch_log")
		doc["baseline"]["device"] = "%s · %s · %s" % [dev.get("model", "?"), dev.get("renderer", "?"), dev.get("adapter", "?")]
		doc["baseline"]["measured_when"] = str(dump.get("when", ""))
		doc["baseline"]["measured"] = measured
		var f := FileAccess.open(PerfBudget.PATH, FileAccess.WRITE)
		f.store_string(JSON.stringify(doc, "  ") + "\n")
		f.close()
		print("BASELINE  %s %s on %s written to %s" % [picked.get("area", "?"), picked.get("mode", "?"), doc["baseline"]["device"], PerfBudget.PATH])
		dump = JSON.parse_string(FileAccess.open(path, FileAccess.READ).get_as_text())
		PerfBudget._loaded = false
	print("PERF  %s · %s · %s · %s (%s, %.0f s after a %.0f s warm-up)" % [dev.get("model", "?"), dev.get("os", "?"), dev.get("renderer", "?"), dev.get("adapter", "?"),
		dump.get("when", "?"), float(dump.get("seconds", 0)), float(dump.get("warmup_s", 0))])
	print(PerfBudget.header_text())
	for r in dump["runs"]:
		print(PerfBudget.row_text(r))
	var base: Dictionary = Dictionary(PerfBudget.baseline().get("measured", {}))
	var hr := PerfBudget.headroom()
	print("BUDGET  baseline %s %s on %s × headroom %s" % [PerfBudget.baseline().get("area", "?"), PerfBudget.baseline().get("mode", "?"),
		PerfBudget.baseline().get("device", "(none yet)"), JSON.stringify(hr)])
	if base.is_empty():
		print("NO BASELINE — copy the phone's cage heat_pip row into data/perf_budget.json → baseline.measured")
		quit(2)
		return
	var lim := PerfBudget.limits(base, hr)
	print("  limits: p50 %.1f · p95 %.1f · p99 %.1f ms · hitches %s · spikes %.1f/60s · draws %d · script p95 %.1f ms · coverage %.2f" % [
		lim["frame_p50"], lim["frame_p95"], lim["frame_p99"], ("%.1f/60s" % lim["hitches_per_60s"]) if bool(lim["hitches_enforced"]) else "not enforced (baseline p50 near hitch_ms; spikes carry stutter)",
		lim["spikes_per_60s"], roundi(lim["draws_total"]), lim["script_p95"], lim["coverage_max"]])
	var problems := PackedStringArray()
	for r in dump["runs"]:
		problems.append_array(PerfBudget.compare(r, base, hr))
	if problems.is_empty():
		print("OK — every area and mode inside the budget.")
	else:
		for p in problems:
			print("OVER  %s" % p)
	quit(0 if problems.is_empty() else 1)
