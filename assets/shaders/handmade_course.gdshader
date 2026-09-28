shader_type canvas_item;
render_mode unshaded;

uniform vec4 base_color : source_color;
uniform vec4 cut_color : source_color;
uniform sampler2D grain_noise : repeat_enable, filter_linear_mipmap;
uniform float width_mm;
uniform float grain_period_mm;
uniform float grain_strength;
uniform float paint_period_mm;
uniform float paint_strength;
uniform float cut_period_mm;
uniform float cut_jitter_mm;
uniform vec2 cut_band_mm;
uniform float cut_strength;
uniform vec2 edge_aa_mm;
varying vec2 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float grain = texture(grain_noise, world_point / grain_period_mm).r - 0.5;
	vec2 paint_uv = world_point / paint_period_mm;
	vec3 paint = texture(TEXTURE, paint_uv).rgb - texture(TEXTURE, paint_uv + vec2(0.137, 0.271)).rgb;
	float edge_distance = min(UV.y, 1.0 - UV.y) * width_mm;
	float rough_cut = texture(grain_noise, world_point / cut_period_mm).r * cut_jitter_mm;
	float cut = 1.0 - smoothstep(cut_band_mm.x, cut_band_mm.y, edge_distance - rough_cut);
	vec3 color = base_color.rgb * (1.0 + grain * grain_strength + dot(paint, vec3(0.2126, 0.7152, 0.0722)) * paint_strength);
	color = mix(color, cut_color.rgb, cut * cut_strength);
	float aa = max(fwidth(edge_distance), edge_aa_mm.y - edge_aa_mm.x);
	float alpha = smoothstep(edge_aa_mm.x, edge_aa_mm.x + aa, edge_distance - rough_cut);
	COLOR = vec4(color, alpha);
}
