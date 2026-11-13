extends SceneTree

const RUN_WALK := preload("res://tests/support/run_walk.gd")
const ERRAND := preload("res://scripts/ui/run_errand_scene.gd")
const BENCH := preload("res://scripts/ui/run_bench_scene.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	var app := root.get_node("App")
	var shell := app.get("_shell") as CanvasLayer
	for reduced: bool in [false, true]:
		app.call("update_setting", "reduced_motion", reduced)
		var session := _find_stop(app, "errand")
		if not _expect(session != null, "fixture reaches errand"):
			return
		session.run_state.set_car_wear(session.current_car_id, "rusty")
		shell.call("show_run_errand")
		for frame in 4:
			await process_frame
		(shell.find_child("ErrandTuneUp", true, false) as Button).pressed.emit()
		await create_timer(ERRAND.STAMP_TIME + 0.2).timeout
		var acknowledgement := shell.find_child("ErrandAcknowledgement", true, false) as Label
		if not _expect(acknowledgement != null and acknowledgement.text == "ERRAND DONE - TUNE-UP", "tune-up returns its acknowledgement to the board"):
			return
		await create_timer(0.5).timeout
		if not _expect(is_instance_valid(acknowledgement) and acknowledgement.is_visible_in_tree(), "acknowledgement persists without another action"):
			return
		var board := shell.get("_run_board") as Control
		var next_id := String(session.available_nodes()[0]["id"])
		var next_marker: Button = board.call("marker", next_id)
		var connected_before := next_marker.pressed.get_connections().size()
		# Selecting the completed errand frees the tape. The next marker still
		# exists, and used to retain a lambda capturing that freed label.
		board.call("preview", session.current_node_id)
		await process_frame
		if not _expect(not is_instance_valid(acknowledgement), "next selection frees the acknowledgement"):
			return
		if not _expect(next_marker.pressed.get_connections().size() == connected_before - 1, "freeing the tape disconnects its callback from surviving buttons"):
			return
		next_marker.pressed.emit()
		await process_frame
		if not _expect(board.call("selected_id") == next_id and shell.find_child("ErrandAcknowledgement", true, false) == null, "next stop remains selectable after the tape is freed"):
			return
		shell.call("show_run_board")
		await process_frame
		if not _expect(shell.find_child("ErrandAcknowledgement", true, false) == null, "reopening the board does not replay the acknowledgement"):
			return

		var bench_session := _find_stop(app, "bench")
		if not _expect(bench_session != null, "fixture reaches bench"):
			return
		bench_session.run_state.set_car_wear(bench_session.current_car_id, "rusty")
		shell.call("show_run_bench")
		for frame in 4:
			await process_frame
		(shell.find_child("BenchRepair", true, false) as Button).pressed.emit()
		await create_timer(BENCH.CONFIRM_TIME + 0.2).timeout
		var repair := shell.find_child("BenchRepairAcknowledgement", true, false) as Label
		if not _expect(repair != null and repair.text == "REPAIRED - RUSTY -> CLEAN", "repair preserves the exact acknowledgement copy"):
			return
		var tape := repair.get_theme_stylebox("normal") as StyleBoxFlat
		if not _expect(tape != null and repair.get_theme_color("font_color") == SKIN.INK and tape.bg_color == SKIN.CREAM, "repair uses dark ink on light tape"):
			return
		var text_width := repair.get_theme_font("font").get_string_size(repair.text, HORIZONTAL_ALIGNMENT_LEFT, -1, repair.get_theme_font_size("font_size")).x
		var padded_width := text_width + tape.get_content_margin(SIDE_LEFT) + tape.get_content_margin(SIDE_RIGHT)
		if not _expect(repair.autowrap_mode == TextServer.AUTOWRAP_OFF and repair.get_line_count() == 1 and padded_width <= repair.size.x and repair.get_global_rect().end.x <= 1280 and repair.size.x <= (repair.get_parent() as Control).size.x, "padded repair tape fits one line inside its card at 1280 width"):
			return
		await create_timer(0.5).timeout
		if not _expect(is_instance_valid(repair) and repair.is_visible_in_tree(), "repair acknowledgement persists until the next action"):
			return
		var shot := OS.get_environment("PC_ACK_SHOT_PATH")
		if not shot.is_empty() and reduced:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(shot)
		(shell.get("_run_board") as Control).call("preview", bench_session.current_node_id)
		await process_frame
		if not _expect(not is_instance_valid(repair), "next selection clears the repair acknowledgement"):
			return
	print("ACK_LIFETIME_TEST PASS errand=tune_up callbacks=disconnected next_stop=safe persistence=until_action repair=dark_on_light single_line=1280 motion=both")
	quit(0)


func _find_stop(app: Node, kind: String) -> RunSession:
	for attempt in 12:
		var session: RunSession = app.call("start_run", 900004 + attempt * 101)
		if RUN_WALK.walk_to(app, session, kind):
			return session
	return null


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("ACK_LIFETIME_TEST FAIL: " + message)
		quit(1)
	return condition
