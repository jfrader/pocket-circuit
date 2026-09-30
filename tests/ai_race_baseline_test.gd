extends SceneTree

## Strict deterministic race-outcome baseline.
##
## Runs a fixed seed list at the project's REAL physics settings — it does NOT
## change Engine.physics_ticks_per_second or Engine.time_scale (unlike
## ai_seed_sweep_test.gd, which forces 240 Hz / 4x to stay fast). For each seed
## it records the finishing order, every racer's finish time, DNF flags, and a
## SHA-256 hash of that outcome, then compares the run against the checked-in
## baseline file `tests/ai_race_baseline.json`.
##
## Modes (via environment):
##   (default)                 run the small gate seed list and verify vs baseline
##   PC_BASELINE_RECORD=1      run and (re)write the baseline file
##   PC_BASELINE_FULL=1        run the full seed list instead of the gate list
##   PC_BASELINE_SEED=<n>      run a single ad-hoc seed (theme/room via env)
##
## The gate globs `tests/*.gd`, so the default list is small (3 seeds x 2 laps).
## The full sweep is opt-in because it is long at real time-scale.

const PROTOTYPE_SCENE := preload("res://scenes/race/prototype_race.tscn")
const AI_CONTROLLER_SCRIPT := preload("res://scripts/vehicle/ai_vehicle_controller.gd")
const CATALOG := preload("res://data/championship/catalog.gd")

const BASELINE_PATH := "res://tests/ai_race_baseline.json"
const SCHEMA_VERSION := 1

const DIFFICULTY := "club_circuit"
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
	var record := not OS.get_environment("PC_BASELINE_RECORD").is_empty()
	var seed_cases := _seed_cases()
	var baseline := _load_baseline()

	# This baseline only means something at the project's default tick rate and
	# time scale. A project tick-rate change must fail here, not drift silently.
	if not _expect(Engine.physics_ticks_per_second == 60, "physics_ticks_per_second must be 60 (project default), got %d" % Engine.physics_ticks_per_second):
		return
	if not _expect(is_equal_approx(Engine.time_scale, 1.0), "time_scale must be 1.0, got %f" % Engine.time_scale):
		return

	var entries: Array[Dictionary] = []
	for case: Dictionary in seed_cases:
		var result := await _run_race(case)
		if result.is_empty():
			return
		entries.append(result)

	var document := {
		"schema_version": SCHEMA_VERSION,
		"godot_version": String(Engine.get_version_info().get("string", "")),
		"config": {
			"difficulty": DIFFICULTY,
			"laps": LAPS,
			"field_size": FIELD_SIZE,
			"physics_ticks_per_second": Engine.physics_ticks_per_second,
			"time_scale": Engine.time_scale,
		},
		"seeds": entries,
	}

	if record:
		_write_baseline(document)
		print("AI_RACE_BASELINE RECORDED seeds=%d -> %s" % [entries.size(), BASELINE_PATH])
		quit(0)
		return

	if baseline.is_empty():
		# Baseline not recorded yet. Keep the gate green but make the gap loud.
		print("AI_RACE_BASELINE SKIP: %s missing; run with PC_BASELINE_RECORD=1 to record" % BASELINE_PATH)
		quit(0)
		return

	var problems := _compare(document, baseline)
	if not _expect(problems.is_empty(), "AI_RACE_BASELINE MISMATCH:\n%s" % "\n".join(problems)):
		return
	print("AI_RACE_BASELINE PASS seeds=%d" % entries.size())
	quit(0)


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


func _run_race(case: Dictionary) -> Dictionary:
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
		"difficulty": DIFFICULTY,
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
	player_controller.configure(player, manager, -10.0, DIFFICULTY, "cass", cass.get("ai_style", {}) as Dictionary)
	var racers: Array[Node2D] = manager.get_rankings()
	if not _expect(racers.size() == FIELD_SIZE, "%s/%s/%d created %d racers, expected %d" % [case["theme"], case["room"], case["seed"], racers.size(), FIELD_SIZE]):
		current_scene = null
		root.remove_child(prototype)
		prototype.free()
		return {}
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
		if not is_finite(finish_time):
			finish_time = float(state.get("elapsed", INF))
		var driver := String(state.get("driver_name", ""))
		if driver.is_empty():
			driver = racer.name
		results.append({
			"driver": driver,
			"position": int(state.get("finish_position", 0)),
			"finish_time": _round_time(finish_time),
			"dnf": dnf,
		})
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["position"]) < int(b["position"]))
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
	}


func _all_finished(manager: RaceManager, racers: Array[Node2D]) -> bool:
	for racer: Node2D in racers:
		if not manager.is_racer_finished(racer):
			return false
	return not racers.is_empty()


func _round_time(value: float) -> float:
	return round(value * 1000.0) / 1000.0


func _load_baseline() -> Dictionary:
	if not FileAccess.file_exists(BASELINE_PATH):
		return {}
	var file := FileAccess.open(BASELINE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


func _write_baseline(document: Dictionary) -> void:
	var file := FileAccess.open(BASELINE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("AI_RACE_BASELINE FAIL: cannot write %s" % BASELINE_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(document, "  ") + "\n")
	file.close()


func _compare(document: Dictionary, baseline: Dictionary) -> Array[String]:
	var problems: Array[String] = []
	var doc_config: Dictionary = document.get("config", {})
	var base_config: Dictionary = baseline.get("config", {})
	if int(doc_config.get("physics_ticks_per_second", -1)) != int(base_config.get("physics_ticks_per_second", -1)):
		problems.append("config.physics_ticks_per_second: current=%s baseline=%s" % [doc_config.get("physics_ticks_per_second"), base_config.get("physics_ticks_per_second")])
	if int(doc_config.get("laps", -1)) != int(base_config.get("laps", -1)):
		problems.append("config.laps: current=%s baseline=%s" % [doc_config.get("laps"), base_config.get("laps")])
	if int(doc_config.get("field_size", -1)) != int(base_config.get("field_size", -1)):
		problems.append("config.field_size: current=%s baseline=%s" % [doc_config.get("field_size"), base_config.get("field_size")])
	var base_by_key := {}
	for entry: Dictionary in baseline.get("seeds", []):
		base_by_key[String(entry.get("key", ""))] = entry
	for entry: Dictionary in document.get("seeds", []):
		var key := String(entry.get("key", ""))
		var base: Dictionary = base_by_key.get(key, {})
		if base.is_empty():
			problems.append("seed %s not present in baseline" % key)
			continue
		if String(entry.get("hash", "")) != String(base.get("hash", "")):
			problems.append(
				"seed %s outcome changed\n  current  order=%s times=%s\n  baseline order=%s times=%s" % [
					key,
					str(entry.get("finish_order", [])),
					_times_str(entry.get("racers", [])),
					str(base.get("finish_order", [])),
					_times_str(base.get("racers", [])),
				]
			)
	return problems


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
