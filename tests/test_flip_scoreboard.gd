extends RefCounted
## The park's flip-card scoreboard (game/view/flip_scoreboard.gd): digits as
## atlas offsets on each card's own material, a changed digit swinging its
## flap up over the rings in FLIP_S, HOME / AWAY wrapped to two cards, the
## park court binding it so show_score() and set_visitor() reach the cards,
## and a court without one unaffected.


func run(t) -> void:
	_board(t)
	_court(t)


## A synthetic FlipBoard tree: four cards, four pivots with a front each.
static func _tree() -> Node3D:
	var board := Node3D.new()
	board.name = "FlipBoard"
	var mat := StandardMaterial3D.new()
	for i in 4:
		var card := MeshInstance3D.new()
		card.name = "FlipCard%d" % i
		card.mesh = QuadMesh.new()
		card.mesh.surface_set_material(0, mat)
		board.add_child(card)
		var piv := Node3D.new()
		piv.name = "FlipPivot%d" % i
		board.add_child(piv)
		var front := MeshInstance3D.new()
		front.name = "FlipFront%d" % i
		front.mesh = QuadMesh.new()
		front.mesh.surface_set_material(0, mat)
		piv.add_child(front)
	return board


func _board(t) -> void:
	var arena := Node3D.new()
	var board := _tree()
	arena.add_child(board)
	var fb := FlipScoreboard.new()
	t.ok(fb.setup(arena), "the board binds four cards, pivots and fronts")
	var cards: Array = []
	var pivots: Array = []
	for i in 4:
		cards.push_back(board.find_child("FlipCard%d" % i, true, false))
		pivots.push_back(board.find_child("FlipPivot%d" % i, true, false))
	t.ok(cards[0].material_override != cards[1].material_override and cards[0].material_override != null, "every card has its own copy of the atlas material")
	t.ok(cards[0].material_override.uv1_scale.is_equal_approx(Vector3(0.1, 0.5, 1.0)), "…scaled to one card of the atlas")
	t.ok(FlipScoreboard.offset_of(cards[0]) == Vector3.ZERO and FlipScoreboard.offset_of(cards[2]) == Vector3(0.0, 0.5, 0.0), "00 00 at first: HOME on the black row, AWAY on the red")
	t.ok(not pivots[0].visible and not fb.flipping(), "the flaps hidden, nothing swinging")
	fb.set_home(7)
	t.eq(fb.home(), 7, "HOME 7")
	t.ok(FlipScoreboard.offset_of(cards[1]).is_equal_approx(Vector3(0.7, 0.0, 0.0)) and FlipScoreboard.offset_of(cards[0]) == Vector3.ZERO, "the ones card shows 7, the tens stays 0")
	t.ok(pivots[1].visible and not pivots[0].visible, "only the changed card's flap swings")
	var front1: MeshInstance3D = board.find_child("FlipFront1", true, false)
	t.ok(FlipScoreboard.offset_of(front1) == Vector3.ZERO, "the flap carries the old digit (0) up")
	fb.advance(FlipScoreboard.FLIP_S / 2.0)
	t.close(pivots[1].rotation.z, -PI / 2.0, 1e-6, "halfway: the card stands straight up, swung toward the viewer (ease-in-out)")
	t.ok(fb.flipping(), "…still swinging")
	fb.advance(FlipScoreboard.FLIP_S / 2.0 + 1e-4)
	t.ok(not pivots[1].visible and pivots[1].rotation.z == 0.0 and not fb.flipping(), "after FLIP_S the flap hides and rests")
	fb.set_home(12)
	t.ok(pivots[0].visible and pivots[1].visible, "7 → 12 flips both cards")
	t.ok(FlipScoreboard.offset_of(cards[0]).is_equal_approx(Vector3(0.1, 0.0, 0.0)) and FlipScoreboard.offset_of(cards[1]).is_equal_approx(Vector3(0.2, 0.0, 0.0)), "…to 1 and 2")
	t.ok(FlipScoreboard.offset_of(front1).is_equal_approx(Vector3(0.7, 0.0, 0.0)), "the ones flap carries the 7 up")
	fb.advance(0.1)
	fb.set_home(13)
	t.ok(FlipScoreboard.offset_of(front1).is_equal_approx(Vector3(0.2, 0.0, 0.0)) and pivots[1].rotation.z == 0.0, "a change mid-swing restarts with the digit just replaced")
	fb.set_home(12)
	fb.advance(1.0)
	fb.set_home(105)
	t.eq(fb.home(), 5, "105 wraps to 05")
	t.ok(FlipScoreboard.offset_of(cards[0]) == Vector3.ZERO, "…the tens back to 0")
	fb.advance(1.0)
	fb.set_visitor(34)
	t.eq(fb.visitor(), 34, "AWAY 34")
	t.ok(FlipScoreboard.offset_of(cards[2]).is_equal_approx(Vector3(0.3, 0.5, 0.0)) and FlipScoreboard.offset_of(cards[3]).is_equal_approx(Vector3(0.4, 0.5, 0.0)), "…on the red row")
	t.ok(not pivots[0].visible and pivots[2].visible, "…HOME untouched")
	fb.set_visitor(34)
	fb.advance(1.0)
	t.ok(not fb.flipping(), "the same score again flips nothing")
	# A board missing a part binds nothing.
	var broken := Node3D.new()
	var half := _tree()
	half.find_child("FlipFront3", true, false).free()
	broken.add_child(half)
	var nope := FlipScoreboard.new()
	t.ok(not nope.setup(broken), "a board short a front does not bind")
	t.ok(not nope.setup(Node3D.new()), "…nor an arena without one")
	nope.free()
	fb.free()
	arena.free()
	broken.free()


func _court(t) -> void:
	var root := Node3D.new()
	var park := CourtGeometry.new()
	park.geo = SimGeometry.park()
	park.arena_set = CosmeticLibrary.get_arena("park")
	park.hoop_set = CosmeticLibrary.get_hoop("park") if CosmeticLibrary.get_hoop("park") != null else CosmeticLibrary.starter_hoop()
	root.add_child(park)
	park._ready()
	var fb := park.flip_board()
	t.ok(fb != null, "the park court binds its flip board")
	if fb != null:
		t.ok(park.info == park.led and not (park.led is Scoreboard), "the LED stays the message channel, the flip board is not a Scoreboard")
		park.show_score(9, 2)
		t.eq(fb.home(), 9, "show_score() tallies HOME")
		t.eq(park.led.idle_text(), "SCORE 9 x2", "…and the LED's idle line as before")
		park.set_visitor(4)
		t.eq(fb.visitor(), 4, "set_visitor() tallies AWAY")
		var board: Node3D = park.find_child("FlipBoard", true, false)
		t.ok(board != null and board.position.x < SimGeometry.PARK_FENCE_X and board.position.x > SimGeometry.PARK_FENCE_X - 0.2 and absf(board.position.z - 0.95) < 0.01, "the board hangs on the court side of the fence, right of the hoop (%s)" % str(board.position if board != null else Vector3.ZERO))
		t.ok(board != null and board.position.y > 0.6 and board.position.y < 1.0, "…at the top rail's height")
	var beach := CourtGeometry.new()
	beach.geo = SimGeometry.beach()
	beach.arena_set = CosmeticLibrary.get_arena("beach")
	beach.hoop_set = CosmeticLibrary.starter_hoop()
	root.add_child(beach)
	beach._ready()
	t.ok(beach.flip_board() == null, "the beach has no flip board")
	beach.show_score(3)
	t.eq(beach.led.idle_text(), "SCORE 3", "…show_score() still reaches its LED")
	root.free()
