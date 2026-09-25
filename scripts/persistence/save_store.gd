class_name SaveStore
extends RefCounted

const CURRENT_VERSION := 4
const DEFAULT_PATH := "user://pocket_circuit_save.json"
const VALID_DIFFICULTIES := ["sunday_drive", "club_circuit", "clockwork"]
const CATALOG := preload("res://data/championship/catalog.gd")
const CIRCUIT_IDENTITIES := preload("res://scripts/progression/championship_circuit_identity.gd")
const MASTERY := preload("res://scripts/progression/mastery_run.gd")
const PERSONAL_GHOST := preload("res://scripts/race/personal_ghost.gd")
const CIRCUIT_LIBRARY := preload("res://scripts/persistence/circuit_library.gd")

var save_path: String
var last_load_error: String = ""
var last_save_error: String = ""
var is_read_only := false


func _init(injected_path: String = DEFAULT_PATH) -> void:
	save_path = injected_path


func default_data() -> Dictionary:
	return {
		"version": CURRENT_VERSION,
		"championship_started": false,
		"championship_circuit": CIRCUIT_IDENTITIES.create_championship(CIRCUIT_IDENTITIES.LEGACY_MIGRATION_SEED),
		"best_event_finishes": {},
		"best_event_points": {},
		"completed_events": [],
		"completed_acts": [],
		"unlocked_vehicles": ["rustbug"],
		"selected_vehicle": "rustbug",
		"mastery_circuit_metrics": {},
		"mastery_records": [],
		"personal_ghosts": [],
		"circuit_history": [],
		"favorite_circuits": [],
		"ending_seen": false,
		"difficulty": "club_circuit",
		"master_volume": 1.0,
		"music_volume": 0.8,
		"sfx_volume": 0.9,
		"engine_volume": 0.9,
		"tyre_volume": 0.9,
		"fullscreen": false,
		"reduced_camera_shake": false,
		"reduced_motion": false,
		"first_run": true,
	}


func load_data() -> Dictionary:
	last_load_error = ""
	is_read_only = false
	var primary := _read_candidate(save_path)
	if String(primary["status"]) == "ok":
		return primary["data"] as Dictionary
	if String(primary["status"]) == "future":
		return _future_version_defaults(int(primary["version"]), "primary")

	var backup_path := save_path + ".bak"
	var backup := _read_candidate(backup_path)
	if String(backup["status"]) == "ok":
		last_load_error = "%s; recovered validated backup" % String(primary["diagnostic"])
		return backup["data"] as Dictionary
	if String(backup["status"]) == "future":
		return _future_version_defaults(int(backup["version"]), "backup")
	if String(primary["status"]) != "missing":
		last_load_error = "%s; no valid backup was available" % String(primary["diagnostic"])
	elif String(backup["status"]) != "missing":
		last_load_error = "%s; defaults restored" % String(backup["diagnostic"])
	return default_data()


