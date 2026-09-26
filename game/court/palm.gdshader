// Palm billboard in a breeze: the quad's vertices sway sideways (world z) and a
// little fore/aft, weighted by height squared so the trunk base stays planted
// and the crown moves most. Two sines at different rates so it never loops
// obviously; `phase` differs per tree. Alpha-scissored, double-sided, lit.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float t = 0.0;
uniform float sway = 0.14;
uniform float phase = 0.0;

void vertex() {
	// glTF import flips V: UV.y is 0 at the top of the texture, 1 at the bottom.
	float h = 1.0 - UV.y;
	float s = sin(t * 1.1 + phase) * 0.7 + sin(t * 2.3 + phase * 1.7) * 0.3;
	VERTEX.z += s * sway * h * h;
	VERTEX.x += s * sway * 0.35 * h * h;
}

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.9;
}
