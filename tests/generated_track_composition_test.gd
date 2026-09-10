extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const PRESENTER := preload("res://scripts/presentation/track_variant_presenter.gd")

const THEMES: Array[StringName] = [&"kitchen", &"workshop", &"office"]
const ROOMS: Array[StringName] = [&"classic", &"wide", &"tall", &"square"]
const SIGNATURE_ASSETS := {
	&"kitchen": "res://assets/textures/imagine/stove_top.png",
	&"workshop": "res://assets/textures/workshop_hero/hero_workshop_toolbox.png",
	&"office": "res://assets/textures/office_hero/hero_office_keyboard.png",
}

var _built_count := 0
var _minimum_gate_span := INF
var _maximum_gate_span := 0.0


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	for theme: StringName in THEMES:
		if not _check_story_assets(theme):
			return
		var story_seeds := _find_story_seeds(theme)
		if not _expect(story_seeds.size() >= 4, "%s should expose at least four well-mixed stories" % theme):
			return
		var seen_story_ids := {}
		var seen_assets: Array[String] = []
		for story_index in 4:
			var seed := int(story_seeds[story_index])
			var room := ROOMS[(story_index + THEMES.find(theme)) % ROOMS.size()]
			var built: Dictionary = BUILDER.build_packed(theme, room, seed)
			if not _expect(built.get("scene") is PackedScene, "%s/%s/%d should complete its build" % [theme, room, seed]):
				return
			var track := (built["scene"] as PackedScene).instantiate() as Node2D
			var generated_signature := _node_signature(track)
			root.add_child(track)
			_built_count += 1
			if not _check_generated_track(track, theme, seed, seen_story_ids, seen_assets):
				return
			if story_index == 0:
				var repeated: Dictionary = BUILDER.build_packed(theme, room, seed)
				if not _expect(repeated.get("scene") is PackedScene, "%s repeated request should build" % theme):
					return
				var repeated_track := (repeated["scene"] as PackedScene).instantiate() as Node2D
				var repeated_signature := _node_signature(repeated_track)
				if not _expect(generated_signature == repeated_signature, "%s same request should have an identical generated node signature (%s)" % [theme, _first_signature_difference(generated_signature, repeated_signature)]):
					return
				repeated_track.free()
			track.free()
		if not _expect(seen_story_ids.size() >= 4, "%s sample should build four distinct story ids (got %s)" % [theme, seen_story_ids.keys()]):
			return
		var expected_asset := String(SIGNATURE_ASSETS[theme])
		if not _expect(expected_asset in seen_assets, "%s stories should exercise their theme landmark %s" % [theme, expected_asset.get_file()]):
			return
	if not _check_wide_triangle_regression():
		return
	if not _check_boundary_room_regressions():
		return
	if not _check_shadow_helpers():
		return
	if not _check_legacy_builder_scale():
		return
	print("GENERATED_TRACK_COMPOSITION_TEST PASS builds=%d stories=12 surfaces=24+ gate_spans=%.1f..%.1f density floor60-120 edge60-150 giants1-3" % [_built_count, _minimum_gate_span, _maximum_gate_span])
	quit(0)


func _find_story_seeds(theme: StringName) -> Array[int]:
	var kits: Array = BUILDER.STORY_KITS[theme]
	var seeds_by_story := {}
	var mixed_differs_from_modulo := false
	for seed in 96:
		var kit_index := posmod(BUILDER._mix_seed(seed, String(theme)), kits.size())
		mixed_differs_from_modulo = mixed_differs_from_modulo or kit_index != seed % kits.size()
		var story_id := StringName((kits[kit_index] as Dictionary)["id"])
		if not seeds_by_story.has(story_id):
			seeds_by_story[story_id] = seed
	var result: Array[int] = []
	for kit: Dictionary in kits:
		var story_id := StringName(kit["id"])
		if seeds_by_story.has(story_id):
			result.append(int(seeds_by_story[story_id]))
	if not mixed_differs_from_modulo:
		return []
	return result


