extends SceneTree

const PRESENTER_SCRIPT := preload("res://scripts/presentation/track_variant_presenter.gd")
const KITCHEN_SCENE := preload("res://scenes/tracks/kitchen_graybox.tscn")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not await _test_variant(&"kitchen", &"polished counter", 1, "KitchenHazard", ""):
		return
	if not await _test_variant(&"workshop", &"workbench", 2, "WorkshopHazard", "WorkshopRuntimeArt"):
		return
	if not await _test_variant(&"office", &"desk mat", 2, "OfficeHazard", "OfficeRuntimeArt"):
		return
	if not await _test_proven_footprint_variant(&"workshop"):
		return
	if not await _test_proven_footprint_variant(&"office"):
		return
	print("TRACK_VARIANT_TEST PASS")
	quit(0)


func _test_variant(theme: StringName, base_surface: StringName, surface_count: int, hazard_node_name: String, art_node_name: String) -> bool:
	var track := Node2D.new()
	track.name = "AssetFreeTrack"
	root.add_child(track)
	var presenter := PRESENTER_SCRIPT.new() as TrackVariantPresenter
	track.add_child(presenter)
	presenter.configure(track, theme)
	if not _expect(presenter.theme == theme and presenter.base_surface_name == base_surface, "%s should configure its runtime theme and base surface" % theme):
		return false
	if not _expect(presenter.surface_zones.size() == surface_count, "%s should create the documented surface zones" % theme):
		return false
	if not _expect(presenter.hazard != null and presenter.hazard.name == hazard_node_name and presenter.hazard.get_state_name() == &"warning", "%s should create a telegraphed deterministic hazard" % theme):
		return false
	if not art_node_name.is_empty() and not _expect(presenter.has_node(art_node_name), "%s should build an asset-free vector presentation" % theme):
		return false
	track.queue_free()
	await process_frame
	return true


func _test_proven_footprint_variant(theme: StringName) -> bool:
	var track := KITCHEN_SCENE.instantiate() as Node2D
	root.add_child(track)
	var presenter := PRESENTER_SCRIPT.new() as TrackVariantPresenter
	track.add_child(presenter)
	presenter.configure(track, theme)
	var art_surfaces := track.get_node("ArtSurfaces") as Node2D
	var floor := track.get_node("Floor") as Polygon2D
	var obstacle_sprite := track.get_node("MugA/Sprite") as Sprite2D
	var obstacle_fallback := track.get_node("MugA/Visual") as Polygon2D
	if not _expect(not art_surfaces.visible and floor.visible, "%s should replace Kitchen texture layers with runtime vectors" % theme):
		return false
	if not _expect(not obstacle_sprite.visible and obstacle_fallback.visible, "%s should reveal safe collision-matched obstacle fallbacks" % theme):
		return false
	var checkpoints: Array[Node] = []
	for child: Node in track.get_children():
		if child.is_in_group("track_checkpoints"):
			checkpoints.append(child)
	for obstacle_name: String in TrackVariantPresenter.OBSTACLE_NAMES:
		var obstacle := track.get_node(obstacle_name) as StaticBody2D
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
