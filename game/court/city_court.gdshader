// The city court: the asphalt tile and the painted lines and leaves in one pass.
// They were two meshes, the paint a full-court alpha-cut quad over the asphalt,
// which lit every court pixel twice (about 1 ms on the phone, 2026-11-03).
shader_type spatial;
render_mode cull_back;

uniform sampler2D asphalt : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D paint : source_color, filter_nearest;
uniform vec2 court_tiles = vec2(14.6, 15.2);   // the asphalt's repeats over the court (build_city.py)

void fragment() {
	vec2 paint_uv = vec2(UV.x / court_tiles.x, 1.0 - (1.0 - UV.y) / court_tiles.y);
	vec4 p = texture(paint, paint_uv);
	ALBEDO = p.a > 0.5 ? p.rgb : texture(asphalt, UV).rgb;
	ROUGHNESS = 1.0;
}
