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
	for definition: Dictionary in SCALE.definitions:
		if not _expect(float(definition["length_mm"]) > 0.0, "every prop needs a positive physical dimension"):
			return
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
	for sample: Array in [[&"kitchen", &"classic", 0], [&"kitchen", &"tall", 1], [&"workshop", &"square", 51940], [&"office", &"el", 7]]:
		var packed: PackedScene = BUILDER.build_packed(sample[0], sample[1], sample[2])["scene"]
		var track := packed.instantiate() as Node2D
		root.add_child(track)
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
