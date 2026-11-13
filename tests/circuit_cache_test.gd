extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const CACHE := preload("res://scripts/race/circuit_cache.gd")
const FINALE := preload("res://scripts/race/run_finale_circuit.gd")
var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	CACHE.directory = "user://circuit_cache_test"
	if not OS.get_environment("PC_CIRCUIT_CACHE_BENCH").is_empty():
		var seed := int(OS.get_environment("PC_CIRCUIT_CACHE_BENCH"))
		var started := Time.get_ticks_usec()
		var prepared := BUILDER.prepare_layout(&"kitchen", &"long", seed)
		print("CIRCUIT_CACHE_BENCH seed=%d elapsed_ms=%.3f hits=%d misses=%d generations=%d hash=%d" % [seed, (Time.get_ticks_usec() - started) / 1000.0, CACHE.hits, CACHE.misses, BUILDER.prepared_layout_generations, hash(prepared)])
		_expect(not prepared.is_empty(), "benchmark prepares a layout")
		_finish()
		return
	_clear()
	var key := CACHE.key(&"kitchen", &"long", 24469, {})
	var generated := BUILDER.prepare_layout(&"kitchen", &"long", 24469)
	_expect(not generated.is_empty() and FileAccess.file_exists(CACHE.entry_path(key)), "miss generates and stores")
	var generations := BUILDER.prepared_layout_generations
	BUILDER.clear_generated_cache()
	var restored := BUILDER.prepare_layout(&"kitchen", &"long", 24469)
	_expect(hash(generated) == hash(restored) and var_to_bytes(generated) == var_to_bytes(restored), "disk hit restores identical complete layout")
	_expect(BUILDER.prepared_layout_generations == generations and CACHE.hits == 1, "hit skips generation with empty process-local cache")
	_expect(CACHE.key(&"kitchen", &"long", 24469, {}, CACHE.CONTENT_VERSION + 1) != key, "content version changes identity")
	for options: Dictionary in [{"length_tier": "long"}, {"reverse": true}, {"road_width": "varied"}, {"authored_route": FINALE.ROUTE_ID}, {"route_shape": "strip"}]:
		_expect(CACHE.key(&"kitchen", &"long", 24469, options) != key, "generation options change identity")
	_expect(CACHE.key(&"office", &"long", 24469, {}) != key and CACHE.key(&"kitchen", &"long", 24470, {}) != key, "theme and seed change identity")
	_expect(CACHE.key(&"kitchen", &"long", 1, {"sub_seeds": {"a": 1, "b": 2}}) == CACHE.key(&"kitchen", &"long", 1, {"sub_seeds": {"b": 2, "a": 1}}), "nested option order is canonical")
	var file := FileAccess.open(CACHE.entry_path(key), FileAccess.READ_WRITE)
	file.seek(4)
	file.store_32(CACHE.CONTENT_VERSION + 1)
	file.close()
	_expect(CACHE.load_layout(key).is_empty() and not FileAccess.file_exists(CACHE.entry_path(key)), "old version header is rejected and pruned")
	CACHE.store_layout(key, generated)
	file = FileAccess.open(CACHE.entry_path(key), FileAccess.WRITE)
	file.store_buffer(PackedByteArray([1, 2, 3]))
	file.close()
	restored = BUILDER.prepare_layout(&"kitchen", &"long", 24469)
	_expect(BUILDER.prepared_layout_generations == generations + 1 and hash(restored) == hash(generated), "truncated file regenerates deterministically")
	file = FileAccess.open(CACHE.entry_path(key), FileAccess.READ_WRITE)
	file.seek(CACHE.HEADER_BYTES + 20)
	file.store_8(255)
	file.close()
	_expect(CACHE.load_layout(key).is_empty(), "checksum rejects payload corruption before decoding")
	CACHE._write_payload(CACHE.entry_path(key), var_to_bytes({"identity": key, "layout": {"spec": {}}}))
	_expect(CACHE.load_layout(key).is_empty() and not FileAccess.file_exists(CACHE.entry_path(key)), "well-encoded malformed schema is ignored and pruned")
	CACHE.enabled = false
	restored = BUILDER.prepare_layout(&"kitchen", &"long", 24469)
	_expect(hash(restored) == hash(generated) and not FileAccess.file_exists(CACHE.entry_path(key)), "disabled cache preserves deterministic generation without writes")
	CACHE.enabled = true
	_expect(not CACHE.valid_layout({}) and not CACHE.valid_layout({"spec": RefCounted.new()}), "malformed or object data is rejected")
	var misses := CACHE.misses
	var new_seed := BUILDER.prepare_layout(&"kitchen", &"long", 24470)
	_expect(not new_seed.is_empty() and CACHE.misses == misses + 1 and hash(new_seed) != hash(generated), "new seed misses and generates a distinct layout")
	for event: Dictionary in [FINALE.event(), {"theme": &"kitchen", "room": &"long", "seed": 24469, "options": {"route_shape": "strip"}}]:
		var theme := StringName(event["theme"])
		var room := StringName(event["room"])
		var seed := int(event["seed"])
		var options: Dictionary = event.get("options", BUILDER.generated_circuit_options(event))
		var special := BUILDER.prepare_layout(theme, room, seed, options)
		generations = BUILDER.prepared_layout_generations
		var special_hit := BUILDER.prepare_layout(theme, room, seed, options)
		_expect(not special.is_empty() and hash(special) == hash(special_hit) and BUILDER.prepared_layout_generations == generations, "authored finale and strip both restore without regeneration")
	_clear()
	for identity: String in ["old", "recent", "new"]:
		CACHE.store_layout(identity, generated)
		OS.delay_msec(2)
	CACHE.load_layout("old")
	CACHE.prune(2)
	_expect(FileAccess.file_exists(CACHE.entry_path("old")) and FileAccess.file_exists(CACHE.entry_path("new")) and not FileAccess.file_exists(CACHE.entry_path("recent")), "LRU evicts least recently accessed, not oldest written")
	CACHE.prune(CACHE.MAX_ENTRIES, 1)
	_expect(DirAccess.get_files_at(CACHE.directory).is_empty(), "total byte cap evicts entries")
	for index in CACHE.MAX_ENTRIES + 2:
		CACHE.store_layout(str(index), generated)
	_expect(DirAccess.get_files_at(CACHE.directory).size() == CACHE.MAX_ENTRIES, "automatic entry bound enforced")
	_clear()
	_finish()


func _clear() -> void:
	if not DirAccess.dir_exists_absolute(CACHE.directory):
		return
	for name: String in DirAccess.get_files_at(CACHE.directory):
		DirAccess.remove_absolute(CACHE.directory.path_join(name))


func _expect(ok: bool, message: String) -> void:
	if not ok:
		_failed = true
		push_error("CIRCUIT_CACHE_TEST FAIL: " + message)


func _finish() -> void:
	if not _failed:
		print("CIRCUIT_CACHE_TEST PASS persistence_identity_version_corruption_lru_determinism")
	quit(1 if _failed else 0)
