extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const VEHICLE_SCENERY_MASK := 2 | 4 | 16
const COVERAGE_MINIMUM := 0.90
const MICRO_COVERAGE_MINIMUM := 0.50
const MAX_ALPHA_SAMPLES := 96
const CONTACT_MARGIN_TOLERANCE := 6.0
const CONTACT_MARGIN_HARD_LIMIT := 8.0
const CENTER_OFFSET_TOLERANCE := 2.0
const THIN_ALPHA_THRESHOLD := 8.0
const MARGIN_CLASSES := {
	&"rail": "Rails",
	&"giant": "Giants",
	&"gate_post": "Gate posts",
	&"obstacle": "Obstacles",
	&"apron_prop": "Story props",
	&"boundary_prop": "Story props",
	&"corner_giant": "Story props",
	&"island_prop": "Story props",
}
const SAMPLES: Array[Dictionary] = [
	{"theme": &"kitchen", "room": &"classic", "seed": 0},
	{"theme": &"kitchen", "room": &"wide", "seed": 9},
	{"theme": &"workshop", "room": &"tall", "seed": 1},
	{"theme": &"workshop", "room": &"long", "seed": 6},
	{"theme": &"office", "room": &"square", "seed": 2},
	{"theme": &"office", "room": &"el", "seed": 8},
]

var _solid_bodies_checked := 0
var _solid_probe_points_checked := 0
var _flat_visuals_checked := 0
var _opaque_point_cache: Dictionary = {}
var _margin_stats: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not await _check_every_giant_asset():
		return
	if not await _check_every_obstacle_asset():
		return
	var themes := {}
	var families := {}
	for sample_index in SAMPLES.size():
		var sample := SAMPLES[sample_index]
		var built: Dictionary = BUILDER.build_packed(sample["theme"], sample["room"], sample["seed"])
		if not _expect(built.get("scene") is PackedScene, "%s/%s/%d should build" % [sample["theme"], sample["room"], sample["seed"]]):
			return
		var track := (built["scene"] as PackedScene).instantiate() as Node2D
		root.add_child(track)
		await physics_frame
		themes[sample["theme"]] = true
		families[StringName(track.get_meta("family", &""))] = true
		if not _check_solid_contract(track, sample_index < 3):
			return
		if not _check_flat_contract(track, sample_index < 3):
			return
		track.queue_free()
		await process_frame
	if not _expect(themes.size() == 3 and families.size() >= 3, "six samples should span all themes and multiple route families (families=%s)" % str(families.keys())):
		return
	if not _check_margin_statistics():
		return
	print("ASSET_COLLISION_INTEGRITY_TEST PASS builds=%d families=%d solid_bodies=%d probe_points=%d flat_visuals=%d" % [SAMPLES.size(), families.size(), _solid_bodies_checked, _solid_probe_points_checked, _flat_visuals_checked])
	quit(0)


