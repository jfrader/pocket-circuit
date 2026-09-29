class_name TrackBuilderPlacement
## Prop placement safety, mix-seed, and generated prop spawn.


static func placement_is_safe(
		candidate: Vector2,
		radius: float,
		room_polygon: PackedVector2Array,
		allowed_polygon: PackedVector2Array,
		occupied: Array[Dictionary]
) -> bool:
	if not inside_polygon_with_radius(candidate, radius, room_polygon):
		return false
	if not inside_polygon_with_radius(candidate, radius, allowed_polygon):
		return false
	return TrackBuilderCore._clear_of_occupied(candidate, radius, occupied)


static func best_island_position(
		preferred: Vector2,
		radius: float,
		room_polygon: PackedVector2Array,
		island_polygon: PackedVector2Array,
		occupied: Array[Dictionary]
) -> Dictionary:
	var bounds := TrackBuilderCore._polygon_bounds_rect(island_polygon)
	var best_position := Vector2.ZERO
	var best_score := INF
	# A deterministic dense scan is the final placement path for strongly
	# concave islands where an authored local formation lands in a bay or waist.
	for x in 17:
		for y in 17:
			var candidate := bounds.position + Vector2(
				bounds.size.x * (float(x) + 0.5) / 17.0,
				bounds.size.y * (float(y) + 0.5) / 17.0
			)
			if not placement_is_safe(candidate, radius, room_polygon, island_polygon, occupied):
				continue
			var score := candidate.distance_squared_to(preferred)
			if score < best_score:
				best_score = score
				best_position = candidate
	return {"found": best_score < INF, "position": best_position}


static func best_offtrack_position(
		preferred: Vector2,
		radius: float,
		room_polygon: PackedVector2Array,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary]
) -> Dictionary:
	var bounds := TrackBuilderCore._polygon_bounds_rect(room_polygon)
	var best_position := Vector2.ZERO
	var best_score := INF
	for x in 25:
		for y in 17:
			var candidate := bounds.position + Vector2(
				bounds.size.x * (float(x) + 0.5) / 25.0,
				bounds.size.y * (float(y) + 0.5) / 17.0
			)
			if not trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied):
				continue
			var score := candidate.distance_squared_to(preferred)
			if score < best_score:
				best_score = score
				best_position = candidate
	return {"found": best_score < INF, "position": best_position}


static func best_giant_position(
		preferred_index: int,
		size: Vector2,
		shape_kind: StringName,
		local_footprint_rotation: float,
		room_polygon: PackedVector2Array,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary],
		committed_racing_lines: Array[PackedVector2Array] = []
) -> Dictionary:
	var bounds := TrackBuilderCore._polygon_bounds_rect(room_polygon)
	var preferred := centerline[preferred_index]
	var best := {}
	var best_score := INF
	for x in 29:
		for y in 19:
			var candidate := bounds.position + Vector2(
				bounds.size.x * (float(x) + 0.5) / 29.0,
				bounds.size.y * (float(y) + 0.5) / 19.0
			)
			var closest: Dictionary = TrackBuilderCore._closest_point_on_loop(candidate, centerline)
			var centerline_index := int(closest["index"])
			var tangent_angle := TrackBuilderCore._sample_tangent(centerline, centerline_index).angle()
			var rotation := tangent_angle - local_footprint_rotation if size.x >= size.y else tangent_angle - PI * 0.5 - local_footprint_rotation
			if not giant_placement_is_safe(candidate, size, shape_kind, rotation + local_footprint_rotation, room_polygon, centerline, gate_samples, occupied, committed_racing_lines):
				continue
			var score := candidate.distance_squared_to(preferred)
			if score < best_score:
				best_score = score
				best = {"found": true, "position": candidate, "rotation": rotation}
	return best if not best.is_empty() else {"found": false}


