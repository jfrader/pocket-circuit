shader_type canvas_item;

uniform vec2 tile_world_size = vec2(1024.0);
uniform float edge_feather : hint_range(0.0, 0.49) = 0.16;
varying vec2 surface_uv;
varying vec4 surface_tint;

void vertex() {
	surface_uv = VERTEX / tile_world_size;
	surface_tint = COLOR;
}

void fragment() {
	float feather = max(edge_feather, 0.001);
	float edge = smoothstep(0.0, feather, UV.y) * smoothstep(0.0, feather, 1.0 - UV.y);
	vec4 material = texture(TEXTURE, surface_uv);
	COLOR = vec4(material.rgb * surface_tint.rgb, material.a * surface_tint.a * edge);
}
