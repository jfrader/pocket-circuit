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
		for sample in SAMPLE_COUNT:
			var result := MATERIALS.resolve(theme, sample)
			assert(result == MATERIALS.resolve(theme, sample), "same seed must reproduce every surface parameter")
			floors[result["floor"]["id"]] = true
			islands[result["island"]["id"]] = true
			pairs[str(result["floor"]["id"]) + ":" + str(result["island"]["id"])] = true
			structures[str(result["floor"]["pattern"]) + ":" + str(result["island"]["pattern"])] = true
			for role: String in ["floor", "island"]:
				var profile: Dictionary = result[role]
				var id := String(profile["id"])
				assert(not all_profiles.has(id) or all_profiles[id] == theme, "surface identity must not leak across rooms")
				all_profiles[id] = theme
				assert((profile["cell_mm"] as Vector2).x > float(profile["line_mm"]) * 4.0, "marks must leave negative space")
				assert(FileAccess.file_exists(profile["texture"]), "painted grain source must exist")
		assert(floors.size() == 4 and islands.size() == 3, "every authored material family must remain reachable")
		assert(pairs.size() >= 10, "variation must change floor/island combinations, not just color")
		assert(structures.size() >= 4, "variation must include different structural patterns")
		print("SURFACE_RANGE ", theme, " seeds=", SAMPLE_COUNT, " floor=", floors.size(), " island=", islands.size(), " pairs=", pairs.size(), " structures=", structures.size())
	var first := CORE.prepare_layout(&"workshop", &"wide", 246810, {"material_seed": 1})
	var second := CORE.prepare_layout(&"workshop", &"wide", 246810, {"material_seed": 2})
	assert(first["centerline"] == second["centerline"], "material variation must not perturb route geometry")
	assert(MATERIALS.resolve(&"workshop", 1) != MATERIALS.resolve(&"workshop", 2))
	print("HOUSEHOLD_SURFACE_MATERIALS_TEST PASS deterministic_theme_isolation_structural_variation_geometry_independence")
	var app := root.get_node("App")
	root.remove_child(app)
	await process_frame
	app.free()
	await create_timer(0.2).timeout
	quit()
