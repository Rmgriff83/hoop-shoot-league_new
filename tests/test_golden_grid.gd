extends RefCounted
## Fidelity keystone: replays the launch grid dumped from the ORIGINAL
## TypeScript sim (tools/dump_golden.mjs → fixtures/golden_grid.json) and
## requires ≥98% exact outcome-type agreement. Both sims are float64; the
## mismatch budget exists only for knife-edge collision-basin boundaries where
## libm rounding differs.
##
## Known, deliberate divergence: the reference board collider was a half-space
## with a hard cutoff at the board's top/side edges (a ball crossing the top
## edge got an instant deep contact and pinned there with sim time frozen — the
## "stuck on top of the backboard" bug). The port models the board as a thin
## box with continuous edge contacts. Fixtures whose trajectory touches a board
## edge therefore encode the old bug and are excluded from the agreement score;
## MAX_EDGE_ROWS caps how many may be excluded so the carve-out can't mask a
## real regression (88 of 1785 at the time of the fix).

const FIXTURE := "res://tests/fixtures/golden_grid.json"
const MIN_AGREEMENT := 0.98
const MAX_EDGE_ROWS := 120


func run(t) -> void:
	t.ok(SimGeometry.regulation().hoop_z == 0.0, "golden path: regulation hoop_z is exactly 0")
	var raw := FileAccess.get_file_as_string(FIXTURE)
	t.ok(raw != "", "golden fixture readable")
	if raw == "":
		return
	var rows: Array = JSON.parse_string(raw)
	t.ok(rows.size() > 1500, "golden fixture has full grid (%d rows)" % rows.size())

	var match_count := 0
	var edge_rows := 0
	var mismatches: Array[String] = []
	for row: Dictionary in rows:
		var launch := {
			"angle_deg": float(row["angle_deg"]),
			"speed": float(row["speed"]),
			"vz": float(row["vz"]),
		}
		var out := ShotSim.simulate_shot(launch)
		if _touched_board_edge(out["events"]):
			edge_rows += 1
			continue
		var agree: bool = (
			out["type"] == row["type"]
			and out["points"] == int(row["points"])
			and out["made"] == bool(row["made"])
		)
		if agree:
			match_count += 1
		elif mismatches.size() < 12:
			mismatches.push_back(
				"%.1f°/%.2f/vz=%.1f: gd=%s(%d) ts=%s(%d)" % [
					launch["angle_deg"], launch["speed"], launch["vz"],
					out["type"], out["points"], row["type"], int(row["points"]),
				]
			)

	var scored := rows.size() - edge_rows
	var agreement := float(match_count) / float(scored)
	print("    golden grid agreement: %d/%d = %.2f%% (%d board-edge rows excluded)" % [
		match_count, scored, agreement * 100.0, edge_rows])
	for m in mismatches:
		print("      mismatch: " + m)
	t.ok(edge_rows <= MAX_EDGE_ROWS, "board-edge exclusions %d <= %d" % [edge_rows, MAX_EDGE_ROWS])
	t.ok(agreement >= MIN_AGREEMENT,
		"golden agreement %.4f >= %.2f" % [agreement, MIN_AGREEMENT])


## A board contact whose normal is not straight back (−x) came from the box's
## top/side/bottom edge — geometry the reference collider did not have.
static func _touched_board_edge(events: Array) -> bool:
	for ev in events:
		if ev["kind"] == "board" and (absf(ev["normal"]["y"]) > 1e-9 or absf(ev["normal"]["z"]) > 1e-9):
			return true
	return false
