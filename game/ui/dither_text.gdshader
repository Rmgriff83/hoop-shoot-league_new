shader_type canvas_item;
// A dithered drop shadow behind a Label (docs/HOME.md, RetroTheme.dithered):
// the Label's shadow pass is the only pass drawn with a translucent colour,
// so those fragments keep one square of a CELL-px checkerboard (in design
// px, from the item's canvas transform) and drop the other, while the face
// and its ink outline draw solid.
uniform float cell = 3.0;
varying vec2 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 col = texture(TEXTURE, UV) * COLOR;
	if (COLOR.a < 0.9) {
		vec2 c = floor(wp / cell);
		if (mod(c.x + c.y, 2.0) > 0.5) {
			discard;
		}
	}
	COLOR = col;
}
