extends SceneTree

const BOOT_SCENE := preload("res://scenes/boot/boot.tscn")
const RACE_SCENE := preload("res://scenes/race/prototype_race.tscn")
const IDENTITIES := preload("res://scripts/race/generated_circuit_identity.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload should be available"):
		return
	var boot := BOOT_SCENE.instantiate()
	root.add_child(boot)
	current_scene = boot
	await _wait_frames(3)
	var identity := IDENTITIES.create(&"kitchen", IDENTITIES.room_for_route_seed(31415), 31415, true, 1)
	var preview: Dictionary = await app.call("prepare_circuit_preview", identity)
	if not _expect(not preview.is_empty(), "runtime fixture should prepare a route preview"):
		return
	if not _expect(app.call("start_discovery_race", identity, "rustbug", String(preview["loaded_fingerprint"])), "a confirmed preview should begin discovery loading"):
		return
	var deadline := Time.get_ticks_msec() + 35000
	while app.call("is_race_loading") and Time.get_ticks_msec() < deadline:
		await process_frame
	var race := current_scene
	if not _expect(not app.call("is_race_loading") and race != null and race.scene_file_path == RACE_SCENE.resource_path, "discovery preparation should reach the loaded race within its deadline"):
		return
	var track := race.get("track_root") as Node2D
	var manager := race.get_node_or_null("RaceManager") as RaceManager
	if not _expect(track != null and String(track.get_meta("preview_fingerprint", "")) == String(preview["loaded_fingerprint"]), "the loaded race must verify and publish the exact confirmed preview fingerprint"):
		return
	if not _expect(String(track.get_meta("generated_circuit_fingerprint", "")) == String(identity["fingerprint"]) and manager != null and manager.is_reverse_direction(), "the loaded track identity and race direction must exactly match the imported code"):
		return
	root.remove_child(race)
	race.free()
	current_scene = null
	print("DISCOVERY_RACE_RUNTIME_TEST PASS")
	quit(0)


func _wait_frames(count: int) -> void:
	for _frame in count:
		await process_frame


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	paused = false
	push_error("DISCOVERY_RACE_RUNTIME_TEST FAIL: " + message)
	quit(1)
	return false