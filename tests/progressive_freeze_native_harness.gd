extends SceneTree

## Native rendered + live audio progressive freeze harness.
## Run under: xvfb-run -a --server-args="-screen 0 640x480x24" \
##   /usr/bin/godot --path . --rendering-method gl_compatibility \
##   --resolution 640x480 --script res://tests/progressive_freeze_native_harness.gd
## (Deliberately omits --audio-driver Dummy and --headless so Gamestruments live
## audio and real renderer run; this is the only way to reproduce the user freeze.)
##
## Drives NUM_RACES with REAL LAPS (several seconds of actual driving in _physics_process
## and _process, no result shortcut until after drive window) to measure per-frame cost.
## Records per race during driving window:
##   avg/max physics frame time, process frame time, fps (min/avg), collision pairs,
##   PHYSICS_2D_* monitors, render draw/objects/prims, plus track props:
##   route_length, surface_zone count, StaticBody2D collider count.
## Also full before/after snapshots for accumulation.
## Keep total wall time bounded (<2min for 3 races x ~6s drive + load).

const APP_PATH := "/root/App"
const RACE_SCENE := "res://scenes/race/prototype_race.tscn"
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const AUDIO_DIRECTOR_SCRIPT := preload("res://scripts/audio/audio_director.gd")
const TRACK_CORE := preload("res://scripts/race/track_builder_core.gd")
const ENGINE_LOOP_GEN := preload("res://scripts/audio/engine/engine_loop_generator.gd")
const ENGINE_VOICE_GEN := preload("res://scripts/audio/engine/engine_voice_generator.gd")
const AI_CONTROLLER_SCRIPT := preload("res://scripts/vehicle/ai_vehicle_controller.gd")
const RACE_MANAGER_SCRIPT := preload("res://scripts/race/race_manager.gd")
const ENV_HAZARD_SCRIPT := preload("res://scripts/race/environmental_hazard.gd")

const NUM_RACES := 3
const BASE_SEED := 424242
const DRIVE_SECONDS := 5.5  # real driving time per race to exercise per-tick costs

## Long single-race trace (PC_LONG_TRACE=1): drive one race for a minute+ and
## sample ~once per second so we can see exactly what grows (or does not) over a
## long driving session instead of the ~5s window every prior harness used.
const LONG_TRACE_SECONDS := 90.0
const LONG_TRACE_SAMPLE_SECONDS := 1.0

var _race_results: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 1.0
	# Rendered run: uncap so the harness finishes in reasonable wall time; real
	# user runs are vsynced but the accumulation is independent of fps cap.
	Engine.max_fps = 0

	var app := root.get_node_or_null(APP_PATH)
	if not _expect(app != null, "App autoload must exist"):
		return

	# Start clean from boot
	if current_scene == null or current_scene.scene_file_path != "res://scenes/boot/boot.tscn":
		change_scene_to_file("res://scenes/boot/boot.tscn")
		await process_frame
		await process_frame

	if OS.get_environment("PC_LONG_TRACE") == "1":
		await _run_long_trace(app)
		return

	_race_results.clear()
	for r in NUM_RACES:
		var seed := BASE_SEED + r * 1000
		var before := _snapshot("before_race_%d" % r)
		var drive := await _run_one_real_drive_race(app, seed)
		if drive.is_empty():
			return
		# Let a couple rendered frames so Performance and audio children settle
		await process_frame
		await process_frame
		var after := _snapshot("after_race_%d" % r)
		_race_results.append({
			"race": r,
			"before": before,
			"after": after,
			"drive": drive,
		})
		await _ensure_back_in_boot(app)

	_print_report()

	# For native harness we do not assert (gate runs are headless only); we only
	# measure and name what grows. The progressive_freeze_harness.gd is extended
	# separately to regress the bounded-object part.
	print("PROGRESSIVE_FREEZE_NATIVE_HARNESS PASS races=%d" % NUM_RACES)
	quit(0)


