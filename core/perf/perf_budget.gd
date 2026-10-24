class_name PerfBudget
extends RefCounted
## The performance budget (docs/PERFORMANCE.md): data/perf_budget.json holds
## the baseline row (the cage's league heat with the PiP open, measured on
## Ross's phone by --qa-perf) and the headroom each number may take above it.
## `compare` judges one --qa-perf row against it — the ledger
## (tools/perf_ledger.gd) prints the gaps, the suite checks the arithmetic.
## Frame time, hitches, draw calls (visible + shadow, both viewports), script
## time and see-through coverage are enforced; triangles are only logged.
## Headless, pure.

const PATH := "res://data/perf_budget.json"

static var _doc: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.open(PATH, FileAccess.READ).get_as_text())
		if parsed is Dictionary:
			_doc = parsed


static func doc() -> Dictionary:
	_load()
	return _doc


static func baseline() -> Dictionary:
	return doc().get("baseline", {})


static func headroom() -> Dictionary:
	return doc().get("headroom", {})


## Draw calls in a row: visible + shadow, main + PiP.
static func draws_total(row: Dictionary) -> int:
	var n := 0
	for k in ["main", "pip"]:
		var v: Dictionary = row.get(k, {}) if row.get(k) is Dictionary else {}
		n += int(v.get("draws_v", 0)) + int(v.get("draws_s", 0))
	return n


## Triangles in a row (logged, never enforced): visible + shadow, main + PiP.
static func prims_total(row: Dictionary) -> int:
	var n := 0
	for k in ["main", "pip"]:
		var v: Dictionary = row.get(k, {}) if row.get(k) is Dictionary else {}
		n += int(v.get("prims_v", 0)) + int(v.get("prims_s", 0))
	return n


## The limits a row must sit under, from the baseline row × the headroom:
## {frame_p50, frame_p95, frame_p99, hitches_per_60s, spikes_per_60s, draws_total, script_p95, coverage_max}.
## Hitches are frames over an absolute `hitch_ms`; spikes are frames one
## refresh period over that run's own p50 (never under 1.5 × it) — the stutter
## a player feels at any frame rate, without counting a vsync phone's ordinary
## dropped frames.
## On a device whose baseline p50 already sits near `hitch_ms` (the phone runs
## the cage at ~19 ms) nearly every frame is a "hitch", so the absolute count
## is not enforced there (limit INF; `hitches_enforced` says so) — the spikes
## carry the stutter check.
static func limits(base: Dictionary, hr: Dictionary) -> Dictionary:
	var out := {}
	for k in ["frame_p50", "frame_p95", "frame_p99", "script_p95"]:
		out[k] = float(base.get(k, 0.0)) * float(hr.get(k, 1.0))
	var hitch_ms := float(doc().get("hitch_ms", 20))
	out["hitches_enforced"] = float(base.get("frame_p50", 0.0)) < 0.8 * hitch_ms
	out["hitches_per_60s"] = maxf(float(base.get("hitches_per_60s", 0.0)) + float(hr.get("hitches_plus", 2)), float(hr.get("hitches_floor", 3))) if out["hitches_enforced"] else INF
	out["spikes_per_60s"] = maxf(float(base.get("spikes_per_60s", 0.0)) + float(hr.get("spikes_plus", 3)), float(hr.get("spikes_floor", 6)))
	out["draws_total"] = float(draws_total(base)) * float(hr.get("draws_total", 1.5))
	out["coverage_max"] = float(hr.get("coverage_max", 1.5))
	return out


## The gaps of one row against the limits: ["beach heat_pip frame_p95 24.1 ms > 19.6", …]; [] inside the budget.
static func compare(row: Dictionary, base: Dictionary, hr: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if base.is_empty():
		out.push_back("no baseline measured yet (run --qa-perf on the phone and copy the cage heat_pip row into data/perf_budget.json)")
		return out
	var lim := limits(base, hr)
	var who := "%s %s" % [row.get("area", "?"), row.get("mode", "?")]
	for k in ["frame_p50", "frame_p95", "frame_p99", "script_p95"]:
		var v := float(row.get(k, 0.0))
		if v > float(lim[k]):
			out.push_back("%s %s %.1f ms > %.1f" % [who, k, v, lim[k]])
	var h := float(row.get("hitches_per_60s", 0.0))
	if h > float(lim["hitches_per_60s"]):
		out.push_back("%s hitches %.1f/60s > %.1f" % [who, h, lim["hitches_per_60s"]])
	var s := float(row.get("spikes_per_60s", 0.0))
	if s > float(lim["spikes_per_60s"]):
		out.push_back("%s spikes %.1f/60s > %.1f (frames a refresh period over the run's p50)" % [who, s, lim["spikes_per_60s"]])
	var d := draws_total(row)
	if d > float(lim["draws_total"]):
		out.push_back("%s draws %d > %d (visible + shadow, both views)" % [who, d, roundi(lim["draws_total"])])
	var c := float(row.get("coverage_max", 0.0))
	if c > float(lim["coverage_max"]):
		out.push_back("%s see-through coverage %.2f screens > %.2f" % [who, c, lim["coverage_max"]])
	return out


static func header_text() -> String:
	return "  %-6s %-16s %6s %6s %6s %5s %5s | %6s %6s %6s %6s | %5s %5s | %6s %5s %5s %6s | %7s" % [
		"area", "mode", "p50", "p95", "p99", "hit60", "spk60", "mainC", "mainG", "pipC", "pipG", "drwV", "drwS", "script", "sim", "cov", "pipDrw", "tris"]


static func row_text(row: Dictionary) -> String:
	var m: Dictionary = row.get("main", {}) if row.get("main") is Dictionary else {}
	var p: Dictionary = row.get("pip", {}) if row.get("pip") is Dictionary else {}
	var gpu := func(v: Dictionary) -> String:
		return "n/a" if float(v.get("gpu", 0.0)) <= 0.0 else "%.1f" % float(v.get("gpu", 0.0))
	return "  %-6s %-16s %6.1f %6.1f %6.1f %5.0f %5.1f | %6.1f %6s %6s %6s | %5d %5d | %6.1f %5.1f %5.2f %6s | %7d" % [
		row.get("area", "?"), row.get("mode", "?"), float(row.get("frame_p50", 0)), float(row.get("frame_p95", 0)), float(row.get("frame_p99", 0)), float(row.get("hitches_per_60s", 0)), float(row.get("spikes_per_60s", 0)),
		float(m.get("cpu", 0)), gpu.call(m), ("%.1f" % float(p.get("cpu", 0))) if not p.is_empty() else "-", gpu.call(p) if not p.is_empty() else "-",
		int(m.get("draws_v", 0)), int(m.get("draws_s", 0)), float(row.get("script_p95", 0)), float(row.get("sim_p95", 0)), float(row.get("coverage_max", 0)),
		("%d+%d" % [int(p.get("draws_v", 0)), int(p.get("draws_s", 0))]) if not p.is_empty() else "-", prims_total(row)]
