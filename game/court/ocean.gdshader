// Beach ocean, 2D-texture style. A subdivided plane rides three travelling
// sines (a long swell, a short chop and a diagonal cross-swell) heading toward
// the shore (-x), flattened over the last metres so crests never dip through
// the sand. The look stays flat and painterly: two drifting layers of the
// water texture, plus stylized two-tone crest lines that roll shoreward and
// break whiter as they reach the beach. Unshaded on purpose (a low sun would
// leave a lit plane nearly black); `t` is fed by BeachFx every frame.
shader_type spatial;
render_mode cull_disabled, unshaded;

uniform sampler2D water : source_color, filter_linear_mipmap, repeat_enable;
uniform float t = 0.0;
uniform float a1 = 0.07;
uniform float k1 = 2.2;     // ~2.9 m swell
uniform float w1 = 1.6;
uniform float a2 = 0.03;
uniform float k2 = 5.7;     // ~1.1 m chop
uniform float w2 = 2.4;
uniform float a3 = 0.04;
uniform float k3 = 1.4;     // diagonal cross-swell
uniform float w3 = 1.1;
uniform float tiles = 6.0;
uniform float shore_fade = 0.12;   // fraction of the plane (from the shore edge) where waves die out
uniform float crest_width = 0.18;  // how much of each swell shows as a foam line (0..1)
uniform vec3 crest : source_color = vec3(0.92, 0.97, 1.0);
uniform vec3 crest_shadow : source_color = vec3(0.16, 0.42, 0.52);

varying float h;
varying float wx;
varying float wz;

void vertex() {
	float fade = smoothstep(0.0, shore_fade, UV.x);
	wx = VERTEX.x;
	wz = VERTEX.z;
	h = fade * (a1 * sin(k1 * wx + w1 * t)
		+ a2 * sin(k2 * (wx + 0.5 * wz) + w2 * t)
		+ a3 * sin(k3 * (wx - 0.7 * wz) + w3 * t));
	VERTEX.y += h;
}

void fragment() {
	vec2 uv1 = UV * vec2(tiles, tiles * 2.5) + vec2(-0.05 * t, 0.02 * t);
	vec2 uv2 = UV * vec2(tiles * 0.45, tiles * 1.1) + vec2(0.025 * t, -0.012 * t);
	vec3 c = mix(texture(water, uv1).rgb, texture(water, uv2).rgb, 0.5);

	// Stylized crest lines: the long swell's phase, thresholded to a band that
	// travels shoreward. A darker trough line rides just behind each crest so
	// the wave reads as a drawn shape, not a gradient.
	float phase = 0.5 + 0.5 * sin(k1 * wx + w1 * t + 0.35 * sin(0.8 * wz + 0.3 * t));
	float shore_w = 1.0 - smoothstep(0.0, 0.35, UV.x);   // stronger toward the beach
	float line = smoothstep(1.0 - crest_width, 1.0 - crest_width * 0.5, phase);
	float trough = smoothstep(0.55, 0.65, phase) * (1.0 - smoothstep(0.7, 0.8, phase));
	float foam = line * mix(0.35, 1.0, shore_w) * smoothstep(0.0, 0.04, UV.x);
	c = mix(c, crest_shadow, trough * 0.35);
	c = mix(c, crest, foam);
	// Chop glints: small bright flecks where the short chop peaks.
	float glint = smoothstep(0.024, 0.03, a2 * sin(k2 * (wx + 0.5 * wz) + w2 * t));
	c = mix(c, crest, glint * 0.25);
	ALBEDO = c;
}