func _check_every_giant_asset() -> bool:
	var fixture := Node2D.new()
	fixture.name = "EveryGiantAssetFixture"
	root.add_child(fixture)
	var index := 0
	var registered := {}
	for theme: StringName in [&"kitchen", &"workshop", &"office"]:
		var theme_assets: Array = BUILDER.LAYOUTS[theme]["giants"].duplicate()
		for story: Dictionary in BUILDER.STORY_KITS[theme]:
			theme_assets.append_array(story.get("giants", []))
		for asset_path: String in theme_assets:
			if registered.has(asset_path):
				continue
			registered[asset_path] = true
			var entry: Dictionary = BUILDER.PROP_SHAPES.get(asset_path.get_file(), {})
			if not _expect(bool(entry.get("solid", false)), "%s should explicitly declare solid=true" % asset_path):
				return false
			var texture := load(asset_path) as Texture2D
			if not _expect(texture != null, "%s should load for collision verification" % asset_path):
				return false
			var used := BUILDER._texture_opaque_rect(texture)
			var sprite_scale := 360.0 / maxf(used.size.x, used.size.y)
			var footprint := BUILDER._texture_collision_footprint(texture, StringName(entry.get("shape", &"rect")))
			var footprint_center: Vector2 = footprint["center"]
			var visual_offset := (footprint_center - Vector2(texture.get_width(), texture.get_height()) * 0.5) * sprite_scale
			var landmark := Node2D.new()
			landmark.name = asset_path.get_file().get_basename()
			landmark.position = Vector2(float(index % 6) * 520.0, float(index / 6) * 520.0)
			fixture.add_child(landmark)
			var sprite := Sprite2D.new()
			sprite.name = "Sprite"
			sprite.texture = texture
			sprite.position = -visual_offset
			sprite.scale = Vector2.ONE * sprite_scale
			BUILDER._mark_solid_visual(sprite, asset_path, &"giant")
			landmark.add_child(sprite)
			var body := StaticBody2D.new()
			body.name = "GiantBody"
			body.collision_layer = 4 | 16
			BUILDER._mark_solid_body(body, asset_path, &"giant")
			landmark.add_child(body)
			var _offset := BUILDER._add_giant_collision(body, asset_path, sprite_scale)
			index += 1
	await physics_frame
	for node: Node in fixture.find_children("GiantBody", "StaticBody2D", true, false):
		var body := node as StaticBody2D
		var sprite := body.get_parent().get_node("Sprite") as Sprite2D
		if not _check_sprite_coverage(body, sprite):
			return false
		var probes: PackedVector2Array = body.get_meta("collision_probe_points", PackedVector2Array())
		if not _expect(probes.size() == 3, "%s should expose center and two extremity probes" % String(body.get_meta("asset_path", ""))):
			return false
		for point: Vector2 in probes:
			if not _expect(_physics_point_hits_body(body.to_global(point), body), "%s should collide at center/end probe %s" % [String(body.get_meta("asset_path", "")), str(point)]):
				return false
			_solid_probe_points_checked += 1
	fixture.queue_free()
	await process_frame
	return _expect(index == registered.size() and index > 0, "every distinct theme/story giant asset should receive direct collider verification")


func _check_every_obstacle_asset() -> bool:
	var fixture := Node2D.new()
	fixture.name = "EveryObstacleAssetFixture"
	root.add_child(fixture)
	var index := 0
	var seen := {}
	for theme: StringName in [&"kitchen", &"workshop", &"office"]:
		var obstacles: Dictionary = BUILDER.LAYOUTS[theme]["obstacles"]
		for obstacle_name: String in obstacles:
			var data: Dictionary = obstacles[obstacle_name]
			var asset_path := String(data["tex"])
			var key := "%s:%s" % [theme, asset_path]
			if seen.has(key):
				continue
			seen[key] = true
			BUILDER._add_obstacle(
				fixture,
				"%s_%s" % [theme, obstacle_name],
				Vector2(float(index % 6) * 180.0, float(index / 6) * 180.0),
				float(data["r"]),
				asset_path
			)
			index += 1
	await physics_frame
	for node: Node in fixture.find_children("*", "StaticBody2D", true, false):
		var body := node as StaticBody2D
		var sprite := _solid_sprite_for_body(body)
		if not _expect(sprite != null and _check_sprite_coverage(body, sprite), "%s obstacle fixture should expose aligned solid art" % body.name):
			return false
	fixture.queue_free()
	await process_frame
	return _expect(index >= 20, "all theme obstacle assets should receive direct collider verification")


