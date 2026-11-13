extends SceneTree

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const RUN_MAP_VIEW := preload("res://scripts/ui/run_map_view.gd")
const SAVE_PATH := "user://tests/run_board_ux_test.json"


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node("App")
	var boot := preload("res://scenes/boot/boot.tscn").instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	var shell := app.get("_shell") as CanvasLayer
	var store := SAVE_STORE.new(SAVE_PATH)
	store.remove_save()
	app.set("_save_store", store)
	app.call("update_setting", "reduced_motion", true)
	var session: RunSession = app.call("start_new_run")
	shell.call("show_run_board")
	await process_frame
	var snapshot := RunSession.serialize(session)
	var saved: Dictionary = store.load_data()["current_run"]
	var abandon := shell.find_child("ActionAbandon", true, false) as Button
	abandon.pressed.emit()
	await process_frame
	var strip := shell.find_child("AbandonConfirm", true, false) as Control
	if not _expect(strip != null and strip.is_visible_in_tree() and app.call("current_run_session") == session, "ABANDON RUN asks before ending the night"):
		return
	var warning := strip.find_child("AbandonWarning", true, false) as Label
	if not _expect(warning != null and warning.text == "THE NIGHT ENDS - CARS NOT BANKED ARE LOST", "confirmation names the loss"):
		return
	var keep := strip.find_child("ActionKeepDriving", true, false) as Button
	if not _expect(keep != null and keep.text == "KEEP DRIVING" and keep.has_focus(), "the safe choice receives focus"):
		return
	var shot_path := OS.get_environment("PC_SHOT_PATH")
	if not shot_path.is_empty():
		await RenderingServer.frame_post_draw
		if not _expect(root.get_texture().get_image().save_png(shot_path) == OK, "confirmation capture saves"):
			return
	keep.pressed.emit()
	await process_frame
	if not _expect(shell.find_child("AbandonConfirm", true, false) == null and abandon.is_visible_in_tree() and abandon.has_focus() and shell.get("_screen") == "run_board" and app.call("current_run_session") == session and RunSession.serialize(session) == snapshot and store.load_data()["current_run"] == saved, "KEEP DRIVING restores the board without changing the live or saved night"):
		return
	var board := shell.find_child("RunBoard", true, false) as Control
	board.set("reduced_motion", false)
	if not _expect(is_equal_approx(RUN_MAP_VIEW.TRAVEL_TIME, 2.4) and is_equal_approx(float(board.call("travel_to", session.current_node_id)), RUN_MAP_VIEW.TRAVEL_TIME), "normal travel returns the settled 2.4-second beat"):
		return
	board.call("reset_token")
	board.set("reduced_motion", true)
	if not _expect(float(board.call("travel_to", session.current_node_id)) == 0.0, "reduced motion skips travel"):
		return
	abandon.pressed.emit()
	var confirm := shell.find_child("ActionConfirmAbandon", true, false) as Button
	if not _expect(confirm != null and confirm.text == "ABANDON THE NIGHT", "confirmation has an explicit destructive action"):
		return
	confirm.pressed.emit()
	await process_frame
	if not _expect(app.call("current_run_session") == null and shell.get("_screen") == "title" and (store.load_data()["current_run"] as Dictionary).is_empty(), "ABANDON THE NIGHT clears the live and saved night and returns to title"):
		return
	store.remove_save()
	print("RUN_BOARD_UX_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("RUN_BOARD_UX_TEST FAIL: " + message)
	quit(1)
	return false
