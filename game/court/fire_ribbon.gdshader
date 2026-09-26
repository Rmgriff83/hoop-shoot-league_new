// A single line of flames around the rim: a thin open cylinder strip standing on
// the ring, textured with a looping flipbook rendered in Blender
// (tools/blender/render_fire_flipbook.py, 8 x 4 frames, frame 0 top-left).
// `tiles` frames wrap around the ring; u scrolls slowly so the tile seams never
// sit still; `intensity` fades the flames in/out and stretches them taller.
shader_type spatial;
render_mode cull_disabled, unshaded, blend_add, depth_draw_never, fog_disabled;

uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform float t = 0.0;
uniform float intensity = 0.0;   // 0 = out, 1 = fully lit
uniform float tiles = 4.0;
uniform float fps = 30.0;
uniform float cols = 8.0;
uniform float rows = 4.0;

varying float vv;

void vertex() {
	// The top edge licks: a little sideways/vertical wander that varies around the ring.
	float h = 1.0 - UV.y;            // 0 at the base, 1 at the top (glTF-free mesh: UV.y = 0 at top)
	float lick = sin(UV.x * 31.0 + t * 9.0) * 0.5 + sin(UV.x * 17.0 - t * 6.0) * 0.5;
	VERTEX.y += h * lick * 0.03 * intensity;
	VERTEX.y *= mix(0.6, 1.15, clamp(intensity, 0.0, 1.0));
	vv = UV.y;
}

void fragment() {
	float frames = cols * rows;
	float fi = mod(floor(t * fps), frames);
	float c = mod(fi, cols);
	float r = floor(fi / cols);
	// Wrap `tiles` frames around the ring, scrolling so the seams drift.
	float u = fract(UV.x * tiles + t * 0.22);
	float v = clamp(UV.y, 0.0, 1.0);
	vec2 uv = vec2((c + u) / cols, (r + v) / rows);
	vec4 s = texture(sheet, uv);
	float a = s.a * clamp(intensity, 0.0, 1.0);
	ALBEDO = s.rgb * a * 1.2;
	ALPHA = a;
}
