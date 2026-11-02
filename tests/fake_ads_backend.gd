class_name FakeAdsBackend
extends AdsBackend
## A scriptable ad network for tests and QA: whether it is there, whether
## an interstitial is loaded, how a show ends ("shown" | "failed"), and a
## record of every call. `auto` closes a shown ad at once; otherwise
## `close()` ends it (a test looks at the muted world first). In QA,
## `visual` puts a dark AD card over the screen while one is "up".

var available_ := true
var ready_ := true
var show_outcome := "shown"
var auto := true
var visual := false
var starts: Array = []
var loads := 0
var shows := 0
var _up := false
var _card: CanvasLayer


func accepts_empty_cfg() -> bool:
	return true


func available() -> bool:
	return available_


func start(cfg: Dictionary) -> void:
	starts.push_back(cfg.duplicate(true))
	started.emit()


func ready() -> bool:
	return ready_


func load_interstitial() -> void:
	loads += 1
	if ready_:
		interstitial_ready.emit()


func show_interstitial() -> void:
	shows += 1
	if not ready_ or show_outcome != "shown":
		interstitial_closed.emit(false)
		return
	_up = true
	if visual:
		_show_card()
	if auto:
		close()


## The player closed the ad.
func close() -> void:
	if not _up:
		return
	_up = false
	if _card != null:
		_card.queue_free()
		_card = null
	interstitial_closed.emit(true)


func up() -> bool:
	return _up


func _show_card() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_card = CanvasLayer.new()
	_card.name = "FakeAd"
	_card.layer = 100
	var bg := ColorRect.new()
	bg.color = Color("#111111")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.add_child(bg)
	var l := Label.new()
	l.text = "AD"
	l.add_theme_font_size_override("font_size", 96)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.add_child(l)
	tree.root.add_child(_card)
