extends SceneTree

const PROTOTYPE_SCENE := preload("res://scenes/race/prototype_race.tscn")
const AI_CONTROLLER_SCRIPT := preload("res://scripts/vehicle/ai_vehicle_controller.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
const LAPS := 3
const CHECKPOINTS_PER_LAP := 8
const MAX_PHYSICS_FRAMES := 7200
const MAX_RECOVERIES := 3
const MAX_FINISH_GAP_RATIO := 1.80


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	Engine.time_scale = 1.0
	# Use production grace (8 s) instead of the harness's long inspection grace.
	# Hook before any add_child so the RaceManager instances pick it up.
	node_added.connect(func(node: Node) -> void:
		if node is RaceManager:
			(node as RaceManager).finish_grace_seconds = 8.0
	)
	var theme_only := String(OS.get_environment("PC_THEME_ONLY"))
	for case: Array in [[&"kitchen", &"classic", 0], [&"workshop", &"wide", 1], [&"office", &"el", 7], [&"kitchen", &"long", 24469], [&"workshop", &"square", 51940], [&"office", &"tall", 42]]:
		if not theme_only.is_empty() and case[0] != StringName(theme_only):
			continue
		if not await _run_theme(case[0], case[1], case[2]):
			return
	Engine.time_scale = 1.0
	print("AI_FIELD_SPREAD_TEST PASS six_routes_production_grace")
	quit(0)


func _run_theme(theme: StringName, room: StringName, seed: int) -> bool:
	var prototype := PROTOTYPE_SCENE.instantiate()
	prototype.set("_session", {
		"event": {
			"theme": theme,
			"circuit": "generated",
			"room": room,
			"seed": seed,
			"reverse": false,
			"laps": LAPS,
			"opponents": ["juniper", "milo", "tess"],
			"opponent_count": 3,
		},
		"difficulty": "club_circuit",
	})
	var manager := prototype.get_node("RaceManager") as RaceManager
	root.add_child(prototype)
	current_scene = prototype

	var player := get_first_node_in_group("player_vehicle") as VehicleController
	if not _expect(player != null, "%s should create the fourth race vehicle" % theme):
		return false
	var cass := CATALOG.get_driver("cass")
	var cass_controller := AI_CONTROLLER_SCRIPT.new() as AIVehicleController
	player.add_child(cass_controller)
	cass_controller.configure(
		player,
		manager,
		-10.0,
		"club_circuit",
		"cass",
		cass.get("ai_style", {}) as Dictionary
	)

	var checkpoint_history: Dictionary = {}
	var position_events := {"count": 0}
	manager.racer_checkpoint_passed.connect(func(racer: Node2D, checkpoint_index: int) -> void:
		if checkpoint_history.has(racer):
			(checkpoint_history[racer] as Array).append(checkpoint_index)
	)
	manager.position_changed.connect(func(_racer: Node2D, _position: int, _racer_count: int) -> void:
		if manager.is_running and manager.race_time > 0.5:
			position_events["count"] = int(position_events["count"]) + 1
	)
	var racers := manager.get_rankings()
	if not _expect(racers.size() == 4, "%s should run a four-AI field" % theme):
		return false
	for racer: Node2D in racers:
		if not _expect(_get_ai_controller(racer) != null, "%s %s should use AI control" % [theme, racer.name]):
			return false
		checkpoint_history[racer] = []

	# Deterministic settle: the old 6 x 0.1 s wall-clock timers covered 0.6 s of
	# simulated time, which is 36 physics frames here (physics_ticks / time_scale
	# = 60 frames per simulated second). Stepping physics frames directly keeps
	# the settle independent of rendered frame rate, so the cars reach the start
	# line in the same state every run.
	for _settle in 36:
		await physics_frame
	paused = false
	# Bounded condition wait: poll the manager's running state on physics frames
	# instead of wall-clock timers, with the old 30 x 0.1 s = 3.0 s budget
	# converted to 180 physics frames.
	var startup_waits := 0
	while not manager.is_running and startup_waits < 180:
		await physics_frame
		startup_waits += 1
	if not _expect(manager.is_running, "%s should finish its countdown (paused=%s countdown_active=%s race_time=%.2f)" % [theme, str(paused), str(prototype.get("_countdown_active")), manager.race_time]):
		return false

	var frame := 0
	while frame < MAX_PHYSICS_FRAMES and not _all_finished(manager, racers):
		await physics_frame
		frame += 1
	if not _expect(_all_finished(manager, racers), "%s four-AI field should finish three laps within the frame budget" % theme):
		return false

	var legal_gate_order := _legal_gate_order(manager)
	var finish_times: Array[float] = []
	var overtake_attempts := 0
	for racer: Node2D in racers:
		var history := checkpoint_history[racer] as Array
		if not _expect(history.size() == LAPS * CHECKPOINTS_PER_LAP, "%s %s should pass exactly %d ordered gates (passes=%d history=%s)" % [theme, racer.name, LAPS * CHECKPOINTS_PER_LAP, history.size(), str(history)]):
			return false
		for gate_index in history.size():
			if not _expect(int(history[gate_index]) == legal_gate_order[gate_index % legal_gate_order.size()], "%s %s should follow the legal gate order at pass %d" % [theme, racer.name, gate_index + 1]):
				return false
		var state := manager.get_racer_state(racer)
		if not _expect(bool(state.get("finished", false)) and not bool(state.get("dnf", true)), "%s %s should finish without a DNF" % [theme, racer.name]):
			return false
		finish_times.append(float(state.get("finish_time", INF)))
		var controller := _get_ai_controller(racer)
		if not _expect(controller.recovery_count <= MAX_RECOVERIES, "%s %s should use at most %d recoveries (recoveries=%d)" % [theme, racer.name, MAX_RECOVERIES, controller.recovery_count]):
			return false
		overtake_attempts += controller.overtake_attempt_count

	var fastest: float = finish_times.min()
	var slowest: float = finish_times.max()
	var gap_ratio: float = slowest / maxf(fastest, 0.001)
	if not _expect(int(position_events["count"]) >= 2, "%s should produce at least one on-track position exchange" % theme):
		return false
	if not _expect(overtake_attempts >= 1, "%s should produce at least one deliberate pass attempt" % theme):
		return false
	if not _expect(gap_ratio <= MAX_FINISH_GAP_RATIO, "%s field spread should stay bounded (ratio=%.3f, max=%.2f)" % [theme, gap_ratio, MAX_FINISH_GAP_RATIO]):
		return false
	print(
		"AI_FIELD_SPREAD theme=%s room=%s seed=%d laps=%d finish_times=%s gap_ratio=%.3f position_events=%d overtake_attempts=%d"
		% [theme, str(room), seed, LAPS, str(finish_times), gap_ratio, int(position_events["count"]), overtake_attempts]
	)

	current_scene = null
	prototype.queue_free()
	await process_frame
	return true


func _all_finished(manager: RaceManager, racers: Array[Node2D]) -> bool:
	if racers.size() != 4:
		return false
	for racer: Node2D in racers:
		if not manager.is_racer_finished(racer):
			return false
	return true


func _legal_gate_order(manager: RaceManager) -> Array[int]:
	var order: Array[int] = []
	var finish_index := -1
	for checkpoint: Node in manager.get_ordered_checkpoints():
		if bool(checkpoint.get("is_finish_line")):
			finish_index = int(checkpoint.get("checkpoint_index"))
		else:
			order.append(int(checkpoint.get("checkpoint_index")))
	order.append(finish_index)
	return order


func _get_ai_controller(racer: Node) -> AIVehicleController:
	for child: Node in racer.get_children():
		if child is AIVehicleController:
			return child as AIVehicleController
	return null


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	Engine.time_scale = 1.0
	push_error("AI_FIELD_SPREAD_TEST FAIL: " + message)
	quit(1)
	return false
