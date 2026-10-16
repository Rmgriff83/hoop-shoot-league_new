// Park sky: gradient + sun glow + pixel-stepped drifting clouds.
// Line-for-line port of the SkyDome ShaderMaterial in Park Area Concept.html.
// Use as the Sky material of the park's WorldEnvironment (Sky -> ShaderMaterial).
shader_type sky;

// Colours are the raw values from the concept. They are NOT source_color:
// the maths runs on these exact numbers and the result is converted to
// linear once, at the end (see srgb_to_linear below).
uniform vec3 top_color = vec3(0.30, 0.52, 0.84);
uniform vec3 mid_color = vec3(0.55, 0.72, 0.90);
uniform vec3 horizon_color = vec3(0.80, 0.86, 0.92);   // same value as the fog colour
uniform vec3 sun_dir = vec3(-0.65204, 0.51232, -0.55890); // normalize(-14, 11, -12)

// Seconds. Drive from script (see guide) so it never jumps at TIME rollover.
uniform float cloud_time = 0.0;

// Cloud tuning, all equal to the concept's hard-coded numbers.
uniform float cloud_scale = 1.6;      // size of the cloud plane projection
uniform float cloud_pixels = 24.0;    // pixel stepping: blocks per unit of cloud plane
uniform float noise_scale = 0.55;
uniform vec2 drift = vec2(0.012, 0.004); // noise units per second (the "minimal motion")
uniform float coverage_lo = 0.50;     // partly cloudy threshold
uniform float coverage_hi = 0.62;
uniform float cloud_opacity = 0.92;

float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1.0, 0.0)), f.x), mix(h(i + vec2(0.0, 1.0)), h(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float a = 0.5, s = 0.0;
	for (int k = 0; k < 4; k++) { s += a * n(p); p *= 2.03; a *= 0.5; }
	return s;
}
vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = max(d.y, 0.0);

	vec3 c = mix(horizon_color, mid_color, smoothstep(0.0, 0.18, y));
	c = mix(c, top_color, smoothstep(0.18, 0.75, y));

	float sd = max(dot(d, normalize(sun_dir)), 0.0);
	c += vec3(1.0, 0.93, 0.78) * (pow(sd, 6.0) * 0.28 + pow(sd, 400.0) * 1.2);

	// Clouds are skipped in the radiance/reflection cubemap pass so the
	// moving clouds never force a per-frame radiance rebuild.
	if (!AT_CUBEMAP_PASS) {
		vec2 uv = d.xz / (y + 0.12) * cloud_scale;     // project onto a flat cloud plane
		uv = floor(uv * cloud_pixels) / cloud_pixels;  // pixel-step BEFORE the noise
		vec2 t = drift * cloud_time;
		float cl = fbm(uv * noise_scale + t);
		float cov = smoothstep(coverage_lo, coverage_hi, cl) * smoothstep(0.0, 0.08, y); // fade at the horizon
		float shade = smoothstep(0.55, 0.78, fbm(uv * noise_scale + vec2(0.35, 0.2) + t));
		vec3 cc = mix(vec3(0.98, 0.97, 0.95), vec3(0.70, 0.74, 0.82), shade * 0.8)
			+ vec3(1.0, 0.9, 0.75) * pow(sd, 4.0) * 0.25;
		c = mix(c, cc, cov * cloud_opacity);
	}

	COLOR = srgb_to_linear(c);
}
