extends SceneTree

const CORE := preload("res://scripts/race/track_builder_core.gd")
const ART := preload("res://scripts/race/world_environment_art.gd")
const CATALOG := preload("res://scripts/race/world_environment_catalog.gd")

var failures: Array[String] = []
var contact_material: Material

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var props := 0
	for asset: Dictionary in CATALOG.all_assets():
		if asset.get("kind", "prop") != "prop" or asset["collision"] == "flat":
			continue
		var container := Node2D.new()
		container.rotation = 0.3
		for angle: float in [0.0, PI * 0.5, PI]:
			var prop := ART.render_prop(container, asset, {"role": "support", "position": Vector2.ZERO, "rotation": angle})
			var sprite := prop.get_node("Sprite") as Sprite2D
			var shadow := prop.get_node_or_null("ContactShadow") as Sprite2D
			if asset.get("shadow", "none") == "none":
				_check(shadow == null, "%s forbids a generated shadow" % asset["id"])
				continue
			_check(shadow != null, "%s needs a contact shadow" % asset["id"])
			if shadow == null:
				continue
			var offset := (shadow.position - sprite.position).rotated(angle + container.rotation)
			_check(offset.length() <= 3.01, "%s contact shadow floats %.2f mm from its art" % [asset["id"], offset.length()])
			_check(offset.normalized().dot(CORE.SHADOW_DIRECTION.normalized()) > 0.99, "%s shadow must follow room lighting, not prop rotation" % asset["id"])
			_check(shadow.texture == sprite.texture and shadow.scale == sprite.scale and shadow.rotation == sprite.rotation, "%s shadow must follow the visible silhouette, not a generic card" % asset["id"])
			if contact_material == null:
				contact_material = shadow.material
			_check(contact_material is ShaderMaterial and shadow.material == contact_material, "contact shadows must share one material, not allocate one per prop")
			_check(prop.get_node_or_null("AssetCollision") != null, "%s must retain its physical collision" % asset["id"])
		props += 1
		container.free()
	var paths := {}
	for theme: StringName in CORE.LAYOUTS:
		for patch: Dictionary in CORE.LAYOUTS[theme].get("grip_patches", []):
			paths[patch["decal"]] = true
		for story: Dictionary in CORE.STORY_KITS[theme]:
			for surface: Dictionary in story["surfaces"]:
				paths[surface["decal"]] = true
	for path: String in paths:
		for width: float in [52.0, 92.0, 184.0]:
			_check_grip(path, width)
		if DisplayServer.get_name() != "headless":
			await _check_grip_pixels(path)
	_check(props > 0 and paths.size() > 0, "the regression must exercise actual catalog assets")
	_check_grip_exclusions()
	if not failures.is_empty():
		for message: String in failures:
			printerr("ENVIRONMENT_GROUNDING_TEST FAIL: ", message)
		quit(1)
		return
	print("ENVIRONMENT_GROUNDING_TEST PASS props=", props, " grip_assets=", paths.size())
	quit(0)

