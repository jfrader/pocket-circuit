extends SceneTree

const RACE_SCENE := "res://scenes/race/prototype_race.tscn"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var theme := StringName(OS.get_environment("PC_THEME"))
	var room := StringName(OS.get_environment("PC_ROOM"))
	var seed_text := OS.get_environment("PC_SEED")
	var output_path := OS.get_environment("PC_CAPTURE_PATH")
	var focus := StringName(OS.get_environment("PC_CAPTURE_FOCUS"))
	if theme not in [&"kitchen", &"workshop", &"office"] or room not in [&"classic", &"wide", &"tall", &"long", &"square", &"el"] or not seed_text.is_valid_int() or output_path.is_empty():
		push_error("VISUAL_DENSITY_CAPTURE FAIL: set PC_THEME, PC_ROOM, PC_SEED, and PC_CAPTURE_PATH")
		quit(1)
		return
	var app := root.get_node_or_null("App")
	if app == null:
		push_error("VISUAL_DENSITY_CAPTURE FAIL: App autoload is unavailable")
		quit(1)
		return
	var frozen := OS.get_environment("PC_CAPTURE_FROZEN") == "1"
	if frozen:
		var packed := load(RACE_SCENE) as PackedScene
		var fixture := packed.instantiate()
		fixture.set("_session", {"vehicle_id": "rustbug", "event": {"circuit": "generated", "theme": theme, "room": room, "seed": int(seed_text), "laps": 3, "length_tier": OS.get_environment("PC_LENGTH_TIER") if OS.get_environment("PC_LENGTH_TIER") != "" else "standard"}})
		root.add_child(fixture)
		current_scene = fixture
	else:
		change_scene_to_file("res://scenes/boot/boot.tscn")
		for boot_frame in 3:
			await process_frame
		app.call("start_circuit_race", theme, room, int(seed_text), "rustbug")
		var deadline := Time.get_ticks_msec() + 45000
		while app.call("is_race_loading") and Time.get_ticks_msec() < deadline and not app.get("_loading_failed"):
			await process_frame
	if app.call("is_race_loading") or current_scene == null or current_scene.scene_file_path != RACE_SCENE:
		var loading := app.get("_loading_screen") as Node
		if loading:
			print("VISUAL_CAPTURE_LOADING_STATE ", loading.call("metrics"))
		push_error("VISUAL_DENSITY_CAPTURE FAIL: race scene did not load")
		quit(1)
		return
	paused = false
	current_scene.call("_set_paused", false)
	if frozen:
		paused = true
		var countdown := current_scene.get("_countdown_label") as Label
		if countdown:
			countdown.hide()
		current_scene.call("_update_race_hud")
		var camera := current_scene.get_node("FollowCamera2D") as Camera2D
		camera.global_position = (current_scene.get("_player_vehicle") as Node2D).global_position
		camera.reset_smoothing()
		camera.force_update_scroll()
	else:
		for settle_frame in 20:
			await process_frame
		await create_timer(4.2, false).timeout
	var track := current_scene.get_node("Track") as Node2D
	var racing_line := track.get_node("RacingLine") as Line2D
	var checkpoints := PackedVector2Array()
	for node: Node in track.find_children("*", "Area2D", true, false):
		if node.is_in_group("track_checkpoints"):
			checkpoints.append((node as Node2D).position)
	print("CAPTURE_GEOMETRY theme=%s room=%s seed=%s route_hash=%s gates_hash=%s" % [theme, room, seed_text, hash(racing_line.points), hash(checkpoints)])
	for ready_frame in 2:
		await process_frame
	var views: Array[StringName] = [focus]
	if focus == &"all":
		views = [&"race", &"overview"]
	for view in views:
		if view in [&"overview", &"giant", &"grip"]:
			_focus_density_detail(current_scene, view)
		if view == &"overview" and focus == &"all":
			(current_scene.get_node("HUD") as CanvasLayer).hide()
		for camera_frame in 8:
			await process_frame
		if frozen:
			(current_scene.get("_countdown_label") as Label).hide()
		await RenderingServer.frame_post_draw
		var path := output_path.get_basename() + "-" + String(view) + ".png" if focus == &"all" else output_path
		if not _save_capture(path):
			return
		print("VISUAL_DENSITY_CAPTURE PASS %s/%s/%s focus=%s path=%s" % [theme, room, seed_text, view if view else &"race", path])
	var race := current_scene
	paused = false
	current_scene = null
	app.current_race_session.clear()
	race.free()
	app.free()
	await create_timer(1.0, true).timeout
	quit(0)


func _save_capture(path: String) -> bool:
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_width() != 1280 or image.get_height() != 720:
		push_error("VISUAL_DENSITY_CAPTURE FAIL: expected a rendered 1280x720 frame")
		quit(1)
		return false
	var save_error := image.save_png(path)
	if save_error != OK:
		push_error("VISUAL_DENSITY_CAPTURE FAIL: %s" % error_string(save_error))
		quit(1)
		return false
	return true


func _focus_density_detail(race: Node, focus: StringName) -> void:
	var track := race.get_node_or_null("Track") as Node2D
	var camera := race.get_node_or_null("FollowCamera2D") as Camera2D
	if track == null or camera == null:
		return
	var target := Vector2.ZERO
	if focus == &"overview":
		var room_bounds: Rect2 = track.get_meta("room_bounds", Rect2())
		target = room_bounds.get_center()
		var viewport_size := Vector2(1280.0, 720.0)
		var fit_zoom := minf(viewport_size.x / room_bounds.size.x, viewport_size.y / room_bounds.size.y) * 0.9
		camera.zoom = Vector2.ONE * fit_zoom
	elif focus == &"giant":
		var giants := track.get_node_or_null("GeneratedMoments/GiantLandmarks")
		if giants and giants.get_child_count() > 0:
			target = (giants.get_child(0) as Node2D).global_position
	else:
		var patches := track.find_children("ExtraGripPatch*", "Node2D", true, false)
		if not patches.is_empty():
			var polygon: PackedVector2Array = patches[0].get_meta("polygon", PackedVector2Array())
			for point: Vector2 in polygon:
				target += point
			target /= maxf(float(polygon.size()), 1.0)
	camera.set_physics_process(false)
	camera.set("target_vehicle", null)
	camera.global_position = track.to_global(target)
	if focus != &"overview":
		camera.zoom = Vector2.ONE * (0.9 if focus == &"giant" else 2.0)
	camera.reset_smoothing()
	camera.force_update_scroll()
