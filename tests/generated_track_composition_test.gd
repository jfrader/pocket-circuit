extends SceneTree

const BUILDER := preload("res://tools/track_builder_core.gd")
const PRESENTER := preload("res://scripts/presentation/track_variant_presenter.gd")

const THEMES: Array[StringName] = [&"kitchen", &"workshop", &"office"]
const ROOMS: Array[StringName] = [&"classic", &"wide", &"tall", &"square"]
const SIGNATURE_ASSETS := {
	&"kitchen": "res://assets/textures/imagine/stove_top.png",
	&"workshop": "res://assets/textures/imagine/bucket_stack.png",
	&"office": "res://assets/textures/imagine/monitor_top.png",
}

var _built_count := 0


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
	print("GENERATED_TRACK_COMPOSITION_TEST PASS builds=%d stories=12 surfaces=24" % _built_count)
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

	var definitions: Variant = track.get_meta("generated_surfaces", null)
	if not _expect(definitions is Array and (definitions as Array).size() == 2, "%s should define exactly two generated surfaces" % theme):
		return false
	var definitions_by_role := {}
	for definition: Dictionary in definitions:
		var polygon: PackedVector2Array = definition.get("points", PackedVector2Array())
		if not _expect(polygon.size() >= 3 and absf(_polygon_area(polygon)) > 1.0, "%s generated surface polygon should follow a non-empty track section" % theme):
			return false
		definitions_by_role[StringName(definition.get("role", &""))] = definition
	if not _expect(definitions_by_role.has(&"technical") and definitions_by_role.has(&"shortcut"), "%s should expose technical and shortcut surface roles" % theme):
		return false
	var technical_surface := track.get_node_or_null("GeneratedMoments/TechnicalSurfaceMoment")
	var shortcut := track.get_node_or_null("GeneratedMoments/ShortcutDecision")
	if not _expect(technical_surface != null and shortcut != null, "%s should expose technical and shortcut moments" % theme):
		return false
	if not _expect(technical_surface.get_child_count() == 4 and shortcut.get_child_count() == 4, "%s surfaces should carry readable decal sprites" % theme):
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
	var shortcut_index := int(shortcut.get_meta("centerline_index", -1))
	if not _expect(racing_line != null and shortcut_index >= 0 and not Geometry2D.is_point_in_polygon(racing_line.points[shortcut_index], shortcut_polygon), "%s generated AI line should take the safe lane around the optional shortcut" % theme):
		return false

	var presenter := PRESENTER.new() as TrackVariantPresenter
	track.add_child(presenter)
	presenter.configure(track, theme, false)
	if not _expect(presenter.surface_zones.size() == 2, "%s presenter should consume exactly two generated surface definitions" % theme):
		return false
	for zone: SurfaceZone in presenter.surface_zones:
		var collision := zone.get_node_or_null("SurfaceCollision") as CollisionPolygon2D
		if not _expect(collision != null and not collision.polygon.is_empty(), "%s generated SurfaceZone should have a polygon" % theme):
			return false
	var forward_hazard_path: PackedVector2Array = hazard_paths["forward"]
	if not _expect(presenter.hazard.start_position == forward_hazard_path[0] and presenter.hazard.end_position == forward_hazard_path[1] and StringName(presenter.hazard.get_meta("direction", &"")) == &"forward", "%s forward race should use the forward conflict path" % theme):
		return false
	presenter.free()
	var reverse_presenter := PRESENTER.new() as TrackVariantPresenter
	track.add_child(reverse_presenter)
	reverse_presenter.configure(track, theme, true)
	var reverse_hazard_path: PackedVector2Array = hazard_paths["reverse"]
	if not _expect(reverse_presenter.hazard.start_position == reverse_hazard_path[0] and reverse_presenter.hazard.end_position == reverse_hazard_path[1] and StringName(reverse_presenter.hazard.get_meta("direction", &"")) == &"reverse", "%s reverse race should use the reverse conflict path" % theme):
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


func _check_island_geometry(track: Node2D, label: String) -> bool:
	var barrier := track.get_node_or_null("InnerBarrier")
	var boundary_collision := barrier.get_node_or_null("BoundaryCollision") as CollisionShape2D if barrier else null
	if not _expect(boundary_collision != null and boundary_collision.shape is ConcavePolygonShape2D, "%s should have one physical island boundary" % label):
		return false
	var island_polygon: PackedVector2Array = barrier.get_meta("boundary_polygon", PackedVector2Array())
	if not _expect(island_polygon.size() > 20, "%s island collision should follow the generated inner loop" % label):
		return false
	if not _expect(not _has_self_intersection(island_polygon), "%s island collision should be a simple polygon" % label):
		return false
	for grid_name in ["GridForward", "GridReverse"]:
		var grid := track.get_node_or_null(grid_name)
		if not _expect(grid != null and grid.get_child_count() == 4, "%s should build %s" % [label, grid_name]):
			return false
		for marker: Node2D in grid.get_children():
			if not _expect(not Geometry2D.is_point_in_polygon(marker.position, island_polygon), "%s %s marker should not overlap the island collision" % [label, grid_name]):
				return false
	return true


func _check_story_assets(theme: StringName) -> bool:
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


func _check_room_dressing(track: Node2D, theme: StringName, seed: int) -> bool:
	var dressing := track.get_node_or_null("GeneratedMoments/RoomDressing")
	if not _expect(dressing != null, "%s seed %d should include ambient room dressing" % [theme, seed]):
		return false
	var placed_count := int(dressing.get_meta("placed_count", 0))
	var pocket_count := int(dressing.get_meta("pocket_count", 0))
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
	if not _expect(details != null and details.get_child_count() == decal_count and decal_count >= 8, "%s seed %d should add at least eight off-track floor details" % [theme, seed]):
		return false
	var centerline := (track.get_node("TrackSurface") as Line2D).points
	var room_shape := StringName(track.get_meta("room_shape", &"classic"))
	var room_polygon: PackedVector2Array = BUILDER.ROOM_SHAPES[room_shape]
	var bounds: Rect2 = _points_bounds(room_polygon)
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
