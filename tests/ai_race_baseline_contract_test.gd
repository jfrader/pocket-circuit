extends SceneTree

const BASELINE_SCRIPT := preload("res://tests/ai_race_baseline_test.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := BASELINE_SCRIPT.new()
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(harness.BASELINE_PATH))
	var document := baseline.duplicate(true)
	document["schema_version"] = int(document["schema_version"])
	for key: String in ["fixed_fps", "physics_ticks_per_second", "laps", "field_size"]:
		document["config"][key] = int(document["config"][key])
	for entry: Dictionary in document["seeds"]:
		entry["frames"] = int(entry["frames"])
		var racers: Array[Dictionary] = []
		for racer: Dictionary in entry["racers"]:
			racer["position"] = int(racer["position"])
			racers.append(racer)
		entry["racers"] = racers
	if not _expect(harness._compare(document, baseline).is_empty(), "native race records must match their stored JSON representation"):
		harness.free()
		return
	var mutations: Array[Dictionary] = []
	var changed := document.duplicate(true)
	changed["schema_version"] = 0
	mutations.append(changed)
	for key: String in baseline["config"]:
		changed = document.duplicate(true)
		changed["config"].erase(key)
		mutations.append(changed)
	changed = document.duplicate(true)
	changed["seeds"][0]["key"] = "missing/seed/0"
	mutations.append(changed)
	for frame_error in [1.0, 0.5]:
		changed = document.duplicate(true)
		changed["seeds"][0]["frames"] = float(changed["seeds"][0]["frames"]) + frame_error
		mutations.append(changed)
	changed = document.duplicate(true)
	changed["seeds"][0]["hash"] = "changed"
	mutations.append(changed)
	changed = document.duplicate(true)
	changed["seeds"][0]["finish_order"].reverse()
	mutations.append(changed)
	# Leave the stored hash unchanged: racer fields must be checked themselves.
	for key: String in ["driver", "position", "finish_time", "dnf"]:
		changed = document.duplicate(true)
		changed["seeds"][0]["racers"][0].erase(key)
		mutations.append(changed)
	for index in mutations.size():
		if not _expect(not harness._compare(mutations[index], baseline).is_empty(), "mutation %d must fail" % index):
			harness.free()
			return
	harness.free()
	print("AI_BASELINE_CONTRACT_TEST PASS mutations=%d" % mutations.size())
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("AI_BASELINE_CONTRACT_TEST FAIL: " + message)
	quit(1)
	return false
