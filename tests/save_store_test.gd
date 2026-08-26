extends SceneTree

const SAVE_STORE_SCRIPT := preload("res://scripts/persistence/save_store.gd")
const TEST_PATH := "user://tests/pocket_circuit_save_store_test.json"


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var store := SAVE_STORE_SCRIPT.new(TEST_PATH) as SaveStore
	store.remove_save()
	var data := store.default_data()
	if not _expect(not bool(data["championship_started"]), "new saves should not start a championship implicitly"):
		return
	if not _expect(not bool(data["reduced_motion"]), "reduced motion should default off"):
		return
	data["championship_started"] = true
	data["best_event_finishes"] = {
		"kitchen_crumb_rush": 1,
		"kitchen_mug_run": 1,
		"kitchen_clean_line": 1,
	}
	data["best_event_points"] = {"kitchen_crumb_rush": 3}
	data["completed_events"] = ["office_last_light"]
	data["unlocked_vehicles"] = ["rustbug", "flicker", "pinbolt"]
	data["selected_vehicle"] = "pinbolt"
	data["difficulty"] = "clockwork"
	data["master_volume"] = 0.35
	data["reduced_camera_shake"] = true
	data["reduced_motion"] = true
	if not _expect(store.save_data(data), "round-trip fixture should save: %s" % store.last_save_error):
		return
	var loaded := store.load_data()
	if not _expect(loaded["best_event_points"] == {"kitchen_crumb_rush": 10, "kitchen_mug_run": 10, "kitchen_clean_line": 10}, "best points should be derived from legal finishes"):
		return
	if not _expect(loaded["completed_events"] == ["kitchen_crumb_rush", "kitchen_mug_run", "kitchen_clean_line"] and loaded["completed_acts"] == ["kitchen"], "completed events and acts should be derived sequentially"):
		return
	if not _expect(loaded["unlocked_vehicles"] == ["rustbug", "pinbolt"] and loaded["selected_vehicle"] == "pinbolt", "legal unlocks and selected vehicle should round-trip"):
		return
	if not _expect(loaded["difficulty"] == "clockwork" and is_equal_approx(float(loaded["master_volume"]), 0.35) and loaded["reduced_camera_shake"] and loaded["reduced_motion"], "settings should round-trip"):
		return

	var replacement := loaded.duplicate(true)
	replacement["difficulty"] = "sunday_drive"
	if not _expect(store.save_data(replacement), "replacement fixture should save: %s" % store.last_save_error):
		return
	if not _expect(FileAccess.file_exists(TEST_PATH + ".bak"), "a validated replacement should retain the previous save backup"):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	loaded = store.load_data()
	if not _expect(loaded["difficulty"] == "clockwork" and loaded["selected_vehicle"] == "pinbolt", "a missing primary should recover the validated backup"):
		return
	if not _expect(store.last_load_error.contains("backup"), "backup recovery should expose a diagnostic"):
		return

	_write_raw(TEST_PATH, "{ definitely not json")
	loaded = store.load_data()
	if not _expect(loaded["difficulty"] == "clockwork" and loaded["selected_vehicle"] == "pinbolt", "a malformed primary should recover the validated backup"):
		return

	_write_raw(TEST_PATH, '{"version":99,"championship_started":true,"best_event_finishes":{"kitchen_crumb_rush":1}}')
	loaded = store.load_data()
	if not _expect(loaded["best_event_finishes"].is_empty() and not bool(loaded["championship_started"]), "future versions should return safe defaults instead of loading an older backup"):
		return
	if not _expect(not bool(loaded["first_run"]) and store.last_load_error.contains("future save version 99"), "future-version rejection should be diagnostic and avoid automatic rewrite"):
		return
	if not _expect(int(_read_json(TEST_PATH)["version"]) == 99, "loading a future save must leave it unchanged"):
		return
	if not _expect(store.is_read_only, "a future save should make the store read-only for this process"):
		return
	if not _expect(not store.save_data(store.default_data()), "read-only mode must reject every replacement save"):
		return
	if not _expect(store.last_save_error.contains("newer Pocket Circuit version") and int(_read_json(TEST_PATH)["version"]) == 99, "a rejected write must explain and preserve the future save"):
		return

	_write_raw(TEST_PATH, '{"version":1,"championship_started":true,"best_event_finishes":{"office_last_light":1},"best_event_points":{"office_last_light":10},"completed_events":["office_last_light"],"completed_acts":["office"],"unlocked_vehicles":["rustbug","flicker"],"selected_vehicle":"flicker","ending_seen":true,"difficulty":"clockwork","master_volume":0.4,"reduced_camera_shake":true}')
	loaded = store.load_data()
	if not _expect(loaded["best_event_finishes"].is_empty() and loaded["best_event_points"].is_empty() and loaded["completed_events"].is_empty(), "results that bypass event gates should be discarded"):
		return
	if not _expect(loaded["completed_acts"].is_empty() and loaded["unlocked_vehicles"] == ["rustbug"] and not bool(loaded["ending_seen"]), "impossible cross-field combinations must not unlock acts, vehicles, or ending"):
		return
	if not _expect(loaded["selected_vehicle"] == "rustbug" and loaded["difficulty"] == "clockwork" and is_equal_approx(float(loaded["master_volume"]), 0.4) and loaded["reduced_camera_shake"], "valid settings should survive while an invalid selected vehicle falls back"):
		return

	_write_raw(TEST_PATH, '{"version":1,"best_event_finishes":{"kitchen_crumb_rush":2}}')
	loaded = store.load_data()
	if not _expect(loaded["completed_events"] == ["kitchen_crumb_rush"] and int(loaded["best_event_points"]["kitchen_crumb_rush"]) == 7, "older saves should derive current progress fields from finishes"):
		return
	if not _expect(bool(loaded["championship_started"]) and loaded.has("music_volume") and loaded.has("first_run") and not bool(loaded["reduced_motion"]), "older raced saves should merge the current reduced-motion default"):
		return

	store.remove_save()
	print("SAVE_STORE_TEST PASS")
	quit(0)


func _write_raw(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	SAVE_STORE_SCRIPT.new(TEST_PATH).remove_save()
	push_error("SAVE_STORE_TEST FAIL: " + message)
	quit(1)
	return false
