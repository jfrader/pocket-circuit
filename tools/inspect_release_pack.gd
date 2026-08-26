extends SceneTree


func _initialize() -> void:
	for excluded_path in [
		"res://scripts/ui/debug_overlay.gd",
		"res://addons/godot_mcp/plugin.cfg",
		"res://addons/release_export/plugin.cfg",
		"res://tests/input_map_test.gd",
		"res://tools/build_release.sh",
	]:
		if ResourceLoader.exists(excluded_path) or FileAccess.file_exists(excluded_path):
			_fail("excluded release file is present: %s" % excluded_path)
			return
	for required_path in ["res://THIRD_PARTY_NOTICES.md", "res://assets/audio/LICENSE.md"]:
		if not FileAccess.file_exists(required_path):
			_fail("required release notice is missing: %s" % required_path)
			return
	var race_scene := load("res://scenes/race/prototype_race.tscn") as PackedScene
	if race_scene == null:
		_fail("release race scene could not be loaded")
		return
	var race := race_scene.instantiate()
	if race.has_node("DebugOverlay"):
		race.free()
		_fail("release race scene still contains DebugOverlay")
		return
	race.free()
	print("PACKAGED_CONTENT_TEST PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("PACKAGED_CONTENT_TEST FAIL: " + message)
	quit(1)
