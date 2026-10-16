// Falling snow for the park (game/view/park_fx.gd): one points mesh whose
// vertices are seeds in 0..1; every flake's motion runs here from TIME —
// it falls at its own speed, sways, and wraps inside a box that follows
// the camera, so nothing is ever spawned or freed. Unshaded, no texture,
// opaque squares: no sorting, no blending. Never touches the sim.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform vec3 box = vec3(14.0, 9.0, 14.0);
uniform vec3 center = vec3(0.0, 4.0, 0.0);
uniform float px_scale = 1.0;
uniform vec3 colour : source_color = vec3(0.97, 0.98, 1.0);

void vertex() {
	vec3 s = VERTEX;
	float speed = 0.45 + s.x * 0.35;
	vec3 p = s * box;
	p.y -= TIME * speed;
	p.x += sin(TIME * 0.7 + s.z * 31.0) * 0.18;
	p.z += cos(TIME * 0.5 + s.x * 17.0) * 0.12;
	vec3 lo = center - box * 0.5;
	p = lo + mod(p - lo, box);
	VERTEX = p;
	vec4 mv = MODELVIEW_MATRIX * vec4(p, 1.0);
	POINT_SIZE = clamp(floor(px_scale * (0.9 + s.y) * 6.0 / max(-mv.z, 0.5)), 1.0, 4.0 * px_scale);
}

void fragment() {
	ALBEDO = colour;
}
