extends SceneTree

const MATERIALS := preload("res://scripts/race/household_surface_materials.gd")
const CORE := preload("res://scripts/race/track_builder_core.gd")
const SAMPLE_COUNT := 512


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var all_profiles := {}
	for theme: StringName in [&"kitchen", &"workshop", &"office"]:
		var floors := {}
		var islands := {}
		var pairs := {}
		var structures := {}
		var courses := {}
		var constructions := {}
		for sample in SAMPLE_COUNT:
			var result := MATERIALS.resolve(theme, sample)
			if not _expect(result == MATERIALS.resolve(theme, sample), "same seed must reproduce every surface parameter"): return
			var course: Dictionary = result["course"]
			courses[course["id"]] = true
			constructions[str([course["grain_seed"], course["brush_period_mm"], course["brush_phase"], course["edge_width_mm"]])] = true
			if not _expect(course["contrast_safe"], "authored course/floor/island combinations must have a readable palette"): return
			if not _expect(float(course["min_surface_contrast"]) >= 1.5, "contrast policy must not be weakened"): return
			if not _expect(float(course["paint_opacity"]) > 0.0 and float(course["paint_opacity"]) <= 0.90, "paint must remain translucent"): return
			if not _expect((course["pigment_color"] as Color).s <= 0.3, "pigments must remain restrained rather than saturated"): return
			for neighbor: String in ["floor", "island"]:
				if not _expect(MATERIALS.COURSE.course_contrast(course, result["floor"], result[neighbor]) >= float(course["min_surface_contrast"]), "composited paint must remain clearly distinct from " + neighbor): return
			if not _expect(FileAccess.file_exists(course["texture"]), "course grain must use a shipping texture"): return
			if not _expect(course["texture"] == result["floor"]["texture"], "paint must retain the actual supporting material"): return
			if not _expect(String(course["id"]).begins_with(String(theme) + "_"), "course palette must belong to its room"): return
			floors[result["floor"]["id"]] = true
			islands[result["island"]["id"]] = true
			pairs[str(result["floor"]["id"]) + ":" + str(result["island"]["id"])] = true
			structures[str(result["floor"]["pattern"]) + ":" + str(result["island"]["pattern"])] = true
			for role: String in ["floor", "island"]:
				var profile: Dictionary = result[role]
				var id := String(profile["id"])
				if not _expect(not all_profiles.has(id) or all_profiles[id] == theme, "surface identity must not leak across rooms"): return
				all_profiles[id] = theme
				if not _expect((profile["cell_mm"] as Vector2).x > float(profile["line_mm"]) * 4.0, "marks must leave negative space"): return
				if not _expect(FileAccess.file_exists(profile["texture"]), "painted grain source must exist"): return
		if not _expect(floors.size() == 4 and islands.size() == 3, "every authored material family must remain reachable"): return
		if not _expect(pairs.size() >= 10, "variation must change floor/island combinations, not just color"): return
		if not _expect(structures.size() >= 4, "variation must include different structural patterns"): return
		if not _expect(courses.size() == 3 and constructions.size() == SAMPLE_COUNT, "course variation must reach all palettes and vary grain/construction beyond tint"): return
		for family: String in MATERIALS.catalog()["families"]:
			if not family.begins_with(String(theme) + "_"):
				continue
			for sample in 32:
				var identity := CORE.WORLD_MATERIALS.resolve(theme, &"", sample, family)
				if not _expect(identity["known"], "contrast coverage must exercise actual curated palettes"): return
				var resolved := MATERIALS.resolve(theme, sample, family, identity["palette_id"], identity["floor_modulate"])
				if not _expect(resolved["course"]["contrast_safe"], "curated story tints must preserve course contrast"): return
				for neighbor: String in ["floor", "island"]:
					if not _expect(MATERIALS.COURSE.course_contrast(resolved["course"], resolved["floor"], resolved[neighbor]) >= float(resolved["course"]["min_surface_contrast"]), "curated story paint must differ from " + neighbor): return
		print("SURFACE_RANGE ", theme, " seeds=", SAMPLE_COUNT, " floor=", floors.size(), " island=", islands.size(), " pairs=", pairs.size(), " structures=", structures.size())
	var first := CORE.prepare_layout(&"workshop", &"wide", 246810, {"material_seed": 1})
	var second := CORE.prepare_layout(&"workshop", &"wide", 246810, {"material_seed": 2})
	if not _expect(first["centerline"] == second["centerline"], "material variation must not perturb route geometry"): return
	if not _expect(MATERIALS.resolve(&"workshop", 1) != MATERIALS.resolve(&"workshop", 2), "different seeds must produce different materials"): return
	if _failed:
		return
	print("HOUSEHOLD_SURFACE_MATERIALS_TEST PASS deterministic_theme_isolation_structural_variation_geometry_independence")
	var app := root.get_node("App")
	root.remove_child(app)
	await process_frame
	app.free()
	await create_timer(0.2).timeout
	quit()

var _failed := false
func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error("FAIL: " + message)
		quit(1)
		return false
	return true
