// The machine row's lit parts: the atlas's paint with a grain over it, lighter
// or darker around the paint's own colour. UV2 is the surface's position in
// metres, so the grain keeps one scale on every face. One extra fetch, no draw.
shader_type spatial;
render_mode cull_back;

uniform sampler2D atlas : source_color, filter_nearest;
uniform sampler2D grain : filter_nearest, repeat_enable;
uniform float grain_per_m = 1.0;   // tiles of the grain per metre
uniform float detail = 0.5;        // 0 = the bare paint

void fragment() {
	float g = texture(grain, UV2 * grain_per_m).r * 2.0 - 1.0;
	ALBEDO = texture(atlas, UV).rgb * (1.0 + detail * g);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
