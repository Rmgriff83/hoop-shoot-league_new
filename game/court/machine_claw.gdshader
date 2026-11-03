// The claw machine's cable and head, all in the vertex stage: a slow roam and a
// drop every 7 s. The mesh rests with the head at y 0; UV2.x = 1 marks what
// follows it down (the cable's top stays at the gantry). No script, no upload.
shader_type spatial;
render_mode cull_back;

uniform sampler2D atlas : source_color, filter_nearest;
uniform float rate = 1.0;   // 0 = still (the PiP's frozen cage)
uniform float k = 0.0;      // the slot's z: the design's phase

void vertex() {
	float t = TIME * rate;
	float ph = mod(t, 7.0) / 7.0;
	float drop = ph > 0.62 && ph < 0.86 ? sin((ph - 0.62) / 0.24 * PI) * 0.38 : 0.0;
	// Machine x is world z and machine z is world -x (the row faces the cage).
	VERTEX += vec3(0.04 - 0.15 * sin(t * 0.53 + k), UV2.x * (1.62 - drop), 0.2 * sin(t * 0.7 + k));
}

void fragment() {
	ALBEDO = texture(atlas, UV).rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
