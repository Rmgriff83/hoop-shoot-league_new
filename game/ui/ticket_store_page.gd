class_name TicketStorePage
extends HomePage
## The Ticket Store (design "Ticket Store" 50a, 2026-10-31; docs/ECONOMY.md →
## Ticket packs): a full page over the area like the locker, opened from the
## home's ticket chip, the locker's and PEGGY's ticket panels and a league
## card you can't afford. TICKETS with the balance chip, one line on what
## tickets buy, the two packs (TicketShop.packs()) and `< BACK`.
##
## A pack's price button runs idle → ask (X / BUY) → busy (the spinner while
## the store sheet is up and the Worker's credit is awaited) → done (+N, the
## tickets flying into the chip and the count ticking up) → idle. The buying
## is `Store` (RevenueCat → the webhook → pending → CLAIM → grant); the page
## only shows it: a cancel goes back quietly, an error or a slow credit goes
## back with a toast, and `show_bought` plays the success. Without a store
## (desktop, QA, no plugin) busy ends in no sale, the old stub.

const LINE := "SPEND TICKETS ON PEGGY AND IN EACH AREA'S CARD SHOP."
const BODY_X := 6.0           # the design's 36 px margin inside the 30 px frame
const BODY_W := 642.0         # 36 → 678
const ROW_H := 104.0         # the head row (TICKETS · the chip)
const CHIP := Vector2(170, 104)
const LINE_Y := 144.0         # under the header's top (the design's 262 at 118)
const PACK_Y := 242.0         # 360
const PACK_H := 250.0
const PACK_GAP := 40.0
const BUY := Vector2(176, 96)
const X_W := 72.0
const CONFIRM_W := 150.0
const ASK_GAP := 14
const BACK_H := 96.0
const FOOT := 9.0             # BACK's face ends 60 px above the screen's bottom
const DONE_S := 2.8           # +N shows this long (4.2 s after BUY with the spinner)
const BUMP_S := 0.2
const BUMP := 1.25
const HI := LeagueContext.HI
## Each pack's fanned tickets: [centre, degrees] in its 150 px art box (the
## design's 84 px boxes; the 22 × 14 ticket keeps its shape at 84 wide).
const FAN := [
	[[Vector2(72, 86), -12.0], [Vector2(48, 112), 8.0]],
	[[Vector2(72, 86), -12.0], [Vector2(48, 112), 8.0], [Vector2(94, 64), -4.0], [Vector2(60, 138), 14.0], [Vector2(86, 42), -18.0]],
]
const FAN_TICKET := Vector2(84, 53)

var _store: Control
var _chip_count: Label
var _chip_icon: PixelIcon
var _packs: Array[ShadowPanel] = []
var _areas: Array[HBoxContainer] = []
var _st: Array = []          # per pack: {state: idle | ask | busy | done, until, t}
var _clock := 0.0
var _bump_t := -1.0
var _flight: StoreFlight
var _fly_from := 0


func _flush_top() -> bool:
	return true


func _row_gap() -> int:
	return 0


func _layout_frame() -> void:
	super()
	if body != null:
		body.position.x = BODY_X
		body.size.x = BODY_W


func _build() -> void:
	_store = Control.new()
	_store.name = "Store"
	_store.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_store.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_child(_store)
	_build_head()
	var line := words(LINE, 22)
	line.name = "Line"
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_constant_override("line_spacing", 10)   # line-height 1.45
	line.position = Vector2(0, LINE_Y)
	line.size = Vector2(BODY_W, 0)
	_store.add_child(line)
	for i in TicketShop.packs().size():
		_st.push_back({"state": "idle", "until": 0.0, "t": 0.0})
		_build_pack(i)
	var back := back_button(24, 28, 16, BACK_H)
	body.add_child(back)
	var foot := Control.new()
	foot.name = "Foot"
	foot.custom_minimum_size = Vector2(0, FOOT)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(foot)
	_flight = StoreFlight.new()
	_flight.name = "Flight"
	_flight.count_changed.connect(_on_count)
	add_child(_flight)   # over the frame
	Store.purchase_done.connect(_on_purchase_done)
	Store.prices_changed.connect(_on_prices)
	Store.tickets_credited.connect(_on_credited)
	Store.fetch_prices()   # the player's own currency replaces the US tiers
	Store.sync()           # a credit that landed while the page was away


