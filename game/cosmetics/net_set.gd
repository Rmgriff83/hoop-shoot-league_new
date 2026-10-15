class_name NetSet
extends CosmeticSet
## A net style (docs/LOCKER.md → NETS): the look of the net a hoop hangs —
## bought for tickets in the locker, equipped per court from the pause menu.
## Look only: the feel (the nine net_* knobs, the make sounds) stays on the
## court's HoopSet, and a style only fits hoops of its KIND ("cotton" on the
## nylon hoops, "chain" on the city's steel rim). Procedural: no model_path.

const KINDS := ["cotton", "chain"]

@export var kind := "cotton"
## The body NetBodies builds (defaults to the id).
@export var style := ""


func body_style() -> String:
	return style if style != "" else id


## HoopSet.net_kind ("nylon" | "chain") → a net kind.
static func kind_of_hoop(h: HoopSet) -> String:
	return "chain" if h != null and h.net_kind == "chain" else "cotton"


static func thumb_path(net_id: String) -> String:
	return "res://assets/textures/nets/thumbs/%s.png" % net_id


func validate() -> PackedStringArray:
	var out := super()
	if not (kind in KINDS):
		out.push_back("<kind %s>" % kind)
	if not NetBodies.has_style(body_style()):
		out.push_back("<style %s>" % body_style())
	elif NetBodies.kind_of(body_style()) != kind:
		out.push_back("<style %s is not %s>" % [body_style(), kind])
	return out