func _check_generated_track(track: Node2D, theme: StringName, seed: int, seen_story_ids: Dictionary, seen_assets: Array[String]) -> bool:
	if not _expect(bool(track.get_meta("generated_track", false)), "%s seed %d should identify as generated" % [theme, seed]):
		return false
	if not _expect(int(track.get_meta("requested_seed", -1)) == seed, "%s should retain requested_seed" % theme):
		return false
	if not _expect(not String(track.get_meta("family", "")).is_empty(), "%s should retain generator family" % theme):
		return false
	if not _expect(float(track.get_meta("loop_length", 0.0)) > 0.0, "%s should retain loop length" % theme):
		return false
	var story_id := StringName(track.get_meta("story_id", &""))
	if not _expect(not String(story_id).is_empty(), "%s should retain story id" % theme):
		return false
	seen_story_ids[story_id] = true
	var void_backdrop := track.get_node_or_null("Floor") as Polygon2D
	var room_surface := track.get_node_or_null("RoomSurface") as Polygon2D
	if not _expect(void_backdrop != null and void_backdrop.color.is_equal_approx(Color("111316")) and room_surface != null, "%s should present its textured room as an island over a dark void" % theme):
		return false
	if not _expect(room_surface.texture != null and room_surface.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED and room_surface.uv.size() == room_surface.polygon.size(), "%s room floor should have complete, repeating material coordinates" % theme):
		return false
	var floor_period: Vector2 = BUILDER.LAYOUTS[theme].get("floor_tile_world_size", BUILDER.DEFAULT_FLOOR_TILE_WORLD_SIZE)
	for index in room_surface.polygon.size():
		var expected_uv := room_surface.polygon[index] / floor_period * room_surface.texture.get_size()
		if not _expect(room_surface.uv[index].is_equal_approx(expected_uv), "%s floor must respect its configured world material period" % theme):
			return false

	if not _expect(track.find_children("PaperclipLine", "", true, false).is_empty(), "%s generated track must not use the old global PaperclipLine" % theme):
		return false
	if not _expect(track.find_children("BoundaryProp", "", true, false).is_empty(), "%s generated track must leave non-moment boundaries bare" % theme):
		return false

	var assets := _generated_asset_paths(track)
	seen_assets.append_array(assets)
	for asset_path: String in assets:
		if not _expect(not asset_path.ends_with(".jpg"), "%s generated story must not use an opaque JPG prop (%s)" % [theme, asset_path]):
			return false
	for other_theme: StringName in THEMES:
		if other_theme == theme:
			continue
		if not _expect(String(SIGNATURE_ASSETS[other_theme]) not in assets, "%s story must not leak %s landmark" % [theme, other_theme]):
			return false
	var unique_assets: Array[String] = []
	_collect_unique_prop_assets(track, unique_assets)
	var seen_unique_assets := {}
	for asset_path: String in unique_assets:
		if not _expect(not seen_unique_assets.has(asset_path), "%s unique story props should not repeat %s" % [theme, asset_path.get_file()]):
			return false
		seen_unique_assets[asset_path] = true

	var formation_nodes: Array[Node] = []
	var cluster := track.get_node_or_null("GeneratedMoments/IslandFocalCluster")
	if cluster:
		formation_nodes.append_array(cluster.get_children())
	for path: String in ["GeneratedMoments/ObjectLine", "GeneratedMoments/SparseDelimiter"]:
		var formation := track.get_node_or_null(path)
		if formation:
			formation_nodes.append(formation)
	if not _expect(formation_nodes.size() == 5, "%s should expose three island quantities and two track formations" % theme):
		return false
	for formation: Node in formation_nodes:
		var quantity := StringName(formation.get_meta("semantic_quantity", &""))
		var placed_count := int(formation.get_meta("placed_count", -1))
		match quantity:
			&"unique":
				if not _expect(placed_count == 1, "%s/%s seed %d unique formation %s must contain exactly one focal" % [theme, story_id, seed, formation.name]):
					return false
			&"few":
				if not _expect(placed_count >= 2 and placed_count <= 3, "%s/%s seed %d few formation %s must contain 2-3 objects (got %d)" % [theme, story_id, seed, formation.name, placed_count]):
					return false
			&"many":
				if not _expect(placed_count >= 8 and placed_count <= 20, "%s/%s seed %d many formation %s must contain 8-20 objects (got %d)" % [theme, story_id, seed, formation.name, placed_count]):
					return false
			_:
				if not _expect(false, "%s formation %s should declare a semantic quantity" % [theme, formation.name]):
					return false

	var landmarks := track.get_node_or_null("GeneratedMoments/CornerLandmarks")
	if not _expect(landmarks != null and int(landmarks.get_meta("placed_count", 0)) in [1, 2], "%s should place one or two corner landmarks" % theme):
		return false
	var opening := track.get_node_or_null("GeneratedMoments/OpeningLandmark")
	if not _expect(opening != null and int(opening.get_meta("placed_count", 0)) == 1, "%s should place one iconic opening landmark" % theme):
		return false
	if not _check_room_dressing(track, theme, seed):
		return false
	if not _check_density_systems(track, theme, seed):
		return false
	var moment_indices: Dictionary = track.get_meta("generated_moment_indices", {})
	for required_moment: String in ["opening", "early_conflict_forward", "early_conflict_reverse", "shortcut", "technical", "speed", "finish"]:
		if not _expect(moment_indices.has(required_moment), "%s should expose its %s moment index" % [theme, required_moment]):
			return false
	var forward_conflict := track.get_node_or_null("GeneratedMoments/EarlyConflictForward")
	var reverse_conflict := track.get_node_or_null("GeneratedMoments/EarlyConflictReverse")
	if not _expect(forward_conflict != null and reverse_conflict != null, "%s should expose direction-aware early conflict points" % theme):
		return false
	if not _expect(float(forward_conflict.get_meta("lap_fraction", 0.0)) >= 0.12 and float(forward_conflict.get_meta("lap_fraction", 0.0)) <= 0.25, "%s forward conflict should occur early in the lap" % theme):
		return false
	if not _expect(float(reverse_conflict.get_meta("lap_fraction", 0.0)) >= 0.12 and float(reverse_conflict.get_meta("lap_fraction", 0.0)) <= 0.25, "%s reverse conflict should occur early in the reverse lap" % theme):
		return false
	var hazard_paths: Dictionary = track.get_meta("generated_hazard_paths", {})
	for direction: String in ["forward", "reverse"]:
		var hazard_path: PackedVector2Array = hazard_paths.get(direction, PackedVector2Array())
		if not _expect(hazard_path.size() == 2 and hazard_path[0].distance_to(hazard_path[1]) >= 160.0, "%s %s conflict hazard should cross most of the corridor" % [theme, direction]):
			return false
	var speed_section := track.get_node_or_null("GeneratedMoments/SpeedSection")
	var dramatic_finish := track.get_node_or_null("GeneratedMoments/DramaticFinish")
	if not _expect(speed_section != null and dramatic_finish != null, "%s should reserve a speed section and dramatic finish" % theme):
		return false
	var finish_gate := track.get_node_or_null("Checkpoint0Finish") as Node2D
	var forward_finish_path: PackedVector2Array = dramatic_finish.get_meta("forward_approach", PackedVector2Array())
	var reverse_finish_path: PackedVector2Array = dramatic_finish.get_meta("reverse_approach", PackedVector2Array())
	if not _expect(finish_gate != null and forward_finish_path.size() > 10 and reverse_finish_path.size() > 10, "%s finish should have clear approaches in both directions" % theme):
		return false
	if not _expect(forward_finish_path[forward_finish_path.size() - 1].distance_to(finish_gate.position) < 1.0 and reverse_finish_path[reverse_finish_path.size() - 1].distance_to(finish_gate.position) < 1.0, "%s finish approaches should terminate at the checker gate" % theme):
		return false
	if not _expect(_open_path_length(forward_finish_path) > 140.0 and _open_path_length(reverse_finish_path) > 140.0, "%s dramatic finish should have meaningful run-up in both directions" % theme):
		return false
	if not _expect(track.get_node_or_null("StartFinishWhite") != null and track.get_node_or_null("StartFinishBlack") != null, "%s dramatic finish should retain the checker landmark" % theme):
		return false
	if not _check_island_geometry(track, "%s seed %d" % [theme, seed]):
		return false
	if not _check_open_boundary_assets(track, theme, seed):
		return false
	if not _check_corridor_gates(track, "%s seed %d" % [theme, seed]):
		return false
	if not _check_visible_collision_backing(track, "%s seed %d" % [theme, seed]):
		return false

	var centerline := (track.get_node("TrackSurface") as Line2D).points
	var definitions: Variant = track.get_meta("generated_surfaces", null)
	if not _expect(definitions is Array and (definitions as Array).size() >= 6 and (definitions as Array).size() <= 10, "%s should define two designed surfaces plus 4-8 grip patches" % theme):
		return false
	var definitions_by_role := {}
	var patch_definitions: Array[Dictionary] = []
	for definition: Dictionary in definitions:
		var polygon: PackedVector2Array = definition.get("points", PackedVector2Array())
		if not _expect(polygon.size() >= 3 and absf(_polygon_area(polygon)) > 1.0, "%s generated surface polygon should follow a non-empty track section" % theme):
			return false
		definitions_by_role[StringName(definition.get("role", &""))] = definition
		if StringName(definition.get("role", &"")) == &"patch":
			patch_definitions.append(definition)
	if not _expect(definitions_by_role.has(&"technical") and definitions_by_role.has(&"shortcut"), "%s should expose technical and shortcut surface roles" % theme):
		return false
	if not _expect(patch_definitions.size() >= BUILDER.GRIP_PATCH_MIN_COUNT and patch_definitions.size() <= BUILDER.GRIP_PATCH_MAX_COUNT, "%s should expose 4-8 deterministic grip-patch definitions" % theme):
		return false
	var gate_positions := PackedVector2Array()
	for checkpoint_index in 8:
		var checkpoint := track.get_node_or_null("Checkpoint0Finish" if checkpoint_index == 0 else "Checkpoint%d" % checkpoint_index) as Node2D
		if checkpoint:
			gate_positions.append(checkpoint.position)
	for patch_definition: Dictionary in patch_definitions:
		var patch_index := int(patch_definition.get("centerline_index", -1))
		var patch_polygon: PackedVector2Array = patch_definition.get("points", PackedVector2Array())
		if not _expect(patch_index >= 0 and _minimum_point_distance(centerline[patch_index], gate_positions) >= 155.0, "%s grip patches should stay clear of start, finish, and checkpoint gates" % theme):
			return false
		for point: Vector2 in patch_polygon:
			if not _expect(_minimum_point_distance(point, centerline) <= BUILDER.HALF_WIDTH, "%s grip patches should remain inside the drivable corridor" % theme):
				return false
	var technical_surface := track.get_node_or_null("GeneratedMoments/TechnicalSurfaceMoment")
	var shortcut := track.get_node_or_null("GeneratedMoments/ShortcutDecision")
	if not _expect(technical_surface != null and shortcut != null, "%s should expose technical and shortcut moments" % theme):
		return false
	if not _expect(technical_surface.get_child_count() == 7 and shortcut.get_child_count() == 7, "%s surfaces should use seven readable decals without a rectangular zone overlay" % theme):
		return false
	if not _expect(track.find_children("SurfaceTint", "Polygon2D", true, false).is_empty(), "%s should not render gameplay-zone rectangles under surface art" % theme):
		return false
	for surface_moment: Node2D in [technical_surface, shortcut]:
		var decals := surface_moment.find_children("CenterlineDecal*", "Sprite2D", false, false)
		if not _expect(decals.size() == 7, "%s should retain its themed surface cues when the overlay is removed" % theme):
			return false
	var shortcut_path: PackedVector2Array = shortcut.get_meta("shortcut_path", PackedVector2Array())
	var safe_path: PackedVector2Array = shortcut.get_meta("safe_path", PackedVector2Array())
	var shortcut_polygon: PackedVector2Array = shortcut.get_meta("polygon", PackedVector2Array())
	var shortcut_definition: Dictionary = definitions_by_role[&"shortcut"]
	if not _expect(shortcut_path.size() == safe_path.size() and shortcut_path.size() > 8, "%s shortcut should expose comparable risk and safe paths" % theme):
		return false
	if not _expect(float(shortcut.get_meta("shortcut_length", INF)) + 1.0 < float(shortcut.get_meta("safe_length", 0.0)), "%s risk lane should be geometrically shorter than the safe lane" % theme):
		return false
	var path_middle := shortcut_path.size() / 2
	if not _expect(Geometry2D.is_point_in_polygon(shortcut_path[path_middle], shortcut_polygon) and not Geometry2D.is_point_in_polygon(safe_path[path_middle], shortcut_polygon), "%s shortcut surface should cover only the risky inside lane" % theme):
		return false
	if not _expect(float(shortcut_definition["grip"]) < 0.7 and float(shortcut_definition["speed"]) > 1.0, "%s shortcut should trade lower grip for a faster route" % theme):
		return false
	var racing_line := track.get_node_or_null("RacingLine") as Line2D
	var shortcut_racing_line := track.get_node_or_null("ShortcutRacingLine") as Line2D
	var shortcut_index := int(shortcut.get_meta("centerline_index", -1))
	if not _expect(racing_line != null and shortcut_index >= 0 and not Geometry2D.is_point_in_polygon(racing_line.points[shortcut_index], shortcut_polygon), "%s generated AI line should take the safe lane around the optional shortcut" % theme):
		return false
	if not _expect(shortcut_racing_line != null and bool(shortcut_racing_line.get_meta("ai_path_clear", false)) and Geometry2D.is_point_in_polygon(shortcut_racing_line.points[shortcut_index], shortcut_polygon), "%s should expose a metadata-cleared AI line through the risky shortcut lane" % theme):
		return false
	var max_apex_offset := 0.0
	for line_index in centerline.size():
		if BUILDER._cyclic_index_distance(line_index, shortcut_index, centerline.size()) <= BUILDER.SHORTCUT_HALF_SPAN + 6:
			continue
		max_apex_offset = maxf(max_apex_offset, racing_line.points[line_index].distance_to(centerline[line_index]))
	if not _expect(max_apex_offset > 42.0 and max_apex_offset <= BUILDER.APEX_MAX_INWARD_OFFSET + 0.5, "%s racing line should use a bounded sharp-corner apex beyond the old 40-unit cut" % theme):
		return false

	var presenter := PRESENTER.new() as TrackVariantPresenter
	track.add_child(presenter)
	presenter.configure(track, theme, false)
	if not _expect(presenter.surface_zones.size() == (definitions as Array).size(), "%s presenter should create one SurfaceZone per generated surface definition" % theme):
		return false
	var presented_patch_count := 0
	for zone: SurfaceZone in presenter.surface_zones:
		var collision := zone.get_node_or_null("SurfaceCollision") as CollisionPolygon2D
		if not _expect(collision != null and not collision.polygon.is_empty(), "%s generated SurfaceZone should have a polygon" % theme):
			return false
		if StringName(zone.get_meta("role", &"")) == &"patch":
			presented_patch_count += 1
	if not _expect(presented_patch_count == patch_definitions.size(), "%s grip patches should become authoritative runtime SurfaceZones" % theme):
		return false
	var hazard_plan: Dictionary = track.get_meta("generated_hazard_plan", {})
	var forward_hazard_path: PackedVector2Array = hazard_paths["forward"]
	if bool(hazard_plan.get("present", false)):
		if not _expect(presenter.hazard != null and presenter.hazard.start_position == forward_hazard_path[0] and presenter.hazard.end_position == forward_hazard_path[1] and StringName(presenter.hazard.get_meta("direction", &"")) == &"forward", "%s forward race should use the forward conflict path when its deterministic plan is present" % theme):
			return false
	elif not _expect(presenter.hazard == null, "%s should omit an occasional hazard when its deterministic plan says absent" % theme):
		return false
	presenter.free()
	var reverse_presenter := PRESENTER.new() as TrackVariantPresenter
	track.add_child(reverse_presenter)
	reverse_presenter.configure(track, theme, true)
	var reverse_hazard_path: PackedVector2Array = hazard_paths["reverse"]
	if bool(hazard_plan.get("present", false)):
		if not _expect(reverse_presenter.hazard != null and reverse_presenter.hazard.start_position == reverse_hazard_path[0] and reverse_presenter.hazard.end_position == reverse_hazard_path[1] and StringName(reverse_presenter.hazard.get_meta("direction", &"")) == &"reverse", "%s reverse race should use the reverse conflict path when its deterministic plan is present" % theme):
			return false
	elif not _expect(reverse_presenter.hazard == null, "%s reverse race should share the same absent hazard plan" % theme):
		return false
	return true


