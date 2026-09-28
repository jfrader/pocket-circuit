extends SceneTree


func _initialize() -> void:
	for excluded_path in [
		"res://assets/source/kitchen_hero/mug.jpg",
		"res://assets/source/kitchen_hero/tea_board.jpg",
		"res://assets/ui/concepts/title-concept.jpg",
		"res://assets/ui/concepts/garage-concept.jpg",
		"res://assets/ui/concepts/hud-concept.jpg",
		"res://scripts/ui/debug_overlay.gd",
		"res://addons/godot_mcp/plugin.cfg",
		"res://addons/release_export/plugin.cfg",
		"res://tests/input_map_test.gd",
		"res://tools/build_release.sh",
		"res://tools/create_media_save.gd",
		"res://tools/environment_pilot.tscn",
		"res://tools/environment_race_pilot.tscn",
		"res://graphify-out/graph.json",
		"res://assets/textures/environment_pilot/kitchen_teapot.png",
		"res://assets/textures/environment_pilot/workshop_toolbox.png",
		"res://assets/textures/environment_pilot/office_keyboard.png",
		"res://media/steam/capsules/header_capsule.png",
	]:
		if ResourceLoader.exists(excluded_path) or FileAccess.file_exists(excluded_path):
			_fail("excluded release file is present: %s" % excluded_path)
			return
	for required_path in [
		"res://ASSET_PROVENANCE.md",
		"res://THIRD_PARTY_NOTICES.md",
		"res://assets/audio/LICENSE.md",
		"res://data/vendor/procedural_2d/avatar_catalog.json",
		"res://data/vendor/procedural_2d/car_catalog.json",
		"res://data/vendor/procedural_2d/LICENSE",
		"res://data/household_material_patterns.json",
	]:
		if not FileAccess.file_exists(required_path):
			_fail("required release notice is missing: %s" % required_path)
			return
	if not ResourceLoader.exists("res://assets/shaders/handmade_course.gdshader"):
		_fail("handmade course shader is missing")
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