static func giant_placement_is_safe(
		candidate: Vector2,
		size: Vector2,
		shape_kind: StringName,
		rotation: float,
		room_polygon: PackedVector2Array,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary],
		committed_racing_lines: Array[PackedVector2Array] = []
) -> bool:
	var bounding_radius := size.length() * 0.5
	if not TrackBuilderCore._clear_of_occupied(candidate, bounding_radius, occupied):
		return false
	if shape_kind == &"circle":
		var radius := maxf(size.x, size.y) * 0.5
		if not inside_polygon_with_radius(candidate, radius, room_polygon):
			return false
		if not TrackBuilderCore._line_sweep_clears_footprint(centerline, candidate, size, shape_kind, rotation, TrackBuilderCore.HALF_WIDTH + TrackBuilderCore.APRON_COLLIDER_CLEARANCE):
			return false
		for gate: Vector2 in gate_samples:
			if candidate.distance_to(gate) < radius + 82.0:
				return false
		return committed_lines_clear_giant(committed_racing_lines, candidate, size, shape_kind, rotation)
	var half_size := size * 0.5
	for corner: Vector2 in [
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y),
	]:
		if not Geometry2D.is_point_in_polygon(candidate + corner.rotated(rotation), room_polygon):
			return false
	if not TrackBuilderCore._line_sweep_clears_footprint(centerline, candidate, size, shape_kind, rotation, TrackBuilderCore.HALF_WIDTH + TrackBuilderCore.APRON_COLLIDER_CLEARANCE):
		return false
	for gate: Vector2 in gate_samples:
		if point_to_oriented_rect_distance(gate, candidate, size, rotation) < 82.0:
			return false
	return committed_lines_clear_giant(committed_racing_lines, candidate, size, shape_kind, rotation)


static func committed_lines_clear_giant(
		committed_racing_lines: Array[PackedVector2Array],
		candidate: Vector2,
		size: Vector2,
		shape_kind: StringName,
		rotation: float
) -> bool:
	for line: PackedVector2Array in committed_racing_lines:
		if not TrackBuilderCore._line_sweep_clears_footprint(line, candidate, size, shape_kind, rotation, TrackBuilderCore.RACING_LINE_HULL_RADIUS):
			return false
	return true



static func oriented_rect_inside_polygon(center: Vector2, size: Vector2, rotation: float, polygon: PackedVector2Array) -> bool:
	var half_size := size * 0.5
	return (
		Geometry2D.is_point_in_polygon(center + Vector2(-half_size.x, -half_size.y).rotated(rotation), polygon)
		and Geometry2D.is_point_in_polygon(center + Vector2(half_size.x, -half_size.y).rotated(rotation), polygon)
		and Geometry2D.is_point_in_polygon(center + Vector2(half_size.x, half_size.y).rotated(rotation), polygon)
		and Geometry2D.is_point_in_polygon(center + Vector2(-half_size.x, half_size.y).rotated(rotation), polygon)
	)


static func point_to_oriented_rect_distance(point: Vector2, center: Vector2, size: Vector2, rotation: float) -> float:
	var local := (point - center).rotated(-rotation)
	var outside := Vector2(maxf(absf(local.x) - size.x * 0.5, 0.0), maxf(absf(local.y) - size.y * 0.5, 0.0))
	return outside.length()


static func trackside_placement_is_safe(
		candidate: Vector2,
		radius: float,
		room_polygon: PackedVector2Array,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary]
) -> bool:
	if not inside_polygon_with_radius(candidate, radius, room_polygon):
		return false
	if TrackBuilderCore._distance_to_centerline(candidate, centerline) < TrackBuilderCore.HALF_WIDTH + radius + TrackBuilderCore.APRON_COLLIDER_CLEARANCE:
		return false
	if candidate.distance_to(centerline[0]) < 245.0 + radius:
		return false
	if not TrackBuilderCore._clear_of_points(candidate, gate_samples, 24.0 + radius):
		return false
	if not clear_of_recovery_lanes(candidate, radius, centerline, gate_samples):
		return false
	return TrackBuilderCore._clear_of_occupied(candidate, radius, occupied)


