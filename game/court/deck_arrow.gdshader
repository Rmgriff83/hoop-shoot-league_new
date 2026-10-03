// The cage's return arrows (DeckArrow%02d decals): the arrow texture, dim at
// rest and glowing when `lit` (ArcadeFx.chase() runs the lit value down the
// lane when a game starts). Unshaded so the dim state is a steady paint-like
// orange whatever the sun does; alpha-scissored so the decal has no fringe.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_nearest, repeat_disable;
uniform float lit : hint_range(0.0, 1.0) = 0.0;
uniform float idle : hint_range(0.0, 1.0) = 0.38;

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * mix(idle, 1.0, lit);
	EMISSION = c.rgb * lit * 1.4;
}
