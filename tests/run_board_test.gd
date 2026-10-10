extends SceneTree

## GURI-1740 board slice: the run board renders the active run, enables exactly
## the available nodes, and entering a node moves + persists the session.

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const RUN_UI := preload("res://scripts/ui/run_ui.gd")
const RUN_WALK := preload("res://tests/support/run_walk.gd")
const RUN_MAP_VIEW := preload("res://scripts/ui/run_map_view.gd")

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

	# Every stop can be picked to read it; the reachable ones are available_nodes().
	var reachable: Array[String] = []
	for child: Node in board.get_children():
		var marker_button := child as Button
		if marker_button == null or not marker_button.has_meta("stop_id"):
			continue
		if not _expect(not marker_button.disabled, "every stop must be pickable"):
			return
		if bool(marker_button.get_meta("reachable")):
			reachable.append(String(marker_button.get_meta("stop_id")))
	var available: Array[String] = []
	for entry: Dictionary in sess.available_nodes():
		available.append(String(entry.get("id", "")))
	reachable.sort()
	available.sort()
	if not _expect(str(reachable) == str(available), "the reachable stops must equal available_nodes (got %s want %s)" % [str(reachable), str(available)]):
		return
	if not _expect(available.size() == 1 and available[0] == sess.current_node_id, "a fresh run offers only its opening race"):
		return
	# The board opens on the opening race, picked, with its card and a live RACE.
	var go := shell.find_child("RunGo", true, false) as Button
	if not _expect(board.call("selected_id") == sess.current_node_id and go != null and not go.disabled and go.text == String(RUN_UI.GO_LABELS["race"]), "the board opens on the opening race with RACE ready"):
		return
	var circuit: Dictionary = app.call("run_stop_circuit", sess.current_node_id)
	if not _expect(_has_label_containing(shell.find_child("RunStop", true, false), String(circuit.get("display_name", "?"))), "the stop card names the circuit it races on"):
		return

	# The detail column carries the session values.
	var detail := shell.find_child("RunDetail", true, false) as Control
	if not _expect(detail != null, "the board must have its detail column"):
		return
	if not _expect(_has_label(detail, str(sess.run_points)), "the detail must show the run points"):
		return
	if not _expect(_has_label(detail, str(sess.owned_cars.size())), "the detail must show owned cars"):
		return
	if not _expect(_has_label(detail, "%s · %s" % [RUN_UI.car_name(sess.current_car_id), sess.run_state.get_car_wear(sess.current_car_id)]), "the detail must show the car's name and wear"):
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

	# Pressing the picked opening race goes: the car drives there and it starts.
	var opening := board.get_node_or_null("Node_" + sess.current_node_id.replace("_", "-")) as Button
	opening.pressed.emit()
	await _settle_travel()
	var race_session: Dictionary = app.get("current_race_session")
	if not _expect(String(race_session.get("run_node_id", "")) == sess.current_node_id, "pressing the picked opening race must start it"):
		return
	app.call("report_race_result", RUN_WALK.WIN, 1.0, [], false, {})
	shell.call("show_run_board")
	await process_frame
	await process_frame
	board = shell.find_child("RunBoard", true, false) as Control
	var children: Array[Dictionary] = sess.available_nodes()
	if not _expect(not children.is_empty() and String(children[0]["id"]) != sess.current_node_id, "a raced opening offers its children"):
		return
	# Picking a stop only shows it; an out-of-reach stop cannot be gone to.
	var standing := sess.current_node_id
	var far_id := ""
	for node_id: String in sess.current_map.nodes:
		if node_id != standing and not sess.available_nodes().any(func(n: Dictionary) -> bool: return n["id"] == node_id):
			far_id = node_id
	(board.get_node_or_null("Node_" + far_id.replace("_", "-")) as Button).pressed.emit()
	await process_frame
	go = shell.find_child("RunGo", true, false) as Button
	if not _expect(sess.current_node_id == standing and board.call("selected_id") == far_id and go.disabled and _has_label(shell, "OUT OF REACH"), "picking an out-of-reach stop shows it and offers no way there"):
		return
	var target_id := String(children[children.size() - 1]["id"])
	var button := board.get_node_or_null("Node_" + target_id.replace("_", "-")) as Button
	button.pressed.emit()
	await _settle_travel()
	var target_kind := String(sess.current_map.get_node(target_id)["type"])
	if not _expect(sess.current_node_id == standing and board.call("selected_id") == target_id and _has_label(shell, String(RUN_UI.TYPES[target_kind]["name"])), "picking a reachable stop shows it without going"):
		return
	(shell.find_child("RunGo", true, false) as Button).pressed.emit()
	await _settle_travel()
	if not _expect(String(sess.current_node_id) == target_id, "the go button must enter the picked stop"):
		return
	var live_store: Object = app.get("_save_store")
	var path := String(live_store.get("save_path"))
	var saved: Dictionary = SAVE_STORE.new(path).load_data()
	var saved_run: Dictionary = saved.get("current_run", {}) as Dictionary
	if not _expect(String(saved_run.get("current_node_id", "")) == target_id, "the save must persist the entered node"):
		return

	# Node screens must retain their action and description without clipping the
	# legend; the bench with a full pile of parts is its tallest. The van is
	# checked on a real van in run_parts_test.
	sess.parts_held = RunParts.deal(7, sess.car_stats(sess.current_car_id))
	# A long night of fits wraps under the car instead of widening the column.
	var night_of_fits: Array = []
	for stop_roll: int in 3:
		night_of_fits.append_array(RunParts.deal(8 + stop_roll, sess.car_stats(sess.current_car_id)))
	sess.installed_parts[sess.current_car_id] = night_of_fits
	var screens := [
		["show_run_bench", "BenchFit_%d" % (RunParts.VAN_STOCK - 1), String(RUN_UI.TYPES["bench"]["copy"])],
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
		var side := shell.find_child("BenchParts", true, false) as Control
		if side == null:
			side = shell.find_child("RunContextMap", true, false) as Control
		if not _expect(side != null and side.get_global_rect().end.x <= root.get_visible_rect().end.x, "%s must keep its right-hand card inside the logical viewport" % screen[0]):
			return
	# Reduced motion: the map is whole at once and the car arrives without driving.
	app.call("update_setting", "reduced_motion", true)
	shell.call("show_run_board")
	await process_frame
	board = shell.find_child("RunBoard", true, false) as Control
	var markers_rest := true
	for child: Node in board.get_children():
		if child is Button and ((child as Button).modulate.a < 1.0 or not (child as Button).scale.is_equal_approx(Vector2.ONE * (RUN_MAP_VIEW.SELECTED_SCALE if String(child.get_meta("stop_id", "")) == board.call("selected_id") else 1.0))):
			markers_rest = false
	var started := Time.get_ticks_msec()
	await board.call("travel_to", String(board.call("selected_id")))
	if not _expect(float(board.get("_reveal")) == 1.0 and markers_rest and Time.get_ticks_msec() - started < int(RUN_MAP_VIEW.TRAVEL_TIME * 1000.0), "with reduced motion the board shows at rest and the car does not drive"):
		return
	app.call("update_setting", "reduced_motion", false)
	# With a run in progress the title offers to continue it, not to replace it.
	shell.call("show_title")
	await process_frame
	var continue_button := _button_with_text(shell, "YOUR RUN")
	if not _expect(continue_button != null and _button_with_text(shell, "NEW RUN") == null, "the title offers YOUR RUN while a run is on"):
		return
	continue_button.pressed.emit()
	await process_frame
	if not _expect(shell.find_child("RunBoard", true, false) != null and app.call("current_run_session") == sess, "YOUR RUN returns to the same run"):
		return
	app.call("abandon_run")
	shell.call("show_title")
	await process_frame
	if not _expect(_button_with_text(shell, "NEW RUN") != null, "with no run the title offers NEW RUN"):
		return
	if not _expect((shell.get("_run_backdrop") as ColorRect).visible == false, "leaving a run screen must restore the title backdrop"):
		return
	if _failed:
		return
	print("RUN_BOARD_TEST PASS")
	quit(0)


func _button_with_text(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text and (node as Button).is_visible_in_tree():
		return node as Button
	for child in node.get_children():
		var found := _button_with_text(child, text)
		if found != null:
			return found
	return null


## Waits out the car's drive along the map.
func _settle_travel() -> void:
	await create_timer(RUN_MAP_VIEW.TRAVEL_TIME + 0.3).timeout


func _has_label_containing(node: Node, text: String) -> bool:
	if node == null:
		return false
	if node is Label and String((node as Label).text).contains(text):
		return true
	for child in node.get_children():
		if _has_label_containing(child, text):
			return true
	return false


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
