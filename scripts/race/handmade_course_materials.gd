class_name HandmadeCourseMaterials
extends RefCounted

const SHADER := preload("res://assets/shaders/handmade_course.gdshader")
const CONTRAST_LUMINANCE_OFFSET := 0.05
const COLOR_DIVISION_EPSILON := 0.001
const SHADER_KEYS := ["pigment_color", "edge_color", "paint_opacity", "brush_min_coverage", "brush_cross_repeat", "brush_phase", "edge_inset_mm", "edge_width_mm", "edge_opacity", "edge_roughness_mm", "edge_feather_mm"]
static var _grains: Dictionary = {}


static func resolve(theme: StringName, seed_value: int, definition: Dictionary, settings: Dictionary, neighboring_surfaces: Array[Dictionary]) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s:course-v%d:%d" % [theme, int(settings["version"]), seed_value]).hash()
	var candidates: Array[Dictionary] = []
	var best: Dictionary = {}
	var best_contrast := 0.0
	for palette: Dictionary in definition["palettes"]:
		for opacity: float in settings["opacity_steps"]:
			var candidate := {"id":palette["id"], "pigment_color":Color(palette["pigment"]), "edge_color":Color(palette["edge"]), "paint_opacity":opacity, "brush_min_coverage":float(settings["brush_min_coverage"])}
			var minimum := INF
			for neighbor: Dictionary in neighboring_surfaces:
				minimum = minf(minimum, course_contrast(candidate, neighboring_surfaces[0], neighbor))
			if minimum > best_contrast:
				best = candidate
				best_contrast = minimum
			if minimum >= float(settings["min_surface_contrast"]):
				candidates.append(candidate)
				break
	var chosen: Dictionary = best if candidates.is_empty() else candidates[rng.randi_range(0, candidates.size() - 1)]
	var result := settings.duplicate(true)
	result.merge(chosen, true)
	result.merge({
		"kind": definition["kind"],
		"texture": neighboring_surfaces[0]["texture"],
		"grain_seed": rng.randi(),
		"brush_phase": rng.randf(),
		"contrast_safe": not candidates.is_empty(),
	}, true)
	for key: String in ["grain_frequency", "brush_period_mm", "edge_width_mm"]:
		result[key] = rng.randf_range(float(settings[key][0]), float(settings[key][1]))
	return result


static func course_contrast(course: Dictionary, floor_profile: Dictionary, neighbor: Dictionary) -> float:
	var neighboring := _surface_luminance_range(neighbor)
	var result := INF
	for linear_space: bool in [false, true]:
		var painted := _paint_luminance_range(course, floor_profile, linear_space)
		var ratio := 1.0
		if painted.y < neighboring.x:
			ratio = (neighboring.x + CONTRAST_LUMINANCE_OFFSET) / (painted.y + CONTRAST_LUMINANCE_OFFSET)
		elif neighboring.y < painted.x:
			ratio = (painted.x + CONTRAST_LUMINANCE_OFFSET) / (neighboring.y + CONTRAST_LUMINANCE_OFFSET)
		result = minf(result, ratio)
	return result


static func _profile_colors(profile: Dictionary) -> Array[Color]:
	var base: Color = profile["base_color"]
	var alternate: Color = profile["alternate_color"]
	var weight := float(profile["contrast"])
	return [base, base.lerp(alternate, weight), base.srgb_to_linear().lerp(alternate.srgb_to_linear(), weight).linear_to_srgb()]


static func _surface_luminance_range(profile: Dictionary) -> Vector2:
	var result := Vector2(INF, -INF)
	for color: Color in _profile_colors(profile):
		var luminance := color.srgb_to_linear().get_luminance()
		result.x = minf(result.x, luminance)
		result.y = maxf(result.y, luminance)
	return result


static func _paint_luminance_range(course: Dictionary, floor_profile: Dictionary, linear_space: bool) -> Vector2:
	var result := Vector2(INF, -INF)
	var base: Color = floor_profile["base_color"]
	var pigment: Color = course["pigment_color"]
	if linear_space:
		base = base.srgb_to_linear()
		pigment = pigment.srgb_to_linear()
	for substrate: Color in _profile_colors(floor_profile):
		if linear_space:
			substrate = substrate.srgb_to_linear()
		var coated := Color(
			pigment.r * substrate.r / maxf(base.r, COLOR_DIVISION_EPSILON),
			pigment.g * substrate.g / maxf(base.g, COLOR_DIVISION_EPSILON),
			pigment.b * substrate.b / maxf(base.b, COLOR_DIVISION_EPSILON)
		)
		for coverage: float in [float(course["brush_min_coverage"]), 1.0]:
			var color := substrate.lerp(coated, float(course["paint_opacity"]) * coverage)
			var luminance := color.get_luminance() if linear_space else color.srgb_to_linear().get_luminance()
			result.x = minf(result.x, luminance)
			result.y = maxf(result.y, luminance)
	return result


static func apply(track: Node2D, profile: Dictionary, substrate_material: ShaderMaterial) -> ImageTexture:
	var surface := track.get_node_or_null("TrackSurface") as Line2D
	if surface == null:
		return null
	var grain := _grain(profile)
	var material := substrate_material.duplicate() as ShaderMaterial
	material.shader = SHADER
	for key: String in SHADER_KEYS:
		material.set_shader_parameter(key, profile[key])
	material.set_shader_parameter("grain_noise", grain)
	material.set_shader_parameter("width_mm", surface.width)
	var length := _path_length(surface)
	material.set_shader_parameter("brush_repeats", maxf(1.0, roundf(length / float(profile["brush_period_mm"]))))
	surface.texture = load(profile["texture"]) as Texture2D
	surface.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	surface.material = material
	surface.default_color = Color.WHITE
	surface.modulate = Color.WHITE
	surface.set_meta("material_profile", profile["id"])
	surface.set_meta("course_kind", profile["kind"])
	TrackBuilderCore._mark_flat_visual(surface, profile["texture"], &"track_surface")
	return grain


static func _path_length(surface: Line2D) -> float:
	if surface.points.size() < 2:
		return 0.0
	var arc := TrackBuilderCore._arc_lengths(surface.points)
	var result := arc[-1]
	if surface.closed:
		result += surface.points[-1].distance_to(surface.points[0])
	return result


static func _grain(profile: Dictionary) -> ImageTexture:
	var key := str([profile["grain_seed"], profile["grain_frequency"], profile["grain_texture_size"], profile["grain_octaves"], profile["grain_blend_skirt"]])
	if _grains.has(key):
		return _grains[key]
	var noise := FastNoiseLite.new()
	noise.seed = int(profile["grain_seed"])
	noise.frequency = float(profile["grain_frequency"])
	noise.fractal_octaves = int(profile["grain_octaves"])
	var size := int(profile["grain_texture_size"])
	var image := noise.get_seamless_image(size, size, false, false, float(profile["grain_blend_skirt"]))
	image.generate_mipmaps()
	var grain := ImageTexture.create_from_image(image)
	while _grains.size() >= int(profile["grain_cache_limit"]):
		_grains.erase(_grains.keys()[0])
	_grains[key] = grain
	return grain
