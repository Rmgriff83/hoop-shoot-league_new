extends RefCounted
## WordFilter (docs/HOME.md → New player): typing scrubbed to A–Z, 0–9 and
## single spaces; the blocked list read inside words, across spaces, in leet
## and stretched; the verdict table the Worker's twin shares
## (data/word_filter_cases.json); the rolled handles and listed towns all
## pass; the list itself stays tidy.


func run(t) -> void:
	_typing(t)
	_verdicts(t)
	_lists(t)


func _typing(t) -> void:
	t.eq(WordFilter.clean_typing("brick  baron", 24), "BRICK BARON", "upper-case, single spaces")
	t.eq(WordFilter.clean_typing("  salt harbor ", 16), "SALT HARBOR ", "no leading space; a trailing one stays while typing")
	t.eq(WordFilter.clean_typing("'; DROP TABLE players; --", 24), "DROP TABLE PLAYERS ", "quotes, semicolons and dashes go")
	t.eq(WordFilter.clean_typing("<script>alert(1)</script>", 24), "SCRIPTALERT1SCRIPT", "angle brackets and parentheses go")
	t.eq(WordFilter.clean_typing("na​me\n\ttab\u0000", 24), "NAMETAB", "zero-width, line breaks, tabs and NULs go")
	t.eq(WordFilter.clean_typing("émilie 🏀 söder", 24), "MILIE SDER", "accents and emoji go (the pixel faces have no such glyphs)")
	t.eq(WordFilter.clean_typing("АСС", 24), "", "look-alike letters from other scripts go, never mapped")
	t.eq(WordFilter.clean_typing("a very long hometown name", 16), "A VERY LONG HOME", "capped")


func _verdicts(t) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/word_filter_cases.json"))
	t.ok(parsed is Dictionary and parsed["blocked"].size() >= 20 and parsed["allowed"].size() >= 20, "the shared verdict table")
	for s in parsed["blocked"]:
		t.ok(WordFilter.blocked_word(str(s)) != "", "blocked: %s" % s)
	for s in parsed["allowed"]:
		t.eq(WordFilter.blocked_word(str(s)), "", "allowed: %s" % s)
	t.eq(WordFilter.blocked_word("SH1T HEAD"), "SHIT", "names the word it found (leet)")
	t.eq(WordFilter.blocked_word("FU CK"), "FUCK", "…across a space")
	t.eq(WordFilter.blocked_word("FUUUCK"), "FUCK", "…stretched")
	t.eq(WordFilter.blocked_word("A SS"), "ASS", "…a whole word split")
	t.eq(WordFilter.blocked_word("fuck"), "FUCK", "…whatever the case")
	t.eq(WordFilter.blocked_word("FU​CK"), "FUCK", "…hidden characters stripped first, never a way round")
	t.eq(WordFilter.blocked_word(""), "", "nothing is clean")


func _lists(t) -> void:
	var l := WordFilter.lists()
	var all: Array = l["blocked"] + l["whole"]
	t.ok(all.size() >= 120, "a real list (%d)" % all.size())
	var seen := {}
	var re := RegEx.create_from_string("^[A-Z0-9]+$")
	for w in all + l["allow"]:
		t.ok(re.search(str(w)) != null, "%s: upper-case letters and digits only" % w)
	for w in all:
		t.ok(not seen.has(w), "%s listed once" % w)
		seen[w] = true
	for w in l["allow"]:
		var inside := false
		for b in l["blocked"]:
			if str(w).contains(str(b)):
				inside = true
		t.ok(inside, "%s is on the allow list because it contains a blocked word" % w)
	var w := HandleWords.words()
	for f in w["first"]:
		for s in w["second"]:
			if WordFilter.blocked_word("%s %s" % [f, s]) != "":
				t.ok(false, "a rolled handle never trips the filter (%s %s)" % [f, s])
	t.ok(true, "every rolled handle passes")
	for town in Towns.list():
		t.ok(Towns.valid(str(town)), "%s passes" % town)
