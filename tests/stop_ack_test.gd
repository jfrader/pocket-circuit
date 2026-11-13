extends SceneTree

const RUN_WALK := preload("res://tests/support/run_walk.gd")
const LOCKUP := preload("res://scripts/ui/run_lockup_scene.gd")
const ERRAND := preload("res://scripts/ui/run_errand_scene.gd")
const ACKS := ["ERRAND DONE - +6 POINTS", "ERRAND DONE - TUNE-UP", "ERRAND DONE - TOW"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	var app := root.get_node("App")
	var shell := app.get("_shell") as CanvasLayer
	app.call("dismiss_run_intro")
	for reduced: bool in [false, true]:
		app.call("update_setting", "reduced_motion", reduced)
		for choice: int in RunSession.ErrandChoice.values():
			var session := _find_stop(app, "errand")
			if not _expect(session != null, "fixture reaches errand"):
				return
			session.run_state.set_car_wear(session.current_car_id, "rusty")
			shell.call("show_run_errand")
			for frame in 4:
				await process_frame
			shell.call("_on_errand_choice_pressed", choice)
			await create_timer(ERRAND.STAMP_TIME + 0.15).timeout
			var ack := shell.find_child("ErrandAcknowledgement", true, false) as Label
			if not _expect(shell.get("_screen") == "run_board" and ack != null and ack.text == ACKS[choice] and ack.visible, "exact resolution acknowledgement appears on board"):
				return
			if not _expect(ack.get_theme_stylebox("normal") is StyleBoxFlat and ack.focus_mode == Control.FOCUS_NONE and root.gui_get_focus_owner() != null, "status tape does not delay board focus"):
				return
			var board := shell.get("_run_board") as Control
			board.call("preview", session.current_node_id)
			await process_frame
			if not _expect(shell.find_child("ErrandAcknowledgement", true, false) == null, "next board selection clears acknowledgement"):
				return
			shell.call("show_run_board")
			if not _expect(shell.find_child("ErrandAcknowledgement", true, false) == null, "acknowledgement does not replay on board reopen"):
				return
		var session := _find_stop(app, "lockup")
		if not _expect(session != null, "fixture reaches lockup"):
			return
		shell.call("show_run_lockup")
		for frame in 4:
			await process_frame
		var open := shell.find_child("LockupOpen", true, false) as Button
		open.pressed.emit()
		var owned := session.owned_cars.size()
		if not _expect(open.disabled and open.text == "OPENING LOCKUP", "opening action is disabled during reveal"):
			return
		open.pressed.emit()
		if not _expect(shell.get("_screen") == "run_lockup" and session.owned_cars.size() == owned, "repeated opening cannot interrupt reveal or grant another car"):
			return
		await create_timer(LOCKUP.STAMP_TIME + LOCKUP.UNLOCK_TIME + LOCKUP.DOOR_TIME + LOCKUP.ROLL_TIME + LOCKUP.HOLD_TIME + 0.15).timeout
		if not _expect(shell.get("_screen") == "run_offer" and shell.find_child("LockupOpen", true, false) == null and shell.find_child("ActionTakeOffer", true, false) != null and shell.find_child("ActionKeepCar", true, false) != null, "completed reveal replaces opening with drive/keep offer"):
			return
	print("STOP_ACK_TEST PASS errand=pay_tune_up_tow clear=next_action lockup=disabled_during_reveal follow_up=offer reduced_motion=covered")
	quit(0)


func _find_stop(app: Node, kind: String) -> RunSession:
	for attempt in 12:
		var session: RunSession = app.call("start_run", 900004 + attempt * 101)
		if RUN_WALK.walk_to(app, session, kind):
			return session
	return null


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("STOP_ACK_TEST FAIL: " + message)
		quit(1)
	return condition