func _check_grip(path: String, width: float) -> void:
	var container := Node2D.new()
	var polygon := PackedVector2Array([Vector2.ZERO, Vector2(240, 0), Vector2(240, width), Vector2(0, width)])
	ART._draw_grip_surface(container, "SurfaceRegion", CATALOG.for_path(path), polygon, 6)
	var region := container.get_node("SurfaceRegion") as Node2D
	_check(container.find_children("*", "Polygon2D", true, false).is_empty(), "grip artwork must not draw a zone-wide tinted underlay")
	var material := region.material as ShaderMaterial
	var boundary: PackedVector2Array = material.get_shader_parameter("boundary")
	_check(boundary.slice(0, int(material.get_shader_parameter("boundary_count"))) == polygon, "grip artwork must not change the authoritative zone")
	var stamps: Array[Dictionary] = []
	for sprite: Sprite2D in region.get_children():
		var used := CORE._texture_opaque_rect(sprite.texture)
		var local_center := (used.get_center() - sprite.texture.get_size() * 0.5) * sprite.scale
		var center := sprite.position + local_center.rotated(sprite.rotation)
		var radius := (used.size * sprite.scale).length() * 0.5
		_check(center.x >= radius and center.y >= radius and center.x + radius <= 240.01 and center.y + radius <= width + 0.01, "%s artwork must fit the grip zone instead of being sliced into a rectangle (%s mm)" % [path.get_file(), width])
		for other: Dictionary in stamps:
			_check(center.distance_to(other["center"]) >= radius + float(other["radius"]) - 0.01, "%s repeated stamps must retain transparent gaps" % path.get_file())
		stamps.append({"center": center, "radius": radius})
	_check(not stamps.is_empty(), "%s grip cue must remain visible" % path.get_file())
	var replay := Node2D.new()
	ART._draw_grip_surface(replay, "SurfaceRegion", CATALOG.for_path(path), polygon, 6)
	var replay_region := replay.get_node("SurfaceRegion")
	_check(region.get_child_count() == replay_region.get_child_count(), "same grip seed must retain its stamp count")
	for index in region.get_child_count():
		_check((region.get_child(index) as Node2D).transform == (replay_region.get_child(index) as Node2D).transform, "same grip seed must retain its stamp transforms")
	replay.free()
	container.free()

func _check_grip_pixels(path: String) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 128)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var polygon := PackedVector2Array([Vector2(8, 18), Vector2(248, 18), Vector2(248, 110), Vector2(8, 110)])
	var world := Node2D.new()
	viewport.add_child(world)
	ART._draw_grip_surface(world, "SurfaceRegion", CATALOG.for_path(path), polygon, 6)
	root.add_child(viewport)
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var visible := 0
	var bare_pixels := 0
	var tinted_bare_pixels := 0
	var sprites := world.find_children("*", "Sprite2D", true, false)
	for y in range(18, 110):
		for x in range(8, 248):
			if image.get_pixel(x, y).a > 0.15:
				visible += 1
			var covered := false
			for sprite: Sprite2D in sprites:
				if sprite.get_rect().has_point(sprite.to_local(Vector2(x + 0.5, y + 0.5))):
					covered = true
					break
			if not covered:
				bare_pixels += 1
				if image.get_pixel(x, y).a > 1.0 / 255.0:
					tinted_bare_pixels += 1
	_check(bare_pixels > 100 and tinted_bare_pixels == 0, "%s must leave bare track between debris unchanged; tinted gap pixels=%d" % [path.get_file(), tinted_bare_pixels])
	var coverage := float(visible) / (240.0 * 92.0)
	_check(coverage > 0.01 and coverage < 0.5, "%s rendered grip cue must be visible with open gaps, not a filled card (coverage %.3f)" % [path.get_file(), coverage])
	print("GRIP_PIXEL_COVERAGE ", path, " ", coverage)
	viewport.free()

func _check_grip_exclusions() -> void:
	var polygon := PackedVector2Array([Vector2.ZERO, Vector2(240, 0), Vector2(240, 92), Vector2(0, 92)])
	var post := PackedVector2Array([Vector2(105, 0), Vector2(145, 0), Vector2(145, 70), Vector2(105, 70)])
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var stamps := ART._grip_stamp_layout(polygon, 40.0, 6, rng, [post])
	_check(not stamps.is_empty(), "grip art must use the remaining driveable area beside a reserved solid")
	for stamp: Dictionary in stamps:
		var point: Vector2 = stamp["position"]
		_check(not Geometry2D.is_point_in_polygon(point, post), "grip art must not sit on a reserved solid")
		for edge in post.size():
			var closest := Geometry2D.get_closest_point_to_segment(point, post[edge], post[(edge + 1) % post.size()])
			_check(point.distance_to(closest) >= float(stamp["radius"]), "the whole grip stamp must clear reserved collision, not just its center")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
