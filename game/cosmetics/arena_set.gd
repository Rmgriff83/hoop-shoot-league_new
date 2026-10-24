class_name ArenaSet
extends CosmeticSet
## An environment bundle: the arena glb, its lighting, its camera framing and
## which surfaces glow on their own. Model contract (all by name, all
## OPTIONAL): `Crossbar` (rides side rails, x), `Trolley` (rides the crossbar,
## x + z), `Pole` (placed behind the board), `Ocean` + `Shore` (BeachFx),
## `AnimationPlayer` (one clip per NLA track, played via play_arena).
## Defaults are the arcade cage's dim hall, so a manifest that says nothing
## looks like the cage.

## Nodes whose material should render unshaded (marquees, neon, the sky).
@export var emissive_nodes := PackedStringArray()

## Sun (key light): Godot lights shine along their local -Z. (-55, -30, 0)
## lights the cage from behind the shooter. Facing the hoop is "north": the
## beach's setting sun sits low in the east-north-east, (-18, 22.5, 0), so the
## light comes from the shooter's front-right, with a cool fill opposite it.
@export var sun_rotation_deg := Vector3(-55.0, -30.0, 0.0)
@export var sun_energy := 1.0
@export var sun_color := Color(1.0, 1.0, 1.0)
@export var ambient_color := Color(0.68, 0.62, 0.56)
@export var ambient_energy := 0.55
@export var background_color := Color(0.03, 0.02, 0.02)

## The fill: since 2026-10-24 NOT a second light — CourtGeometry folds its
## colour and energy into the ambient (the ambient's second tone; a second
## DirectionalLight3D cost the phone 4–7 ms, docs/NEW_AREA_PERFORMANCE.txt).
## Then key-light shadows and distance haze.
@export var fill_rotation_deg := Vector3(-35.0, -70.0, 0.0)
@export var fill_energy := 0.0
@export var fill_color := Color(0.5, 0.6, 0.95)
@export var sun_shadows := false
## How far the sun's shadows reach (m) and the directional shadow map's size
## (the project's mobile default is 2048); the park trims both (20 m, 1024)
## with its near-only tree casters (ParkFx.SHADOW_R) to run lighter.
@export var shadow_distance := 30.0
@export var shadow_size := 2048
## The 3D render scale CourtGeometry puts on its viewport while this area is
## up (bilinear; the 2D HUD stays full-res). Every area runs 1.0: the park
## tried 0.7 (2026-10-16) and Godot's bilinear upscale smeared the pixel
## art — "everything all blurry" — so the knob stays for a nearest-neighbour
## path some day, not for dropping below 1.0 as things stand.
@export var render_scale := 1.0
@export var fog_enabled := false
@export var fog_color := Color(0.9, 0.58, 0.45)
@export var fog_density := 0.01

## Camera framing.
@export var camera_fov := 60.0
@export var camera_look_height := 2.2

## The home screen's slow pan over this area (game/screens/title_pan.gd,
## docs/HOME.md): the camera trucks ±title_drift around title_cam_pos over
## title_period_s while looking at title_look_at. Defaults are the cage's
## "facing forward, a bit off kilter" pose — inside the cage at its back
## line, off the shooting axis, a touch high, wide enough to take in the
## rails, the ceiling mesh and the cabinets through the side walls.
@export var title_cam_pos := Vector3(-1.65, 2.0, -0.55)
@export var title_look_at := Vector3(2.9, 1.55, 0.2)
@export var title_drift := Vector3(0.05, 0.0, 0.5)
@export var title_period_s := 28.0
@export var title_fov := 66.0
## The home page's star row over the area name: how hard this area plays
## (one star per step; the cage is 1, the beach 2).
@export var title_stars := 1
## A bright sky (the midday city) washes out the cream chrome at the top of
## the screen: the alpha of an ink gradient laid over the top TOP_WASH_H px
## behind the HUD's cards and the home's top bar (0 = none).
@export var top_wash := 0.0
## Does a ball hitting the enclosure's walls make a sound? The beach lost
## its fence (2026-10-02) but keeps the sim's walls: they stay silent there.
@export var wall_sound := true

