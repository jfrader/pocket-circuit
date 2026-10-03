shader_type canvas_item;
render_mode unshaded;

#include "res://assets/shaders/household_surface.gdshaderinc"
varying vec2 room_point;
varying vec4 item_tint;

void vertex() {
	room_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	item_tint = COLOR;
}

void fragment() {
	float seam;
	vec3 color = household_surface(room_point, seam);
	COLOR = vec4(color * item_tint.rgb, item_tint.a);
}