func _run_long_trace(app: Node) -> void:
	# Real-game conditions: 60 Hz physics (the project never overrides the
	# default) and a 60 fps cap approximating vsync, so per-frame time budget
	# matches what the user experiences rather than the 240 Hz stress rate the
	# short harness used to reproduce accumulation.
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_fps = 60

	var seed := int(OS.get_environment("PC_LONG_TRACE_SEED")) if OS.get_environment("PC_LONG_TRACE_SEED").is_valid_int() else BASE_SEED
	var ok: bool = app.call("start_circuit_race", &"kitchen", &"classic", seed, "rustbug")
	if not _expect(ok, "start_circuit_race must succeed for long trace seed %d" % seed):
		return

	var deadline := Time.get_ticks_msec() + 60000
	while app.call("is_race_loading") and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _expect(not app.call("is_race_loading") and not app.get("_loading_failed"), "loading must complete for long trace"):
		return

	var race := current_scene
	if not _expect(race != null and race.scene_file_path == RACE_SCENE, "must be in race scene"):
		return
	var race_manager := race.get_node_or_null("RaceManager") as Node
	if not _expect(race_manager != null, "RaceManager must exist"):
		return

	var start_deadline := Time.get_ticks_msec() + 15000
	while not bool(race_manager.get("is_running")) and Time.get_ticks_msec() < start_deadline:
		await process_frame
	if not _expect(bool(race_manager.get("is_running")), "race must start running"):
		return

	# Baseline counters (statics persist across the process; we measure deltas
	# over the drive window).
	var base_scans := int(AI_CONTROLLER_SCRIPT.tree_group_scan_count)
	var base_probes := int(AI_CONTROLLER_SCRIPT.surface_zone_probe_count)
	var base_route := int(RACE_MANAGER_SCRIPT.route_tangent_query_count)
	var base_ranks := int(RACE_MANAGER_SCRIPT.ranking_sort_count)
	var base_overlap := int(ENV_HAZARD_SCRIPT.overlap_poll_count)

	var race_time_prev := float(race_manager.get("race_time"))
	var wall_prev := Time.get_ticks_msec()
	var duration_seconds := LONG_TRACE_SECONDS
	var requested_seconds := OS.get_environment("PC_LONG_TRACE_SECONDS")
	if requested_seconds.is_valid_float():
		duration_seconds = clampf(float(requested_seconds), 1.0, 600.0)
	var duration_ms := int(duration_seconds * 1000.0)
	var drive_start := Time.get_ticks_msec()
	var drive_end := drive_start + duration_ms
	var sample_start := drive_start
	var sample_end := sample_start + int(LONG_TRACE_SAMPLE_SECONDS * 1000.0)

	var physics_sum := 0.0
	var physics_max := 0.0
	var process_sum := 0.0
	var process_max := 0.0
	var fps_sum := 0.0
	var fps_min := 9999.0
	var frames := 0
	var physics_ticks := 0
	var sample_index := 0

	print("LONG_TRACE_HEADER t_s physics_avg_ms physics_max_ms process_avg_ms process_max_ms fps_min audio_avail underruns scans probes route_queries ranking_sorts overlap_polls ghost lap race_dt_s objects nodes mem_kb pairs active speed")

	while Time.get_ticks_msec() < drive_end and current_scene != null and current_scene.scene_file_path == RACE_SCENE:
		await process_frame
		var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		var proc := Performance.get_monitor(Performance.TIME_PROCESS)
		var fps := Performance.get_monitor(Performance.TIME_FPS)
		physics_sum += phys
		physics_max = maxf(physics_max, phys)
		process_sum += proc
		process_max = maxf(process_max, proc)
		fps_sum += fps
		fps_min = minf(fps_min, fps)
		frames += 1

		var now := Time.get_ticks_msec()
		if now < sample_end:
			continue
		# One wall-second elapsed: emit a sample.
		var n := maxi(1, frames)
		var race_time_now := float(race_manager.get("race_time"))
		var audio_avail := _engine_voice_frames_available()
		var underruns := _engine_voice_underruns()
		var ghost := _ghost_sample_count(race)
		var speed := _player_speed(race)
		print("LONG_TRACE t=%.0f phys_avg=%.3f phys_max=%.3f proc_avg=%.3f proc_max=%.3f fps_min=%.1f audio=%d underruns=%d scans=%d probes=%d route=%d ranks=%d overlap=%d ghost=%d lap=%d race_dt=%.3f objects=%d nodes=%d mem=%.0f pairs=%d active=%d speed=%.1f" % [
			float(sample_index) * LONG_TRACE_SAMPLE_SECONDS,
			physics_sum / n,
			physics_max,
			process_sum / n,
			process_max,
			fps_min,
			audio_avail,
			underruns,
			int(AI_CONTROLLER_SCRIPT.tree_group_scan_count) - base_scans,
			int(AI_CONTROLLER_SCRIPT.surface_zone_probe_count) - base_probes,
			int(RACE_MANAGER_SCRIPT.route_tangent_query_count) - base_route,
			int(RACE_MANAGER_SCRIPT.ranking_sort_count) - base_ranks,
			int(ENV_HAZARD_SCRIPT.overlap_poll_count) - base_overlap,
			ghost,
			int(race_manager.get("lap_count")),
			race_time_now - race_time_prev,
			Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.MEMORY_STATIC),
			int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)),
			int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)),
			speed,
		])
		race_time_prev = race_time_now
		wall_prev = now
		sample_start = now
		sample_end = now + int(LONG_TRACE_SAMPLE_SECONDS * 1000.0)
		physics_sum = 0.0
		physics_max = 0.0
		process_sum = 0.0
		process_max = 0.0
		fps_sum = 0.0
		fps_min = 9999.0
		frames = 0
		sample_index += 1

	# Clean up: leave the race and return to boot so a repeated run stays clean.
	var fake_results: Array = [
		{"position": 1, "driver_name": "Rae", "vehicle_name": "Rustbug", "time": 45.0, "finished": true, "dnf": false},
	]
	app.call("report_race_result", 1, 45.0, fake_results, false, {})
	await process_frame
	app.call("continue_after_race", true)
	print("PROGRESSIVE_FREEZE_LONG_TRACE PASS samples=%d" % sample_index)
	quit(0)


