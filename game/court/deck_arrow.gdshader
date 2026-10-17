// The cage's return arrows (DeckArrow%02d decals): the LED chevron texture
// (two rows of white-cored dots in a dark housing, design "Arcade Cage
// Concept" 32a), coloured by how lit the step is — ArcadeFx.chase() runs
// `lit` down the lane when a game starts. The design's four states as a
// ramp over lit: off (a dim brown ember) → low → mid (orange) → on (warm
// white at the head). The housing's dark greys stay dark under any tint;
// the white dots take the colour. Unshaded so the rest state is a steady
// paint-like glow whatever the sun does; alpha-scissored, no fringe.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_nearest, repeat_disable;
uniform float lit : hint_range(0.0, 1.0) = 0.0;
uniform vec3 led_off : source_color = vec3(0.227, 0.141, 0.078);   // #3A2414
uniform vec3 led_low : source_color = vec3(0.478, 0.243, 0.086);   // #7A3E16
uniform vec3 led_mid : source_color = vec3(0.910, 0.439, 0.227);   // #E8703A
uniform vec3 led_on : source_color = vec3(1.000, 0.886, 0.659);    // #FFE2A8

vec3 ramp(float k) {
	if (k < 0.34) {
		return mix(led_off, led_low, k / 0.34);
	}
	if (k < 0.67) {
		return mix(led_low, led_mid, (k - 0.34) / 0.33);
	}
	return mix(led_mid, led_on, (k - 0.67) / 0.33);
}

void fragment() {
	vec4 c = texture(tex, UV);
	if (c.a < 0.5) {
		discard;
	}
	vec3 tint = ramp(lit);
	// The dots take the colour; a lit step also floods its housing with a
	// share of it, so the chase reads from the key where a dot is a pixel.
	vec3 base = c.rgb * tint;
	ALBEDO = mix(base, tint, lit * 0.45);
	EMISSION = mix(base, tint, lit * 0.45) * lit * 1.4;
}
