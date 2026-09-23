extends SceneTree

const PROTOTYPE_SCENE := preload("res://scenes/race/prototype_race.tscn")
const IDENTITIES := preload("res://scripts/race/generated_circuit_identity.gd")
const GENERATOR := preload("res://scripts/race/track_v8_development_generator.gd")
const RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const AI_CONTROLLER_SCRIPT := preload("res://scripts/vehicle/ai_vehicle_controller.gd")
const CATALOG := preload("res://data/championship/catalog.gd")

const DEFAULT_THEME := &"kitchen"
const DIFFICULTY := "clockwork"
const PLAYER_DRIVER := "cass"
const PLAYER_LANE_OFFSET := -10.0

# Runtime gates (architecture §7.3): zero DNF and at most 3 recoveries per car.
const MAX_RECOVERIES_PER_RACER := 3
const CONSERVATIVE_UNITS_PER_SECOND := 150.0
const LAP_CEILING_PADDING_SECONDS := 10.0

# Wall-clock acceleration: 240 physics ticks at 4x time scale keeps the physics
# step at 1/60 simulated seconds per frame (same delta as ai_seed_sweep_test.gd).
const PHYSICS_TICKS_PER_SECOND := 240
const TIME_SCALE := 4.0
const SETTLE_FRAMES := 36
const STARTUP_WAIT_FRAMES := 180

const DEFAULT_CASES: Array[Dictionary] = [
	{"room": &"classic", "tier": "standard", "seed": 928, "reverse": false},
	{"room": &"classic", "tier": "standard", "seed": 928, "reverse": true},
	{"room": &"el", "tier": "compact", "seed": 1001, "reverse": false},
	{"room": &"el", "tier": "compact", "seed": 1001, "reverse": true},
]

var _saved_physics_ticks := 0
var _saved_time_scale := 1.0


func _initialize() -> void:
	_saved_physics_ticks = Engine.physics_ticks_per_second
	_saved_time_scale = Engine.time_scale
	Engine.physics_ticks_per_second = PHYSICS_TICKS_PER_SECOND
	Engine.time_scale = TIME_SCALE
	call_deferred("_run_test")


func _run_test() -> void:
	var cases := _selected_cases()
	if cases.is_empty():
		_finish(1)
		return
	print("V8_DRESSED_RUNTIME_LAP_TEST selected %d case(s): %s" % [cases.size(), str(cases)])
	for test_case: Dictionary in cases:
		if not await _run_case(test_case):
			return
	_finish(0, "V8_DRESSED_RUNTIME_LAP_TEST PASS cases=%d" % cases.size())


# ── Selectors ─────────────────────────────────────────────────────────
# Opt-in overrides for farm shards; the 4 default cases remain the default.
#   PC_V8_CELL=room/tier      single cell (e.g. "classic/compact")
#   PC_V8_SEED=integer        route seed (default 0 in cell mode)
#   PC_V8_THEME=theme         kitchen|workshop|office
#   PC_V8_DIRECTION=forward|reverse|both
func _selected_cases() -> Array[Dictionary]:
	var cell := OS.get_environment("PC_V8_CELL")
	if not cell.is_empty():
		return _cell_cases(cell)
	var direction := OS.get_environment("PC_V8_DIRECTION")
	if not direction.is_empty() and direction not in ["forward", "reverse", "both"]:
		_expect(false, "PC_V8_DIRECTION must be forward|reverse|both (got '%s')" % direction)
		return []
	var seed_override := OS.get_environment("PC_V8_SEED")
	if not seed_override.is_empty():
		if not seed_override.is_valid_int():
			_expect(false, "PC_V8_SEED must be an integer (got '%s')" % seed_override)
			return []
		if not _is_seed(int(seed_override)):
			_expect(false, "PC_V8_SEED must be within [0, %d] (got '%s')" % [IDENTITIES.MAX_SEED, seed_override])
			return []
	var theme_override := _env_theme(&"")
	var cases: Array[Dictionary] = []
	for base: Dictionary in DEFAULT_CASES:
		var c := base.duplicate()
		if not seed_override.is_empty():
			c["seed"] = int(seed_override)
		if theme_override != &"":
			c["theme"] = theme_override
		var reverse: bool = bool(c.get("reverse", false))
		if direction == "forward" and reverse:
			continue
		if direction == "reverse" and not reverse:
			continue
		cases.append(c)
	return cases


