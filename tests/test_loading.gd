extends RefCounted
## The loading states (design "Loading States" 39a / 39b, 2026-10-25).


func run(t) -> void:
	# The loader's rule: no screen under 0.4 s, at least 0.6 s once up.
	t.eq(LoadingCopy.next_step(0.1, false, -1.0), "wait", "a quick load shows nothing")
	t.eq(LoadingCopy.next_step(0.2, true, -1.0), "finish", "…and finishes straight away")
	t.eq(LoadingCopy.next_step(0.45, false, -1.0), "show", "past 0.4 s the screen comes up")
	t.eq(LoadingCopy.next_step(0.6, true, 0.15), "hold", "loaded, but the screen stays its 0.6 s")
	t.eq(LoadingCopy.next_step(1.1, true, 0.65), "finish", "…then the move")
	t.eq(LoadingCopy.next_step(2.0, false, 1.5), "wait", "a long load keeps the screen")
	# The words.
	t.eq([LoadingCopy.dots(0.0), LoadingCopy.dots(0.35), LoadingCopy.dots(0.65), LoadingCopy.dots(1.0), LoadingCopy.dots(1.25)], ["", ".", "..", "...", ""], "LOADING's dots in four steps")
	var d := LoadingCopy.dest("continue", "Beach")
	t.eq([d["dest"], d["sub"], d["busy"]], ["BEACH", "WHERE YOU LEFT OFF", "LOADING YOUR SAVE"], "CONTINUE: where you left off")
	t.eq(LoadingCopy.stage_for(d["stages"], 0), "READING YOUR SAVE", "the first stage")
	t.eq(LoadingCopy.stage_for(d["stages"], 30), "BUILDING THE BEACH", "…the next at 26 %")
	t.eq(LoadingCopy.stage_for(d["stages"], 100), "HANGING THE NET", "…the last at the end")
	var n := LoadingCopy.dest("new", "Arcade Cage")
	t.eq([n["dest"], n["sub"], n["stages"][1]], ["ARCADE CAGE", "YOUR FIRST COURT", "BUILDING THE CAGE"], "NEW GAME builds the cage")
	var h := LoadingCopy.dest("heat", "Arcade Cage", "LEAGUE · SEASON 2 · DAY 4 · VS OLLIE")
	t.eq([h["sub"], h["stages"][1], h["busy"]], ["LEAGUE · SEASON 2 · DAY 4 · VS OLLIE", "LOADING OLLIE", ""], "a match: the league line, the opponent loading, the button keeps its name")
	t.ok(LoadingCopy.tip_at(0.0) != LoadingCopy.tip_at(LoadingCopy.TIP_S), "the tip changes every few seconds")
	# The spinner turns in 45° steps.
	t.eq(PixelSpinner.slot_at(7, 0.0), 7, "the lead starts top-left")
	t.eq(PixelSpinner.slot_at(7, 0.1), 0, "…one step on after a tenth of a second")
	# The screen.
	var s := LoadingScreen.new(d, "res://assets/ui/areas/area_beach_tall.png")
	s.manual = true
	t.ok(s.find_child("Art", true, false) != null, "the destination's art behind")
	t.eq((s.find_child("Dest", true, false) as Label).text, "BEACH", "where you're going, in gold")
	s.set_progress(0.5)
	s.step(0.1)
	t.eq((s.find_child("Pct", true, false) as Label).text, "50%", "the percentage")
	t.eq((s.find_child("Stage", true, false) as Label).text, "BUILDING THE BEACH...", "what is loading")
	s.set_progress(0.3)
	t.eq(s.progress(), 0.5, "the bar never runs backwards")
	t.ok((s.find_child("Tip", true, false) as Label).text != "", "a tip")
	s.free()
	# The pressed button's loading state.
	var page := Control.new()
	var b := HomePage.button("RUN IT BACK", RetroTheme.c("orange"), 22, 120.0)
	b.custom_minimum_size = Vector2(400, 125)
	var other := HomePage.button("HOME", Color.WHITE, 20, 120.0)
	page.add_child(b)
	page.add_child(other)
	ButtonBusy.apply(b, "", page)
	t.ok(ButtonBusy.is_busy(b) and b.button_pressed and b.disabled, "the pressed button stays pushed in")
	t.eq((b.find_child("BusySub", true, false) as Label).text, "RUN IT BACK", "…LOADING with its own name under it")
	t.ok(other.disabled and is_equal_approx(other.modulate.a, ButtonBusy.DIM), "every other button dims and stops taking taps")
	page.free()
	# Lists (39b): the skeleton rows while a board loads.
	var sk := SkeletonList.new("LOADING RANKS")
	t.eq(sk.custom_minimum_size.y, SkeletonList.HEAD_H + SkeletonList.ROW_H * 4, "a head and four skeleton rows")
	t.ok(sk.find_child("Spinner", false, false) is PixelSpinner, "…with the spinner in the head")
	sk._process(0.65)
	t.eq(sk.text(), "LOADING RANKS..", "LOADING RANKS with live dots")
	t.close(SkeletonList.pulse(0.0, 0.0), 0.35, 1e-6, "the bars rest at 0.35")
	t.close(SkeletonList.pulse(0.6, 0.0), 0.6, 1e-6, "…and pulse to 0.6 halfway")
	t.close(SkeletonList.pulse(0.75, 0.15), 0.6, 1e-6, "each row a beat behind")
	sk.free()
	var cold := RewardsPage.new()
	cold.build({})
	t.ok(cold.root.find_child("Skeleton", true, false) != null and cold.root.find_child("MeterBar", true, false) == null, "rewards with nothing cached: the skeleton, not an empty meter")
	cold.set_data({"pending": [], "unlocked": [], "login_days": 0})
	t.ok(cold.root.find_child("MeterBar", true, false) != null, "…until the answer comes")
	cold.free()
	# 3D previews (39b): PEGGY's slot spinner while the cabinet loads on a thread.
	var was := PeggyMachine.threaded
	PeggyMachine.threaded = false
	var m := PeggyMachine.new()
	t.ok(m.loaded() and m.find_child("SlotSpinner", false, false) == null and not m.is_busy(), "a synchronous build has no spinner")
	m.free()
	PeggyMachine.threaded = was
