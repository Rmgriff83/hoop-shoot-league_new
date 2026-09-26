class_name InteractableKinds
extends RefCounted
## Registry of tappable prop kinds (ArenaSet.interactables rows → node type).
## Add a kind: a script extending Interactable and a row here.

const KINDS := {
	"radio": preload("res://game/court/interactables/radio.gd"),
}


static func make(kind: String) -> Interactable:
	if not KINDS.has(kind):
		return null
	return (KINDS[kind] as GDScript).new()
