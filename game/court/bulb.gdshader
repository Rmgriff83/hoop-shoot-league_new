// Runner lights around the top of the arcade hall: a bright head with a short
// comet tail chases around the loop. All bulbs share ONE material so they still
// batch; each knows only its ordinal along the path, as an instance uniform.
shader_type spatial;
render_mode unshaded;

uniform float t = 0.0;
uniform float flare = 0.0;                        // brief run-wide lift on heat-up
uniform float count = 60.0;                       // bulbs in the loop
uniform float speed = 11.0;                       // bulbs per second
uniform float tail = 9.0;                         // how many trail behind the head
uniform vec3 warm : source_color = vec3(1.0, 0.81, 0.55);
instance uniform float bulb_index = 0.0;

void fragment() {
	// Distance BEHIND the running head, wrapped around the loop.
	float head = mod(t * speed, count);
	float d = mod(bulb_index - head + count, count);
	float lit = smoothstep(tail, 0.0, d);
	float b = clamp(0.34 + 1.10 * lit + flare, 0.0, 2.0);
	ALBEDO = warm * b;
	EMISSION = warm * b * 0.9;
}
