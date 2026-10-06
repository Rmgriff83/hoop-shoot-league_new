extends RefCounted
## HandleWords (docs/BACKEND.md → Identity): a seeded handle from the word
## lists, the display form, the name rule the server shares, and every word
## in both pixel faces.


func run(t) -> void:
	var w := HandleWords.words()
	t.ok(w["first"].size() >= 30 and w["second"].size() >= 30, "two generous word lists")
	var a := HandleWords.generate(DetRng.new(42))
	var b := HandleWords.generate(DetRng.new(42))
	t.eq(a, b, "the same seed, the same handle")
	var parts: PackedStringArray = str(a["name"]).split(" ")
	t.eq(parts.size(), 2, "two words")
	t.ok(w["first"].has(parts[0]) and w["second"].has(parts[1]), "from the lists, in order")
	t.ok(RegEx.create_from_string("^[0-9]{2}$").search(str(a["tag"])) != null, "a two-digit tag")
	t.ok(HandleWords.valid(str(a["name"])), "a generated handle is a valid name")
	t.eq(HandleWords.display("BRICK BARON", "42"), "BRICK BARON 42", "the display form")
	t.eq(HandleWords.display("BRICK BARON", ""), "BRICK BARON", "no tag, no trailing space")
	t.eq(HandleWords.normalize("  brick   baron "), "BRICK BARON", "tidied")
	t.ok(HandleWords.valid("BRICK BARON"), "a plain name")
	t.ok(not HandleWords.valid("AB"), "too short")
	t.ok(not HandleWords.valid("A".repeat(25)), "too long")
	t.ok(not HandleWords.valid("BRICK-BARON"), "no punctuation")
	t.ok(not HandleWords.valid("brick baron"), "already upper-cased by then")
	t.ok(not HandleWords.valid("FUCK BARON"), "a blocked word")
	t.ok(HandleWords.valid("FU CK BARON"), "short blocked words match whole tokens only")
	t.ok(not HandleWords.valid("NIG GER"), "long ones match squashed too")
	var display := UiFont.display()
	var bold := UiFont.body_bold()
	for list in [w["first"], w["second"]]:
		for word in list:
			for ch in str(word):
				t.ok(display.has_char(ch.unicode_at(0)) and bold.has_char(ch.unicode_at(0)), "glyph '%s' in both faces (%s)" % [ch, word])
