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
	var cel_outputs := 0
	for definition: Dictionary in SCALE.definitions:
		if not _expect(float(definition["length_mm"]) > 0.0, "every prop needs a positive physical dimension"):
			return
		if not _expect(String(definition.get("style", "cel")) == "cel", "every environment prop must use the cel-illustrated preparation"):
			return
		cel_outputs += (definition["outputs"] as Array).size()
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
	if not _expect(cel_outputs >= 150, "the cel-illustrated pass must cover the complete environment manifest"):
		return
	for theme: StringName in [&"kitchen", &"workshop", &"office"]:
		var layout: Dictionary = BUILDER.LAYOUTS[theme]
		var boundary: Dictionary = layout["generated_boundary"]
		if not _expect((layout["ambient_props"] as Array).size() >= 8 and (boundary["sections"] as Array).size() >= 8, "%s dressing and boundaries must draw from broad prop families" % theme):
			return
		for story: Dictionary in BUILDER.ROOM_COMPOSITIONS[theme]:
			var object_line: Dictionary = story["object_line"]
			var delimiter: Dictionary = story["delimiter"]
			if not _expect((object_line.get("assets", []) as Array).size() >= 3 and (delimiter.get("assets", []) as Array).size() >= 3, "every %s story must vary repeated trackside props" % theme):
				return
	for sample_path: String in ["res://assets/textures/kitchen_hero/hero_kitchen_mug.png", "res://assets/textures/workshop_hero/hero_workshop_toolbox.png", "res://assets/textures/office_hero/hero_office_keyboard.png"]:
		if not _expect(_is_rich_cel_sprite(sample_path), "cel-illustrated sprites must keep anti-aliased edges and material color depth: " + sample_path):
			return
	for sample: Array in [[&"kitchen", &"classic", 0], [&"kitchen", &"tall", 1], [&"workshop", &"square", 51940], [&"office", &"el", 7]]:
		var packed: PackedScene = BUILDER.build_packed(sample[0], sample[1], sample[2])["scene"]
		var track := packed.instantiate() as Node2D
		root.add_child(track)
		var object_line := track.get_node("GeneratedMoments/ObjectLine")
		var live_variants := {}
		for prop: Node in object_line.get_children():
			live_variants[String(prop.get_meta("asset_path", ""))] = true
		if not _expect(live_variants.size() >= 3, "a live %s object line must cycle through several prop variants" % sample[0]):
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


func _is_rich_cel_sprite(path: String) -> bool:
	var image := (load(path) as Texture2D).get_image()
	image.convert(Image.FORMAT_RGBA8)
	var data := image.get_data()
	var colors := {}
	var has_soft_edge := false
	for index in range(0, data.size(), 4):
		var alpha := data[index + 3]
		if alpha > 0 and alpha < 255:
			has_soft_edge = true
		if alpha >= 128 and colors.size() <= 24:
			colors[Vector3i(data[index], data[index + 1], data[index + 2])] = true
	return has_soft_edge and colors.size() > 24


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("WORLD_PROP_SCALE_TEST FAIL: " + message)
	quit(1)
	return false