func _check_wide_triangle_regression() -> bool:
	var built: Dictionary = BUILDER.build_packed(&"kitchen", &"wide", 9)
	if not _expect(built.get("scene") is PackedScene, "kitchen/wide/9 should build its broad-triangle regression track"):
		return false
	var track := (built["scene"] as PackedScene).instantiate() as Node2D
	_built_count += 1
	var valid := _check_island_geometry(track, "kitchen/wide/9")
	track.free()
	return valid


func _check_boundary_room_regressions() -> bool:
	for sample: Dictionary in [
		{"theme": &"kitchen", "room": &"long", "seed": 3},
		{"theme": &"office", "room": &"el", "seed": 8},
	]:
		var built: Dictionary = BUILDER.build_packed(sample["theme"], sample["room"], sample["seed"])
		if not _expect(built.get("scene") is PackedScene, "%s/%s/%d should build its boundary regression track" % [sample["theme"], sample["room"], sample["seed"]]):
			return false
		var track := (built["scene"] as PackedScene).instantiate() as Node2D
		_built_count += 1
		var valid := _check_open_boundary_assets(track, sample["theme"], sample["seed"])
		track.free()
		if not valid:
			return false
	return true


func _check_legacy_builder_scale() -> bool:
	var base_bounds := _points_bounds(BUILDER.BASE_ROOM_SHAPES["classic"])
	var generated_bounds := _points_bounds(BUILDER.ROOM_SHAPES["classic"])
	return _expect(base_bounds.size == Vector2(1750.0, 1150.0) and generated_bounds.size.is_equal_approx(base_bounds.size * BUILDER.WORLD_SCALE), "negative-seed canonical rooms should stay unscaled while generated rooms use world scale")


func _check_shadow_helpers() -> bool:
	var sample := Node2D.new()
	BUILDER._add_obstacle(sample, "RectObstacle", Vector2.ZERO, 32.0, "res://assets/textures/kitchen/ruler_plank.png")
	BUILDER._add_prop_with_collision(sample, Vector2(120.0, 0.0), 28.0, "res://assets/textures/kitchen/apple_cartoon.png")
	var obstacle := sample.get_node_or_null("RectObstacle") as StaticBody2D
	var apron := sample.get_node_or_null("ApronProp") as StaticBody2D
	var obstacle_shadow := obstacle.get_node_or_null("ContactShadow") as Sprite2D if obstacle else null
	var apron_shadow := apron.get_node_or_null("ContactShadow") as Sprite2D if apron else null
	var valid := _expect(
		obstacle_shadow != null
		and apron_shadow != null
		and StringName(obstacle_shadow.get_meta("shadow_shape", &"")) == &"rect"
		and StringName(apron_shadow.get_meta("shadow_shape", &"")) == &"circle"
		and obstacle_shadow.position.dot(BUILDER.SHADOW_DIRECTION) > 0.0
		and apron_shadow.position.dot(BUILDER.SHADOW_DIRECTION) > 0.0,
		"obstacles and apron props should share the shape-aware down-right shadow system"
	)
	sample.free()
	return valid


