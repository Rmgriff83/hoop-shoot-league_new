// The ticket wheel's face: 1/48 of a turn every 90 ms, clockwise from the front,
// all in the vertex stage. The disc lies in its local yz plane round its origin.
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float rate = 1.0;   // 0 = still (the PiP's frozen cage)

void vertex() {
	float a = mod(floor(TIME * rate / 0.09), 48.0) * TAU / 48.0;
	vec2 p = VERTEX.zy;
	VERTEX.z = p.x * cos(a) + p.y * sin(a);
	VERTEX.y = p.y * cos(a) - p.x * sin(a);
}

void fragment() {
	ALBEDO = texture(atlas, UV).rgb;
}
