extends SceneTree

const MATERIALS := preload("res://scripts/race/household_surface_materials.gd")
const STRIP_THEMES := preload("res://scripts/race/strip_themes.gd")
const PRESENTER := preload("res://scripts/presentation/track_variant_presenter.gd")
const CORE := preload("res://scripts/race/track_builder_core.gd")
const CATALOG := preload("res://scripts/race/world_environment_catalog.gd")
const THEME := &"basement"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	if not _expect(MATERIALS.catalog()["themes"].has(String(THEME)), "material theme registration"): return
	if not _expect(STRIP_THEMES.second_theme(&"kitchen", String(THEME)) == THEME, "strip theme registration"): return
	if not _expect(STRIP_THEMES.second_theme(&"office") == &"kitchen", "hand-built room must not replace procedural strip story rosters"): return
	var identity := MATERIALS.resolve(THEME, 2474)
	var reference := MATERIALS.resolve(&"workshop", 2474)
	for role: String in ["floor", "island", "course"]:
		for key: String in reference[role]:
			if not _expect(identity[role].has(key) and typeof(identity[role][key]) == typeof(reference[role][key]), "shared surface schema: " + role + "/" + key): return
		if not _expect(load(identity[role]["texture"]) is Texture2D, "surface texture loads: " + role): return
	for seed_value in 64:
		var resolved := MATERIALS.resolve(THEME, seed_value)
		if not _expect(resolved["course"]["contrast_safe"], "dark floor must preserve course readability"): return
	var composition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG.COMPOSITION_PATH))
	var count := 0
	for role: String in ["support", "micro", "ground"]:
		var paths: Array = composition["themes"][String(THEME)][role]
		if not _expect(not paths.is_empty(), "composition role populated: " + role): return
		for path: String in paths:
			var full_path := CATALOG.PREFIX + path
			var asset := CATALOG.for_path(full_path)
			if not _expect(not asset.is_empty() and String(THEME) in asset["themes"] and role in asset["roles"], "composition resolves to same-theme asset: " + path): return
			var texture := load(full_path) as Texture2D
			if not _expect(texture != null and texture.get_size() == Vector2(512, 512), "prepared texture loads and is normalized: " + path): return
			if not _expect(texture.get_image().get_pixel(0, 0).a == 0.0, "no opaque sheet matte: " + path): return
			count += 1
	var candidates := CATALOG.candidates(THEME, {}, {})
	if not _expect(candidates.size() == count, "all composition assets are usable by the environment planner"): return

	# Reuse a geometry fixture, not its artwork or generated kitchen story.
	# The finale supplies its own authored route through this same scene builder.
	var prepared := CORE.prepare_layout(&"kitchen", &"wide", 2474)
	if not _expect(not prepared.is_empty(), "track geometry fixture builds"): return
	var spec: Dictionary = prepared["spec"]
	spec["environment_theme"] = THEME
	spec["surface_identity"] = identity
	spec["floor_texture"] = identity["floor"]["texture"]
	spec["track_texture"] = identity["course"]["texture"]
	spec["island_material_texture"] = identity["island"]["texture"]
	spec["edge_texture"] = identity["floor"]["texture"]
	spec["seed_obstacles"] = false
	spec["story_kit"] = {"surfaces": [
		{"name": &"basement puddle", "grip": 0.58, "speed": 0.88, "decal": CATALOG.PREFIX + "ground_dressing/basement_puddle.png"},
		{"name": &"basement oil stain", "grip": 0.45, "speed": 0.92, "decal": CATALOG.PREFIX + "ground_dressing/basement_oil_stain.png"},
	]}
	spec["environment_plan"] = {"placements": [], "diagnostics": {}}
	var track := Node2D.new()
	root.add_child(track)
	await CORE._build_scene(track, spec, prepared["centerline"], prepared["edges"], prepared["room_polygon"], THEME)
	var presenter := PRESENTER.new()
	track.add_child(presenter)
	presenter.configure(track, THEME)
	if not _expect(presenter.theme == THEME and presenter.base_surface_name == &"concrete floor", "presenter retains basement identity"): return
	var floor := track.get_node_or_null("RoomSurface") as Polygon2D
	if not _expect(floor != null and floor.material is ShaderMaterial and floor.texture != null, "built track instantiates its floor material"): return
	if not _expect(floor.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED, "floor must repeat in world space rather than stretch"): return
	var floor_material := floor.material as ShaderMaterial
	if not _expect(is_equal_approx(float(floor_material.get_shader_parameter("grain_period")), float(identity["floor"]["grain_period"])) and float(identity["floor"]["grain_period"]) > 0.0, "floor repeat must retain its resolved millimeter period"): return
	var floor_image := floor.texture.get_image()
	var darkest := 1.0
	var lightest := 0.0
	for y in range(0, floor_image.get_height(), 16):
		for x in range(0, floor_image.get_width(), 16):
			var luminance := floor_image.get_pixel(x, y).get_luminance()
			darkest = minf(darkest, luminance)
			lightest = maxf(lightest, luminance)
	if not _expect(lightest-darkest >= 0.1, "floor grain must retain texture signal rather than become a flat swatch"): return
	for pixel in floor_image.get_width():
		if not _expect(floor_image.get_pixel(pixel, 0) == floor_image.get_pixel(pixel, floor_image.get_height()-1), "floor tile north/south edges must join"): return
	for pixel in floor_image.get_height():
		if not _expect(floor_image.get_pixel(0, pixel) == floor_image.get_pixel(floor_image.get_width()-1, pixel), "floor tile east/west edges must join"): return
	if not _expect(floor.texture.resource_path == identity["floor"]["texture"] and track.get_meta("surface_identity")["theme"] == String(THEME), "built track uses basement, not a fallback theme"): return
	track.queue_free()
	await process_frame
	print("BASEMENT_THEME_TEST PASS registration surface_schema composition_assets track_surface")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("BASEMENT_THEME_TEST FAIL: " + message)
	quit(1)
	return false
