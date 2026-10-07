extends SceneTree

const CATALOG := preload("res://data/championship/catalog.gd")
const SAVE_STORE_SCRIPT := preload("res://scripts/persistence/save_store.gd")
const CIRCUIT_IDENTITIES := preload("res://scripts/progression/championship_circuit_identity.gd")
const MASTERY := preload("res://scripts/progression/mastery_run.gd")
const PERSONAL_GHOST := preload("res://scripts/race/personal_ghost.gd")
const TEST_PATH := "user://tests/pocket_circuit_save_store_test.json"


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var store := SAVE_STORE_SCRIPT.new(TEST_PATH) as SaveStore
	store.remove_save()
	var data := store.default_data()
	if not _expect(not bool(data["championship_started"]), "new saves should not start a championship implicitly"):
		return
	if not _expect(int(data["version"]) == int(SAVE_STORE_SCRIPT.CURRENT_VERSION) and int(data["championship_circuit"]["seed"]) == 665001 and data["championship_circuit"]["events"].size() == CATALOG.EVENTS.size() and (data["mastery_circuit_metrics"] as Dictionary).is_empty() and data["circuit_history"].is_empty() and data["favorite_circuits"].is_empty(), "new saves should carry complete circuit identity and empty mastery/discovery collections"):
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
	var mastery_event := CIRCUIT_IDENTITIES.apply_to_event(CATALOG.get_event("kitchen_crumb_rush"), data["championship_circuit"]["events"]["kitchen_crumb_rush"])
	var mastery_metrics := MASTERY.prepare_circuit_metrics(mastery_event)
	var mastery_context := MASTERY.create_context(mastery_event, "rustbug", mastery_metrics)
	var mastery_identity: Dictionary = mastery_context["identity"]
	data["mastery_circuit_metrics"] = {MASTERY.circuit_metrics_key_for_event(mastery_event): mastery_metrics}
	data["mastery_records"] = MASTERY.apply_result([], mastery_identity, mastery_context["targets"], 39.0, 82.0)["records"]
	data["personal_ghosts"] = PERSONAL_GHOST.store_best([], mastery_identity, 82.0, [
		PERSONAL_GHOST.sample(0.0, Transform2D(0.0, Vector2.ZERO)),
		PERSONAL_GHOST.sample(82.0, Transform2D(0.5, Vector2(20.0, 40.0))),
	])["ghosts"]
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
	if not _expect(loaded["championship_circuit"] == data["championship_circuit"], "championship circuit identities should round-trip without changing"):
		return
	if not _expect(loaded["mastery_circuit_metrics"] == data["mastery_circuit_metrics"] and loaded["mastery_records"] == data["mastery_records"], "derived circuit metrics and mastery records should round-trip"):
		return
	if not _expect((loaded["personal_ghosts"] as Array).size() == 1 and is_equal_approx(float(loaded["personal_ghosts"][0]["race_time"]), 82.0), "bounded ghost samples should survive save"):
		return
	var dense_samples: Array = []
	var sample_time := 0.0
	while sample_time <= 22.1:
		dense_samples.append(PERSONAL_GHOST.sample(sample_time, Transform2D(sample_time * 0.01, Vector2(sample_time * 10.0, sin(sample_time) * 5.0))))
		sample_time += 0.1
	data["personal_ghosts"] = PERSONAL_GHOST.store_best([], mastery_identity, 22.1, dense_samples)["ghosts"]
	if not _expect(store.save_data(data), "a full time-trial ghost should save: %s" % store.last_save_error):
		return
	loaded = store.load_data()
	if not _expect((loaded["personal_ghosts"] as Array).size() == 1 and (loaded["personal_ghosts"][0]["samples"] as Array).size() > 200, "a raced ghost must persist instead of failing validation"):
		return
	var reboot_metrics := MASTERY.metrics_for_event(loaded["mastery_circuit_metrics"], mastery_event)
	if not _expect(not reboot_metrics.is_empty() and not (MASTERY.create_context(mastery_event, "rustbug", reboot_metrics)["targets"] as Dictionary).is_empty(), "persisted metrics should make post-boot target lookup immediately ready without route preparation"):
		return
	loaded["personal_ghosts"][0]["samples"][0][1] = 999.0
	if not _expect(float(store.load_data()["personal_ghosts"][0]["samples"][0][1]) == 0.0, "loaded nested ghost data should not alias a later load"):
		return
	loaded = store.load_data()

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
	if not _expect(store.recovery_message == "Save recovered from backup", "backup recovery should set clean recovery message for title"):
		return

	_write_raw(TEST_PATH, "{ definitely not json")
	loaded = store.load_data()
	if not _expect(loaded["difficulty"] == "clockwork" and loaded["selected_vehicle"] == "pinbolt", "a malformed primary should recover the validated backup"):
		return

	var champion := store.default_data()
	champion["championship_started"] = true
	for event: Dictionary in CATALOG.EVENTS:
		champion = CATALOG.apply_event_result(champion, String(event["id"]), 1)["save"]
	if not _expect(CATALOG.is_ending_pending(champion) and store.save_data(champion), "a completed championship should save with its ending pending"):
		return
	loaded = store.load_data()
	if not _expect(CATALOG.is_ending_pending(loaded) and not bool(loaded["ending_seen"]), "loading a completed championship should retain its pending ending"):
		return
	champion["ending_seen"] = true
	if not _expect(store.save_data(champion), "an acknowledged championship ending should save"):
		return
	loaded = store.load_data()
	if not _expect(bool(loaded["ending_seen"]) and not CATALOG.is_ending_pending(loaded), "loading should retain a valid ending acknowledgment"):
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
	if not _expect(store.recovery_message == "Save is from a newer version (v99) — running read-only", "future version should set clean recovery message for title"):
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
	if not _expect(loaded["completed_events"] == ["kitchen_crumb_rush"] and int(loaded["best_event_points"].get("kitchen_crumb_rush", -1)) == 7, "older saves should derive current progress fields from finishes"):
		return
	if not _expect(bool(loaded["championship_started"]) and loaded.has("music_volume") and loaded.has("engine_volume") and loaded.has("tyre_volume") and loaded.has("first_run") and not bool(loaded["reduced_motion"]), "older raced saves should merge the current reduced-motion default"):
		return
	if not _expect(is_equal_approx(float(loaded["engine_volume"]), float(loaded["sfx_volume"])) and is_equal_approx(float(loaded["tyre_volume"]), float(loaded["sfx_volume"])), "saves without engine or tyre volume should start from the saved SFX level"):
		return
	var migrated_identity: Dictionary = loaded["championship_circuit"]
	if not _expect(int(loaded["version"]) == int(SAVE_STORE_SCRIPT.CURRENT_VERSION) and int(migrated_identity["seed"]) == 665001 and migrated_identity["events"].size() == CATALOG.EVENTS.size() and loaded["mastery_records"].is_empty() and loaded["personal_ghosts"].is_empty() and loaded["circuit_history"].is_empty() and loaded["favorite_circuits"].is_empty(), "version 1 saves should receive deterministic identity and empty mastery/discovery archives in memory"):
		return
	if not _expect(int(_read_json(TEST_PATH)["version"]) == 1, "loading a legacy save should not rewrite it before a validated save action"):
		return
	if not _expect(store.save_data(loaded), "a migrated save should persist safely: %s" % store.last_save_error):
		return
	var migrated_on_disk := _read_json(TEST_PATH)
	if not _expect(int(migrated_on_disk["version"]) == int(SAVE_STORE_SCRIPT.CURRENT_VERSION) and int(migrated_on_disk["best_event_finishes"]["kitchen_crumb_rush"]) == 2, "persisting migration should upgrade the schema without changing player progress"):
		return
	if not _expect(store.load_data()["championship_circuit"] == migrated_identity, "reloading a persisted migration should retain the exact generated identity"):
		return
	if not _test_legacy_vehicle_selections(store):
		return
	if not _test_generator_version_migration(store):
		return
	if not _test_current_run_migration(store):
		return

	store.remove_save()
	print("SAVE_STORE_TEST PASS")
	quit(0)


