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

// The clouds' clock is TIME plus this phase (ParkFx.CLOUD_T0, set once).
// Driving it from script every frame flagged the Sky dirty and re-rendered
// its radiance cubemap every frame on the phone (2026-10-16); TIME costs
// nothing. Its rollover is pushed out to days in project.godot
// (rendering/limits/time/time_rollover_secs), so the one jump never shows.
uniform float cloud_time = 0.0;

// Cloud tuning: the concept's hard-coded numbers (the cover thresholds re-set for the bake, above).
uniform float cloud_scale = 1.6;      // size of the cloud plane projection
uniform float cloud_pixels = 24.0;    // pixel stepping: blocks per unit of cloud plane
uniform float noise_scale = 0.55;
uniform vec2 drift = vec2(0.012, 0.004); // noise units per second (the "minimal motion")
// Partly cloudy: the concept's 0.50 / 0.62 on the GPU's own noise; 0.60 / 0.72
// on the baked field reads the same (the hash took the sine of numbers in the
// thousands, which every GPU rounds its own way — the baked draw has more
// mid values, so the cover threshold sits higher for the same sky).
uniform float coverage_lo = 0.60;
uniform float coverage_hi = 0.72;
uniform float cloud_opacity = 0.92;

// The two noise fields baked to a tiling texture (tools/bake_sky_clouds.gd:
// R = fbm for the cover, G = fbm2 for the shade, periodic over cloud_period
// noise units): one fetch per pixel instead of 24 hash lookups — on the
// phone the per-pixel noise cost the park 6 ms and the city 3.6
// (docs/PERFORMANCE.md → Stage 3c). `baked` 0 runs the noise in place
// (the --qa-ab=sky_fbm lever: the look before 2026-10-24).
uniform sampler2D clouds : repeat_enable, filter_linear;
uniform float cloud_period = 16.0;
uniform float baked = 1.0;
// Where the clouds fade out toward the horizon (the concept's 0.08 of EYEDIR.y).
// The per-pixel noise hashed the sine of numbers in the thousands near the
// horizon, which every GPU collapses differently and left the low sky clear;
// the baked field keeps real clouds there, so the fade carries that look.
uniform float horizon_fade = 0.08;
// Where in the baked tile the clouds start (noise units): the look at launch.
uniform vec2 cloud_offset = vec2(0.0, 0.0);

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
// The shade layer only steers a soft tint, so two octaves carry it.
float fbm2(vec2 p) {
	return 0.5 * n(p) + 0.25 * n(p * 2.03);
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
		vec2 t = drift * (TIME + cloud_time);
		vec2 q = uv * noise_scale + t + cloud_offset;
		float cl;
		float sh;
		if (baked > 0.5) {
			vec2 f = texture(clouds, q / cloud_period).rg;
			cl = f.r;
			sh = f.g;
		} else {
			cl = fbm(q);
			sh = fbm2(q + vec2(0.35, 0.2));
		}
		float cov = smoothstep(coverage_lo, coverage_hi, cl) * smoothstep(0.0, horizon_fade, y); // fade at the horizon
		float shade = smoothstep(0.55, 0.78, sh);
		vec3 cc = mix(vec3(0.98, 0.97, 0.95), vec3(0.70, 0.74, 0.82), shade * 0.8)
			+ vec3(1.0, 0.9, 0.75) * pow(sd, 4.0) * 0.25;
		c = mix(c, cc, cov * cloud_opacity);
	}

	COLOR = srgb_to_linear(c);
}
