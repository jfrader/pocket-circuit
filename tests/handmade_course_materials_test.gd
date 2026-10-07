extends SceneTree

const CORE := preload("res://scripts/race/track_builder_core.gd")
const MATERIALS := preload("res://scripts/race/household_surface_materials.gd")
const ROLES := preload("res://scripts/race/generated_world_visual_role.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	for theme: StringName in [&"kitchen", &"workshop", &"office"]:
		var built := CORE.build_packed(theme, &"classic", 0, {"length_tier":"compact"})
		if not _expect(built["scene"] != null, "the packed course must build"): return
		var track := (built["scene"] as PackedScene).instantiate() as Node2D
		root.add_child(track)
		var surface := track.get_node("TrackSurface") as Line2D
		var floor_node := track.get_node("RoomSurface") as Polygon2D
		if not _expect(surface.material != floor_node.material, "paint uniforms must not mutate the supporting material"): return
		if not _expect((surface.material as ShaderMaterial).shader == MATERIALS.COURSE.SHADER, "saved/generated road must use handmade material"): return
		if not _expect(surface.get_meta("material_profile") != floor_node.get_meta("material_profile"), "road and apron need distinct visual identities"): return
		if not _expect(surface.width == CORE.HALF_WIDTH * 2.0, "material must retain authoritative road width"): return
		if not _expect(track.get_meta("surface_identity").has("course"), "scene must expose its seeded course identity"): return
		var collision := _collision_signature(track)
		var route := surface.points.duplicate()
		var racing_line := (track.get_node("RacingLine") as Line2D).points.duplicate()
		var grip: Array = track.get_meta("generated_surfaces", []).duplicate(true)
		var first := MATERIALS.resolve(theme, 123)
		var grain: Texture2D = MATERIALS.apply(track, first)
		if not _expect(grain is ImageTexture, "course textures must be completed images, not worker-owning resources that can deadlock threaded scene-load shutdown"): return
		if not _expect(grain.get_image() != null, "course grain must finish before interactive presentation"): return
		if not _expect(grain.get_image().has_mipmaps(), "grain needs mipmaps to avoid distant shimmer"): return
		if not _expect(track.get_node_or_null("CourseConstruction") == null, "paint must not have paper joins, tape or a raised shadow"): return
		if not _expect(ROLES.read(surface) == ROLES.FLAT, "surface must be flat"): return
		var signature := var_to_str(track.get_meta("surface_identity")["course"])
		if not _expect(MATERIALS.apply(track, first) == grain, "repeated material must reuse the prepared grain"): return
		if not _expect(signature == var_to_str(track.get_meta("surface_identity")["course"]), "reapplying the same seed must preserve brushwork"): return
		var paint := surface.material as ShaderMaterial
		var substrate := floor_node.material as ShaderMaterial
		if not _expect(surface.texture == floor_node.texture, "paint must share the underlying texture"): return
		for key: String in ["base_color", "alternate_color", "seam_color", "pattern", "cell_mm", "phase_mm", "angle", "line_mm", "contrast", "stagger", "grain_period", "surface_grain"]:
			if not _expect(paint.get_shader_parameter(key) == substrate.get_shader_parameter(key), "paint must not invent a second grid: " + key): return
		MATERIALS.apply(track, MATERIALS.resolve(theme, 456))
		if not _expect(signature != var_to_str(track.get_meta("surface_identity")["course"]), "different material seed must vary brushwork"): return
		if not _expect(collision == _collision_signature(track), "surface changes must preserve collision geometry and layers"): return
		if not _expect(route == surface.points and racing_line == (track.get_node("RacingLine") as Line2D).points, "surface changes must preserve route and racing line"): return
		if not _expect(grip == track.get_meta("generated_surfaces"), "decorative materials must not alter authoritative grip zones"): return
		if not _expect(track.get_node_or_null("OuterBarrier") == null, "course must not add an apron wall"): return
		root.remove_child(track)
		track.free()
		await process_frame
	if not _expect(MATERIALS.COURSE._grains.size() <= int(MATERIALS.catalog()["course_settings"]["grain_cache_limit"]), "grain cache must remain bounded across races"): return
	_check_closing_segment()
	for scene_name: String in ["kitchen_circuit", "kitchen_graybox", "workshop_workbench", "office_desk"]:
		var path := "res://scenes/tracks/%s.tscn" % scene_name
		if not _expect(ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID, "saved fixtures must preserve their resource identity"): return
		var packed := load(path) as PackedScene
		var saved := packed.instantiate()
		if not _expect(saved.get_meta("surface_identity").has("course"), "canonical scenes must retain the course identity"): return
		var identity: Dictionary = saved.get_meta("surface_identity")
		if not _expect(identity["course"]["kind"] == MATERIALS.catalog()["themes"][identity["theme"]]["course"]["kind"], "canonical fixtures must use the current course material family"): return
		for neighbor: String in ["floor", "island"]:
			if not _expect(MATERIALS.COURSE.course_contrast(identity["course"], identity["floor"], identity[neighbor]) >= float(MATERIALS.catalog()["course_settings"]["min_surface_contrast"]), "canonical paint must differ from " + neighbor): return
		if not _expect((saved.get_node("TrackSurface").material as ShaderMaterial).shader == MATERIALS.COURSE.SHADER, "canonical course must render through the production shader"): return
		if not _expect((saved.get_node("TrackSurface").material as ShaderMaterial).get_shader_parameter("grain_noise") is ImageTexture, "thread-loaded fixtures must not embed active noise generators"): return
		saved.free()
	var app := root.get_node("App")
	root.remove_child(app)
	await process_frame
	app.free()
	await create_timer(0.2).timeout
	if _failed:
		return
	print("HANDMADE_COURSE_MATERIALS_TEST PASS distinct_course_idempotent_seeded_visual_only")
	quit()


func _check_closing_segment() -> void:
	var track := Node2D.new()
	var surface := Line2D.new()
	surface.name = "TrackSurface"
	surface.width = CORE.HALF_WIDTH * 2.0
	surface.closed = true
	surface.points = PackedVector2Array([Vector2.ZERO, Vector2(1000, 0), Vector2(1000, 1000), Vector2(0, 1000)])
	track.add_child(surface)
	var resolved := MATERIALS.resolve(&"office", 1)
	var profile: Dictionary = resolved["course"].duplicate(true)
	profile["brush_period_mm"] = 1000.0
	var substrate := MATERIALS._material(resolved["floor"])
	MATERIALS.COURSE.apply(track, profile, substrate)
	if not _expect(is_equal_approx(MATERIALS.COURSE._path_length(surface), 4000.0), "brush mapping must include the closing segment"): return
	if not _expect(is_equal_approx(surface.material.get_shader_parameter("brush_repeats"), 4.0), "closed brush texture must join seamlessly"): return
	surface.closed = false
	MATERIALS.COURSE.apply(track, profile, substrate)
	if not _expect(is_equal_approx(MATERIALS.COURSE._path_length(surface), 3000.0), "open paths must not gain a closing segment"): return
	if not _expect(is_equal_approx(surface.material.get_shader_parameter("brush_repeats"), 3.0), "brush repeats must be 3 for open path"): return
	track.free()


func _collision_signature(track: Node) -> String:
	var result: Array = []
	for node: CollisionObject2D in track.find_children("*", "CollisionObject2D", true, false):
		result.append([track.get_path_to(node), node.transform, node.collision_layer, node.collision_mask])
	for node: CollisionShape2D in track.find_children("*", "CollisionShape2D", true, false):
		var properties := {}
		for property: Dictionary in node.shape.get_property_list():
			if int(property["usage"]) & PROPERTY_USAGE_STORAGE:
				properties[property["name"]] = node.shape.get(property["name"])
		result.append([track.get_path_to(node), node.transform, node.disabled, properties])
	for node: CollisionPolygon2D in track.find_children("*", "CollisionPolygon2D", true, false):
		result.append([track.get_path_to(node), node.transform, node.disabled, node.polygon])
	return var_to_str(result)

var _failed := false
func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error("FAIL: " + message)
		quit(1)
		return false
	return true
