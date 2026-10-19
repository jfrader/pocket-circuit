extends RefCounted
## Disk front for the builder's data-only prepared layouts, never packed scenes.

# Bump when generation rules, authored content or the engine's Variant format change.
const CONTENT_VERSION := 1
const DIRECTORY := "user://circuit_cache"
const MAX_ENTRIES := 32
const MAX_BYTES := 64 * 1024 * 1024
const MAX_ENTRY_BYTES := 8 * 1024 * 1024
const MAGIC := 0x50434348
const HEADER_BYTES := 56
const STALE_TEMP_SECONDS := 60.0
static var enabled := true
static var directory := DIRECTORY
static var hits := 0
static var misses := 0
static var _mutex := Mutex.new()


static func key(theme: StringName, room: StringName, seed: int, options: Dictionary, version: int = CONTENT_VERSION) -> String:
	return var_to_bytes([version, String(theme), String(room), seed, _canonical(options)]).hex_encode().sha256_text()


static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var result := {}
		for k: Variant in keys:
			result[k] = _canonical(value[k])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_canonical(item))
		return result
	return value


static func load_layout(identity: String) -> Dictionary:
	if not enabled:
		return {}
	_mutex.lock()
	var path := entry_path(identity)
	var payload := _read_payload(path)
	var decoded: Variant = bytes_to_var(payload) if not payload.is_empty() else null
	var envelope: Dictionary = decoded if decoded is Dictionary else {}
	var layout: Variant = envelope.get("layout")
	var result: Dictionary = layout if layout is Dictionary and envelope.get("identity") == identity else {}
	if not valid_layout(result):
		_remove(path)
		result = {}
		misses += 1
	else:
		hits += 1
		_write_payload(path, payload)
	_mutex.unlock()
	return result


static func store_layout(identity: String, prepared: Dictionary) -> void:
	if not enabled or not valid_layout(prepared):
		return
	var payload := var_to_bytes({"identity": identity, "layout": prepared})
	if payload.size() > MAX_ENTRY_BYTES:
		return
	_mutex.lock()
	if DirAccess.make_dir_recursive_absolute(directory) == OK:
		_write_payload(entry_path(identity), payload)
		_prune(MAX_ENTRIES, MAX_BYTES)
	_mutex.unlock()


static func entry_path(identity: String) -> String:
	return directory.path_join(identity.sha256_text() + ".circuit")


