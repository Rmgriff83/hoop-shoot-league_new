extends RefCounted
## The hometown list and rules (Towns, data/towns.json).


func run(t) -> void:
	var all := Towns.list()
	t.ok(all.size() >= 30, "at least thirty towns (%d)" % all.size())
	var display := UiFont.display()
	var bold := UiFont.body_bold()
	for town in all:
		t.ok(str(town).length() <= Towns.TOWN_MAX and Towns.valid(str(town)), "%s fits the rules" % town)
		for ch in str(town):
			t.ok(display.has_char(ch.unicode_at(0)) and bold.has_char(ch.unicode_at(0)), "glyph '%s' in both faces (%s)" % [ch, town])
	var rng := DetRng.new(7)
	var a := Towns.pick(rng)
	t.ok(all.has(a), "pick draws from the list")
	t.eq(Towns.pick(DetRng.new(7)), a, "same seed, same town")
	var b := Towns.pick(DetRng.new(7), a)
	t.ok(b != a and all.has(b), "a roll never lands on the town it was avoiding")
	t.eq(Towns.normalize("  salt   harbor! "), "SALT HARBOR", "normalize: upper, single spaces, no punctuation")
	t.eq(Towns.normalize("a very long town name indeed"), "A VERY LONG TOWN", "normalize caps at %d" % Towns.TOWN_MAX)
	t.ok(Towns.valid("BLUE MESA") and not Towns.valid("") and not Towns.valid("blue mesa") and not Towns.valid("  BLUE"), "valid wants a tidy non-empty town")
