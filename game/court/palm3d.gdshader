// The beach's 3D coconut palms (design "Beach Concept" 34a, 2026-10-16): the
// unit model in palm.glb, drawn ten times by two MultiMeshes (trunks + nuts,
// fronds) placed by the PalmRig empties. The sway runs here, in the model's
// own unit frame, phased by each instance's world position (MODEL_MATRIX is
// the per-instance matrix in a MultiMesh), weighted by height squared so the
// foot stays planted; the fronds flutter on top of it (`flutter`), each by
// its own phase and outward direction carried in UV2 (x: phase / 32, y:
// direction / 2π). Alpha-scissored, double-sided, lit; nearest sampling like
// the design's palm textures.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled;

uniform sampler2D tex : source_color, filter_nearest_mipmap;
uniform float t = 0.0;
uniform bool flutter = false;

void vertex() {
	float ph = MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 0.9;
	float hh = clamp(VERTEX.y, 0.0, 1.2);
	float s = sin(t * 1.1 + ph) * 0.7 + sin(t * 2.3 + ph * 1.7) * 0.3;
	VERTEX.z += s * 0.035 * hh * hh;
	VERTEX.x += s * 0.012 * hh * hh;
	if (flutter) {
		float rr = length(VERTEX.xz - vec2(0.36, 0.0));
		float pf = UV2.x * 32.0 + ph;
		float ang = UV2.y * TAU;
		vec2 side = vec2(-sin(ang), cos(ang));
		float gust = 0.6 + 0.4 * sin(t * 0.7 + pf * 0.5);
		float lift = (sin(t * 1.9 + pf) * 0.7 + sin(t * 3.7 + pf * 1.3) * 0.3) * gust;
		VERTEX.y += lift * 0.04 * rr * rr * 4.0;
		VERTEX.xz += side * sin(t * 1.4 + pf * 1.7) * 0.028 * rr * rr * 4.0 * gust;
		VERTEX.y += sin(t * 5.3 + pf + rr * 14.0) * 0.004 * rr;
	}
}

void fragment() {
	vec4 c = texture(tex, UV);
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 0.9;
}
