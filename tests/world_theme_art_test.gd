extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const HERO_ASSETS := [
	"workshop_hero/hero_workshop_toolbox", "workshop_hero/hero_workshop_wrench", "workshop_hero/hero_workshop_paint_can",
	"office_hero/hero_office_keyboard", "office_hero/hero_office_keycap", "office_hero/hero_office_notebook",
]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var clear_color: Color = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
	if not _expect(clear_color.is_equal_approx(Color("111316")), "the viewport outside room overscan must match the intended dark void"):
		return
	var points := PackedVector2Array([Vector2(-512, -256), Vector2(512, -256), Vector2(512, 256), Vector2(-512, 256)])
	for theme in [&"kitchen", &"workshop", &"office"]:
		var spec: Dictionary = BUILDER.LAYOUTS[theme].duplicate(true)
		if not _expect(spec["track_texture"] == spec["floor_texture"] and spec["track_world_tile_size"] == spec["floor_tile_world_size"], "route and room must share one continuous material scale"):
			return
		var world := Node2D.new()
		root.add_child(world)
		spec["seed_obstacles"] = false
		BUILDER._add_textured_polygon(world, "Ground", points, spec["floor_texture"], Color.WHITE, -20, spec["floor_tile_world_size"])
		BUILDER._build_island_prop(world, spec, points, points, points)
		var island := world.get_node("IslandProp") as Polygon2D
		if not _expect(island.texture.resource_path == spec["island_material_texture"] and island.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED, "islands should use a repeatable material, not a stretched object image"):
			return
		for index in points.size():
			var expected: Vector2 = points[index] / spec["island_material_world_size"] * island.texture.get_size()
			if not _expect(island.uv[index].is_equal_approx(expected), "island material must retain world-space alignment"):
				return
		BUILDER._add_wall_segment(world, "Wall", Vector2.ZERO, 2200.0, 0.0, spec["edge_texture"])
		var wall := world.get_node("Wall")
		var side := wall.get_node("SideStrip") as Sprite2D
		var side_size := side.get_rect().size * side.scale
		if not _expect(side_size.is_equal_approx(Vector2(2260, 34)), "wall side art must cover its entire span regardless of texture resolution"):
			return
		for strip: Sprite2D in wall.find_children("EdgeStrip*", "Sprite2D", false, false):
			if not _expect(is_equal_approx(strip.get_rect().size.y * strip.scale.y, 50.0), "edge textures must not become oversized rectangles when their dimensions change"):
				return
		world.free()
	for asset: String in HERO_ASSETS:
		var texture := load("res://assets/textures/%s.png" % asset) as Texture2D
		if not _expect(texture != null, "hero art must load"):
			return
		var image := texture.get_image()
		var used := image.get_used_rect()
		if not _expect(image.get_size() == Vector2i(512, 512) and used.has_area() and used.position.x >= 16 and used.position.y >= 16 and used.end.x <= 496 and used.end.y <= 496, "hero sprites need normalized resolution and clean padding"):
			return
		if not asset.ends_with("wrench") and not _expect(image.get_pixel(256, 256).a > 0.95, "%s keying must preserve the solid interior, not only leave an outline" % asset):
			return
		for corner in [Vector2i.ZERO, Vector2i(511, 0), Vector2i(0, 511), Vector2i(511, 511)]:
			if not _expect(image.get_pixelv(corner).a == 0, "hero art must not carry an opaque background rectangle"):
				return
	print("WORLD_THEME_ART_TEST PASS three_material_sets_and_six_prepared_props")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("WORLD_THEME_ART_TEST FAIL: " + message)
	quit(1)
	return false
