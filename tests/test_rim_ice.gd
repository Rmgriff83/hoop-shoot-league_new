extends RefCounted
## Rim ice rig: the Blender model loads with its shards and icicles, and the
## freeze / crack / shatter / clear lifecycle behaves.


func run(t) -> void:
	var scene: PackedScene = load("res://assets/fx/rim_ice.glb")
	t.ok(scene != null, "rim_ice.glb loads")
	if scene == null:
		return
	var inst := scene.instantiate()
	var shards := 0
	var icicles := 0
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		if n.name.begins_with("Shard"):
			shards += 1
		elif n.name.begins_with("Icicle"):
			icicles += 1
	inst.free()
	t.eq(shards, 12, "12 shards")
	t.eq(icicles, 4, "4 icicles")

	var ice := RimIce.new()
	ice._ready()
	t.eq(ice._pieces.size(), 16, "rig picked up every piece")
	t.ok(not ice.is_iced() and not ice.visible, "hidden at rest")
	ice.freeze()
	for i in 60:
		ice._process(1.0 / 60.0)
	t.ok(ice.is_iced() and ice.visible, "iced after freeze()")
	t.close(ice.freeze_amount(), 1.0, 0.01, "fully frozen in after 1 s")
	ice.crack(2)
	t.ok(ice.is_iced(), "a crack keeps the ice")
	ice.grab()
	for i in 30:
		ice._process(1.0 / 60.0)
	t.ok(ice.is_iced() and ice._crack > 0.5, "grab spreads the fissures while still iced")
	ice.shatter("swish")
	t.ok(not ice.is_iced(), "shatter ends the ice state at once")
	ice._process(0.1)
	t.ok(ice.visible and ice._mist.visible and ice._crystals.emitting, "shards, mist and crystals showing mid-shatter")
	for i in 90:
		ice._process(1.0 / 60.0)
	t.ok(not ice.visible, "shards gone after the shatter")
	t.eq(ice._pieces[0].transform, ice._rest[0], "pieces reset to rest")
	ice.freeze()
	ice.clear()
	t.ok(not ice.is_iced() and not ice.visible, "clear() is instant")
	ice.free()