## TICKETS ...... [ticket over the balance].
func _build_head() -> void:
	var h := HBoxContainer.new()
	h.name = "Head"
	h.size = Vector2(BODY_W, ROW_H + ShadowStyle.OFFSET)
	h.add_theme_constant_override("separation", 22)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_store.add_child(h)
	var t := RetroTheme.display("TICKETS", 52, CREAM)
	t.name = "Title"
	# The design's own text-shadow (a 4 px ink drop, no outline).
	t.add_theme_color_override("font_shadow_color", RetroTheme.SCENE_OUTLINE)
	t.add_theme_constant_override("shadow_offset_x", 4)
	t.add_theme_constant_override("shadow_offset_y", 4)
	t.add_theme_constant_override("shadow_outline_size", 0)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.custom_minimum_size.y = ROW_H
	h.add_child(t)
	var chip := ShadowPanel.new(RetroTheme.LIGHT["gold"], 0.0, 0.35)
	chip.name = "Balance"
	chip.custom_minimum_size = CHIP + Vector2.ONE * ShadowStyle.OFFSET
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(chip)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(col)
	var slot := Control.new()   # the icon bumps: kept out of the container's sort
	slot.name = "Slot"
	slot.custom_minimum_size = Vector2(40, 25)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(slot)
	_chip_icon = PixelIcon.new("icon_ticket", Vector2(40, 25), 2.0)
	_chip_icon.name = "Icon"
	_chip_icon.pivot_offset = Vector2(20, 12.5)
	slot.add_child(_chip_icon)
	_chip_count = words(RetroTheme.thousands(App.tickets()), 22, true)
	_chip_count.name = "Count"
	col.add_child(_chip_count)


func _build_pack(i: int) -> void:
	var p: Dictionary = TicketShop.packs()[i]
	var best := bool(p.get("best", false))
	var panel := ShadowPanel.new(RetroTheme.LIGHT["gold"] if best else CREAM, 0.0, ShadowStyle.TINT)
	panel.name = "Pack%d" % i
	var sb := ShadowStyle.margins(0.0)
	sb.content_margin_left = 28.0
	sb.content_margin_right = 26.0 + ShadowStyle.OFFSET
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = Vector2(0, PACK_Y + float(i) * (PACK_H + PACK_GAP))
	panel.size = Vector2(BODY_W, PACK_H + ShadowStyle.OFFSET)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_store.add_child(panel)
	_packs.push_back(panel)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 26)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(row)
	var art := Control.new()
	art.name = "Art"
	art.custom_minimum_size = Vector2(150, 150)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(art)
	for f in FAN[mini(i, FAN.size() - 1)]:
		var tk := PixelIcon.new("icon_ticket", FAN_TICKET, 4.0)
		tk.position = Vector2(f[0]) - FAN_TICKET * 0.5
		tk.turn = float(f[1])
		art.add_child(tk)
	# The words take what's left (the design's flex 1, min-width 0): a plain
	# holder, so the wider ask (X + BUY) squeezes them instead of the row
	# outgrowing the pack; the column centres on its left edge.
	var words_box := Control.new()
	words_box.name = "Words"
	words_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words_box)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 16)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	col.grow_vertical = Control.GROW_DIRECTION_BOTH
	words_box.add_child(col)
	var amount := words(str(int(p["tickets"])), 40, true)
	amount.name = "Amount"
	amount.add_theme_color_override("font_color", HI)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(amount)
	var unit := words("TICKETS", 22)
	unit.name = "Unit"
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(unit)
	var area := HBoxContainer.new()
	area.name = "BuyArea"
	area.add_theme_constant_override("separation", ASK_GAP)
	area.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	area.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(area)
	_areas.push_back(area)
	_fill(i)
	if best:
		var tag := BestTag.new()
		tag.name = "BestValue"
		_store.add_child(tag)
		# top −16, right −6 off the face
		tag.position = Vector2(BODY_W - ShadowStyle.OFFSET + 6.0 - tag.custom_minimum_size.x + BestTag.DROP, panel.position.y - 16.0)


