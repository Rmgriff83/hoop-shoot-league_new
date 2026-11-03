// The machine row's unshaded atlas parts: marquees, playfields, coin lights,
// wheel header. A backglass or claw sign keeps its other frame in UV2 and flips
// to it every 380 ms (everything else has UV2 = UV, so the flip does nothing).
// One draw, no script.
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float rate = 1.0;   // 0 = still (the PiP's frozen cage)

varying vec2 atlas_uv;

void vertex() {
	float odd = mod(floor(TIME * rate / 0.38), 2.0);
	atlas_uv = mix(UV2, UV, odd);
}

void fragment() {
	ALBEDO = texture(atlas, atlas_uv).rgb;
}