func save_data(data: Dictionary) -> bool:
	last_save_error = ""
	if is_read_only:
		last_save_error = "Saving is disabled because this file was created by a newer Pocket Circuit version"
		return false
	var normalized := _canonicalize_for_disk(data)
	if normalized.is_empty():
		last_save_error = "Temporary save failed validation"
		return false
	var base_dir := save_path.get_base_dir()
	if not base_dir.is_empty():
		var directory_error := DirAccess.make_dir_recursive_absolute(_absolute_path(base_dir))
		if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
			last_save_error = "Could not create save directory: %s" % error_string(directory_error)
			return false

	var temp_path := save_path + ".tmp"
	_remove_if_present(temp_path)
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		last_save_error = "Could not open temporary save: %s" % error_string(FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(normalized, "\t"))
	file.flush()
	file.close()
	var temp_candidate := _read_candidate(temp_path)
	if String(temp_candidate["status"]) != "ok" or temp_candidate["data"] != normalized:
		last_save_error = "Temporary save failed validation"
		_remove_if_present(temp_path)
		return false

	var temp_absolute := _absolute_path(temp_path)
	var save_absolute := _absolute_path(save_path)
	var backup_path := save_path + ".bak"
	var backup_absolute := _absolute_path(backup_path)
	var primary_candidate := _read_candidate(save_path)
	if String(primary_candidate["status"]) == "ok":
		var backup_temp_path := backup_path + ".tmp"
		_remove_if_present(backup_temp_path)
		if not _copy_file(save_path, backup_temp_path):
			last_save_error = "Could not stage the previous save backup"
			_remove_if_present(temp_path)
			return false
		var staged_backup := _read_candidate(backup_temp_path)
		if String(staged_backup["status"]) != "ok" or staged_backup["data"] != primary_candidate["data"]:
			last_save_error = "Previous save backup failed validation"
			_remove_if_present(backup_temp_path)
			_remove_if_present(temp_path)
			return false
		_remove_if_present(backup_path)
		var backup_error := DirAccess.rename_absolute(_absolute_path(backup_temp_path), backup_absolute)
		if backup_error != OK:
			last_save_error = "Could not finalize save backup: %s" % error_string(backup_error)
			_remove_if_present(backup_temp_path)
			_remove_if_present(temp_path)
			return false

	_remove_if_present(save_path)
	var replace_error := DirAccess.rename_absolute(temp_absolute, save_absolute)
	if replace_error != OK:
		_restore_backup(backup_path)
		last_save_error = "Could not finalize save: %s" % error_string(replace_error)
		_remove_if_present(temp_path)
		return false
	var saved_candidate := _read_candidate(save_path)
	if String(saved_candidate["status"]) != "ok" or saved_candidate["data"] != normalized:
		_remove_if_present(save_path)
		_restore_backup(backup_path)
		last_save_error = "Replacement save failed validation"
		return false
	return true


func remove_save() -> void:
	_remove_if_present(save_path)
	_remove_if_present(save_path + ".tmp")
	_remove_if_present(save_path + ".bak")
	_remove_if_present(save_path + ".bak.tmp")
	is_read_only = false


func _canonicalize_for_disk(raw: Dictionary) -> Dictionary:
	var normalized := _normalize(raw)
	var parsed: Variant = JSON.parse_string(JSON.stringify(normalized))
	if parsed is not Dictionary:
		return {}
	return _normalize(parsed as Dictionary)


func _normalize(raw: Dictionary) -> Dictionary:
	var normalized := default_data()
	var raw_finishes: Dictionary = {}
	var supplied_finishes: Variant = raw.get("best_event_finishes")
	if supplied_finishes is Dictionary:
		raw_finishes = supplied_finishes as Dictionary
	var derived := _derive_progress(raw_finishes)
	for key: String in ["best_event_finishes", "best_event_points", "completed_events", "completed_acts", "unlocked_vehicles"]:
		normalized[key] = derived[key]
	normalized["ending_seen"] = (
		raw.get("ending_seen") is bool
		and bool(raw["ending_seen"])
		and "office" in (derived["completed_acts"] as Array)
	)
	normalized["mastery_circuit_metrics"] = MASTERY.normalize_circuit_metrics_map(raw.get("mastery_circuit_metrics"))
	normalized["mastery_records"] = MASTERY.normalize_records(raw.get("mastery_records"))
	normalized["personal_ghosts"] = PERSONAL_GHOST.normalize_ghosts(raw.get("personal_ghosts"))
	normalized["circuit_history"] = CIRCUIT_LIBRARY.normalize_history(raw.get("circuit_history"))
	normalized["favorite_circuits"] = CIRCUIT_LIBRARY.normalize_favorites(raw.get("favorite_circuits"))
	var started: Variant = raw.get("championship_started")
	normalized["championship_started"] = (started is bool and bool(started)) or not derived["completed_events"].is_empty()
	normalized["championship_circuit"] = CIRCUIT_IDENTITIES.normalize_championship(
		raw.get("championship_circuit"),
		CIRCUIT_IDENTITIES.LEGACY_MIGRATION_SEED
	)

	var unlocked: Array = normalized["unlocked_vehicles"]
	var selected: Variant = raw.get("selected_vehicle", "rustbug")
	normalized["selected_vehicle"] = str(selected) if selected is String and selected in unlocked else "rustbug"

	var difficulty: Variant = raw.get("difficulty", "club_circuit")
	if difficulty is String and difficulty in VALID_DIFFICULTIES:
		normalized["difficulty"] = difficulty
	normalized["master_volume"] = _bounded_float(raw.get("master_volume"), 0.0, 1.0, 1.0)
	normalized["music_volume"] = _bounded_float(raw.get("music_volume"), 0.0, 1.0, 0.8)
	normalized["sfx_volume"] = _bounded_float(raw.get("sfx_volume"), 0.0, 1.0, 0.9)
	var sfx_volume := float(normalized["sfx_volume"])
	normalized["engine_volume"] = _bounded_float(raw.get("engine_volume"), 0.0, 1.0, sfx_volume)
	normalized["tyre_volume"] = _bounded_float(raw.get("tyre_volume"), 0.0, 1.0, sfx_volume)
	for key: String in ["fullscreen", "reduced_camera_shake", "reduced_motion", "first_run"]:
		if raw.get(key) is bool:
			normalized[key] = raw[key]
	return normalized


