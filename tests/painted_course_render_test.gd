extends SceneTree

const MATERIALS := preload("res://scripts/race/household_surface_materials.gd")
const CORE := preload("res://scripts/race/track_builder_core.gd")
const VIEW_SIZE := Vector2i(512, 384)
const PIXEL_TOLERANCE := 2

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for theme: StringName in [&"kitchen", &"workshop", &"office"]:
		var viewport := SubViewport.new()
		viewport.size = VIEW_SIZE
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var world := Node2D.new()
		viewport.add_child(world)
		var floor_node := Polygon2D.new()
		floor_node.name = "RoomSurface"
		floor_node.polygon = PackedVector2Array([Vector2.ZERO, Vector2(VIEW_SIZE.x, 0), Vector2(VIEW_SIZE), Vector2(0, VIEW_SIZE.y)])
		floor_node.z_index = -20
		world.add_child(floor_node)
		var resolved := MATERIALS.resolve(theme, 6)
		CORE._add_centerline_tiles(world, PackedVector2Array([Vector2(0, 140), Vector2(230, 140), Vector2(450, 320), Vector2(512, 320)]), resolved["floor"]["texture"])
		var surface := world.get_node("TrackSurface") as Line2D
		surface.closed = false
		MATERIALS.apply(world, resolved)
		var material := surface.material as ShaderMaterial
		if not _expect(material.get_shader_parameter("paint_opacity") == resolved["course"]["paint_opacity"], "opacity match"): return
		if not _expect(material.get_shader_parameter("surface_grain") == (floor_node.material as ShaderMaterial).get_shader_parameter("surface_grain"), "grain match"): return
		root.add_child(viewport)
		if DisplayServer.get_name() != "headless":
			surface.hide()
			var bare := await _pixels(viewport)
			surface.show()
			material.set_shader_parameter("paint_opacity", 0.0)
			var neutral := await _pixels(viewport)
			var maximum := 0
			for index in bare.size():
				maximum = maxi(maximum, absi(int(bare[index]) - int(neutral[index])))
			if not _expect(maximum <= PIXEL_TOLERANCE, "zero-coat substrate must remain continuous across turns: " + String(theme)): return
			material.set_shader_parameter("paint_opacity", resolved["course"]["paint_opacity"])
			var painted := await _pixels(viewport)
			var changed_pixels := 0
			for index in range(0, bare.size(), 4):
				if absi(int(bare[index]) - int(painted[index])) > PIXEL_TOLERANCE:
					changed_pixels += 1
			if not _expect(changed_pixels > VIEW_SIZE.x * VIEW_SIZE.y / 10, "paint must remain visible, not just render its substrate"): return
			print("PAINTED_PIXELS ", theme, " zero_coat_max=", maximum, " changed=", changed_pixels)
		root.remove_child(viewport)
		viewport.free()
		await process_frame
	if DisplayServer.get_name() == "headless":
		print("PAINTED_PIXELS skipped=headless; run natively for framebuffer assertions")
	if _failed:
		return
	print("PAINTED_COURSE_RENDER_TEST PASS shared_substrate_visible_pigment")
	quit(0)

func _pixels(viewport: SubViewport) -> PackedByteArray:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image.get_data()

var _failed := false
func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error("FAIL: " + message)
		quit(1)
		return false
	return true