func _check_solid_contract(track: Node2D, run_physics_probes: bool) -> bool:
	for node: Node in track.find_children("*", "StaticBody2D", true, false):
		var body := node as StaticBody2D
		if StringName(body.get_meta("collision_contract", &"")) != BUILDER.COLLISION_SOLID:
			continue
		_solid_bodies_checked += 1
		var collisions := body.find_children("*", "CollisionShape2D", true, false)
		collisions.append_array(body.find_children("*", "CollisionPolygon2D", true, false))
		if not _expect(not collisions.is_empty(), "%s SOLID body must own collision" % str(track.get_path_to(body))):
			return false
		if not _expect((body.collision_layer & VEHICLE_SCENERY_MASK) != 0, "%s SOLID body must be visible to the vehicle/AI mask" % str(track.get_path_to(body))):
			return false
		var sprite := _solid_sprite_for_body(body)
		if sprite != null and not _check_sprite_coverage(body, sprite):
			return false
		var asset_path := String(body.get_meta("asset_path", ""))
		if run_physics_probes and not asset_path.is_empty():
			var probe_points: PackedVector2Array = body.get_meta("collision_probe_points", PackedVector2Array())
			if not _expect(probe_points.size() >= 3, "%s SOLID asset should publish center and end probes" % str(track.get_path_to(body))):
				return false
			for local_point: Vector2 in probe_points:
				if not _physics_point_hits_body(body.to_global(local_point), body):
					return _expect(false, "%s SOLID asset should collide at local probe %s" % [str(track.get_path_to(body)), str(local_point)])
				_solid_probe_points_checked += 1
	return true


func _solid_sprite_for_body(body: StaticBody2D) -> Sprite2D:
	for child: Node in body.get_children():
		if child is Sprite2D and StringName(child.get_meta("collision_contract", &"")) == BUILDER.COLLISION_SOLID:
			return child as Sprite2D
	var parent := body.get_parent()
	if parent:
		for sibling: Node in parent.get_children():
			if sibling is Sprite2D and StringName(sibling.get_meta("collision_contract", &"")) == BUILDER.COLLISION_SOLID and String(sibling.get_meta("asset_path", "")) == String(body.get_meta("asset_path", "")):
				return sibling as Sprite2D
	return null


func _check_sprite_coverage(body: StaticBody2D, sprite: Sprite2D) -> bool:
	var collisions := _body_collision_shapes(body)
	if not _expect(not collisions.is_empty(), "%s SOLID sprite should have a footprint shape" % str(body.get_path())):
		return false
	var visual_bounds := _sprite_opaque_bounds_in_body(sprite, body)
	if not _expect(visual_bounds.size.x > 0.0 and visual_bounds.size.y > 0.0, "%s should expose a visible alpha footprint" % str(sprite.get_path())):
		return false
	for collision: CollisionShape2D in collisions:
		if not collision.shape is CircleShape2D and not collision.shape is RectangleShape2D and not collision.shape is CapsuleShape2D and not collision.shape is ConvexPolygonShape2D:
			return _expect(false, "%s uses an unsupported solid sprite shape %s" % [str(body.get_path()), collision.shape.get_class()])
	if not _check_alpha_samples_inside(body, sprite, collisions, visual_bounds):
		return false
	return _check_bidirectional_alignment(body, sprite, collisions, visual_bounds)


func _asset_label(body: StaticBody2D, sprite: Sprite2D) -> String:
	return "%s [%s]" % [str(sprite.get_path()), String(body.get_meta("asset_path", sprite.get_meta("asset_path", "unknown asset")))]


func _body_collision_shapes(body: StaticBody2D) -> Array[CollisionShape2D]:
	var result: Array[CollisionShape2D] = []
	for child: Node in body.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).shape != null:
			result.append(child as CollisionShape2D)
	return result


func _sprite_opaque_bounds_in_body(sprite: Sprite2D, body: StaticBody2D) -> Rect2:
	var texture := sprite.texture
	if texture == null:
		return Rect2()
	var image := texture.get_image()
	var used := image.get_used_rect() if image != null and not image.is_empty() else Rect2i(Vector2i.ZERO, Vector2i(texture.get_width(), texture.get_height()))
	var canvas_half := Vector2(texture.get_width(), texture.get_height()) * 0.5
	var from := Vector2(used.position) - canvas_half
	var to := from + Vector2(used.size)
	var points := PackedVector2Array([
		body.to_local(sprite.to_global(Vector2(from.x, from.y))),
		body.to_local(sprite.to_global(Vector2(to.x, from.y))),
		body.to_local(sprite.to_global(Vector2(to.x, to.y))),
		body.to_local(sprite.to_global(Vector2(from.x, to.y))),
	])
	return _points_bounds(points)