# ---- the buy button --------------------------------------------------------------


func state(i: int) -> String:
	return str(_st[i]["state"])


## A tap on pack `i`'s price: idle → ask.
func tap(i: int) -> void:
	if state(i) == "idle":
		_set_state(i, "ask")


func cancel(i: int) -> void:
	if state(i) == "ask":
		_set_state(i, "idle")


## BUY: the store's turn (the spinner) until the sale is credited or not.
func confirm(i: int) -> void:
	if state(i) != "ask" or Store.buying() != "":
		return
	_set_state(i, "busy")
	Store.purchase(str(TicketShop.packs()[i]["id"]))


## Store.purchase_done: the credit landed (granted already: count up from
## the old balance), or the sale did not happen (back to the price, with a
## word when it was not the player's own cancel).
func _on_purchase_done(product_id: String, ok: bool, reason: String) -> void:
	var i := _index_of(product_id)
	if i < 0 or state(i) != "busy":
		return
	if ok:
		var n := int(TicketShop.packs()[i]["tickets"])
		show_bought(i, App.tickets() - n)
		return
	_set_state(i, "idle")
	match reason:
		"error":
			_toast(StoreCopy.failed(), CREAM, StoreCopy.detail(Store.last_error))
		"unavailable":
			_toast(StoreCopy.unavailable(), CREAM)
		"slow":
			_toast(StoreCopy.on_the_way(), RetroTheme.LIGHT["gold"])


func _index_of(product_id: String) -> int:
	for i in TicketShop.packs().size():
		if str(TicketShop.packs()[i]["id"]) == product_id:
			return i
	return -1


## The store's own price strings arrived: the idle and ask buttons re-read them.
func _on_prices() -> void:
	for i in _st.size():
		if state(i) == "idle" or state(i) == "ask":
			_fill(i)


## A credit landed outside a sale this page is showing (Store.sync, a slow
## webhook): the chip follows and a toast says so. A sale in flight shows
## its own +N (the credit signal comes a beat before purchase_done).
func _on_credited(n: int) -> void:
	if Store.buying() != "" or (_flight != null and _flight.playing()):
		return
	set_tickets()
	_toast(StoreCopy.credited(n), RetroTheme.LIGHT["gold"])


const TOAST_TOP := 44.0

## The toast is built off-tree too (tests); `show_once` runs deferred, once the page is up.
func _toast(text: String, colour: Color, sub := "") -> void:
	var toast := Toast.new(colour, UiLayout.screen_top() + TOAST_TOP)
	toast.name = "StoreToast"
	toast.set_small(text, sub, "icon_ticket")
	add_child(toast)
	toast.show_once.call_deferred()


func _exit_tree() -> void:
	if Store.purchase_done.is_connected(_on_purchase_done):
		Store.purchase_done.disconnect(_on_purchase_done)
	if Store.prices_changed.is_connected(_on_prices):
		Store.prices_changed.disconnect(_on_prices)
	if Store.tickets_credited.is_connected(_on_credited):
		Store.tickets_credited.disconnect(_on_credited)


