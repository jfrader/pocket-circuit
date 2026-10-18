extends SceneTree

const PROTOTYPE := preload("res://scenes/race/prototype_race.tscn")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")

var _failed := false

class TestRace extends "res://scripts/race/prototype_race.gd":
	var returned := false

	func _run_countdown() -> void:
		_countdown_active = false
		race_manager.prepare_race()
		race_manager.start_race()

	func request_return() -> void:
		if _wear_out_active:
			return
		returned = true
		get_node("/root/App").call("continue_after_race", false)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var race := PROTOTYPE.instantiate()
	race.set("_session", {"mode": "run", "event": {"opponents": ["juniper", "milo", "tess", "juniper", "milo"], "opponent_count": 5}})
	if not _expect((race.call("_build_field_racers_for_preparation") as Array).size() == 6, "ordinary run prepares six cars"):
		race.free()
		return
	race.free()
	var app := root.get_node("App")
	app.set("reduced_motion", true)
	var run: RunSession = app.call("start_run", 247400) as RunSession
	run.nitro_count = 1
	run.run_state.set_car_wear(run.current_car_id, "rusty")
	var live := _make_race(app, run)
	await process_frame
	var manager := live.get_node("RaceManager") as RaceManager
	if not _expect(manager.get_racer_count() == 6, "six cars register in the real race scene"):
		return
	var racers := manager.get_rankings()
	for i in racers.size():
		for j in range(i + 1, racers.size()):
			if not _expect(racers[i].position.distance_to(racers[j].position) > 52.0, "six grid footprints do not overlap"):
				return
	for frame in 4:
		await physics_frame
		await process_frame
	live.call("_set_paused", false)
	var player := live.get("_player_vehicle") as VehicleController
	var owned_key := IDENTITIES.resolve_visual_key(String(run.car_record(run.current_car_id)["id"]))
	if not _expect(owned_key != IDENTITIES.resolve_visual_key(run.current_car_id, "rae"), "seeded owned car and driver have different liveries"):
		return
	if not _expect(String((app.call("get_current_race_session") as Dictionary)["player_visual_key"]) == owned_key and String(player.get("_visual_key")) == owned_key, "run race uses the owned car record look, not the driver livery"):
		return
	player.boost_amount = 0.0
	if not _expect(bool(live.call("fire_nitro")) and run.nitro_count == 0 and player.boost_amount > 0.0, "nitro spends one bottle and supplies boost"):
		return
	var boost := player.boost_amount
	if not _expect(not bool(live.call("fire_nitro")) and player.boost_amount == boost, "zero bottles cannot boost again"):
		return
	run.add_nitro()
	var nitro_key := InputEventKey.new()
	nitro_key.keycode = KEY_N
	nitro_key.pressed = true
	nitro_key.echo = true
	live.call("_unhandled_input", nitro_key)
	if not _expect(run.nitro_count == 1, "holding the nitro key cannot spend repeated bottles"):
		return
	nitro_key.echo = false
	live.call("_unhandled_input", nitro_key)
	if not _expect(run.nitro_count == 0, "the mapped nitro action spends exactly one bottle on a new press"):
		return
	await physics_frame
	await physics_frame
	if not _expect(player.linear_velocity.dot(Vector2.UP.rotated(player.rotation)) > 1.0, "bottled nitro applies an immediate forward kick without holding boost"):
		return
	var hud := live.get("_race_hud") as RaceHUD
	if not _expect(hud.nitro_count == 0 and hud.racer_count == 6, "HUD reflects bottle inventory and six positions"):
		return
	var worn := live.get("_player_wear_texture") as Texture2D
	var clean := IDENTITIES.car_texture_with_wear_for_key(String(player.get("_visual_key")), "clean", IDENTITIES.NATIVE_PIXEL_SCALE, 64)
	if not _expect(worn.get_image().get_data() != clean.get_image().get_data(), "race texture has visible wear"):
		return
	var wear_pixels := {}
	for wear: String in ["clean", "dusty", "rusty", "dented"]:
		var texture := IDENTITIES.car_texture_with_wear_for_key(String(player.get("_visual_key")), wear, IDENTITIES.NATIVE_PIXEL_SCALE, 64)
		wear_pixels[hash(texture.get_image().get_data())] = true
	if not _expect(wear_pixels.size() == 4, "all four wear levels differ at the race raster scale"):
		return
	await physics_frame
	await process_frame
	var overlay := live.get("_player_wear_overlay") as Sprite2D
	if not _expect(overlay.visible and overlay.texture.get_image().get_data() != clean.get_image().get_data(), "wear survives wheel animation through its body overlay"):
		return
	for racer: Node2D in racers:
		for lap in manager.laps_to_finish:
			for checkpoint_index in manager.get_checkpoint_count():
				var expected := manager.get_expected_checkpoint(racer)
				var checkpoint: Node = null
				for candidate: Node in manager.checkpoints:
					if int(candidate.get("checkpoint_index")) == expected:
						checkpoint = candidate
				if not _expect(manager.report_checkpoint(checkpoint, racer), "each racer passes its required sensor"):
					return
	var results := manager.get_results()
	if not _expect(results.size() == 6 and int(results[5]["position"]) == 6 and bool(results[5]["finished"]), "all six racers finish in six result positions"):
		return
	live.free()
	await process_frame
	# The same presentation runs from the committed domain outcome, with and
	# without a tow. The test override keeps the scene alive at board handoff.
	for scenario: Dictionary in [{"tow": true, "reduced": true}, {"tow": false, "reduced": true}, {"tow": true, "reduced": false}, {"tow": false, "reduced": true, "stale_tow": true}]:
		var towed := bool(scenario["tow"])
		app.set("reduced_motion", bool(scenario["reduced"]))
		run = app.call("start_run", 247401 + int(towed)) as RunSession
		run.tow_count = 1 if towed else 0
		run.towed_to_bench = bool(scenario.get("stale_tow", false))
		run.run_state.set_car_wear(run.current_car_id, "rusty")
		live = _make_race(app, run)
		await process_frame
		manager = live.get_node("RaceManager") as RaceManager
		var beats: Array[String] = []
		live.wear_out_beat_changed.connect(func(beat: String) -> void: beats.append(beat))
		var failed_results := manager.get_results()
		for result: Dictionary in failed_results:
			result["dnf"] = true
			result["time"] = 10.0
		live.call("_on_results_ready", failed_results)
		if not _expect(String(live.get("wear_out_beat")) == "wreck" and not live.returned, "wear-out cuts control and holds before returning"):
			return
		if not _expect((live.get("_player_vehicle") as VehicleController).controls_locked, "wreck control is locked"):
			return
		live.call("request_return")
		if not _expect(not live.returned, "return cannot skip the wear-out sequence"):
			return
		for tick in 1000:
			if live.returned:
				break
			await create_timer(0.01).timeout
		var expected_beats: Array = ["wreck", "pickup", "passenger", "bench"] if towed else ["wreck", "run_over"]
		if not _expect(live.returned and beats == expected_beats and String(app.get("_destination")) == "run_board", "only a spent tow gets all four beats, then the board"):
			return
		if not _expect(run.tow_count == 0 and run.towed_to_bench == (towed or bool(scenario.get("stale_tow", false))) and run.is_failed() != towed, "presentation leaves the domain tow/failure outcome unchanged"):
			return
		live.free()
		await process_frame
	var duel := PROTOTYPE.instantiate()
	duel.set("_session", {"mode": "run", "event": {"race_format": "rival_duel", "opponent_count": 5, "opponents": ["juniper", "milo", "tess", "juniper", "milo"]}})
	if not _expect((duel.call("_build_field_racers_for_preparation") as Array).size() == 2, "duel remains one versus one even with an oversized roster"):
		return
	duel.free()
	run = app.call("start_run", 247409) as RunSession
	live = _make_race(app, run, false, false, true)
	if not _expect((live.get_node("RaceManager") as RaceManager).get_racer_count() == 2, "a real duel scene registers exactly two racers"):
		return
	live.free()
	await process_frame
	for reverse in [false, true]:
		run = app.call("start_run", 247410) as RunSession
		live = _make_race(app, run, true, reverse)
		await physics_frame
		await process_frame
		manager = live.get_node("RaceManager") as RaceManager
		if not _expect(manager.get_racer_count() == 6, "generated grid fields six cars in both directions"):
			return
		var grid := live.call("_grid_transforms", reverse) as Array
		for i in grid.size():
			for j in range(i + 1, grid.size()):
				if not _expect((grid[i] as Transform2D).origin.distance_to((grid[j] as Transform2D).origin) > 52.0, "six generated grid slots have disjoint footprints: reverse=%s slots=%d,%d distance=%.2f grid=%s" % [reverse, i, j, (grid[i] as Transform2D).origin.distance_to((grid[j] as Transform2D).origin), grid]):
					return
		for racer: Node2D in manager.get_rankings():
			var collision := racer.get_node("CollisionShape2D") as CollisionShape2D
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = collision.shape
			query.transform = collision.global_transform
			query.collision_mask = 2 | 4 | 16
			query.exclude = [(racer as RigidBody2D).get_rid()]
			if not _expect(racer.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(), "six generated grid cars are clear of solid scenery"):
				return
		live.free()
		await process_frame
	if _failed:
		return
	print("RUN_RACE_PLAN_TEST PASS")
	quit(0)


func _make_race(app: Node, run: RunSession, generated: bool = false, reverse: bool = false, duel: bool = false) -> TestRace:
	app.call("start_run_race", run.current_node_id)
	var session: Dictionary = app.call("get_current_race_session")
	var event: Dictionary = session["event"]
	event["circuit"] = "generated" if generated else "kitchen"
	event["theme"] = "kitchen"
	event["laps"] = 1
	event["reverse"] = reverse
	if duel:
		event["race_format"] = "rival_duel"
	app.set("current_race_session", session)
	var race := PROTOTYPE.instantiate()
	race.set_script(TestRace)
	root.add_child(race)
	return race as TestRace


func _expect(ok: bool, message: String) -> bool:
	if not ok:
		_failed = true
		push_error("RUN_RACE_PLAN_TEST FAIL: " + message)
		quit(1)
	return ok