func _cell_cases(cell: String) -> Array[Dictionary]:
	var parts := cell.split("/", true, 1)
	if parts.size() != 2 or parts[0].strip_edges().is_empty() or parts[1].strip_edges().is_empty():
		_expect(false, "PC_V8_CELL must be room/tier (got '%s')" % cell)
		return []
	var room := StringName(parts[0].strip_edges())
	var tier := parts[1].strip_edges()
	if not RULES.ROOMS.has(String(room)):
		_expect(false, "PC_V8_CELL room '%s' is not a known room (expected one of %s)" % [room, str(RULES.ROOMS)])
		return []
	if not RULES.LENGTH_TIERS.has(tier):
		_expect(false, "PC_V8_CELL tier '%s' is not a known tier (expected one of %s)" % [tier, str(RULES.LENGTH_TIERS)])
		return []
	var seed := _env_seed(0)
	var theme := _env_theme(DEFAULT_THEME)
	var directions := _env_directions(&"forward")
	var cases: Array[Dictionary] = []
	for reverse: bool in directions:
		cases.append({"room": room, "tier": tier, "seed": seed, "reverse": reverse, "theme": theme})
	return cases


func _env_seed(default_seed: int) -> int:
	var raw := OS.get_environment("PC_V8_SEED")
	if raw.is_empty():
		return default_seed
	if not raw.is_valid_int() or not _is_seed(int(raw)):
		_expect(false, "PC_V8_SEED must be an integer within [0, %d] (got '%s')" % [IDENTITIES.MAX_SEED, raw])
		return default_seed
	return int(raw)


func _env_theme(default_theme: StringName) -> StringName:
	var raw := OS.get_environment("PC_V8_THEME")
	if raw.is_empty():
		return default_theme
	var theme := StringName(raw)
	if not IDENTITIES.THEMES.has(String(theme)):
		_expect(false, "PC_V8_THEME '%s' is not a known theme (expected one of %s)" % [theme, str(IDENTITIES.THEMES)])
		return default_theme
	return theme


func _env_directions(default_direction: StringName) -> Array[bool]:
	var raw := OS.get_environment("PC_V8_DIRECTION")
	if raw.is_empty():
		return [default_direction == &"reverse"]
	match raw:
		"forward":
			return [false]
		"reverse":
			return [true]
		"both":
			return [false, true]
	_expect(false, "PC_V8_DIRECTION must be forward|reverse|both (got '%s')" % raw)
	return []


func _is_seed(value: int) -> bool:
	return value >= 0 and value <= IDENTITIES.MAX_SEED


# ── Tier-specific ceilings ────────────────────────────────────────────
func _frames_per_simulated_second() -> float:
	return float(Engine.physics_ticks_per_second) / Engine.time_scale


func _tier_lap_ceiling_seconds(tier: String) -> float:
	var profile := RULES.length_profile(tier)
	return float(profile["max_length"]) / CONSERVATIVE_UNITS_PER_SECOND + LAP_CEILING_PADDING_SECONDS


func _tier_frame_budget(tier: String) -> int:
	return ceili(_tier_lap_ceiling_seconds(tier) * _frames_per_simulated_second())


