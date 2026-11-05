class_name WordFilter
extends RefCounted
## The filter over what a player types — their name and hometown (NEW
## PLAYER, Settings → PLAYER). `clean_typing` keeps A–Z, 0–9 and single
## spaces (quotes, punctuation, line breaks, emoji, accents and look-alike
## letters all go, so nothing but plain words ever reaches a save or the
## server). `blocked_word` finds a word from data/blocked_words.json in the
## cleaned text: anywhere inside a word or across a space (FUCKVILLE, FU CK),
## with digits read as letters (SH1T, 80085) and stretched letters squeezed
## (FUUUCK); `whole` words match a whole word only (ASS, never CLASS) and
## `allow` words are innocent despite what they contain (SCUNTHORPE). The
## server runs the same rule over the same file (server/src/word_filter.ts).
## Pure: no nodes.

const PATH := "res://data/blocked_words.json"
const LEET := {"0": "O", "1": "I", "2": "Z", "3": "E", "4": "A", "5": "S", "6": "G", "7": "T", "8": "B", "9": "G"}

static var _lists: Dictionary = {}
static var _strip: RegEx


static func lists() -> Dictionary:
	if _lists.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_lists = parsed if parsed is Dictionary else {"blocked": [], "whole": [], "allow": []}
	return _lists


## Typing tidied in place (upper-case, the allowed characters, single
## spaces, at most `max_len`) with a trailing space kept so words can follow.
static func clean_typing(raw: String, max_len: int) -> String:
	if _strip == null:
		_strip = RegEx.create_from_string("[^A-Z0-9 ]")
	var s := _strip.sub(raw.to_upper(), "", true)
	while s.contains("  "):
		s = s.replace("  ", " ")
	if s.begins_with(" "):
		s = s.substr(1)
	return s.left(max_len)


## The blocked word the text carries, or "" when it is clean.
static func blocked_word(text: String) -> String:
	var l := lists()
	var allow: Array = l.get("allow", [])
	var tokens := PackedStringArray()
	for tok in clean_typing(text, 1 << 20).split(" ", false):
		if not allow.has(tok):
			tokens.append(tok)
	if tokens.is_empty():
		return ""
	var blocked: Array = l.get("blocked", [])
	var whole: Array = l.get("whole", [])
	var leet := PackedStringArray()
	var squeezed := PackedStringArray()
	for tok in tokens:
		var lt := _leet(tok)
		leet.append(lt)
		squeezed.append(_squeeze(lt))
	for form in [tokens, leet]:
		var hit := _find(form, blocked, whole)
		if hit != "":
			return hit
	# Stretched spellings: only words without a doubled letter can be read
	# squeezed (BOOB squeezed is BOB, which a BOB must keep).
	var single_b: Array = blocked.filter(func(w: Variant) -> bool: return _squeeze(str(w)) == str(w))
	var single_w: Array = whole.filter(func(w: Variant) -> bool: return _squeeze(str(w)) == str(w))
	return _find(squeezed, single_b, single_w)


static func _find(tokens: PackedStringArray, blocked: Array, whole: Array) -> String:
	var squash := "".join(tokens)
	for w in blocked:
		if squash.contains(str(w)):
			return str(w)
	for w in whole:
		if tokens.has(str(w)) or squash == str(w):
			return str(w)
	return ""


static func _leet(tok: String) -> String:
	var out := ""
	for ch in tok:
		out += str(LEET.get(ch, ch))
	return out


static func _squeeze(tok: String) -> String:
	var out := ""
	for ch in tok:
		if out.is_empty() or out[out.length() - 1] != ch:
			out += ch
	return out
