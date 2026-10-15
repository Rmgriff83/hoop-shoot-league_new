class_name NetBodies
extends RefCounted
## The net styles a hoop can hang (docs/BLENDER_101.md §28–30): the body
## class and the rest layout per style id. A NetSet's `style` names one;
## the stock styles are the kinds themselves ("cotton", "chain").

const STYLES := ["cotton", "chain", "jack", "ladder", "wool"]
const KIND_OF := {"cotton": "cotton", "chain": "chain", "jack": "chain", "ladder": "chain", "wool": "cotton"}


static func has_style(style: String) -> bool:
	return STYLES.has(style)


## The net kind a style belongs to ("" for an unknown style).
static func kind_of(style: String) -> String:
	return str(KIND_OF.get(style, ""))


## The stock style of a kind.
static func stock_style(kind: String) -> String:
	return "chain" if kind == "chain" else "cotton"


## The body a NetSet hangs: its style's body, tinted when the set says so.
static func for_set(ns: NetSet) -> NetRig:
	var body := for_style(ns.body_style() if ns != null else "cotton")
	if ns != null and body is CottonNet:
		(body as CottonNet).tint = ns.tint
	return body


static func for_style(style: String) -> NetRig:
	match style:
		"chain":
			return ChainNet.new()
		"jack":
			return JackNet.new()
		"ladder":
			return LadderNet.new()
		"wool":
			return WoolNet.new()
		_:
			return CottonNet.new()


static func layout(style: String, rim_r := SimConstants.R_RIM, tube_r := SimConstants.R_TUBE) -> Dictionary:
	match style:
		"chain":
			return ChainNet.layout(rim_r, tube_r)
		"jack":
			return JackNet.layout(rim_r, tube_r)
		"ladder":
			return LadderNet.layout(rim_r, tube_r)
		"wool":
			return WoolNet.layout(rim_r, tube_r)
		_:
			return NetSim.cotton_layout(rim_r, tube_r)
