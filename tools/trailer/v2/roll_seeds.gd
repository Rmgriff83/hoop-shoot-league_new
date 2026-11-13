extends SceneTree
## What the NEW PLAYER page rolls for each seed (trailer v2 part 1: the page's
## rng is reseeded by stage_new_player, then its first roll, the name die and
## the hometown die run in that order). Pick a seed whose three reads are clean.
##   godot --headless --path . -s tools/trailer/v2/roll_seeds.gd [-- --from=1 --to=60]


func _init() -> void:
	var from := 1
	var to := 60
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--from="):
			from = int(str(a).trim_prefix("--from="))
		elif str(a).begins_with("--to="):
			to = int(str(a).trim_prefix("--to="))
	print("seed  first roll (name #tag, town)  ->  name die  ->  hometown die")
	for s in range(from, to + 1):
		var rng := DetRng.new()
		rng.reseed(s)
		var h := HandleWords.generate(rng)
		var town := Towns.pick(rng)
		var name2 := str(HandleWords.generate(rng)["name"])
		var town2 := Towns.pick(rng, town)
		print("%4d  %-22s #%s %-16s -> %-22s -> %s" % [s, str(h["name"]), str(h["tag"]), town, name2, town2])
	quit()
