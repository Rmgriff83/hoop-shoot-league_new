// One puff of smoke: a camera-facing quad playing the 4 x 4 one-shot flipbook
// rendered by tools/blender/render_smoke_flipbook.py (frame 0 top-left), with a
// crossfade between frames, a slow rise and a gentle swell. `age` is seconds
// since this puff started (negative = not yet); past `duration` it is gone.
shader_type spatial;
render_mode cull_disabled, unshaded, blend_mix, depth_draw_never, fog_disabled;

uniform sampler2D sheet : source_color, filter_linear_mipmap, repeat_disable;
uniform float age = -1.0;
uniform float duration = 1.5;
uniform float flip = 1.0;        // -1 mirrors the puff so neighbours differ
uniform float opacity = 0.9;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float cols = 4.0;
uniform float rows = 4.0;

void vertex() {
	float k = clamp(age / duration, 0.0, 1.0);
	vec3 v = VERTEX * (0.75 + 0.55 * k);
	v.y += 0.22 * k;
	// Billboard: keep the quad facing the camera, keep the node's position.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		vec4(INV_VIEW_MATRIX[0].xyz, 0.0), vec4(INV_VIEW_MATRIX[1].xyz, 0.0),
		vec4(INV_VIEW_MATRIX[2].xyz, 0.0), MODEL_MATRIX[3]);
	VERTEX = v;
}

vec4 frame(float fi, vec2 uv) {
	float c = mod(fi, cols);
	float r = floor(fi / cols);
	return texture(sheet, vec2((c + uv.x) / cols, (r + uv.y) / rows));
}

void fragment() {
	float frames = cols * rows;
	float k = clamp(age / duration, 0.0, 1.0);
	float f = k * (frames - 1.0);
	float f0 = floor(f);
	float f1 = min(f0 + 1.0, frames - 1.0);
	vec2 uv = vec2(flip < 0.0 ? 1.0 - UV.x : UV.x, UV.y);
	vec4 s = mix(frame(f0, uv), frame(f1, uv), f - f0);
	float on = (age >= 0.0 && age <= duration) ? 1.0 : 0.0;
	ALBEDO = s.rgb * tint.rgb;
	ALPHA = s.a * opacity * on;
}
