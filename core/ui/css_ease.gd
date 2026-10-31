class_name CssEase
extends RefCounted
## The design prototypes' CSS timing, ported (pure, headless): cubic-bezier
## curves, steps(), and keyframe runs. CSS applies an animation's timing
## function to EACH keyframe interval, not to the whole run — a 0 % / 45 % /
## 100 % keyframe set eases twice — and these ports follow that. The named
## animations below are the ones "Home League Context v2" (2026-10-30) uses.

const SNAP := Vector4(0.2, 0.8, 0.2, 1.0)     # cubic-bezier(.2,.8,.2,1): the slides
const EASE := Vector4(0.25, 0.1, 0.25, 1.0)   # ease
const EASE_IN := Vector4(0.42, 0.0, 1.0, 1.0)
const EASE_OUT := Vector4(0.0, 0.0, 0.58, 1.0)
const EASE_IN_OUT := Vector4(0.42, 0.0, 0.58, 1.0)
const FLY := Vector4(0.45, 0.05, 0.3, 1.0)    # cardFly


## cubic-bezier(p.x, p.y, p.z, p.w) at progress x (0..1), exact at the ends.
static func bezier(p: Vector4, x: float) -> float:
	if x <= 0.0 or x >= 1.0:
		return clampf(x, 0.0, 1.0)
	var lo := 0.0
	var hi := 1.0
	var u := x
	for i in 30:
		u = (lo + hi) * 0.5
		if _b(u, p.x, p.z) < x:
			lo = u
		else:
			hi = u
	return _b(u, p.y, p.w)


static func _b(u: float, a: float, b: float) -> float:
	return 3.0 * (1.0 - u) * (1.0 - u) * u * a + 3.0 * (1.0 - u) * u * u * b + u * u * u


## steps(n, end) at progress x: the value jumps at the end of each step.
static func steps(n: int, x: float) -> float:
	if x >= 1.0:
		return 1.0
	return floorf(clampf(x, 0.0, 1.0) * n) / float(n)


## A keyframe run at progress k (0..1): `keys` = [[at, value], …] sorted by
## `at` (0..1, values float / Vector2 / Vector3 — anything lerp takes), the
## timing `curve` (a Vector4 bezier, or an int n for steps(n, end)) applied
## inside each interval.
static func keyframes(keys: Array, k: float, curve: Variant = EASE) -> Variant:
	if k <= float(keys[0][0]):
		return keys[0][1]
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if k <= float(b[0]):
			var span := float(b[0]) - float(a[0])
			var x := (k - float(a[0])) / span if span > 0.0 else 1.0
			var e := steps(int(curve), x) if curve is int else bezier(curve, x)
			return lerp(a[1], b[1], e)
	return keys[keys.size() - 1][1]


# ---- the named animations ---------------------------------------------------------


## twinkle (the trophies' sparkle): 2.4 s, steps(6, end) per interval →
## Vector3(alpha, scale, rotation in degrees). `t` is seconds since the
## sparkle's own start (its delay already taken off); it loops.
const TWINKLE_S := 2.4
const TWINKLE_KEYS := [[0.0, Vector3(0, 0.3, 0)], [0.62, Vector3(0, 0.3, 0)], [0.70, Vector3(1, 1, 0)],
	[0.78, Vector3(0.9, 0.7, 45)], [0.86, Vector3(0, 0.2, 90)], [1.0, Vector3(0, 0.3, 0)]]

static func twinkle(t: float) -> Vector3:
	if t < 0.0:
		return Vector3(0, 0.3, 0)
	return keyframes(TWINKLE_KEYS, fposmod(t, TWINKLE_S) / TWINKLE_S, 6)


## tabDot (the MATCH tab's waiting dot): scale 1 → .8 → 1, 1.6 s ease-in-out, looping.
const TAB_DOT_S := 1.6

static func tab_dot(t: float) -> float:
	return keyframes([[0.0, 1.0], [0.5, 0.8], [1.0, 1.0]], fposmod(t, TAB_DOT_S) / TAB_DOT_S, EASE_IN_OUT)


## cntBump (a count badge taking one more): 0.35 s ease-out, 1 → 1.6 at 35 % → 1.
const BUMP_S := 0.35

static func cnt_bump(t: float) -> float:
	return keyframes([[0.0, 1.0], [0.35, 1.6], [1.0, 1.0]], clampf(t / BUMP_S, 0.0, 1.0), EASE_OUT)


## slotGrow (a new kind's slot opening in YOUR CARDS): 0.38 s on SNAP →
## Vector2(width 0 → 96, gap correction −28 → 0).
const GROW_S := 0.38

static func slot_grow(t: float) -> Vector2:
	var e := bezier(SNAP, clampf(t / GROW_S, 0.0, 1.0))
	return Vector2(96.0 * e, -28.0 * (1.0 - e))


## cardFly (a bought card into YOUR CARDS): 0.7 s, FLY per interval, the
## transform origin at the card's top-left → {pos, scale, rot (degrees)}.
## 0 %: `from`, scale `s0`; 45 %: the midpoint 40 px right, 90 px above the
## higher end, scale 1.15, −10°; 100 %: `to`, scale 1, 0°.
const FLY_S := 0.7

static func card_fly(t: float, from: Vector2, to: Vector2, s0: float) -> Dictionary:
	var mid := Vector2((from.x + to.x) / 2.0 + 40.0, minf(from.y, to.y) - 90.0)
	var k := clampf(t / FLY_S, 0.0, 1.0)
	var keys := [[0.0, Vector4(from.x, from.y, s0, 0.0)], [0.45, Vector4(mid.x, mid.y, 1.15, -10.0)], [1.0, Vector4(to.x, to.y, 1.0, 0.0)]]
	var v: Vector4 = keyframes(keys, k, FLY)
	return {"pos": Vector2(v.x, v.y), "scale": v.z, "rot": v.w}


## lbIn (the board popup sliding in): 0.3 s on SNAP → Vector2(x offset 80 → 0, opacity 0 → 1).
const LB_IN_S := 0.3

static func lb_in(t: float) -> Vector2:
	var e := bezier(SNAP, clampf(t / LB_IN_S, 0.0, 1.0))
	return Vector2(80.0 * (1.0 - e), e)
