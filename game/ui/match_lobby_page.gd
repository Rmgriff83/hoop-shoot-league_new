class_name MatchLobbyPage
extends CanvasLayer
## The 1v1 lobby (docs/BACKEND.md → Phase 3), behind the home's multiplayer
## icon: `<` BEACH · 1V1; QUICK MATCH, CREATE CODE, ENTER CODE (a code field
## + GO); then the waiting state — the code to tell a friend or FINDING A
## PLAYER..., a status line and CANCEL. The page owns no network: it emits
## `quick`, `create`, `join(code)` and `cancel`, and App drives it through
## show_waiting / show_found / show_failed.

signal closed
signal quick
signal create
signal join(code: String)
signal cancel
## Open the online deck (docs/BACKEND.md → Cards online).
signal cards

const PAD := Vector2(28, 44)
const BTN := Vector2(664, 112)

var _root: Control
var _menu: VBoxContainer
var _wait: VBoxContainer
var _code_edit: LineEdit
var _strip: HBoxContainer
var _big: Label
var _status: Label
var _cancel: Button
var _state := "menu"


func _init() -> void:
	layer = 30


func build(area: String) -> Control:
	if _root != null:
		_root.queue_free()
	_root = Control.new()
	_root.name = "LobbyRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = RetroTheme.c("bg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	var head := HBoxContainer.new()
	head.name = "Head"
	head.position = PAD
	head.size = Vector2(720 - PAD.x * 2, 56)
	head.add_theme_constant_override("separation", 20)
	_root.add_child(head)
	var back := Button.new()
	back.name = "Back"
	back.text = "<"
	back.custom_minimum_size = Vector2(56 + ShadowStyle.OFFSET, 56 + ShadowStyle.OFFSET)
	RetroTheme.card_button(back, RetroTheme.c("panel"), RetroTheme.RADIUS, 0.0)
	back.add_theme_font_size_override("font_size", UiFont.snap(24))
	back.add_theme_color_override("font_color", RetroTheme.c("text"))
	back.add_theme_color_override("font_pressed_color", RetroTheme.c("text"))
	back.add_theme_color_override("font_hover_color", RetroTheme.c("text"))
	back.pressed.connect(close)
	head.add_child(back)
	var title := RetroTheme.display(MatchCopy.title(area), 28)
	title.name = "Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(title)
	# Your online cards: coins, the three slots, CARDS >.
	_strip = HBoxContainer.new()
	_strip.name = "CardStrip"
	_strip.position = Vector2(PAD.x, PAD.y + 56 + 24)
	_strip.size = Vector2(720 - PAD.x * 2, 56)
	_strip.add_theme_constant_override("separation", 16)
	_root.add_child(_strip)
	refresh_strip()
	# The menu.
	_menu = VBoxContainer.new()
	_menu.name = "Menu"
	_menu.position = Vector2(PAD.x, 220)
	_menu.size = Vector2(720 - PAD.x * 2, 0)
	_menu.add_theme_constant_override("separation", 28)
	_root.add_child(_menu)
	_menu.add_child(_button("Quick", "QUICK MATCH", MatchCopy.quick_sub(), RetroTheme.c("orange"), func() -> void: quick.emit()))
	_menu.add_child(_button("Create", "CREATE CODE", MatchCopy.code_sub(), RetroTheme.c("teal"), func() -> void: create.emit()))
	var join_row := HBoxContainer.new()
	join_row.name = "JoinRow"
	join_row.add_theme_constant_override("separation", 16)
	_menu.add_child(join_row)
	_code_edit = LineEdit.new()
	_code_edit.name = "CodeEdit"
	_code_edit.placeholder_text = "ENTER CODE"
	_code_edit.max_length = 6
	_code_edit.custom_minimum_size = Vector2(0, BTN.y)
	_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_code_edit.add_theme_font_override("font", UiFont.display())
	_code_edit.add_theme_font_size_override("font_size", UiFont.snap(24))
	_code_edit.add_theme_color_override("font_color", RetroTheme.c("text"))
	_code_edit.add_theme_color_override("font_placeholder_color", RetroTheme.c("muted"))
	_code_edit.add_theme_color_override("caret_color", RetroTheme.c("text"))
	_code_edit.add_theme_stylebox_override("normal", RetroTheme.flat(RetroTheme.c("panel"), RetroTheme.RADIUS, 16.0))
	_code_edit.add_theme_stylebox_override("focus", RetroTheme.flat(RetroTheme.c("panel").lightened(0.05), RetroTheme.RADIUS, 16.0))
	_code_edit.text_submitted.connect(func(_t: String) -> void: _go())
	join_row.add_child(_code_edit)
	var go := _button("Go", "GO", "", RetroTheme.c("gold"), _go, Vector2(160, BTN.y))
	join_row.add_child(go)
	var sub := RetroTheme.caps(MatchCopy.join_sub(), 14, RetroTheme.c("muted"))
	sub.name = "JoinSub"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.add_child(sub)
	# The waiting state.
	_wait = VBoxContainer.new()
	_wait.name = "Wait"
	_wait.visible = false
	_wait.position = Vector2(PAD.x, 360)
	_wait.size = Vector2(720 - PAD.x * 2, 0)
	_wait.add_theme_constant_override("separation", 36)
	_root.add_child(_wait)
	_big = RetroTheme.display("", 40)
	_big.name = "Big"
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.autowrap_mode = TextServer.AUTOWRAP_WORD
	_wait.add_child(_big)
	_status = RetroTheme.caps("", 16, RetroTheme.c("muted"))
	_status.name = "Status"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wait.add_child(_status)
	_cancel = _button("Cancel", "CANCEL", "", RetroTheme.c("panel"), func() -> void:
		cancel.emit()
		show_menu())
	_wait.add_child(_cancel)
	return _root


