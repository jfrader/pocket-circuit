extends SceneTree

const SESSION := preload("res://scripts/progression/run_session.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const RUN_UI := preload("res://scripts/ui/run_ui.gd")
var _failed := false


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
	var solo: RunSession = app.call("start_run", 33333)
	_move_to(solo, "bench")
	shell.call("show_run_bench")
	_expect(shell.find_child("BenchSwap", true, false) == null, "no spares means no swap action")
	_expect(not bool(solo.call("bench_swap", solo.current_car_id)), "cannot swap to the current car")
	_expect(not solo.bench_action_done, "invalid swap leaves visit unused")
	var sess: RunSession = app.call("start_run", 33333)
	var starter := sess.current_car_id
	_move_to(sess, "rival")
	sess.resolve_rival(sess.current_node_id, true)
	var won := sess.pending_offer
	_expect(sess.take_offer(), "offer swap still switches cars")
	_move_to(sess, "bench")
	sess.run_state.set_car_wear(starter, "rusty")
	sess.run_state.set_car_wear(won, "dusty")
	sess.parts_held = RunParts.deal(sess.run_seed, sess.car_stats(starter))
	sess.installed_parts[starter] = [sess.parts_held[0].duplicate(true)]
	sess.installed_parts[won] = [sess.parts_held[1].duplicate(true)]
	var before := SESSION.serialize(sess).duplicate(true)
	shell.call("show_run_bench")
	var swap := shell.find_child("BenchSwap", true, false) as Button
	_expect(swap != null and not swap.disabled, "unused bench offers swap with an owned starter spare")
	if swap == null:
		quit(1)
		return
	swap.pressed.emit()
	var choice := shell.find_child("BenchSwapCar_0", true, false) as Button
	_expect(choice != null and choice.is_visible_in_tree(), "swap opens spare list")
	if choice == null:
		quit(1)
		return
	_expect(choice.icon == IDENTITIES.car_texture(starter) and choice.text == RUN_UI.car_name(starter), "spare shows its identity and name")
	choice.pressed.emit()
	_expect(sess.current_car_id == starter and sess.bench_action_done, "swap switches current car and consumes visit")
	var after := SESSION.serialize(sess)
	for key: String in ["installed_parts", "owned_cars", "run_state"]:
		_expect(after[key] == before[key], "swap preserves both cars' state: " + key)
	var saved: Dictionary = app.call("get_save_data")
	var restored := SESSION.deserialize(JSON.parse_string(JSON.stringify(saved["current_run"])))
	_expect(restored != null and restored.current_car_id == starter and restored.bench_action_done, "adapter persists swap through JSON roundtrip")
	if restored != null:
		var roundtrip := SESSION.serialize(restored)
		for key: String in ["installed_parts", "owned_cars", "run_state"]:
			_expect(JSON.stringify(roundtrip[key]) == JSON.stringify(after[key]), "roundtrip preserves car state: " + key)
	_expect(not sess.bench_repair(starter) and not sess.bench_fit(starter, 0) and not sess.bench_bank_haul() and not bool(sess.call("bench_swap", won)), "swap excludes repair fit bank and repeat swap")
	shell.call("show_run_bench")
	_expect(shell.find_child("BenchSwap", true, false) == null, "used bench offers no swap")
	for action: String in ["repair", "fit", "bank"]:
		var fixture := SESSION.deserialize(before)
		if action == "repair":
			_expect(fixture.bench_repair(won), "repair fixture consumes visit")
		elif action == "fit":
			_expect(fixture.bench_fit(won, 0), "fit fixture consumes visit")
		else:
			fixture.boot_cars[won] = {}
			_expect(fixture.bench_bank_haul(), "bank fixture consumes visit")
		_expect(not bool(fixture.call("bench_swap", starter)), action + " excludes swap")
	var invalid := SESSION.deserialize(before)
	_expect(not bool(invalid.call("bench_swap", "unknown")), "unowned car rejected")
	_move_to(invalid, "parts_van")
	_expect(not bool(invalid.call("bench_swap", starter)), "swap rejected outside bench")
	invalid = SESSION.deserialize(before)
	invalid.failed = true
	_expect(not bool(invalid.call("bench_swap", starter)), "failed night rejects swap")
	invalid.failed = false
	invalid.completed = true
	_expect(not bool(invalid.call("bench_swap", starter)), "completed night rejects swap")
	if _failed:
		quit(1)
		return
	print("RUN_BENCH_SWAP_TEST PASS switch=owned visit=exclusive state=preserved persistence=roundtrip ui=identity_spares")
	quit(0)


func _move_to(sess: RunSession, kind: String) -> void:
	for node: Dictionary in sess.current_map.nodes.values():
		if node["type"] == kind:
			sess.current_node_id = node["id"]
			sess.run_state.row = node["row"]
			if kind == "bench":
				sess.last_bench_visited = node["id"]
				sess.bench_action_done = false
			return
	_expect(false, "fixture stop exists: " + kind)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("RUN_BENCH_SWAP_TEST FAIL: " + message)
