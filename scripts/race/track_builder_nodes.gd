class_name TrackBuilderNodes
## Primitive track nodes: polygons, walls, gates, grid, decals.


static func add_polygon(parent: Node, node_name: String, points: PackedVector2Array, color: Color, z: int) -> void:
	var polygon := Polygon2D.new()
	polygon.name = node_name
	polygon.polygon = points
	polygon.color = color
	polygon.z_index = z
	parent.add_child(polygon)


static func add_finish_checker(parent: Node2D, finish: Vector2, tangent: Vector2) -> void:
	var along := tangent.normalized()
	var across := along.rotated(PI * 0.5)
	var columns := 6
	var rows := 2
	var cell_width := TrackBuilderCore.HALF_WIDTH * 2.0 / float(columns)
	var cell_depth := 36.0
	var color_counts := {&"White": 0, &"Black": 0}
	for row in rows:
		for column in columns:
			var color_key := &"White" if (row + column) % 2 == 0 else &"Black"
			var color_index := int(color_counts[color_key])
			var node_name := "StartFinish%s" % String(color_key) if color_index == 0 else "StartFinish%sCell%02d" % [String(color_key), color_index]
			var center := finish
			center += along * (float(row) - float(rows - 1) * 0.5) * cell_depth
			center += across * (float(column) - float(columns - 1) * 0.5) * cell_width
			var half_along := along * cell_depth * 0.5
			var half_across := across * cell_width * 0.5
			var cell := Polygon2D.new()
			cell.name = node_name
			cell.polygon = PackedVector2Array([
				center - half_along - half_across,
				center + half_along - half_across,
				center + half_along + half_across,
				center - half_along + half_across,
			])
			cell.color = Color("f5eec8") if color_key == &"White" else Color("0d0f14")
			cell.z_index = -7 if color_key == &"White" else -6
			cell.set_meta("checker_color", color_key)
			cell.set_meta("checker_cell", row * columns + column)
			TrackBuilderCore._mark_flat_visual(cell, "", &"checker")
			parent.add_child(cell)
			color_counts[color_key] = color_index + 1
	for color_key: StringName in color_counts:
		var first := parent.get_node("StartFinish%s" % String(color_key))
		first.set_meta("checker_cell_count", int(color_counts[color_key]))
		first.set_meta("corridor_span", TrackBuilderCore.HALF_WIDTH * 2.0)
		first.set_meta("bidirectional", true)


