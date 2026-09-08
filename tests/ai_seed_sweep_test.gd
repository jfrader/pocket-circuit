extends SceneTree

const PROTOTYPE_SCENE := preload("res://scenes/race/prototype_race.tscn")
const AI_CONTROLLER_SCRIPT := preload("res://scripts/vehicle/ai_vehicle_controller.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
const THEMES: Array[StringName] = [&"kitchen", &"workshop", &"office"]
const ROOMS: Array[StringName] = [&"classic", &"wide", &"tall", &"long", &"square", &"el"]
const SWEEP_SIZE := 50
const FIELD_SIZE := 4
const LAPS := 3
const MAX_PHYSICS_FRAMES := 7200
const MAX_DNF_RATE := 0.02
const MAX_MEAN_P1_LAP_SECONDS := 18.0
const MAX_REPRO_RECOVERIES := 3
const REPRO_CASES := [
	{&"theme": &"kitchen", &"room": &"long", &"seed": 24469},
	{&"theme": &"workshop", &"room": &"square", &"seed": 51940},
]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	var cases := _seed_cases()
	var requested_limit := int(OS.get_environment("PC_SEED_LIMIT"))
	if requested_limit > 0:
		cases = cases.slice(0, mini(requested_limit, cases.size()))
	var opponent_count := FIELD_SIZE - 1
	var requested_opponents := OS.get_environment("PC_OPPONENT_COUNT")
	if requested_opponents.is_valid_int():
		opponent_count = clampi(int(requested_opponents), 0, FIELD_SIZE - 1)
	var dnf_slots := 0
	var p1_lap_sum := 0.0
	var p1_samples := 0
	for case: Dictionary in cases:
		var result := await _run_race(case, "club_circuit", LAPS, opponent_count)
		if result.is_empty():
			return
		dnf_slots += int(result[&"dnf_slots"])
		if is_finite(float(result[&"p1_lap_seconds"])):
			p1_lap_sum += float(result[&"p1_lap_seconds"])
			p1_samples += 1
		if bool(case.get(&"repro", false)):
			if not _expect(int(result[&"dnf_slots"]) == 0, "repro seed %d should finish without DNF" % int(case[&"seed"])):
				return
			if not _expect(int(result[&"max_recoveries"]) <= MAX_REPRO_RECOVERIES, "repro seed %d should use at most %d recoveries" % [int(case[&"seed"]), MAX_REPRO_RECOVERIES]):
				return
	var slots := cases.size() * (opponent_count + 1)
	var dnf_rate := float(dnf_slots) / maxf(float(slots), 1.0)
	var mean_p1_lap := p1_lap_sum / maxf(float(p1_samples), 1.0)
	if not _expect(dnf_rate <= MAX_DNF_RATE, "%d-seed club field DNF rate should be at most %.1f%% (dnf=%d/%d)" % [cases.size(), MAX_DNF_RATE * 100.0, dnf_slots, slots]):
		return
	if not _expect(p1_samples == cases.size(), "every club field should produce a legal P1 finish (samples=%d/%d)" % [p1_samples, cases.size()]):
		return
	if cases.size() == SWEEP_SIZE and not _expect(mean_p1_lap <= MAX_MEAN_P1_LAP_SECONDS, "club field mean P1 lap should be at most %.1fs (mean=%.3f)" % [MAX_MEAN_P1_LAP_SECONDS, mean_p1_lap]):
		return
	if not await _check_difficulty_separation():
		return
	print("AI_SEED_SWEEP_TEST PASS seeds=%d dnf_slots=%d dnf_rate=%.3f mean_p1_lap=%.3f" % [cases.size(), dnf_slots, dnf_rate, mean_p1_lap])
	quit(0)


func _seed_cases() -> Array[Dictionary]:
	var requested_seed := OS.get_environment("PC_SEED")
	if requested_seed.is_valid_int():
		return [{
			&"theme": StringName(OS.get_environment("PC_THEME")) if not OS.get_environment("PC_THEME").is_empty() else &"kitchen",
			&"room": StringName(OS.get_environment("PC_ROOM")) if not OS.get_environment("PC_ROOM").is_empty() else &"classic",
			&"seed": int(requested_seed),
			&"repro": false,
		}]
	var cases: Array[Dictionary] = []
	for repro: Dictionary in REPRO_CASES:
		var tagged := repro.duplicate()
		tagged[&"repro"] = true
		cases.append(tagged)
	var rng := RandomNumberGenerator.new()
	rng.seed = 556
	while cases.size() < SWEEP_SIZE:
		var index := cases.size() - REPRO_CASES.size()
		cases.append({
			&"theme": THEMES[index % THEMES.size()],
			&"room": ROOMS[rng.randi_range(0, ROOMS.size() - 1)],
			&"seed": rng.randi_range(0, 99999),
			&"repro": false,
		})
	return cases


func _check_difficulty_separation() -> bool:
	var case := {&"theme": &"kitchen", &"room": &"classic", &"seed": 0}
	var times: Dictionary = {}
	for difficulty: String in ["sunday_drive", "club_circuit", "clockwork"]:
		var result := await _run_race(case, difficulty, 1, 0)
		if result.is_empty():
			return false
		times[difficulty] = float(result[&"p1_lap_seconds"])
	var sunday := float(times["sunday_drive"])
	var club := float(times["club_circuit"])
	var clockwork := float(times["clockwork"])
	print("AI_DIFFICULTY_SEPARATION sunday=%.3f club=%.3f clockwork=%.3f" % [sunday, club, clockwork])
	return _expect(sunday > club and club > clockwork, "fixed-seed pace should order sunday_drive < club_circuit < clockwork")


func _run_race(case: Dictionary, difficulty: String, laps: int, opponent_count: int) -> Dictionary:
	var prototype := PROTOTYPE_SCENE.instantiate()
	prototype.set("_session", {
		"event": {
			"theme": case[&"theme"],
			"circuit": "generated",
			"room": case[&"room"],
			"seed": case[&"seed"],
			"reverse": false,
			"laps": laps,
			"opponents": ["juniper", "milo", "tess"],
			"opponent_count": opponent_count,
		},
		"difficulty": difficulty,
		"vehicle_id": "rustbug",
	})
	var manager := prototype.get_node("RaceManager") as RaceManager
	manager.finish_grace_seconds = 8.0
	root.add_child(prototype)
	current_scene = prototype
	var track := prototype.get("track_root") as Node2D
	var player := get_first_node_in_group("player_vehicle") as VehicleController
	if not _expect(player != null, "%s/%s/%d should create the player vehicle" % [case[&"theme"], case[&"room"], case[&"seed"]]):
		return {}
	var cass := CATALOG.get_driver("cass")
	var player_controller := AI_CONTROLLER_SCRIPT.new() as AIVehicleController
	player.add_child(player_controller)
	player_controller.configure(player, manager, -10.0, difficulty, "cass", cass.get("ai_style", {}) as Dictionary)
	var racers: Array[Node2D] = manager.get_rankings()
	if not _expect(racers.size() == opponent_count + 1, "%s/%s/%d should create the requested %d-car field" % [case[&"theme"], case[&"room"], case[&"seed"], opponent_count + 1]):
		return {}
	var controllers: Array[AIVehicleController] = []
	for racer: Node2D in racers:
		var controller := _get_ai_controller(racer)
		if not _expect(controller != null, "%s should have AI control" % racer.name):
			return {}
		controllers.append(controller)
	for settle in 6:
		await create_timer(0.1).timeout
	paused = false
	var startup_waits := 0
	while not manager.is_running and startup_waits < 30:
		await create_timer(0.1).timeout
		startup_waits += 1
	if not _expect(manager.is_running, "%s/%s/%d should finish its countdown" % [case[&"theme"], case[&"room"], case[&"seed"]]):
		return {}
	var frame := 0
	while frame < MAX_PHYSICS_FRAMES and not _all_finished(manager, racers):
		await physics_frame
		frame += 1
	var dnf_slots := 0
	var finish_times: Array[float] = []
	var racer_results: Array[String] = []
	var max_recoveries := 0
	for index in racers.size():
		var state := manager.get_racer_state(racers[index])
		var dnf := not bool(state.get("finished", false)) or bool(state.get("dnf", false))
		if dnf:
			dnf_slots += 1
		else:
			finish_times.append(float(state.get("finish_time", INF)))
		max_recoveries = maxi(max_recoveries, controllers[index].recovery_count)
		racer_results.append("%s:%.3f:%s:r%d%s:s%s:l%d:e%d" % [racers[index].name, float(state.get("finish_time", INF)), str(dnf), controllers[index].recovery_count, str(controllers[index].recovery_reasons), str(controllers[index].uses_shortcut_line), int(state.get("lap", 0)), int(state.get("expected_checkpoint", -1))])
	var p1_lap_seconds: float = INF if finish_times.is_empty() else finish_times.min() / float(laps)
	print("AI_SEED_CASE theme=%s room=%s seed=%d family=%s story=%s difficulty=%s racers=%d dnf=%d p1_lap=%.3f max_recoveries=%d frames=%d results=%s" % [case[&"theme"], case[&"room"], case[&"seed"], track.get_meta("family", &"unknown"), track.get_meta("story_id", &"unknown"), difficulty, racers.size(), dnf_slots, p1_lap_seconds, max_recoveries, frame, str(racer_results)])
	current_scene = null
	root.remove_child(prototype)
	prototype.free()
	await process_frame
	await physics_frame
	return {&"dnf_slots": dnf_slots, &"p1_lap_seconds": p1_lap_seconds, &"max_recoveries": max_recoveries}


func _all_finished(manager: RaceManager, racers: Array[Node2D]) -> bool:
	for racer: Node2D in racers:
		if not manager.is_racer_finished(racer):
			return false
	return not racers.is_empty()


func _get_ai_controller(racer: Node) -> AIVehicleController:
	for child: Node in racer.get_children():
		if child is AIVehicleController:
			return child as AIVehicleController
	return null


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	Engine.time_scale = 1.0
	push_error("AI_SEED_SWEEP_TEST FAIL: " + message)
	quit(1)
	return false
