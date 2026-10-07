extends SceneTree

## GURI-1740 board slice: the run board renders the active run, enables exactly
## the available nodes, and entering a node moves + persists the session.

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const RUN_UI := preload("res://scripts/ui/run_ui.gd")
const RUN_WALK := preload("res://tests/support/run_walk.gd")

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

	if not _expect(available.size() == 1 and available[0] == sess.current_node_id, "a fresh run offers only its opening race"):
		return

	# The detail column carries the session values.
	var detail := shell.find_child("RunDetail", true, false) as Control
	if not _expect(detail != null, "the board must have its detail column"):
		return
	if not _expect(_has_label(detail, str(sess.run_points)), "the detail must show the run points"):
		return
	if not _expect(_has_label(detail, str(sess.owned_cars.size())), "the detail must show owned cars"):
		return
	if not _expect(_has_label(detail, "%s · %s" % [sess.current_car_id, sess.run_state.get_car_wear(sess.current_car_id)]), "the detail must show car and wear"):
		return
	var legend := shell.find_child("RunLegend", true, false) as Control
	if not _expect(legend != null and legend.get_global_rect().end.y <= root.get_visible_rect().end.y, "the map legend must fit inside the logical viewport"):
		return
	for node_id: String in sess.current_map.nodes:
		var marker := board.get_node_or_null("Node_" + node_id.replace("_", "-")) as Button
		if not _expect(marker != null and marker.icon != null and marker.flat and marker.text.is_empty(), "every stop must be an SVG marker, not a text chip"):
			return
		if not _expect(Rect2(Vector2.ZERO, board.size).encloses(marker.get_rect()), "map markers must stay inside their card"):
			return
		if String(sess.current_map.get_node(node_id).get("type", "")) == "act_rival":
			if not _expect(is_equal_approx(marker.position.x + marker.size.x * 0.5, board.size.x * 0.5), "the act rival must be centred above the route"):
				return
			for other: Node in board.get_children():
				if other is Button and other != marker:
					if not _expect(marker.position.y < (other as Button).position.y, "the act rival must be above ordinary nodes"):
						return

	# Pressing the opening race starts it; once raced, its children open.
	var opening := board.get_node_or_null("Node_" + sess.current_node_id.replace("_", "-")) as Button
	opening.pressed.emit()
	await process_frame
	var race_session: Dictionary = app.get("current_race_session")
	if not _expect(String(race_session.get("run_node_id", "")) == sess.current_node_id, "pressing the opening race must start it"):
		return
	app.call("report_race_result", RUN_WALK.WIN, 1.0, [], false, {})
	shell.call("show_run_board")
	await process_frame
	await process_frame
	board = shell.find_child("RunBoard", true, false) as Control
	var children: Array[Dictionary] = sess.available_nodes()
	if not _expect(not children.is_empty() and String(children[0]["id"]) != sess.current_node_id, "a raced opening offers its children"):
		return
	var target_id := String(children[0]["id"])
	var button := board.get_node_or_null("Node_" + target_id.replace("_", "-")) as Button
	if not _expect(button != null and not button.disabled, "the child marker must be pressable for %s" % target_id):
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

	# Node screens must retain their action and description without clipping the legend.
	var screens := [
		["show_run_bench", "BenchRepair", String(RUN_UI.TYPES["bench"]["copy"])],
		["show_run_parts_van", "VanBuy_spare_shell", String(RUN_UI.TYPES["parts_van"]["copy"])],
		["show_run_lockup", "LockupOpen", String(RUN_UI.TYPES["lockup"]["copy"])],
		["show_run_errand", "ErrandPay", String(RUN_UI.TYPES["errand"]["copy"])],
	]
	for screen: Array in screens:
		shell.call(String(screen[0]))
		for frame in 4:
			await process_frame
		var action := shell.find_child(String(screen[1]), true, false) as Button
		var back := shell.find_child("ActionBack", true, false) as Button
		legend = shell.find_child("RunLegend", true, false) as Control
		if not _expect(action != null and back != null, "%s must retain its actions" % screen[0]):
			return
		if not _expect(_has_label(shell, String(screen[2])), "%s must show its node description" % screen[0]):
			return
		if not _expect(legend != null and legend.get_global_rect().end.y <= root.get_visible_rect().end.y and back.get_global_rect().end.y < legend.get_global_rect().position.y, "%s must keep actions and legend inside the logical viewport" % screen[0]):
			return
	app.call("abandon_run")
	shell.call("show_title")
	await process_frame
	if not _expect((shell.get("_run_backdrop") as ColorRect).visible == false, "leaving a run screen must restore the title backdrop"):
		return
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