static func add_wall_segment(parent: Node, node_name: String, position: Vector2, length: float, rotation: float, edge_texture_path: String) -> void:
	var wall := StaticBody2D.new()
	wall.name = node_name
	wall.position = position
	wall.rotation = rotation
	wall.collision_layer = 2
	TrackBuilderCore._mark_solid_body(wall, edge_texture_path, &"room_wall")
	parent.add_child(wall)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(length + 60.0, 50.0)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	wall.add_child(cs)
	TrackBuilderCore._record_shape_probe_points(wall, Vector2.ZERO, shape.size, &"rect")
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = TrackBuilderCore._rect_points(Vector2.ZERO, Vector2(length + 60.0, 50.0))
	visual.color = Color("0e1524")
	TrackBuilderCore._mark_solid_visual(visual, edge_texture_path, &"room_wall")
	wall.add_child(visual)
	var side_face := Polygon2D.new()
	side_face.name = "SideFace"
	side_face.polygon = TrackBuilderCore._rect_points(Vector2(0.0, -14.0), Vector2(length + 60.0, 22.0))
	side_face.color = Color("262e3a")
	TrackBuilderCore._mark_solid_visual(side_face, "", &"room_wall")
	wall.add_child(side_face)
	var edge_texture_side := load(edge_texture_path) as Texture2D
	if edge_texture_side:
		var side_strip := Sprite2D.new()
		side_strip.name = "SideStrip"
		side_strip.texture = edge_texture_side
		side_strip.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		side_strip.position = Vector2(0.0, -14.0)
		var side_tiles := maxi(1, int(ceil((length + 60.0) / TrackBuilderCore.ROOM_EDGE_TILE_WORLD_LENGTH)))
		side_strip.region_enabled = true
		side_strip.region_rect = Rect2(0, 0, edge_texture_side.get_width() * side_tiles, edge_texture_side.get_height())
		side_strip.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		side_strip.scale = Vector2((length + 60.0) / (edge_texture_side.get_width() * float(side_tiles)), 34.0 / edge_texture_side.get_height())
		side_strip.modulate = Color(0.85, 0.85, 0.85)
		side_strip.set_meta("asset_path", edge_texture_path)
		TrackBuilderCore.VISUAL_ROLE_CONTRACT.assign(side_strip, TrackBuilderCore.VISUAL_ROLE_SOLID)
		wall.add_child(side_strip)
	var top_lip := Polygon2D.new()
	top_lip.name = "TopLip"
	top_lip.polygon = TrackBuilderCore._rect_points(Vector2(0.0, -28.0), Vector2(length + 60.0, 5.0))
	top_lip.color = Color("e8d9b8", 0.85)
	TrackBuilderCore._mark_solid_visual(top_lip, "", &"room_wall")
	wall.add_child(top_lip)
	var edge_texture := load(edge_texture_path) as Texture2D
	if edge_texture:
		var tile_count := maxi(1, int(ceil((length + 60.0) / TrackBuilderCore.ROOM_EDGE_TILE_WORLD_LENGTH)))
		for tile in tile_count:
			var strip := Sprite2D.new()
			strip.name = "EdgeStrip"
			strip.texture = edge_texture
			strip.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			var offset := (float(tile) - float(tile_count - 1) * 0.5) * ((length + 60.0) / float(tile_count))
			strip.position = Vector2(offset, 0.0)
			strip.scale = Vector2((length + 60.0) / (edge_texture.get_width() * float(tile_count)), 50.0 / edge_texture.get_height())
			strip.set_meta("asset_path", edge_texture_path)
			TrackBuilderCore.VISUAL_ROLE_CONTRACT.assign(strip, TrackBuilderCore.VISUAL_ROLE_SOLID)
			wall.add_child(strip)


static func gate_span_endpoints(sample: Vector2, tangent: Vector2, room_polygon: PackedVector2Array, island_polygon: PackedVector2Array) -> PackedVector2Array:
	var normal := tangent.rotated(PI * 0.5).normalized()
	var positive_island := nearest_gate_boundary(sample, normal, PackedVector2Array(), island_polygon)
	var negative_island := nearest_gate_boundary(sample, -normal, PackedVector2Array(), island_polygon)
	var positive_distance := (positive_island - sample).dot(normal)
	var negative_distance := (negative_island - sample).dot(-normal)
	var inner_direction := normal if positive_distance <= negative_distance else -normal
	var outer_direction := -inner_direction
	return PackedVector2Array([
		corridor_gate_endpoint(sample, inner_direction, room_polygon, island_polygon),
		nearest_gate_boundary(sample, outer_direction, room_polygon, island_polygon),
	])


static func corridor_gate_endpoint(sample: Vector2, direction: Vector2, room_polygon: PackedVector2Array, island_polygon: PackedVector2Array) -> Vector2:
	var boundary := nearest_gate_boundary(sample, direction, room_polygon, island_polygon)
	var projected := (boundary - sample).dot(direction.normalized())
	return sample + direction.normalized() * minf(projected, TrackBuilderCore.HALF_WIDTH)


static func nearest_gate_boundary(sample: Vector2, direction: Vector2, room_polygon: PackedVector2Array, island_polygon: PackedVector2Array) -> Vector2:
	var ray_end := sample + direction * 12000.0
	var nearest := ray_end
	var nearest_distance := INF
	for polygon: PackedVector2Array in [island_polygon, room_polygon]:
		for edge_index in polygon.size():
			var intersection: Variant = Geometry2D.segment_intersects_segment(sample, ray_end, polygon[edge_index], polygon[(edge_index + 1) % polygon.size()])
			if not intersection is Vector2:
				continue
			var point := intersection as Vector2
			var projected := (point - sample).dot(direction)
			if projected > 0.5 and projected < nearest_distance:
				nearest = point
				nearest_distance = projected
	return nearest