## The sale's success shown: +N, the tickets flying from the pack into the
## chip and the count ticking from `from_balance` up by the pack. Visual
## only — the grant is the store's (QA and the tests call it directly).
func show_bought(i: int, from_balance: int) -> void:
	_set_state(i, "done")
	_fly_from = from_balance
	_chip_count.text = RetroTheme.thousands(from_balance)
	var n := int(TicketShop.packs()[i]["tickets"])
	if not _flight.is_inside_tree():
		_flight.play(StoreFlight.FROM, Vector2.ZERO, n)   # off-tree (tests): the count only
		return
	var origin := _flight.get_global_rect().position
	var pack := _packs[i].get_global_rect().position - origin
	var to := _chip_icon.get_global_rect().get_center() - origin
	_flight.play(pack + StoreFlight.FROM, to, n)


func flight() -> StoreFlight:
	return _flight


func balance_text() -> String:
	return _chip_count.text


func _set_state(i: int, s: String) -> void:
	_st[i]["state"] = s
	_st[i]["t"] = 0.0
	_st[i]["until"] = _clock + DONE_S if s == "done" else 0.0
	_fill(i)


func _fill(i: int) -> void:
	var area := _areas[i]
	for c in area.get_children():
		area.remove_child(c)
		c.queue_free()
	var price := TicketShop.price(str(TicketShop.packs()[i]["id"]))
	match state(i):
		"ask":
			var x := button("X", CREAM, 26, BUY.y)
			x.name = "Cancel"
			x.custom_minimum_size = Vector2(X_W, BUY.y) + Vector2.ONE * ShadowStyle.OFFSET
			x.pressed.connect(cancel.bind(i))
			area.add_child(x)
			var ok := ShadowCard.new(RetroTheme.LIGHT["gold"])
			ok.name = "Confirm"
			ok.custom_minimum_size = Vector2(CONFIRM_W, BUY.y) + Vector2.ONE * ShadowStyle.OFFSET
			var oc := _centred(VBoxContainer.new(), 10)
			ok.add_child(oc)
			var bw := words("BUY", 20, true)
			bw.name = "Word"
			oc.add_child(bw)
			var bp := words(price, 18)
			bp.name = "Price"
			oc.add_child(bp)
			ok.pressed.connect(confirm.bind(i))
			area.add_child(ok)
		"busy":
			var busy := ShadowPanel.new(RetroTheme.LIGHT["orange"], 0.0, ShadowStyle.TINT)
			busy.name = "Busy"
			busy.custom_minimum_size = BUY + Vector2.ONE * ShadowStyle.OFFSET
			busy.mouse_default_cursor_shape = Control.CURSOR_BUSY
			var spin := PixelSpinner.new(32.0)
			spin.name = "Spinner"
			spin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			spin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			busy.add_child(spin)
			area.add_child(busy)
		"done":
			# A plain holder: the pop scales the face, which a container would reset.
			var hold := Control.new()
			hold.name = "Done"
			hold.custom_minimum_size = BUY + Vector2.ONE * ShadowStyle.OFFSET
			hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
			area.add_child(hold)
			var face := ShadowPanel.new(RetroTheme.LIGHT["gold"], 0.0, 0.5)
			face.name = "Face"
			face.size = hold.custom_minimum_size
			face.pivot_offset = BUY * 0.5
			hold.add_child(face)
			var dl := words("+%d" % int(TicketShop.packs()[i]["tickets"]), 24, true)
			dl.name = "Word"
			dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			face.add_child(dl)
			_pop(face, 0.0)
		_:
			var buy := button(price, RetroTheme.LIGHT["orange"], 26, BUY.y)
			buy.name = "Price"
			buy.custom_minimum_size = BUY + Vector2.ONE * ShadowStyle.OFFSET
			buy.pressed.connect(tap.bind(i))
			area.add_child(buy)


## A column centred on a button's face (clear of its shadow strip).
func _centred(box: BoxContainer, gap: int) -> BoxContainer:
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", gap)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiLayout.full_rect(box)
	box.offset_right = -ShadowStyle.OFFSET
	box.offset_bottom = -ShadowStyle.OFFSET
	return box


