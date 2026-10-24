extends RefCounted
## The performance budget (docs/PERFORMANCE.md): data/perf_budget.json has
## its shape, PerfBudget's limits and gaps follow the headroom, and the table
## text renders a row (and a row without a PiP).


func run(t) -> void:
	var hr := PerfBudget.headroom()
	for k in ["frame_p50", "frame_p95", "frame_p99", "draws_total", "script_p95", "coverage_max", "hitches_plus", "hitches_floor", "spikes_plus", "spikes_floor"]:
		t.ok(hr.has(k), "headroom has %s" % k)
	t.ok(float(hr["frame_p50"]) >= 1.0 and float(hr["frame_p99"]) >= float(hr["frame_p95"]), "headroom widens with the percentile")
	t.ok(PerfBudget.baseline().has("measured"), "the baseline slot exists")
	var base := {"frame_p50": 12.0, "frame_p95": 20.0, "frame_p99": 24.0, "hitches_per_60s": 1.0, "script_p95": 4.0,
		"main": {"draws_v": 100, "draws_s": 20, "prims_v": 5000, "prims_s": 1000}, "pip": {"draws_v": 40, "draws_s": 10, "prims_v": 2000, "prims_s": 500}}
	var h := {"frame_p50": 1.15, "frame_p95": 1.25, "frame_p99": 1.35, "hitches_plus": 2, "hitches_floor": 3, "spikes_plus": 3, "spikes_floor": 6, "draws_total": 1.5, "script_p95": 1.3, "coverage_max": 1.5}
	t.eq(PerfBudget.draws_total(base), 170, "draws: visible + shadow, both views")
	t.eq(PerfBudget.prims_total(base), 8500, "triangles the same way")
	var lim := PerfBudget.limits(base, h)
	t.close(float(lim["frame_p95"]), 25.0, 1e-9, "p95 limit = base × headroom")
	t.close(float(lim["hitches_per_60s"]), 3.0, 1e-9, "hitches: base + 2, floored at 3")
	var slow := base.duplicate(true)
	slow["frame_p50"] = 19.0
	slow["hitches_per_60s"] = 1000.0
	t.ok(not bool(PerfBudget.limits(slow, h)["hitches_enforced"]) and PerfBudget.limits(slow, h)["hitches_per_60s"] == INF, "a baseline near the hitch threshold turns the absolute hitch count off")
	t.close(float(lim["spikes_per_60s"]), 6.0, 1e-9, "spikes: base + 3, floored at 6")
	t.close(float(lim["draws_total"]), 255.0, 1e-9, "draws × 1.5")
	t.eq(PerfBudget.compare(base, base, h), PackedStringArray(), "the baseline itself is inside")
	var over := base.duplicate(true)
	over["area"] = "beach"
	over["mode"] = "heat_pip"
	over["frame_p95"] = 26.0
	over["hitches_per_60s"] = 5.0
	over["spikes_per_60s"] = 9.0
	over["coverage_max"] = 1.8
	over["main"]["draws_v"] = 300
	var gaps := PerfBudget.compare(over, base, h)
	t.eq(gaps.size(), 5, "five gaps named (%s)" % str(gaps))
	t.ok(str(gaps[0]).begins_with("beach heat_pip frame_p95 26.0 ms > 25.0"), "the gap line names the run, the number and the limit")
	t.eq(PerfBudget.compare(over, {}, h).size(), 1, "no baseline: one line saying so")
	t.ok(PerfBudget.row_text(over).contains("beach") and PerfBudget.row_text(over).contains("n/a"), "a row renders; a GPU time of 0 reads n/a")
	var no_pip := base.duplicate(true)
	no_pip.erase("pip")
	no_pip["area"] = "cage"
	no_pip["mode"] = "trial"
	t.ok(PerfBudget.row_text(no_pip).contains("  -"), "a trial row has no PiP column values")
	t.ok(PerfBudget.header_text().contains("p95") and PerfBudget.header_text().contains("pipDrw"), "the header")
