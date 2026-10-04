extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const LAYOUT := preload("res://scripts/race/strip_layout.gd")
const VEHICLE_SCENE := preload("res://scenes/vehicles/rustbug.tscn")
const AI_SCRIPT := preload("res://scripts/vehicle/ai_vehicle_controller.gd")
const TRAFFIC_SCRIPT := preload("res://scripts/race/strip/strip_traffic.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
const SAMPLE_FRAMES := 1200


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var prepared := BUILDER.prepare_layout(&"kitchen", &"classic", 42, {"route_shape": "strip"})
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
	var min_dist_stationary := 9999.0
	for frame in SAMPLE_FRAMES:
		await physics_frame
		var dd := chaser.global_position.distance_to(player.global_position)
		if dd < min_dist_stationary:
			min_dist_stationary = dd
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
	if recoveries > 2 or final_progress <= start_progress + 0.3 or worst_regression > 0.6 or final_arc <= start_arc + 1000.0 or player_arc - final_arc >= player_arc - start_arc - 1000.0:
		push_error("Chaser stalled: progress %.2f->%.2f, regression %.2f, travel %.0f, distance %.0f, recoveries %d reasons %s timeline %s" % [start_progress, final_progress, worst_regression, chaser.global_position.distance_to(start), distance, recoveries, ai.recovery_reasons, timeline])
		quit(1)
		return
	# stationary target evidence (from bug: must not fly to cap; after sim chaser dist from stationary)
	print("STRIP_CHASER stationary: min_dist=%.1f (target <=90 for capture on stationary)" % min_dist_stationary)
	if min_dist_stationary > 90.0:
		push_error("STRIP_CHASER stationary: never reached <=90 (min=%.1f)" % min_dist_stationary)
		quit(1)
		return

	# === clean full-speed player for ~20s: chaser should not sustain close ===
	player.freeze = false
	chaser.place_on_grid(prepared["strip_grid"]["chaser"])
	ai.set("_reference_nearest_index", -1)
	ai.recovery_count = 0
	ai.recovery_reasons.clear()
	var clean_min := 9999.0
	var clean_max_consec_below := 0
	var consec := 0
	for frame in 1200:
		await physics_frame
		# simulate clean full speed drive (no input, direct vel for test harness)
		var pforward := Vector2.UP.rotated(player.rotation)
		player.linear_velocity = pforward * 210.0
		var dd := chaser.global_position.distance_to(player.global_position)
		if dd < clean_min:
			clean_min = dd
		if dd < 90.0:
			consec += 1
			if consec > clean_max_consec_below:
				clean_max_consec_below = consec
		else:
			consec = 0
	print("STRIP_CHASER clean fullspeed: min_dist=%.1f max_consec_below90=%d (never sustained >=1.5s)" % [clean_min, clean_max_consec_below])
	if clean_max_consec_below > 90:
		push_error("STRIP_CHASER clean: sustained close too long max_consec=%d" % clean_max_consec_below)
		quit(1)
		return
	if clean_min < 50.0:  # sanity, shouldn't ram
		push_error("STRIP_CHASER clean: min too low %.1f (ram?)" % clean_min)
		quit(1)
		return

	# === player lifts after ~8s: chaser catches ===
	chaser.place_on_grid(prepared["strip_grid"]["chaser"])
	ai.set("_reference_nearest_index", -1)
	ai.recovery_count = 0
	ai.recovery_reasons.clear()
	# reset player to a catchable position ahead (mid strip)
	var lift_player_arc := minf(float(prepared["strip_length"]) - 2500.0, 6500.0)
	player.place_on_grid(LAYOUT.sample_at_arc(prepared["centerline"], arcs, lift_player_arc))
	player.linear_velocity = Vector2.UP.rotated(player.rotation) * 210.0
	var lift_min := 9999.0
	var caught := false
	for frame in 1200:
		await physics_frame
		var pforward := Vector2.UP.rotated(player.rotation)
		if frame < 480:  # ~8s full speed
			player.linear_velocity = pforward * 210.0
		else:
			player.linear_velocity = pforward * 20.0  # lift / slow
		var dd := chaser.global_position.distance_to(player.global_position)
		if dd < lift_min:
			lift_min = dd
		if dd <= 90.0:
			caught = true
	print("STRIP_CHASER lift after 8s: min_dist=%.1f caught=%s (target true)" % [lift_min, caught])
	if lift_min > 90.0:
		push_error("STRIP_CHASER lift: never caught after lift (min=%.1f)" % lift_min)
		quit(1)
		return

	print("STRIP_CHASER_TEST PASS all cases")
	quit(0)