func _check_island_geometry(track: Node2D, label: String) -> bool:
	var barrier := track.get_node_or_null("InnerBarrier")
	var boundary_collision := barrier.get_node_or_null("BoundaryCollision") as CollisionShape2D if barrier else null
	if not _expect(boundary_collision != null and boundary_collision.shape is ConcavePolygonShape2D, "%s should have one physical island boundary" % label):
		return false
	var island_polygon: PackedVector2Array = barrier.get_meta("boundary_polygon", PackedVector2Array())
	var collision_polygon: PackedVector2Array = barrier.get_meta("collision_boundary_polygon", PackedVector2Array())
	if not _expect(island_polygon.size() > 20, "%s island collision should follow the generated inner loop" % label):
		return false
	if not _expect(not _has_self_intersection(island_polygon), "%s island collision should be a simple polygon" % label):
		return false
	if not _expect(collision_polygon.size() >= 3 and track.get_meta("island_invalid_polygon", PackedVector2Array()) == collision_polygon, "%s recovery should begin at the raised rim's physical contact edge" % label):
		return false
	var side_face := barrier.get_node_or_null("SideFace") as Line2D
	var textured_rim := barrier.get_node_or_null("TexturedRim") as Line2D
	var top_lip := barrier.get_node_or_null("TopLip") as Line2D
	if not _expect(side_face != null and textured_rim != null and top_lip != null and side_face.closed and textured_rim.closed and top_lip.closed, "%s island collision should be backed by a closed raised side face, textured rim, and top lip" % label):
		return false
	if not _expect(side_face.points == island_polygon and textured_rim.points == island_polygon and top_lip.points == island_polygon and textured_rim.texture != null, "%s raised island visuals should follow the exact physical contour" % label):
		return false
	for collision_point: Vector2 in collision_polygon:
		var visual_clearance := INF
		for point_index in island_polygon.size():
			visual_clearance = minf(visual_clearance, BUILDER._point_to_segment_distance(collision_point, island_polygon[point_index], island_polygon[(point_index + 1) % island_polygon.size()]))
		if not _expect(visual_clearance <= BUILDER.ISLAND_TEXTURED_RIM_WIDTH * 0.5 + 1.0, "%s island recovery boundary must remain under the visible textured rim" % label):
			return false
	var rim_landmarks := track.get_node_or_null("IslandRimLandmarks")
	if not _expect(rim_landmarks != null and int(rim_landmarks.get_meta("placed_count", 0)) == 3 and rim_landmarks.get_child_count() == 3, "%s raised island should carry three colliding edge landmarks for scale" % label):
		return false
	for landmark: StaticBody2D in rim_landmarks.get_children():
		if not _expect(landmark.collision_layer == 16 and landmark.get_node_or_null("Sprite") is Sprite2D and landmark.find_children("*", "CollisionShape2D", true, false).size() == 1, "%s island edge landmark should be one visible colliding asset" % label):
			return false
	for grid_name in ["GridForward", "GridReverse"]:
		var grid := track.get_node_or_null(grid_name)
		if not _expect(grid != null and grid.get_child_count() == 4, "%s should build %s" % [label, grid_name]):
			return false
		for marker: Node2D in grid.get_children():
			if not _expect(not Geometry2D.is_point_in_polygon(marker.position, island_polygon), "%s %s marker should not overlap the island collision" % [label, grid_name]):
				return false
	return true


func _check_open_boundary_assets(track: Node2D, theme: StringName, seed: int) -> bool:
	var label := "%s seed %d" % [theme, seed]
	if not _expect(track.get_node_or_null("OuterBarrier") == null and track.get_node_or_null("ContinuousBoundaryBacking") == null, "%s open apron must not contain a continuous outer collider or contour rim" % label):
		return false
	var track_surface := track.get_node("TrackSurface") as Line2D
	var centerline := track_surface.points
	if not _expect(absf(track_surface.width - BUILDER.HALF_WIDTH * 2.0) < 0.1, "%s visible road should reach the full legal corridor edge" % label):
		return false
	var visuals := track.get_node_or_null("GeneratedOuterBoundaryVisuals")
	var expected: Dictionary = BUILDER.LAYOUTS[theme]["generated_boundary"]
	if not _expect(visuals != null and String(visuals.get_meta("section_asset", "")) == String(expected["section"]) and String(visuals.get_meta("accent_asset", "")) == String(expected["accent"]), "%s sparse boundary assets should use only their theme-specific kit" % label):
		return false
	var expected_sections: Array = expected.get("sections", [expected["section"]])
	for section_asset: String in expected_sections:
		if not _expect(load(section_asset) is Texture2D, "%s boundary rail should be a tracked loadable asset: %s" % [label, section_asset]):
			return false
	var sections: Array[StaticBody2D] = []
	var accents: Array[StaticBody2D] = []
	for child: Node in visuals.get_children():
		if child.name.contains("Section") and child is StaticBody2D:
			sections.append(child as StaticBody2D)
		elif child.name.begins_with("CornerAccent") and child is StaticBody2D:
			accents.append(child as StaticBody2D)
	if not _expect(sections.size() == int(visuals.get_meta("section_count", 0)) and sections.size() >= 24 and sections.size() <= 84, "%s should retain extended but partial real-asset rail sections (count=%d)" % [label, sections.size()]):
		return false
	if not _expect(accents.size() == int(visuals.get_meta("accent_count", 0)) and accents.size() in [1, 2], "%s should retain one or two visual corner-mouth accents" % label):
		return false
	var run_modes: Array = visuals.get_meta("run_modes", [])
	var sides_by_run := {}
	for section: StaticBody2D in sections:
		var run_index := int(section.get_meta("run_index", -1))
		var centerline_index := int(section.get_meta("centerline_index", -1))
		var run_center := int(round((float(run_index) + 0.5) * float(centerline.size()) / 8.0)) % centerline.size()
		var positioned_index := int(BUILDER._closest_point_on_loop(section.position, centerline)["index"])
		if not _expect(run_index in range(8) and centerline_index >= 0 and BUILDER._cyclic_index_distance(centerline_index, run_center, centerline.size()) < centerline.size() / 16 and BUILDER._cyclic_index_distance(positioned_index, run_center, centerline.size()) < centerline.size() / 16, "%s rail section should stay inside its assigned visual sector" % label):
			return false
		var sprite := section.get_node_or_null("Sprite") as Sprite2D
		var collision := section.get_node_or_null("RailCollision") as CollisionShape2D
		if not _expect(section.collision_layer == 16 and sprite != null and sprite.texture != null and collision != null and (collision.shape is RectangleShape2D or collision.shape is ConvexPolygonShape2D), "%s every colliding rail must be a footprint-matched visible asset" % label):
			return false
		var footprint_size: Vector2 = section.get_meta("footprint_size", Vector2.ZERO)
		if not _expect(footprint_size != Vector2.ZERO and BUILDER._line_sweep_clears_footprint(centerline, section.position, footprint_size, &"rect", section.rotation, BUILDER.HALF_WIDTH + BUILDER.APRON_COLLIDER_CLEARANCE) and String(section.get_meta("asset_path", "")) in expected_sections, "%s real rail footprint should clear the corridor apron and use the themed kit" % label):
			return false
		var sides: Dictionary = sides_by_run.get(run_index, {})
		sides[StringName(section.get_meta("boundary_side", &""))] = true
		sides_by_run[run_index] = sides
	var actual_empty_runs := 0
	var actual_one_sided_runs := 0
	var actual_both_sided_runs := 0
	if not _expect(run_modes.size() == 8, "%s should expose eight authored boundary sectors" % label):
		return false
	for run_index in 8:
		var sides: Dictionary = sides_by_run.get(run_index, {})
		var actual_mode := &"both" if sides.has(&"outer") and sides.has(&"inner") else (&"outer" if sides.has(&"outer") else (&"inner" if sides.has(&"inner") else &"none"))
		if not _expect(StringName(run_modes[run_index]) == actual_mode, "%s run %d metadata should match its placed real assets" % [label, run_index]):
			return false
		if actual_mode == &"none":
			actual_empty_runs += 1
		elif actual_mode == &"both":
			actual_both_sided_runs += 1
		else:
			actual_one_sided_runs += 1
	if not _expect(actual_empty_runs == 1 and actual_one_sided_runs in [2, 3] and actual_both_sided_runs in [4, 5], "%s should retain one open sector and a strong mix of one- and both-sided sectors (empty=%d one-sided=%d both=%d modes=%s)" % [label, actual_empty_runs, actual_one_sided_runs, actual_both_sided_runs, str(run_modes)]):
		return false
	var inner_runs := int(visuals.get_meta("inner_run_count", 0))
	var outer_runs := int(visuals.get_meta("outer_run_count", 0))
	if not _expect(inner_runs + outer_runs >= 11 and inner_runs >= 5 and outer_runs >= 5, "%s sparse rails should retain balanced sector coverage without sacrificing clearance" % label):
		return false
	if not _expect(visuals.find_children("EmptyRunHint", "Sprite2D", false, false).size() == 1, "%s should mark its open sector with one flat worn-floor hint" % label):
		return false
	for accent: StaticBody2D in accents:
		var sprite := accent.get_node_or_null("Sprite") as Sprite2D
		var collision := accent.get_node_or_null("AssetCollision") as CollisionShape2D
		if not _expect(sprite != null and sprite.texture != null and collision != null and accent.collision_layer == 16 and StringName(accent.get_meta("boundary_kind", &"")) == &"corner_mouth_accent" and StringName(accent.get_meta("collision_contract", &"")) == BUILDER.COLLISION_SOLID, "%s physical corner accents should be footprint-matched visible boundary props" % label):
			return false
		var footprint_size: Vector2 = accent.get_meta("footprint_size", Vector2.ZERO)
		if not _expect(footprint_size != Vector2.ZERO and BUILDER._line_sweep_clears_footprint(centerline, accent.position, footprint_size, &"rect", accent.rotation, BUILDER.HALF_WIDTH + BUILDER.APRON_COLLIDER_CLEARANCE), "%s corner accent footprint should clear the corridor apron" % label):
			return false
	return _expect(_has_clear_open_apron_path(track, visuals, centerline), "%s open sector should expose a collider-free path from the racing corridor into the room apron" % label)