func _engine_voice_frames_available() -> int:
	var player := _find_node_named(root, "EngineVoicePlayer")
	if player == null:
		return -1
	var playback: Variant = (player as AudioStreamPlayer).get_stream_playback()
	if playback == null:
		return -1
	return int((playback as AudioStreamGeneratorPlayback).get_frames_available())


func _engine_voice_underruns() -> int:
	var app := root.get_node_or_null(APP_PATH)
	if app == null:
		return -1
	var director: Variant = app.get("audio_director")
	if not is_instance_valid(director):
		return -1
	var voice := (director as Node).get_node_or_null("EngineVoice")
	if not is_instance_valid(voice):
		return -1
	return int(voice.get("_underruns"))


func _ghost_sample_count(race: Node) -> int:
	var samples: Variant = race.get("_ghost_samples")
	return int(samples.size()) if samples is Array else -1


func _player_speed(race: Node) -> float:
	var player := race.get_tree().get_first_node_in_group("player_vehicle") as Node
	if player == null:
		return -1.0
	return float(player.get("speed"))


func _find_node_named(from: Node, wanted: String) -> Node:
	if from == null:
		return null
	if from.name == wanted:
		return from
	for child: Node in from.get_children():
		var hit := _find_node_named(child, wanted)
		if hit != null:
			return hit
	return null


