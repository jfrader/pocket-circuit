shader_type canvas_item;
render_mode unshaded;
uniform vec2 boundary[64];
uniform int boundary_count = 0;
uniform float feather_mm = 18.0;
varying vec2 room_point;
varying vec4 item_tint;
void vertex() {
	room_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	item_tint = COLOR;
}
void fragment() {
	float edge_distance = 100000.0;
	bool inside = false;
	for (int i = 0; i < 64; i++) {
		if (i >= boundary_count) { break; }
		vec2 a = boundary[i];
		vec2 b = boundary[(i + 1) % boundary_count];
		vec2 segment = b - a;
		float t = clamp(dot(room_point - a, segment) / max(dot(segment, segment), 0.0001), 0.0, 1.0);
		edge_distance = min(edge_distance, length(room_point - (a + segment * t)));
		if ((a.y > room_point.y) != (b.y > room_point.y)) {
			if (room_point.x < (b.x - a.x) * (room_point.y - a.y) / (b.y - a.y) + a.x) { inside = !inside; }
		}
	}
	float fade = inside ? smoothstep(0.0, feather_mm, edge_distance) : 0.0;
	vec4 paint = texture(TEXTURE, UV) * item_tint;
	COLOR = vec4(paint.rgb, paint.a * fade);
}