func _has_clear_open_apron_path(track: Node2D, visuals: Node, centerline: PackedVector2Array) -> bool:
	var run_modes: Array = visuals.get_meta("run_modes", [])
	var open_run := run_modes.find(&"none")
	if open_run < 0:
		return false
	var run_center := int(round((float(open_run) + 0.5) * float(centerline.size()) / 8.0)) % centerline.size()
	var room_polygon: PackedVector2Array = track.get_meta("room_polygon", PackedVector2Array())
	var island_polygon: PackedVector2Array = track.get_meta("island_invalid_polygon", PackedVector2Array())
	for center_offset in range(-12, 13, 3):
		var center_index := posmod(run_center + center_offset, centerline.size())
		var tangent: Vector2 = (centerline[(center_index + 1) % centerline.size()] - centerline[(center_index - 1 + centerline.size()) % centerline.size()]).normalized()
		var normal: Vector2 = tangent.rotated(PI * 0.5)
		for side: float in [-1.0, 1.0]:
			for distance: float in [210.0, 280.0, 360.0]:
				var target: Vector2 = centerline[center_index] + normal * distance * side
				if not Geometry2D.is_point_in_polygon(target, room_polygon) or Geometry2D.is_point_in_polygon(target, island_polygon):
					continue
				var clear_path := true
				for step in 7:
					var sample := centerline[center_index].lerp(target, float(step + 1) / 7.0)
					if not _point_clear_of_static_colliders(track, sample, 16.0):
						clear_path = false
						break
				if clear_path:
					return true
	return false


func _check_corridor_gates(track: Node2D, label: String) -> bool:
	var room_polygon: PackedVector2Array = track.get_meta("room_polygon", PackedVector2Array())
	var island_polygon: PackedVector2Array = track.get_meta("island_invalid_polygon", PackedVector2Array())
	var minimum_span := INF
	var maximum_span := 0.0
	for gate_index in BUILDER.GATE_COUNT:
		var checkpoint := track.get_node_or_null("Checkpoint0Finish" if gate_index == 0 else "Checkpoint%d" % gate_index) as Area2D
		if not _expect(checkpoint != null and bool(checkpoint.get_meta("sensor_asymmetric_span", false)), "%s gate %d should declare an inner-capped, outer-apron sensor" % [label, gate_index]):
			return false
		var endpoints: PackedVector2Array = checkpoint.get_meta("sensor_endpoints", PackedVector2Array())
		var span := float(checkpoint.get_meta("sensor_span", 0.0))
		var collision := checkpoint.get_node_or_null("CollisionShape2D") as CollisionShape2D
		var shape := collision.shape as RectangleShape2D if collision else null
		if not _expect(endpoints.size() == 2 and shape != null and span >= BUILDER.HALF_WIDTH * 2.0 - 0.5 and shape.size.y >= span, "%s gate %d sensor should cover the corridor and any available legal outer apron (endpoints=%d span=%.1f shape=%s)" % [label, gate_index, endpoints.size(), span, shape.size if shape else Vector2.ZERO]):
			return false
		var local_a := collision.position + Vector2(0.0, -shape.size.y * 0.5)
		var local_b := collision.position + Vector2(0.0, shape.size.y * 0.5)
		var world_a := checkpoint.transform * local_a
		var world_b := checkpoint.transform * local_b
		if not _expect(minf(world_a.distance_to(endpoints[0]), world_a.distance_to(endpoints[1])) <= 5.0 and minf(world_b.distance_to(endpoints[0]), world_b.distance_to(endpoints[1])) <= 5.0, "%s gate %d collision rectangle should physically reach both recorded corridor ends" % [label, gate_index]):
			return false
		var inner_end: Vector2 = checkpoint.get_meta("sensor_inner_endpoint", Vector2.ZERO)
		var outer_end: Vector2 = checkpoint.get_meta("sensor_outer_endpoint", Vector2.ZERO)
		if not _expect(inner_end == endpoints[0] and outer_end == endpoints[1], "%s gate %d should expose its locally resolved island and apron sides" % [label, gate_index]):
			return false
		if not _expect(checkpoint.position.distance_to(inner_end) <= BUILDER.HALF_WIDTH + 0.5 and checkpoint.position.distance_to(outer_end) >= BUILDER.HALF_WIDTH - 0.5, "%s gate %d should cap its island side and retain the full outer corridor" % [label, gate_index]):
			return false
		var inner_dir := inner_end - checkpoint.position
		if inner_dir.length_squared() > 1.0:
			inner_dir = inner_dir.normalized()
			var ribbon := checkpoint.position + inner_dir * minf(checkpoint.position.distance_to(inner_end) * 0.45, BUILDER.HALF_WIDTH * 0.45)
			var grass := checkpoint.position + inner_dir * (BUILDER.HALF_WIDTH + 36.0)
			if not _expect(_checkpoint_contains_world(checkpoint, ribbon), "%s gate %d should still count a car on the racing ribbon" % [label, gate_index]):
				return false
			if Geometry2D.is_point_in_polygon(grass, room_polygon) and not Geometry2D.is_point_in_polygon(grass, island_polygon):
				if not _expect(not _checkpoint_contains_world(checkpoint, grass), "%s gate %d must not count an inner-grass corner cut" % [label, gate_index]):
					return false
		if checkpoint.position.distance_to(outer_end) > BUILDER.HALF_WIDTH + 8.0:
			var outer_dir := (outer_end - checkpoint.position).normalized()
			var outer_apron := checkpoint.position + outer_dir * minf(BUILDER.HALF_WIDTH + 36.0, checkpoint.position.distance_to(outer_end) - 4.0)
			if not _expect(_checkpoint_contains_world(checkpoint, outer_apron), "%s gate %d should count a legal outer-apron line" % [label, gate_index]):
				return false
		minimum_span = minf(minimum_span, span)
		maximum_span = maxf(maximum_span, span)
	var posts := track.get_node_or_null("GatePosts")
	if not _expect(posts != null and int(posts.get_meta("placed_count", 0)) == BUILDER.GATE_COUNT * 2 and posts.get_child_count() == BUILDER.GATE_COUNT * 2, "%s should place two visible colliding posts at every nominal corridor gate" % label):
		return false
	for post: StaticBody2D in posts.get_children():
		var sprite := post.get_node_or_null("Sprite") as Sprite2D
		var collision := post.get_node_or_null("PostCollision") as CollisionShape2D
		var checkpoint := track.get_node_or_null("Checkpoint0Finish" if int(post.get_meta("gate_index", -1)) == 0 else "Checkpoint%d" % int(post.get_meta("gate_index", -1))) as Node2D
		var expected_offset := BUILDER.FINISH_LANDMARK_OFFSET if int(post.get_meta("gate_index", -1)) == 0 else BUILDER.GATE_POST_OFFSET
		if not _expect(sprite != null and sprite.texture != null and collision != null and post.collision_layer == 16 and absf(post.position.distance_to(checkpoint.position) - expected_offset) < 1.0, "%s gate post should be a visible collider just outside the racing line" % label):
			return false
	track.set_meta("tested_gate_span_range", Vector2(minimum_span, maximum_span))
	_minimum_gate_span = minf(_minimum_gate_span, minimum_span)
	_maximum_gate_span = maxf(_maximum_gate_span, maximum_span)
	return true