func _run_one_real_drive_race(app: Node, seed: int) -> Dictionary:
	var ok: bool = app.call("start_circuit_race", &"kitchen", &"classic", seed, "rustbug")

	var deadline := Time.get_ticks_msec() + 30000
	while app.call("is_race_loading") and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _expect(not app.call("is_race_loading"), "loading must complete for seed %d"):
		return {}
	if app.get("_loading_failed"):
		_expect(false, "loading must not fail")
		return {}

	var race := current_scene
	if not _expect(race != null and race.scene_file_path == RACE_SCENE, "must be in race scene"):
		return {}

	var race_manager := race.get_node_or_null("RaceManager") as Node
	if not _expect(race_manager != null, "RaceManager must exist"):
		return {}

	# Touch identity for opponents (same as headless harness)
	var ev: Dictionary = app.call("get_current_race_session").get("event", {})
	var oids: Array = ev.get("opponents", []) if not ev.is_empty() else []
	for did_v in oids:
		var did := String(did_v)
		if not did.is_empty():
			var _p := IDENTITIES.avatar_payload(did)
			var _t := IDENTITIES.avatar_texture(did)

	# Wait for race to actually start driving (countdown ends, is_running)
	var start_deadline := Time.get_ticks_msec() + 15000
	while not bool(race_manager.get("is_running")) and Time.get_ticks_msec() < start_deadline:
		await process_frame
	if not _expect(bool(race_manager.get("is_running")), "race must start running for seed %d" % seed):
		return {}

	# Capture track scale properties once (these drive per-frame cost)
	var route_len := float(race_manager.get("_route_length"))
	var surface_zones: int = get_nodes_in_group("surface_zone").size()
	var collider_count := _count_static_colliders()

	# Drive for real seconds: AI controllers execute _physics_process hot paths,
	# rankings update per frame, surface/hazard queries run every tick.
	var drive_start := Time.get_ticks_msec()
	var drive_end := drive_start + int(DRIVE_SECONDS * 1000)
	var physics_sum := 0.0
	var physics_max := 0.0
	var process_sum := 0.0
	var process_max := 0.0
	var fps_sum := 0.0
	var fps_min := 9999.0
	var pairs_max: int = 0
	var active_max: int = 0
	var samples: int = 0
	while Time.get_ticks_msec() < drive_end and current_scene != null and current_scene.scene_file_path == RACE_SCENE:
		await process_frame
		var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		var proc := Performance.get_monitor(Performance.TIME_PROCESS)
		var fps := Performance.get_monitor(Performance.TIME_FPS)
		physics_sum += phys
		physics_max = maxf(physics_max, phys)
		process_sum += proc
		process_max = maxf(process_max, proc)
		fps_sum += fps
		fps_min = minf(fps_min, fps)
		var pairs := int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS))
		pairs_max = maxi(pairs_max, pairs)
		var act := int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS))
		active_max = maxi(active_max, act)
		samples += 1

	# Now end the race cleanly with fake result (after real driving exercised)
	var fake_results: Array = [
		{"position": 1, "driver_name": "Rae", "vehicle_name": "Rustbug", "time": 45.0, "finished": true, "dnf": false},
		{"position": 2, "driver_name": "Opp1", "vehicle_name": "Pinbolt", "time": 46.0, "finished": true, "dnf": false},
		{"position": 3, "driver_name": "Opp2", "vehicle_name": "Scrapjaw", "time": 47.0, "finished": true, "dnf": false},
		{"position": 4, "driver_name": "Opp3", "vehicle_name": "Flicker", "time": 48.0, "finished": true, "dnf": false},
	]
	var committed: bool = app.call("report_race_result", 1, 45.0, fake_results, false, {})
	if not _expect(committed, "report must succeed after real drive for seed %d" % seed):
		return {}

	await process_frame

	app.call("continue_after_race", true)

	deadline = Time.get_ticks_msec() + 10000
	while current_scene != null and current_scene.scene_file_path == RACE_SCENE and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	await process_frame

	var n: int = maxi(1, samples)
	return {
		"physics_avg": physics_sum / n,
		"physics_max": physics_max,
		"process_avg": process_sum / n,
		"process_max": process_max,
		"fps_avg": fps_sum / n,
		"fps_min": fps_min,
		"collision_pairs_max": pairs_max,
		"physics_2d_active_max": active_max,
		"samples": samples,
		"route_length": route_len,
		"surface_zones": surface_zones,
		"collider_count": collider_count,
	}


func _ensure_back_in_boot(app: Node) -> bool:
	if current_scene == null or current_scene.scene_file_path != "res://scenes/boot/boot.tscn":
		change_scene_to_file("res://scenes/boot/boot.tscn")
		await process_frame
		await process_frame
	app.set("_quick_roster", {})
	if app.has_method("get_current_race_session"):
		var sess: Dictionary = app.call("get_current_race_session")
		if not sess.is_empty():
			sess.clear()
	return true


