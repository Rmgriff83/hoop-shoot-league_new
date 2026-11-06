class_name PeggyGifts
extends RefCounted
## Free PEGGY plays (docs/LOCKER.md → Free plays): the reasons one is given
## and the rule for the first of them. A free play is a PLAY that costs no
## tickets; each reason grants once per save (cosmetics.peggy.gifts). Pure:
## App reads the save and calls in.

## After a new player's very first finished time trial or match (design
## "First Time Walkthrough" 36c, 2026-11-06).
const FIRST_PLAY := "first_play"

## What an earlier play leaves behind. Any of them above zero and this is
## not the save's first play: a player from before the free play shipped.
const PLAYED_FACTS := ["scores", "league_games", "online_games", "results", "xp", "drops"]


## Is the play about to be recorded the save's first? `facts` are read
## BEFORE the play is written: trial scores kept, league games, rated online
## games, results counted, xp, PEGGY drops.
static func is_first_play(facts: Dictionary) -> bool:
	for k in PLAYED_FACTS:
		if int(facts.get(k, 0)) > 0:
			return false
	return true


## The free plays in a cosmetics doc's peggy block.
static func free_plays(peggy: Dictionary) -> int:
	return maxi(0, int(peggy.get("free", 0)))


static func granted(peggy: Dictionary, reason: String) -> bool:
	return Array(peggy.get("gifts", [])).has(reason)


## The peggy block with `n` free plays added for `reason`; unchanged (and
## false) when that reason was already given or `n` is not positive.
static func grant(peggy: Dictionary, reason: String, n := 1) -> Dictionary:
	if reason == "" or n <= 0 or granted(peggy, reason):
		return {"ok": false, "peggy": peggy}
	var out := peggy.duplicate(true)
	var gifts: Array = Array(out.get("gifts", [])).duplicate()
	gifts.push_back(reason)
	out["gifts"] = gifts
	out["free"] = free_plays(out) + n
	return {"ok": true, "peggy": out}
