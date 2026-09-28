uniform vec4 base_color : source_color = vec4(0.7, 0.6, 0.4, 1.0);
uniform vec4 alternate_color : source_color = vec4(0.6, 0.5, 0.3, 1.0);
uniform vec4 seam_color : source_color = vec4(0.4, 0.3, 0.2, 1.0);
uniform int pattern = 0;
uniform vec2 cell_mm = vec2(200.0);
uniform vec2 phase_mm = vec2(0.0);
uniform float angle = 0.0;
uniform float line_mm = 1.0;
uniform float contrast = 0.1;
uniform float stagger = 0.5;
uniform float grain_strength = 0.18;
uniform float grain_period = 430.0;
uniform sampler2D surface_grain : source_color, repeat_enable, filter_linear_mipmap;

float surface_stroke(float distance_mm, float width_mm) {
	float aa = max(fwidth(distance_mm), 0.35);
	return 1.0 - smoothstep(width_mm - aa, width_mm + aa, distance_mm);
}

vec3 household_surface(vec2 world_point, out float seam) {
	float c = cos(angle);
	float s = sin(angle);
	vec2 p = mat2(vec2(c, -s), vec2(s, c)) * world_point + phase_mm;
	vec2 grid = p / cell_mm;
	vec2 cell_id = floor(grid);
	vec2 inside = fract(grid);
	float mask = 0.0;
	seam = 0.0;
	if (pattern == 1 || pattern == 6) {
		mask = mod(cell_id.x + cell_id.y, 2.0);
		vec2 edge = min(inside, 1.0 - inside) * cell_mm;
		seam = surface_stroke(min(edge.x, edge.y), line_mm);
	} else if (pattern == 2) {
		grid.x += cell_id.y * stagger;
		inside = fract(grid);
		mask = 0.5 + 0.5 * sin(cell_id.y * 2.13 + phase_mm.x * 0.01);
		vec2 edge = min(inside, 1.0 - inside) * cell_mm;
		seam = surface_stroke(min(edge.x, edge.y), line_mm);
	} else if (pattern == 3) {
		vec2 edge = min(inside, 1.0 - inside) * cell_mm;
		vec2 major = abs(mod(p + cell_mm * 2.5, cell_mm * 5.0) - cell_mm * 2.5);
		seam = max(surface_stroke(min(edge.x, edge.y), line_mm) * 0.35, surface_stroke(min(major.x, major.y), line_mm * 1.3));
	} else if (pattern == 4) {
		mask = 0.5 + 0.5 * sin(grid.x * 6.283185) * sin(grid.y * 6.283185);
	} else if (pattern == 5) {
		float band = mod(cell_id.y, 2.0) < 1.0 ? grid.x + inside.y : grid.x - inside.y;
		mask = mod(floor(band), 2.0);
		float joint = min(fract(band), 1.0 - fract(band)) * cell_mm.x;
		seam = surface_stroke(joint, line_mm) * 0.6;
	} else if (pattern == 7) {
		mask = 0.5 + 0.5 * cos(grid.x * 6.283185);
	}
	vec2 grain_uv = p / grain_period;
	vec3 grain_a = texture(surface_grain, grain_uv).rgb;
	vec3 grain_b = texture(surface_grain, grain_uv + vec2(0.137, 0.271)).rgb;
	float grain = dot(grain_a - grain_b, vec3(0.2126, 0.7152, 0.0722));
	vec3 color = mix(base_color.rgb, alternate_color.rgb, mask * contrast);
	color = mix(color, seam_color.rgb, seam * (pattern == 3 ? contrast : 0.5));
	return color * (1.0 + grain * grain_strength);
}
