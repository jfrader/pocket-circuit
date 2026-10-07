extends SceneTree

const APP_PATH := "/root/App"
const RACE_SCENE := "res://scenes/race/prototype_race.tscn"
const NUM_CYCLES := 3

var _cycles: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 1.0

	var app := root.get_node_or_null(APP_PATH)
	if not _expect(app != null, "App autoload must exist"):
		return

	if current_scene == null or current_scene.scene_file_path != "res://scenes/boot/boot.tscn":
		change_scene_to_file("res://scenes/boot/boot.tscn")
		await process_frame
		await process_frame

	_cycles.clear()
	for c in NUM_CYCLES:
		var seed := 424242 + c * 1000
		var before := _snapshot_audio("before_%d" % c, app)
		if not await _run_one_quick_race(app, seed):
			return
		var after := _snapshot_audio("after_%d" % c, app)
		_cycles.append({"cycle": c, "before": before, "after": after})
		await _ensure_back_in_boot(app)

	# Assert stability across cycles (small tolerance for pools / transient nodes)
	var first_after: Dictionary = _cycles[0]["after"]
	var last_after: Dictionary = _cycles[_cycles.size() - 1]["after"]
	var bus_delta := int(last_after["bus_count"]) - int(first_after["bus_count"])
	if not _expect(bus_delta == 0, "AudioServer bus count must be stable across cycles, delta=%d" % bus_delta):
		return
	var player_delta := int(last_after["player_count"]) - int(first_after["player_count"])
	if not _expect(player_delta <= 5, "AudioStreamPlayer count must not grow unboundedly (tolerance 5), delta=%d" % player_delta):
		return
	var emitter_delta := int(last_after["emitter_nodes"]) - int(first_after["emitter_nodes"])
	if not _expect(emitter_delta <= 3, "emitter/voice container nodes must not leak (tolerance 3), delta=%d" % emitter_delta):
		return
	var pos_delta := int(last_after["pos_tyre"]) - int(first_after["pos_tyre"]) + int(last_after["pos_engine"]) - int(first_after["pos_engine"])
	if not _expect(pos_delta <= 2, "positional emitters must clear between races (tolerance 2), delta=%d" % pos_delta):
		return

	print("AUDIO_TEARDOWN_TEST PASS")
	quit(0)


func _run_one_quick_race(app: Node, seed: int) -> bool:
	var ok: bool = app.call("start_circuit_race", &"kitchen", &"classic", seed, "rustbug")
	if not _expect(ok, "start_circuit_race must succeed for seed %d" % seed):
		return false

	var deadline := Time.get_ticks_msec() + 30000
	while app.call("is_race_loading") and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _expect(not app.call("is_race_loading"), "loading must complete for seed %d"):
		return false

	await process_frame

	# Force result on the ready grid (exercises audio teardown on report/return)
	var fake_results: Array = [
		{"position": 1, "driver_name": "Rae", "vehicle_name": "Rustbug", "time": 12.0, "finished": true, "dnf": false},
		{"position": 2, "driver_name": "Opp1", "vehicle_name": "Pinbolt", "time": 13.0, "finished": true, "dnf": false},
	]
	var committed: bool = app.call("report_race_result", 1, 12.0, fake_results, false, {})
	if not _expect(committed, "report must succeed for quick race"):
		return false

	await process_frame

	app.call("continue_after_race", true)

	deadline = Time.get_ticks_msec() + 10000
	while current_scene != null and current_scene.scene_file_path == RACE_SCENE and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	await process_frame

	return true


func _ensure_back_in_boot(app: Node) -> bool:
	if current_scene == null or current_scene.scene_file_path != "res://scenes/boot/boot.tscn":
		change_scene_to_file("res://scenes/boot/boot.tscn")
		await process_frame
		await process_frame
	app.set("_quick_roster", {})
	return true


func _snapshot_audio(label: String, app: Node) -> Dictionary:
	var player_count := _count_audio_players(root)
	var bus_count := AudioServer.bus_count
	var emitter_nodes := _count_emitter_like(root)
	var pos_tyre := 0
	var pos_engine := 0
	if app != null:
		var director := app.get_node_or_null("AudioDirector")
		if director != null:
			if director.has_method("get_positional_tyre_emitters"):
				pos_tyre = (director.call("get_positional_tyre_emitters") as Array).size()
			if director.has_method("get_positional_engine_emitters"):
				pos_engine = (director.call("get_positional_engine_emitters") as Array).size()
	return {
		"label": label,
		"player_count": player_count,
		"bus_count": bus_count,
		"emitter_nodes": emitter_nodes,
		"pos_tyre": pos_tyre,
		"pos_engine": pos_engine,
	}


func _count_audio_players(n: Node) -> int:
	var count := 0
	var stack: Array[Node] = [n]
	while stack.size() > 0:
		var cur := stack.pop_back()
		if cur is AudioStreamPlayer or cur is AudioStreamPlayer2D:
			count += 1
		for c in cur.get_children():
			if is_instance_valid(c):
				stack.append(c)
	return count


func _count_emitter_like(n: Node) -> int:
	var count := 0
	var stack: Array[Node] = [n]
	while stack.size() > 0:
		var cur := stack.pop_back()
		var nm := String(cur.name)
		if nm.find("Emitter") != -1 or nm.find("Voice") != -1 or nm.find("TyreVoice") != -1 or nm.find("EnginePlayer") != -1:
			count += 1
		for c in cur.get_children():
			if is_instance_valid(c):
				stack.append(c)
	return count


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("AUDIO_TEARDOWN_TEST FAIL: " + message)
	quit(1)
	return false