static func add_gate_posts(root: Node2D, spec: Dictionary, sample: Vector2, tangent: Vector2, gate_index: int) -> void:
	var container := root.get_node_or_null("GatePosts") as Node2D
	if container == null:
		container = Node2D.new()
		container.name = "GatePosts"
		container.set_meta("placed_count", 0)
		root.add_child(container)
	var boundary_assets: Dictionary = spec.get("generated_boundary", {})
	var asset_paths: Array = spec.get("gate_props", [])
	if asset_paths.is_empty():
		return
	var normal := tangent.rotated(PI * 0.5).normalized()
	for side in [-1, 1]:
		var asset_path := String(asset_paths[posmod(gate_index * 2 + (1 if side > 0 else 0), asset_paths.size())])
		var texture := load(asset_path) as Texture2D
		if texture == null:
			continue
		var post := StaticBody2D.new()
		post.name = "Gate%02d%s" % [gate_index, "Right" if side > 0 else "Left"]
		var post_offset := TrackBuilderCore.FINISH_LANDMARK_OFFSET if gate_index == 0 else TrackBuilderCore.GATE_POST_OFFSET
		post.position = sample + normal * post_offset * float(side)
		post.rotation = tangent.angle()
		post.collision_layer = 16
		post.z_index = -1 if gate_index == 0 else -2
		post.set_meta("asset_path", asset_path)
		post.set_meta("gate_index", gate_index)
		post.set_meta("visible_collision_backing", &"gate_post_sprite")
		if gate_index == 0:
			post.set_meta("finish_landmark", true)
			post.set_meta("landmark_side", &"right" if side > 0 else &"left")
			post.set_meta("race_directions", PackedStringArray(["forward", "reverse"]))
		TrackBuilderCore._mark_solid_body(post, asset_path, &"gate_post")
		container.add_child(post)
		var sprite_scale := Vector2.ONE * TrackBuilderCore.PROP_SCALE.sprite_scale(texture, TrackBuilderCore._texture_opaque_rect(texture), TrackBuilderCore.GATE_POST_SIZE.x)
		var offset := TrackBuilderCore._add_texture_collision(post, texture, sprite_scale, &"convex", true, 2.0)
		(post.get_node("AssetCollision") as CollisionShape2D).name = "PostCollision"
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.scale = sprite_scale
		sprite.position = -offset
		TrackBuilderCore._mark_solid_visual(sprite, asset_path, &"gate_post")
		post.add_child(sprite)
		TrackBuilderCore._add_directional_shadow(sprite)
		container.set_meta("placed_count", int(container.get_meta("placed_count", 0)) + 1)
	if gate_index == 0:
		container.set_meta("finish_landmark_paths", [NodePath("Gate00Left"), NodePath("Gate00Right")])
		container.set_meta("finish_landmark_offset", TrackBuilderCore.FINISH_LANDMARK_OFFSET)


static func add_cp(parent: Node, node_name: String, position: Vector2, rotation: float, index: int, is_finish: bool, recovery_rotation: float, span_endpoints: PackedVector2Array = PackedVector2Array()) -> void:
	var cp := Area2D.new()
	cp.name = node_name
	cp.position = position
	cp.rotation = rotation
	cp.visible = false
	cp.collision_layer = 0
	cp.set_script(TrackBuilderCore.CHECKPOINT_SCRIPT)
	cp.add_to_group("track_checkpoints", true)
	cp.set("checkpoint_index", index)
	cp.set("is_finish_line", is_finish)
	cp.set("recovery_rotation", recovery_rotation)
	cp.set("recovery_offset", 70.0)
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	cp.add_child(collision)
	if span_endpoints.size() == 2:
		var forgiving := RectangleShape2D.new()
		forgiving.size = Vector2(TrackBuilderCore.GATE_SENSOR_THICKNESS, span_endpoints[0].distance_to(span_endpoints[1]) + 8.0)
		collision.shape = forgiving
		var checkpoint_transform := Transform2D(rotation, position)
		collision.position = checkpoint_transform.affine_inverse() * span_endpoints[0].lerp(span_endpoints[1], 0.5)
		cp.set_meta("sensor_endpoints", span_endpoints)
		cp.set_meta("sensor_inner_endpoint", span_endpoints[0])
		cp.set_meta("sensor_outer_endpoint", span_endpoints[1])
		cp.set_meta("sensor_span", span_endpoints[0].distance_to(span_endpoints[1]))
		cp.set_meta("sensor_asymmetric_span", true)
	elif not is_finish:
		var forgiving := RectangleShape2D.new()
		forgiving.size = Vector2(70.0, 300.0)
		collision.shape = forgiving
	else:
		var finish_shape := RectangleShape2D.new()
		finish_shape.size = Vector2(34.0, 280.0)
		collision.shape = finish_shape
	parent.add_child(cp)


