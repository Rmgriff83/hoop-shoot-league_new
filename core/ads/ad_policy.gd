class_name AdPolicy
extends RefCounted
## When an interstitial may play (docs/ADS.md, Ross 2026-11-01): never for
## a remove_ads owner, never without a loaded ad, not during a new player's
## first `grace_matches` results, and never within `min_gap_s` of the last
## one. Headless: a dictionary in, a bool out. The nudge toward the store
## (`upsell_due`) comes once every `every` ads.


## ctx: {owner, available, ready, matches_played, grace_matches, last_ad_at (-1 = never), now, min_gap_s}
static func should_show(ctx: Dictionary) -> bool:
	if bool(ctx.get("owner", false)) or not bool(ctx.get("available", false)) or not bool(ctx.get("ready", false)):
		return false
	if int(ctx.get("matches_played", 0)) < int(ctx.get("grace_matches", 0)):
		return false
	var last := float(ctx.get("last_ad_at", -1.0))
	if last >= 0.0 and float(ctx.get("now", 0.0)) - last < float(ctx.get("min_gap_s", 0.0)):
		return false
	return true


static func upsell_due(ads_shown: int, every: int) -> bool:
	return every > 0 and ads_shown > 0 and ads_shown % every == 0
