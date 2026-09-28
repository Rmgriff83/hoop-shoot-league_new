// The city's building windows (game/view/city_fx.gd): the texture is a wall
// with a grid of `cells` windows per tile; each cell is one window whose pane
// (the `pane_min`..`pane_max` rectangle of the cell) is painted lit or dark by
// a per-cell hash, and switched now and then — every cell has its own period
// (minutes) and phase, so at any moment one or two panes a building change,
// never a blink. `clock` comes from CityFx so QA and tests step it.
shader_type spatial;
render_mode unshaded, cull_back;

uniform sampler2D albedo : source_color, filter_nearest;
uniform vec2 cells = vec2(4.0, 4.0);
uniform vec2 pane_min = vec2(0.25, 0.19);
uniform vec2 pane_max = vec2(0.75, 0.81);
uniform float clock = 0.0;
uniform float lit_share = 0.6;
uniform float period_base = 180.0;
uniform float period_spread = 300.0;
uniform vec3 lit_color : source_color = vec3(1.0, 0.82, 0.55);
uniform vec3 dark_color : source_color = vec3(0.09, 0.12, 0.2);

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 cell = floor(UV * cells);
	vec2 f = fract(UV * cells);
	vec3 tex = texture(albedo, UV).rgb;
	bool in_pane = all(greaterThan(f, pane_min)) && all(lessThan(f, pane_max));
	float h1 = hash2(cell + vec2(0.1, 0.1));
	float h2 = hash2(cell + vec2(7.3, 7.3));
	float h3 = hash2(cell + vec2(3.7, 3.7));
	float period = period_base + period_spread * h2;
	float flips = floor((clock + h3 * period) / period);
	bool base_lit = h1 < lit_share;
	bool flipped = mod(flips, 2.0) >= 1.0;
	bool lit = base_lit != flipped;
	vec3 col = tex;
	if (in_pane) {
		float warm = 0.8 + 0.4 * hash2(cell + vec2(11.1, 11.1));
		col = lit ? lit_color * warm : dark_color;
	}
	ALBEDO = col;
}