func _test_legacy_vehicle_selections(store: SaveStore) -> bool:
	var unlock_sequences := {
		"rustbug": [],
		"pinbolt": ["kitchen_crumb_rush", "kitchen_mug_run", "kitchen_clean_line"],
		"scrapjaw": [
			"kitchen_crumb_rush", "kitchen_mug_run", "kitchen_clean_line",
			"workshop_screw_loose", "workshop_ruler_drop", "workshop_heavy_metal",
		],
		"flicker": CATALOG.event_ids(),
	}
	for vehicle_id: String in unlock_sequences:
		var finishes := {}
		for event_id: String in unlock_sequences[vehicle_id]:
			finishes[event_id] = 1
		_write_raw(TEST_PATH, JSON.stringify({
			"version": 1,
			"best_event_finishes": finishes,
			"selected_vehicle": vehicle_id,
		}))
		var loaded := store.load_data()
		if not _expect(String(loaded["selected_vehicle"]) == vehicle_id, "legacy save should keep selected vehicle '%s' after catalog resource migration" % vehicle_id):
			return false
	return true


func _test_generator_version_migration(store: SaveStore) -> bool:
	# An older championship record keeps its master seed and story progress, but
	# its circuit fingerprints advance so old-geometry ghosts and mastery keys no
	# longer compare as the current circuit.
	_write_raw(TEST_PATH, JSON.stringify({
		"version": 4,
		"championship_started": true,
		"championship_circuit": {
			"schema_version": 1,
			"generator_version": 1,
			"seed": 123456789,
			"events": {},
			"fingerprint": "ba391b90f4c3f2b5",
		},
		"best_event_finishes": {
			"kitchen_crumb_rush": 1,
			"kitchen_mug_run": 1,
			"kitchen_clean_line": 1,
		},
	}))
	var loaded := store.load_data()
	var migrated: Dictionary = loaded["championship_circuit"]
	if not _expect(int(migrated["seed"]) == 123456789 and int(migrated["generator_version"]) == 12, "an older championship save should keep its master seed while advancing the generator version"):
		return false
	if not _expect(
			loaded["completed_events"] == ["kitchen_crumb_rush", "kitchen_mug_run", "kitchen_clean_line"]
			and loaded["completed_acts"] == ["kitchen"]
			and loaded["unlocked_vehicles"] == ["rustbug", "pinbolt"]
			and loaded["best_event_points"] == {"kitchen_crumb_rush": 10, "kitchen_mug_run": 10, "kitchen_clean_line": 10},
			"generator migration should preserve completed events, standings, and unlocks"
	):
		return false
	var migrated_event := CIRCUIT_IDENTITIES.apply_to_event(CATALOG.get_event("kitchen_crumb_rush"), migrated["events"]["kitchen_crumb_rush"])
	var migrated_identity := MASTERY.create_identity(migrated_event, "rustbug", MASTERY.prepare_circuit_metrics(migrated_event))
	var legacy_identity := migrated_identity.duplicate(true)
	legacy_identity["circuit"]["generator_version"] = 1
	if not _expect(MASTERY.identity_key(legacy_identity) != MASTERY.identity_key(migrated_identity), "the generator version bump should change the lap/mastery identity key"):
		return false
	var legacy_ghost: Array = PERSONAL_GHOST.store_best([], legacy_identity, 30.0, [
		PERSONAL_GHOST.sample(0.0, Transform2D(0.0, Vector2.ZERO)),
		PERSONAL_GHOST.sample(30.0, Transform2D(0.5, Vector2(10.0, 10.0))),
	])["ghosts"]
	if not _expect(legacy_ghost.size() == 1, "the migration fixture must contain an actual old-geometry ghost"):
		return false
	if not _expect(PERSONAL_GHOST.compatible_best(legacy_ghost, migrated_identity).is_empty(), "a ghost recorded under an older identity must not be accepted against the current circuit"):
		return false
	return true



