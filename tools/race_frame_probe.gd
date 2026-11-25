extends SceneTree

## Measures a live race's frame pacing so a stutter fix is judged by numbers,
## not by feel. It is a probe, not a gate: it reports and exits 0 even on a
## slow host, because loaded and shared machines are expected.
##
##   PC_PROBE_SECONDS=60 xvfb-run -a godot --path . --script res://tools/race_frame_probe.gd
##
## The player holds the throttle; the probe prints 10 s windows and the worst
## frames, including car-pose uploads and draw calls at the time of a stall.

const RACE_READY_TIMEOUT_MSEC := 30000
const STALL_MS := 45.0
const WINDOW_MS := 10000
const DEFAULT_SECONDS := 60


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var seconds := int(OS.get_environment("PC_PROBE_SECONDS"))
	if seconds <= 0:
		seconds = DEFAULT_SECONDS
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for i in 8:
		await process_frame
	var app := root.get_node_or_null("App")
	var night: RunSession = app.call("start_run", 1806001) as RunSession
	if not bool(app.call("start_run_race", night.current_node_id)):
		push_error("RACE_FRAME_PROBE FAIL: opening race refused")
		quit(1)
		return
	# Use the app's real transition, not a hand-instantiated scene: the loading
	# prewarm is part of the player path and skipping it would measure a race no
	# player runs.
	app.call("_begin_race_transition", night.current_car_id)
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + RACE_READY_TIMEOUT_MSEC
	var race: Node = null
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if tree.current_scene != null and tree.current_scene.get("race_manager") != null:
			race = tree.current_scene
			break
	if race == null:
		push_error("RACE_FRAME_PROBE FAIL: race scene did not open")
		quit(1)
		return
	var manager := race.get("race_manager") as Node
	var director: Node = app.get("audio_director")
	while not bool(manager.get("is_running")) and Time.get_ticks_msec() < deadline:
		await process_frame
	while bool(race.get("_countdown_active")) and Time.get_ticks_msec() < deadline:
		await process_frame
	Input.action_press("accelerate")
	var stalls: Array[Dictionary] = []
	var last := Time.get_ticks_usec()
	var window_start := last
	var window_frames := 0
	var window_worst := 0.0
	var poses := ProceduralIdentityLibrary.motion_image_generations
	var start := last
	while Time.get_ticks_usec() - start < seconds * 1_000_000:
		await process_frame
		var now := Time.get_ticks_usec()
		var frame_ms := float(now - last) / 1000.0
		last = now
		window_frames += 1
		window_worst = maxf(window_worst, frame_ms)
		if frame_ms >= STALL_MS:
			stalls.append({
				"ms": snappedf(frame_ms, 0.1),
				"race": snappedf(float(manager.get("race_time")), 1),
				"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
				"score_gens": director.call("get_live_score_generations") if is_instance_valid(director) else -1,
			})
		var elapsed := float(now - window_start) / 1000.0
		if elapsed >= WINDOW_MS:
			_report_window(window_frames, elapsed, window_worst, manager, poses, director)
			poses = ProceduralIdentityLibrary.motion_image_generations
			window_start = now
			window_frames = 0
			window_worst = 0.0
	Input.action_release("accelerate")
	stalls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["ms"]) > float(b["ms"]))
	print("RACE_FRAME_PROBE stalls_over_%dms=%d" % [int(STALL_MS), stalls.size()])
	for index in mini(stalls.size(), 12):
		print("RACE_FRAME_STALL ", JSON.stringify(stalls[index]))
	quit(0)


func _report_window(frames: int, elapsed_ms: float, worst_ms: float, manager: Node, poses_before: int, director: Node) -> void:
	var score_gens := int(director.call("get_live_score_generations")) if is_instance_valid(director) else -1
	print("RACE_FRAME_WINDOW fps=", snappedf(frames * 1000.0 / elapsed_ms, 1),
		" worst_ms=", snappedf(worst_ms, 1),
		" pose_installs=", ProceduralIdentityLibrary.motion_image_generations - poses_before,
		" score_gens=", score_gens,
		" race=", snappedf(float(manager.get("race_time")), 1))
