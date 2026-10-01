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

uniform sampler2D albedo : source_color, filter_linear_mipmap;
uniform sampler2D mask : hint_default_black, filter_nearest;
// R + 256 G = the window's id (conform_buildings.lua): one state per window.
uniform sampler2D window_id : hint_default_black, filter_nearest;
uniform bool use_mask = true;
uniform vec2 cells = vec2(32.0, 32.0);
uniform vec2 pane_min = vec2(0.25, 0.19);
uniform vec2 pane_max = vec2(0.75, 0.81);
uniform float clock = 0.0;
uniform float lit_share = 0.34;
uniform float period_base = 240.0;
uniform float period_spread = 600.0;
uniform vec3 lit_color : source_color = vec3(1.0, 0.82, 0.55);
uniform vec3 dark_color : source_color = vec3(0.09, 0.12, 0.2);
uniform float emission_energy = 1.4;
uniform vec3 dusk_tint : source_color = vec3(0.9, 0.88, 0.94);
uniform float face_light = 0.25;
instance uniform float seed = 0.0;

// Integer hash (exact on every GPU — the sine hash collapses in the
// half-precision floats phone GPUs use). Mirrored by CityFx.hash_f.
uint hash_u(uint x) {
	x ^= x >> 16u;
	x *= 0x7feb352du;
	x ^= x >> 15u;
	x *= 0x846ca68bu;
	x ^= x >> 16u;
	return x;
}

float hash_f(float a, float b) {
	uint h = hash_u((uint(a + 7.0) * 0x9E3779B9u) ^ hash_u(uint(b + 3.0)));
	return float(h & 0xFFFFFFu) / 16777216.0;
}

void fragment() {
	vec2 uv = UV;
	vec2 cell = floor(uv * cells);
	float wid = cell.x + cell.y * 131.0 + seed * 17.0;
	if (use_mask) {
		vec2 idt = texture(window_id, uv).rg;
		float id = floor(idt.r * 255.0 + 0.5) + 256.0 * floor(idt.g * 255.0 + 0.5);
		// UV2.x is the face's own key (build_city.py), so every copy of an
		// atlas window on a building rolls its lights apart.
		float face_key = floor(UV2.x * 997.0 + 0.5);
		wid = id + 41.0 * face_key + seed * 17.0;
	}
	vec2 f = fract(uv * cells);
	// Dusk grade, and a little form: faces toward the sky and the court's
	// floodlights (+y, -x) read brighter than those turned away.
	vec3 nrm = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float form = 1.0 - face_light + face_light * clamp(0.5 + 0.5 * nrm.y - 0.35 * nrm.x, 0.0, 1.0) * 2.0;
	vec3 tex = texture(albedo, uv).rgb * dusk_tint * form;
	float h2 = hash_f(wid, 1.0);
	float h3 = hash_f(wid, 2.0);
	float period = period_base + period_spread * h2;
	// Every period the window re-rolls its state (not a toggle: a toggle
	// drifts every building toward half lit; a re-roll holds lit_share).
	float epoch = floor((clock + h3 * period) / period);
	bool lit = hash_f(wid, 100.0 + epoch) < lit_share;
	float warm = 0.8 + 0.4 * hash_f(wid, 5.0);
	// Unshaded: the lit pane is painted straight into ALBEDO (EMISSION is a
	// lighting term and never reaches an unshaded surface).
	if (use_mask) {
		float pane = texture(mask, uv).r;
		vec3 glow = lit_color * warm * emission_energy;
		// A lit pane keeps a little of the glass and frame under the glow.
		ALBEDO = lit ? mix(tex, glow, 0.8 * pane) : mix(tex, dark_color, 0.6 * pane);
	} else {
		bool in_pane = all(greaterThan(f, pane_min)) && all(lessThan(f, pane_max));
		ALBEDO = tex;
		if (in_pane) {
			ALBEDO = lit ? lit_color * warm * emission_energy : dark_color;
		}
	}
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