func _pop(face: Control, t: float) -> void:
	var v := CssEase.done_pop(t)
	face.scale = Vector2.ONE * v.x
	face.modulate.a = v.y


func _process(dt: float) -> void:
	_clock += dt
	for i in _st.size():
		_st[i]["t"] = float(_st[i]["t"]) + dt
		if state(i) == "done":
			var face: Control = _areas[i].get_node_or_null("Done/Face")
			if face != null:
				_pop(face, float(_st[i]["t"]))
			if _clock >= float(_st[i]["until"]):
				_set_state(i, "idle")
	if _bump_t >= 0.0:
		_bump_t += dt
		_chip_icon.scale = Vector2.ONE * CssEase.cnt_bump(_bump_t, BUMP_S, BUMP)
		if _bump_t >= BUMP_S:
			_bump_t = -1.0
			_chip_icon.scale = Vector2.ONE


## A flyer landed: the chip counts up and its ticket bumps.
func _on_count(shown: int) -> void:
	_chip_count.text = RetroTheme.thousands(_fly_from + shown)
	_bump_t = 0.0


func set_tickets() -> void:
	super()
	if _chip_count != null and (_flight == null or not _flight.playing()):
		_chip_count.text = RetroTheme.thousands(App.tickets())


## BEST VALUE: butter with a 2 px ink edge and a 4 px ink drop, ink words.
class BestTag extends Control:
	const H := 44.0
	const PAD := 14.0
	const DROP := 4.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := UiFont.label("BEST VALUE", 16, RetroTheme.SCENE_OUTLINE, UiFont.display())
		l.name = "Word"
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w := UiFont.display().get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFont.snap(16)).x
		l.position = Vector2(PAD, 0)
		l.size = Vector2(w, H)
		add_child(l)
		custom_minimum_size = Vector2(w + 2.0 * PAD + DROP, H + DROP)
		size = custom_minimum_size
	func _draw() -> void:
		var face := Rect2(Vector2.ZERO, size - Vector2.ONE * DROP)
		draw_rect(Rect2(face.position + Vector2.ONE * DROP, face.size), RetroTheme.SCENE_OUTLINE)
		draw_rect(face, HI)
		draw_rect(Rect2(face.position + Vector2.ONE, face.size - Vector2.ONE * 2.0), RetroTheme.SCENE_OUTLINE, false, 2.0)


## tkFly (design 50a): 6 tickets (12 for a pack over 500), 44 px, 0.08 s
## apart, 0.7 s each, from the pack's buy area into the chip's ticket.
class StoreFlight extends TicketStream:
	## The stream's start in the pack (the design's 590 / 470 against the pack's 36 / 360).
	const FROM := Vector2(576, 132)
	func _init() -> void:
		super()
		dur = 0.7
		gap = 0.08
		icon = Vector2(44, 28)
	func flyers_for(n: int) -> int:
		return 0 if n <= 0 else (12 if n > 500 else 6)
	func flyer_start(i: int) -> Vector2:
		return from + Vector2(-float((i * 53) % 120), float((i * 37) % 50) - 25.0)
	func flyer_mid(i: int) -> Vector2:
		return to + (flyer_start(i) - to) * 0.4 + Vector2(-60, -40)
	func flyer_at(i: int, t: float) -> Dictionary:
		var t0 := start + float(i) * gap
		if t < t0 or t > t0 + dur:
			return {}
		var r0 := (1.0 if i % 2 == 1 else -1.0) * (18.0 + float(i) * 6.0)
		var rm := (-1.0 if i % 2 == 1 else 1.0) * 12.0
		var f := CssEase.tk_fly((t - t0) / dur, flyer_start(i), flyer_mid(i), to, r0, rm)
		f["rot"] = deg_to_rad(float(f["rot"]))
		return f
