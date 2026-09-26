// Rim ice (cold streak): translucent blue-white ice with a fresnel edge and a
// few drifting sparkles. `freeze` reveals it from the outside of the rim
// inward (radial distance from `center` between r_out and r_in); `fade`
// dissolves a shard as it flies off; `frost` whitens the whole thing.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform float freeze = 1.0;
uniform float fade = 1.0;
uniform float frost = 0.0;
uniform float crack = 0.0;   // 0..1: fissures light up as the ice fails
uniform float t = 0.0;
uniform vec3 center = vec3(0.0);
uniform float r_out = 0.25;
uniform float r_in = 0.18;
uniform vec4 tint : source_color = vec4(0.5, 0.78, 1.0, 1.0);

varying float vr;
varying vec3 vworld;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	vworld = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vr = length((vworld - center).xz);
}

void fragment() {
	// Freeze-in: outer ring first, the lip last, with a crystalline noisy edge.
	float k = clamp((r_out - vr) / max(r_out - r_in, 0.001), 0.0, 1.0);
	float edge = hash3(floor(vworld * 220.0)) * 0.18;
	if (k + edge > freeze * 1.18) {
		discard;
	}
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	// Deeper, bluer toward the lip (k → 1), pale frost at the rim.
	vec3 deep = tint.rgb * vec3(0.55, 0.7, 0.95);
	vec3 base = mix(mix(tint.rgb, deep, k * 0.8), vec3(0.9, 0.96, 1.0), frost * 0.5);
	// Sparkles: sparse bright specks that twinkle.
	vec3 cell = floor(vworld * 160.0 + vec3(0.0, t * 0.7, 0.0));
	float sp = step(0.965, hash3(cell)) * (0.5 + 0.5 * sin(t * 9.0 + hash3(cell + 1.0) * 6.28));
	// Fissures: sparse cells brighten as `crack` rises, then the whole slab glows.
	float fis = step(1.0 - 0.35 * crack, hash3(floor(vworld * 70.0) + 3.0));
	ALBEDO = base * 0.7 + fres * 0.3 + sp * 0.6 + fis * 0.3;
	EMISSION = vec3(0.1, 0.3, 0.5) * (0.35 + 0.65 * fres) + sp * vec3(0.5, 0.6, 0.7)
		+ vec3(0.6, 0.8, 1.0) * (fis * 0.45 + crack * crack * 0.12);
	ALPHA = clamp((0.78 + 0.22 * fres) * fade, 0.0, 1.0);
	ROUGHNESS = 0.18;
	SPECULAR = 0.7;
	METALLIC = 0.0;
}
