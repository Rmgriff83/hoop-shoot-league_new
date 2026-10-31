extends RefCounted
## The generic button click (Ross, 2026-10-26): five clips, one at random
## per press (never the same twice running), hooked onto every BaseButton
## that enters the tree unless it opts out with the `no_click` meta.


func run(t) -> void:
	for i in 5:
		var s: AudioStream = load("res://assets/audio/click_%d.wav" % i)
		t.ok(s != null and s.get_length() > 0.15 and s.get_length() < 0.4, "click_%d ships (~0.2-0.3 s)" % i)
	var sfx = Engine.get_main_loop().root.get_node_or_null("Sfx")
	if sfx == null:
		t.ok(false, "the Sfx autoload is up")
		return
	var seen := {}
	var last: int = sfx.last_click()
	var repeat := false
	for i in 40:
		sfx.click()
		var now: int = sfx.last_click()
		if now == last:
			repeat = true
		t.ok(now >= 0 and now < 5, "a pick in range")
		seen[now] = true
		last = now
	t.ok(not repeat, "never the same clip twice running")
	t.ok(seen.size() >= 3, "the picks spread over the set (%d of 5 in 40)" % seen.size())
	# The hook (the runner executes before the autoload's _ready connects it
	# to node_added, so drive the handler directly): a button entering the
	# tree is wired to click on pressed; a no_click one is not.
	var b := Button.new()
	sfx._on_node_added(b)
	t.ok(b.pressed.is_connected(sfx.click), "a Button entering the tree is wired to Sfx.click")
	var quiet := Button.new()
	quiet.set_meta(sfx.NO_CLICK, true)
	sfx._on_node_added(quiet)
	t.ok(not quiet.pressed.is_connected(sfx.click), "…unless it carries no_click")
	var plain := Node.new()
	sfx._on_node_added(plain)
	t.ok(true, "a non-button passes through")
	var before: int = sfx.last_click()
	b.pressed.emit()
	t.ok(sfx.last_click() != before, "a press picks a clip")
	b.free()
	quiet.free()
	plain.free()
	var src := FileAccess.get_file_as_string("res://game/autoload/sfx.gd")
	t.ok(src.find("get_tree().node_added.connect(_on_node_added)") >= 0, "Sfx hooks node_added in _ready")
	# The pre-match pick (Ross, 2026-10-30): a dragged card clicks as it lifts and as it lands.
	var pm := FileAccess.get_file_as_string("res://game/ui/pre_match_page.gd")
	var lift := pm.substr(pm.find("func _start_ghost("), 400)
	t.ok(lift.find("Sfx.click()") >= 0, "a card picked up off the row clicks")
	var drop := pm.substr(pm.find("App.equip_card(over, cid, bucket)"), 120)
	t.ok(drop.find("Sfx.click()") >= 0, "…and clicks again as it lands in a slot")
	# Credited (Ross, 2026-10-26): TannerSound's pack.
	var credits: Dictionary = load("res://game/screens/credits_screen.gd").load_credits()
	var found := false
	for c in credits["sounds"]:
		if str(c.get("url", "")) == "https://freesound.org/people/TannerSound/sounds/843597/" and str(c.get("author", "")) == "TannerSound":
			found = true
	t.ok(found, "the clicks are credited to TannerSound at Ross's link")
