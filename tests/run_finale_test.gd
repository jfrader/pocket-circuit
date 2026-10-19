extends SceneTree

const CORE := preload("res://scripts/race/track_builder_core.gd")
const PROTOTYPE := preload("res://scenes/race/prototype_race.tscn")
const AI := preload("res://scripts/vehicle/ai_vehicle_controller.gd")
const RUN_UI := preload("res://scripts/ui/run_ui.gd")
const PRESENTER := preload("res://scripts/presentation/track_variant_presenter.gd")
const FINALE := preload("res://scripts/race/run_finale_circuit.gd")

class TestRace extends "res://scripts/race/prototype_race.gd":
	func _run_countdown() -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var app := root.get_node("App")
	var reference := PackedVector2Array()
	for seed_value in [2474, 31800, 991073]:
		var run := app.call("start_run", seed_value) as RunSession
		for act in range(1, RunSession.FINAL_ACT + 1):
			run.current_map = RunMap.generate(seed_value, act)
			for node: Dictionary in run.current_map.nodes.values():
				if node["type"] not in ["race", "rival", "act_rival"]:
					continue
				var circuit: Dictionary = app.call("run_stop_circuit", String(node["id"]))
				var finale: bool = act == RunSession.FINAL_ACT and node["type"] == "act_rival"
				if not _expect((circuit.get("theme") == "basement") == finale, "basement belongs only to the final act rival"): return
				if not _expect(circuit.has("authored_route") == finale, "only the finale is authored"): return
				if not finale:
					if not _expect(circuit.get("theme") in ["kitchen", "workshop", "office"], "normal circuits retain generated themes"): return
					if not _expect(circuit.has("sub_seeds") and circuit.get("length_tier") == "standard", "normal stops keep generated standard routes"): return
					continue
				run.current_node_id = String(node["id"])
				if not _expect(app.call("start_run_race", run.current_node_id), "finale session starts"): return
				var session: Dictionary = app.call("get_current_race_session")
				var event: Dictionary = session["event"]
				var tuning: Dictionary = AI.DIFFICULTY_TUNING[session["difficulty"]]
				for profile: Dictionary in AI.DIFFICULTY_TUNING.values():
					if not _expect(tuning["pace"] >= profile["pace"] and tuning["baseline_power"] >= profile["baseline_power"] and tuning["reaction_seconds"] <= profile["reaction_seconds"], "finale uses actual fastest/strongest/most responsive AI"): return
				if not _expect(event["opponent_count"] == 5 and event["length_tier"] == "long", "six-car long finale"): return
				var race := PROTOTYPE.instantiate()
				race.set("_session", session)
				if not _expect((race.call("_build_field_racers_for_preparation") as Array).size() == 6, "race prepares all six racers"): return
				var prepared := CORE.prepare_layout(&"basement", &"wide", seed_value, race.call("_track_generation_options", event))
				race.free()
				if not _expect(not prepared.is_empty(), "authored builder layout exists"): return
				var centerline: PackedVector2Array = prepared["centerline"]
				if reference.is_empty(): reference = centerline
				if not _expect(centerline == reference, "every run seed uses the identical authored route"): return
				var validation := TrackSeedGen._validate_controls(prepared["spec"]["controls"], FINALE.ROOM, prepared["room_polygon"], 190.0, 320.0, 12000.0)
				if not _expect(validation["valid"], "authored route meets existing safety validator: " + str(validation.get("reason", ""))): return
				var length := CORE._arc_lengths(centerline)[-1]
				if not _expect(length >= 12000.0 and length <= 16000.0, "route meets long length band: %f" % length): return
				var track := CORE.create_layout_root(prepared)
				root.add_child(track)
				await CORE.assemble_runtime(track, prepared, Callable())
				var presenter := PRESENTER.new()
				track.add_child(presenter)
				presenter.configure(track, &"basement")
				var hazard := presenter.get_node_or_null("BoilerLeakSurface") as SurfaceZone
				if not _expect(hazard != null and hazard.grip_multiplier < 1.0 and hazard.speed_multiplier < 1.0, "exclusive puddle hazard has real physics"): return
				if not _expect(presenter.surface_zones.size() == 1, "no random or fallback kitchen hazards in finale"): return
				if not _expect(track.has_node("BoilerLeak/SurfaceVisual") and track.has_node("BoilerLeak/SurfaceLabel"), "hazard is visible and telegraphed"): return
				var facts := RUN_UI.stop_facts("act_rival", run, circuit)
				if not _expect("THE BASEMENT" in str(facts) and "long" in str(facts), "stop facts describe authored finale honestly"): return
				track.free()
	for theme: StringName in [&"kitchen", &"workshop", &"office"]:
		var ordinary := CORE.prepare_route(theme, &"wide", 2474)
		if not _expect(not ordinary.is_empty() and not ordinary["spec"].has("signature_hazards"), "generated routes cannot carry finale hazard"): return
	if not _expect(CORE.prepare_route(&"basement", &"wide", 2474).is_empty(), "basement is not a procedural room"): return
	var live := PROTOTYPE.instantiate()
	live.set_script(TestRace)
	root.add_child(live)
	for frame in 3:
		await physics_frame
		await process_frame
	var manager := live.get_node("RaceManager") as RaceManager
	if not _expect(manager.get_racer_count() == 6, "real finale scene registers six cars"): return
	var live_track := live.get_node("Track")
	if not _expect(live_track.get_meta("authored_route", "") == FINALE.ROUTE_ID and live_track.has_node("BoilerLeak"), "real race loads authored route and hazard, not a static fallback"): return
	var ai_count := 0
	for node: Node in live.find_children("*", "Node", true, false):
		if node is AIVehicleController:
			ai_count += 1
			if not _expect(node.difficulty == App.RUN_ACT_RIVAL_DIFFICULTY, "real finale AI receives hardest tuning"): return
	if not _expect(ai_count == 5, "all five opponents get AI controllers"): return
	for racer: Node2D in manager.get_rankings():
		var collision := racer.get_node("CollisionShape2D") as CollisionShape2D
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = collision.shape
		query.transform = collision.global_transform
		query.collision_mask = 2 | 4 | 16
		query.exclude = [(racer as RigidBody2D).get_rid()]
		if not _expect(racer.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(), "finale grid cars clear physical scenery"): return
	live.free()
	await process_frame
	print("RUN_FINALE_TEST PASS authored_route seed_stability exclusive_hazard six_cars hardest_ai long_tier stop_facts")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("RUN_FINALE_TEST FAIL: " + message)
	quit(1)
	return false
