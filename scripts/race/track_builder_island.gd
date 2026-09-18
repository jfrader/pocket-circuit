class_name TrackBuilderIsland
const TrackBuilderCore = preload("res://scripts/race/track_builder_core.gd")
## Raised island visual, rim, and rim landmarks.


static func build_island_prop(root: Node2D, spec: Dictionary, region: PackedVector2Array, inner_loop: PackedVector2Array, centerline: PackedVector2Array, stage: Callable = Callable()) -> void:
	var expanded := PackedVector2Array()
	if spec.get("seed_obstacles", false):
		# Geometry2D already returns a simple central polygon. Procedural concave
		# loops can make a naively offset inner centerline self-intersect, which is
		# not a valid CollisionPolygon2D; use the clipped island itself instead.
		expanded = region.duplicate()
	else:
		var last := Vector2(INF, INF)
		for index in inner_loop.size():
			var toward_track := (centerline[index] - inner_loop[index]).normalized()
			var point := inner_loop[index] + toward_track * float(spec.get("island_expansion", 10.0))
			if point.distance_to(last) > 3.0:
				expanded.append(point)
				last = point
	var barrier := StaticBody2D.new()
	barrier.name = "InnerBarrier"
	barrier.collision_layer = 2
	TrackBuilderCore._mark_solid_body(barrier, "", &"raised_island_rim")
	barrier.set_meta("boundary_polygon", expanded)
	barrier.set_meta("visible_collision_backing", &"raised_island_rim")
	root.add_child(barrier)
	if spec.get("seed_obstacles", false):
		# The line art is centered on `expanded`; contact belongs at its outer
		# (track-facing) edge, not invisibly halfway through the 26u textured rim.
		var collision_boundary := TrackBuilderCore._outset_polygon(expanded, TrackBuilderCore.ISLAND_TEXTURED_RIM_WIDTH * 0.5)
		# A generated inner offset can be concave enough that solid polygon
		# decomposition fails. A closed concave segment chain is valid on a static
		# body and still makes the household island a physical boundary.
		var segments := PackedVector2Array()
		for index in collision_boundary.size():
			segments.append(collision_boundary[index])
			segments.append(collision_boundary[(index + 1) % collision_boundary.size()])
		var boundary_shape := ConcavePolygonShape2D.new()
		boundary_shape.segments = segments
		var boundary_collision := CollisionShape2D.new()
		boundary_collision.name = "BoundaryCollision"
		boundary_collision.shape = boundary_shape
		barrier.add_child(boundary_collision)
		barrier.set_meta("collision_boundary_polygon", collision_boundary)
		barrier.set_meta("rim_contact_offset", TrackBuilderCore.ISLAND_TEXTURED_RIM_WIDTH * 0.5)
		root.set_meta("island_invalid_polygon", collision_boundary)
	else:
		var barrier_collision := CollisionPolygon2D.new()
		barrier_collision.polygon = expanded
		barrier.add_child(barrier_collision)
	if spec.get("seed_obstacles", false):
		build_raised_island_rim(barrier, spec, expanded)

	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point: Vector2 in region:
		min_point = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
		max_point = Vector2(maxf(max_point.x, point.x), maxf(max_point.y, point.y))

	var visual := Polygon2D.new()
	visual.name = "IslandProp"
	visual.z_index = -9
	visual.polygon = region
	var material_texture := String(spec.get("island_material_texture", ""))
	var prop_texture := material_texture if not material_texture.is_empty() else String(spec.get("prop_texture", ""))
	var texture := load(prop_texture) as Texture2D if not prop_texture.is_empty() else null
	if texture:
		# Transparent artwork margins must not make the solid island look hollow.
		TrackBuilderCore._add_polygon(root, "IslandMaterial", region, spec["island"], -9)
		TrackBuilderCore._mark_solid_visual(root.get_node("IslandMaterial") as Polygon2D, "", &"raised_island")
		visual.texture = texture
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		visual.modulate = Color(1.2, 1.2, 1.2)
		var uvs := PackedVector2Array()
		if not material_texture.is_empty():
			visual.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			visual.modulate = Color.WHITE
			var period: Vector2 = spec.get("island_material_world_size", TrackBuilderCore.DEFAULT_FLOOR_TILE_WORLD_SIZE)
			for point: Vector2 in region:
				uvs.append(point / period * texture.get_size())
		else:
			for point: Vector2 in region:
				uvs.append(Vector2(
					(point.x - min_point.x) / maxf(max_point.x - min_point.x, 1.0),
					(point.y - min_point.y) / maxf(max_point.y - min_point.y, 1.0)
				) * texture.get_size())
		visual.uv = uvs
	else:
		visual.color = spec["island"]
	TrackBuilderCore._mark_solid_visual(visual, prop_texture, &"raised_island")
	root.add_child(visual)
	if spec.get("seed_obstacles", false):
		await add_island_rim_landmarks(root, spec, expanded, centerline, stage)


