extends SceneTree

## Covers the generated-circuit cache (GURI-1594): bounded storage, independent
## copies, oldest-first eviction, packed-room reuse, and the real cache keys.

const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const PROTOTYPE_RACE := preload("res://scripts/race/prototype_race.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	TRACK_BUILDER.clear_generated_cache()
	if not _expect(TRACK_BUILDER.generated_cache_size() == 0, "cache starts empty after clear"):
		return

	# The cache is content-agnostic; synthetic prepared dicts keep this test fast.
	TRACK_BUILDER.store_prepared("k-a", {"seed": 1})
	if not _expect(TRACK_BUILDER.generated_cache_size() == 1, "size==1 after first store"):
		return
	var hit: Dictionary = TRACK_BUILDER.cached_prepared("k-a")
	if not _expect(int(hit.get("seed", 0)) == 1, "cached_prepared returns the stored data"):
		return
	hit["mutated"] = true
	if not _expect(not TRACK_BUILDER.cached_prepared("k-a").has("mutated"), "returned prepared is an independent copy"):
		return
	if not _expect(TRACK_BUILDER.cached_prepared("missing").is_empty(), "an unknown key misses"):
		return

	# Oldest-first eviction at the documented cap.
	for extra in range(TRACK_BUILDER.MAX_GENERATED_CACHE_ENTRIES + 2):
		TRACK_BUILDER.store_prepared("evict-%d" % extra, {"seed": extra})
	if not _expect(TRACK_BUILDER.generated_cache_size() == TRACK_BUILDER.MAX_GENERATED_CACHE_ENTRIES, "eviction keeps the documented cap"):
		return
	if not _expect(TRACK_BUILDER.cached_prepared("k-a").is_empty(), "the oldest entry is evicted first"):
		return

	# Packed room round trip: pack a small tree, store, instantiate independently.
	var root := Node2D.new()
	root.name = "Track"
	var child := Node2D.new()
	child.name = "Child"
	root.add_child(child)
	child.owner = root
	var packed := PackedScene.new()
	if not _expect(packed.pack(root) == OK, "packing a layout root succeeds"):
		return
	root.free()
	TRACK_BUILDER.store_room("room-a", packed)
	var room_hit: PackedScene = TRACK_BUILDER.cached_room("room-a")
	if not _expect(room_hit != null, "cached_room returns the packed scene"):
		return
	var instance := room_hit.instantiate()
	if not _expect(instance is Node2D and instance.get_node_or_null("Child") != null, "the instantiated room is independent and complete"):
		instance.free()
		return
	instance.free()

	# Real cache keys: fingerprints win, and option changes stay distinct.
	var race := PROTOTYPE_RACE.new()
	var by_fingerprint: String = race.call("_circuit_cache_key", {"circuit_fingerprint": "abc123"})
	var by_other_fingerprint: String = race.call("_circuit_cache_key", {"circuit_fingerprint": "def456"})
	if not _expect(by_fingerprint == "cfp|abc123", "circuit_fingerprint is used as the key"):
		race.free()
		return
	if not _expect(by_fingerprint != by_other_fingerprint, "different fingerprints give different keys"):
		race.free()
		return
	var flat_key: String = race.call("_circuit_cache_key", {"theme": "kitchen", "room": "classic", "seed": 42})
	var seeded_key: String = race.call("_circuit_cache_key", {"theme": "kitchen", "room": "classic", "seed": 42, "road_width": 115.0})
	var other_tier: String = race.call("_circuit_cache_key", {"theme": "kitchen", "room": "classic", "seed": 42, "length_tier": "long"})
	if not _expect(flat_key != seeded_key and flat_key != other_tier and seeded_key != other_tier, "option changes produce distinct fallback keys"):
		race.free()
		return
	race.free()

	TRACK_BUILDER.clear_generated_cache()
	if not _expect(TRACK_BUILDER.generated_cache_size() == 0, "clear_generated_cache resets the cache"):
		return

	print("GENERATED_CIRCUIT_CACHE_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("GENERATED_CIRCUIT_CACHE_TEST FAIL: " + message)
	quit(1)
	return false
