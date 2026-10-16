extends SceneTree

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const RUN_WALK := preload("res://tests/support/run_walk.gd")
const STOP_TYPES: Array[String] = ["bench", "parts_van", "lockup", "errand"]
const SAVE_PATH := "user://tests/run_stop_reopen_test.json"

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload exists"):
		return
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	var shell := app.get("_shell") as CanvasLayer
	var store := SAVE_STORE.new(SAVE_PATH)
	store.remove_save()
	app.set("_save_store", store)
	app.call("update_setting", "reduced_motion", true)
	for kind: String in STOP_TYPES:
		var session := _find_stop(app, kind)
		if not _expect(session != null, "a generated route reaches " + kind):
			return
		var stop_id := session.current_node_id
		if kind == "parts_van":
			# Enough for repeated purchases: refusal must be the used-stop guard.
			session.run_points = 2 * RunParts.cost(session.van_stock()[0])
			app.call("persist_current_run")
		var children := session.current_map.get_children(stop_id)
		if not _expect(not children.is_empty(), kind + " has a child route"):
			return
		var snapshot := RunSession.serialize(session)
		if not _expect(_available(session, stop_id), kind + " remains available while unused"):
			return
		for child: Dictionary in children:
			if not _expect(_available(session, String(child["id"])), kind + " keeps optional child routes available"):
				return
		if not _expect(session.enter_node(stop_id) and RunSession.serialize(session) == snapshot, kind + " reopens without resetting domain state"):
			return
		shell.call("show_run_board")
		if not _expect(_board_can_open(shell, stop_id), kind + " is selectable on the board"):
			return
		shell.call("_go_to_run_stop", stop_id, false)
		await process_frame
		if not _expect(String(shell.get("_screen")) == "run_" + kind, kind + " opens through the board GO action"):
			return
		var back := shell.find_child("ActionBack", true, false) as Button
		if not _expect(back != null, kind + " offers BACK"):
			return
		back.pressed.emit()
		await process_frame
		if not _expect(String(shell.get("_screen")) == "run_board" and _board_can_open(shell, stop_id), kind + " remains open after BACK"):
			return
		app.call("persist_current_run")
		var loaded := RunSession.deserialize(SAVE_STORE.new(SAVE_PATH).load_data()["current_run"])
		if not _expect(loaded != null and _available(loaded, stop_id), kind + " remains open after a saved restart"):
			return
		app.set("_current_run_session", loaded)
		app.call("_install_held_vehicles")
		shell.call("show_run_board")
		shell.call("_go_to_run_stop", stop_id, false)
		await process_frame
		if not _expect(String(shell.get("_screen")) == "run_" + kind, kind + " reopens through App/UI after loading"):
			return
		if not _expect(_use_stop(app, loaded, kind), kind + " action succeeds once"):
			return
		if not loaded.pending_offer.is_empty():
			app.call("run_decline_offer")
		var used := RunSession.serialize(loaded)
		if not _expect(not _available(loaded, stop_id) and not loaded.enter_node(stop_id) and not _use_stop(app, loaded, kind) and RunSession.serialize(loaded) == used, kind + " action cannot repeat or reopen once used"):
			return
		shell.call("show_run_board")
		shell.call("_on_run_node_pressed", stop_id)
		if not _expect(String(shell.get("_screen")) == "run_board", kind + " refuses a used stop through App/UI"):
			return
		var used_loaded := RunSession.deserialize(SAVE_STORE.new(SAVE_PATH).load_data()["current_run"])
		if not _expect(used_loaded != null and not _available(used_loaded, stop_id) and not used_loaded.enter_node(stop_id), kind + " stays used after loading"):
			return
		app.set("_current_run_session", used_loaded)
		var used_saved := RunSession.serialize(used_loaded)
		if not _expect(not _use_stop(app, used_loaded, kind) and RunSession.serialize(used_loaded) == used_saved, kind + " refuses its used action after loading"):
			return
		if kind == "lockup":
			if not _expect(used_loaded.lockup_used and used_loaded.open_lockup().is_empty(), "the act's lockup scarcity survives loading"):
				return
		# Taking a child instead of the optional action retires the old stop.
		var skipped := RunSession.deserialize(snapshot)
		if not _expect(skipped != null and skipped.enter_node(String(children[0]["id"])) and not _available(skipped, stop_id) and not skipped.enter_node(stop_id), kind + " cannot be revisited after choosing a child route"):
			return
		app.set("_current_run_session", skipped)
		app.call("persist_current_run")
		shell.call("show_run_board")
		shell.call("_on_run_node_pressed", stop_id)
		if not _expect(String(shell.get("_screen")) == "run_board" and not bool(app.call("enter_run_node", stop_id)), kind + " is retired through App/UI after leaving"):
			return
	app.call("abandon_run")
	store.remove_save()
	if _failed:
		return
	print("RUN_STOP_REOPEN_TEST PASS")
	quit(0)


func _find_stop(app: Object, kind: String) -> RunSession:
	for attempt in 12:
		var session: RunSession = app.call("start_run", 180600 + attempt * 37) as RunSession
		if RUN_WALK.walk_to(app, session, kind):
			return session
	return null


func _available(session: RunSession, stop_id: String) -> bool:
	return session.available_nodes().any(func(node: Dictionary) -> bool: return String(node["id"]) == stop_id)


func _board_can_open(shell: CanvasLayer, stop_id: String) -> bool:
	var board: Control = shell.get("_run_board")
	return board != null and bool(board.call("is_reachable", stop_id))


func _use_stop(app: Object, session: RunSession, kind: String) -> bool:
	match kind:
		"bench":
			return bool(app.call("run_bench_repair", session.current_car_id))
		"parts_van":
			return bool(app.call("run_buy_part", String(session.van_stock()[0]["part"])))
		"lockup":
			return bool(app.call("run_open_lockup"))
		"errand":
			return bool(app.call("run_resolve_errand", 0))
	return false


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	push_error("RUN_STOP_REOPEN_TEST FAIL: " + message)
	quit(1)
	return false