static func build_raised_island_rim(parent: StaticBody2D, spec: Dictionary, points: PackedVector2Array) -> void:
	var face := Line2D.new()
	face.name = "SideFace"
	face.points = points
	face.closed = true
	face.width = TrackBuilderCore.ISLAND_SIDE_FACE_WIDTH
	face.position = TrackBuilderCore.SHADOW_DIRECTION * 10.0
	face.default_color = (spec.get("rim_dark", Color("3f2a22")) as Color).darkened(0.28)
	face.joint_mode = Line2D.LINE_JOINT_ROUND
	face.antialiased = true
	face.z_index = -8
	face.set_meta("backs_collision", true)
	TrackBuilderCore._mark_solid_visual(face, "", &"raised_island_rim")
	parent.add_child(face)

	var textured := Line2D.new()
	textured.name = "TexturedRim"
	textured.points = points
	textured.closed = true
	textured.width = TrackBuilderCore.ISLAND_TEXTURED_RIM_WIDTH
	textured.default_color = Color(0.9, 0.9, 0.9)
	textured.joint_mode = Line2D.LINE_JOINT_ROUND
	textured.antialiased = true
	textured.z_index = -7
	var edge_texture_path := String(spec.get("edge_texture", ""))
	var edge_texture := load(edge_texture_path) as Texture2D if not edge_texture_path.is_empty() else null
	if edge_texture:
		textured.texture = edge_texture
		textured.texture_mode = Line2D.LINE_TEXTURE_TILE
		textured.set_meta("asset_path", edge_texture_path)
	textured.set_meta("backs_collision", true)
	TrackBuilderCore._mark_solid_visual(textured, edge_texture_path, &"raised_island_rim")
	parent.add_child(textured)

	var lip := Line2D.new()
	lip.name = "TopLip"
	lip.points = points
	lip.closed = true
	lip.width = TrackBuilderCore.ISLAND_TOP_LIP_WIDTH
	lip.default_color = spec.get("rim_highlight", Color("ead6aa", 0.76))
	lip.joint_mode = Line2D.LINE_JOINT_ROUND
	lip.antialiased = true
	lip.z_index = -5
	lip.set_meta("backs_collision", true)
	TrackBuilderCore._mark_solid_visual(lip, "", &"raised_island_rim")
	parent.add_child(lip)


static func add_island_rim_landmarks(root: Node2D, spec: Dictionary, boundary: PackedVector2Array, centerline: PackedVector2Array, stage: Callable = Callable()) -> void:
	var assets: Array = spec.get("island_fill_textures", [])
	if assets.is_empty() or boundary.size() < 12:
		return
	var container := Node2D.new()
	container.name = "IslandRimLandmarks"
	container.set_meta("placed_count", 3)
	root.add_child(container)
	var seed := TrackBuilderCore._mix_seed(int(spec.get("dressing_seed", spec.get("requested_seed", spec.get("seed", 0)))), "island_rim_landmarks")
	var offset := posmod(seed, boundary.size())
	for landmark_index in 3:
		if stage.is_valid():
			await stage.call("Building physical track boundaries")
		var boundary_index := posmod(offset + int(round(float(landmark_index) * float(boundary.size()) / 3.0)), boundary.size())
		var boundary_point := boundary[boundary_index]
		var center_sample: Vector2 = TrackBuilderCore._closest_point_on_loop(boundary_point, centerline)["position"]
		var inward := (boundary_point - center_sample).normalized()
		var position := boundary_point + inward * 22.0
		var next_point := boundary[(boundary_index + 1) % boundary.size()]
		var texture_path := String(assets[posmod(seed + landmark_index * 5, assets.size())])
		TrackBuilderCore._add_generated_prop(container, "Landmark%02d" % landmark_index, position, texture_path, (next_point - boundary_point).angle(), &"island_rim", &"few", landmark_index, 0.72)


