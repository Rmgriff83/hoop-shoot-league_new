// A gull in flight: camera-facing quad playing the 4-frame flap sheet
// (assets/textures/beach_bird.png), dark silhouette with alpha cut-out.
shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_opaque;

uniform sampler2D sheet : source_color, filter_nearest, repeat_disable;
uniform float t = 0.0;
uniform float phase = 0.0;
uniform float flap_hz = 3.2;
uniform float frames = 4.0;
uniform float facing = 1.0;   // +1 flies toward +z, -1 toward -z (mirrors the sprite)

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz, 0.0), vec4(INV_VIEW_MATRIX[1].xyz, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz, 0.0), MODEL_MATRIX[3]);
}

void fragment() {
	float f = mod(floor((t * flap_hz + phase) * frames), frames);
	float u = facing > 0.0 ? UV.x : 1.0 - UV.x;
	vec4 s = texture(sheet, vec2((f + u) / frames, UV.y));
	ALBEDO = s.rgb;
	ALPHA = s.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
