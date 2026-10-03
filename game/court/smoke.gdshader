// A rooftop smoke puff: a camera-facing quad with the soft blob texture
// (assets/textures/city_smoke.png), tinted and faded by CityFx as it rises.
shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix, depth_draw_never;

uniform sampler2D puff : source_color, filter_linear, repeat_disable;
uniform vec3 tint : source_color = vec3(0.78, 0.78, 0.8);
uniform float alpha = 0.4;

void vertex() {
	// Camera-facing, keeping the node's scale (CityFx grows a puff by scaling it).
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz * s, 0.0), vec4(INV_VIEW_MATRIX[1].xyz * s, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz * s, 0.0), MODEL_MATRIX[3]);
}

void fragment() {
	vec4 s = texture(puff, UV);
	ALBEDO = tint;
	ALPHA = s.a * alpha;
}
