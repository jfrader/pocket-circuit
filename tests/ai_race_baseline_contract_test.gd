extends SceneTree

const BASELINE_SCRIPT := preload("res://tests/ai_race_baseline_test.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var harness := BASELINE_SCRIPT.new()
	var cases: Array[Dictionary] = [{"theme": &"kitchen", "room": &"long", "seed": 24469}]
	var racers: Array = []
	for index in 4:
		racers.append({
			"driver": "driver%d" % index,
			"position": index + 1,
			"finish_time": 30.0 + index,
			"finished": true,
			"dnf": false,
			"lap": 2,
			"recoveries": 0,
			"gates": [1, 0, 1, 0],
		})
	var document := {
		"schema_version": harness.SCHEMA_VERSION,
		"config": {"difficulty": "club_circuit", "fixed_fps": 60, "physics_ticks_per_second": 60, "time_scale": 1.0, "laps": 2, "field_size": 4},
		"seeds": [{
			"key": "kitchen/long/24469", "theme": "kitchen", "room": "long", "seed": 24469,
			"frames": 2100, "gate_order": [1, 0], "finish_order": ["driver0", "driver1", "driver2", "driver3"],
			"racers": racers, "hash": "diagnostic only",
		}],
	}
	if not _expect(harness.validate_document(document, cases).is_empty(), "native functional race should pass"):
		return
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(document))
	if not _expect(harness.validate_document(roundtrip, cases).is_empty(), "JSON numeric records should pass"):
		return
	var changed := document.duplicate(true)
	changed["seeds"][0]["racers"].reverse()
	for position in 4:
		changed["seeds"][0]["racers"][position]["position"] = position + 1
		changed["seeds"][0]["racers"][position]["finish_time"] = 28.0 + position
		changed["seeds"][0]["finish_order"][position] = changed["seeds"][0]["racers"][position]["driver"]
	if not _expect(harness.validate_document(changed, cases).is_empty(), "different legal winner and times should pass"):
		return
	var failures: Array[Dictionary] = []
	changed = document.duplicate(true)
	changed["schema_version"] = 0
	failures.append(changed)
	for key: String in document["config"]:
		changed = document.duplicate(true)
		changed["config"].erase(key)
		failures.append(changed)
	changed = document.duplicate(true)
	changed["seeds"][0]["key"] = "missing/seed/0"
	failures.append(changed)
	changed = document.duplicate(true)
	changed["seeds"].clear()
	failures.append(changed)
	for bad_frames in [0, 0.5, 7201, NAN, INF]:
		changed = document.duplicate(true)
		changed["seeds"][0]["frames"] = bad_frames
		failures.append(changed)
	for key: String in ["driver", "position", "finish_time", "dnf", "finished", "lap", "recoveries", "gates"]:
		changed = document.duplicate(true)
		changed["seeds"][0]["racers"][0].erase(key)
		failures.append(changed)
	for key: String in ["driver", "position"]:
		changed = document.duplicate(true)
		changed["seeds"][0]["racers"][1][key] = changed["seeds"][0]["racers"][0][key]
		failures.append(changed)
	changed = document.duplicate(true)
	changed["seeds"][0]["racers"].pop_back()
	failures.append(changed)
	changed = document.duplicate(true)
	changed["seeds"][0]["finish_order"].reverse()
	failures.append(changed)
	for bad_time in [0.0, -1.0, 121.0, NAN, INF]:
		changed = document.duplicate(true)
		changed["seeds"][0]["racers"][0]["finish_time"] = bad_time
		failures.append(changed)
	for key: String in ["dnf", "finished", "lap", "recoveries", "gates"]:
		changed = document.duplicate(true)
		changed["seeds"][0]["racers"][0][key] = {"dnf": true, "finished": false, "lap": 1, "recoveries": 4, "gates": [1, 0, 0, 1]}[key]
		failures.append(changed)
	changed = document.duplicate(true)
	changed["seeds"][0]["racers"][3]["finish_time"] = 60.0
	failures.append(changed)
	changed = document.duplicate(true)
	changed["seeds"][0]["racers"][0]["finish_time"] = 32.0
	failures.append(changed)
	for index in failures.size():
		if not _expect(not harness.validate_document(failures[index], cases).is_empty(), "broken race %d must fail" % index):
			return
	harness.free()
	print("AI_BASELINE_CONTRACT_TEST PASS mutations=%d" % failures.size())
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("AI_BASELINE_CONTRACT_TEST FAIL: " + message)
	quit(1)
	return false
