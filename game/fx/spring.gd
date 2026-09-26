class_name JuiceSpring
extends RefCounted
## Damped spring — the workhorse of all bouncy motion (score count-ups, ball
## squash settle, rim wobble). Step it from _process with real dt; it is
## framerate-independent. Ported from src/engine/anim/spring.ts.
## (Named JuiceSpring: physics springs live in the sim, this one is pure juice.)

var value := 0.0
var velocity := 0.0
var target := 0.0
## Stiffness (1/s²). Higher = snappier.
var stiffness := 170.0
## Damping ratio: 1 = critically damped, <1 = bouncy overshoot.
var damping_ratio := 1.0


func _init(p_value := 0.0, p_stiffness := 170.0, p_damping_ratio := 1.0) -> void:
	value = p_value
	target = p_value
	stiffness = p_stiffness
	damping_ratio = p_damping_ratio


## Kick adds velocity — great for impact reactions (rim wobble, squash).
func kick(impulse: float) -> void:
	velocity += impulse


func set_to(p_value: float) -> void:
	value = p_value
	target = p_value
	velocity = 0.0


func step(dt: float) -> float:
	# Semi-implicit Euler on m x'' = -k (x - target) - c x', clamped substeps for stability.
	var c := 2.0 * damping_ratio * sqrt(stiffness)
	var remaining := dt
	while remaining > 0.0:
		var h := minf(remaining, 1.0 / 120.0)
		var accel := -stiffness * (value - target) - c * velocity
		velocity += accel * h
		value += velocity * h
		remaining -= h
	return value


func is_settled() -> bool:
	return absf(value - target) < 1e-4 and absf(velocity) < 1e-4


## 3-channel spring for positions/scales.
class Spring3:
	var x: JuiceSpring
	var y: JuiceSpring
	var z: JuiceSpring

	func _init(px := 0.0, py := 0.0, pz := 0.0, p_stiffness := 170.0, p_damping_ratio := 1.0) -> void:
		x = JuiceSpring.new(px, p_stiffness, p_damping_ratio)
		y = JuiceSpring.new(py, p_stiffness, p_damping_ratio)
		z = JuiceSpring.new(pz, p_stiffness, p_damping_ratio)

	func set_target(px: float, py: float, pz: float) -> void:
		x.target = px
		y.target = py
		z.target = pz

	func set_to(px: float, py: float, pz: float) -> void:
		x.set_to(px)
		y.set_to(py)
		z.set_to(pz)

	func step(dt: float) -> void:
		x.step(dt)
		y.step(dt)
		z.step(dt)