func _run_case(test_case: Dictionary) -> bool:
	var app := root.get_node_or_null("App")
	if app != null:
		app.current_race_session.clear()
	var room: StringName = test_case["room"]
	var tier: String = test_case["tier"]
	var seed: int = int(test_case["seed"])
	var rev: bool = bool(test_case.get("reverse", false))
	var theme: StringName = StringName(test_case.get("theme", "kitchen"))
	var dir_text := "reverse" if rev else "forward"
	var cell := "%s/%s" % [room, tier]

	# Derive the canonical PC2 identity FIRST; its room_geometry_seed is the
	# single source of truth that both the analytic route and the assembled
	# runtime track must share.
	var identity := IDENTITIES.create_v8(theme, room, seed, rev, 1, "", "", {}, tier, -1, 1, -1)
	if not _expect(not identity.is_empty(), "%s/%s/%s/%s should create a canonical PC2 identity" % [theme, cell, tier, dir_text]):
		return false
	var room_geometry_seed := int(identity["room_geometry_seed"])

	var generated := GENERATOR.generate_route(room, StringName(tier), seed, room_geometry_seed)
	if not _expect(bool(generated.get("ok", false)), "%s/%s/%s/%s runtime fixture should solve before scene assembly: %s" % [theme, cell, tier, dir_text, generated.get("reason", "unknown")]):
		return false
	if not _expect(int(generated.get("identity", {}).get("room_geometry_seed", -1)) == room_geometry_seed, "%s/%s/%s/%s analytic route should use the identity's room_geometry_seed (%d != %d)" % [theme, cell, tier, dir_text, int(generated.get("identity", {}).get("room_geometry_seed", -1)), room_geometry_seed]):
		return false

	var event := IDENTITIES.apply_to_event(identity, ["juniper", "milo", "tess"])
	event["laps"] = 1
	event["obstacles_enabled"] = true
	var prototype := PROTOTYPE_SCENE.instantiate()
	prototype.set("_session", {"mode": "quick", "event": event, "difficulty": DIFFICULTY, "vehicle_id": "rustbug"})
	var manager := prototype.get_node("RaceManager") as RaceManager
	root.add_child(prototype)
	current_scene = prototype
	await process_frame
	await physics_frame
	# Scene assembly calls App.record_prepared_mastery_metrics, which writes
	# mastery_circuit_metrics into the app's current_race_session even though the
	# harness never started a real App race. Re-clear it so the app's
	# report_race_result path short-circuits on an empty session when the player
	# (now AI-driven) finishes, instead of erroring on the missing "mode" key.
	if app != null:
		app.current_race_session.clear()

	var player := get_first_node_in_group("player_vehicle") as VehicleController
	if not _expect(player != null, "%s/%s/%s/%s should create the player vehicle" % [theme, cell, tier, dir_text]):
		return false
	# Attach an AI controller to the player (ai_seed_sweep_test.gd) so the full
	# four-car field races instead of freezing the player and driving 3 AI.
	var player_driver := CATALOG.get_driver(PLAYER_DRIVER)
	var player_controller := AI_CONTROLLER_SCRIPT.new() as AIVehicleController
	player.add_child(player_controller)
	player_controller.configure(player, manager, PLAYER_LANE_OFFSET, DIFFICULTY, PLAYER_DRIVER, player_driver.get("ai_style", {}) as Dictionary)

	var racers: Array[Node2D] = manager.get_rankings()
	if not _expect(racers.size() == 4, "%s/%s/%s/%s should create a 4-car field for the dressed lap (got %d)" % [theme, cell, tier, dir_text, racers.size()]):
		return false
	var controllers: Array[AIVehicleController] = []
	for racer: Node2D in racers:
		var controller := _get_ai_controller(racer)
		if not _expect(controller != null, "%s should have AI control" % racer.name):
			return false
		controllers.append(controller)

	var track := prototype.get_node_or_null("Track") as Node2D
	if not _expect(track != null and bool(track.get_meta("generated_track", false)) and int(track.get_meta("generator_version", 0)) == 8 and StringName(track.get_meta("room_shape", &"")) == room and bool(track.get_meta("obstacles_enabled", false)), "%s/%s/%s/%s should race assembled dressed v8 geometry with obstacles enabled" % [theme, cell, tier, dir_text]):
		return false
	# Assembled world present: floor, island, walls, posts, gates, props
	if not _expect(track.has_node("Floor") and track.has_node("RoomSurface"), "%s/%s should have floor/room surface" % [cell, tier]):
		return false
	if not _expect(track.has_node("InnerBarrier") or track.has_node("IslandProp") or track.has_node("IslandMaterial"), "%s/%s should have island" % [cell, tier]):
		return false
	if not _expect(track.has_node("Wall0"), "%s/%s should have room walls" % [cell, tier]):
		return false
	if not _expect(track.has_node("GatePosts") and (track.get_node("GatePosts").get_child_count() >= 2), "%s/%s should have gate posts" % [cell, tier]):
		return false
	if not _expect(track.has_node("Checkpoint0Finish"), "%s/%s should have gates/checkpoints" % [cell, tier]):
		return false
	if not _expect(track.has_node("PermanentObstacles"), "%s/%s dressed should have obstacle props container" % [cell, tier]):
		return false
	# pre-drive blocked passage scan (static solids vs centerline + reserved lanes)
	var centerline: PackedVector2Array = generated.get("points", PackedVector2Array())
	var room_model: Dictionary = generated.get("room_model", {})
	var pre_blocked := _count_blocked_passages(track, centerline, room_model)
	if not _expect(pre_blocked == 0, "%s/%s/%s/%s assembled world must have 0 blocked passages before run (got %d)" % [theme, cell, tier, dir_text, pre_blocked]):
		return false

	var lap_ceiling_seconds := _tier_lap_ceiling_seconds(tier)
	var frame_budget := _tier_frame_budget(tier)
	manager.finish_grace_seconds = lap_ceiling_seconds

	for _settle in SETTLE_FRAMES:
		await physics_frame
	paused = false
	var startup_waits := 0
	while not manager.is_running and startup_waits < STARTUP_WAIT_FRAMES:
		await physics_frame
		startup_waits += 1
	if not _expect(manager.is_running, "%s/%s/%s/%s should finish its countdown within %d frames" % [theme, cell, tier, dir_text, STARTUP_WAIT_FRAMES]):
		return false
	var started := Time.get_ticks_usec()
	var frame := 0
	while frame < frame_budget and not _all_finished(manager, racers):
		await physics_frame
		frame += 1
	var wall_ms := (Time.get_ticks_usec() - started) / 1000.0

	# Report every racer before asserting so a failure still shows the full field.
	for index in racers.size():
		var racer := racers[index]
		var controller := controllers[index]
		var state := manager.get_racer_state(racer)
		var finished := bool(state.get("finished", false))
		var dnf := (not finished) or bool(state.get("dnf", false))
		var finish_time := float(state.get("finish_time", state.get("elapsed", 0.0)))
		print("V8_DRESSED_RACER room=%s tier=%s seed=%d dir=%s racer=%s lap=%d checkpoint=%d finished=%s dnf=%s recoveries=%d finish_time=%.3f elapsed=%.3f" % [
			room, tier, seed, dir_text, racer.name, int(state.get("lap", 0)), int(state.get("expected_checkpoint", -1)),
			"yes" if finished else "no", "yes" if dnf else "no", controller.recovery_count, finish_time, float(state.get("elapsed", 0.0)),
		])
	print("V8_DRESSED_RUNTIME_LAP room=%s tier=%s seed=%d dir=%s theme=%s room_seed=%d length=%.2f lap_ceiling=%.2f frames=%d budget=%d race_time=%.3f blocked=%d wall_ms=%.2f" % [
		room, tier, seed, dir_text, theme, room_geometry_seed, float(track.get_meta("loop_length", 0.0)) if track else 0.0, lap_ceiling_seconds, frame, frame_budget, float(manager.race_time), pre_blocked, wall_ms,
	])

	for index in racers.size():
		var racer := racers[index]
		var controller := controllers[index]
		var state := manager.get_racer_state(racer)
		var finished := bool(state.get("finished", false))
		var dnf := (not finished) or bool(state.get("dnf", false))
		if not _expect(finished and int(state.get("lap", 0)) >= 1, "%s/%s/%s/%s racer %s should complete one ordered lap within the %s-tier ceiling (%.1fs, %d frames); lap=%d checkpoint=%d" % [theme, cell, tier, dir_text, racer.name, tier, lap_ceiling_seconds, frame_budget, int(state.get("lap", 0)), int(state.get("expected_checkpoint", -1))]):
			return false
		if not _expect(not dnf, "%s/%s/%s/%s racer %s should finish with zero DNF (finished=%s dnf=%s)" % [theme, cell, tier, dir_text, racer.name, finished, bool(state.get("dnf", false))]):
			return false
		if not _expect(controller.recovery_count <= MAX_RECOVERIES_PER_RACER, "%s/%s/%s/%s racer %s should need at most %d recoveries (got %d: %s)" % [theme, cell, tier, dir_text, racer.name, MAX_RECOVERIES_PER_RACER, controller.recovery_count, str(controller.recovery_reasons)]):
			return false

	# final post-run scan (should still be 0)
	var post_blocked := _count_blocked_passages(track, centerline, room_model)
	if not _expect(post_blocked == 0, "%s/%s/%s/%s post-run should still have 0 blocked (got %d)" % [theme, cell, tier, dir_text, post_blocked]):
		return false
	current_scene = null
	root.remove_child(prototype)
	prototype.free()
	if app != null:
		app.current_race_session.clear()
	await process_frame
	await physics_frame
	return true


