extends Node3D
## Dev scene: infinite balls, no clock — exists to tune the flick before the
## game mode wraps it. Steps raw BallStates at the sim's fixed 240 Hz and logs
## every outcome to the F3 overlay.
## NOTE: the lab still uses the legacy drag-length flick model from the fixed
## release point (it wires neither drag_moved nor aim-by-pointing).

var geo := SimGeometry.arcade(2.9)  # matches the time trial's starting distance
var tuning := FlickTuning.new()
var _flights: Array[Dictionary] = []  # { "state": BallState, "scored": bool }
var _accumulator := 0.0
var _holding := false

@onready var _pool := BallPool.new()
@onready var _overlay := TuningOverlay.new()


func _ready() -> void:
	var court := CourtGeometry.new()
	court.name = "Court"
	court.geo = geo
	court.debug_markers = true
	add_child(court)

	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.position = Vector3(-0.9, 1.55, 0.0)
	cam.fov = 60.0
	add_child(cam)
	cam.look_at(Vector3(geo.hoop_x, 2.2, 0.0))

	_pool.name = "Balls"
	add_child(_pool)

	_overlay.name = "Overlay"
	_overlay.tuning = tuning
	_overlay.geo = geo
	add_child(_overlay)
	_overlay.visible = true

	var input := FlickInput.new()
	input.name = "FlickInput"
	add_child(input)
	input.grab_pressed.connect(_on_grab)
	input.flick_released.connect(_on_flick)


func _on_grab() -> void:
	_holding = true


func _on_flick(sample: Dictionary) -> void:
	if not _holding:
		return
	_holding = false
	var launch := FlickMap.map_flick(sample, tuning, geo)
	_overlay.record_flick(sample, launch)
	if launch.is_empty():
		return
	_flights.push_back({"state": ShotSim.create_shot(launch, geo), "scored": false})


## Frame-delta clamp (s), same as time_trial_screen.gd: no backlog dumps.
const MAX_FRAME_DT := 0.05


func _process(dt: float) -> void:
	_accumulator += minf(dt, MAX_FRAME_DT)
	while _accumulator >= SimConstants.SIM_DT:
		_accumulator -= SimConstants.SIM_DT
		for f in _flights:
			var s: BallState = f["state"]
			if s.settled:
				continue
			ShotSim.step_shot(s)
			if s.resolved and not f["scored"]:
				f["scored"] = true
				_overlay.record_outcome(ShotClassify.classify_shot(s))
	var kept: Array[Dictionary] = []
	var balls: Array[BallState] = []
	for f in _flights:
		var s: BallState = f["state"]
		if not s.settled or not f["scored"]:
			kept.push_back(f)
			balls.push_back(s)
	_flights = kept
	_pool.update_balls(balls, _holding, dt)
