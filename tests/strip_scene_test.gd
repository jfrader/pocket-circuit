extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var started := Time.get_ticks_msec()
	var prepared := BUILDER.prepare_layout(&"kitchen", &"classic", 42, {"route_shape": "strip"})
	if prepared.is_empty():
		_fail("Strip layout unavailable")
		return
	var prepared_ms := Time.get_ticks_msec() - started
	var root := BUILDER.create_layout_root(prepared)
	get_root().add_child(root)
	await BUILDER.assemble_runtime(root, prepared, Callable())
	var assembled_ms := Time.get_ticks_msec() - started - prepared_ms
	var line := root.get_node_or_null("RacingLine") as Line2D
	var road := root.get_node_or_null("TrackSurface") as Line2D
	if not _check_runner(root, road):
		return
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
	var prop_count := placements.filter(func(entry: Dictionary) -> bool: return not bool(entry.get("edge_detail", false))).size()
	var length := float(prepared["strip_length"])
	var counts := [edge.get_child_count() if edge else 0, detail_count, ground_count, giants.get_child_count() if giants else 0, obstacles.get_child_count() if obstacles else 0, surface_count, prop_count]
	var dressed: bool = moments != null and edge != null and counts[0] >= floori(length / 300.0) * 2 and floor_sectors >= 4 and detail_count >= floori(length / 150.0) and ground_count >= floori(length / 700.0) and giants != null and counts[3] >= floori(length / 12000.0) and obstacles != null and counts[4] >= floori(length / 4000.0) and surface_count >= floori(length / 5000.0) and prop_count >= floori(length / 900.0)
	if not dressed:
		push_error("Strip dressing absent: edge=%d floor=%d ground=%d giants=%d obstacles=%d surfaces=%d props=%d" % counts)
	root.free()
	if not okay or not dressed:
		_fail("Open road assembly missing caps, gates, grid, or open lines")
		return
	var packed_start := Time.get_ticks_msec()
	var packed_result := BUILDER.build_packed(&"kitchen", &"classic", 42, {"route_shape": "strip"})
	var packed_ms := Time.get_ticks_msec() - packed_start
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
	var other_ms: Array[int] = []
	for theme in [&"workshop", &"office"]:
		var other_start := Time.get_ticks_msec()
		var themed := BUILDER.build_packed(theme, &"classic", 42, {"route_shape": "strip"})
		other_ms.append(Time.get_ticks_msec() - other_start)
		var scene := themed.get("scene") as PackedScene
		if scene == null:
			_fail("Strip room could not be packed for " + String(theme))
			return
		var room := scene.instantiate()
		if not _check_runner(room, room.get_node("TrackSurface") as Line2D):
			return
		var themed_moments := room.get_node_or_null("GeneratedMoments")
		if themed_moments == null or room.get_node_or_null("PermanentObstacles") == null or (room.get_meta("generated_surfaces", []) as Array).is_empty():
			room.free()
			_fail("Packed strip lost dressing in " + String(theme))
			return
		room.free()
	var marathon_start := Time.get_ticks_msec()
	var longest := BUILDER.build_packed(&"kitchen", &"classic", 42, {"route_shape": "strip", "length_tier": "marathon"})
	var marathon_ms := Time.get_ticks_msec() - marathon_start
	var long_scene := longest.get("scene") as PackedScene
	if long_scene == null:
		_fail("Marathon strip could not be packed")
		return
	var long_room := long_scene.instantiate()
	var long_moments := long_room.get_node_or_null("GeneratedMoments")
	var sectors := 0
	var marathon_nodes := long_room.find_children("*", "", true, false).size() + 1
	if long_moments != null:
		for child: Node in long_moments.get_children():
			if child.name.begins_with("RunnerFloor"):
				sectors += 1
	if sectors < 9 or marathon_nodes > 10000:
		_fail("Long runner lost its floor sections or exceeded the node budget: sectors=%d nodes=%d" % [sectors, marathon_nodes])
		return
	long_room.free()
	print("STRIP_SCENE_TEST PASS edge=%d floor=%d ground=%d giants=%d obstacles=%d surfaces=%d props=%d traffic=%d prepare_ms=%d assemble_ms=%d packed_ms=%d workshop_ms=%d office_ms=%d marathon_ms=%d marathon_nodes=%d" % [counts[0], counts[1], counts[2], counts[3], counts[4], counts[5], counts[6], (prepared["traffic_plan"] as Array).size(), prepared_ms, assembled_ms, packed_ms, other_ms[0], other_ms[1], marathon_ms, marathon_nodes])
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)


func _check_runner(track: Node, road: Line2D) -> bool:
	var runner := track.get_node_or_null("WovenRunner") as Line2D
	var left := track.get_node_or_null("RunnerBindingLeft") as Line2D
	var right := track.get_node_or_null("RunnerBindingRight") as Line2D
	if runner == null or left == null or right == null or left.width > 6.0 or right.width > 6.0 or left.default_color == right.default_color:
		_fail("Runner needs thin independently seeded fabric bindings")
		return false
	if runner.width != road.width + 20.0 or runner.closed or left.closed or right.closed:
		_fail("Runner selvedge must follow the open painted road")
		return false
	if runner.get_meta("material_profile", "") != "strip_woven_runner" or road.get_meta("substrate_profile", "") != runner.get_meta("material_profile") or runner.material == null or road.material == null:
		_fail("Road paint and runner must share their woven substrate")
		return false
	if (runner.material as ShaderMaterial).get_shader_parameter("pattern") != 4 or (road.material as ShaderMaterial).get_shader_parameter("pattern") != 4:
		_fail("Runner weave was lost when applying the paint shader")
		return false
	for name in ["PrintedCenterDashes", "RunnerStitchLeft", "RunnerStitchRight", "PrintedGridPlayer", "PrintedGridChaser"]:
		if track.get_node_or_null(name) == null:
			_fail("Missing runner marking " + name)
			return false
	if not track.find_children("*Boundary*", "StaticBody2D", false, false).is_empty():
		_fail("Flat binding must not conceal a continuous wall")
		return false
	for name in ["StartCap", "FinishCap"]:
		var cap := track.get_node(name) as StaticBody2D
		var visual := cap.get_node("FoldedFabric") as Polygon2D
		var collision := cap.get_child(0) as CollisionShape2D
		var shape := collision.shape as RectangleShape2D
		var bounds := BUILDER._polygon_bounds_rect(visual.polygon)
		if shape.size.y != 8.0 or bounds.size != shape.size or bounds.get_center() != collision.position:
			_fail("Raised fabric hem collision must exactly match its visible footprint")
			return false
	return true