func _derive_progress(raw_finishes: Dictionary) -> Dictionary:
	var progress := {
		"best_event_finishes": {},
		"best_event_points": {},
		"completed_events": [],
		"completed_acts": [],
		"unlocked_vehicles": ["rustbug"],
		"ending_seen": false,
	}
	for event: Dictionary in CATALOG.EVENTS:
		var event_id := String(event["id"])
		var racer_count := clampi((event.get("opponents", []) as Array).size() + 1, 1, 4)
		var finish := _bounded_int(raw_finishes.get(event_id), 1, racer_count, 0)
		if finish == 0 or not CATALOG.is_event_unlocked(event_id, progress):
			continue
		progress = CATALOG.apply_event_result(progress, event_id, finish)["save"]
	return progress


func _read_candidate(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"status": "missing", "diagnostic": "Save file is missing"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"status": "invalid",
			"diagnostic": "Could not open %s: %s" % [path, error_string(FileAccess.get_open_error())],
		}
	var json_text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var parse_error := json.parse(json_text)
	if parse_error != OK or json.data is not Dictionary:
		return {"status": "invalid", "diagnostic": "Malformed save at %s" % path}
	var raw := json.data as Dictionary
	var raw_version: Variant = raw.get("version", 1)
	if raw_version is int or raw_version is float:
		var version := int(raw_version)
		if version > CURRENT_VERSION:
			return {"status": "future", "version": version, "diagnostic": "Unsupported save version %d" % version}
	return {"status": "ok", "data": _normalize(raw)}


func _future_version_defaults(version: int, source: String) -> Dictionary:
	is_read_only = true
	last_load_error = "Unsupported future save version %d in %s; save was left unchanged" % [version, source]
	var fallback := default_data()
	fallback["first_run"] = false
	return fallback


func _copy_file(source_path: String, destination_path: String) -> bool:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return false
	var contents := source.get_as_text()
	source.close()
	var destination := FileAccess.open(destination_path, FileAccess.WRITE)
	if destination == null:
		return false
	destination.store_string(contents)
	destination.flush()
	destination.close()
	return true


func _restore_backup(backup_path: String) -> void:
	var backup := _read_candidate(backup_path)
	if String(backup["status"]) == "ok":
		_copy_file(backup_path, save_path)


func _valid_string_array(value: Variant, allowed: Array) -> Array:
	var output: Array = []
	if value is not Array:
		return output
	for item: Variant in value:
		if item is String and item in allowed and not item in output:
			output.append(item)
	return output


func _bounded_int(value: Variant, minimum: int, maximum: int, fallback: int) -> int:
	if value is not int and value is not float:
		return fallback
	var integer := int(value)
	return integer if integer >= minimum and integer <= maximum else fallback


func _bounded_float(value: Variant, minimum: float, maximum: float, fallback: float) -> float:
	if value is not int and value is not float:
		return fallback
	return clampf(float(value), minimum, maximum)


func _absolute_path(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path


func _remove_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(_absolute_path(path))
