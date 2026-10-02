extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const VISUAL_ROLE := preload("res://scripts/race/generated_world_visual_role.gd")
const SAMPLES: Array[Dictionary] = [
	{"theme": &"kitchen", "room": &"classic", "seed": 0},
	{"theme": &"workshop", "room": &"tall", "seed": 1},
	{"theme": &"office", "room": &"square", "seed": 2},
]

var _solid_visuals := 0
var _flat_visuals := 0


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not _expect(
		VISUAL_ROLE.VALUES == [VISUAL_ROLE.SOLID, VISUAL_ROLE.FLAT]
		and BUILDER.VISUAL_ROLE_SOLID == VISUAL_ROLE.SOLID
		and BUILDER.VISUAL_ROLE_FLAT == VISUAL_ROLE.FLAT,
		"generated world roles should expose one authoritative SOLID/FLAT vocabulary"
	):
		return
	for sample: Dictionary in SAMPLES:
		var built: Dictionary = BUILDER.build_packed(sample["theme"], sample["room"], sample["seed"])
		if not _expect(built.get("scene") is PackedScene, "%s generated sample should build" % sample["theme"]):
			return
		var track := (built["scene"] as PackedScene).instantiate() as Node2D
		root.add_child(track)
		if not _check_generated_roles(track, sample["theme"]):
			return
		if not _check_finish(track, sample["theme"]):
			return

		track.free()

	print("GENERATED_VISUAL_ROLE_TEST PASS samples=%d solid=%d flat=%d" % [SAMPLES.size(), _solid_visuals, _flat_visuals])
	quit(0)


func _check_generated_roles(track: Node2D, theme: StringName) -> bool:
	for node: Node in track.find_children("*", "", true, false):
		var collision_contract := StringName(node.get_meta("collision_contract", &""))
		if collision_contract == BUILDER.COLLISION_SOLID and not _expect(VISUAL_ROLE.read(node) == VISUAL_ROLE.SOLID, "%s SOLID collision metadata should agree with visual_role on %s" % [theme, track.get_path_to(node)]):
			return false
		if collision_contract == BUILDER.COLLISION_FLAT and not _expect(VISUAL_ROLE.read(node) == VISUAL_ROLE.FLAT, "%s FLAT collision metadata should agree with visual_role on %s" % [theme, track.get_path_to(node)]):
			return false
		if node is StaticBody2D and _owns_collision(node) and not _expect(VISUAL_ROLE.read(node) == VISUAL_ROLE.SOLID, "%s collision-bearing body %s should declare SOLID" % [theme, track.get_path_to(node)]):
			return false
		if not _is_visible_world_drawing(node):
			continue
		if not _expect(VISUAL_ROLE.is_valid(node), "%s visible generated drawing %s should declare a valid visual role" % [theme, track.get_path_to(node)]):
			return false
		match VISUAL_ROLE.read(node):
			VISUAL_ROLE.SOLID:
				_solid_visuals += 1
			VISUAL_ROLE.FLAT:
				_flat_visuals += 1
	return _expect(_solid_visuals > 0 and _flat_visuals > 0, "%s should exercise both physical and drive-over world art" % theme)


func _check_finish(track: Node2D, theme: StringName) -> bool:
	var finish := track.get_node("Checkpoint0Finish") as Node2D
	var track_surface := track.get_node("TrackSurface") as Line2D
	var tangent := (track_surface.points[1] - track_surface.points[track_surface.points.size() - 1]).normalized()
	var normal := tangent.rotated(PI * 0.5)
	var along_min := INF
	var along_max := -INF
	var across_min := INF
	var across_max := -INF
	var cells := 0
	var white_cells := 0
	var black_cells := 0
	for node: Node in track.get_children():
		if node is not Polygon2D or not String(node.name).begins_with("StartFinish"):
			continue
		var cell := node as Polygon2D
		cells += 1
		white_cells += 1 if StringName(cell.get_meta("checker_color", &"")) == &"White" else 0
		black_cells += 1 if StringName(cell.get_meta("checker_color", &"")) == &"Black" else 0
		if not _expect(VISUAL_ROLE.read(cell) == VISUAL_ROLE.FLAT and StringName(cell.get_meta("flat_class", &"")) == &"checker", "%s checker cells should be explicitly FLAT" % theme):
			return false
		for point: Vector2 in cell.polygon:
			var local_point := track.to_local(cell.to_global(point)) - finish.position
			along_min = minf(along_min, local_point.dot(tangent))
			along_max = maxf(along_max, local_point.dot(tangent))
			across_min = minf(across_min, local_point.dot(normal))
			across_max = maxf(across_max, local_point.dot(normal))
	if not _expect(cells == 12 and white_cells == 6 and black_cells == 6, "%s finish should use twelve simple alternating checker cells" % theme):
		return false
	if not _expect(across_max - across_min >= BUILDER.HALF_WIDTH * 2.0 - 0.5 and along_max - along_min >= 70.0, "%s checker should cover the full corridor with a readable finish depth" % theme):
		return false
	if not _expect(track.find_children("BannerBlock*", "Polygon2D", true, false).is_empty(), "%s generated finish should not retain a one-sided start-only banner" % theme):
		return false

	var left := track.get_node("GatePosts/Gate00Left") as StaticBody2D
	var right := track.get_node("GatePosts/Gate00Right") as StaticBody2D
	var left_offset := left.position - finish.position
	var right_offset := right.position - finish.position
	if not _expect(left_offset.length() > BUILDER.HALF_WIDTH and left_offset.is_equal_approx(-right_offset), "%s finish landmarks should be symmetric around the gate" % theme):
		return false
	for landmark: StaticBody2D in [left, right]:
		var sprite := landmark.get_node("Sprite") as Sprite2D
		var visual_size := BUILDER._texture_opaque_rect(sprite.texture).size * sprite.scale.abs()
		if not _expect(
			bool(landmark.get_meta("finish_landmark", false))
			and landmark.get_meta("race_directions", PackedStringArray()) == PackedStringArray(["forward", "reverse"])
			and VISUAL_ROLE.read(landmark) == VISUAL_ROLE.SOLID
			and is_equal_approx(maxf(visual_size.x, visual_size.y), BUILDER.PROP_SCALE.length_for(sprite.texture.resource_path, -1.0)),
			"%s paired finish posts should be bidirectional SOLID landmarks at their real prop size" % theme
		):
			return false
	var dramatic := track.get_node("GeneratedMoments/DramaticFinish")
	return _expect(
		bool(dramatic.get_meta("bidirectional_landmarks", false))
		and float(dramatic.get_meta("corridor_span", 0.0)) == BUILDER.HALF_WIDTH * 2.0
		and dramatic.get_meta("finish_landmark_left") == NodePath("../../GatePosts/Gate00Left")
		and dramatic.get_meta("finish_landmark_right") == NodePath("../../GatePosts/Gate00Right"),
		"%s dramatic finish should publish its full-width symmetric landmarks" % theme
	)


func _is_visible_world_drawing(node: Node) -> bool:
	if node is not CanvasItem or not (node as CanvasItem).visible:
		return false
	if node is Sprite2D:
		return (node as Sprite2D).texture != null
	if node is Polygon2D:
		return not (node as Polygon2D).polygon.is_empty()
	if node is Line2D:
		return not (node as Line2D).points.is_empty()
	return false


func _owns_collision(node: Node) -> bool:
	return not node.find_children("*", "CollisionShape2D", true, false).is_empty() or not node.find_children("*", "CollisionPolygon2D", true, false).is_empty()


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("GENERATED_VISUAL_ROLE_TEST FAIL: " + message)
	quit(1)
	return false
