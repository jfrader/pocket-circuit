extends SceneTree

## GURI-1740 board slice: the run board renders the active run, enables exactly
## the available nodes, and entering a node moves + persists the session.

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload must exist"):
		return
	# The shell is materialised by the boot scene, like in the controller test.
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	var shell := app.get("_shell") as CanvasLayer
	if not _expect(shell != null, "the shell must exist after boot"):
		return
	var sess: RunSession = app.call("start_new_run") as RunSession
	if not _expect(sess != null, "start_new_run must create a session"):
		return
	shell.call("show_run_board")
	await process_frame
	await process_frame
	var board := shell.find_child("RunBoard", true, false) as Control
	if not _expect(board != null, "the board must render"):
		return

	# The enabled node set must equal available_nodes() exactly.
	var enabled: Array[String] = []
	for child: Node in board.get_children():
		var button := child as Button
		if button != null and not button.disabled:
			enabled.append(String(button.name).replace("-", "_").trim_prefix("Node_"))
	var available: Array[String] = []
	for entry: Dictionary in sess.available_nodes():
		available.append(String(entry.get("id", "")))
	enabled.sort()
	available.sort()
	if not _expect(str(enabled) == str(available), "the enabled nodes must equal available_nodes (got %s want %s)" % [str(enabled), str(available)]):
		return

	# The header carries the session values.
	if not _expect(_has_label(board.get_parent(), str(sess.run_budget)), "the header must show the run budget"):
		return
	if not _expect(_has_label(board.get_parent(), str(sess.run_points)), "the header must show the run points"):
		return

	# Press one available node: the session moves and the save follows.
	if not _expect(available.size() > 0, "the run must have an available node"):
		return
	var target_id: String = available[0]
	var button := board.get_node_or_null("Node_" + target_id.replace("_", "-")) as Button
	if not _expect(button != null, "the node button must exist for %s" % target_id):
		return
	button.pressed.emit()
	await process_frame
	await process_frame
	if not _expect(String(sess.current_node_id) == target_id, "pressing a node must enter it"):
		return
	var live_store: Object = app.get("_save_store")
	var path := String(live_store.get("save_path"))
	var saved: Dictionary = SAVE_STORE.new(path).load_data()
	var saved_run: Dictionary = saved.get("current_run", {}) as Dictionary
	if not _expect(String(saved_run.get("current_node_id", "")) == target_id, "the save must persist the entered node"):
		return

	app.call("abandon_run")
	if _failed:
		return
	print("RUN_BOARD_TEST PASS")
	quit(0)


func _has_label(node: Node, text: String) -> bool:
	if node is Label and String((node as Label).text) == text:
		return true
	for child in node.get_children():
		if _has_label(child, text):
			return true
	return false


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	push_error("RUN_BOARD_TEST FAIL: " + message)
	quit(1)
	return false
