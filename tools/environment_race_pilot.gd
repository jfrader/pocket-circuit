extends "res://scripts/race/prototype_race.gd"

const PILOT_ART := preload("res://tools/environment_race_art.gd")
@export_enum("kitchen", "workshop", "office") var pilot_theme := "kitchen"
@export var capture_mode := false
var pilot_ready := false
var pilot_art := PILOT_ART.new()
var pilot_frame_gap_ms := 0.0
var pilot_slowest_phase := ""
var runtime_fps := 0.0
var auto_drive := "--pilot-autodrive" in OS.get_cmdline_user_args()
var _drive_report_elapsed := 0.0
var _last_frame_usec := 0
var _pilot_phase := "Initializing"


func _ready() -> void:
	var requested := OS.get_environment("PC_THEME")
	if requested in ["kitchen", "workshop", "office"]:
		pilot_theme = requested
	capture_mode = capture_mode or OS.get_environment("PC_PILOT_CAPTURE") == "1"
	if auto_drive:
		capture_mode = false
	is_preparing = true
	var initial_player := get_tree().get_first_node_in_group("player_vehicle") as VehicleController
	if initial_player:
		initial_player.freeze = true
		initial_player.set_controls_locked(true)
	track_root.hide()
	_create_phase_one_ui()
	var definition: Dictionary = pilot_art.manifest["themes"][pilot_theme]
	_session = {"mode": "pilot", "vehicle_id": "rustbug", "event": {"name": definition["story"], "theme": pilot_theme, "circuit": "generated", "laps": 3}}
	_configure_session()
	_countdown_label.text = "Loading"
	_countdown_label.show()
	await get_tree().process_frame
	var preparation := PREPARATION_SCRIPT.new()
	add_child(preparation)
	var prepared: Dictionary = await preparation.run_data_job(pilot_art.prepare.bind(pilot_theme))
	await pilot_art.prepare_props(_pilot_stage)
	var embedded := track_root
	remove_child(embedded)
	embedded.free()
	track_root = TRACK_BUILDER.create_layout_root(prepared)
	track_root.name = "Track"
	add_child(track_root)
	await TRACK_BUILDER.assemble_runtime(track_root, prepared, _pilot_stage, pilot_art.dress)
	_apply_track_variant(StringName(pilot_theme))
	pilot_art.restyle_hazard(_track_variant_presenter)
	var field_racers: Array[Dictionary] = _build_field_racers_for_preparation()
	var visual_keys: Dictionary = IDENTITIES.resolve_field_visual_keys(field_racers)
	for visual_key: String in visual_keys.values():
		await _pilot_stage("Preparing vehicle animation")
		var plan := IDENTITIES.motion_preparation_plan_for_key(visual_key)
		if not (plan["jobs"] as Array).is_empty():
			var rendered: Dictionary = await preparation.run_data_job(IDENTITIES.render_motion_plan.bind(plan))
			for index in rendered["jobs"].size():
				IDENTITIES.install_motion_image_for_key(visual_key, rendered["jobs"][index], rendered["images"][index])
				await _pilot_stage("Preparing vehicle animation")
	preparation.queue_free()
	var director := _audio_director()
	if director:
		for racer: Dictionary in field_racers:
			await _pilot_stage("Preparing race audio")
			director.call("warm_vehicle_audio", String(racer["vehicle_id"]))
	await _pilot_stage("Setting the starting grid")
	_complete_race_setup(not capture_mode)
	is_preparing = false
	if capture_mode:
		var focal: Vector2 = track_root.get_meta("pilot_focal", _player_vehicle.position)
		var detail_center := focal
		for item: Dictionary in pilot_art.placements:
			if item["asset_key"] == "medium" and item["body"].get_meta("cluster_index", -1) == 0:
				detail_center = focal.lerp((item["body"] as Node2D).position, 0.5)
				break
		var line := track_root.get_node("RacingLine") as Line2D
		var closest: Dictionary = TRACK_BUILDER._closest_point_on_loop(focal, line.points)
		var target: Vector2 = closest["position"]
		var tangent := TRACK_BUILDER._sample_tangent(line.points, int(closest["index"]))
		_player_vehicle.place_on_grid(Transform2D(tangent.angle() + PI * 0.5, target))
		for frame in 3:
			await get_tree().physics_frame
		for racer: Node2D in race_manager.get_rankings():
			(racer as RigidBody2D).freeze = true
		_countdown_label.hide()
		_update_race_hud()
		camera.set_physics_process(false)
		camera.global_position = _player_vehicle.global_position.lerp(detail_center, 0.6)
		camera.zoom = Vector2.ONE * 0.9
		camera.reset_smoothing()
		camera.force_update_scroll()
	await get_tree().process_frame
	pilot_ready = true
	print("NATIVE_RACE_PILOT_READY theme=%s racers=%d frame_gap=%.1f phase=%s frame=%d" % [pilot_theme, race_manager.get_rankings().size(), pilot_frame_gap_ms, pilot_slowest_phase, Engine.get_process_frames()])


func _process(delta: float) -> void:
	runtime_fps = Engine.get_frames_per_second()
	var now := Time.get_ticks_usec()
	if _last_frame_usec > 0 and not pilot_ready:
		var gap := float(now - _last_frame_usec) / 1000.0
		if gap > pilot_frame_gap_ms:
			pilot_frame_gap_ms = gap
			pilot_slowest_phase = _pilot_phase
	_last_frame_usec = now
	super._process(delta)
	if pilot_ready and auto_drive:
		_drive_report_elapsed += delta
		if _drive_report_elapsed >= 5.0:
			_drive_report_elapsed = 0.0
			print("PILOT_DRIVE time=%.1f position=%s speed=%.1f checkpoint=%d" % [race_manager.race_time, _player_vehicle.position, _player_vehicle.speed, race_manager.get_expected_checkpoint(_player_vehicle)])


func _pilot_stage(phase: String) -> void:
	_pilot_phase = phase
	await get_tree().process_frame


func _configure_racers() -> void:
	super._configure_racers()
	if auto_drive:
		var driver := AI_CONTROLLER_SCRIPT.new() as AIVehicleController
		_player_vehicle.add_child(driver)
		driver.configure(_player_vehicle, race_manager, 0.0, "club_circuit", "rae", CATALOG.get_driver("rae").get("ai_style", {}))


func _attempt_result_commit(results: Array) -> void:
	_update_results(results)


func _update_results(results: Array) -> void:
	var lines := PackedStringArray(["PILOT RESULTS", ""])
	for result: Dictionary in results:
		var status := "DNF" if bool(result.get("dnf", false)) else (_format_time(float(result["time"])) if bool(result.get("finished", false)) else "RACING")
		lines.append("%d. %s · %s" % [int(result["position"]), String(result["driver_name"]), status])
	_results_label.text = "\n".join(lines)


func restart_race() -> void:
	_left_results = true
	_set_paused(false)
	get_tree().reload_current_scene()


func request_return() -> void:
	_set_paused(false)
	get_tree().quit()
