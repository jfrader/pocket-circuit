extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const ROAD := preload("res://scripts/race/strip/strip_road_rules.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var summaries: Array[String] = []
	for theme in [&"kitchen", &"workshop", &"office"]:
		var started := Time.get_ticks_msec()
		var prepared := BUILDER.prepare_layout(theme, &"classic", 42, {"route_shape": "strip"})
		var track := BUILDER.create_layout_root(prepared)
		root.add_child(track)
		await BUILDER.assemble_runtime(track, prepared, Callable())
		if not _check_scene(track, prepared):
			return
		track.free()
		var built := BUILDER.build_packed(theme, &"classic", 42, {"route_shape": "strip"})
		var scene := built.get("scene") as PackedScene
		if scene == null:
			_fail("Two-theme strip could not be packed")
			return
		var saved := scene.instantiate()
		if not _check_scene(saved, prepared):
			return
		summaries.append("%s→%s runtime+packed_ms=%d nodes=%d" % [theme, prepared["theme_b"], Time.get_ticks_msec() - started, saved.find_children("*", "", true, false).size() + 1])
		saved.free()
	var longest := BUILDER.build_packed(&"kitchen", &"classic", 42, {"route_shape": "strip", "length_tier": "marathon"})
	var long_track := (longest["scene"] as PackedScene).instantiate()
	var nodes := long_track.find_children("*", "", true, false).size() + 1
	var sectors := long_track.find_children("RunnerFloor*", "Node2D", true, false).size()
	if nodes > 10000 or sectors < 9:
		_fail("Marathon lost dressing coverage or exceeded the node budget")
		return
	long_track.free()
	print("STRIP_SCENE_TEST PASS four_lane_dual_theme_exact_seam caps_match_visuals %s marathon_nodes=%d sectors=%d" % ["; ".join(summaries), nodes, sectors])
	quit(0)


func _check_scene(track: Node, prepared: Dictionary) -> bool:
	var racing := track.get_node_or_null("RacingLine") as Line2D
	if racing == null or racing.closed or track.get_node_or_null("GridForward") == null:
		return _fail("Missing open racing line or grid")
	var gates := track.get_children().filter(func(child: Node) -> bool: return child.is_in_group("track_checkpoints"))
	if gates.size() != (prepared["strip_gates"] as Array).size():
		return _fail("Open strip lost its ordered checkpoints")
	var threshold := track.get_node_or_null("RoomThreshold") as Line2D
	if threshold == null or threshold.get_meta("theme_a") != prepared["theme"] or threshold.get_meta("theme_b") != prepared["theme_b"]:
		return _fail("Missing explicit two-room threshold")
	var seam: Vector2 = prepared["strip_theme_switch"]["position"]
	if (threshold.points[0] + threshold.points[-1]).distance_to(seam * 2.0) > 0.01:
		return _fail("Threshold is not at the recorded seam")
	var counts := {"edge": 0, "floor": 0, "ground": 0, "giants": 0, "obstacles": 0, "surfaces": 0}
	for index in 2:
		var region := track.get_node_or_null("StripRoom%d" % index)
		if region == null or region.get_meta("theme") != prepared["strip_regions"][index]["theme"]:
			return _fail("Missing theme region")
		if not _check_runner(region):
			return false
		var floor_node := region.get_node("RoomSurface") as Polygon2D
		if floor_node.get_meta("material_profile") != prepared["strip_regions"][index]["spec"]["surface_identity"]["floor"]["id"]:
			return _fail("Room floor rendered with the other theme's material")
		var floor_bounds := BUILDER._polygon_bounds_rect(floor_node.polygon)
		if absf((floor_bounds.position.y if index == 0 else floor_bounds.end.y) - seam.y) > 0.01:
			return _fail("Floor materials overlap or leave a gap at the seam")
		var moments := region.get_node("GeneratedMoments")
		counts["edge"] += moments.get_node("EdgeApronDecor").get_child_count()
		counts["giants"] += moments.get_node("GiantLandmarks").get_child_count()
		counts["obstacles"] += region.get_node("PermanentObstacles").get_child_count()
		counts["surfaces"] += (region.get_meta("generated_surfaces", []) as Array).size()
		for sector in moments.get_children():
			if String(sector.name).begins_with("RunnerFloor"):
				var details := sector.get_node_or_null("FloorDetails")
				var ground := sector.get_node_or_null("GroundSections")
				counts["floor"] += details.get_child_count() if details else 0
				counts["ground"] += ground.get_child_count() if ground else 0
	var length := float(prepared["strip_length"])
	var placements: Array = track.get_meta("environment_placements")
	var props := placements.filter(func(entry: Dictionary) -> bool: return not bool(entry.get("edge_detail", false))).size()
	if props < floori(length / 900.0):
		return _fail("Two rooms lost their supporting household props")
	if counts["edge"] < floori(length / 300.0) * 2 or counts["floor"] < floori(length / 150.0) or counts["ground"] < floori(length / 700.0) or counts["giants"] < floori(length / 12000.0) or counts["obstacles"] < floori(length / 4000.0) or counts["surfaces"] < floori(length / 5000.0):
		return _fail("Dual-theme dressing lost its density: " + str(counts))
	for name in ["PrintedGridPlayer", "PrintedGridChaser", "StartCap", "FinishCap"]:
		if track.get_node_or_null(name) == null:
			return _fail("Missing runner endpoint/grid " + name)
	for name in ["StartCap", "FinishCap"]:
		var cap := track.get_node(name) as StaticBody2D
		var visual := cap.get_node("FoldedFabric") as Polygon2D
		var collision := cap.get_child(0) as CollisionShape2D
		var shape := collision.shape as RectangleShape2D
		var bounds := BUILDER._polygon_bounds_rect(visual.polygon)
		if shape.size.y != 8.0 or shape.size.x != ROAD.HALF_WIDTH * 2.0 + 20.0 or bounds.size != shape.size or bounds.get_center() != collision.position:
			return _fail("Raised fabric hem collision must exactly match its visible footprint")
	return true


func _check_runner(region: Node) -> bool:
	var road := region.get_node("TrackSurface") as Line2D
	var runner := region.get_node("WovenRunner") as Line2D
	var left := region.get_node("RunnerBindingLeft") as Line2D
	var right := region.get_node("RunnerBindingRight") as Line2D
	if left.width > 6.0 or right.width > 6.0 or left.default_color == right.default_color:
		return _fail("Runner needs thin independently seeded fabric bindings")
	if road.width != ROAD.HALF_WIDTH * 2.0 or runner.width != road.width + 20.0 or runner.closed or road.closed:
		return _fail("Four-lane runner width/selvedge mismatch")
	if runner.get_meta("material_profile") != "strip_woven_runner" or road.get_meta("substrate_profile") != runner.get_meta("material_profile"):
		return _fail("Road paint and runner must share their woven substrate")
	if (runner.material as ShaderMaterial).get_shader_parameter("pattern") != 4 or (road.material as ShaderMaterial).get_shader_parameter("pattern") != 4:
		return _fail("Runner weave was lost when applying the paint shader")
	for name in ["CenterDividerLeft", "CenterDividerRight", "NorthboundLaneDashes", "SouthboundLaneDashes", "PrintedDirectionArrows", "RunnerStitchLeft", "RunnerStitchRight"]:
		if region.get_node_or_null(name) == null:
			return _fail("Missing four-lane runner marking " + name)
	if not region.find_children("*Boundary*", "StaticBody2D", false, false).is_empty():
		return _fail("Flat binding must not conceal a continuous wall")
	return true


func _fail(message: String) -> bool:
	push_error(message)
	quit(1)
	return false
