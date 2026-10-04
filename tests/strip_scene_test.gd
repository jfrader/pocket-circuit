extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var prepared := BUILDER.prepare_layout(&"kitchen", &"classic", 42, {"route_shape": "strip"})
	if prepared.is_empty():
		_fail("Strip layout unavailable")
		return
	var root := BUILDER.create_layout_root(prepared)
	get_root().add_child(root)
	await BUILDER.assemble_runtime(root, prepared, Callable())
	var line := root.get_node_or_null("RacingLine") as Line2D
	var road := root.get_node_or_null("TrackSurface") as Line2D
	var start_cap := root.get_node_or_null("StartCap") as StaticBody2D
	var finish_cap := root.get_node_or_null("FinishCap") as StaticBody2D
	var caps := start_cap != null and finish_cap != null and start_cap.get_children().any(func(child: Node) -> bool: return child is CollisionShape2D) and finish_cap.get_children().any(func(child: Node) -> bool: return child is CollisionShape2D)
	var gates := get_nodes_in_group("track_checkpoints")
	var okay := line != null and not line.closed and road != null and not road.closed and caps and gates.size() == (prepared["strip_gates"] as Array).size() and root.get_node_or_null("GridForward") != null
	var moments := root.get_node_or_null("GeneratedMoments")
	var edge := root.get_node_or_null("GeneratedMoments/EdgeApronDecor")
	var floor_sectors := 0
	var detail_count := 0
	var ground_count := 0
	if moments != null:
		for sector: Node in moments.get_children():
			if not sector.name.begins_with("RunnerFloor"):
				continue
			floor_sectors += 1
			var floor_details := sector.get_node_or_null("FloorDetails")
			var ground := sector.get_node_or_null("GroundSections")
			detail_count += floor_details.get_child_count() if floor_details else 0
			ground_count += ground.get_child_count() if ground else 0
	var giants := root.get_node_or_null("GeneratedMoments/GiantLandmarks")
	var obstacles := root.get_node_or_null("PermanentObstacles")
	var surface_count := (root.get_meta("generated_surfaces", []) as Array).size()
	var placements: Array = root.get_meta("environment_placements", [])
	var counts := [edge.get_child_count() if edge else 0, detail_count, ground_count, giants.get_child_count() if giants else 0, obstacles.get_child_count() if obstacles else 0, surface_count, placements.size()]
	var dressed := moments != null and edge != null and edge.get_child_count() > 0 and floor_sectors >= 4 and detail_count >= floor_sectors and ground_count >= floor_sectors and giants != null and giants.get_child_count() > 0 and obstacles != null and obstacles.get_child_count() > 0 and surface_count > 0 and placements.size() > 8
	if not dressed:
		push_error("Strip dressing absent: edge=%d floor=%d ground=%d giants=%d obstacles=%d surfaces=%d placements=%d" % counts)
	root.free()
	if not okay or not dressed:
		_fail("Open road assembly missing caps, gates, grid, or open lines")
		return
	var packed_result := BUILDER.build_packed(&"kitchen", &"classic", 42, {"route_shape": "strip"})
	var packed := packed_result.get("scene") as PackedScene
	if packed == null:
		_fail("Strip could not be packed")
		return
	var instance := packed.instantiate()
	if instance.get_node_or_null("StartCap") == null or instance.get_node_or_null("FinishCap") == null or instance.get_node_or_null("RacingLine") == null:
		instance.free()
		_fail("Packed strip lost open-road nodes")
		return
	instance.free()
	for theme in [&"workshop", &"office"]:
		var themed := BUILDER.build_packed(theme, &"classic", 42, {"route_shape": "strip"})
		var scene := themed.get("scene") as PackedScene
		if scene == null:
			_fail("Strip room could not be packed for " + String(theme))
			return
		var room := scene.instantiate()
		var themed_moments := room.get_node_or_null("GeneratedMoments")
		if themed_moments == null or room.get_node_or_null("PermanentObstacles") == null or (room.get_meta("generated_surfaces", []) as Array).is_empty():
			room.free()
			_fail("Packed strip lost dressing in " + String(theme))
			return
		room.free()
	var longest := BUILDER.build_packed(&"kitchen", &"classic", 42, {"route_shape": "strip", "length_tier": "marathon"})
	var long_scene := longest.get("scene") as PackedScene
	if long_scene == null:
		_fail("Marathon strip could not be packed")
		return
	var long_room := long_scene.instantiate()
	var long_moments := long_room.get_node_or_null("GeneratedMoments")
	var sectors := 0
	if long_moments != null:
		for child: Node in long_moments.get_children():
			if child.name.begins_with("RunnerFloor"):
				sectors += 1
	long_room.free()
	if sectors < 9:
		_fail("Long runner lost its floor sections")
		return
	print("STRIP_SCENE_TEST PASS edge=%d floor=%d ground=%d giants=%d obstacles=%d surfaces=%d placements=%d" % counts)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
