class_name WorldPropScale
## One world unit is one millimetre of tabletop; sprite padding is not object size.

const MANIFEST := "res://data/world_prop_art.json"
const WORLD_UNITS_PER_MM := 1.0
const SMALL_PROP_LIMIT := 64.0
const HAZARD_ASSETS := {
	&"kitchen": "res://assets/textures/imagine/hazard_kitchen_apple.png",
	&"workshop": "res://assets/textures/imagine/hazard_workshop_socket.png",
	&"office": "res://assets/textures/imagine/hazard_office_cable.png",
}
static var definitions: Array = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
static var lengths: Dictionary = _load_lengths()
static var scenery_lengths: Dictionary = _load_lengths(true)
static var sizes: Dictionary = _load_sizes()


static func _load_lengths(scenery_only: bool = false) -> Dictionary:
	var result := {}
	for definition: Dictionary in definitions:
		if scenery_only and not bool(definition.get("scenery", true)):
			continue
		for output: String in definition["outputs"]:
			result[output.get_file()] = float(definition["length_mm"]) * WORLD_UNITS_PER_MM
	return result


static func length_for(path: String, fallback: float) -> float:
	return float(lengths.get(path.get_file(), fallback))


static func _load_sizes() -> Dictionary:
	var result := {}
	for definition: Dictionary in definitions:
		var length := float(definition["length_mm"]) * WORLD_UNITS_PER_MM
		var width := float(definition.get("width_mm", definition["length_mm"])) * WORLD_UNITS_PER_MM
		var dimensions: Array = definition.get("dimensions_mm", [length, width])
		for output: String in definition["outputs"]:
			result[output.get_file()] = Vector2(float(dimensions[0]), float(dimensions[1]))
	return result


static func size_for(path: String, fallback: Vector2) -> Vector2:
	return sizes.get(path.get_file(), fallback)


static func sprite_scale(texture: Texture2D, visible_bounds: Rect2, fallback: float) -> float:
	return length_for(texture.resource_path, fallback) / maxf(visible_bounds.size.x, visible_bounds.size.y)


static func small_assets(paths: Array) -> Array[String]:
	var result: Array[String] = []
	for path: String in paths:
		if length_for(path, INF) <= SMALL_PROP_LIMIT:
			result.append(path)
	return result


static func hazard_size(theme: StringName) -> Vector2:
	return size_for(String(HAZARD_ASSETS.get(theme, HAZARD_ASSETS[&"kitchen"])), Vector2(60.0, 60.0))