func _test_current_run_migration(store: SaveStore) -> bool:
	# v4 legacy without current_run -> {} , progress untouched, disk not yet upgraded
	_write_raw(TEST_PATH, "{\"version\":4,\"best_event_finishes\":{\"kitchen_crumb_rush\":1},\"completed_events\":[\"kitchen_crumb_rush\"]}")
	var loaded := store.load_data()
	if not _expect(loaded.get("current_run") == {} and loaded["completed_events"] == ["kitchen_crumb_rush"], "old v4 normalises current_run to {} and leaves progress/records untouched"):
		return false
	if not _expect(int(_read_json(TEST_PATH)["version"]) == 4, "v4 load leaves disk at old version"):
		return false
	# persist migrates version to 5 and keeps current_run
	if not _expect(store.save_data(loaded), "save of migrated v4+current_run"):
		return false
	var on_disk := _read_json(TEST_PATH)
	if not _expect(int(on_disk["version"]) == 5 and on_disk.get("current_run") == {}, "save after v4 load writes v5 and current_run:{} "):
		return false

	# hand v5 with mid-run data persists and reloads
	var v5_with_run := store.default_data()
	v5_with_run["current_run"] = {
		"schema_version": 1,
		"run_seed": 424242,
		"run_points": 12,
		"run_budget": 33,
		"current_node_id": "1_3",
		"current_car_id": "rustbug",
		"owned_cars": {"rustbug": "compact"},
	}
	if not _expect(store.save_data(v5_with_run), "save v5 with current_run data"):
		return false
	loaded = store.load_data()
	if not _expect(int(loaded["version"]) == int(SAVE_STORE_SCRIPT.CURRENT_VERSION) and int(loaded["current_run"].get("run_seed",0)) == 424242 and int(loaded["current_run"].get("run_budget",0)) == 33, "v5 current_run data roundtrips via normalize"):
		return false

	# future v6 crafted save -> read only, defaults (current_run={}), disk untouched
	_write_raw(TEST_PATH, "{\"version\":6,\"current_run\":{\"run_seed\":999},\"best_event_finishes\":{\"kitchen_crumb_rush\":1}}")
	loaded = store.load_data()
	if not _expect(loaded["current_run"] == {} and loaded["best_event_finishes"].is_empty(), "v6 future yields safe defaults including empty current_run, no old data"):
		return false
	if not _expect(int(_read_json(TEST_PATH)["version"]) == 6 and store.is_read_only, "v6 must leave disk at 6 and set read-only"):
		return false
	if not _expect(not store.save_data(store.default_data()), "read-only rejects write on v6"):
		return false
	if not _expect(int(_read_json(TEST_PATH)["version"]) == 6, "rejected write leaves v6 untouched"):
		return false
	return true

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
