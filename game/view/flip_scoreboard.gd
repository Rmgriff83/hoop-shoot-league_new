class_name FlipScoreboard
extends Node
## The park's analog flip-card scoreboard (Ross's "Park Area Concept",
## 2026-10-16): HOME in black and AWAY in red, two cards each, hung on the
## fence's top rail right of the hoop. It is the park's reader board — what
## the cage's LED, the beach's cabinet and the city's fence scoreboard are
## elsewhere: CourtGeometry.show_score() tallies HOME (this court's score,
## practice and time trial included) and set_visitor() AWAY (the other side
## in a league heat). No clock, no period, no messages: those stay on the HUD
## and the rim pops.
##
## Binds the park glb's FlipBoard subtree by name (build_park.py
## add_flip_board): FlipCard{i} are the static cards, FlipPivot{i} the hidden
## flaps (FlipFront{i} the card face, FlipBack{i} plain stock) on the ring
## axle. Every card is one quad over the park_scorecards.png atlas; a digit
## is a uv1 offset on that card's own material (no per-frame image work).
## When a digit changes the front takes the old digit, the static card the
## new one, and the pivot swings up and over the rings in FLIP_S with the
## design's ease-in-out; advance(dt) steps it headless, _process calls it.

const FLIP_S := 0.42
const SLOTS := 4
const ATLAS_COLS := 10.0

var _cards: Array[MeshInstance3D] = []
var _pivots: Array[Node3D] = []
var _fronts: Array[MeshInstance3D] = []
var _digit: Array[int] = [0, 0, 0, 0]
var _t: Array[float] = [-1.0, -1.0, -1.0, -1.0]
var _home := 0
var _visitor := 0


## Bind the board under `arena`. False (and nothing bound) when any card,
## pivot or front is missing.
func setup(arena: Node) -> bool:
	var board := arena.find_child("FlipBoard", true, false)
	if board == null:
		return false
	var cards: Array[MeshInstance3D] = []
	var pivots: Array[Node3D] = []
	var fronts: Array[MeshInstance3D] = []
	for i in SLOTS:
		var card := board.find_child("FlipCard%d" % i, true, false) as MeshInstance3D
		var piv := board.find_child("FlipPivot%d" % i, true, false) as Node3D
		var front := board.find_child("FlipFront%d" % i, true, false) as MeshInstance3D
		if card == null or piv == null or front == null:
			return false
		cards.push_back(card)
		pivots.push_back(piv)
		fronts.push_back(front)
	_cards = cards
	_pivots = pivots
	_fronts = fronts
	for i in SLOTS:
		_bind(_cards[i])
		_bind(_fronts[i])
		_set_digit(_cards[i], 0, i)
		_set_digit(_fronts[i], 0, i)
		_pivots[i].visible = false
		_pivots[i].rotation = Vector3.ZERO
	return true


## HOME: this court's score (wrapped to two cards).
func set_home(n: int) -> void:
	_home = posmod(n, 100)
	_show(0, _home / 10)
	_show(1, _home % 10)


## AWAY: the other side's score.
func set_visitor(n: int) -> void:
	_visitor = posmod(n, 100)
	_show(2, _visitor / 10)
	_show(3, _visitor % 10)


func home() -> int:
	return _home


func visitor() -> int:
	return _visitor


## True while any card is mid-swing.
func flipping() -> bool:
	for t in _t:
		if t >= 0.0:
			return true
	return false


## The digit a slot shows on its static card (tests).
func digit(slot: int) -> int:
	return _digit[slot]


func _process(dt: float) -> void:
	advance(dt)


## Step every swing. The pivot turns about the lateral (z) axis: the card
## hangs down from the axle and its bottom edge comes up TOWARD the viewer
## and over the rings (the design's rotation.x → -π), so the old digit stays
## in front of the new card until the flap passes vertical and its plain
## back shows. Swung the other way it would sink behind the card stack.
func advance(dt: float) -> void:
	for i in SLOTS:
		if _t[i] < 0.0:
			continue
		_t[i] += dt
		var k := minf(1.0, _t[i] / FLIP_S)
		var e := 2.0 * k * k if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 2.0) / 2.0
		_pivots[i].rotation = Vector3(0.0, 0.0, -PI * e)
		if k >= 1.0:
			_pivots[i].visible = false
			_pivots[i].rotation = Vector3.ZERO
			_t[i] = -1.0


func _show(i: int, d: int) -> void:
	if _digit[i] == d:
		return
	_set_digit(_fronts[i], _digit[i], i)
	_set_digit(_cards[i], d, i)
	_digit[i] = d
	_t[i] = 0.0
	_pivots[i].rotation = Vector3.ZERO
	_pivots[i].visible = true


## Each card gets its own copy of the atlas material so its offset is its own.
static func _bind(mi: MeshInstance3D) -> void:
	var base := mi.get_active_material(0)
	var m: BaseMaterial3D = (base.duplicate() as BaseMaterial3D) if base is BaseMaterial3D else StandardMaterial3D.new()
	m.uv1_scale = Vector3(1.0 / ATLAS_COLS, 0.5, 1.0)
	mi.material_override = m


## Slots 0–1 read the atlas's black row, 2–3 the red.
static func _set_digit(mi: MeshInstance3D, d: int, slot: int) -> void:
	var m := mi.material_override as BaseMaterial3D
	if m != null:
		m.uv1_offset = Vector3(float(d) / ATLAS_COLS, 0.5 if slot >= 2 else 0.0, 0.0)


## The atlas offset a card shows (tests).
static func offset_of(mi: MeshInstance3D) -> Vector3:
	var m := mi.material_override as BaseMaterial3D
	return m.uv1_offset if m != null else Vector3(-1, -1, -1)
