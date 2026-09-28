class_name HandmadeCourseMaterials
extends RefCounted

const SHADER := preload("res://assets/shaders/handmade_course.gdshader")
const CONSTRUCTION_NAME := "CourseConstruction"
const CONTRAST_LUMINANCE_OFFSET := 0.05
const SHADER_KEYS := ["base_color", "cut_color", "grain_period_mm", "grain_strength", "paint_period_mm", "paint_strength", "cut_period_mm", "cut_jitter_mm", "cut_band_mm", "cut_strength", "edge_aa_mm"]
static var _grains: Dictionary = {}


static func resolve(theme: StringName, seed_value: int, definition: Dictionary, settings: Dictionary, floor_profile: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%s:course-v%d:%d" % [theme, int(settings["version"]), seed_value]).hash()
	var candidates: Array[Dictionary] = []
	var best: Dictionary = definition["palettes"][0]
	var best_contrast := 0.0
	for palette: Dictionary in definition["palettes"]:
		var contrast := floor_contrast(Color(palette["base"]), floor_profile)
		if contrast > best_contrast:
			best = palette
			best_contrast = contrast
		if contrast >= float(settings["min_floor_contrast"]):
			candidates.append(palette)
	var chosen: Dictionary = best if candidates.is_empty() else candidates[rng.randi_range(0, candidates.size() - 1)]
	var result := settings.duplicate(true)
	result.merge({
		"id": chosen["id"],
		"kind": definition["kind"],
		"texture": definition["texture"],
		"base_color": Color(chosen["base"]),
		"cut_color": Color(chosen["cut"]),
		"tape_color": Color(chosen["tape"]),
		"grain_seed": rng.randi(),
		"detail_seed": rng.randi(),
		"contrast_safe": not candidates.is_empty(),
	}, true)
	for key: String in ["grain_frequency", "grain_period_mm", "cut_jitter_mm", "join_phase"]:
		result[key] = _range(rng, settings[key])
	result["grain_strength"] = _range(rng, definition["grain_strength"])
	result["join_count"] = rng.randi_range(int(settings["join_count"][0]), int(settings["join_count"][1]))
	for key: String in ["cut_band_mm", "edge_aa_mm", "shadow_offset_mm", "tape_size_mm"]:
		result[key] = Vector2(float(settings[key][0]), float(settings[key][1]))
	return result


static func floor_contrast(color: Color, floor_profile: Dictionary) -> float:
	var base: Color = floor_profile["base_color"]
	var alternate := base.lerp(floor_profile["alternate_color"], float(floor_profile["contrast"]))
	var lower := minf(base.srgb_to_linear().get_luminance(), alternate.srgb_to_linear().get_luminance())
	var upper := maxf(base.srgb_to_linear().get_luminance(), alternate.srgb_to_linear().get_luminance())
	var luminance := color.srgb_to_linear().get_luminance()
	var nearest := clampf(luminance, lower, upper)
	return (maxf(luminance, nearest) + CONTRAST_LUMINANCE_OFFSET) / (minf(luminance, nearest) + CONTRAST_LUMINANCE_OFFSET)


static func apply(track: Node2D, profile: Dictionary) -> ImageTexture:
	var surface := track.get_node_or_null("TrackSurface") as Line2D
	if surface == null:
		return null
	var grain := _grain(profile)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	for key: String in SHADER_KEYS:
		material.set_shader_parameter(key, profile[key])
	material.set_shader_parameter("grain_noise", grain)
	material.set_shader_parameter("width_mm", surface.width)
	surface.texture = load(profile["texture"]) as Texture2D
	surface.material = material
	surface.default_color = Color.WHITE
	surface.modulate = Color.WHITE
	surface.set_meta("material_profile", profile["id"])
	surface.set_meta("course_kind", profile["kind"])
	TrackBuilderCore._mark_flat_visual(surface, profile["texture"], &"track_surface")
	_build_construction(track, surface, profile)
	return grain


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


static func _build_construction(track: Node2D, surface: Line2D, profile: Dictionary) -> void:
	var previous := track.get_node_or_null(CONSTRUCTION_NAME)
	if previous:
		previous.free()
	var container := Node2D.new()
	container.name = CONSTRUCTION_NAME
	container.transform = surface.transform
	track.add_child(container)
	var shadow := _line(container, "ContactShadow", surface.points, surface.width + float(profile["shadow_extra_width_mm"]), Color(profile["shadow_color"]), surface.z_index - 1)
	shadow.closed = surface.closed
	shadow.position = profile["shadow_offset_mm"]
	var path := surface.points.duplicate()
	if surface.closed and path.size() > 1 and path[-1] != path[0]:
		path.append(path[0])
	var arc := TrackBuilderCore._arc_lengths(path)
	var total := arc[arc.size() - 1]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(profile["detail_seed"])
	var join_count := int(profile["join_count"])
	for index in join_count:
		var fraction := (float(index) + float(profile["join_phase"]) + rng.randf_range(-float(profile["join_jitter"]), float(profile["join_jitter"]))) / join_count
		var point := TrackBuilderCore._sample_at_arc(path, arc, fposmod(fraction, 1.0) * total)
		var tangent := TrackBuilderCore._tangent_at_arc(path, arc, fposmod(fraction, 1.0) * total)
		var normal := tangent.rotated(PI * 0.5)
		var inset := (profile["cut_band_mm"] as Vector2).y
		var seam_color: Color = profile["cut_color"]
		seam_color.a = float(profile["seam_alpha"])
		_line(container, "Join%d" % index, PackedVector2Array([point - normal * (surface.width * 0.5 - inset), point + normal * (surface.width * 0.5 - inset)]), float(profile["seam_width_mm"]), seam_color, surface.z_index + 1)
		for side in [-1, 1]:
			var tape := Polygon2D.new()
			tape.name = "Tape%d%s" % [index, "Left" if side < 0 else "Right"]
			tape.position = point + normal * (surface.width * 0.5 - float(profile["tape_edge_inset_mm"])) * side
			tape.rotation = tangent.angle() + _range(rng, profile["tape_angle_range"])
			tape.polygon = TrackBuilderCore._rect_points(Vector2.ZERO, profile["tape_size_mm"])
			tape.color = profile["tape_color"]
			tape.color.a = float(profile["tape_alpha"])
			tape.z_index = surface.z_index + 1
			tape.antialiased = true
			TrackBuilderCore._mark_flat_visual(tape, "", &"course_construction")
			container.add_child(tape)


static func _line(parent: Node, node_name: String, points: PackedVector2Array, width: float, color: Color, z_index: int) -> Line2D:
	var line := Line2D.new()
	line.name = node_name
	line.points = points
	line.width = width
	line.default_color = color
	line.z_index = z_index
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.antialiased = true
	TrackBuilderCore._mark_flat_visual(line, "", &"course_construction")
	parent.add_child(line)
	return line


static func _range(rng: RandomNumberGenerator, values: Array) -> float:
	return rng.randf_range(float(values[0]), float(values[1]))
