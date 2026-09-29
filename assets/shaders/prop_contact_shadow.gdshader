shader_type canvas_item;
render_mode unshaded;

uniform float softness_mm;
varying vec2 softness_uv;
varying vec4 shadow_tint;

void vertex() {
	shadow_tint = COLOR;
	vec2 world_scale = vec2(length(MODEL_MATRIX[0].xy), length(MODEL_MATRIX[1].xy));
	softness_uv = TEXTURE_PIXEL_SIZE * softness_mm / max(world_scale, vec2(0.0001));
}

void fragment() {
	float alpha = texture(TEXTURE, UV).a * 0.25;
	alpha += texture(TEXTURE, UV + vec2(softness_uv.x, 0.0)).a * 0.125;
	alpha += texture(TEXTURE, UV - vec2(softness_uv.x, 0.0)).a * 0.125;
	alpha += texture(TEXTURE, UV + vec2(0.0, softness_uv.y)).a * 0.125;
	alpha += texture(TEXTURE, UV - vec2(0.0, softness_uv.y)).a * 0.125;
	alpha += texture(TEXTURE, UV + softness_uv).a * 0.0625;
	alpha += texture(TEXTURE, UV - softness_uv).a * 0.0625;
	alpha += texture(TEXTURE, UV + vec2(softness_uv.x, -softness_uv.y)).a * 0.0625;
	alpha += texture(TEXTURE, UV + vec2(-softness_uv.x, softness_uv.y)).a * 0.0625;
	COLOR = vec4(shadow_tint.rgb, shadow_tint.a * alpha);
}
