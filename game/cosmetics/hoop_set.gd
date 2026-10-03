class_name HoopSet
extends CosmeticSet
## A hoop bundle: backboard + rim + net model (node RimPivot required; LedFace /
## BoardBand / Backboard / Net / AnimationPlayer optional — a hoop with no LED
## just scores on the HUD), the hoop's sounds (make, miss,
## optional rim/board contact overrides), the net's feel, the LED skin and
## flourish animation names. Sound ownership: the hoop owns what the hoop does.

@export var make_clips := PackedStringArray()
@export var miss_clips := PackedStringArray()
## Optional 3-variant (soft→hard) contact overrides; empty → generic synthetic.
@export var rim_clips := PackedStringArray()
@export var board_clips := PackedStringArray()

## "nylon" (the classic cord lattice) or "chain" (the city court's steel
## links: Sfx layers the link rattle under rim hits; CourtGeometry checks it
## against SimGeometry.net_rigidity() so the visible net matches the sim).
@export var net_kind := "nylon"
## Net feel (see NetSim for what each does). Defaults = the classic net.
## Nylon defaults (2026-10-03, the snap model — docs/BLENDER_101.md): cords
## stretch a little (stiffness), a spring pulls them home through rest so
## they overshoot and ring down (rest_spring, damping), the bottom ring hangs
## heavy (tail_mass), an entering ball kicks the cords (kick), and they keep
## about half their own momentum under the ball (friction).
@export var net_stiffness := 0.14
@export var net_damping := 0.9965
@export var net_rest_pull := 0.003
@export var net_rest_spring := 90.0
@export var net_tail_mass := 1.6
@export var net_kick := 1.6
@export var net_grab_band := 0.06
@export var net_grab_pull := 0.5
@export var net_friction := 0.55

## LED skin (defaults = LedBoard's constants).
@export var led_color := Color8(255, 70, 30)
@export var led_accent := Color8(255, 180, 40)
@export var band_flash_color := Color8(255, 200, 40)
@export var band_buzzer_color := Color8(255, 40, 30)

## Authored glb animations to play on events; empty = none (the net is
## simulated at runtime, so a make needs no clip unless the set wants a flourish).
@export var make_anim := ""
@export var streak_anim := ""
## Played on every rim hit (the rim's own reaction to a brick / rattle).
@export var miss_anim := ""

## The glb's authored board size (m); CourtGeometry scales the Backboard node
## from these to the live SimGeometry. Classic = the arcade junior board.
@export var model_board_h := 0.76
@export var model_board_half_w := 0.61


func referenced_paths() -> PackedStringArray:
	var out := super()
	for arr in [make_clips, miss_clips, rim_clips, board_clips]:
		for p in arr:
			out.push_back(p)
	return out


func validate() -> PackedStringArray:
	var out := super()
	if not (net_kind in ["nylon", "chain"]):
		out.push_back("<net_kind %s>" % net_kind)
	return out
