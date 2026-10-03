extends SceneTree

const PRESENTER_SCRIPT := preload("res://scripts/presentation/track_variant_presenter.gd")
const OBSTACLE_NAMES: Array[String] = ["MugA", "MugB", "CerealA", "CerealB", "Sponge", "Fork", "Ruler", "Apple", "Lime", "Cup", "Spoon"]
const THEME_SCENES: Dictionary = {
	&"kitchen": "res://scenes/tracks/kitchen_circuit.tscn",
	&"workshop": "res://scenes/tracks/workshop_workbench.tscn",
	&"office": "res://scenes/tracks/office_desk.tscn",
}
const THEME_EXPECTATIONS: Dictionary = {
	&"kitchen": {"base_surface": &"polished counter", "zones": 2},
	&"workshop": {"base_surface": &"workbench", "zones": 3},
	&"office": {"base_surface": &"desktop", "zones": 3},
}


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	for theme: StringName in [&"kitchen", &"workshop", &"office"]:
		if not await _test_theme(theme):
			return
	print("TRACK_VARIANT_TEST PASS")
	quit(0)


func _test_theme(theme: StringName) -> bool:
	var packed := load(String(THEME_SCENES[theme])) as PackedScene
	if not _expect(packed != null, "%s track scene should exist" % theme):
		return false
	var track := packed.instantiate() as Node2D
	track.name = "Track"
	root.add_child(track)
	var presenter := PRESENTER_SCRIPT.new() as TrackVariantPresenter
	track.add_child(presenter)
	presenter.configure(track, theme)
	var expected: Dictionary = THEME_EXPECTATIONS[theme]
	if not _expect(presenter.theme == theme and presenter.base_surface_name == expected["base_surface"], "%s should configure its runtime theme and base surface" % theme):
		return false
	var surface_definitions: Array = track.get_meta("generated_surfaces", [])
	if not _expect(presenter.surface_zones.size() == surface_definitions.size() and presenter.surface_zones.size() >= int(expected["zones"]), "%s should create all declared gameplay surface zones (%d)" % [theme, presenter.surface_zones.size()]):
		return false
	# Authored scenes still carry baked hazard metadata; the moving hazard was
	# removed, so the presenter must not spawn one from it.
	if not _expect(presenter.find_children("*Hazard", "", true, false).is_empty(), "%s should not create a moving hazard" % theme):
		return false
	var art_surfaces := track.get_node_or_null("ArtSurfaces") as Node2D
	if art_surfaces and not _expect(art_surfaces.visible, "%s should keep its authored art visible" % theme):
		return false
	var checkpoints: Array[Node] = []
	for child: Node in track.get_children():
		if child.is_in_group("track_checkpoints"):
			checkpoints.append(child)
	for obstacle_name: String in OBSTACLE_NAMES:
		var obstacle := track.get_node_or_null(obstacle_name) as StaticBody2D
		if obstacle == null:
			continue
		for checkpoint: Node2D in checkpoints:
			if not _expect(obstacle.position.distance_to(checkpoint.position) >= 145.0, "%s obstacle %s should not block checkpoint %s" % [theme, obstacle_name, checkpoint.name]):
				return false
	track.queue_free()
	await process_frame
	return true


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_VARIANT_TEST FAIL: " + message)
	quit(1)
	return false
