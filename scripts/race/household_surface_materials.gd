class_name HouseholdSurfaceMaterials
extends RefCounted

const CATALOG_PATH := "res://data/household_material_patterns.json"
const SURFACE_SHADER := preload("res://assets/shaders/household_surface.gdshader")
const COURSE := preload("res://scripts/race/handmade_course_materials.gd")
static var _catalog: Dictionary = {}


static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	return _catalog


static func resolve(theme: StringName, material_seed: int, family: String = "", palette: String = "", tint: Color = Color.WHITE) -> Dictionary:
	var data := catalog()
	var definition: Dictionary = data["themes"][String(theme)]
	var result := {"version": int(data["version"]), "theme": String(theme), "seed": material_seed,"family":family,"palette":palette}
	for role: String in ["floor", "island"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = ("%s:surface-v%d:%s:%d:%s:%s" % [theme, int(data["version"]), role, material_seed, family, palette]).hash()
		var pool: Array = definition[role].duplicate()
		if role == "floor" and data["families"].has(family):
			pool = pool.filter(func(profile: Dictionary) -> bool: return profile["id"] in data["families"][family])
		var profile: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		var dimensions: Array = profile["cell_mm"]
		var angles: Array = profile["angles"]
		result[role] = {
			"id": String(profile["id"]), "pattern": int(data["patterns"][profile["pattern"]]),
			"base_color": Color(profile["colors"][0]) * tint, "alternate_color": Color(profile["colors"][1]) * tint, "seam_color": Color(profile["colors"][2]) * tint,
			"cell_mm": Vector2(_range(rng, dimensions[0]), _range(rng, dimensions[1])),
			"line_mm": _range(rng, profile["line_mm"]), "contrast": _range(rng, profile["contrast"]),
			"angle": deg_to_rad(float(angles[rng.randi_range(0, angles.size() - 1)])),
			"phase_mm": Vector2(rng.randf_range(-900.0, 900.0), rng.randf_range(-900.0, 900.0)),
			"stagger": rng.randf_range(0.25, 0.75), "grain_period": rng.randf_range(310.0, 620.0),
			"texture": String(definition["grain_" + role]),
		}
	result["course"] = COURSE.resolve(theme, material_seed, definition["course"], data["course_settings"], [result["floor"], result["island"]])
	result["signature"] = var_to_str(result).sha256_text()
	return result


static func apply(track: Node2D, resolved: Dictionary) -> ImageTexture:
	var floor_material := _material(resolved["floor"])
	var island_material := _material(resolved["island"])
	for node: Node in track.find_children("*", "CanvasItem", true, false):
		if node.name == "RoomSurface":
			_paint(node, resolved["floor"], floor_material)
		elif node.name in ["IslandProp", "RaisedPad"]:
			_paint(node, resolved["island"], island_material)
		elif node.name == "TexturedRim" and node is Line2D:
			node.texture = null
			node.default_color = (resolved["island"]["base_color"] as Color).darkened(0.15)
		elif node.name == "SideFace" and node is Line2D:
			node.default_color = (resolved["island"]["base_color"] as Color).darkened(0.3)
		elif node.name == "TopLip" and node is Line2D:
			node.default_color = (resolved["island"]["base_color"] as Color).lightened(0.2)
	track.set_meta("surface_identity", resolved.duplicate(true))
	return COURSE.apply(track, resolved["course"], floor_material)


static func _paint(node: CanvasItem, profile: Dictionary, material: ShaderMaterial) -> void:
	node.material = material
	node.modulate = Color.WHITE
	node.texture = load(profile["texture"]) as Texture2D
	node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if node is Polygon2D:
		node.color = Color.WHITE
	elif node is Line2D:
		node.default_color = Color.WHITE
	node.set_meta("material_profile", profile["id"])


static func _material(profile: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	material.set_shader_parameter("surface_grain", load(profile["texture"]) as Texture2D)
	for key: String in ["pattern", "base_color", "alternate_color", "seam_color", "cell_mm", "phase_mm", "angle", "line_mm", "contrast", "stagger", "grain_period"]:
		material.set_shader_parameter(key, profile[key])
	return material


static func _range(rng: RandomNumberGenerator, values: Array) -> float:
	return rng.randf_range(float(values[0]), float(values[1]))
