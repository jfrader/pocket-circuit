extends SceneTree

const PROTOTYPE := preload("res://scenes/race/prototype_race.tscn")
const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const CAMERA := preload("res://scripts/camera/follow_camera.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var race := PROTOTYPE.instantiate()
	race.set("_session", {"event": {"theme": &"kitchen", "circuit": "generated", "room": &"classic", "seed": 42}})
	root.add_child(race)
	current_scene = race
	var manager := race.get_node("RaceManager") as RaceManager
	var hud: Control = race.get("_race_hud")
	var player: Node2D = race.get("_player_vehicle")
	manager.set_physics_process(false)
	manager.race_time = 0.0
	race.call("_update_race_hud")
	if not _expect(hud.call("clock_copy") == "00:00.0" and hud.call("finish_countdown_copy") == "", "elapsed time must be visible before anyone finishes, without an invented deadline"):
		return
	manager.race_time = 52.0
	var opponent: Node2D = manager.get_rankings().filter(func(racer: Node2D) -> bool: return racer != player)[0]
	var first := manager.get_racer_state_ref(opponent)
	first["elapsed"] = manager.race_time
	manager.call("_finish_racer", opponent, first)
	race.call("_update_race_hud")
	var deadline := 52.0 + manager.finish_grace_seconds
	if not _expect(hud.call("clock_copy") == "00:52.0" and hud.call("finish_countdown_copy") == "FINISH IN %ds" % ceili(manager.finish_grace_seconds), "first finisher must start the real grace countdown while preserving elapsed time"):
		return
	if not _expect(hud.call("deadline_warning") == "", "the full grace period must not already carry a low-time warning"):
		return
	manager.race_time = deadline - 2.1
	race.call("_update_race_hud")
	if not _expect(hud.call("finish_countdown_copy") == "FINISH IN 3s" and hud.call("deadline_warning") == "3s LEFT", "countdown must decrease and warn in the final three seconds"):
		return
	manager.race_time = deadline
	var player_state := manager.get_racer_state_ref(player)
	player_state["dnf"] = true
	player_state["finished"] = true
	var expected_limit := "%d:%02d" % [int(deadline) / 60, int(deadline) % 60]
	if not _expect(race.call("_player_dnf_explanation", manager.get_results()) == "TIME UP (LIMIT %s)" % expected_limit, "results must retain TIME UP with the actual first-finish-plus-grace limit"):
		return
	hud.set("finish_grace_countdown", false)
	hud.set("elapsed_seconds", 10.0)
	hud.set("deadline_seconds", 45.0)
	if not _expect(hud.call("clock_copy") == "00:10 / 00:45" and hud.call("finish_countdown_copy") == "", "fixed strip deadlines must keep their elapsed/limit display"):
		return
	var camera := race.get_node("FollowCamera2D") as Camera2D
	var bounds: Rect2 = (race.get("track_root") as Node).get_meta("room_bounds")
	if not _expect(camera.limit_left == floori(bounds.position.x) and camera.limit_right == ceili(bounds.end.x) and camera.limit_top == floori(bounds.position.y) and camera.limit_bottom == ceili(bounds.end.y), "race camera must retain its room bounds"):
		return
	current_scene = null
	root.remove_child(race)
	race.free()
	await process_frame
	for theme in [&"kitchen", &"workshop", &"office"]:
		for strip in [false, true]:
			var options := {"route_shape": "strip"} if strip else {}
			var built := BUILDER.build_packed(theme, &"classic", 42, options)
			var track := (built["scene"] as PackedScene).instantiate() as Node2D
			root.add_child(track)
			if not await _check_backdrop(track, "%s strip=%s" % [theme, strip]):
				return
			track.free()
	print("RACE_DEADLINE_HUD_TEST PASS elapsed_first_finish_countdown_warning_time_up three_theme_circuit_strip_backdrops")
	quit(0)


func _check_backdrop(track: Node2D, context: String) -> bool:
	var bounds: Rect2 = track.get_meta("room_bounds")
	var camera := CAMERA.new() as Camera2D
	root.add_child(camera)
	camera.set_physics_process(false)
	camera.limit_left = floori(bounds.position.x)
	camera.limit_right = ceili(bounds.end.x)
	camera.limit_top = floori(bounds.position.y)
	camera.limit_bottom = ceili(bounds.end.y)
	# Maximum-speed boost is the widest normal camera view.
	camera.zoom = Vector2.ONE * camera.fast_zoom * 0.985
	camera.make_current()
	var floors: Array[Polygon2D] = []
	for node: Node in track.find_children("Floor", "Polygon2D", true, false):
		floors.append(node as Polygon2D)
		if not _expect((node as Polygon2D).texture != null, context + " exterior must use a themed floor material, not a dark void"):
			return false
		var room_surface := node.get_parent().get_node("RoomSurface") as Polygon2D
		if not _expect(node.get("material") == room_surface.material and node.get("texture") == room_surface.texture, context + " backdrop must continue the room's actual material"):
			return false
	if not _expect(not floors.is_empty(), context + " must have a backdrop"):
		return false
	var floor_bounds: Array[Rect2] = []
	for floor_node: Polygon2D in floors:
		var rect := BUILDER._polygon_bounds_rect(floor_node.polygon)
		if not _expect(is_equal_approx(absf(BUILDER._polygon_area(floor_node.polygon)), rect.get_area()), context + " backdrop must cover its full rectangle"):
			return false
		var world_rect := Rect2(floor_node.to_global(rect.position), rect.size)
		for other: Rect2 in floor_bounds:
			if not _expect(not world_rect.intersection(other).has_area(), context + " theme backdrops must meet without overlapping"):
				return false
		floor_bounds.append(world_rect)
	for point in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y), bounds.get_center()]:
		camera.global_position = point + Vector2(120, -120)
		camera.reset_smoothing()
		camera.force_update_scroll()
		await process_frame
		var screen := root.get_visible_rect()
		var to_world := root.get_canvas_transform().affine_inverse()
		var viewport := Rect2(to_world * screen.position, screen.size / camera.zoom)
		var covered_area := 0.0
		for rect: Rect2 in floor_bounds:
			covered_area += viewport.intersection(rect).get_area()
		if not _expect(is_equal_approx(covered_area, viewport.get_area()), "%s high-speed corner viewport must be fully covered by the themed backdrops: %s" % [context, viewport]):
			return false
	camera.free()
	return true


func _expect(ok: bool, message: String) -> bool:
	if not ok:
		push_error("RACE_DEADLINE_HUD_TEST FAIL: " + message)
		quit(1)
	return ok
