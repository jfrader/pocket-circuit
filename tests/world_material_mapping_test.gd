extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const FLOOR_TEXTURE := "res://assets/textures/imagine/floor_cloth.png"


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var world := Node2D.new()
	root.add_child(world)
	var points := PackedVector2Array([Vector2(64, 64), Vector2(1088, 64), Vector2(1088, 576), Vector2(64, 576)])
	BUILDER._add_textured_polygon(world, "Ground", points, FLOOR_TEXTURE, Color.WHITE, 0)
	var ground := world.get_node("Ground") as Polygon2D
	var texture_size := ground.texture.get_size()
	var checker := Image.create(int(texture_size.x), int(texture_size.y), false, Image.FORMAT_RGBA8)
	checker.fill(Color("d64a36"))
	checker.fill_rect(Rect2i(int(texture_size.x / 2), 0, int(texture_size.x / 2), int(texture_size.y / 2)), Color("296bc2"))
	checker.fill_rect(Rect2i(0, int(texture_size.y / 2), int(texture_size.x / 2), int(texture_size.y / 2)), Color("296bc2"))
	ground.texture = ImageTexture.create_from_image(checker)
	await process_frame
	await process_frame
	var rendered: Image
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		rendered = root.get_texture().get_image()
		var output := OS.get_environment("PC_MAPPING_SCREENSHOT")
		if not output.is_empty() and not _expect(rendered.save_png(output) == OK, "diagnostic checker capture should be saved"):
			return
	var uv_span := ground.uv[1] - ground.uv[0]
	print("MATERIAL_UV_SPAN actual=%s expected=%s" % [uv_span, Vector2(texture_size.x * 2.0, 0)])
	if not _expect(uv_span.is_equal_approx(Vector2(texture_size.x * 2.0, 0)), "1024 world units should cover two complete 512-unit texture tiles, not two texture pixels"):
		return
	if not _expect(ground.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED, "ground material must repeat beyond its first tile"):
		return
	if not _expect(ground.polygon == points, "material mapping must not change floor geometry"):
		return
	if rendered != null:
		var first := rendered.get_pixel(96, 96)
		var alternate := rendered.get_pixel(352, 96)
		var repeated := rendered.get_pixel(608, 96)
		if not _expect(first.r > first.b and alternate.b > alternate.r and first.is_equal_approx(repeated), "rendered checker must show both colors and repeat at the configured world period"):
			return
	var neighbor_points := PackedVector2Array([points[1], Vector2(1600, 64), Vector2(1600, 576), points[2]])
	BUILDER._add_textured_polygon(world, "Neighbor", neighbor_points, FLOOR_TEXTURE, Color.WHITE, 0)
	var neighbor := world.get_node("Neighbor") as Polygon2D
	if not _expect(neighbor.uv[0].is_equal_approx(ground.uv[1]), "adjacent floor pieces must share texture phase at their common edge"):
		return
	BUILDER._add_textured_polygon(world, "Anisotropic", points, FLOOR_TEXTURE, Color.WHITE, 0, Vector2(256, 1024))
	var scaled := world.get_node("Anisotropic") as Polygon2D
	if not _expect((scaled.uv[1] - scaled.uv[0]).is_equal_approx(Vector2(texture_size.x * 4, 0)) and (scaled.uv[3] - scaled.uv[0]).is_equal_approx(Vector2(0, texture_size.y * 0.5)), "explicit world tile dimensions must independently control each axis"):
		return
	var negative := PackedVector2Array([Vector2(-512, -512), Vector2.ZERO, Vector2(-512, 0)])
	BUILDER._add_textured_polygon(world, "Negative", negative, FLOOR_TEXTURE, Color.WHITE, 0)
	if not _expect((world.get_node("Negative") as Polygon2D).uv[0].is_equal_approx(-texture_size), "negative track coordinates must retain the same world-space tile phase"):
		return
	BUILDER._add_textured_polygon(world, "Fallback", points, "", Color.CORAL, 0)
	var fallback := world.get_node("Fallback") as Polygon2D
	if not _expect(fallback.texture == null and fallback.color == Color.CORAL and fallback.polygon == points, "untextured fallback must preserve its original color and geometry"):
		return
	var island_root := Node2D.new()
	world.add_child(island_root)
	var island_points := PackedVector2Array([Vector2(0, -1024), Vector2(512, -1024), Vector2(512, -512), Vector2(0, -512)])
	var island_spec := {"island_expansion": 0.0, "island": Color("414c54"), "prop_texture": "res://assets/textures/imagine/island_keyboard.png"}
	BUILDER._build_island_prop(island_root, island_spec, island_points, island_points, island_points)
	var island := island_root.get_node("IslandProp") as Polygon2D
	if not _expect(island.uv[0].is_equal_approx(Vector2.ZERO) and island.uv[2].is_equal_approx(island.texture.get_size()), "fitted island artwork should cover its full texture, not one texel"):
		return
	if not _expect(island.polygon == island_points, "island artwork mapping must preserve the raised-island geometry"):
		return
	var island_material := island_root.get_node("IslandMaterial") as Polygon2D
	if not _expect(island_material.polygon == island_points and island_material.color == island_spec["island"], "transparent artwork margins must retain a continuous raised-island material underneath"):
		return
	world.queue_free()
	await process_frame
	print("WORLD_MATERIAL_MAPPING_TEST PASS pixel_space_repeat_phase_scale_and_geometry")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("WORLD_MATERIAL_MAPPING_TEST FAIL: " + message)
	quit(1)
	return false
