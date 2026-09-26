class_name SimVec3
extends RefCounted
## Float64 3-vector for the headless sim. Godot's Vector3 stores 32-bit
## components in standard builds, which would shift the tuned collision basins;
## GDScript float fields are 64-bit, so core/ uses this instead. Keep it minimal.

var x: float
var y: float
var z: float


func _init(px := 0.0, py := 0.0, pz := 0.0) -> void:
	x = px
	y = py
	z = pz


func clone() -> SimVec3:
	return SimVec3.new(x, y, z)


func length() -> float:
	return sqrt(x * x + y * y + z * z)
