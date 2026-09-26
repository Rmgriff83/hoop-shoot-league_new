class_name ScheduleGen
extends RefCounted
## Round-robin schedule for a compact league (circle method): with N teams
## (even) one cycle is N−1 days of N/2 games where everyone plays; `rounds`
## cycles (2 = home-and-home, 14 days at 8 teams). Seeded: the team order is
## shuffled once so every season pairs differently. Home/away flips between
## cycles. Game records match the original's GameRecord shape.


static func game_record(id: String, day: int, home: String, away: String) -> Dictionary:
	return {
		"id": id, "day": day, "homeId": home, "awayId": away,
		"homeScore": 0, "awayScore": 0, "homeSwishes": 0, "awaySwishes": 0,
		"ot": 0, "playedLive": false, "played": false,
	}


static func generate(team_ids: Array, rounds: int, seed_value: int, id_prefix := "g") -> Array:
	var rng := DetRng.new(seed_value)
	var order: Array = rng.shuffled(team_ids)
	var n := order.size()
	assert(n % 2 == 0, "round robin needs an even team count")
	var games := []
	var day := 0
	var fixed: Variant = order[0]
	var rest: Array = order.slice(1)
	for cycle in rounds:
		var rot: Array = rest.duplicate()
		for r in n - 1:
			day += 1
			var ring: Array = [fixed] + rot
			for i in n / 2:
				var a: Variant = ring[i]
				var b: Variant = ring[n - 1 - i]
				# Alternate home/away by day parity; the second cycle flips it.
				var a_home := ((r + i) % 2 == 0) == (cycle % 2 == 0)
				var home: String = str(a if a_home else b)
				var away: String = str(b if a_home else a)
				games.push_back(game_record("%s-d%02d-%d" % [id_prefix, day, i], day, home, away))
			# Rotate all but the fixed team.
			rot = [rot[rot.size() - 1]] + rot.slice(0, rot.size() - 1)
	return games


static func season_days(games: Array) -> int:
	var d := 0
	for g in games:
		d = maxi(d, int(g["day"]))
	return d


static func games_on(games: Array, day: int) -> Array:
	var out := []
	for g in games:
		if int(g["day"]) == day:
			out.push_back(g)
	return out
