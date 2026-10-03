extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const LAYOUT := preload("res://scripts/race/strip_layout.gd")
const VEHICLE_SCENE := preload("res://scenes/vehicles/rustbug.tscn")
const AI_SCRIPT := preload("res://scripts/vehicle/ai_vehicle_controller.gd")
const TRAFFIC_SCRIPT := preload("res://scripts/race/strip/strip_traffic.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
const TRACK_CATALOG := preload("res://scripts/race/track_builder_catalog.gd")
const SAMPLE_FRAMES := 600


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var test_room: PackedVector2Array = TRACK_CATALOG.ROOM_SHAPES[&"classic"].duplicate()
	for index in test_room.size():
		test_room[index].y *= 4.0
	var prepared := LAYOUT.prepare(&"kitchen", &"classic", 42, {"route_shape": "strip"}, TRACK_CATALOG.LAYOUTS[&"kitchen"], test_room, TRACK_CATALOG.ROOM_COMPOSITIONS[&"kitchen"])
	var manager := RaceManager.new()
	manager.add_to_group("race_manager")
	get_root().add_child(manager)
	var track := BUILDER.create_layout_root(prepared)
	track.name = "Track"
	get_root().add_child(track)
	await BUILDER.assemble_runtime(track, prepared, Callable())
	var gates: Array = []
	for child in track.get_children():
		if child.is_in_group("track_checkpoints"):
			gates.append(child)
	manager.configure_checkpoints(gates)
	var gate_count := (prepared["strip_gates"] as Array).size()
	manager.configure_strip_route(1, gate_count - 1)
	manager.configure_route_reference(prepared["centerline"], true)
	var arcs := LAYOUT._arc_lengths(prepared["centerline"])
	var player_arc := minf(float(prepared["strip_length"]) - 500.0, 9000.0)
	var player := VEHICLE_SCENE.instantiate() as VehicleController
	get_root().add_child(player)
	player.place_on_grid(LAYOUT.sample_at_arc(prepared["centerline"], arcs, player_arc))
	player.freeze = true
	player.collision_layer = 0
	player.collision_mask = 0
	manager.register_racer(player, "Player", "Rustbug", true)
	var chaser := VEHICLE_SCENE.instantiate() as VehicleController
	chaser.remove_from_group("player_vehicle")
	chaser.add_to_group("race_vehicle")
	chaser.stats = CATALOG.create_vehicle_stats("pinbolt")
	get_root().add_child(chaser)
	chaser.place_on_grid(prepared["strip_grid"]["chaser"])
	chaser.set_player_controlled(false)
	manager.register_racer(chaser, "Chaser", "Pinbolt")
	var ai := AI_SCRIPT.new() as AIVehicleController
	chaser.add_child(ai)
	ai.configure(chaser, manager, 0.0, "club_circuit", "juniper", {}, player)
	var traffic := TRAFFIC_SCRIPT.new() as StripTraffic
	track.add_child(traffic)
	traffic.configure(prepared["centerline"], float(prepared["strip_half_width"]), prepared["traffic_plan"], manager)
	manager.prepare_race()
	manager.start_race()
	var start := chaser.global_position
	var start_distance := start.distance_to(player.global_position)
	var start_arc := float(ai.call("_active_route_sample", 1)["arc"])
	var start_progress := manager.get_racer_progress(chaser)
	var highest := start_progress
	var worst_regression := 0.0
	var timeline: Array[String] = []
	for frame in SAMPLE_FRAMES:
		await physics_frame
		if frame % 120 == 0:
			timeline.append("%.1fs p=%.2f pos=%s vel=%s expected=%d target=%s" % [float(frame) / 60.0, manager.get_racer_progress(chaser), chaser.global_position, chaser.linear_velocity, manager.get_expected_checkpoint(chaser), ai.call("_reference_goal", Vector2.UP.rotated(chaser.rotation), 250.0)["goal"]])
		if frame % 30 == 0:
			var progress := manager.get_racer_progress(chaser)
			worst_regression = maxf(worst_regression, highest - progress)
			highest = maxf(highest, progress)
	var final_progress := manager.get_racer_progress(chaser)
	var distance := chaser.global_position.distance_to(player.global_position)
	var final_arc := float(ai.call("_active_route_sample", manager.get_expected_checkpoint(chaser))["arc"])
	var recoveries := ai.recovery_count
	if recoveries > 0 or final_progress <= start_progress + 0.3 or worst_regression > 0.6 or final_arc <= start_arc + 1000.0 or player_arc - final_arc >= player_arc - start_arc - 1000.0:
		push_error("Chaser stalled: progress %.2f->%.2f, regression %.2f, travel %.0f, distance %.0f, recoveries %d reasons %s timeline %s" % [start_progress, final_progress, worst_regression, chaser.global_position.distance_to(start), distance, recoveries, ai.recovery_reasons, timeline])
		quit(1)
		return
	chaser.place_on_grid(LAYOUT.sample_at_arc(prepared["centerline"], arcs, float(prepared["strip_length"]) - 150.0))
	ai.set("_reference_nearest_index", -1)
	var terminal: Vector2 = ai.call("_reference_goal", Vector2.UP.rotated(chaser.rotation), 300.0)["goal"]
	if terminal.distance_to((prepared["centerline"] as PackedVector2Array)[-1]) > 1.0 or bool(ai.call("_active_route_sample", manager.get_expected_checkpoint(chaser))["closed"]):
		push_error("Open AI lookahead wrapped behind the finish cap")
		quit(1)
		return
	print("STRIP_CHASER_TEST PASS progress=%.2f->%.2f arc=%.0f->%.0f player_arc=%.0f distance=%.0f->%.0f recoveries=%d" % [start_progress, final_progress, start_arc, final_arc, player_arc, start_distance, distance, recoveries])
	quit(0)
