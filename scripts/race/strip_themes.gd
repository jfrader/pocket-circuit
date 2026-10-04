extends RefCounted

const SURFACES := preload("res://scripts/race/household_surface_materials.gd")
const RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const MATERIALS := preload("res://scripts/race/generated_world_materials.gd")


static func second_theme(theme: StringName, requested: String = "") -> StringName:
	var themes: Array = SURFACES.catalog()["themes"].keys()
	if not requested.is_empty():
		return StringName(requested) if requested in themes else &""
	var index := themes.find(String(theme))
	return StringName(themes[(index + 1) % themes.size()]) if index >= 0 else &""


static func switch_arc(sections: Array, total: float) -> float:
	var best := total * 0.5
	var distance := INF
	for section: Dictionary in sections:
		if section["kind"] != "straight":
			continue
		var arc := (float(section["start_arc"]) + float(section["end_arc"])) * 0.5
		if absf(arc - total * 0.5) < distance:
			best = arc
			distance = absf(arc - total * 0.5)
	return best


static func spec_for(theme: StringName, source: Dictionary, base: Dictionary, kits: Array, inherit_material: bool) -> Dictionary:
	var spec := base.duplicate(true)
	for key in ["route_shape", "requested_seed", "seed", "seed_obstacles", "generation_fallback", "generation_attempt", "controls", "strip_sections", "length_tier", "material_seed", "dressing_seed", "obstacle_seed", "half_width"]:
		spec[key] = source[key]
	spec["material_id"] = source.get("material_id", "") if inherit_material else ""
	spec["palette_id"] = source.get("palette_id", "") if inherit_material else ""
	spec["environment_theme"] = theme
	spec["story_id"] = RULES.story_id(theme, int(spec["dressing_seed"]))
	spec["story_kit"] = (kits[RULES.story_index(theme, int(spec["dressing_seed"]))] as Dictionary).duplicate(true)
	spec["story_kit"]["id"] = spec["story_id"]
	MATERIALS.apply_to_spec(spec, MATERIALS.resolve(theme, spec["story_id"], int(spec["material_seed"]), spec["material_id"], spec["palette_id"]))
	var surface := SURFACES.resolve(theme, int(spec["material_seed"]), spec["material_id"], spec["palette_id"], spec.get("floor_modulate", Color.WHITE))
	spec["surface_identity"] = surface
	spec["floor_texture"] = surface["floor"]["texture"]
	spec["track_texture"] = surface["course"]["texture"]
	spec["floor_modulate"] = Color.WHITE
	return spec


static func room_half(room: PackedVector2Array, seam_y: float, north: bool) -> PackedVector2Array:
	var bounds := Rect2(room[0], Vector2.ZERO)
	for point in room:
		bounds = bounds.expand(point)
	var top := bounds.position.y if north else seam_y
	var bottom := seam_y if north else bounds.end.y
	var clip := PackedVector2Array([Vector2(bounds.position.x, top), Vector2(bounds.end.x, top), Vector2(bounds.end.x, bottom), Vector2(bounds.position.x, bottom)])
	var pieces := Geometry2D.intersect_polygons(room, clip)
	return pieces[0] if not pieces.is_empty() else PackedVector2Array()
