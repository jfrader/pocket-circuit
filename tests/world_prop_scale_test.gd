extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const SCALE := preload("res://scripts/race/world_prop_scale.gd")
var _checked := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _expect(SCALE.length_for("kitchen_spoon.png", 0) == 180.0 and SCALE.length_for("workshop_nail_micro.png", 0) == 40.0, "a tablespoon must be substantially longer than a small nail"):
		return
	if not _expect(SCALE.length_for("hero_office_keyboard.png", 0) > SCALE.length_for("hero_office_keycap.png", 0) * 20.0, "a full keyboard cannot be comparable to a loose keycap"):
		return
	var paths := {}
	var painted_kitchen_outputs := 0
	for definition: Dictionary in SCALE.definitions:
		if not _expect(float(definition["length_mm"]) > 0.0, "every prop needs a positive physical dimension"):
			return
		if String(definition.get("style", "")) == "painted" and String(definition["sheet"]).contains("kitchen"):
			painted_kitchen_outputs += (definition["outputs"] as Array).size()
		for output: String in definition["outputs"]:
			var path := "res://assets/textures/" + output
			if not _expect(not paths.has(path) and ResourceLoader.exists(path), "manifest outputs must be unique and loadable: " + path):
				return
			paths[path] = true
			var texture := load(path) as Texture2D
			var bounds := BUILDER._texture_opaque_rect(texture)
			var scale := SCALE.sprite_scale(texture, bounds, -1.0)
			if not _expect(is_equal_approx(maxf(bounds.size.x, bounds.size.y) * scale, float(definition["length_mm"])), "padding must not change physical size: " + path):
				return
	if not _expect(painted_kitchen_outputs >= 50, "the Kitchen pilot must include painted base props plus meaningful family variants"):
		return
	var kitchen_layout: Dictionary = BUILDER.LAYOUTS[&"kitchen"]
	var kitchen_boundary: Dictionary = kitchen_layout["generated_boundary"]
	if not _expect((kitchen_layout["ambient_props"] as Array).size() >= 10 and (kitchen_boundary["sections"] as Array).size() >= 10, "Kitchen dressing and boundaries must draw from broad prop families"):
		return
	for story: Dictionary in BUILDER.ROOM_COMPOSITIONS[&"kitchen"]:
		var object_line: Dictionary = story["object_line"]
		var delimiter: Dictionary = story["delimiter"]
		if not _expect((object_line.get("assets", []) as Array).size() >= 3 and (delimiter.get("assets", []) as Array).size() >= 2, "every Kitchen story must vary repeated trackside props"):
			return
	var painted_sample := (load("res://assets/textures/kitchen_hero/hero_kitchen_mug.png") as Texture2D).get_image()
	painted_sample.convert(Image.FORMAT_RGBA8)
	var painted_data := painted_sample.get_data()
	var painted_colors := {}
	var has_soft_edge := false
	for index in range(0, painted_data.size(), 4):
		var alpha := painted_data[index + 3]
		if alpha > 0 and alpha < 255:
			has_soft_edge = true
		if alpha >= 128 and painted_colors.size() <= 24:
			painted_colors[Vector3i(painted_data[index], painted_data[index + 1], painted_data[index + 2])] = true
	if not _expect(has_soft_edge and painted_colors.size() > 24, "painted Kitchen sprites must keep anti-aliased edges and material color depth"):
		return
	for sample: Array in [[&"kitchen", &"classic", 0], [&"kitchen", &"tall", 1], [&"workshop", &"square", 51940], [&"office", &"el", 7]]:
		var packed: PackedScene = BUILDER.build_packed(sample[0], sample[1], sample[2])["scene"]
		var track := packed.instantiate() as Node2D
		root.add_child(track)
		if sample[0] == &"kitchen":
			var object_line := track.get_node("GeneratedMoments/ObjectLine")
			var live_variants := {}
			for prop: Node in object_line.get_children():
				live_variants[String(prop.get_meta("asset_path", ""))] = true
			if not _expect(live_variants.size() >= 3, "a live Kitchen object line must cycle through several prop variants"):
				track.free()
				return
		for sprite: Sprite2D in track.find_children("*", "Sprite2D", true, false):
			if BUILDER.VISUAL_ROLE_CONTRACT.read(sprite) != BUILDER.VISUAL_ROLE_SOLID or sprite.texture == null:
				continue
			var expected := SCALE.length_for(sprite.texture.resource_path, -1.0)
			if expected < 0.0:
				continue
			var size := BUILDER._texture_opaque_rect(sprite.texture).size * sprite.scale.abs()
			if not _expect(absf(sprite.scale.x - sprite.scale.y) < 0.0001 and absf(maxf(size.x, size.y) - expected) < 1.0, "all roles must preserve aspect and physical size: %s %s actual=%s expected=%s" % [sprite.get_path(), sprite.texture.resource_path, size, expected]):
				track.free()
				return
			_checked += 1
		var boundary := track.get_node("GeneratedOuterBoundaryVisuals")
		var sections: Array[Node2D] = []
		for child: Node2D in boundary.get_children():
			if child.has_meta("footprint_size"):
				sections.append(child)
		for index in sections.size():
			var a := sections[index]
			var a_polygon := TrackBuilderBoundary._footprint_polygon(a.position, a.get_meta("footprint_size"), a.rotation)
			for other_index in range(index + 1, sections.size()):
				var b := sections[other_index]
				var b_polygon := TrackBuilderBoundary._footprint_polygon(b.position, b.get_meta("footprint_size"), b.rotation)
				if not _expect(Geometry2D.intersect_polygons(a_polygon, b_polygon).is_empty(), "physical rails must not overlap their neighbors"):
					track.free()
					return
		track.free()
	if not _expect(_checked >= 200, "scale regression must inspect live generated scenery, not only manifest data"):
		return
	print("WORLD_PROP_SCALE_TEST PASS checked=%d assets=%d" % [_checked, paths.size()])
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("WORLD_PROP_SCALE_TEST FAIL: " + message)
	quit(1)
	return false
