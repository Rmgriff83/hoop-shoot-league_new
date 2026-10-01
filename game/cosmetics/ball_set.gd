class_name BallSet
extends CosmeticSet
## A ball bundle: the ball model/skin (first MeshInstance3D in the glb) and the
## ball's own sounds — floor bounces (any number of clips, a random one per
## ground hit, never the same twice running) and, later, pickup / release.
## Sound ownership: the ball owns what the ball does on its own.

## The ball's skin. Every ball shares ONE mesh (the classic glb) and differs
## only by this texture, applied as a material_override. Twenty near-identical
## glbs would cost ~3.6 MB and make Godot build LODs and a shadow mesh for each
## copy of the same 800-face sphere.
@export var skin_path := ""

## PEGGY rarity ("common" | "rare" | "epic" | "legend", docs/LOCKER.md): which
## plate of the drop machine can pay this ball. Balls are never bought, so
## price_coins is 0 on every one of them.
@export var rarity := "common"

## Bounce clips played on floor contacts; empty → generic synthetic bounces.
@export var bounce_clips := PackedStringArray()
@export var pickup_clips := PackedStringArray()
@export var release_clips := PackedStringArray()

## Look tweaks the pool applies.
@export var held_scale := 1.0
@export var squash_gain := 1.0


func referenced_paths() -> PackedStringArray:
	var out := super()
	if skin_path != "":
		out.push_back(skin_path)   # so validate() catches a missing skin
	for arr in [bounce_clips, pickup_clips, release_clips]:
		for p in arr:
			out.push_back(p)
	return out
