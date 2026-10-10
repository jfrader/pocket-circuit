extends SceneTree

const IDENTITIES := preload("res://scripts/race/generated_circuit_identity.gd")
const CORE := preload("res://scripts/race/track_builder_core.gd")
const WAIT_TIMEOUT_MS := 60000
const RACE_LOAD_WAIT := preload("res://tests/support/race_load_wait.gd")
var capture_dir := OS.get_environment("PC_QUICK_RACE_CAPTURE_DIR")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	change_scene_to_file("res://scenes/boot/boot.tscn")
	var app := root.get_node("App")
	for expected_theme: String in IDENTITIES.THEMES:
		if not await _wait_for_menu(app):
			return
		app.call("open_quick_race")
		await process_frame
		var shell: Node = app.get("_shell")
		if not await _click(shell, "REROLL"):
			return
		var attempts := 0
		while String(shell.get("_quick_race_theme")) != expected_theme and attempts < IDENTITIES.THEMES.size():
			if not await _click(shell, "REROLL"):
				return
			attempts += 1
		if not _expect(String(shell.get("_quick_race_theme")) == expected_theme, "reroll must make " + expected_theme + " reachable"):
			return
		if not await _capture(expected_theme + "-menu"):
			return
		if not await _click(shell, "PLAY"):
			return
		await RACE_LOAD_WAIT.finished(self, app)
		if not _expect(not app.call("is_race_loading") and current_scene.has_node("RaceManager"), "Play must finish loading " + expected_theme):
			return
		var session: Dictionary = app.call("get_current_race_session")
		var track := current_scene.get("track_root") as Node2D
		if not _expect(session["event"]["theme"] == expected_theme and String(track.get_meta("theme")) == expected_theme, "loaded race must match the displayed theme"):
			return
		var manager := current_scene.get_node("RaceManager") as RaceManager
		var deadline := Time.get_ticks_msec() + WAIT_TIMEOUT_MS
		while not manager.is_running and Time.get_ticks_msec() < deadline:
			await physics_frame
		if not _expect(manager.is_running, "selected theme must reach GO"):
			return
		paused = true
		if not await _capture(expected_theme + "-race"):
			return
		if not capture_dir.is_empty() and DisplayServer.get_name() != "headless":
			for layer: CanvasLayer in current_scene.find_children("*", "CanvasLayer", true, false):
				layer.visible = false
			var camera := current_scene.get("camera") as Camera2D
			var bounds := CORE._polygon_bounds_rect((track.get_node("RoomSurface") as Polygon2D).polygon)
			camera.set_physics_process(false)
			camera.position = bounds.get_center()
			var view_size := root.get_visible_rect().size
			camera.zoom = Vector2.ONE * minf(view_size.x / (bounds.size.x + 140.0), view_size.y / (bounds.size.y + 140.0))
			camera.reset_smoothing()
			camera.force_update_scroll()
			if not await _capture(expected_theme + "-overview"):
				return
		print("QUICK_THEME_LAUNCHED ", expected_theme, " seed=", track.get_meta("requested_seed"), " course=", track.get_meta("surface_identity")["course"]["id"])
		paused = false
		app.call("abandon_race")
	if not await _wait_for_menu(app):
		return
	print("QUICK_RACE_THEME_RUNTIME_TEST PASS real_reroll_play_all_themes")
	quit()


func _wait_for_menu(app: Node) -> bool:
	var deadline := Time.get_ticks_msec() + WAIT_TIMEOUT_MS
	while not app.call("is_menu_visible") and Time.get_ticks_msec() < deadline:
		await process_frame
	return _expect(bool(app.call("is_menu_visible")), "menu must become visible")


func _click(shell: Node, caption: String) -> bool:
	var target: Button
	for button: Button in shell.find_children("*", "Button", true, false):
		if button.text == caption and button.is_visible_in_tree():
			target = button
			break
	if not _expect(target != null, "missing menu action " + caption):
		return false
	var point := target.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	await process_frame
	return true


func _capture(name: String) -> bool:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return true
	DirAccess.make_dir_recursive_absolute(capture_dir)
	await process_frame
	await RenderingServer.frame_post_draw
	return _expect(root.get_texture().get_image().save_png(capture_dir.path_join(name + ".png")) == OK, "native capture must save")


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("QUICK_RACE_THEME_RUNTIME_TEST FAIL: " + message)
	quit(1)
	return false
