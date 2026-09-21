extends SceneTree

const IDENTITIES := preload("res://scripts/race/generated_circuit_identity.gd")
const LIBRARY := preload("res://scripts/persistence/circuit_library.gd")
const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const TEST_PATH := "user://tests/pocket_circuit_library_test.json"


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var history: Array = []
	for seed in LIBRARY.HISTORY_LIMIT + 5:
		history = LIBRARY.add_recent(history, _identity(seed))
	if not _expect(history.size() == LIBRARY.HISTORY_LIMIT and int(history[0]["sub_seeds"]["route"]) == LIBRARY.HISTORY_LIMIT + 4, "history should be newest-first and explicitly bounded"):
		return
	var repeated := _identity(8)
	history = LIBRARY.add_recent(history, repeated)
	if not _expect(history.size() == LIBRARY.HISTORY_LIMIT and history[0] == repeated and _fingerprint_count(history, String(repeated["fingerprint"])) == 1, "revisiting a circuit should move one fingerprint-deduplicated entry to the front"):
		return

	var favorites: Array = []
	for seed in LIBRARY.FAVORITES_LIMIT + 4:
		favorites = LIBRARY.add_favorite(favorites, _identity(seed))
	if not _expect(favorites.size() == LIBRARY.FAVORITES_LIMIT, "favorites should have an independent explicit bound"):
		return
	var history_before_remove := history.duplicate(true)
	favorites = LIBRARY.remove_favorite(favorites, String(favorites[0]["fingerprint"]))
	if not _expect(favorites.size() == LIBRARY.FAVORITES_LIMIT - 1 and history == history_before_remove, "removing a favorite must not erase or reorder history"):
		return

	var alias_source := _identity(99)
	var copied := LIBRARY.add_recent([], alias_source)
	alias_source["sub_seeds"]["route"] = 1
	if not _expect(int(copied[0]["sub_seeds"]["route"]) == 99, "library writes should deep-copy nested circuit identity"):
		return
	var normalized := LIBRARY.normalize_history([_identity(2), _identity(2), {"fingerprint": "forged"}, "bad"])
	if not _expect(normalized.size() == 1 and normalized[0] == _identity(2), "normalization should reject malformed entries and deduplicate valid fingerprints"):
		return
	var v8_identity := IDENTITIES.create_v8(&"office", IDENTITIES.room_for_route_seed(2026), 2026, false, 3, "", "", {}, "endurance")
	var mixed_result := LIBRARY.normalize_history_result([repeated, v8_identity, repeated])
	if not _expect(bool(mixed_result.get("ok", false)) and mixed_result["entries"] == [repeated, v8_identity], "mixed v7/v8 library records should retain both canonical identities without migration"):
		return
	var unsupported := repeated.duplicate(true)
	unsupported["generator_version"] = 6
	var unsupported_result := LIBRARY.normalize_history_result([repeated, unsupported])
	if not _expect(unsupported_result.get("kind") == "unsupported_generator" and String(unsupported_result.get("error", "")).contains("version 6"), "a versioned unsupported library entry should fail explicitly instead of being silently dropped"):
		return

	var store := SAVE_STORE.new(TEST_PATH) as SaveStore
	store.remove_save()
	_write_raw(JSON.stringify({"version": 3, "difficulty": "clockwork", "circuit_history": [repeated, repeated], "favorite_circuits": [repeated]}))
	var migrated := store.load_data()
	if not _expect(
		int(migrated["version"]) == 4
		and migrated["circuit_history"].size() == 1
		and migrated["favorite_circuits"].size() == 1
		and String(migrated["circuit_history"][0]["fingerprint"]) == String(repeated["fingerprint"])
		and String(migrated["favorite_circuits"][0]["fingerprint"]) == String(repeated["fingerprint"]),
		"v3 saves should migrate valid discovery data to bounded canonical v4 records"
	):
		return
	if not _expect(store.save_data(migrated), "migrated discovery data should persist: %s" % store.last_save_error):
		return
	var restarted := SAVE_STORE.new(TEST_PATH).load_data()
	if not _expect(restarted["circuit_history"] == migrated["circuit_history"] and restarted["favorite_circuits"] == migrated["favorite_circuits"], "history and favorites should survive save/restart exactly"):
		return
	restarted["circuit_history"][0]["sub_seeds"]["route"] = 0
	if not _expect(int(SAVE_STORE.new(TEST_PATH).load_data()["circuit_history"][0]["sub_seeds"]["route"]) == 8, "loaded discovery identities should not alias persisted nested data"):
		return
	store.remove_save()
	print("CIRCUIT_LIBRARY_TEST PASS")
	quit(0)


func _identity(seed: int) -> Dictionary:
	return IDENTITIES.create(&"kitchen", IDENTITIES.room_for_route_seed(seed), seed, seed % 2 == 1)


func _fingerprint_count(entries: Array, fingerprint: String) -> int:
	var count := 0
	for entry: Dictionary in entries:
		if String(entry["fingerprint"]) == fingerprint:
			count += 1
	return count


func _write_raw(text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://tests"))
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	if file:
		file.store_string(text)
		file.close()


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	SAVE_STORE.new(TEST_PATH).remove_save()
	push_error("CIRCUIT_LIBRARY_TEST FAIL: " + message)
	quit(1)
	return false
