extends SceneTree

## Regression for GURI-1343 (Fix progressive freeze across races and audit
## performance patterns): the AI used to run a full polygon test against every
## surface zone, per probe distance, per AI, per tick — a per-frame cost that
## scaled with the field and the track's zone count. The per-race bounding-circle
## broad phase rejects far zones before the polygon test, so the same drive
## window's SurfaceZone.contains_global_point count collapses. This test drives a
## fixed four-AI field for a fixed number of physics frames and asserts the
## surface probe count stays far below the pre-broad-phase rate.

const PROTOTYPE_SCENE := preload("res://scenes/race/prototype_race.tscn")
const AI_CONTROLLER_SCRIPT := preload("res://scripts/vehicle/ai_vehicle_controller.gd")
const CATALOG := preload("res://data/championship/catalog.gd")

const THEME := &"kitchen"
const ROOM := &"classic"
const SEED := 424242
const DIFFICULTY := "club_circuit"
const DRIVE_FRAMES := 600
## The unphased scan produced ~75 probes per physics frame on this field; the
## broad phase drops that to single digits. A generous 20,000 ceiling keeps
## determinism noise irrelevant while still failing the old behaviour (~45,000).
const MAX_PROBES := 20000


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 4.0
	var prototype := PROTOTYPE_SCENE.instantiate()
	prototype.set("_session", {
		"event": {
			"theme": THEME,
			"circuit": "generated",
			"room": ROOM,
			"seed": SEED,
			"reverse": false,
			"laps": 3,
			"length_tier": "standard",
			"opponents": ["juniper", "milo", "tess"],
			"opponent_count": 3,
		},
		"difficulty": DIFFICULTY,
		"vehicle_id": "rustbug",
	})
	var manager := prototype.get_node("RaceManager") as RaceManager
	manager.finish_grace_seconds = 8.0
	root.add_child(prototype)
	current_scene = prototype
	var player := get_first_node_in_group("player_vehicle") as VehicleController
	if not _expect(player != null, "player vehicle should be created"):
		return
	# Drive the player too, so the field is a full four-AI sweep like the seed
	# sweep and the probe cost is representative.
	var driver := CATALOG.get_driver("cass")
	var player_controller := AI_CONTROLLER_SCRIPT.new() as AIVehicleController
	player.add_child(player_controller)
	player_controller.configure(player, manager, -10.0, DIFFICULTY, "cass", driver.get("ai_style", {}) as Dictionary)
	# Deterministic settle to the start line (matches the seed sweep's 36 frames).
	for _settle in 36:
		await physics_frame
	paused = false
	var startup_waits := 0
	while not manager.is_running and startup_waits < 180:
		await physics_frame
		startup_waits += 1
	if not _expect(manager.is_running, "countdown should finish"):
		return
	var base_probes := int(AI_CONTROLLER_SCRIPT.surface_zone_probe_count)
	for _frame in DRIVE_FRAMES:
		await physics_frame
	var probe_delta := int(AI_CONTROLLER_SCRIPT.surface_zone_probe_count) - base_probes
	print("SURFACE_PROBE_REGRESSION probes=%d frames=%d" % [probe_delta, DRIVE_FRAMES])
	if not _expect(probe_delta < MAX_PROBES, "surface probes over %d frames should stay below %d (got %d)" % [DRIVE_FRAMES, MAX_PROBES, probe_delta]):
		return
	current_scene = null
	root.remove_child(prototype)
	prototype.free()
	await process_frame
	await physics_frame
	print("SURFACE_PROBE_REGRESSION_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	Engine.time_scale = 1.0
	push_error("SURFACE_PROBE_REGRESSION_TEST FAIL: " + message)
	quit(1)
	return false
