extends SceneTree

const APP_PATH := "/root/App"
const RACE_SCENE := "res://scenes/race/prototype_race.tscn"
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")

const NUM_RACES := 12
const BASE_SEED := 424242

var _race_results: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 1.0  # keep deterministic for loading; we shortcut results

	var app := root.get_node_or_null(APP_PATH)
	if not _expect(app != null, "App autoload must exist"):
		return

	# Ensure we start from boot with clean session
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
		var after := _snapshot("after_race_%d" % r)
		_race_results.append({
			"race": r,
			"before": before,
			"after": after,
		})
		# Return to stable boot state
		await _ensure_back_in_boot(app)

	_print_report()
	# A quick race mints three fresh opponents, so without eviction these caches
	# grow by three entries every race and a session accumulates portrait and
	# livery textures without limit. They must stay bounded once the caps are reached.
	var last: Dictionary = _race_results[_race_results.size() - 1]["after"]
	if not _expect(int(last["avatar_payloads"]) <= IDENTITIES.MAX_AVATAR_ENTRIES and int(last["avatar_textures"]) <= IDENTITIES.MAX_AVATAR_ENTRIES, "avatar caches must stay bounded across %d races, saw payloads=%d textures=%d (cap %d)" % [NUM_RACES, int(last["avatar_payloads"]), int(last["avatar_textures"]), IDENTITIES.MAX_AVATAR_ENTRIES]):
		return
	if not _expect(int(last["car_payloads"]) <= IDENTITIES.MAX_CAR_ENTRIES and int(last["car_textures"]) <= IDENTITIES.MAX_CAR_ENTRIES and int(last["car_spins"]) <= IDENTITIES.MAX_CAR_ENTRIES and int(last["visual_resolutions"]) <= IDENTITIES.MAX_CAR_ENTRIES, "car caches must stay bounded across %d races, saw payloads=%d textures=%d spins=%d resolutions=%d (cap %d)" % [NUM_RACES, int(last["car_payloads"]), int(last["car_textures"]), int(last["car_spins"]), int(last["visual_resolutions"]), IDENTITIES.MAX_CAR_ENTRIES]):
		return
	# Nodes and orphans must not drift either: the growth above was pure cache state.
	var nodes := int(last["node_count"])
	var orphans := int(last["orphan_count"])
	if not _expect(orphans == 0 and nodes <= 80, "a raced session must not leak nodes or orphans (nodes=%d orphans=%d)" % [nodes, orphans]):
		return
	print("PROGRESSIVE_FREEZE_HARNESS PASS races=%d" % NUM_RACES)
	quit(0)


func _run_one_quick_race(app: Node, seed: int) -> bool:
	# Use quick race path to force fresh op-<seed>-NN roster each time
	var ok: bool = app.call("start_circuit_race", &"kitchen", &"classic", seed, "rustbug")
	if not _expect(ok, "start_circuit_race must succeed for seed %d" % seed):
		return false

	var deadline := Time.get_ticks_msec() + 30000
	while app.call("is_race_loading") and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _expect(not app.call("is_race_loading"), "loading must complete for seed %d"):
		return false
	if app.get("_loading_failed"):
		if not _expect(false, "loading must not fail"):
			return false

	# Race scene is now current; ensure visuals and roster installed
	var race := current_scene
	if not _expect(race != null and race.scene_file_path == RACE_SCENE, "must be in race scene"):
		return false

	# Touch avatar caches for the generated opponents too (covers full identity leak path)
	var ev: Dictionary = app.call("get_current_race_session").get("event", {})
	var oids: Array = ev.get("opponents", []) if not ev.is_empty() else []
	for did_v in oids:
		var did := String(did_v)
		if not did.is_empty():
			var _p := IDENTITIES.avatar_payload(did)
			var _t := IDENTITIES.avatar_texture(did)

	# Force a result immediately (quick races accept it); this exercises full post-load paths
	var fake_results: Array = [
		{"position": 1, "driver_name": "Rae", "vehicle_name": "Rustbug", "time": 45.0, "finished": true, "dnf": false},
		{"position": 2, "driver_name": "Opp1", "vehicle_name": "Pinbolt", "time": 46.0, "finished": true, "dnf": false},
		{"position": 3, "driver_name": "Opp2", "vehicle_name": "Scrapjaw", "time": 47.0, "finished": true, "dnf": false},
		{"position": 4, "driver_name": "Opp3", "vehicle_name": "Flicker", "time": 48.0, "finished": true, "dnf": false},
	]
	var committed: bool = app.call("report_race_result", 1, 45.0, fake_results, false, {})
	if not _expect(committed, "report must succeed for quick race"):
		return false

	# Let one frame for any deferred
	await process_frame

	# Return via continue (exercises the boot sync path)
	app.call("continue_after_race", true)

	# Wait for scene switch back
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
	# Clear any lingering quick state the way boot sync does
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
		# Cache sizes (access via preload; _ vars are readable by convention in tests)
		"avatar_payloads": IDENTITIES._avatar_payload_cache.size(),
		"avatar_textures": IDENTITIES._avatar_texture_cache.size(),
		"car_payloads": IDENTITIES._car_payload_cache.size(),
		"car_textures": IDENTITIES._car_texture_cache.size(),
		"car_spins": IDENTITIES._car_spin_cache.size(),
		"visual_resolutions": IDENTITIES._visual_resolutions.size(),
		"generated_drivers": _generated_driver_count(),
		"motion_gens": IDENTITIES.motion_image_generations,
	}
	return snap


func _print_report() -> void:
	print("PROGRESSIVE_SNAPSHOTS start")
	for res in _race_results:
		var b: Dictionary = res["before"]
		var a: Dictionary = res["after"]
		print("RACE %d BEFORE %s" % [res["race"], str(b)])
		print("RACE %d AFTER  %s" % [res["race"], str(a)])
		# deltas for quick visual
		print("RACE %d DELTA avatar_payloads=%d avatar_tex=%d visual=%d objects=%d orphans=%d nodes=%d mem=%d" % [
			res["race"],
			int(a["avatar_payloads"]) - int(b["avatar_payloads"]),
			int(a["avatar_textures"]) - int(b["avatar_textures"]),
			int(a["visual_resolutions"]) - int(b["visual_resolutions"]),
			int(a["object_count"]) - int(b["object_count"]),
			int(a["orphan_count"]) - int(b["orphan_count"]),
			int(a["node_count"]) - int(b["node_count"]),
			int(a["mem_static"]) - int(b["mem_static"]),
		])
	print("PROGRESSIVE_SNAPSHOTS end")


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
	push_error("PROGRESSIVE_FREEZE_HARNESS FAIL: " + message)
	quit(1)
	return false