func _get_ai_controller(racer: Node) -> AIVehicleController:
	for child: Node in racer.get_children():
		if child is AIVehicleController:
			return child as AIVehicleController
	return null


func _all_finished(manager: RaceManager, racers: Array[Node2D]) -> bool:
	for racer: Node2D in racers:
		if not manager.is_racer_finished(racer):
			return false
	return not racers.is_empty()


func _count_blocked_passages(track: Node2D, centerline: PackedVector2Array, room_model: Dictionary) -> int:
	if not is_instance_valid(track) or centerline.is_empty():
		return 0
	var probes := centerline.duplicate()
	for psg: Dictionary in room_model.get("reserved_passages", []) as Array:
		probes.append_array(psg.get("lane_centers", PackedVector2Array()) as PackedVector2Array)
	var shape := CircleShape2D.new()
	shape.radius = 125.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	var excluded: Array[RID] = []
	for racer: Node in get_nodes_in_group("race_vehicle"):
		if racer is CollisionObject2D:
			excluded.append((racer as CollisionObject2D).get_rid())
	query.exclude = excluded
	var space := track.get_world_2d().direct_space_state
	var blocked := 0
	for probe: Vector2 in probes:
		query.transform = Transform2D(0.0, probe)
		var hits := space.intersect_shape(query, 1)
		if not hits.is_empty():
			blocked += 1
	return blocked


func _finish(exit_code: int, message: String = "") -> void:
	Engine.time_scale = _saved_time_scale
	Engine.physics_ticks_per_second = _saved_physics_ticks
	if not message.is_empty():
		print(message)
	quit(exit_code)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	Engine.time_scale = _saved_time_scale
	Engine.physics_ticks_per_second = _saved_physics_ticks
	push_error("V8_DRESSED_RUNTIME_LAP_TEST FAIL: " + message)
	quit(1)
	return false
