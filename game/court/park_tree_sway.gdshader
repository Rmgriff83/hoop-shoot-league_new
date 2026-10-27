// A swaying park tree (game/view/park_fx.gd, Ross 2026-10-26): the PSX
// pack's trunk or leaf surface with its texture and tint, the crown drifting
// a few centimetres on a slow sine of TIME. The whole sway is this vertex
// stage — no script moves anything, the shadow pass gets the same offset.
// Each tree keeps its own beat from where it stands (MODEL_MATRIX carries
// the multimesh instance). Lit like the conformed StandardMaterial: flat,
// rough, no specular, nearest-sampled, alpha-cut leaves (cut 0 = opaque).
shader_type spatial;
render_mode cull_disabled, specular_disabled;

uniform sampler2D albedo : source_color, filter_nearest;
uniform vec4 tint : source_color = vec4(1.0);
uniform float cut = 0.0;        // alpha scissor threshold; 0 = opaque surface
uniform bool vertex_tint = false;
uniform float amp = 0.03;       // the crown's drift, metres
uniform float period = 3.6;     // seconds one sway takes
uniform float crown = 7.0;      // metres up at which the drift is full

void vertex() {
	vec4 w = MODEL_MATRIX * vec4(VERTEX, 1.0);
	vec3 at = MODEL_MATRIX[3].xyz;
	float h = clamp((w.y - at.y) / crown, 0.0, 1.0);
	float k = h * h * amp;
	float beat = TIME * 6.2831853 / period + at.x * 0.37 + at.z * 0.71;
	vec3 off = vec3(sin(beat), 0.0, 0.6 * cos(beat * 0.73 + at.x)) * k;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
}

void fragment() {
	vec4 c = texture(albedo, UV) * tint;
	if (vertex_tint) {
		c *= COLOR;
	}
	ALBEDO = c.rgb;
	ROUGHNESS = 0.95;
	SPECULAR = 0.0;
	if (cut > 0.0) {
		ALPHA = c.a;
		ALPHA_SCISSOR_THRESHOLD = cut;
	}
}
