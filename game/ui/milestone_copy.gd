class_name MilestoneCopy
extends RefCounted
## The names of the server's grants (docs/BACKEND.md → Ranked → Stage B):
## milestone keys, login days and the welcome-back card, as the rewards page
## and the post-match page print them. Keys are the server's; the words are
## ours. Headless.


static func name(key: String) -> String:
	match key:
		"first_login": return "FIRST LOGIN"
		"first_ranked_match": return "FIRST RANKED MATCH"
		"first_ranked_win": return "FIRST RANKED WIN"
		"first_capture": return "FIRST SPOILS"
	if key.begins_with("ranked_wins_"):
		return "%d RANKED WINS" % int(key.trim_prefix("ranked_wins_"))
	if key.begins_with("login_day_"):
		return "LOGIN DAY %d" % int(key.trim_prefix("login_day_"))
	if key.begins_with("welcome_back"):
		return "WELCOME BACK"
	if key.begins_with("tier_"):
		return "%s REACHED" % RankedRules.tier_name(key.trim_prefix("tier_"))
	if key.begins_with("division_"):
		var parts := key.trim_prefix("division_").rsplit("_", true, 1)
		if parts.size() == 2:
			return "%s %s REACHED" % [RankedRules.tier_name(parts[0]), RankedRules.division_numeral(int(parts[1]))]
	return key.to_upper().replace("_", " ")


## A rank step's name on the ladder: `PRO` (the tier reached) or `PRO II`.
static func step_name(key: String) -> String:
	return name(key).trim_suffix(" REACHED")


## Is this key a rank step (a tier or a division reached)?
static func is_step(key: String) -> bool:
	return key.begins_with("tier_") or key.begins_with("division_")


## The grant's kind as a short word over its row.
static func kind_word(kind: String) -> String:
	match kind:
		"login": return "LOGIN REWARD"
		"welcome_back": return "WELCOME BACK"
		"milestone": return "MILESTONE"
	return kind.to_upper()


static func strings() -> Array:
	var out := [kind_word("login"), kind_word("welcome_back"), kind_word("milestone")]
	for k in OnlineDrops.all_milestone_keys():
		out.push_back(name(k))
	out.push_back(name("login_day_7"))
	out.push_back(name("welcome_back_20750"))
	return out
