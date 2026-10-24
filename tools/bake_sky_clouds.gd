extends SceneTree
## Bakes the sky's two cloud noise fields (docs/PERFORMANCE.md → Stage 3c) into
## one tiling texture, game/court/sky_clouds.png: R = the 4-octave fbm that
## sets the cover, G = the 2-octave fbm that shades it (offset by the shader's
## (0.35, 0.2)), both periodic over PERIOD noise units so the drift wraps with
## no seam. park_sky.gdshader fetches it once per pixel instead of running
## 24 hash lookups per pixel per frame — the same thresholds and maths after.
## The noise is the shader's value noise with the lattice wrapped to the period
## (and an octave step of 2.0, so every octave tiles); the hash is evaluated
## in float64 here, so the cloud shapes are a new draw of the same statistics.
##   godot --headless --path . -s tools/bake_sky_clouds.gd    (then --import)

const OUT := "res://game/court/sky_clouds.png"
const SIZE := 1024          # texels per tile: 64 per noise unit, the finest octave (8 cells/unit) keeps 8 texels per cell
const PERIOD := 16.0        # noise units per tile (the visible plane spans ~9)
const SHADE_OFFSET := Vector2(0.35, 0.2)


static func _h(ix: int, iy: int) -> float:
	var v := sin(ix * 127.1 + iy * 311.7) * 43758.5453
	return v - floor(v)


## Value noise with the lattice wrapped every `per` cells.
static func _n(p: Vector2, per: int) -> float:
	var ix := floori(p.x)
	var iy := floori(p.y)
	var fx := p.x - ix
	var fy := p.y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var x0 := posmod(ix, per)
	var x1 := posmod(ix + 1, per)
	var y0 := posmod(iy, per)
	var y1 := posmod(iy + 1, per)
	return lerpf(lerpf(_h(x0, y0), _h(x1, y0), fx), lerpf(_h(x0, y1), _h(x1, y1), fx), fy)


static func fbm(p: Vector2) -> float:
	var a := 0.5
	var s := 0.0
	var per := int(PERIOD)
	for k in 4:
		s += a * _n(p, per)
		p *= 2.0
		per *= 2
		a *= 0.5
	return s


static func fbm2(p: Vector2) -> float:
	return 0.5 * _n(p, int(PERIOD)) + 0.25 * _n(p * 2.0, int(PERIOD) * 2)


func _initialize() -> void:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var k := PERIOD / SIZE
	for y in SIZE:
		for x in SIZE:
			var q := Vector2((x + 0.5) * k, (y + 0.5) * k)   # the texel's centre, where the GPU samples it
			img.set_pixel(x, y, Color(fbm(q), fbm2(q + SHADE_OFFSET), 0.0))
	var err := img.save_png(OUT)
	print("sky clouds: %s %dx%d period %.0f → %s (%s)" % [OUT, SIZE, SIZE, PERIOD, "ok" if err == OK else error_string(err), "run --import"])
	quit(0 if err == OK else 1)
