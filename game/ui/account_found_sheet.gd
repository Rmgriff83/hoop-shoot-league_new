class_name AccountFoundSheet
extends CanvasLayer
## "FOUND YOUR ACCOUNT · BRICK BARON 42 · LVL 7 · USE IT?" — the platform
## (Game Center / Play Games) already knows an account other than this one
## (docs/BACKEND.md → Platform identity, a 409 on link). USE IT runs
## Platform.accept_conflict() (restore + forced pull); NOT NOW keeps this
## account unlinked. A dim over the screen, a cream dotted card, like
## NetAreaSheet.

signal closed

const DIM := Color(0.02, 0.02, 0.05, 0.6)
const CARD_POS := Vector2(90, 420)
const CARD_SIZE := Vector2(540, 420)
const CREAM := RetroTheme.SCENE_TEXT

var info := {}
var _status: Label


func _init() -> void:
	layer = 35


func build(p_info: Dictionary) -> void:
	info = p_info.duplicate()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)
	var card := ShadowPanel.new(CREAM, 24.0)
	card.name = "Card"
	card.position = CARD_POS
	card.size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(card)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 24
	col.offset_top = 24
	col.offset_right = -24 - ShadowStyle.OFFSET
	col.offset_bottom = -24 - ShadowStyle.OFFSET
	col.add_theme_constant_override("separation", 14)
	card.add_child(col)
	var title := HomePage.words("FOUND YOUR ACCOUNT", 18, true)
	title.name = "Title"
	col.add_child(title)
	var handle := HomePage.words(HandleWords.display(str(info.get("name", "")), str(info.get("tag", ""))), 16)
	handle.name = "Handle"
	col.add_child(handle)
	var level := HomePage.words("LVL %d" % int(info.get("level", 1)), 14)
	level.name = "Level"
	col.add_child(level)
	var ask := HomePage.words("USE IT?", 14)
	ask.name = "Ask"
	col.add_child(ask)
	_status = HomePage.words("", 12)
	_status.name = "Status"
	col.add_child(_status)
	var use := HomePage.button("USE IT", RetroTheme.LIGHT["gold"], 16, 56)
	use.name = "UseIt"
	use.pressed.connect(_use_it)
	col.add_child(use)
	var not_now := HomePage.button("NOT NOW", CREAM, 16, 56)
	not_now.name = "NotNow"
	not_now.pressed.connect(func() -> void:
		Platform.decline_conflict()
		close()
	)
	col.add_child(not_now)


func _use_it() -> void:
	_status.text = "SWITCHING..."
	var ok: bool = await Platform.accept_conflict()
	if not is_instance_valid(_status):
		return
	if ok:
		_status.text = "WELCOME BACK · %s" % Net.handle()
		await get_tree().create_timer(1.2).timeout
		if is_instance_valid(self):
			close()
	else:
		_status.text = "NO SIGNAL · TRY AGAIN LATER"


func close() -> void:
	closed.emit()
	queue_free()
