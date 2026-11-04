shader_type canvas_item;
// A shop card above the player's level (design "Home League Context v2"):
// CSS grayscale(1) brightness(.6) over the art and its ink shadow, in the
// same space the design filters in, so the numbers carry over.
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
const float BRIGHTNESS = 0.6;

void fragment() {
	// COLOR already carries the texture here.
	COLOR.rgb = vec3(dot(COLOR.rgb, LUMA) * BRIGHTNESS);
}