## Attach BeachFx (animated Ocean waves + tide-driven Shore) at build time.
@export var ocean := false
## The city court: cars pass on the street beyond the fence and the buildings'
## windows switch on and off (CityFx).
@export var traffic := false
## Arcade hall life: cabinets with live screens and chasing marquees
## (CabScreen*/CabMarquee* meshes; game/view/arcade_fx.gd).
@export var arcade_life := false
## The park (game/view/park_fx.gd): falling snow (one points mesh, `snow_amount`
## flakes — the park asks for 300 — capped at 800), a shader sky on the `Sky` mesh (`sky` names the
## look: "partly_cloudy"), parked cars [{model, x, z, yaw}] and the PSX
## trees / litter instanced from a layout JSON.
@export var snow := false
@export var snow_amount := 500
@export var sky := ""
## The shader sky's palette (AreaSky, the design's park values by default —
## raw colours the shader converts to linear itself) and the direction
## toward the sun (the glow); the city sets its own blue and haze.
@export var sky_top := Color(0.30, 0.52, 0.84)
@export var sky_mid := Color(0.55, 0.72, 0.90)
@export var sky_horizon := Color(0.80, 0.86, 0.92)
@export var sky_sun_dir := Vector3(-0.65204, 0.51232, -0.55890)
@export var parked_cars: Array[Dictionary] = []
@export var tree_layout := ""

## Shooting spots (sim metres, y ignored): where the shooter can stand. Empty =
## one spot at the origin (the release plane). The first spot is the default.
@export var spot_names := PackedStringArray()
@export var spot_positions := PackedVector3Array()


## League-only banner (game/view/league_banner.gd), shown in league heats:
## kind "" = none, "standings" = standings / playoff bracket cloth, "label" =
## a small text banner. Position in sim metres, size in metres, yaw about y.
@export var league_banner_kind := ""
## Handwriting style for standings/bracket boards ("chalk").
@export var league_banner_style := "chalk"
@export var league_banner_pos := Vector3.ZERO
@export var league_banner_size := Vector2(1.5, 0.5)
@export var league_banner_yaw_deg := 0.0
@export var league_banner_lit := true
@export var league_banner_label := "LEAGUE MATCH"


## Ambience: looping background layers that play while you are in this area
## (game screens + the league dashboard). One gain per clip (dB, missing = 0);
## layers fade in/out over ambient_fade_s. Empty = silence. Encode clips with
## tools/import_ambience.sh (Ogg Vorbis).
@export var ambient_clips := PackedStringArray()
@export var ambient_gains_db := PackedFloat32Array()
@export var ambient_fade_s := 1.2


## Tappable props unique to this area: one row per prop, {kind, node,
## pad?, ...params} — `kind` from InteractableKinds, `node` the glb node name.
## The beach radio: {"kind": "radio", "node": "Boombox", "tracks": [...]}.
@export var interactables: Array[Dictionary] = []


func ambient_gain_db(i: int) -> float:
	return ambient_gains_db[i] if i < ambient_gains_db.size() else 0.0


func referenced_paths() -> PackedStringArray:
	var out := super()
	for p in ambient_clips:
		out.push_back(p)
	for row in interactables:
		for tp in row.get("tracks", []):
			out.push_back(str(tp))
	return out


## [{name, pos}] with the origin as the lone default.
func spots() -> Array:
	var out := []
	if spot_positions.is_empty():
		return [{"name": "KEY", "pos": Vector3.ZERO}]
	for i in spot_positions.size():
		var nm: String = spot_names[i] if i < spot_names.size() else "SPOT %d" % (i + 1)
		out.push_back({"name": nm, "pos": Vector3(spot_positions[i].x, 0.0, spot_positions[i].z)})
	return out
