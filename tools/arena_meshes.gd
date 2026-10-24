extends SceneTree
## The shadow-caster inventory (docs/PERFORMANCE.md → Stage 3): every
## MeshInstance3D in each arena glb with its triangles, its cast_shadow
## setting, its size and its distance from the hoop — the list the caster
## rules are decided from. Read-only.
##   godot --headless --path . -s tools/arena_meshes.gd [-- --area=park]


func _initialize() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--area="):
			only = str(a).trim_prefix("--area=")
	for id in ["cage", "beach", "park", "city"]:
		if only != "" and id != only:
			continue
		var set := CosmeticLibrary.get_arena(id)
		if set == null or not ResourceLoader.exists(set.model_path):
			print("%s: no model" % id)
			continue
		var inst: Node = (load(set.model_path) as PackedScene).instantiate()
		var hoop := Vector3(2.9, 2.4, 0.0)
		var rows := []
		var total := 0
		var casting := 0
		for n in _descendants(inst):
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var mi := n as MeshInstance3D
				var tris := 0
				for s in mi.mesh.get_surface_count():
					tris += mi.mesh.surface_get_array_len(s) / 3 if mi.mesh.surface_get_array_index_len(s) <= 0 else mi.mesh.surface_get_array_index_len(s) / 3
				var aabb := mi.get_aabb()
				var pos := mi.global_position if mi.is_inside_tree() else _world_pos(mi)
				var cast := mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				total += tris
				if cast:
					casting += tris
				rows.push_back([mi.name, tris, "cast" if cast else "off", aabb.size, pos.distance_to(hoop), mi.visible])
		rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
		print("== %s  %d meshes · %d tris · %d tris casting" % [id, rows.size(), total, casting])
		for r in rows:
			print("  %-22s %6d tris  %-4s  size %.1f×%.1f×%.1f  %5.1f m from the hoop%s" % [r[0], r[1], r[2], r[3].x, r[3].y, r[3].z, r[4], "" if r[5] else "  (hidden)"])
		inst.free()
	quit(0)


func _descendants(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_descendants(c))
	return out


func _world_pos(n: Node3D) -> Vector3:
	var t := n.transform
	var p := n.get_parent()
	while p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t.origin
