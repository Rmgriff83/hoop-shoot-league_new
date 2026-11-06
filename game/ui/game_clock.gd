class_name GameClock
extends RefCounted
## The clock for effects that read real time: sound rate limits, sprite
## frames, twinkles. In play it IS real time. Under Godot's Movie Maker
## (the trailer, docs/TRAILER.md) a frame takes as long as it takes to
## render, so real time runs far ahead of the picture; there it counts game
## time instead, fed once a frame by Sfx._process — a rim rattle then plays
## its clip as often as it does on a phone, and a slow-motion shot slows
## these with everything else.

static var movie := OS.has_feature("movie")
static var _usec := 0


static func advance(dt: float) -> void:
	_usec += int(round(dt * 1_000_000.0))


static func usec() -> int:
	return _usec if movie else Time.get_ticks_usec()


static func msec() -> int:
	return usec() / 1000
