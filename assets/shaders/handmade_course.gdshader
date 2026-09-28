shader_type canvas_item;
render_mode unshaded;

#include "res://assets/shaders/household_surface.gdshaderinc"

uniform vec4 pigment_color : source_color;
uniform vec4 edge_color : source_color;
uniform sampler2D grain_noise : repeat_enable, filter_linear_mipmap;
uniform float paint_opacity;
uniform float brush_min_coverage;
uniform float brush_cross_repeat;
uniform float brush_repeats;
uniform float brush_phase;
uniform float width_mm;
uniform float edge_inset_mm;
uniform float edge_width_mm;
uniform float edge_opacity;
uniform float edge_roughness_mm;
uniform float edge_feather_mm;
varying vec2 world_point;
varying vec4 item_tint;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	item_tint = COLOR;
}

void fragment() {
	float seam;
	vec3 substrate = household_surface(world_point, seam);
	vec3 detail = substrate / max(base_color.rgb, vec3(0.001));
	float edge = min(UV.y, 1.0 - UV.y);
	float edge_mm = edge * width_mm;
	float along = UV.x * brush_repeats + brush_phase;
	float bristles = texture(grain_noise, vec2(along, UV.y * brush_cross_repeat)).r;
	float brush_edge = texture(grain_noise, vec2(along * 4.0, UV.y * 0.3)).r;
	float coverage = mix(brush_min_coverage, 1.0, smoothstep(0.2, 0.72, bristles));
	float ragged = smoothstep(brush_edge * edge_roughness_mm, brush_edge * edge_roughness_mm + edge_feather_mm, edge_mm);
	vec3 painted = mix(substrate, pigment_color.rgb * detail, paint_opacity * coverage * ragged);
	float brush_offset = (brush_edge - 0.5) * edge_roughness_mm;
	float marking = surface_stroke(abs(edge_mm - edge_inset_mm - brush_offset), edge_width_mm * mix(0.4, 0.6, brush_edge));
	float marking_coverage = marking * mix(0.72, 1.0, bristles) * (1.0 - seam * 0.25);
	painted = mix(painted, edge_color.rgb * detail, marking_coverage * edge_opacity * paint_opacity);
	float alpha = smoothstep(0.0, max(fwidth(edge), edge_feather_mm / width_mm), edge);
	COLOR = vec4(painted * item_tint.rgb, item_tint.a * alpha);
}
