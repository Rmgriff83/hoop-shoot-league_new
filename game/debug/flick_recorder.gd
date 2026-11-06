class_name FlickRecorder
extends CanvasLayer
## Records Ross's real flicks for the trailer (docs/TRAILER.md → Recording
## flicks). Debug builds only, switched on in Settings → DEV → RECORD FLICKS.
## Every release appends one JSON line to user://trailer/flicks.jsonl: the
## touch trace ([usec, x, y] in design px, what FlickInput replays through
## _begin_at / _move_at / _end_at), the launch it mapped to, where it was
## thrown from (mode, area, spot, hand origin, hoop pose), the kit worn, the
## phone's tuning values, and the outcome once the ball settles. The trailer
## director feeds the trace back through the real estimator and sim on the
## Mac, so the footage has a human's rhythm, misses and rim rattles.
##   tools/trailer/pull_flicks.sh   (copies the file off the phone)
## A small "REC n" sits in the corner while it runs, so a recording session
## is never a silent one; the trailer itself is captured with this off.

const DIR := "user://trailer"
const PATH := DIR + "/flicks.jsonl"
const VERSION := 1
## An outcome a row can carry besides ShotClassify's types.
const CANCELLED := "CANCELLED"

var path := PATH
var session := ""
var _pending: Array = []
var _seq := 0
var _label: Label


static func enabled() -> bool:
	return OS.is_debug_build() and App.record_flicks


func _init() -> void:
	name = "FlickRecorder"
	layer = 12
	session = str(int(Time.get_unix_time_from_system()))
	_label = RetroTheme.caps("", 16, Color("#FF6A5C"))
	_label.name = "Rec"
	RetroTheme.on_scene(_label)
	_label.add_theme_color_override("font_color", Color("#FF6A5C"))
	_label.position = Vector2(16, 520)   # the left edge, clear of the HUD's rows
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_show_count()


func count() -> int:
	return _seq


func pending() -> int:
	return _pending.size()


## A release. A cancelled gesture is written at once; a shot waits for its
## outcome (balls land in the order they left, near enough: the flick bank
## re-runs each launch through the sim and has the last word).
func note_flick(ctx: Dictionary, sample: Dictionary, launch: Dictionary, origin: Dictionary, tuning: Dictionary, geo: SimGeometry) -> void:
	if not sample.has("trace"):
		return
	var row := row_for(ctx, sample, launch, origin, tuning, geo)
	row["session"] = session
	row["seq"] = _seq
	_seq += 1
	_show_count()
	if launch.is_empty():
		row["outcome"] = {"type": CANCELLED, "made": false}
		_write(row)
	else:
		_pending.push_back(row)


func note_outcome(outcome: Dictionary) -> void:
	if _pending.is_empty():
		return
	var row: Dictionary = _pending.pop_front()
	row["outcome"] = outcome_for(outcome)
	_write(row)


## Leaving the court: shots still in the air go out with no outcome.
func flush() -> void:
	for row in _pending:
		row["outcome"] = null
		_write(row)
	_pending.clear()


## One recorded flick. Pure: the trace and the numbers a replay needs.
static func row_for(ctx: Dictionary, sample: Dictionary, launch: Dictionary, origin: Dictionary, tuning: Dictionary, geo: SimGeometry) -> Dictionary:
	return {
		"v": VERSION,
		"t_ms": int(Time.get_unix_time_from_system() * 1000.0),
		"ctx": clean(ctx),
		"origin": clean(origin),
		"geo": {"hoop_x": geo.hoop_x, "hoop_z": geo.hoop_z, "hoop_y": geo.hoop_y, "release_h": geo.release_h} if geo != null else {},
		"tuning": clean(tuning),
		"sample": clean(sample),
		"launch": clean(launch),
	}


static func outcome_for(outcome: Dictionary) -> Dictionary:
	return clean({"type": str(outcome.get("type", "")), "made": bool(outcome.get("made", false)),
		"points": int(outcome.get("points", 0)), "entry_angle_deg": outcome.get("entry_angle_deg", null)})


## JSON-safe: NaN and infinity become null (JSON has neither), nested values follow.
static func clean(v: Variant) -> Variant:
	if v is float:
		return null if is_nan(v) or is_inf(v) else v
	if v is Dictionary:
		var d := {}
		for k in v:
			d[str(k)] = clean(v[k])
		return d
	if v is Array:
		return (v as Array).map(func(x: Variant) -> Variant: return clean(x))
	return v


func _write(row: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	f.store_line(JSON.stringify(row))
	f.close()


func _show_count() -> void:
	if _label != null:
		_label.text = "REC %d" % _seq
