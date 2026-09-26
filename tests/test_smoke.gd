extends RefCounted


func run(t) -> void:
	t.eq(1 + 1, 2, "arithmetic sanity")
	t.ok("res://tests".begins_with("res://"), "resource paths resolve")
