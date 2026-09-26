class_name Interactable
extends Node3D
## A prop in an arena the player can tap. Data-driven per area
## (ArenaSet.interactables: {kind, node, pad, ...params}); the kind picks a
## subclass (InteractableKinds). Picking is pure math — a camera ray against
## the target's local bounding box — so it runs headless. Presentation only:
## nothing here touches the sim.

var target: Node3D
var params: Dictionary = {}
var _box := AABB()


## Bind to the glb node this stands for; `pad` (m) grows the tap box a little.
func setup(p_target: Node3D, p_params: Dictionary) -> void:
	target = p_target
	params = p_params
	var pad := float(params.get("pad", 0.05))
	_box = _bounds_of(target)
	_box = _box.grow(pad)
	_after_setup()


## Local bounds of the target and every mesh under it, in the target's space.
static func _bounds_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var xf: Transform3D = node.global_transform.affine_inverse() * mi.global_transform if node.is_inside_tree() else Transform3D.IDENTITY
			var b := xf * mi.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		for c in n.get_children():
			stack.push_back(c)
	if first:
		box = AABB(Vector3(-0.1, -0.1, -0.1), Vector3(0.2, 0.2, 0.2))
	return box


## Does a world-space ray hit the tap box? Returns the distance, or -1.
func hit(origin: Vector3, dir: Vector3) -> float:
	if target == null:
		return -1.0
	var inv := target.global_transform.affine_inverse() if target.is_inside_tree() else Transform3D.IDENTITY
	var o := inv * origin
	var d := (inv.basis * dir).normalized()
	var p = _box.intersects_ray(o, d)
	if p == null:
		return -1.0
	return (Vector3(p) - o).length()


func bounds() -> AABB:
	return _box


## World point the on-screen hint floats over (just above the prop).
func anchor() -> Vector3:
	var c := _box.get_center()
	c.y = _box.end.y
	var local := c + Vector3(0.0, 0.28, 0.0)
	if target != null and target.is_inside_tree():
		return target.global_transform * local
	return local


## Hint discs to draw above the prop: [{id: "tap"|"next"|"off"}]. Default one
## "tap" hint; kinds override per state.
func icons() -> Array:
	return [{"id": "tap"}]


## A hint disc was tapped. Default: same as tapping the prop.
func on_icon(_id: String, court: Node) -> void:
	on_tap(court)


## A prop's sibling part by name (glb props are flat: the boombox's LED is
## next to the boombox, not under it). Searches from the arena root down.
func find_part(part_name: String) -> Node:
	if target == null:
		return null
	var root: Node = target
	while root.get_parent() != null and not (root.get_parent() is Viewport):
		root = root.get_parent()
		if root.name == "Arena":
			break
	return root.find_child(part_name, true, false)


## Hooks for kinds.
func _after_setup() -> void:
	pass


func on_tap(_court: Node) -> void:
	pass


## Leaving the area (the screen is going away).
func on_leave() -> void:
	pass


func label() -> String:
	return str(params.get("kind", "prop"))