static func best_trackside_position(
		preferred_index: int,
		radius: float,
		centerline: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary]
) -> Dictionary:
	var best_position := Vector2.ZERO
	var best_index := 0
	var best_score := INF
	for index in range(0, centerline.size(), 2):
		var outward := (outer_loop[index] - centerline[index]).normalized()
		for attempt in 8:
			var side := 1.0 if attempt % 2 == 0 else -1.0
			var offset := TrackBuilderCore.HALF_WIDTH + radius + TrackBuilderCore.APRON_COLLIDER_CLEARANCE + float(attempt / 2) * 8.0
			var candidate := centerline[index] + outward * side * offset
			if not trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied):
				continue
			var score := float(TrackBuilderCore._cyclic_index_distance(index, posmod(preferred_index, centerline.size()), centerline.size())) + float(attempt) * 0.01
			if score < best_score:
				best_score = score
				best_position = candidate
				best_index = index
	return {"found": best_score < INF, "position": best_position, "index": best_index}


static func inside_polygon_with_radius(point: Vector2, radius: float, polygon: PackedVector2Array) -> bool:
	if polygon.is_empty() or not Geometry2D.is_point_in_polygon(point, polygon):
		return false
	for sample in 8:
		var test_point := point + Vector2.RIGHT.rotated(TAU * float(sample) / 8.0) * radius
		if not Geometry2D.is_point_in_polygon(test_point, polygon):
			return false
	return true



static func clear_of_recovery_lanes(
		point: Vector2,
		radius: float,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array
) -> bool:
	for gate: Vector2 in gate_samples:
		var nearest_index := 0
		var nearest_distance := INF
		for index in centerline.size():
			var distance := gate.distance_squared_to(centerline[index])
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_index = index
		var tangent := TrackBuilderCore._sample_tangent(centerline, nearest_index)
		var lane_from := gate - tangent * TrackBuilderCore.RECOVERY_LANE_HALF_LENGTH
		var lane_to := gate + tangent * TrackBuilderCore.RECOVERY_LANE_HALF_LENGTH
		if TrackBuilderCore._point_to_segment_distance(point, lane_from, lane_to) < TrackBuilderCore.RECOVERY_LANE_HALF_WIDTH + radius:
			return false
	return true



static func asset_radius(texture_path: String, fallback_radius: float) -> float:
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return fallback_radius
	var bounds := TrackBuilderCore._texture_opaque_rect(texture)
	var scale := TrackBuilderCore.PROP_SCALE.sprite_scale(texture, bounds, TrackBuilderCore._prop_visual_size(texture_path, fallback_radius * 2.0))
	return bounds.size.length() * scale * 0.5


static func add_generated_prop(
		parent: Node2D,
		node_name: String,
		position: Vector2,
		texture_path: String,
		rotation: float,
		moment_kind: StringName,
		quantity: StringName,
		formation_index: int,
		size_scale: float = 1.0
) -> void:
	var prop := StaticBody2D.new()
	prop.name = node_name
	prop.position = position
	prop.rotation = rotation
	prop.collision_layer = 16
	TrackBuilderCore._mark_solid_body(prop, texture_path, moment_kind)
	prop.set_meta("moment_kind", moment_kind)
	prop.set_meta("semantic_quantity", quantity)
	prop.set_meta("formation_index", formation_index)
	prop.set_meta("size_scale", size_scale)
	parent.add_child(prop)
	var texture := load(texture_path) as Texture2D
	if texture:
		var bounds := TrackBuilderCore._texture_opaque_rect(texture)
		var sprite_scale := TrackBuilderCore.PROP_SCALE.sprite_scale(texture, bounds, TrackBuilderCore._prop_visual_size(texture_path, 48.0)) * size_scale
		var entry: Dictionary = TrackBuilderCore.PROP_SHAPES.get(texture_path.get_file(), {})
		var offset := TrackBuilderCore._add_scaled_texture_collision(prop, texture, sprite_scale, StringName(entry.get("shape", &"circle")))
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.scale = Vector2.ONE * sprite_scale
		sprite.position = -offset
		TrackBuilderCore._mark_solid_visual(sprite, texture_path, moment_kind)
		prop.add_child(sprite)
		TrackBuilderCore._add_directional_shadow(sprite)


static func mix_seed(seed: int, stream: String) -> int:
	var value := (seed ^ int(stream.hash()) ^ 0x6D2B79F5) & 0x7FFFFFFF
	value = ((value ^ (value >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
	value = ((value ^ (value >> 15)) * 0x45D9F3B) & 0x7FFFFFFF
	return (value ^ (value >> 16)) & 0x7FFFFFFF
