class_name WorldEnvironmentCatalog
extends RefCounted

const PATH := "res://data/world_prop_art.json"
const PREFIX := "res://assets/textures/"
const CONTRACT := "overhead_gouache_v1"
const COMPOSITION_PATH := "res://data/environment_composition.json"
static var _entries: Dictionary = {}
static var _paths: Dictionary = {}
static var _composition: Dictionary = {}


static func _load() -> void:
	if not _entries.is_empty():
		return
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	_composition = JSON.parse_string(FileAccess.get_file_as_string(COMPOSITION_PATH))
	for raw: Dictionary in rows:
		var entry := raw.duplicate(true)
		var dimensions: Array = entry["dimensions_mm"]
		entry["dimensions_mm"] = Vector2(float(dimensions[0]), float(dimensions[1]))
		entry["texture_path"] = PREFIX + String(entry["outputs"][0])
		_entries[entry["id"]] = entry
		for output: String in entry["outputs"]:
			_paths[PREFIX + output] = String(entry["id"])


static func get_asset(id: String) -> Dictionary:
	_load()
	return (_entries.get(id, {}) as Dictionary).duplicate(true)


static func for_path(path: String) -> Dictionary:
	_load()
	var asset := get_asset(String(_paths.get(path, "")))
	if not asset.is_empty():
		asset["texture_path"] = path
	return asset


static func all_assets() -> Array[Dictionary]:
	_load()
	var result: Array[Dictionary] = []
	for entry: Dictionary in _entries.values():
		result.append(entry.duplicate(true))
	return result


static func boundary_density() -> Dictionary:
	_load()
	return (_composition["boundary_density"] as Dictionary).duplicate(true)


static func candidates(theme: StringName, story: Dictionary, layout: Dictionary) -> Array[Dictionary]:
	_load()
	var selected := {}
	for group: Dictionary in story.get("island", []):
		var role := "focal" if String(group.get("formation", "")) == "focal" else "support"
		_include(selected, theme, group, role, 5.0 if role == "focal" else 2.0)
	_include(selected, theme, story.get("giants", []), "focal", 3.0)
	_include(selected, theme, story.get("landmarks", []), "focal", 3.0)
	_include(selected, theme, story.get("object_line", {}), "support", 2.0)
	_include(selected, theme, story.get("delimiter", {}), "boundary", 1.0)
	_include(selected, theme, (layout.get("generated_boundary", {}) as Dictionary).get("sections", []), "boundary", 1.0)
	_include(selected, theme, layout.get("ground_sections", []), "ground", 1.0)
	_include(selected, theme, layout.get("edge_decor", []), "micro", 1.0)
	_include(selected, theme, layout.get("edge_decor", []), "boundary", 1.0)
	_include(selected, theme, layout.get("ambient_props", []), "support", 2.0)
	_include(selected, theme, layout.get("decals", []), "decal", 0.5)
	var supporting_families: Dictionary = _composition["themes"][String(theme)]
	for role: String in supporting_families:
		for path: String in supporting_families[role]:
			_include(selected, theme, PREFIX + path, role, 1.5)
			if role == "micro":
				_include(selected, theme, PREFIX + path, "boundary", 1.0)
	var result: Array[Dictionary] = []
	for asset: Dictionary in selected.values():
		result.append(asset)
	return result


static func _include(selected: Dictionary, theme: StringName, value: Variant, role: String, weight: float) -> void:
	if value is Dictionary:
		for child: Variant in value.values():
			_include(selected, theme, child, role, weight)
	elif value is Array:
		for child: Variant in value:
			_include(selected, theme, child, role, weight)
	elif (value is String or value is StringName) and String(value).begins_with(PREFIX):
		var asset := for_path(String(value))
		if asset.is_empty() or String(theme) not in asset["themes"] or asset.get("kind", "prop") != "prop" or not bool(asset.get("scenery", true)):
			return
		if role == "boundary" and String(asset.get("collision", "flat")) == "flat":
			return
		var id := String(asset["id"])
		if not selected.has(id):
			asset["roles"] = []
			asset["texture_path"] = PREFIX + String(asset["outputs"][0])
			selected[id] = asset
		var entry: Dictionary = selected[id]
		var resolved_role := "micro" if role == "support" and float(asset["length_mm"]) <= 55.0 else role
		if resolved_role not in entry["roles"]:
			entry["roles"].append(resolved_role)
		entry["visual_weight"] = maxf(float(entry["visual_weight"]), weight)