func _checkpoint_contains_world(checkpoint: Area2D, point: Vector2) -> bool:
	var collision := checkpoint.get_node("CollisionShape2D") as CollisionShape2D
	var shape := collision.shape as RectangleShape2D
	var local := checkpoint.transform.affine_inverse() * point - collision.position
	var half := shape.size * 0.5
	return absf(local.x) <= half.x and absf(local.y) <= half.y


func _check_visible_collision_backing(track: Node2D, label: String) -> bool:
	for node: Node in track.find_children("*", "StaticBody2D", true, false):
		var body := node as StaticBody2D
		if body.find_children("*", "CollisionShape2D", true, false).is_empty() and body.find_children("*", "CollisionPolygon2D", true, false).is_empty():
			continue
		if not _expect(_static_body_has_visible_backing(body), "%s collider %s must sit within a visible sprite, wall, or raised rim" % [label, str(track.get_path_to(body))]):
			return false
	return true


func _static_body_has_visible_backing(body: StaticBody2D) -> bool:
	for descendant: Node in body.find_children("*", "", true, false):
		if descendant is Sprite2D and descendant.name not in [&"ContactShadow", &"CastShadow"] and (descendant as Sprite2D).texture != null:
			return true
		if descendant is Polygon2D or descendant is Line2D:
			return true
	var shared_visual := body.get_parent().get_node_or_null("Sprite") as Sprite2D if body.get_parent() else null
	if shared_visual != null and shared_visual.texture != null and StringName(shared_visual.get_meta("collision_contract", &"")) == BUILDER.COLLISION_SOLID and String(shared_visual.get_meta("asset_path", "")) == String(body.get_meta("asset_path", "")):
		return true
	return false


func _point_clear_of_static_colliders(track: Node2D, point: Vector2, clearance: float) -> bool:
	var world_point := track.to_global(point)
	for node: Node in track.find_children("*", "StaticBody2D", true, false):
		var body := node as StaticBody2D
		for collision_node: Node in body.get_children():
			if collision_node is CollisionShape2D:
				var collision := collision_node as CollisionShape2D
				var local_point := collision.to_local(world_point)
				if collision.shape is CircleShape2D and local_point.length() <= (collision.shape as CircleShape2D).radius + clearance:
					return false
				if collision.shape is RectangleShape2D:
					var half := (collision.shape as RectangleShape2D).size * 0.5 + Vector2.ONE * clearance
					if absf(local_point.x) <= half.x and absf(local_point.y) <= half.y:
						return false
				if collision.shape is ConcavePolygonShape2D:
					var segments: PackedVector2Array = (collision.shape as ConcavePolygonShape2D).segments
					for segment_index in range(0, segments.size(), 2):
						if _point_to_segment_distance(local_point, segments[segment_index], segments[segment_index + 1]) <= clearance:
							return false
			elif collision_node is CollisionPolygon2D:
				var polygon_node := collision_node as CollisionPolygon2D
				if Geometry2D.is_point_in_polygon(polygon_node.to_local(world_point), polygon_node.polygon):
					return false
	return true


func _distance_to_polygon_edge(point: Vector2, polygon: PackedVector2Array) -> float:
	if polygon.is_empty():
		return INF
	var nearest := INF
	for index in polygon.size():
		nearest = minf(nearest, _point_to_segment_distance(point, polygon[index], polygon[(index + 1) % polygon.size()]))
	return nearest


