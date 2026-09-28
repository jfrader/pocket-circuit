extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const HERO_ASSETS := ["hero_kitchen_mug", "hero_kitchen_plate_stack", "hero_kitchen_tea_board"]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var spec: Dictionary = BUILDER.LAYOUTS[&"kitchen"]
	var materials := HouseholdSurfaceMaterials.resolve(&"kitchen", 0)
	if not _expect(materials["course"]["kind"] == "colored_card" and materials["course"]["contrast_safe"], "Kitchen course should use contrasting colored card rather than blend into the wood island"):
		return
	var world := Node2D.new()
	root.add_child(world)
	var points := PackedVector2Array([Vector2(64, 256), Vector2(448, 256), Vector2(832, 640)])
	BUILDER._add_centerline_tiles(world, points, spec["track_texture"], 1.0, Vector2(512, 512), 1.0)
	var surface := world.get_node("TrackSurface") as Line2D
	surface.closed = false
	var material := surface.material as ShaderMaterial
	if not _expect(material != null and material.get_shader_parameter("tile_world_size") == Vector2(512, 512), "route material should use an explicit world-space period"):
		return
	var checker := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	checker.fill(Color("d64a36"))
	checker.fill_rect(Rect2i(256, 0, 256, 512), Color("296bc2"))
	surface.texture = ImageTexture.create_from_image(checker)
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		for point in [Vector2i(96, 256), Vector2i(352, 256), Vector2i(544, 352), Vector2i(640, 448), Vector2i(736, 544)]:
			var pixel := frame.get_pixelv(point)
			var red_expected := posmod(point.x, 512) < 256
			if not _expect((pixel.r > pixel.b) == red_expected, "material grain must remain world-aligned through a turn"):
				return
	world.remove_child(surface)
	surface.free()
	var island := PackedVector2Array([Vector2(-512, -256), Vector2(512, -256), Vector2(512, 256), Vector2(-512, 256)])
	var island_spec := spec.duplicate(true)
	island_spec["seed_obstacles"] = false
	BUILDER._build_island_prop(world, island_spec, island, island, island)
	var island_art := world.get_node("IslandProp") as Polygon2D
	if not _expect(island_art.texture.resource_path == spec["island_material_texture"] and island_art.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED, "Kitchen island must use board material, not a fitted plate illustration"):
		return
	for asset: String in HERO_ASSETS:
		var texture := load("res://assets/textures/kitchen_hero/%s.png" % asset) as Texture2D
		var image := texture.get_image()
		if not _expect(image.get_size() == Vector2i(512, 512) and image.get_pixel(0, 0).a == 0 and image.get_used_rect().has_area(), "hero sprites must have normalized size and transparent padding"):
			return
		var opaque_samples := 0
		var key_color_samples := 0
		for y in range(0, 512, 4):
			for x in range(0, 512, 4):
				var pixel := image.get_pixel(x, y)
				if pixel.a < 0.5:
					continue
				opaque_samples += 1
				var key_color := pixel.r > pixel.g * 1.5 and pixel.b > pixel.g * 1.2 and pixel.r > 0.5
				if key_color:
					key_color_samples += 1
		if not _expect(key_color_samples <= maxi(2, opaque_samples / 100), "processed hero art must not retain a chroma-colored field"):
			return
	var shadow_root := Node2D.new()
	world.add_child(shadow_root)
	BUILDER._add_directional_shadow(shadow_root, "res://assets/textures/kitchen_hero/hero_kitchen_plate_stack.png", 160.0)
	if not _expect(shadow_root.get_node("ContactShadow").get_meta("shadow_shape") == &"circle", "round hero props should have round contact shadows even when their collider is convex"):
		return
	world.queue_free()
	await process_frame
	print("KITCHEN_PRESENTATION_TEST PASS world_material_alignment_island_and_clean_sprites")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("KITCHEN_PRESENTATION_TEST FAIL: " + message)
	quit(1)
	return false
