// The upright cabinets' screens: the design's one 32 x 24 attract loop in 120 ms
// steps, stars falling past a weaving ship, tinted per cabinet by vertex colour.
// The time work happens per vertex; a pixel only compares its own cell. Each row
// holds at most one star (7 is invertible mod 24), so no loop.
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

uniform float rate = 1.0;   // 0 = still (the PiP's frozen cage)

varying flat vec4 frame;   // rows scrolled, columns scrolled, ship's x, blink

void vertex() {
	float tt = floor(TIME * rate / 0.12) * 0.12;
	frame = vec4(mod(floor(tt * 6.0), 24.0), mod(floor(tt * 3.0), 30.0),
			16.0 + round(sin(tt * 1.3) * 10.0), mod(floor(tt * 2.0), 2.0));
}

void fragment() {
	vec2 p = floor(UV * vec2(32.0, 24.0));
	float star = mod(7.0 * (p.y - frame.x), 24.0);
	float sx = mod(star * 11.0 + frame.y, 30.0);
	bool ink = star < 8.5 && p.x >= sx && p.x < sx + 2.0;
	ink = ink || (p.y >= 19.0 && p.y < 21.0 && p.x >= frame.z - 2.0 && p.x < frame.z + 3.0);
	ink = ink || (p.y == 18.0 && p.x == frame.z);
	ink = ink || (frame.w > 0.5 && p.y == 3.0 && p.x >= 12.0 && p.x < 20.0);
	ALBEDO = COLOR.rgb * (ink ? vec3(1.0) : vec3(0.00152, 0.00182, 0.00304));   // #05060A
}