func _point_to_segment_distance(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment := to - from
	if segment.length_squared() < 0.001:
		return point.distance_to(from)
	var fraction := clampf((point - from).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(from + segment * fraction)


func _check_story_assets(theme: StringName) -> bool:
	for asset_path: String in BUILDER.LAYOUTS[theme].get("edge_decor", []):
		if not _expect(load(asset_path) is Texture2D, "%s is missing edge decor asset %s" % [theme, asset_path]):
			return false
	for asset_path: String in BUILDER.LAYOUTS[theme].get("giants", []):
		if not _expect(load(asset_path) is Texture2D, "%s is missing giant landmark asset %s" % [theme, asset_path]):
			return false
	for asset_path: String in BUILDER.LAYOUTS[theme].get("corridor_patterns", []):
		if not _expect(load(asset_path) is Texture2D, "%s is missing corridor pattern asset %s" % [theme, asset_path]):
			return false
	for patch: Dictionary in BUILDER.LAYOUTS[theme].get("grip_patches", []):
		if not _expect(load(String(patch["decal"])) is Texture2D, "%s is missing grip patch asset %s" % [theme, patch["decal"]]):
			return false
	for ground_section: Dictionary in BUILDER.LAYOUTS[theme].get("ground_sections", []):
		if not _expect(load(String(ground_section["asset"])) is Texture2D, "%s is missing ground section asset %s" % [theme, ground_section["asset"]]):
			return false
	for boundary_asset: String in BUILDER.LAYOUTS[theme].get("generated_boundary", {}).get("sections", []):
		if not _expect(load(boundary_asset) is Texture2D, "%s is missing boundary rail asset %s" % [theme, boundary_asset]):
			return false
	for kit: Dictionary in BUILDER.STORY_KITS[theme]:
		for formation: Dictionary in kit["island"]:
			if not _expect(load(String(formation["asset"])) is Texture2D, "%s/%s is missing island asset %s" % [theme, kit["id"], formation["asset"]]):
				return false
		for field: String in ["object_line", "delimiter"]:
			if not _expect(load(String(kit[field]["asset"])) is Texture2D, "%s/%s is missing %s asset %s" % [theme, kit["id"], field, kit[field]["asset"]]):
				return false
		for landmark: String in kit["landmarks"]:
			if not _expect(load(landmark) is Texture2D, "%s/%s is missing landmark %s" % [theme, kit["id"], landmark]):
				return false
		for surface: Dictionary in kit["surfaces"]:
			if not _expect(load(String(surface["decal"])) is Texture2D, "%s/%s is missing surface decal %s" % [theme, kit["id"], surface["decal"]]):
				return false
	return true


func _check_density_systems(track: Node2D, theme: StringName, seed: int) -> bool:
	var label := "%s seed %d" % [theme, seed]
	var centerline := (track.get_node("TrackSurface") as Line2D).points
	var room_shape := StringName(track.get_meta("room_shape", &"classic"))
	var room_polygon: PackedVector2Array = BUILDER.ROOM_SHAPES[room_shape]
	var patterns := track.get_node_or_null("CorridorPatterns")
	if not _expect(patterns != null and int(patterns.get_meta("placed_count", 0)) == 32 and patterns.get_child_count() == 32, "%s should place 32 subtle corridor-pattern sprites" % label):
		return false
	for pattern: Sprite2D in patterns.get_children():
		var distance := _minimum_point_distance(pattern.position, centerline)
		if not _expect(pattern.texture != null and distance < BUILDER.HALF_WIDTH and pattern.z_index == -8, "%s corridor patterns should stay visual-only inside the road" % label):
			return false

	var edge_decor := track.get_node_or_null("GeneratedMoments/EdgeApronDecor")
	var edge_count := int(edge_decor.get_meta("placed_count", 0)) if edge_decor else 0
	if not _expect(edge_decor != null and edge_count >= 60 and edge_count <= 150 and edge_decor.get_child_count() == edge_count, "%s should place 60-150 classified edge and apron details (got %d)" % [label, edge_count]):
		return false
	for decor: Node in edge_decor.get_children():
		var sprite := decor as Sprite2D if decor is Sprite2D else decor.get_node_or_null("Sprite") as Sprite2D
		var contract := StringName(decor.get_meta("collision_contract", &""))
		if decor is StaticBody2D:
			if not _expect(contract == BUILDER.COLLISION_SOLID and not decor.find_children("*", "CollisionShape2D", true, false).is_empty(), "%s solid-looking edge objects should carry physical scenery collision" % label):
				return false
			var clearance_radius := float(decor.get_meta("placement_clearance_radius", 0.0))
			if not _expect(clearance_radius > 0.0 and BUILDER._distance_to_centerline((decor as Node2D).position, centerline) >= BUILDER.HALF_WIDTH + clearance_radius + BUILDER.APRON_COLLIDER_CLEARANCE and BUILDER._inside_polygon_with_radius((decor as Node2D).position, clearance_radius, room_polygon), "%s solid edge object footprint should clear the corridor apron and stay inside the room" % label):
				return false
		else:
			if not _expect(decor is Sprite2D and contract == BUILDER.COLLISION_FLAT and not decor is CollisionObject2D, "%s painted edge details should remain explicitly FLAT presentation" % label):
				return false
		var decor_position := (decor as Node2D).position
		if not _expect(sprite != null and Geometry2D.is_point_in_polygon(decor_position, room_polygon) and _minimum_point_distance(decor_position, centerline) >= BUILDER.HALF_WIDTH + 8.0, "%s edge decor should stay inside the room and outside the drivable corridor" % label):
			return false

	var giants := track.get_node_or_null("GeneratedMoments/GiantLandmarks")
	var giant_count := int(giants.get_meta("placed_count", 0)) if giants else 0
	if not _expect(giants != null and giant_count >= 1 and giant_count <= 3 and giants.get_child_count() == giant_count, "%s should place 1-3 giant landmarks (got %d)" % [label, giant_count]):
		return false
	var colliding_giants := 0
	var allowed_giants: Array = BUILDER.LAYOUTS[theme].get("giants", [])
	for story: Dictionary in BUILDER.STORY_KITS[theme]:
		if StringName(story["id"]) == StringName(track.get_meta("story_id")):
			allowed_giants = story.get("giants", allowed_giants).duplicate()
			for formation: Dictionary in story["island"]:
				if StringName(formation["quantity"]) == &"unique":
					allowed_giants.erase(formation["asset"])
	var committed_racing_lines: Array[PackedVector2Array] = []
	for line_name: String in ["RacingLine", "ShortcutRacingLine"]:
		var line := track.get_node_or_null(line_name) as Line2D
		if line and not line.points.is_empty():
			committed_racing_lines.append(line.points)
	var seen_giant_assets := {}
	for landmark: Node2D in giants.get_children():
		var world_size := float(landmark.get_meta("world_size", 0.0))
		var footprint_size: Vector2 = landmark.get_meta("footprint_size", Vector2.ZERO)
		var asset_path := String(landmark.get_meta("asset_path", ""))
		if bool(BUILDER.LAYOUTS[theme].get("distinct_giant_assets", false)) and not _expect(not seen_giant_assets.has(asset_path), "%s giant landmarks should not repeat the same object" % label):
			return false
		seen_giant_assets[asset_path] = true
		if not _expect(asset_path in allowed_giants and ResourceLoader.exists(asset_path) and bool(BUILDER.PROP_SHAPES.get(asset_path.get_file(), {}).get("solid", false)) and world_size >= 300.0 and world_size <= 600.0, "%s giant landmarks should use registered 300-600u assets from their story roster" % label):
			return false
		var shape_kind := StringName(landmark.get_meta("footprint_kind", BUILDER.PROP_SHAPES.get(asset_path.get_file(), {}).get("shape", "circle")))
		var gate_samples := PackedVector2Array()
		for checkpoint_index in 8:
			var checkpoint := track.get_node_or_null("Checkpoint0Finish" if checkpoint_index == 0 else "Checkpoint%d" % checkpoint_index) as Node2D
			if checkpoint:
				gate_samples.append(checkpoint.position)
		var footprint_rotation := float(landmark.get_meta("footprint_rotation", 0.0))
		if not _expect(BUILDER._giant_placement_is_safe(landmark.position, footprint_size, shape_kind, landmark.rotation + footprint_rotation, room_polygon, centerline, gate_samples, [], committed_racing_lines), "%s giant landmark footprint should stay inside the room and clear of the corridor, racing-line hulls, walls, and gates" % label):
			return false
		var contact_shadow := landmark.get_node_or_null("ContactShadow") as Sprite2D
		var cast_shadow := landmark.get_node_or_null("CastShadow") as Sprite2D
		var contact_offset := contact_shadow.global_position - landmark.global_position if contact_shadow else Vector2.ZERO
		var cast_offset := cast_shadow.global_position - landmark.global_position if cast_shadow else Vector2.ZERO
		if not _expect(contact_shadow != null and cast_shadow != null and contact_offset.dot(BUILDER.SHADOW_DIRECTION) > 0.0 and cast_offset.dot(BUILDER.SHADOW_DIRECTION) > contact_offset.dot(BUILDER.SHADOW_DIRECTION), "%s giant landmark should carry grounded and elongated down-right shadows" % label):
			return false
		var body := landmark.get_node_or_null("GiantBody") as StaticBody2D
		if body:
			colliding_giants += 1
			var collision := body.get_child(0) as CollisionShape2D if body.get_child_count() > 0 else null
			if not _expect(body.collision_layer == (4 | 16) and StringName(body.get_meta("collision_contract", &"")) == BUILDER.COLLISION_SOLID and collision != null and collision.shape != null, "%s colliding giant should expose a valid SOLID scenery shape" % label):
				return false
	if not _expect(colliding_giants == giant_count, "%s every giant landmark should be SOLID physical scenery" % label):
		return false
	return true


func _check_room_dressing(track: Node2D, theme: StringName, seed: int) -> bool:
	var dressing := track.get_node_or_null("GeneratedMoments/RoomDressing")
	if not _expect(dressing != null, "%s seed %d should include ambient room dressing" % [theme, seed]):
		return false
	var placed_count := int(dressing.get_meta("placed_count", 0))
	var pocket_count := int(dressing.get_meta("pocket_count", 0))
	var ground_section_count := int(dressing.get_meta("ground_section_count", 0))
	var decal_count := int(dressing.get_meta("decal_count", 0))
	if not _expect(placed_count >= 12 and placed_count <= 18, "%s seed %d should fill safe blank space with a semantic many of 12-18 ambient props (got %d)" % [theme, seed, placed_count]):
		return false
	if not _expect(pocket_count >= 4 and pocket_count <= 6, "%s seed %d should distribute dressing across 4-6 pockets (got %d)" % [theme, seed, pocket_count]):
		return false
	for child: Node in dressing.get_children():
		if not child.name.begins_with("Pocket"):
			continue
		var pocket_placed := int(child.get_meta("placed_count", 0))
		if not _expect(pocket_placed >= 2 and pocket_placed <= 3, "%s seed %d ambient pockets should preserve the semantic few quantity (got %d)" % [theme, seed, pocket_placed]):
			return false
	var details := dressing.get_node_or_null("FloorDetails")
	if not _expect(details != null and details.get_child_count() == decal_count and decal_count >= 60, "%s seed %d should add 60-120 off-track floor details for visual density (got %d)" % [theme, seed, decal_count]):
		return false
	var centerline := (track.get_node("TrackSurface") as Line2D).points
	var room_shape := StringName(track.get_meta("room_shape", &"classic"))
	var room_polygon: PackedVector2Array = BUILDER.ROOM_SHAPES[room_shape]
	var bounds: Rect2 = _points_bounds(room_polygon)
	var ground := dressing.get_node_or_null("GroundSections")
	if not _expect(ground != null and ground.get_child_count() == ground_section_count and ground_section_count >= 2 and ground_section_count <= 4, "%s seed %d should add 2-4 broad ground sections (got %d)" % [theme, seed, ground_section_count]):
		return false
	var ground_assets := {}
	var ground_sectors := {}
	for child: Node in ground.get_children():
		if not _expect(child is Sprite2D and not child is StaticBody2D, "%s seed %d ground sections should be non-colliding sprites" % [theme, seed]):
			return false
		var section := child as Sprite2D
		var position := section.global_position
		var asset_path := String(section.get_meta("asset_path", ""))
		if not _expect(section.texture != null and asset_path.begins_with("res://assets/textures/ground_dressing/%s_" % theme), "%s seed %d ground section should use a theme-specific tracked texture" % [theme, seed]):
			return false
		if not _expect(Geometry2D.is_point_in_polygon(position, room_polygon), "%s seed %d ground section should stay inside the room" % [theme, seed]):
			return false
		if not _expect(_minimum_point_distance(position, centerline) >= BUILDER.HALF_WIDTH, "%s seed %d ground section center should stay off the racing corridor" % [theme, seed]):
			return false
		var used := Rect2(section.texture.get_image().get_used_rect())
		used.position -= section.texture.get_size() * 0.5
		for point in [used.position, Vector2(used.end.x, used.position.y), used.end, Vector2(used.position.x, used.end.y), used.get_center()]:
			var visual_point := section.to_global(point)
			if not _expect(Geometry2D.is_point_in_polygon(visual_point, room_polygon) and BUILDER._distance_to_centerline(visual_point, centerline) >= BUILDER.HALF_WIDTH + 8.0, "%s seed %d visible ground-section footprint must clear the racing path, not merely its center" % [theme, seed]):
				return false
		ground_assets[asset_path] = true
		var normalized: Vector2 = (position - bounds.position) / bounds.size
		ground_sectors[Vector2i(clampi(int(normalized.x * 3.0), 0, 2), clampi(int(normalized.y * 2.0), 0, 1))] = true
	if not _expect(ground_assets.size() == ground_section_count, "%s seed %d ground sections should not repeat assets" % [theme, seed]):
		return false
	if not _expect(ground_sectors.size() >= 2, "%s seed %d ground sections should occupy at least two room sectors" % [theme, seed]):
		return false
	var assets := {}
	var sectors := {}
	var prop_nodes := dressing.find_children("*", "StaticBody2D", true, false)
	if not _expect(prop_nodes.size() == placed_count, "%s seed %d dressing metadata should match its physical props" % [theme, seed]):
		return false
	for child: Node in prop_nodes:
		var prop := child as Node2D
		var position := prop.global_position
		if not _expect(Geometry2D.is_point_in_polygon(position, room_polygon), "%s seed %d ambient prop should stay inside the room" % [theme, seed]):
			return false
		if not _expect(_minimum_point_distance(position, centerline) >= 132.0, "%s seed %d ambient prop should stay outside the racing corridor" % [theme, seed]):
			return false
		assets[String(prop.get_meta("asset_path", ""))] = true
		var shadow := prop.get_node_or_null("ContactShadow") as Sprite2D
		var shadow_offset := shadow.global_position - prop.global_position if shadow else Vector2.ZERO
		if not _expect(shadow != null and shadow_offset.dot(BUILDER.SHADOW_DIRECTION) > 0.0 and StringName(shadow.get_meta("shadow_shape", &"")) in [&"circle", &"rect"], "%s seed %d ambient prop %s (asset=%s) should use the unified down-right shape-aware shadow (shadow=%s dot=%.3f)" % [theme, seed, prop.name, prop.get_meta("asset_path", "?"), shadow.name if shadow else "null", shadow_offset.dot(BUILDER.SHADOW_DIRECTION)]):
			return false
		var normalized: Vector2 = (position - bounds.position) / bounds.size
		sectors[Vector2i(clampi(int(normalized.x * 3.0), 0, 2), clampi(int(normalized.y * 2.0), 0, 1))] = true
	if not _expect(assets.size() >= 4, "%s seed %d ambient dressing should use at least four prop assets (got %d)" % [theme, seed, assets.size()]):
		return false
	if not _expect(sectors.size() >= 3, "%s seed %d ambient dressing should occupy at least three room sectors (got %d)" % [theme, seed, sectors.size()]):
		return false
	return true


func _minimum_point_distance(point: Vector2, points: PackedVector2Array) -> float:
	var minimum := INF
	for other: Vector2 in points:
		minimum = minf(minimum, point.distance_to(other))
	return minimum


func _points_bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


func _generated_asset_paths(track: Node) -> Array[String]:
	var paths: Array[String] = []
	_collect_asset_paths(track, paths)
	return paths


func _collect_asset_paths(node: Node, paths: Array[String]) -> void:
	if node.has_meta("asset_path"):
		paths.append(String(node.get_meta("asset_path")))
	for child: Node in node.get_children():
		_collect_asset_paths(child, paths)


func _collect_unique_prop_assets(node: Node, paths: Array[String]) -> void:
	if node is StaticBody2D and StringName(node.get_meta("semantic_quantity", &"")) == &"unique" and node.has_meta("asset_path"):
		paths.append(String(node.get_meta("asset_path")))
	for child: Node in node.get_children():
		_collect_unique_prop_assets(child, paths)


func _node_signature(track: Node2D) -> String:
	var parts: Array[String] = [
		String(track.get_meta("story_id", "")),
		String(track.get_meta("family", "")),
		str(track.get_meta("requested_seed", -1)),
		"%.3f" % float(track.get_meta("loop_length", 0.0)),
	]
	_append_node_signature(track, parts, "")
	var definitions: Array = track.get_meta("generated_surfaces", [])
	for definition: Dictionary in definitions:
		parts.append(String(definition["name"]))
		parts.append(String(definition.get("role", &"")))
		parts.append(String(definition.get("lane", &"")))
		for point: Vector2 in definition["points"]:
			parts.append("%.2f,%.2f" % [point.x, point.y])
	return "|".join(parts)


func _append_node_signature(node: Node, parts: Array[String], prefix: String) -> void:
	var stable_name := String(node.name)
	if stable_name.begins_with("@"):
		stable_name = "%s[%d]" % [node.get_class(), node.get_index()]
	var path := "%s/%s" % [prefix, stable_name]
	var entry := path
	if node is Node2D:
		var node_2d := node as Node2D
		entry += "@%.3f,%.3f,%.4f" % [node_2d.position.x, node_2d.position.y, node_2d.rotation]
	if node.has_meta("asset_path"):
		entry += "#" + String(node.get_meta("asset_path"))
	for key: String in ["moment_kind", "centerline_index", "direction", "lap_fraction", "inside_sign"]:
		if node.has_meta(key):
			entry += "#%s=%s" % [key, str(node.get_meta(key))]
	parts.append(entry)
	for child: Node in node.get_children():
		_append_node_signature(child, parts, path)


func _polygon_area(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in points.size():
		var next := (index + 1) % points.size()
		total += points[index].x * points[next].y - points[next].x * points[index].y
	return total * 0.5


func _open_path_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(1, points.size()):
		total += points[index - 1].distance_to(points[index])
	return total


func _has_self_intersection(points: PackedVector2Array) -> bool:
	for first in points.size():
		var first_next := (first + 1) % points.size()
		for second in range(first + 1, points.size()):
			var second_next := (second + 1) % points.size()
			if first == second or first_next == second or second_next == first:
				continue
			if Geometry2D.segment_intersects_segment(points[first], points[first_next], points[second], points[second_next]) != null:
				return true
	return false


func _first_signature_difference(first: String, second: String) -> String:
	var first_parts := first.split("|")
	var second_parts := second.split("|")
	for index in mini(first_parts.size(), second_parts.size()):
		if first_parts[index] != second_parts[index]:
			return "index %d: %s != %s" % [index, first_parts[index], second_parts[index]]
	return "part counts %d != %d" % [first_parts.size(), second_parts.size()]


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("GENERATED_TRACK_COMPOSITION_TEST FAIL: " + message)
	quit(1)
	return false