static func add_grid(parent: Node, node_name: String, rotation: float, positions: Array, rotations: Array = []) -> void:
	var grid := Node2D.new()
	grid.name = node_name
	parent.add_child(grid)
	for index in positions.size():
		var marker := Node2D.new()
		marker.name = str(index)
		marker.position = positions[index]
		marker.rotation = float(rotations[index]) if index < rotations.size() else rotation
		grid.add_child(marker)


static func grid_arc_distances(centerline: PackedVector2Array, reverse: bool, room_polygon: PackedVector2Array, island_polygon: PackedVector2Array) -> Array[float]:
	var arc := TrackBuilderCore._arc_lengths(centerline)
	var total := arc[arc.size() - 1]
	var start := centerline[0]
	var finish_tangent := (centerline[1] - centerline[centerline.size() - 1]).normalized()
	for offset_step in 48:
		var rows: Array[float] = []
		var clear := true
		for distance: float in TrackBuilderCore.GRID_ROW_DISTANCES:
			var shifted := distance + float(offset_step) * 20.0
			rows.append(shifted)
			var sample_arc := total - shifted if reverse else shifted
			var sample := TrackBuilderCore._sample_at_arc(centerline, arc, sample_arc)
			var normal := TrackBuilderCore._tangent_at_arc(centerline, arc, sample_arc).rotated(PI * 0.5)
			for side in [-1, 1]:
				var point := sample + normal * TrackBuilderCore.GRID_LANE_OFFSET * float(side)
				if absf((point - start).dot(finish_tangent)) < 70.0:
					clear = false
				if not TrackBuilderCore._inside_polygon_with_radius(point, 80.0, room_polygon):
					clear = false
				var nearest := TrackBuilderCore._closest_point_on_loop(point, island_polygon)
				if Geometry2D.is_point_in_polygon(point, island_polygon) or point.distance_to(nearest["position"]) < 68.0:
					clear = false
		if clear:
			return rows
	push_error("Unable to place the starting grid clear of the finish sensor")
	return []


static func scatter_decals(root: Node2D, spec: Dictionary, room_polygon: PackedVector2Array, corridor: PackedVector2Array, rng: RandomNumberGenerator) -> void:
	var decals: Array = spec.get("decals", [])
	if decals.is_empty():
		return
	for decal in 26:
		var position := Vector2(rng.randf_range(-830.0, 830.0), rng.randf_range(-530.0, 530.0))
		if not Geometry2D.is_point_in_polygon(position, room_polygon):
			continue
		if Geometry2D.is_point_in_polygon(position, corridor):
			continue
		var texture_path := String(decals[rng.randi_range(0, decals.size() - 1)])
		var sprite := Sprite2D.new()
		sprite.name = "Decal"
		sprite.texture = load(texture_path) as Texture2D
		if sprite.texture == null:
			sprite.free()
			continue
		sprite.scale = Vector2.ONE * rng.randf_range(0.5, 1.1)
		sprite.rotation = rng.randf_range(0.0, TAU)
		sprite.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(0.4, 0.9))
		sprite.z_index = -15
		TrackBuilderCore._mark_flat_visual(sprite, texture_path, &"floor_decal")
		root.add_child(sprite)
