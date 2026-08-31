extends SceneTree

const CIRCUIT_ROSTER := preload("res://data/circuits/circuit_roster.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var entries: Array = CIRCUIT_ROSTER.entries()
	if not _expect(entries.size() == 64, "the roster should contain 64 generated circuits (32 per theme)"):
		return
	if not _expect(
		CIRCUIT_ROSTER.scene_path(&"workshop", &"classic", 6) == "res://scenes/tracks/circuits/workshop_seed_6.tscn",
		"classic scene paths should use the theme and seed filename format"
	):
		return
	if not _expect(
		CIRCUIT_ROSTER.scene_path(&"workshop", &"wide", 5) == "res://scenes/tracks/circuits/workshop_wide_seed_5.tscn",
		"room-variant scene paths should include the room"
	):
		return
	for entry: Dictionary in entries:
		var scene_path := CIRCUIT_ROSTER.scene_path(StringName(entry["theme"]), StringName(entry["room"]), int(entry["seed"]))
		if not _expect(FileAccess.file_exists(scene_path), "%s should exist" % scene_path):
			return
	print("CIRCUIT_ROSTER_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("CIRCUIT_ROSTER_TEST FAIL: " + message)
	quit(1)
	return false
