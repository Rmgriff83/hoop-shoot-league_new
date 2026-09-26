// Cabinet marquee: a warm backlit strip with a row of chasing bulbs along the
// top and bottom edges. Unshaded, driven by `t` (+ `phase`).
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

uniform float t = 0.0;
uniform float phase = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 0.8, 0.35);
uniform float bulbs = 12.0;

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	float tt = t + phase;
	// Backlit panel with a soft horizontal band.
	vec3 col = tint * (0.55 + 0.25 * sin(uv.x * 6.283 + tt * 0.8));
	// Bulb rows: each bulb lights in turn (chase), three at a time.
	float k = floor(uv.x * bulbs);
	float lit = step(fract(tt * 1.5 - k / bulbs), 0.25);
	float on_row = step(abs(uv.y - 0.12), 0.08) + step(abs(uv.y - 0.88), 0.08);
	float bulb = on_row * step(abs(fract(uv.x * bulbs) - 0.5), 0.22);
	col = mix(col, vec3(1.0, 0.98, 0.85), bulb * lit) + bulb * (1.0 - lit) * vec3(0.12, 0.05, 0.02);
	ALBEDO = col;
	EMISSION = col * 0.8;
}
