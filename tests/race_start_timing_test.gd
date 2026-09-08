extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if OS.get_environment("PC_PROFILE_BASELINE") == "1":
		_profile_baseline()
		return
	change_scene_to_file("res://scenes/boot/boot.tscn")
	await process_frame
	await process_frame
	var app := root.get_node("App")
	for retry in [false, true]:
		if retry:
			app.call("retry_race")
		else:
			app.call("start_circuit_race", &"kitchen", &"long", 24469, "rustbug")
		if not _expect(app.call("is_race_loading") and (app.get("_loading_screen") as CanvasLayer).visible, "loading must be visible as soon as Play returns"):
			return
		if not retry and DisplayServer.get_name() != "headless" and not OS.get_environment("PC_LOADING_SCREENSHOT").is_empty():
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(OS.get_environment("PC_LOADING_SCREENSHOT")) == OK, "the first visible loading frame should be captured"):
				return
		var session: Dictionary = app.call("get_current_race_session")
		app.call("start_circuit_race", &"office", &"classic", 42, "rustbug")
		if not _expect(app.call("get_current_race_session") == session, "a duplicate start must not change the active loading session"):
			return
		var deadline := Time.get_ticks_msec() + 45000
		while app.call("is_race_loading") and Time.get_ticks_msec() < deadline:
			await process_frame
		if app.call("is_race_loading"):
			print("RACE_START_STALLED ", (app.get("_loading_screen") as Node).call("metrics"))
		if not _expect(not app.call("is_race_loading"), "loading must finish within the bounded startup deadline"):
			return
		var metrics: Dictionary = app.get("loading_metrics")
		print("RACE_START_TIMING retry=%s metrics=%s" % [retry, metrics])
		if not _expect(int(metrics["frames"]) >= 3 and float(metrics["max_frame_gap_ms"]) < 250.0, "preparation must keep servicing frames (maximum gap under 250ms)"):
			return
		var generated_before := IDENTITIES.motion_image_generations
		var manager := current_scene.get_node("RaceManager") as RaceManager
		while not manager.is_running and Time.get_ticks_msec() < deadline:
			await physics_frame
		if not _expect(manager.is_running, "countdown must begin only after preparation and reach GO"):
			return
		var last_tick := Time.get_ticks_usec()
		var max_gameplay_gap := 0.0
		for frame in 180:
			await physics_frame
			var now := Time.get_ticks_usec()
			max_gameplay_gap = maxf(max_gameplay_gap, (now - last_tick) / 1000.0)
			last_tick = now
		print("RACE_START_GAMEPLAY retry=%s max_gap_ms=%.3f" % [retry, max_gameplay_gap])
		if not _expect(max_gameplay_gap < 250.0, "the first seconds after GO must not contain a multi-frame preparation stall"):
			return
		if not _expect(IDENTITIES.motion_image_generations == generated_before, "first gameplay movement must not generate more wheel-animation images"):
			return
		if not retry and DisplayServer.get_name() != "headless" and not OS.get_environment("PC_HUD_SCREENSHOT").is_empty():
			await RenderingServer.frame_post_draw
			if not _expect(root.get_texture().get_image().save_png(OS.get_environment("PC_HUD_SCREENSHOT")) == OK, "the live HUD should be captured"):
				return
	app.call("retry_race")
	var previous := current_scene
	var cancel_deadline := Time.get_ticks_msec() + 15000
	while current_scene == previous and Time.get_ticks_msec() < cancel_deadline:
		await process_frame
	await process_frame
	await _cancel_input()
	while app.call("is_race_loading") and Time.get_ticks_msec() < cancel_deadline:
		await process_frame
	await process_frame
	await process_frame
	if not _expect(not app.call("is_race_loading") and current_scene.scene_file_path == "res://scenes/boot/boot.tscn" and not paused, "cancel during preparation must return safely without starting or pausing gameplay"):
		return
	app.call("start_circuit_race", &"invalid_theme", &"classic", 42, "rustbug")
	var failure_deadline := Time.get_ticks_msec() + 15000
	while not app.get("_loading_failed") and Time.get_ticks_msec() < failure_deadline:
		await process_frame
	if not _expect(app.get("_loading_failed") and app.call("is_race_loading"), "generation failure must leave an actionable loading error rather than a black screen"):
		return
	await _cancel_input()
	await process_frame
	await process_frame
	if not _expect(not app.call("is_race_loading") and current_scene.scene_file_path == "res://scenes/boot/boot.tscn", "Back must recover from a loading failure"):
		return
	print("RACE_START_TIMING_TEST PASS cold_warm_responsive_no_gameplay_rasterization_cancel_failure")
	current_scene.queue_free()
	current_scene = null
	await process_frame
	await physics_frame
	quit(0)


func _cancel_input() -> void:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _profile_baseline() -> void:
	var started := Time.get_ticks_usec()
	var built := BUILDER.build_packed(&"kitchen", &"long", 24469)
	print("RACE_START_BASELINE build_packed_ms=%.2f" % ((Time.get_ticks_usec() - started) / 1000.0))
	if built.get("scene") == null:
		quit(1)
		return
	for vehicle_id in ["rustbug", "pinbolt", "scrapjaw", "flicker"]:
		started = Time.get_ticks_usec()
		IDENTITIES.car_texture(vehicle_id)
		print("RACE_START_BASELINE car=%s rest_ms=%.2f" % [vehicle_id, (Time.get_ticks_usec() - started) / 1000.0])
		started = Time.get_ticks_usec()
		IDENTITIES.car_motion_texture(vehicle_id, 64.0, 0.0)
		print("RACE_START_BASELINE car=%s first_spin_ms=%.2f" % [vehicle_id, (Time.get_ticks_usec() - started) / 1000.0])
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("RACE_START_TIMING_TEST FAIL: " + message)
	quit(1)
	return false