## The strip from the online bucket's cache: `120 COINS`, the chips, CARDS >.
func refresh_strip() -> void:
	if _strip == null:
		return
	for c in _strip.get_children():
		_strip.remove_child(c)
		c.queue_free()
	var coins := RetroTheme.display("%d COINS" % App.league_coins(Net.ONLINE_BUCKET), 14, RetroTheme.c("gold"))
	coins.name = "OnlineCoins"
	coins.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_strip.add_child(coins)
	var chips := ModeCards.chip_row(App.loadout_slots(Net.ONLINE_BUCKET), true)
	chips.name = "Loadout"
	chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_strip.add_child(chips)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(spacer)
	var open_cards := ShadowCard.new(RetroTheme.c("ink"))
	open_cards.name = "Cards"
	open_cards.custom_minimum_size = Vector2(150 + ShadowStyle.OFFSET, 46 + ShadowStyle.OFFSET)
	var l := RetroTheme.display("CARDS >", 14, RetroTheme.c("text"))
	l.position = Vector2.ZERO
	l.size = Vector2(150, 46)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	open_cards.add_child(l)
	open_cards.pressed.connect(func() -> void: cards.emit())
	_strip.add_child(open_cards)


func _button(name_: String, text: String, sub: String, fill: Color, on_press: Callable, size_ := BTN) -> ShadowCard:
	var b := ShadowCard.new(fill)
	b.name = name_
	b.custom_minimum_size = size_ + Vector2.ONE * ShadowStyle.OFFSET
	var col := VBoxContainer.new()
	col.position = Vector2.ZERO
	col.size = size_
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(col)
	var l := RetroTheme.display(text, 24, RetroTheme.c("text"))
	l.name = "Text"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	if sub != "":
		var s := RetroTheme.caps(sub, 14, RetroTheme.c("muted"))
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(s)
	b.pressed.connect(on_press)
	return b


func _go() -> void:
	var code := _code_edit.text.strip_edges().replace(" ", "").to_upper()
	if code.length() != 5:
		show_failed("not_found")
		show_menu()
		return
	join.emit(code)


func show_menu() -> void:
	_state = "menu"
	_menu.visible = true
	_wait.visible = false


## Waiting: FINDING A PLAYER... or the code to pass on.
func show_waiting(how: String, code := "") -> void:
	_state = "waiting"
	_menu.visible = false
	_wait.visible = true
	_cancel.visible = true
	_big.text = MatchCopy.code_line(code) if code != "" else MatchCopy.waiting_line(how)
	_status.text = MatchCopy.waiting_line(how) if code != "" else ""


func show_found(peer: Dictionary) -> void:
	_state = "found"
	_menu.visible = false
	_wait.visible = true
	_cancel.visible = false
	_status.text = MatchCopy.found_line(peer)


func show_failed(reason: String) -> void:
	_state = "failed"
	_menu.visible = false
	_wait.visible = true
	_cancel.visible = true
	_big.text = ""
	_status.text = MatchCopy.failed_line(reason)


func state() -> String:
	return _state


func big_text() -> String:
	return _big.text


func status_text() -> String:
	return _status.text


func close() -> void:
	cancel.emit()
	closed.emit()
	queue_free()


func slide_in() -> void:
	if _root == null:
		return
	_root.position.x = 720.0
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_root, "position:x", 0.0, 0.22)
