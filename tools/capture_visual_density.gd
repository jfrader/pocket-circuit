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
	app.call("start_circuit_race", theme, room, int(seed_text), "rustbug")
	for transition_frame in 300:
		if current_scene != null and current_scene.scene_file_path == RACE_SCENE:
			break
		await process_frame
	if current_scene == null or current_scene.scene_file_path != RACE_SCENE:
		push_error("VISUAL_DENSITY_CAPTURE FAIL: race scene did not load")
		quit(1)
		return
	paused = false
	current_scene.call("_set_paused", false)
	for settle_frame in 20:
		await process_frame
	await create_timer(4.2, false).timeout
	if focus in [&"overview", &"giant", &"grip"]:
		_focus_density_detail(current_scene, focus)
		for camera_frame in 8:
			await process_frame
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_width() != 1280 or image.get_height() != 720:
		push_error("VISUAL_DENSITY_CAPTURE FAIL: expected a rendered 1280x720 frame")
		quit(1)
		return
	var save_error := image.save_png(output_path)
	if save_error != OK:
		push_error("VISUAL_DENSITY_CAPTURE FAIL: %s" % error_string(save_error))
		quit(1)
		return
	print("VISUAL_DENSITY_CAPTURE PASS %s/%s/%s focus=%s path=%s" % [theme, room, seed_text, focus if focus else &"race", output_path])
	var race := current_scene
	current_scene = null
	app.current_race_session.clear()
	race.free()
	app.free()
	for cleanup_frame in 60:
		await process_frame
	quit(0)


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
