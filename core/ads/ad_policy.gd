class_name AdPolicy
extends RefCounted
## When an interstitial may play (docs/ADS.md, Ross 2026-11-01): never for
## a remove_ads owner, never without a loaded ad, not during a new player's
## first `grace_matches` results, and never within `min_gap_s` of the last
## one. Headless: a dictionary in, a verdict out — `reason` names what said
## no (owner | not_started | not_loaded | grace | gap), "" when the ad may
## play; `should_show` is the bool of it. The nudge toward the store
## (`upsell_due`) comes once every `every` ads.


## ctx: {owner, available, ready, matches_played, grace_matches, last_ad_at (-1 = never), now, min_gap_s}
static func reason(ctx: Dictionary) -> String:
	if bool(ctx.get("owner", false)):
		return "owner"
	if not bool(ctx.get("available", false)):
		return "not_started"
	if not bool(ctx.get("ready", false)):
		return "not_loaded"
	if int(ctx.get("matches_played", 0)) < int(ctx.get("grace_matches", 0)):
		return "grace"
	var last := float(ctx.get("last_ad_at", -1.0))
	if last >= 0.0 and float(ctx.get("now", 0.0)) - last < float(ctx.get("min_gap_s", 0.0)):
		return "gap"
	return ""


static func should_show(ctx: Dictionary) -> bool:
	return reason(ctx) == ""


static func upsell_due(ads_shown: int, every: int) -> bool:
	return every > 0 and ads_shown > 0 and ads_shown % every == 0
