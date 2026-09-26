// Arcade cabinet "attract mode": a scanlined CRT running one of four tiny
// procedural games, picked by `game` (0 paddle & ball, 1 falling blocks,
// 2 starfield with a ship, 3 maze dot-eater). Unshaded, tinted by `palette`,
// with a faint flicker. Driven by `t` (+ per-cabinet `phase`).
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

uniform float t = 0.0;
uniform float phase = 0.0;
uniform float game = 0.0;
uniform vec3 palette : source_color = vec3(1.0, 0.75, 0.3);
uniform float brightness = 1.6;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float tri(float x) {
	return abs(fract(x) * 2.0 - 1.0);
}

float box(vec2 uv, vec2 c, vec2 h) {
	vec2 d = abs(uv - c) - h;
	return step(max(d.x, d.y), 0.0);
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);   // glTF flips V; make v go up
	float tt = t + phase;
	float g = mod(floor(game + 0.5), 4.0);
	float ink = 0.0;
	float bg = 0.06;
	if (g < 0.5) {
		// Paddle & ball: the ball bounces around, both paddles chase it.
		vec2 ball = vec2(tri(tt * 0.31), tri(tt * 0.47 + 0.2));
		ink += box(uv, ball, vec2(0.03));
		ink += box(uv, vec2(0.06, ball.y + 0.08 * sin(tt * 3.0)), vec2(0.015, 0.11));
		ink += box(uv, vec2(0.94, tri(tt * 0.29 + 0.5)), vec2(0.015, 0.11));
		ink += step(abs(uv.x - 0.5), 0.006) * step(0.5, fract(uv.y * 8.0));   // dashed net
	} else if (g < 1.5) {
		// Falling blocks: a settled pile at the bottom plus one piece dropping.
		vec2 cell = floor(uv * vec2(10.0, 16.0));
		float pile = step(cell.y, 5.0 + 3.0 * hash21(cell.xx + floor(tt * 0.2))) * step(0.35, hash21(cell + floor(tt * 0.2)));
		ink += pile;
		float dropy = 15.0 - mod(tt * 4.0, 12.0);
		float col = floor(3.0 + 4.0 * hash21(vec2(floor(tt * 4.0 / 12.0), 7.0)));
		ink += step(abs(cell.x - col), 1.0) * step(abs(cell.y - floor(dropy)), 0.5);
		ink += step(cell.x - col, 0.0) * step(col - 1.0, cell.x) * step(abs(cell.y - floor(dropy) - 1.0), 0.5);
		bg = 0.04;
	} else if (g < 2.5) {
		// Starfield + ship: stars stream downward, the ship weaves and fires.
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			vec2 suv = vec2(uv.x, fract(uv.y + tt * (0.15 + 0.12 * fi)));
			vec2 sc = floor(suv * (10.0 + 6.0 * fi));
			ink += 0.35 * step(0.93, hash21(sc + fi * 17.0)) * step(0.85, hash21(sc * 1.7 + fi));
		}
		float sx = 0.5 + 0.3 * sin(tt * 0.9);
		ink += box(uv, vec2(sx, 0.12), vec2(0.06, 0.02)) + box(uv, vec2(sx, 0.16), vec2(0.02, 0.03));
		float shot = fract(tt * 1.3);
		ink += box(uv, vec2(sx, 0.2 + shot * 0.8), vec2(0.008, 0.03));
		bg = 0.02;
	} else {
		// Maze dot-eater: a grid of dots, corridors, a wandering muncher.
		vec2 cell = floor(uv * vec2(9.0, 7.0));
		vec2 cuv = fract(uv * vec2(9.0, 7.0));
		float wall = step(0.75, hash21(cell * 3.1 + 5.0)) * step(0.5, mod(cell.x + cell.y, 2.0));
		ink += wall * 0.7;
		float eaten = step(hash21(cell + 2.0), fract(tt * 0.05));
		ink += (1.0 - wall) * (1.0 - eaten) * box(cuv, vec2(0.5), vec2(0.1));
		vec2 pm = vec2(4.0 + 3.5 * sin(tt * 0.7), 3.0 + 2.5 * sin(tt * 0.5 + 1.0));
		float mouth = step(0.35, fract(tt * 3.0));
		ink += step(length((uv * vec2(9.0, 7.0)) - pm), 0.42) * (1.0 - 0.5 * mouth * step(abs(atan(uv.y * 7.0 - pm.y, uv.x * 9.0 - pm.x)), 0.5));
		bg = 0.05;
	}
	ink = clamp(ink, 0.0, 1.0);
	// CRT: scanlines, vignette, a little flicker.
	float scan = 0.82 + 0.18 * step(0.5, fract(uv.y * 40.0));
	float vig = 1.0 - 0.55 * pow(length(uv - 0.5) * 1.35, 2.5);
	float flick = 0.94 + 0.06 * sin(tt * 37.0 + phase * 3.0);
	vec3 col = palette * (bg + ink) * scan * vig * flick * brightness;
	ALBEDO = col;
	EMISSION = col * 0.6;
}
