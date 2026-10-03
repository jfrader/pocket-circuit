extends SceneTree

## Functional four-car race gate at the project's real 60 Hz clock.
## PC_BASELINE_FULL, PC_BASELINE_SEED/THEME/ROOM and PC_BASELINE_DIFFICULTY
## select cases; PC_BASELINE_RECORD is retired (no snapshot writes).
## Direct invocations must pass --fixed-fps 60.

const PROTOTYPE_SCENE := preload("res://scenes/race/prototype_race.tscn")
const AI_CONTROLLER_SCRIPT := preload("res://scripts/vehicle/ai_vehicle_controller.gd")
const CATALOG := preload("res://data/championship/catalog.gd")

const SCHEMA_VERSION := 2
const FIXED_FPS := 60
const MAX_RECOVERIES := 3
const MAX_FINISH_GAP_RATIO := 1.80

const DEFAULT_DIFFICULTY := "club_circuit"
const VALID_DIFFICULTIES := ["sunday_drive", "club_circuit", "clockwork"]
const LAPS := 2
const FIELD_SIZE := 4
const SETTLE_FRAMES := 36
const STARTUP_WAIT_FRAMES := 180
const MAX_PHYSICS_FRAMES := 7200

const GATE_SEEDS := [
	{"theme": &"kitchen", "room": &"long", "seed": 24469},
	{"theme": &"workshop", "room": &"square", "seed": 51940},
	{"theme": &"office", "room": &"classic", "seed": 8001},
]
const FULL_SEEDS := [
	{"theme": &"kitchen", "room": &"long", "seed": 24469},
	{"theme": &"workshop", "room": &"square", "seed": 51940},
	{"theme": &"office", "room": &"classic", "seed": 8001},
	{"theme": &"kitchen", "room": &"classic", "seed": 42},
	{"theme": &"kitchen", "room": &"wide", "seed": 12345},
	{"theme": &"workshop", "room": &"tall", "seed": 30000},
	{"theme": &"office", "room": &"long", "seed": 9999},
	{"theme": &"kitchen", "room": &"square", "seed": 7777},
	{"theme": &"workshop", "room": &"classic", "seed": 55555},
	{"theme": &"office", "room": &"el", "seed": 11111},
	{"theme": &"kitchen", "room": &"el", "seed": 43210},
	{"theme": &"workshop", "room": &"wide", "seed": 65000},
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var difficulty := _baseline_difficulty()
	var seed_cases := _seed_cases()
	# Exercise the project's actual clock, not the accelerated seed sweep clock.
	if not _expect(Engine.physics_ticks_per_second == FIXED_FPS, "physics_ticks_per_second must be %d (project default), got %d" % [FIXED_FPS, Engine.physics_ticks_per_second]):
		return
	if not _expect(is_equal_approx(Engine.time_scale, 1.0), "time_scale must be 1.0, got %f" % Engine.time_scale):
		return
	# Godot consumes --fixed-fps before exposing script arguments. Check its
	# effective process step, not the wall-clock FPS cap or physics tick rate.
	await process_frame
	if not _expect(root.get_process_delta_time() == 1.0 / FIXED_FPS, "run with --fixed-fps %d for the deterministic simulation clock" % FIXED_FPS):
		return

	var entries: Array[Dictionary] = []
	for case: Dictionary in seed_cases:
		var result := await _run_race(case, difficulty)
		if result.is_empty():
			return
		entries.append(result)
	var p1_sum := 0.0
	var spread_sum := 0.0
	var dnf_count := 0
	for entry: Dictionary in entries:
		var racers: Array = entry["racers"]
		p1_sum += float(racers[0]["finish_time"]) / LAPS
		spread_sum += (float(racers[-1]["finish_time"]) - float(racers[0]["finish_time"])) / LAPS
		for racer: Dictionary in racers:
			dnf_count += int(bool(racer["dnf"]))
		print("AI_BASELINE_RESULT key=%s order=%s times=%s hash=%s frames=%d" % [entry["key"], str(entry["finish_order"]), _times_str(racers), entry["hash"], entry["frames"]])
	print("AI_BASELINE_METRICS difficulty=%s mean_p1_lap=%.3f mean_spread=%.3f dnf=%d" % [difficulty, p1_sum / entries.size(), spread_sum / entries.size(), dnf_count])

	var document := {
		"schema_version": SCHEMA_VERSION,
		"config": {
			"difficulty": difficulty,
			"fixed_fps": FIXED_FPS,
			"laps": LAPS,
			"field_size": FIELD_SIZE,
			"physics_ticks_per_second": Engine.physics_ticks_per_second,
			"time_scale": Engine.time_scale,
		},
		"seeds": entries,
	}

	var problems := validate_document(document, seed_cases)
	if not _expect(problems.is_empty(), "AI_RACE_BASELINE invalid race:\n%s" % "\n".join(problems)):
		return
	print("AI_RACE_BASELINE_TEST PASS seeds=%d" % entries.size())
	quit(0)


func _baseline_difficulty() -> String:
	var difficulty := OS.get_environment("PC_BASELINE_DIFFICULTY")
	if difficulty in VALID_DIFFICULTIES:
		return difficulty
	return DEFAULT_DIFFICULTY


func _seed_cases() -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	var single := OS.get_environment("PC_BASELINE_SEED")
	if single.is_valid_int():
		var theme := OS.get_environment("PC_BASELINE_THEME")
		var room := OS.get_environment("PC_BASELINE_ROOM")
		cases.append({
			"theme": StringName(theme) if not theme.is_empty() else &"kitchen",
			"room": StringName(room) if not room.is_empty() else &"classic",
			"seed": int(single),
		})
		return cases
	var source: Array = FULL_SEEDS if not OS.get_environment("PC_BASELINE_FULL").is_empty() else GATE_SEEDS
	for entry: Dictionary in source:
		cases.append(entry)
	return cases


func _run_race(case: Dictionary, difficulty: String) -> Dictionary:
	var prototype := PROTOTYPE_SCENE.instantiate()
	prototype.set("_session", {
		"event": {
			"theme": case["theme"],
			"circuit": "generated",
			"room": case["room"],
			"seed": case["seed"],
			"reverse": false,
			"laps": LAPS,
			"length_tier": StringName("standard"),
			"opponents": ["juniper", "milo", "tess"],
			"opponent_count": FIELD_SIZE - 1,
		},
		"difficulty": difficulty,
		"vehicle_id": "rustbug",
	})
	var manager := prototype.get_node("RaceManager") as RaceManager
	manager.finish_grace_seconds = 8.0
	root.add_child(prototype)
	current_scene = prototype
	var player := get_first_node_in_group("player_vehicle") as VehicleController
	if not _expect(player != null, "%s/%s/%d produced no player vehicle" % [case["theme"], case["room"], case["seed"]]):
		current_scene = null
		root.remove_child(prototype)
		prototype.free()
		return {}
	var cass := CATALOG.get_driver("cass")
	var player_controller := AI_CONTROLLER_SCRIPT.new() as AIVehicleController
	player.add_child(player_controller)
	player_controller.configure(player, manager, -10.0, difficulty, "cass", cass.get("ai_style", {}) as Dictionary)
	var racers: Array[Node2D] = manager.get_rankings()
	if not _expect(racers.size() == FIELD_SIZE, "%s/%s/%d created %d racers, expected %d" % [case["theme"], case["room"], case["seed"], racers.size(), FIELD_SIZE]):
		current_scene = null
		root.remove_child(prototype)
		prototype.free()
		return {}
	var gate_order: Array[int] = []
	var finish_index := -1
	for checkpoint: Node in manager.get_ordered_checkpoints():
		if bool(checkpoint.get("is_finish_line")):
			finish_index = int(checkpoint.get("checkpoint_index"))
		else:
			gate_order.append(int(checkpoint.get("checkpoint_index")))
	gate_order.append(finish_index)
	var histories: Dictionary = {}
	for racer: Node2D in racers:
		histories[racer] = []
	manager.racer_checkpoint_passed.connect(func(racer: Node2D, checkpoint_index: int) -> void:
		if histories.has(racer):
			(histories[racer] as Array).append(checkpoint_index)
	)
	# Deterministic settle + countdown, same frame counts as ai_seed_sweep_test
	# but at the real 60 Hz tick rate (each physics frame is 1/60 simulated s).
	for _settle in SETTLE_FRAMES:
		await physics_frame
	paused = false
	var startup_waits := 0
	while not manager.is_running and startup_waits < STARTUP_WAIT_FRAMES:
		await physics_frame
		startup_waits += 1
	if not _expect(manager.is_running, "%s/%s/%d never reached GO" % [case["theme"], case["room"], case["seed"]]):
		current_scene = null
		root.remove_child(prototype)
		prototype.free()
		return {}
	var frame := 0
	while frame < MAX_PHYSICS_FRAMES and not _all_finished(manager, racers):
		await physics_frame
		frame += 1

	var results: Array[Dictionary] = []
	for racer: Node2D in racers:
		var state := manager.get_racer_state(racer)
		var finished := bool(state.get("finished", false))
		var dnf := (not finished) or bool(state.get("dnf", false))
		var finish_time := float(state.get("finish_time", INF))
		var driver := String(state.get("driver_name", ""))
		if driver.is_empty():
			driver = racer.name
		var controller: AIVehicleController = null
		for child: Node in racer.get_children():
			if child is AIVehicleController:
				controller = child as AIVehicleController
		results.append({
			"driver": driver,
			"position": int(state.get("finish_position", 0)),
			"finish_time": _round_time(finish_time),
			"dnf": dnf,
			"finished": finished,
			"lap": int(state.get("lap", 0)),
			"recoveries": controller.recovery_count if controller != null else -1,
			"gates": (histories[racer] as Array).duplicate(),
		})
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["position"]) < int(b["position"]))
	if not OS.get_environment("PC_MISTAKE_TRACE").is_empty():
		for racer: Node2D in racers:
			for child: Node in racer.get_children():
				if child is AIVehicleController:
					print("MISTAKE_TRACE %s/%s/%d %s count=%d" % [case["theme"], case["room"], case["seed"], racer.name, child.mistake_count])
	var finish_order: Array[String] = []
	var hash_parts: Array[String] = []
	for entry: Dictionary in results:
		finish_order.append(String(entry["driver"]))
		hash_parts.append("%s=%d=%.3f=%s" % [entry["driver"], int(entry["position"]), float(entry["finish_time"]), "DNF" if bool(entry["dnf"]) else "FIN"])
	var outcome_hash := ("|".join(hash_parts)).sha256_text()

	current_scene = null
	root.remove_child(prototype)
	prototype.free()
	await process_frame
	await physics_frame
	return {
		"key": "%s/%s/%d" % [case["theme"], case["room"], case["seed"]],
		"theme": String(case["theme"]),
		"room": String(case["room"]),
		"seed": int(case["seed"]),
		"finish_order": finish_order,
		"racers": results,
		"hash": outcome_hash,
		"frames": frame,
		"gate_order": gate_order,
	}


