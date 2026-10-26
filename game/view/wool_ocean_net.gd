class_name WoolOceanNet
extends WoolNet
## The wool net in ocean yarns (Ross's design "Wool Ocean Net Model" 26e,
## 2026-10-25): deep navy, sea blues, teals, seafoam and white. The hand-
## knitted build of WoolNet (docs/BLENDER_101.md §31) unchanged; only the
## twelve yarns differ.

const OCEAN := ["#1F4FA8", "#7FD3E6", "#F2F1EC", "#2E8FC9", "#9CD6C8", "#BFE4F2",
	"#1FA6B8", "#3C6FB8", "#0E2F6A", "#5FB7A6", "#A9C8EC", "#E6F2F4"]


func _yarn() -> Array:
	return OCEAN
