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

## Optional cool fill light from the other side (0 energy = none), key-light
## shadows, and distance haze.
@export var fill_rotation_deg := Vector3(-35.0, -70.0, 0.0)
@export var fill_energy := 0.0
@export var fill_color := Color(0.5, 0.6, 0.95)
@export var sun_shadows := false
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
## The home page's subtitle under the area name: how hard this area plays.
@export var title_tier := "EASY LEVEL"

## Attach BeachFx (animated Ocean waves + tide-driven Shore) at build time.
@export var ocean := false
## Arcade hall life: cabinets with live screens and chasing marquees
## (CabScreen*/CabMarquee* meshes; game/view/arcade_fx.gd).
@export var arcade_life := false

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
