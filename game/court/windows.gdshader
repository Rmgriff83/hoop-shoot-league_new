// The city's building facades (game/view/city_fx.gd): a daylit photo atlas
// graded to dusk by `dusk_tint` (unshaded — the arena's cool ambient would
// otherwise flatten the photos to grey), a touch of form from the normal
// (`face_light`), plus lit windows. `mask` marks the panes of the atlas (white); the atlas
// is cut into `cells` x `cells` cells and each cell is a window that a
// per-cell hash lights or leaves dark, switching now and then — every cell
// has its own period (minutes) and phase, so at any moment a pane or two a
// building change, never a blink. `seed` is an instance uniform, so every
// building on the shared atlas lights differently; `clock` comes from CityFx.
// Without a mask (the old quad walls) the pane rectangle of each cell lights.
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D albedo : source_color, filter_linear;
uniform sampler2D mask : hint_default_black, filter_nearest;
uniform bool use_mask = true;
uniform vec2 cells = vec2(32.0, 32.0);
uniform vec2 pane_min = vec2(0.25, 0.19);
uniform vec2 pane_max = vec2(0.75, 0.81);
uniform float clock = 0.0;
uniform float lit_share = 0.6;
uniform float period_base = 180.0;
uniform float period_spread = 300.0;
uniform vec3 lit_color : source_color = vec3(1.0, 0.82, 0.55);
uniform vec3 dark_color : source_color = vec3(0.09, 0.12, 0.2);
uniform float emission_energy = 1.4;
uniform vec3 dusk_tint : source_color = vec3(0.72, 0.68, 0.84);
uniform float face_light = 0.25;
instance uniform float seed = 0.0;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 cell = floor(uv * cells) + vec2(seed * 17.0, seed * 5.0);
	vec2 f = fract(uv * cells);
	// Dusk grade, and a little form: faces toward the sky and the court's
	// floodlights (+y, -x) read brighter than those turned away.
	vec3 nrm = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float form = 1.0 - face_light + face_light * clamp(0.5 + 0.5 * nrm.y - 0.35 * nrm.x, 0.0, 1.0) * 2.0;
	vec3 tex = texture(albedo, uv).rgb * dusk_tint * form;
	float h1 = hash2(cell + vec2(0.1, 0.1));
	float h2 = hash2(cell + vec2(7.3, 7.3));
	float h3 = hash2(cell + vec2(3.7, 3.7));
	float period = period_base + period_spread * h2;
	float flips = floor((clock + h3 * period) / period);
	bool base_lit = h1 < lit_share;
	bool flipped = mod(flips, 2.0) >= 1.0;
	bool lit = base_lit != flipped;
	float warm = 0.8 + 0.4 * hash2(cell + vec2(11.1, 11.1));
	if (use_mask) {
		float pane = texture(mask, uv).r;
		ALBEDO = tex;
		EMISSION = lit ? lit_color * warm * pane * emission_energy : vec3(0.0);
		if (pane > 0.5 && !lit) {
			ALBEDO = mix(tex, dark_color, 0.6);
		}
	} else {
		bool in_pane = all(greaterThan(f, pane_min)) && all(lessThan(f, pane_max));
		ALBEDO = tex;
		if (in_pane) {
			ALBEDO = lit ? lit_color * warm : dark_color;
			EMISSION = lit ? lit_color * warm * emission_energy : vec3(0.0);
		}
	}
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
