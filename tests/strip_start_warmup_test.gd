extends SceneTree

const FIXED_FPS := 60
const RUNNING_TICKS := 30
const MAX_RUNNING_FRAME_US := 50000
const LOAD_TIMEOUT_MS := 90000
const TRAFFIC_VISUALS := preload("res://scripts/race/strip/traffic_visuals.gd")
const AI := preload("res://scripts/vehicle/ai_vehicle_controller.gd")
const WARMUP := preload("res://scripts/race/strip/strip_start_warmup.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")

var _draw_calls := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not await _check_draw_hook():
		return
	change_scene_to_file("res://scenes/boot/boot.tscn")
	await process_frame
	await process_frame
	var app := root.get_node("App")
	var loading_started := Time.get_ticks_msec()
	if not app.call("start_strip_race", &"kitchen", &"classic", 42, "rustbug"):
		_fail("Could not start strip")
		return
	var deadline := Time.get_ticks_msec() + LOAD_TIMEOUT_MS
	while app.call("is_race_loading") and Time.get_ticks_msec() < deadline:
		await process_frame
	if app.call("is_race_loading"):
		_fail("Loading did not finish")
		return
	var race := current_scene
	var manager := race.get_node("RaceManager") as RaceManager
	var warm: Dictionary = race.get_meta("strip_start_warmup", {})
	if not warm.get("complete", false) or int(warm.get("frames", 0)) != TRAFFIC_VISUALS.MOTION_POSE_COUNT:
		_fail("Loading did not draw the full strip and every prepared traffic pose")
		return
	var prepared: Dictionary = race.get("_strip_prepared")
	for point: Vector2 in prepared["room_polygon"]:
		if not (warm["bounds"] as Rect2).has_point(point):
			_fail("Warm-up omitted part of a room")
			return
	var traffic := race.get_node("StripTraffic") as StripTraffic
	for racer: Node2D in manager.get_rankings():
		for child: Node in racer.get_children():
			if child is AIVehicleController:
				var ai := child as AIVehicleController
				if ai._tree_cache_dirty or ai._reference_nearest_index < 0 or ai._racing_line_nearest_index < 0 or manager.race_started.is_connected(Callable(ai, "_cache_checkpoints")):
					_fail("Chaser start caches were left for the GO signal")
					return
	for car: TrafficCar in traffic.get_children():
		if not car._visual.motion_preparation_plan()["poses"].is_empty() or car._visual._travel != 0.0 or not car.freeze:
			_fail("Traffic must be completely prepared without advancing under loading")
			return
	print("STRIP_START_PREPARE loading_ms=%d cars=%d pose_count=%d draw_frames=%d warm_bounds=%s" % [Time.get_ticks_msec() - loading_started, traffic.get_child_count(), TRAFFIC_VISUALS.MOTION_POSE_COUNT, warm["frames"], warm["bounds"]])
	var director := app.get("audio_director") as Node
	var generations := int(director.call("get_live_score_generations"))
	var scans := AI.tree_group_scan_count
	var racers_before := IDENTITIES.motion_image_generations
	var raster_before := TRAFFIC_VISUALS.motion_image_generation_usec
	var images_before := TRAFFIC_VISUALS.motion_image_generations
	var last := Time.get_ticks_usec()
	while not manager.is_running and Time.get_ticks_msec() < deadline:
		last = Time.get_ticks_usec()
		await physics_frame
	if not manager.is_running:
		_fail("Countdown did not reach GO")
		return
	var ticks: Array[int] = []
	for tick in RUNNING_TICKS:
		var now := Time.get_ticks_usec()
		ticks.append(now - last)
		last = now
		await physics_frame
	# At fixed FPS headless Godot runs unthrottled. These boundary timings cover
	# the real running scene, physics integration, audio and main-loop work;
	# they include scheduling overhead, not just individual script CPU time.
	print("STRIP_START_CPU first_30_tick_wall_us=%s max_tick_us=%d section=%s" % [ticks, ticks.max(), director.call("get_live_requested_section")])
	print("STRIP_START_RASTER images=%d usec=%d" % [TRAFFIC_VISUALS.motion_image_generations - images_before, TRAFFIC_VISUALS.motion_image_generation_usec - raster_before])
	if TRAFFIC_VISUALS.motion_image_generations != images_before or IDENTITIES.motion_image_generations != racers_before or AI.tree_group_scan_count != scans:
		_fail("GO performed lazy rasterization or a chaser group-cache rebuild")
		return
	if int(ticks.max()) > MAX_RUNNING_FRAME_US:
		_fail("First running frames contain a preparation stall")
		return
	if int(director.call("get_live_score_generations")) != generations or director.call("get_live_requested_section") != "grid":
		_fail("GO changed or regenerated the existing opening music")
		return
	print("STRIP_START_WARMUP_TEST PASS no_first_running_frame_stall full_runner_draw camera_restore cancellation no_gameplay_rasterization")
	current_scene.queue_free()
	current_scene = null
	await process_frame
	quit(0)


func _check_draw_hook() -> bool:
	var camera := Camera2D.new()
	root.add_child(camera)
	var traffic := StripTraffic.new()
	root.add_child(traffic)
	camera.position = Vector2(120, 360)
	camera.zoom = Vector2(1.05, 1.05)
	camera.offset = Vector2(3, 7)
	camera.position_smoothing_enabled = true
	var original := camera.global_transform
	var room := PackedVector2Array([Vector2(-1500, -26000), Vector2(1500, 26000)])
	for cancel in [false, true]:
		_draw_calls = 0
		var result := await WARMUP.draw_runner(camera, room, traffic, _observe_draw.bind(camera, room), func() -> bool: return cancel and _draw_calls >= 2)
		if bool(result["complete"]) == cancel or _draw_calls != (2 if cancel else TRAFFIC_VISUALS.MOTION_POSE_COUNT) or camera.global_transform != original or camera.zoom != Vector2(1.05, 1.05) or camera.offset != Vector2(3, 7) or not camera.position_smoothing_enabled or camera.process_mode != Node.PROCESS_MODE_INHERIT:
			_fail("Warm-up must restore the camera even when cancelled")
			return false
	camera.free()
	traffic.free()
	return true


func _observe_draw(camera: Camera2D, room: PackedVector2Array) -> void:
	var size := camera.get_viewport_rect().size / camera.zoom
	var visible := Rect2(camera.get_screen_center_position() - size * 0.5, size)
	for point in room:
		if not visible.has_point(point):
			_fail("Warm camera excludes a room endpoint")
	_draw_calls += 1
	await process_frame


func _fail(message: String) -> void:
	push_error("STRIP_START_WARMUP_TEST FAIL: " + message)
	quit(1)
