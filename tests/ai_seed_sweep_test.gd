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
	# Opt-in large-tier QA: when PC_LENGTH_TIER is set, run a single wide-room case
	# at that tier instead of the 50-seed standard sweep. Legacy mean/max gates are
	# only asserted on the full standard sweep, never on this single large case.
	var length_tier := OS.get_environment("PC_LENGTH_TIER")
	if not length_tier.is_empty():
		return [{
			&"theme": &"kitchen",
			&"room": &"wide",
			&"seed": int(OS.get_environment("PC_SEED")) if OS.get_environment("PC_SEED").is_valid_int() else 0,
			&"repro": false,
			&"length_tier": StringName(length_tier),
		}]
	var requested_seed := OS.get_environment("PC_SEED")
	if requested_seed.is_valid_int():
		return [{
			&"theme": StringName(OS.get_environment("PC_THEME")) if not OS.get_environment("PC_THEME").is_empty() else &"kitchen",
			&"room": StringName(OS.get_environment("PC_ROOM")) if not OS.get_environment("PC_ROOM").is_empty() else &"classic",
			&"seed": int(requested_seed),
			&"repro": false,
			&"length_tier": StringName("standard"),
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
			"length_tier": case.get("length_tier", StringName("standard")),
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
	if not _expect(manager.is_running, "%s/%s/%d should finish its countdown" % [case[&"theme"], case[&"room"], case[&"seed"]]):
		return {}
	var frame := 0
	var diagnostics := not OS.get_environment("PC_AI_DIAGNOSTICS").is_empty()
	var trace_racer := OS.get_environment("PC_AI_TRACE_RACER")
	var prior_recoveries: Array[int] = []
	var captured: Array[bool] = []
	var trace_left: Array[int] = []
	var prior_lap: Array[int] = []
	var prior_expected: Array[int] = []
	var ledger: Dictionary = {}
	if diagnostics:
		_print_ai_geometry(manager, track)
		for index in controllers.size():
			prior_recoveries.append(controllers[index].recovery_count)
			captured.append(false)
			trace_left.append(0)
			prior_lap.append(-1)
			prior_expected.append(-1)
			ledger[racers[index].name] = []
	while frame < MAX_PHYSICS_FRAMES and not _all_finished(manager, racers):
		await physics_frame
		frame += 1
		if diagnostics:
			for index in controllers.size():
				var controller := controllers[index]
				var stagnant := float(controller.get("_no_progress_time")) >= 1.0
				var recovered := controller.recovery_count > prior_recoveries[index]
				if (stagnant or recovered) and not captured[index]:
					captured[index] = true
					_print_ai_diagnostic(manager, racers[index], controller, stagnant, recovered)
					trace_left[index] = 40
				if trace_left[index] > 0:
					_print_ai_arc_trace(manager, racers[index], controller, frame)
					trace_left[index] -= 1
				prior_recoveries[index] = controller.recovery_count
				var state := manager.get_racer_state(racers[index])
				var lap_now := int(state.get("lap", 0))
				var expected_now := int(state.get("expected_checkpoint", -1))
				if lap_now != prior_lap[index] or expected_now != prior_expected[index]:
					var entries: Array = ledger[racers[index].name]
					entries.append("L%d:E%d@%.2f" % [lap_now, expected_now, float(manager.race_time)])
					ledger[racers[index].name] = entries
				prior_lap[index] = lap_now
				prior_expected[index] = expected_now
				if not trace_racer.is_empty() and racers[index].name == trace_racer and frame % 4 == 0:
					_print_ai_trace(manager, racers[index], controller)
	for racer_name: String in ledger:
		print("PC_AI_LEDGER %s %s" % [racer_name, str(ledger[racer_name])])
	var dnf_slots := 0
	var finish_times: Array[float] = []
	var racer_results: Array[String] = []
	var max_recoveries := 0
	for index in racers.size():
		var state := manager.get_racer_state(racers[index])
		var dnf := not bool(state.get("finished", false)) or bool(state.get("dnf", false))
		if dnf:
			dnf_slots += 1
			if diagnostics:
				_print_ai_finalization(manager, racers[index], controllers[index])
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


func _print_ai_finalization(manager: RaceManager, racer: Node2D, controller: AIVehicleController) -> void:
	var vehicle := racer as VehicleController
	var state := manager.get_racer_state(racer)
	var expected := int(state.get("expected_checkpoint", -1))
	var sample := controller.call("_active_route_sample", expected) as Dictionary
	var checkpoints: Dictionary = controller.get("_checkpoints_by_index")
	var cp := checkpoints.get(expected) as Node2D
	var cp_pos := cp.global_position if cp != null else Vector2.ZERO
	var finish := checkpoints.get(0) as Node2D
	var finish_pos := finish.global_position if finish != null else Vector2.ZERO
	print("PC_AI_DNF racer=%s lap=%d expected=%d pos=(%.1f,%.1f) speed=%.1f vel=(%.1f,%.1f) dist_cp=%.1f dist_finish=%.1f arc=%.1f no_prog=%.2f recovers=%d reasons=%s" % [
		racer.name, int(state.get("lap", 0)), expected,
		vehicle.global_position.x, vehicle.global_position.y, vehicle.speed,
		vehicle.linear_velocity.x, vehicle.linear_velocity.y,
		vehicle.global_position.distance_to(cp_pos),
		vehicle.global_position.distance_to(finish_pos),
		float(sample.get("arc", 0.0)),
		float(controller.get("_no_progress_time")),
		controller.recovery_count, str(controller.recovery_reasons),
	])


func _print_ai_geometry(manager: RaceManager, track: Node2D) -> void:
	var seals := track.get_node_or_null("PocketSeals") as Node2D
	var seal_count := seals.get_child_count() if seals != null else -1
	var room_polygon: PackedVector2Array = track.get_meta("room_polygon", PackedVector2Array())
	print("PC_AI_GEO family=%s story=%s checkpoints=%d seals=%d room_pts=%d room_area=%.0f generated=%s route_ref=%s" % [
		track.get_meta("family", &"unknown"),
		track.get_meta("story_id", &"unknown"),
		manager.get_checkpoint_count(),
		seal_count,
		room_polygon.size(),
		absf(_polygon_area_2d(room_polygon)),
		track.get_meta("generated_track", false),
		manager.has_route_reference(),
	])
	var cp_parts: Array[String] = []
	for checkpoint: Node in manager.get_ordered_checkpoints():
		cp_parts.append("%d=(%.0f,%.0f)fin=%s" % [int(checkpoint.get("checkpoint_index")), (checkpoint as Node2D).global_position.x, (checkpoint as Node2D).global_position.y, str(bool(checkpoint.get("is_finish_line")))])
	print("PC_AI_CHECKPOINTS %s" % str(cp_parts))


func _polygon_area_2d(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in points.size():
		var next := (index + 1) % points.size()
		total += points[index].x * points[next].y - points[next].x * points[index].y
	return total * 0.5


func _print_ai_diagnostic(manager: RaceManager, racer: Node2D, controller: AIVehicleController, stagnant: bool, recovered: bool) -> void:
	var vehicle := racer as VehicleController
	var expected_index := manager.get_expected_checkpoint(racer)
	var next_index := manager.get_checkpoint_after_index(expected_index)
	var sample := controller.call("_active_route_sample", expected_index) as Dictionary
	var checkpoints: Dictionary = controller.get("_checkpoints_by_index")
	var checkpoint := checkpoints.get(expected_index) as Node2D
	var next_checkpoint := checkpoints.get(next_index) as Node2D
	var cp_pos := checkpoint.global_position if checkpoint != null else Vector2.ZERO
	var next_cp_pos := next_checkpoint.global_position if next_checkpoint != null else Vector2.ZERO
	var guide_position: Variant = controller.call("_checkpoint_entry_guide_position", expected_index)
	var target_position := controller.call("_active_target_position", expected_index) as Vector2
	var racing_line := controller.get("_racing_line") as PackedVector2Array
	var reference_path := controller.get("_reference_path") as PackedVector2Array
	var forward := Vector2.UP.rotated(vehicle.rotation)
	var nearest_index := 0
	if not racing_line.is_empty():
		nearest_index = int(controller.call("_nearest_line_index", vehicle.global_position))
	var nearest_line_point := racing_line[nearest_index] if not racing_line.is_empty() else Vector2.ZERO
	var lookahead := (70.0 + vehicle.speed * 0.4) / maxf(float((controller.get("personality") as Dictionary).get("line_commitment", 1.0)), 0.001)
	var goal := controller.call("_reference_goal", forward, lookahead) as Dictionary
	var solids := _nearby_solid_bodies(vehicle, 64.0)
	var line_window := _line_window(racing_line, nearest_index, 24)
	var cp_line_index := int(controller.call("_nearest_line_index", cp_pos)) if not racing_line.is_empty() else -1
	print("PC_AI_DIAG racer=%s stagnant=%s recovered=%s frame_sec=%.2f pos=(%.1f,%.1f) rot=%.3f speed=%.1f vel=(%.1f,%.1f) slip=%.1f expected=%d next=%d cp=(%.1f,%.1f) next_cp=(%.1f,%.1f) dist_cp=%.1f dist_target=%.1f guide=%s target=(%.1f,%.1f) cp_line_idx=%d nearest_line=%d@(%.1f,%.1f) goal=(%.1f,%.1f) sample={arc=%.1f,len=%.1f,dist=%.1f,closed=%s} ref=%d line=%d shortcut=%s no_progress=%.2f off_route=%.2f wrong_way=%.2f stuck=%.2f static=%s normal=(%.2f,%.2f) layer=%d mask=%d solids=%s line_window=%s" % [
		racer.name, stagnant, recovered, float(manager.race_time),
		vehicle.global_position.x, vehicle.global_position.y, vehicle.rotation,
		vehicle.speed, vehicle.linear_velocity.x, vehicle.linear_velocity.y, vehicle.slip_angle,
		expected_index, next_index,
		cp_pos.x, cp_pos.y, next_cp_pos.x, next_cp_pos.y,
		vehicle.global_position.distance_to(cp_pos),
		vehicle.global_position.distance_to(target_position),
		str(guide_position) if guide_position != null else "null",
		target_position.x, target_position.y,
		cp_line_index,
		nearest_index, nearest_line_point.x, nearest_line_point.y,
		(goal["goal"] as Vector2).x, (goal["goal"] as Vector2).y,
		float(sample.get("arc", 0.0)), float(sample.get("length", 0.0)), float(sample.get("distance", 0.0)), bool(sample.get("closed", false)),
		reference_path.size(), racing_line.size(),
		controller.uses_shortcut_line,
		float(controller.get("_no_progress_time")), float(controller.get("_off_route_time")), float(controller.get("_wrong_way_progress_time")), float(controller.get("_stuck_time")),
		vehicle.has_static_contact,
		vehicle.static_contact_normal.x, vehicle.static_contact_normal.y,
		vehicle.collision_layer, vehicle.collision_mask,
		str(solids),
		str(line_window),
	])


func _line_window(line: PackedVector2Array, center_index: int, half_span: int) -> Array:
	var window: Array = []
	if line.is_empty():
		return window
	var count := line.size()
	for offset in range(-half_span, half_span + 1):
		var index := posmod(center_index + offset, count)
		window.append("%d=(%.0f,%.0f)" % [index, line[index].x, line[index].y])
	return window


func _print_ai_arc_trace(manager: RaceManager, racer: Node2D, controller: AIVehicleController, frame: int) -> void:
	var vehicle := racer as VehicleController
	var expected_index := manager.get_expected_checkpoint(racer)
	var sample := controller.call("_active_route_sample", expected_index) as Dictionary
	var checkpoints: Dictionary = controller.get("_checkpoints_by_index")
	var checkpoint := checkpoints.get(expected_index) as Node2D
	var cp_pos := checkpoint.global_position if checkpoint != null else Vector2.ZERO
	print("PC_AI_ARC frame=%d racer=%s arc=%.1f dist_cp=%.1f pos=(%.1f,%.1f) speed=%.1f no_prog=%.2f accum=%.1f tkey=%s room_cut=%d last_arc=%.1f angvel=%.2f wrongway=%s wwt=%.2f" % [
		frame, racer.name,
		float(sample.get("arc", 0.0)),
		vehicle.global_position.distance_to(cp_pos),
		vehicle.global_position.x, vehicle.global_position.y,
		vehicle.speed,
		float(controller.get("_no_progress_time")),
		float(controller.get("_route_progress_accumulator")),
		str(controller.get("_watchdog_target_key")),
		int(controller.get("_room_cut_checkpoint")),
		float(controller.get("_last_route_arc")),
		vehicle.angular_velocity,
		manager.is_racer_wrong_way(racer),
		float(controller.get("_wrong_way_progress_time")),
	])


func _print_ai_trace(manager: RaceManager, racer: Node2D, controller: AIVehicleController) -> void:
	var vehicle := racer as VehicleController
	var expected_index := manager.get_expected_checkpoint(racer)
	var line_radius := controller.call("_racing_line_radius", vehicle.global_position) as float
	print("PC_AI_TRACE t=%.2f %s exp=%d speed=%.1f slip=%.1f vel=(%.1f,%.1f) pos=(%.1f,%.1f) radius=%.1f" % [
		float(manager.race_time), racer.name, expected_index,
		vehicle.speed, vehicle.slip_angle,
		vehicle.linear_velocity.x, vehicle.linear_velocity.y,
		vehicle.global_position.x, vehicle.global_position.y,
		line_radius,
	])


func _nearby_solid_bodies(vehicle: Node2D, radius: float) -> Array:
	var found: Array = []
	if not vehicle.is_inside_tree():
		return found
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, vehicle.global_position)
	query.collision_mask = 2 | 4 | 16
	query.exclude = [vehicle.get_rid()]
	var hits := vehicle.get_world_2d().direct_space_state.intersect_shape(query, 40)
	for hit: Dictionary in hits:
		var collider: Variant = hit.get("collider")
		if not collider is Node:
			continue
		var node := collider as Node
		var desc: Dictionary = {"name": node.name, "class": node.get_class()}
		if node is CollisionObject2D:
			desc["layer"] = (node as CollisionObject2D).collision_layer
		for key: String in ["solid_class", "role", "asset_path", "pocket_index", "collision_contract", "flat_class"]:
			if node.has_meta(key):
				desc[key] = str(node.get_meta(key))
		found.append(desc)
	return found


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
