class_name WoolEmberNet
extends WoolNet
## The wool net in ember yarns (Ross's design "Wool Ember Net Model" 26f,
## 2026-10-25): reds, oranges, golds, cream and warm browns. The hand-knitted
## build of WoolNet (docs/BLENDER_101.md §31) unchanged; only the yarns differ.

const EMBER := ["#C8341E", "#F2A23A", "#F2E6CF", "#E8703A", "#8A3A22", "#FFD04A",
	"#B8421F", "#F07A62", "#5A2A18", "#F0B84A", "#D8A27A", "#FFE7A0"]


func _yarn() -> Array:
	return EMBER