func _snapshot(label: String) -> Dictionary:
	var snap := {
		"label": label,
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS),
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),
		"mem_static": Performance.get_monitor(Performance.MEMORY_STATIC),
		"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_count": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"physics_2d_active": Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
		"physics_2d_pairs": Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS),
		"physics_2d_islands": Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT),
		"avatar_payloads": IDENTITIES._avatar_payload_cache.size(),
		"avatar_textures": IDENTITIES._avatar_texture_cache.size(),
		"car_payloads": IDENTITIES._car_payload_cache.size(),
		"car_textures": IDENTITIES._car_texture_cache.size(),
		"generated_drivers": _generated_driver_count(),
		"motion_gens": IDENTITIES.motion_image_generations,
		"audio_stream_players": _count_audio_stream_players(),
		"audio_director_children": _audio_director_child_count(),
		"gamestruments_children": _gamestruments_child_count(),
		"has_live_stream": _has_live_stream_child(),
		"app_signal_connections": _count_app_signal_connections(),
		"app_child_count": _app_child_count(),
		"spin_textures": _count_cached_spin_textures(),
		"outline_cache": TRACK_CORE._texture_outline_cache.size(),
		"footprint_cache": TRACK_CORE._texture_footprint_cache.size(),
		"engine_loop_cache": ENGINE_LOOP_GEN._cache.size(),
		"engine_voice_cache": ENGINE_VOICE_GEN._cache.size(),
		"race_session_keys": _race_session_size(),
		"quick_roster_size": _quick_roster_size(),
	}
	return snap


func _count_audio_stream_players() -> int:
	var count := 0
	var to_visit: Array[Node] = [root]
	while not to_visit.is_empty():
		var n: Node = to_visit.pop_back()
		var cls := n.get_class()
		if cls == "AudioStreamPlayer" or cls == "AudioStreamPlayer2D":
			count += 1
		to_visit.append_array(n.get_children())
	return count


func _audio_director_child_count() -> int:
	var app := root.get_node_or_null(APP_PATH)
	if app == null:
		return -1
	var director: Node = app.get("audio_director")
	if not is_instance_valid(director):
		return -1
	return director.get_child_count()


func _gamestruments_child_count() -> int:
	var app := root.get_node_or_null(APP_PATH)
	if app == null:
		return -1
	var director: Node = app.get("audio_director")
	if not is_instance_valid(director):
		return -1
	var gm := director.get_node_or_null("GamestrumentsPlayer")
	if not is_instance_valid(gm):
		return -1
	return gm.get_child_count()


func _has_live_stream_child() -> bool:
	var app := root.get_node_or_null(APP_PATH)
	if app == null:
		return false
	var director: Node = app.get("audio_director")
	if not is_instance_valid(director):
		return false
	var gm := director.get_node_or_null("GamestrumentsPlayer")
	if not is_instance_valid(gm):
		return false
	return gm.get_node_or_null("LiveStream") != null


func _count_app_signal_connections() -> int:
	var app := root.get_node_or_null(APP_PATH)
	if app == null:
		return -1
	var total := 0
	for sig_dict in app.get_signal_list():
		var sig_name: StringName = sig_dict.get("name", &"")
		if sig_name.is_empty():
			continue
		total += app.get_signal_connection_list(sig_name).size()
	return total


func _app_child_count() -> int:
	var app := root.get_node_or_null(APP_PATH)
	if app == null:
		return -1
	return app.get_child_count()


func _count_cached_spin_textures() -> int:
	var c := 0
	for k in IDENTITIES._car_spin_cache:
		var per: Variant = IDENTITIES._car_spin_cache[k]
		if per is Dictionary:
			for s in per:
				var arr: Variant = per[s]
				if arr is Array:
					for t: Variant in arr:
						if t != null:
							c += 1
	return c


func _race_session_size() -> int:
	var app := root.get_node_or_null(APP_PATH)
	if app == null:
		return -1
	var sess: Variant = app.get("current_race_session")
	return sess.size() if sess is Dictionary else 0


func _quick_roster_size() -> int:
	var app := root.get_node_or_null(APP_PATH)
	if app == null:
		return -1
	var qr: Variant = app.get("_quick_roster")
	return qr.size() if qr is Dictionary else 0


