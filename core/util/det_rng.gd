class_name DetRng
extends RefCounted
## Deterministic seeded RNG (xorshift64*). Core never touches engine RNG, so a
## seed + the same inputs always replays the same draws (AI shots, quick-sims,
## schedules, reward rolls). State is a plain int and round-trips through save
## dicts. Same pattern as hometown's DetRng, with normal() and fork() added.

const MASK64 := 0x7FFFFFFFFFFFFFFF   # keep the state positive (GDScript ints are signed 64-bit)

var state := 0x2545F4914F6CDD1D
var _spare_normal := 0.0
var _has_spare := false


func _init(seed_value := 0x2545F4914F6CDD1D) -> void:
	reseed(seed_value)


func reseed(seed_value: int) -> void:
	state = seed_value & MASK64
	if state == 0:
		state = 0x2545F4914F6CDD1D
	_has_spare = false
	# Warm up so nearby seeds diverge immediately.
	for i in 4:
		next_u()


## Next 53-bit-ish positive integer.
func next_u() -> int:
	var x := state
	x ^= (x >> 12)
	x ^= (x << 25) & MASK64
	x ^= (x >> 27)
	state = x & MASK64
	return (x * 2685821657736338717) & MASK64


## Uniform float in [0, 1).
func next() -> float:
	return float(next_u() >> 10) / 9007199254740992.0   # 53 bits / 2^53


func randf_range(lo: float, hi: float) -> float:
	return lo + (hi - lo) * next()


## Uniform int in [lo, hi] inclusive.
func range_i(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + int(next_u() % (hi - lo + 1))


## Standard normal (Box–Muller, cached spare).
func normal() -> float:
	if _has_spare:
		_has_spare = false
		return _spare_normal
	var u1 := maxf(next(), 1e-12)
	var u2 := next()
	var r := sqrt(-2.0 * log(u1))
	_spare_normal = r * sin(TAU * u2)
	_has_spare = true
	return r * cos(TAU * u2)


func pick(items: Array) -> Variant:
	if items.is_empty():
		return null
	return items[range_i(0, items.size() - 1)]


## Fisher–Yates shuffle of a copy.
func shuffled(items: Array) -> Array:
	var out := items.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := range_i(0, i)
		var tmp: Variant = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


## An independent stream derived from this one's seed and a label, so
## subsystems never share draws (AI vs rewards vs schedule).
func fork(label: String) -> DetRng:
	var h := hash_seed(label)
	return DetRng.new((state ^ h) & MASK64)


## Stable string → seed hash (FNV-1a 64, masked positive).
static func hash_seed(text: String) -> int:
	# FNV-1a 64 offset basis 0xcbf29ce484222325, written as its signed value
	# (GDScript integer literals are signed 64-bit).
	var h := -3750763034362895579
	for b in text.to_utf8_buffer():
		h = ((h ^ b) * 0x100000001b3) & MASK64
	return h if h != 0 else 1