func _all_finished(manager: RaceManager, racers: Array[Node2D]) -> bool:
	for racer: Node2D in racers:
		if not manager.is_racer_finished(racer):
			return false
	return not racers.is_empty()


func _round_time(value: float) -> float:
	return round(value * 1000.0) / 1000.0


func validate_document(document: Dictionary, expected_cases: Array[Dictionary]) -> Array[String]:
	var problems: Array[String] = []
	if not _whole(document.get("schema_version")) or int(document["schema_version"]) != SCHEMA_VERSION:
		problems.append("schema_version")
	var config: Variant = document.get("config")
	if not config is Dictionary:
		return ["config missing"]
	if config.get("difficulty") not in VALID_DIFFICULTIES:
		problems.append("config.difficulty")
	for key: String in ["fixed_fps", "physics_ticks_per_second", "laps", "field_size"]:
		var target := FIXED_FPS if key in ["fixed_fps", "physics_ticks_per_second"] else (LAPS if key == "laps" else FIELD_SIZE)
		if not _whole(config.get(key)) or int(config[key]) != target:
			problems.append("config.%s" % key)
	if not _number(config.get("time_scale")) or float(config["time_scale"]) != 1.0:
		problems.append("config.time_scale")
	var seeds: Variant = document.get("seeds")
	if not seeds is Array or seeds.size() != expected_cases.size():
		problems.append("seed count")
		return problems
	var expected: Dictionary = {}
	for case: Dictionary in expected_cases:
		var key := "%s/%s/%d" % [case["theme"], case["room"], case["seed"]]
		expected[key] = case
	var seen: Dictionary = {}
	for value: Variant in seeds:
		if not value is Dictionary:
			problems.append("seed record missing")
			continue
		var entry: Dictionary = value
		var key := String(entry.get("key", ""))
		if not expected.has(key) or seen.has(key):
			problems.append("unexpected or duplicate seed %s" % key)
			continue
		seen[key] = true
		var case: Dictionary = expected[key]
		if entry.get("theme") != String(case["theme"]) or entry.get("room") != String(case["room"]) or not _whole(entry.get("seed")) or int(entry["seed"]) != int(case["seed"]):
			problems.append("%s seed fields" % key)
		if not _whole(entry.get("frames")) or int(entry["frames"]) <= 0 or int(entry["frames"]) > MAX_PHYSICS_FRAMES:
			problems.append("%s frames" % key)
		var order: Variant = entry.get("gate_order")
		if not order is Array or order.is_empty():
			problems.append("%s gate order" % key)
			continue
		var unique_gates: Dictionary = {}
		for gate: Variant in order:
			if not _whole(gate) or int(gate) < 0 or unique_gates.has(int(gate)):
				problems.append("%s invalid gate order" % key)
				break
			unique_gates[int(gate)] = true
		var racers: Variant = entry.get("racers")
		var finish_order: Variant = entry.get("finish_order")
		if not racers is Array or racers.size() != FIELD_SIZE or not finish_order is Array or finish_order.size() != FIELD_SIZE:
			problems.append("%s field count" % key)
			continue
		var names: Dictionary = {}
		var positions: Dictionary = {}
		var finish_times: Dictionary = {}
		var fastest := INF
		var slowest := 0.0
		for value_racer: Variant in racers:
			if not value_racer is Dictionary:
				problems.append("%s racer record" % key)
				continue
			var racer: Dictionary = value_racer
			var name: Variant = racer.get("driver")
			var position: Variant = racer.get("position")
			if not name is String or name.is_empty() or names.has(name):
				problems.append("%s driver" % key)
			else:
				names[name] = true
			if not _whole(position) or int(position) < 1 or int(position) > FIELD_SIZE or positions.has(int(position)):
				problems.append("%s position" % key)
				continue
			positions[int(position)] = true
			if finish_order[int(position) - 1] != name:
				problems.append("%s finish order" % key)
			if racer.get("finished") != true or racer.get("dnf") != false or not _whole(racer.get("lap")) or int(racer["lap"]) != LAPS:
				problems.append("%s unfinished racer" % key)
			if not _whole(racer.get("recoveries")) or int(racer["recoveries"]) < 0 or int(racer["recoveries"]) > MAX_RECOVERIES:
				problems.append("%s recoveries" % key)
			var gates: Variant = racer.get("gates")
			if not gates is Array or gates.size() != LAPS * order.size():
				problems.append("%s gate history" % key)
			else:
				for gate_index in gates.size():
					if not _whole(gates[gate_index]) or int(gates[gate_index]) != int(order[gate_index % order.size()]):
						problems.append("%s gate history" % key)
						break
			var time: Variant = racer.get("finish_time")
			if not _number(time) or float(time) <= 0.0 or float(time) > float(MAX_PHYSICS_FRAMES) / FIXED_FPS:
				problems.append("%s finish time" % key)
			else:
				finish_times[int(position)] = float(time)
				fastest = minf(fastest, float(time))
				slowest = maxf(slowest, float(time))
		if positions.size() != FIELD_SIZE or names.size() != FIELD_SIZE:
			problems.append("%s incomplete field" % key)
		for position in range(1, FIELD_SIZE):
			if finish_times.has(position) and finish_times.has(position + 1) and float(finish_times[position]) > float(finish_times[position + 1]):
				problems.append("%s finish chronology" % key)
		if fastest > 0.0 and is_finite(fastest) and slowest / fastest > MAX_FINISH_GAP_RATIO:
			problems.append("%s field spread" % key)
	return problems


func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _whole(value: Variant) -> bool:
	return _number(value) and float(value) == floor(float(value))


func _times_str(racers: Array) -> String:
	var parts: Array[String] = []
	for entry: Dictionary in racers:
		parts.append("%s@%.3f%s" % [String(entry.get("driver", "")), float(entry.get("finish_time", 0.0)), "!" if bool(entry.get("dnf", false)) else ""])
	return "[%s]" % ",".join(parts)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("AI_RACE_BASELINE FAIL: " + message)
	quit(1)
	return false