func _print_report() -> void:
	print("NATIVE_FREEZE_SNAPSHOTS start")
	for res in _race_results:
		var b: Dictionary = res["before"]
		var a: Dictionary = res["after"]
		print("RACE %d BEFORE %s" % [res["race"], str(b)])
		print("RACE %d AFTER  %s" % [res["race"], str(a)])
		print("RACE %d DELTA fps=%.1f process_ms=%.4f draw=%d objs_in_frame=%d prim=%d objects=%d nodes=%d orphans=%d mem=%.0f pairs=%d active=%d audio_pl=%d adir_ch=%d gm_ch=%d live=%s app_conns=%d app_ch=%d spins=%d outline=%d footprint=%d eng_loop=%d eng_vox=%d sess=%d qroster=%d" % [
			res["race"],
			float(a["fps"]) - float(b["fps"]),
			float(a["process_ms"]) - float(b["process_ms"]),
			int(a["draw_calls"]) - int(b["draw_calls"]),
			int(a["objects_in_frame"]) - int(b["objects_in_frame"]),
			int(a["primitives"]) - int(b["primitives"]),
			int(a["object_count"]) - int(b["object_count"]),
			int(a["node_count"]) - int(b["node_count"]),
			int(a["orphan_count"]) - int(b["orphan_count"]),
			float(a["mem_static"]) - float(b["mem_static"]),
			int(a["physics_2d_pairs"]) - int(b["physics_2d_pairs"]),
			int(a["physics_2d_active"]) - int(b["physics_2d_active"]),
			int(a["audio_stream_players"]) - int(b["audio_stream_players"]),
			int(a["audio_director_children"]) - int(b["audio_director_children"]),
			int(a["gamestruments_children"]) - int(b["gamestruments_children"]),
			str(a["has_live_stream"]) + "/" + str(b["has_live_stream"]),
			int(a["app_signal_connections"]) - int(b["app_signal_connections"]),
			int(a["app_child_count"]) - int(b["app_child_count"]),
			int(a["spin_textures"]) - int(b["spin_textures"]),
			int(a["outline_cache"]) - int(b["outline_cache"]),
			int(a["footprint_cache"]) - int(b["footprint_cache"]),
			int(a["engine_loop_cache"]) - int(b["engine_loop_cache"]),
			int(a["engine_voice_cache"]) - int(b["engine_voice_cache"]),
			int(a["race_session_keys"]) - int(b["race_session_keys"]),
			int(a["quick_roster_size"]) - int(b["quick_roster_size"]),
		])
		if res.has("drive"):
			var d: Dictionary = res["drive"]
			print("RACE %d DRIVE physics_avg=%.4f physics_max=%.4f process_avg=%.4f process_max=%.4f fps_avg=%.1f fps_min=%.1f pairs_max=%d active_max=%d samples=%d route=%.1f surfaces=%d colliders=%d" % [
				res["race"],
				float(d.get("physics_avg", 0.0)),
				float(d.get("physics_max", 0.0)),
				float(d.get("process_avg", 0.0)),
				float(d.get("process_max", 0.0)),
				float(d.get("fps_avg", 0.0)),
				float(d.get("fps_min", 0.0)),
				int(d.get("collision_pairs_max", 0)),
				int(d.get("physics_2d_active_max", 0)),
				int(d.get("samples", 0)),
				float(d.get("route_length", 0.0)),
				int(d.get("surface_zones", 0)),
				int(d.get("collider_count", 0)),
			])
	print("NATIVE_FREEZE_SNAPSHOTS end")


func _count_static_colliders() -> int:
	# Count StaticBody2D that carry collision shapes (the dense decor after boundary/obstacle work).
	var count: int = 0
	var to_visit: Array[Node] = [root]
	while not to_visit.is_empty():
		var n: Node = to_visit.pop_back()
		if n is StaticBody2D:
			var has_shape: bool = false
			for c: Node in n.get_children():
				if c is CollisionShape2D or c is CollisionPolygon2D:
					has_shape = true
					break
			if has_shape:
				count += 1
		to_visit.append_array(n.get_children())
	return count


## Roster identities are a later subsystem; this measurement must run without them.
func _generated_driver_count() -> int:
	if not ResourceLoader.exists("res://scripts/progression/driver_directory.gd"):
		return 0
	var script := load("res://scripts/progression/driver_directory.gd")
	if script == null or not script.has_method("installed_ids"):
		return 0
	return int((script as Object).call("installed_ids").size())


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("PROGRESSIVE_FREEZE_NATIVE_HARNESS FAIL: " + message)
	quit(1)
	return false
