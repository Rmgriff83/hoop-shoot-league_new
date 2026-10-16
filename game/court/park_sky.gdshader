// The park's partly cloudy winter sky (game/view/park_fx.gd), on the glb's
// `Sky` sphere seen from inside: a horizon → mid → top gradient, a warm sun
// glow around the sun's direction, and pixel-stepped clouds read from a
// tileable mask that drifts slowly. Unshaded, drawn first, never fogged.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec3 top_colour : source_color = vec3(0.30, 0.52, 0.84);
uniform vec3 mid_colour : source_color = vec3(0.55, 0.72, 0.90);
uniform vec3 horizon_colour : source_color = vec3(0.80, 0.86, 0.92);
uniform vec3 sun_dir = vec3(-0.65, 0.51, -0.56);
uniform sampler2D clouds : hint_default_white, filter_nearest, repeat_enable;
uniform float cloud_cover = 0.56;
uniform float cloud_edge = 0.12;
uniform float drift = 0.012;

varying vec3 v_dir;

void vertex() {
	v_dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(v_dir);
	float y = max(d.y, 0.0);
	vec3 c = mix(horizon_colour, mid_colour, smoothstep(0.0, 0.18, y));
	c = mix(c, top_colour, smoothstep(0.18, 0.75, y));
	float sd = max(dot(d, normalize(sun_dir)), 0.0);
	c += vec3(1.0, 0.93, 0.78) * (pow(sd, 6.0) * 0.28 + pow(sd, 400.0) * 1.2);
	// the cloud plane: the mask projected onto a dome, pixel-stepped
	vec2 uv = d.xz / (y + 0.12) * 0.16;
	uv = floor(uv * 96.0) / 96.0;
	vec2 scroll = vec2(TIME * drift, TIME * drift * 0.33);
	float cl = texture(clouds, uv + scroll).r;
	float cov = smoothstep(cloud_cover, cloud_cover + cloud_edge, cl) * smoothstep(0.0, 0.08, y);
	float shade = smoothstep(0.55, 0.78, texture(clouds, uv * 1.7 + vec2(0.35, 0.2) + scroll).r);
	vec3 cc = mix(vec3(0.98, 0.97, 0.95), vec3(0.70, 0.74, 0.82), shade * 0.8) + vec3(1.0, 0.9, 0.75) * pow(sd, 4.0) * 0.25;
	c = mix(c, cc, cov * 0.92);
	ALBEDO = c;
}
