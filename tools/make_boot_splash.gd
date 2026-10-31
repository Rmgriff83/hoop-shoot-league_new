extends SceneTree
## The boot splash (Ross, 2026-10-30): the neon ball centred on the brick wall,
## its glow feathered to a circle, at 2x nearest → assets/splash/boot_splash.png
## (application/boot_splash/image; iOS reuses it for the launch screen).
## Also the Android 12+ launch icon (export option splash_screen/icon): the same
## ball on a clear ground, sized so that on the system splash (a 288 dp icon box,
## centred) it lands where the boot splash draws it — 235 dp on the 720×1604 /
## 280 dpi phone — so the handover only brings the bricks in around it.
## godot --headless --path . -s tools/make_boot_splash.gd

func _initialize() -> void:
	var bg := Image.load_from_file("res://assets/splash/neon_bg.png")
	var ball := Image.load_from_file("res://assets/splash/neon_ball_on.png")
	bg.convert(Image.FORMAT_RGBA8)
	ball.convert(Image.FORMAT_RGBA8)
	# Feather the glow to a circle: the art's glow runs to its square edge.
	var mid := Vector2(ball.get_width(), ball.get_height()) * 0.5
	for y in ball.get_height():
		for x in ball.get_width():
			var r := Vector2(x + 0.5, y + 0.5).distance_to(mid) / mid.x
			var k := clampf((1.0 - r) / 0.3, 0.0, 1.0)
			if k < 1.0:
				var px := ball.get_pixel(x, y)
				px.a *= k * k * (3.0 - 2.0 * k)
				ball.set_pixel(x, y, px)
	var at := Vector2i((bg.get_width() - ball.get_width()) / 2, (bg.get_height() - ball.get_height()) / 2)
	bg.blend_rect(ball, Rect2i(Vector2i.ZERO, ball.get_size()), at)
	var sum := Color(0, 0, 0)
	var n := 0
	for y in range(0, bg.get_height(), 8):
		for x in range(0, bg.get_width(), 8):
			var c := bg.get_pixel(x, y)
			if y < 300 or y > bg.get_height() - 300:
				sum += c
				n += 1
	print("edge avg ", Color(sum.r / n, sum.g / n, sum.b / n).to_html(false))
	# The launch icon: 504 px box (288 dp at 1.75), the ball 411 px (the boot
	# image's 800 px ball covered onto a 1604-tall screen: 800 × 1604 / 3120).
	var icon := Image.create_empty(504, 504, false, Image.FORMAT_RGBA8)
	var small := ball.duplicate()
	small.resize(411, 411, Image.INTERPOLATE_BILINEAR)
	icon.blend_rect(small, Rect2i(Vector2i.ZERO, small.get_size()), Vector2i((504 - 411) / 2, (504 - 411) / 2))
	print("icon ", icon.save_png("res://assets/splash/android_splash_icon.png"))
	bg.resize(bg.get_width() * 2, bg.get_height() * 2, Image.INTERPOLATE_NEAREST)
	bg.convert(Image.FORMAT_RGB8)
	print("save ", bg.save_png("res://assets/splash/boot_splash.png"), " ", bg.get_size())
	quit()
