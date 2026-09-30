extends SceneTree

## Native rendered + live audio progressive freeze harness.
## Run under: xvfb-run -a --server-args="-screen 0 640x480x24" \
##   /usr/bin/godot --path . --rendering-method gl_compatibility \
##   --resolution 640x480 --script res://tests/progressive_freeze_native_harness.gd
## (Deliberately omits --audio-driver Dummy and --headless so Gamestruments live
## audio and real renderer run; this is the only way to reproduce the user freeze.)
##
## Drives 4 quick races (enough to see per-race growth), records per-race:
##   frame time (last process), fps, draw calls, objects_in_frame, primitives,
##   static mem, object/node/orphan counts,
##   plus audio-side: audio_stream_player count, AudioDirector child count,
##   GamestrumentsPlayer child count, LiveStream presence, connected signals on App.
## Prints full snapshots and deltas so growth can be named by counting instances.

const APP_PATH := "/root/App"
const RACE_SCENE := "res://scenes/race/prototype_race.tscn"
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const DRIVER_DIRECTORY := preload("res://scripts/progression/driver_directory.gd")
const AUDIO_DIRECTOR_SCRIPT := preload("res://scripts/audio/audio_director.gd")
const TRACK_CORE := preload("res://scripts/race/track_builder_core.gd")
const ENGINE_LOOP_GEN := preload("res://scripts/audio/engine/engine_loop_generator.gd")
const ENGINE_VOICE_GEN := preload("res://scripts/audio/engine/engine_voice_generator.gd")

const NUM_RACES := 4
const BASE_SEED := 424242

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

	_race_results.clear()
	for r in NUM_RACES:
		var seed := BASE_SEED + r * 1000
		var before := _snapshot("before_race_%d" % r)
		if not await _run_one_quick_race(app, seed):
			return
		# Let a couple rendered frames so Performance and audio children settle
		await process_frame
		await process_frame
		var after := _snapshot("after_race_%d" % r)
		_race_results.append({
			"race": r,
			"before": before,
			"after": after,
		})
		await _ensure_back_in_boot(app)

	_print_report()

	# For native harness we do not assert (gate runs are headless only); we only
	# measure and name what grows. The progressive_freeze_harness.gd is extended
	# separately to regress the bounded-object part.
	print("PROGRESSIVE_FREEZE_NATIVE_HARNESS PASS races=%d" % NUM_RACES)
	quit(0)


func _run_one_quick_race(app: Node, seed: int) -> bool:
	var ok: bool = app.call("start_circuit_race", &"kitchen", &"classic", seed, "rustbug")
	if not _expect(ok, "start_circuit_race must succeed for seed %d" % seed):
		return false

	var deadline := Time.get_ticks_msec() + 30000
	while app.call("is_race_loading") and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _expect(not app.call("is_race_loading"), "loading must complete for seed %d"):
		return false
	if app.get("_loading_failed"):
		_expect(false, "loading must not fail")
		return false

	var race := current_scene
	if not _expect(race != null and race.scene_file_path == RACE_SCENE, "must be in race scene"):
		return false

	# Touch identity for opponents (same as headless harness)
	var ev: Dictionary = app.call("get_current_race_session").get("event", {})
	var oids: Array = ev.get("opponents", []) if not ev.is_empty() else []
	for did_v in oids:
		var did := String(did_v)
		if not did.is_empty():
			var _p := IDENTITIES.avatar_payload(did)
			var _t := IDENTITIES.avatar_texture(did)

	# Force result immediately (exercises full post-load + audio paths)
	var fake_results: Array = [
		{"position": 1, "driver_name": "Rae", "vehicle_name": "Rustbug", "time": 45.0, "finished": true, "dnf": false},
		{"position": 2, "driver_name": "Opp1", "vehicle_name": "Pinbolt", "time": 46.0, "finished": true, "dnf": false},
		{"position": 3, "driver_name": "Opp2", "vehicle_name": "Scrapjaw", "time": 47.0, "finished": true, "dnf": false},
		{"position": 4, "driver_name": "Opp3", "vehicle_name": "Flicker", "time": 48.0, "finished": true, "dnf": false},
	]
	var committed: bool = app.call("report_race_result", 1, 45.0, fake_results, false, {})
	if not _expect(committed, "report must succeed for quick race"):
		return false

	await process_frame

	app.call("continue_after_race", true)

	deadline = Time.get_ticks_msec() + 10000
	while current_scene != null and current_scene.scene_file_path == RACE_SCENE and Time.get_ticks_msec() < deadline:
		await process_frame
	await process_frame
	await process_frame

	return true


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
		"avatar_payloads": IDENTITIES._avatar_payload_cache.size(),
		"avatar_textures": IDENTITIES._avatar_texture_cache.size(),
		"car_payloads": IDENTITIES._car_payload_cache.size(),
		"car_textures": IDENTITIES._car_texture_cache.size(),
		"generated_drivers": DRIVER_DIRECTORY.installed_ids().size(),
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
	var sess: Dictionary = app.get("current_race_session")
	return sess.size() if sess is Dictionary else 0


func _quick_roster_size() -> int:
	var app := root.get_node_or_null(APP_PATH)
	if app == null:
		return -1
	var qr: Dictionary = app.get("_quick_roster")
	return qr.size() if qr is Dictionary else 0


func _print_report() -> void:
	print("NATIVE_FREEZE_SNAPSHOTS start")
	for res in _race_results:
		var b: Dictionary = res["before"]
		var a: Dictionary = res["after"]
		print("RACE %d BEFORE %s" % [res["race"], str(b)])
		print("RACE %d AFTER  %s" % [res["race"], str(a)])
		print("RACE %d DELTA fps=%.1f process_ms=%.4f draw=%d objs_in_frame=%d prim=%d objects=%d nodes=%d orphans=%d mem=%.0f audio_pl=%d adir_ch=%d gm_ch=%d live=%s app_conns=%d app_ch=%d spins=%d outline=%d footprint=%d eng_loop=%d eng_vox=%d sess=%d qroster=%d" % [
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
	print("NATIVE_FREEZE_SNAPSHOTS end")


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("PROGRESSIVE_FREEZE_NATIVE_HARNESS FAIL: " + message)
	quit(1)
	return false
