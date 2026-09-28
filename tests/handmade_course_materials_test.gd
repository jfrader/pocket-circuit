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
		assert(built["scene"] != null)
		var track := (built["scene"] as PackedScene).instantiate() as Node2D
		root.add_child(track)
		var surface := track.get_node("TrackSurface") as Line2D
		var floor_node := track.get_node("RoomSurface") as Polygon2D
		assert(surface.material != floor_node.material, "road must not reuse the room-floor shader")
		assert((surface.material as ShaderMaterial).shader == MATERIALS.COURSE.SHADER, "saved/generated road must use handmade material")
		assert(surface.get_meta("material_profile") != floor_node.get_meta("material_profile"), "road and apron need distinct visual identities")
		assert(surface.width == CORE.HALF_WIDTH * 2.0, "material must retain authoritative road width")
		assert(track.get_meta("surface_identity").has("course"), "scene must expose its seeded course identity")
		var collision := _collision_signature(track)
		var route := surface.points.duplicate()
		var racing_line := (track.get_node("RacingLine") as Line2D).points.duplicate()
		var grip: Array = track.get_meta("generated_surfaces", []).duplicate(true)
		var first := MATERIALS.resolve(theme, 123)
		var grain: Texture2D = MATERIALS.apply(track, first)
		assert(grain is ImageTexture, "course textures must be completed images, not worker-owning resources that can deadlock threaded scene-load shutdown")
		assert(grain.get_image() != null, "course grain must finish before interactive presentation")
		assert(grain.get_image().has_mipmaps(), "grain needs mipmaps to avoid distant shimmer")
		var construction := track.get_node("CourseConstruction")
		var signature := _construction_signature(construction)
		assert(MATERIALS.apply(track, first) == grain, "repeated material must reuse the prepared grain")
		assert(signature == _construction_signature(track.get_node("CourseConstruction")), "reapplying the same seed must not duplicate or move joins")
		MATERIALS.apply(track, MATERIALS.resolve(theme, 456))
		assert(signature != _construction_signature(track.get_node("CourseConstruction")), "different material seed must vary construction")
		assert(collision == _collision_signature(track), "surface changes must preserve collision geometry and layers")
		assert(route == surface.points and racing_line == (track.get_node("RacingLine") as Line2D).points, "surface changes must preserve route and racing line")
		assert(grip == track.get_meta("generated_surfaces"), "decorative materials must not alter authoritative grip zones")
		assert(track.get_node_or_null("OuterBarrier") == null, "course must not add an apron wall")
		root.remove_child(track)
		track.free()
		await process_frame
	assert(MATERIALS.COURSE._grains.size() <= int(MATERIALS.catalog()["course_settings"]["grain_cache_limit"]), "grain cache must remain bounded across races")
	_check_closing_segment()
	for scene_name: String in ["kitchen_circuit", "kitchen_graybox", "workshop_workbench", "office_desk"]:
		var path := "res://scenes/tracks/%s.tscn" % scene_name
		assert(ResourceLoader.get_resource_uid(path) != ResourceUID.INVALID_ID, "saved fixtures must preserve their resource identity")
		var packed := load(path) as PackedScene
		var saved := packed.instantiate()
		assert(saved.get_meta("surface_identity").has("course"), "canonical scenes must retain the course identity")
		var identity: Dictionary = saved.get_meta("surface_identity")
		assert(identity["course"]["kind"] == MATERIALS.catalog()["themes"][identity["theme"]]["course"]["kind"], "canonical fixtures must use the current course material family")
		for neighbor: String in ["floor", "island"]:
			assert(MATERIALS.COURSE.surface_contrast(identity["course"]["base_color"], identity[neighbor]) >= float(MATERIALS.catalog()["course_settings"]["min_surface_contrast"]), "canonical course must differ from " + neighbor)
		assert((saved.get_node("TrackSurface").material as ShaderMaterial).shader == MATERIALS.COURSE.SHADER, "canonical course must render through the production shader")
		assert((saved.get_node("TrackSurface").material as ShaderMaterial).get_shader_parameter("grain_noise") is ImageTexture, "thread-loaded fixtures must not embed active noise generators")
		saved.free()
	var app := root.get_node("App")
	root.remove_child(app)
	await process_frame
	app.free()
	await create_timer(0.2).timeout
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
	var profile: Dictionary = MATERIALS.resolve(&"office", 1)["course"].duplicate(true)
	profile["join_count"] = 1
	profile["join_phase"] = 0.95
	profile["join_jitter"] = 0.0
	MATERIALS.COURSE.apply(track, profile)
	var join := track.get_node("CourseConstruction/Join0") as Line2D
	assert(((join.points[0] + join.points[1]) * 0.5).is_equal_approx(Vector2(0, 200)), "joins must reach the closing segment of a loop")
	surface.closed = false
	MATERIALS.COURSE.apply(track, profile)
	join = track.get_node("CourseConstruction/Join0") as Line2D
	assert(((join.points[0] + join.points[1]) * 0.5).is_equal_approx(Vector2(150, 1000)), "open paths must not gain a closing segment")
	track.free()


func _construction_signature(container: Node) -> String:
	var result: Array = []
	for node: Node2D in container.get_children():
		assert(ROLES.read(node) == ROLES.FLAT and not node is CollisionObject2D, "paper joins and shadows must stay non-colliding")
		result.append([node.name, node.transform, node.get("polygon") if node is Polygon2D else node.get("points")])
	return var_to_str(result)


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