static func _read_payload(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < HEADER_BYTES or file.get_length() > MAX_ENTRY_BYTES + HEADER_BYTES:
		return PackedByteArray()
	if file.get_32() != MAGIC or file.get_32() != CONTENT_VERSION:
		return PackedByteArray()
	var size := file.get_64()
	file.get_64() # Last access, used only by pruning.
	var digest := file.get_buffer(32)
	if size != file.get_length() - HEADER_BYTES:
		return PackedByteArray()
	var payload := file.get_buffer(size)
	return payload if _digest(payload) == digest else PackedByteArray()


static func _digest(payload: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(payload)
	return context.finish()


static func _write_payload(path: String, payload: PackedByteArray) -> void:
	var temporary := "%s.%d.%d.tmp" % [path, OS.get_process_id(), Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return
	file.store_32(MAGIC)
	file.store_32(CONTENT_VERSION)
	file.store_64(payload.size())
	file.store_64(int(Time.get_unix_time_from_system() * 1000000.0))
	file.store_buffer(_digest(payload))
	file.store_buffer(payload)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(temporary, path) != OK:
		_remove(temporary)


static func prune(max_entries: int = MAX_ENTRIES, max_bytes: int = MAX_BYTES) -> void:
	_mutex.lock()
	_prune(max_entries, max_bytes)
	_mutex.unlock()


static func _prune(max_entries: int, max_bytes: int) -> void:
	var entries: Array[Dictionary] = []
	var total := 0
	for name: String in DirAccess.get_files_at(directory):
		var path := directory.path_join(name)
		if name.ends_with(".tmp"):
			# Another process can be midway through an atomic write.
			if Time.get_unix_time_from_system() - FileAccess.get_modified_time(path) > STALE_TEMP_SECONDS:
				_remove(path)
		elif name.ends_with(".circuit"):
			if _read_payload(path).is_empty():
				_remove(path)
				continue
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null:
				continue
			file.seek(16)
			entries.append({"path": path, "access": file.get_64(), "size": file.get_length()})
			total += file.get_length()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["access"] < b["access"])
	while entries.size() > max_entries or total > max_bytes:
		var oldest: Dictionary = entries.pop_front()
		total -= int(oldest["size"])
		_remove(oldest["path"])


static func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func valid_layout(layout: Dictionary) -> bool:
	if not _data_only(layout) or layout.get("spec") is not Dictionary or layout.get("edges") is not Dictionary:
		return false
	for field: String in ["centerline", "room_polygon"]:
		if layout.get(field) is not PackedVector2Array or layout[field].size() < 3:
			return false
		for point: Vector2 in layout[field]:
			if not point.is_finite():
				return false
	for field: String in ["left", "right"]:
		if layout["edges"].get(field) is not PackedVector2Array or layout["edges"][field].size() != layout["centerline"].size():
			return false
	if layout.get("theme") is not StringName or layout.get("room_shape") is not StringName or layout.get("seed") is not int:
		return false
	var spec: Dictionary = layout["spec"]
	if not _valid_spec(spec):
		return false
	if String(layout.get("route_shape", "circuit")) == "strip":
		if not _has_types(layout, {"strip_regions": TYPE_ARRAY, "strip_gates": TYPE_ARRAY, "strip_grid": TYPE_DICTIONARY, "strip_caps": TYPE_DICTIONARY, "strip_theme_switch": TYPE_DICTIONARY, "traffic_plan": TYPE_ARRAY, "racing_line": TYPE_PACKED_VECTOR2_ARRAY, "theme_b": TYPE_STRING_NAME, "strip_length": TYPE_FLOAT, "strip_time_limit": TYPE_FLOAT, "strip_half_width": TYPE_FLOAT}):
			return false
		if layout["strip_regions"].size() != 2 or layout["strip_gates"].size() < 2:
			return false
		for region: Variant in layout["strip_regions"]:
			if region is not Dictionary or not _has_types(region, {"theme": TYPE_STRING_NAME, "spec": TYPE_DICTIONARY, "centerline": TYPE_PACKED_VECTOR2_ARRAY, "room_polygon": TYPE_PACKED_VECTOR2_ARRAY}) or not _valid_spec(region["spec"]):
				return false
		for gate: Variant in layout["strip_gates"]:
			if gate is not Dictionary or not _has_types(gate, {"index": TYPE_INT, "arc": TYPE_FLOAT, "position": TYPE_VECTOR2, "rotation": TYPE_FLOAT, "is_finish_line": TYPE_BOOL}):
				return false
		if not _has_types(layout["strip_grid"], {"player": TYPE_TRANSFORM2D, "chaser": TYPE_TRANSFORM2D}) or not _has_types(layout["strip_caps"], {"start": TYPE_VECTOR2, "finish": TYPE_VECTOR2}) or not _has_types(layout["strip_theme_switch"], {"position": TYPE_VECTOR2, "arc": TYPE_FLOAT, "rotation": TYPE_FLOAT}):
			return false
	return true


static func _valid_spec(spec: Dictionary) -> bool:
	if not _has_types(spec, {"controls": TYPE_PACKED_VECTOR2_ARRAY, "environment_plan": TYPE_DICTIONARY, "floor_texture": TYPE_STRING, "track_texture": TYPE_STRING, "highlight": TYPE_COLOR}):
		return false
	var plan: Dictionary = spec["environment_plan"]
	if plan.get("placements") is not Array or spec.get("obstacle_plan", []) is not Array:
		return false
	for placement: Variant in plan["placements"]:
		if placement is not Dictionary or not _has_types(placement, {"asset_id": TYPE_STRING, "position": TYPE_VECTOR2, "rotation": TYPE_FLOAT}):
			return false
	for obstacle: Variant in spec.get("obstacle_plan", []):
		if obstacle is not Dictionary or not _has_types(obstacle, {"position": TYPE_VECTOR2, "rotation": TYPE_FLOAT, "footprint_size": TYPE_VECTOR2}):
			return false
	return true


static func _has_types(record: Dictionary, fields: Dictionary) -> bool:
	for field: String in fields:
		if not record.has(field) or typeof(record[field]) != fields[field]:
			return false
	return true


static func _data_only(value: Variant, depth: int = 0) -> bool:
	if depth > 32 or value is Object or value is Callable or value is Signal or value is RID:
		return false
	if value is float and not is_finite(value):
		return false
	if value is Vector2 and not value.is_finite():
		return false
	if value is PackedVector2Array:
		for point: Vector2 in value:
			if not point.is_finite():
				return false
	if value is Dictionary:
		for k: Variant in value:
			if not _data_only(k, depth + 1) or not _data_only(value[k], depth + 1):
				return false
	elif value is Array:
		for item: Variant in value:
			if not _data_only(item, depth + 1):
				return false
	return true