func _points_bounds(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


## Sample the alpha boundary in body-local space. Coverage prevents colliders
## from missing visible art; directional support below independently prevents
## oversized collision in transparent pixels.
func _check_alpha_samples_inside(body: StaticBody2D, sprite: Sprite2D, collisions: Array[CollisionShape2D], visual_bounds: Rect2) -> bool:
	var asset_label := _asset_label(body, sprite)
	var candidates := _sprite_alpha_boundary_points(body, sprite)
	if candidates.is_empty():
		return _expect(false, "%s produced no alpha samples for coverage" % asset_label)
	var samples := candidates
	if candidates.size() > MAX_ALPHA_SAMPLES:
		samples = PackedVector2Array()
		for sample_index in MAX_ALPHA_SAMPLES:
			var candidate_index := int(round(float(sample_index) * float(candidates.size() - 1) / float(MAX_ALPHA_SAMPLES - 1)))
			samples.append(candidates[candidate_index])
	var inside := 0
	for point: Vector2 in samples:
		for collision: CollisionShape2D in collisions:
			if _shape_contains_point(collision, point, CONTACT_MARGIN_TOLERANCE):
				inside += 1
				break
	var ratio := float(inside) / float(samples.size())
	var required := MICRO_COVERAGE_MINIMUM if maxf(visual_bounds.size.x, visual_bounds.size.y) < 40.0 else COVERAGE_MINIMUM
	return _expect(ratio >= required, "%s alpha boundary inside collider shape (%.3f = %d/%d req=%.2f)" % [asset_label, ratio, inside, samples.size(), required])


func _check_bidirectional_alignment(body: StaticBody2D, sprite: Sprite2D, collisions: Array[CollisionShape2D], visual_bounds: Rect2) -> bool:
	var asset_label := _asset_label(body, sprite)
	var alpha_points := _sprite_alpha_boundary_points(body, sprite)
	var collision_center := Vector2.ZERO
	for collision: CollisionShape2D in collisions:
		collision_center += collision.position
	collision_center /= float(collisions.size())
	var alpha_center := _alpha_center_in_shape_axes(alpha_points, collisions[0])
	var center_offset := collision_center.distance_to(alpha_center)
	if not _expect(center_offset <= CENTER_OFFSET_TOLERANCE, "%s collider center offset %.2fu should be <= %.2fu" % [asset_label, center_offset, CENTER_OFFSET_TOLERANCE]):
		return false
	var maximum_margin := -INF
	var minimum_margin := INF
	if minf(visual_bounds.size.x, visual_bounds.size.y) >= THIN_ALPHA_THRESHOLD:
		for direction_index in 8:
			var direction := Vector2.RIGHT.rotated(TAU * float(direction_index) / 8.0)
			var alpha_support := -INF
			for point: Vector2 in alpha_points:
				alpha_support = maxf(alpha_support, point.dot(direction))
			var shape_support := -INF
			for collision: CollisionShape2D in collisions:
				shape_support = maxf(shape_support, _shape_support(collision, direction))
			var margin := shape_support - alpha_support
			maximum_margin = maxf(maximum_margin, margin)
			minimum_margin = minf(minimum_margin, margin)
		if not _expect(minimum_margin >= -CONTACT_MARGIN_TOLERANCE, "%s collider falls %.2fu inside visible art (limit %.2fu)" % [asset_label, -minimum_margin, CONTACT_MARGIN_TOLERANCE]):
			return false
		if not _expect(maximum_margin <= CONTACT_MARGIN_HARD_LIMIT, "%s collider reaches %.2fu into transparent space (hard limit %.2fu, shape=%s size=%s rotation=%.3f alpha=%s)" % [asset_label, maximum_margin, CONTACT_MARGIN_HARD_LIMIT, collisions[0].shape.get_class(), str(body.get_meta("collision_footprint_size", Vector2.ZERO)), collisions[0].rotation, str(visual_bounds.size)]):
			return false
	_record_margin(body, maximum_margin)
	return true


func _alpha_center_in_shape_axes(alpha_points: PackedVector2Array, collision: CollisionShape2D) -> Vector2:
	var local_points := PackedVector2Array()
	for point: Vector2 in alpha_points:
		local_points.append((point - collision.position).rotated(-collision.rotation))
	return collision.position + _points_bounds(local_points).get_center().rotated(collision.rotation)


func _sprite_alpha_boundary_points(body: StaticBody2D, sprite: Sprite2D) -> PackedVector2Array:
	var texture := sprite.texture
	if texture == null:
		return PackedVector2Array()
	var key := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
	if not _opaque_point_cache.has(key):
		var image := texture.get_image()
		var texture_points := PackedVector2Array()
		if image != null and not image.is_empty():
			var used := image.get_used_rect()
			for y in range(used.position.y, used.end.y):
				var first_x := -1
				var last_x := -1
				for x in range(used.position.x, used.end.x):
					if image.get_pixel(x, y).a > BUILDER.COLLISION_ALPHA_THRESHOLD:
						if first_x < 0:
							first_x = x
						last_x = x
				if first_x >= 0:
					texture_points.append(Vector2(first_x + 0.5, y + 0.5))
					texture_points.append(Vector2(last_x + 0.5, y + 0.5))
		_opaque_point_cache[key] = texture_points
	var canvas_half := Vector2(texture.get_width(), texture.get_height()) * 0.5
	var result := PackedVector2Array()
	for texture_point: Vector2 in _opaque_point_cache[key]:
		result.append(body.to_local(sprite.to_global(texture_point - canvas_half)))
	return result


func _shape_contains_point(collision: CollisionShape2D, point: Vector2, tolerance: float) -> bool:
	var local_point := (point - collision.position).rotated(-collision.rotation)
	if collision.shape is CircleShape2D:
		return local_point.length() <= (collision.shape as CircleShape2D).radius + tolerance
	if collision.shape is RectangleShape2D:
		var half := (collision.shape as RectangleShape2D).size * 0.5 + Vector2.ONE * tolerance
		return absf(local_point.x) <= half.x and absf(local_point.y) <= half.y
	if collision.shape is CapsuleShape2D:
		var capsule := collision.shape as CapsuleShape2D
		var segment_half := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
		var closest := Vector2(0.0, clampf(local_point.y, -segment_half, segment_half))
		return local_point.distance_to(closest) <= capsule.radius + tolerance
	if collision.shape is ConvexPolygonShape2D:
		var polygon := (collision.shape as ConvexPolygonShape2D).points
		if Geometry2D.is_point_in_polygon(local_point, polygon):
			return true
		for index in polygon.size():
			if _point_to_segment_distance(local_point, polygon[index], polygon[(index + 1) % polygon.size()]) <= tolerance:
				return true
	return false


func _shape_support(collision: CollisionShape2D, direction: Vector2) -> float:
	var local_direction := direction.rotated(-collision.rotation)
	var extent := 0.0
	if collision.shape is CircleShape2D:
		extent = (collision.shape as CircleShape2D).radius
	elif collision.shape is RectangleShape2D:
		var half := (collision.shape as RectangleShape2D).size * 0.5
		extent = absf(local_direction.x) * half.x + absf(local_direction.y) * half.y
	elif collision.shape is CapsuleShape2D:
		var capsule := collision.shape as CapsuleShape2D
		var segment_half := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
		extent = capsule.radius + absf(local_direction.y) * segment_half
	elif collision.shape is ConvexPolygonShape2D:
		for point: Vector2 in (collision.shape as ConvexPolygonShape2D).points:
			extent = maxf(extent, point.dot(local_direction))
	return collision.position.dot(direction) + extent


func _point_to_segment_distance(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment := to - from
	if segment.length_squared() < 0.001:
		return point.distance_to(from)
	var fraction := clampf((point - from).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(from + segment * fraction)


func _record_margin(body: StaticBody2D, margin: float) -> void:
	var label := String(MARGIN_CLASSES.get(StringName(body.get_meta("solid_class", &"")), ""))
	if label.is_empty():
		return
	var stats: Dictionary = _margin_stats.get(label, {"pairs": 0, "over": 0, "worst": -INF})
	stats["pairs"] = int(stats["pairs"]) + 1
	if margin > CONTACT_MARGIN_TOLERANCE:
		stats["over"] = int(stats["over"]) + 1
	stats["worst"] = maxf(float(stats["worst"]), margin)
	_margin_stats[label] = stats


func _check_margin_statistics() -> bool:
	for label: String in ["Rails", "Giants", "Gate posts", "Obstacles", "Story props"]:
		var stats: Dictionary = _margin_stats.get(label, {})
		var pairs := int(stats.get("pairs", 0))
		var over := int(stats.get("over", 0))
		var rate := float(over) / maxf(float(pairs), 1.0) * 100.0
		var worst := float(stats.get("worst", 0.0))
		print("COLLISION_MARGIN class=%s pairs=%d over_6u=%d rate=%.1f%% worst=%.2fu" % [label, pairs, over, rate, worst])
		if not _expect(pairs > 0, "%s should include measured collider/sprite pairs" % label):
			return false
		if not _expect(rate < 5.0, "%s should keep fewer than 5%% of pairs over 6u (%.1f%%)" % [label, rate]):
			return false
		if not _expect(worst <= CONTACT_MARGIN_HARD_LIMIT, "%s worst invisible margin should be <= %.1fu (%.2fu)" % [label, CONTACT_MARGIN_HARD_LIMIT, worst]):
			return false
	return true


func _physics_point_hits_body(point: Vector2, expected: StaticBody2D) -> bool:
	var params := PhysicsPointQueryParameters2D.new()
	params.position = point
	params.collision_mask = VEHICLE_SCENERY_MASK
	params.collide_with_areas = false
	params.collide_with_bodies = true
	for hit: Dictionary in root.world_2d.direct_space_state.intersect_point(params, 256):
		if hit.get("collider") == expected:
			return true
	return false


func _check_flat_contract(track: Node2D, run_physics_probes: bool) -> bool:
	var safe_physics_samples := 0
	for node: Node in track.find_children("*", "CanvasItem", true, false):
		if StringName(node.get_meta("collision_contract", &"")) != BUILDER.COLLISION_FLAT:
			continue
		_flat_visuals_checked += 1
		if not _expect(not node is CollisionObject2D and node.find_children("*", "CollisionShape2D", true, false).is_empty() and node.find_children("*", "CollisionPolygon2D", true, false).is_empty(), "%s FLAT visual must not own collision" % str(track.get_path_to(node))):
			return false
		var flat_class := StringName(node.get_meta("flat_class", &""))
		if run_physics_probes and node is Node2D and flat_class in [&"corridor_pattern", &"surface_decal"] and safe_physics_samples < 12:
			var params := PhysicsPointQueryParameters2D.new()
			params.position = (node as Node2D).global_position
			params.collision_mask = VEHICLE_SCENERY_MASK
			params.collide_with_areas = false
			params.collide_with_bodies = true
			if not _expect(root.world_2d.direct_space_state.intersect_point(params, 32).is_empty(), "%s FLAT road art must remain drive-over" % str(track.get_path_to(node))):
				return false
			safe_physics_samples += 1
	return _expect(not run_physics_probes or safe_physics_samples >= 6, "representative FLAT road decals should receive collision-free physics probes")


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("ASSET_COLLISION_INTEGRITY_TEST FAIL: " + message)
	quit(1)
	return false
