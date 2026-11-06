extends SceneTree
## The flick bank (docs/TRAILER.md → The flick bank): every recording pulled
## off the phone, checked and indexed for the director.
##   godot --headless --path . -s tools/trailer/flick_bank.gd
## Reads marketing/trailer/flicks/flicks_*.jsonl, and for each flick:
## replays its trace through the real estimator, maps it with the phone's
## tuning values on that court's geometry from the recorded hand position,
## and runs the launch through the sim. `replays` is true when that launch
## is the one the phone made (to a thousandth); `outcome` is what the sim
## says happened, which has the last word over the phone's own note (two
## balls in the air can swap theirs). Writes
## marketing/trailer/flicks/bank.json and prints what there is per court and
## outcome, so it is plain which shots still stand on stand-in flicks.

const DIR := "res://marketing/trailer/flicks"
const OUT := DIR + "/bank.json"


func _initialize() -> void:
	var app: Node = root.get_node_or_null("App")
	var rows := []
	var abs_dir := ProjectSettings.globalize_path(DIR)
	var files := Array(DirAccess.get_files_at(abs_dir)) if DirAccess.dir_exists_absolute(abs_dir) else []
	files.sort()
	for file in files:
		if not (str(file).begins_with("flicks_") and str(file).ends_with(".jsonl")):
			continue
		for line in FileAccess.get_file_as_string("%s/%s" % [DIR, file]).split("\n"):
			var parsed: Variant = JSON.parse_string(line) if line.strip_edges() != "" else null
			if parsed is Dictionary and parsed.get("sample") is Dictionary:
				rows.push_back(parsed)
	var seen := {}
	var out := []
	var tally := {}
	for row in rows:
		var id := "%s:%d" % [str(row.get("session", "?")), int(row.get("seq", 0))]
		if seen.has(id):
			continue   # the same flick pulled twice
		seen[id] = true
		var checked := check(row, app)
		checked["id"] = id
		out.push_back(checked)
		var key := "%s  %s%s" % [str(Dictionary(row.get("ctx", {})).get("area", "?")), str(checked["outcome"]), "" if bool(checked["replays"]) else "  (does not replay)"]
		tally[key] = int(tally.get(key, 0)) + 1
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"rows": out}))
		f.close()
	print("flick bank: %d flicks from %d files → %s" % [out.size(), files.size(), OUT])
	var keys := tally.keys()
	keys.sort()
	for k in keys:
		print("  %3d  %s" % [tally[k], k])
	quit(0)


## The row with `outcome`, `phone_outcome` and `replays` added.
static func check(row: Dictionary, app: Node) -> Dictionary:
	var out := row.duplicate(true)
	var ctx: Dictionary = row.get("ctx", {})
	var phone: Variant = row.get("outcome")
	out["phone_outcome"] = str(phone.get("type", "")) if phone is Dictionary else ""
	out["outcome"] = out["phone_outcome"]
	out["replays"] = false
	var sample: Dictionary = row["sample"]
	var trace: Array = sample.get("trace", [])
	var launch: Dictionary = row.get("launch", {}) if row.get("launch") is Dictionary else {}
	if trace.size() < 2 or launch.is_empty() or app == null:
		return out
	var tuning := FlickTuning.new()
	tuning.apply_dict(row.get("tuning", {}))
	var geo: SimGeometry = app.call("geo_for_mode", str(ctx.get("mode", "practice")))
	var g: Dictionary = row.get("geo", {})
	if bool(ctx.get("moving", false)) and g.has("hoop_x"):
		geo = geo.with_pose(float(g["hoop_x"]), float(g.get("hoop_z", 0.0)))
	var again := FlickSynth.sample_of({"trace": trace, "lift_usec": int(sample.get("lift_usec", trace[-1][0]))})
	if again.is_empty():
		return out
	var relaunch := FlickMap.map_windup(again, tuning, geo, row.get("origin", {}))
	if relaunch.is_empty():
		return out
	out["replays"] = absf(float(relaunch["speed"]) - float(launch.get("speed", 0.0))) < 0.001 \
		and absf(float(relaunch["angle_deg"]) - float(launch.get("angle_deg", 0.0))) < 0.001
	out["outcome"] = str(ShotClassify.classify_shot(ShotSim.run_shot(relaunch, false, geo))["type"])
	return out
