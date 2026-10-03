class_name AimPreview
extends Node3D
## Dotted preview of where a perfect-power throw at the current wind-up goes:
## the ballistic path from the hand at the chosen arc, along the true line to
## the hoop axis, at the make-band anchor (ideal) speed. Pure view-side float
## math; nothing here touches sim state. Ends at the rim plane (or T_MAX).
## `visible_frac` < 1 draws a DIMINISHING line: dots past that fraction of the
## flight are hidden and the last third before it shrink away, so the player
## gets the launch direction and arc without seeing where it lands.

## Fewer, smaller dots than a debug readout wants: this is a player-facing
## hint, so it should suggest the arc rather than draw it.
const DOTS := 12
## How the dots are spread along the flight. 1.0 spaces them evenly in time;
## below 1.0 packs them progressively toward the FAR end, so the line thins out
## near the ball and tightens as it climbs toward the rim — which is the end
## the shot is actually judged on. (Tried front-loading it at 1.67 and 2.4 on
## 2026-09-23; Ross preferred this. The far end is ~3× farther from the
## camera, so perspective already bunches it — this value works with that.)
const SPACING_POW := 0.6
const T_MAX := 1.2
## Portion of the visible run over which the dots shrink to nothing. Kept short
## so the densest, most informative stretch near the rim is not faded away.
const TAPER := 0.18

var _dots: Array[MeshInstance3D] = []


func _ready() -> void:
	var mesh := SphereMesh.new()
	# Small, but not so small that perspective erases the far end: the last
	# dots sit ~4 m out, three times the distance of the first.
	mesh.radius = 0.017
	mesh.height = 0.034
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	# The light yellow of the original (Ross, 2026-10-02: back from the quiet
	# grey) — soft enough to sit behind the shot, warm enough to read on any court.
	mat.albedo_color = Color(1.0, 0.93, 0.62, 0.74)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i in DOTS:
		var mi := MeshInstance3D.new()
		mi.name = "Dot%d" % i
		mi.mesh = mesh
		mi.material_override = mat
		mi.visible = false
		add_child(mi)
		_dots.push_back(mi)


func show_preview(origin: Vector3, angle_deg: float, geo: SimGeometry, visible_frac := 1.0) -> void:
	var dx := geo.hoop_x - origin.x
	var dz := geo.hoop_z - origin.z
	var dist := sqrt(dx * dx + dz * dz)
	if dist < 1e-6:
		hide_preview()
		return
	var rise := geo.hoop_y - origin.y
	var v := Ballistics.speed_for_angle(angle_deg, dist, rise)
	if is_nan(v):
		v = Ballistics.speed_for_angle(FlickMap.ANCHOR_ANGLE_DEG, dist, rise)
	if is_nan(v):
		hide_preview()
		return
	var th := deg_to_rad(angle_deg)
	var dir := Vector3(dx / dist, 0.0, dz / dist)
	var vh := v * cos(th)
	var vy := v * sin(th)
	var g := SimConstants.G
	# Descending crossing of the rim plane: ½g t² − vy t + rise = 0.
	var t_end := T_MAX
	var disc := vy * vy - 2.0 * g * rise
	if disc >= 0.0:
		t_end = minf(T_MAX, (vy + sqrt(disc)) / g)
	for i in DOTS:
		var f := pow(float(i + 1) / float(DOTS), SPACING_POW)
		var t := t_end * f
		var p := origin + dir * (vh * t)
		p.y = origin.y + vy * t - 0.5 * g * t * t
		_dots[i].position = p
		# Diminishing line: full size until the taper starts, then shrink to 0
		# at visible_frac; nothing beyond.
		var s := 1.0
		if visible_frac < 1.0:
			var taper_start := visible_frac * (1.0 - TAPER)
			s = 1.0 - clampf((f - taper_start) / (visible_frac - taper_start), 0.0, 1.0)
		_dots[i].visible = s > 0.02
		_dots[i].scale = Vector3.ONE * maxf(s, 0.02)


func hide_preview() -> void:
	for d in _dots:
		d.visible = false
