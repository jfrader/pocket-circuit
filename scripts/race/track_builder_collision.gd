class_name TrackBuilderCollision
## Texture footprints, colliders, shadows, obstacles, and surface tiles.


static func mark_solid_body(body: CollisionObject2D, texture_path: String, solid_class: StringName) -> void:
	body.set_meta("collision_contract", TrackBuilderCore.COLLISION_SOLID)
	TrackBuilderCore.VISUAL_ROLE_CONTRACT.assign(body, TrackBuilderCore.VISUAL_ROLE_SOLID)
	body.set_meta("solid_class", solid_class)
	if not texture_path.is_empty():
		body.set_meta("asset_path", texture_path)


static func mark_solid_visual(visual: CanvasItem, texture_path: String, solid_class: StringName) -> void:
	visual.set_meta("collision_contract", TrackBuilderCore.COLLISION_SOLID)
	TrackBuilderCore.VISUAL_ROLE_CONTRACT.assign(visual, TrackBuilderCore.VISUAL_ROLE_SOLID)
	visual.set_meta("solid_class", solid_class)
	if not texture_path.is_empty():
		visual.set_meta("asset_path", texture_path)


static func mark_flat_visual(visual: CanvasItem, texture_path: String, flat_class: StringName) -> void:
	visual.set_meta("collision_contract", TrackBuilderCore.COLLISION_FLAT)
	TrackBuilderCore.VISUAL_ROLE_CONTRACT.assign(visual, TrackBuilderCore.VISUAL_ROLE_FLAT)
	visual.set_meta("flat_class", flat_class)
	if not texture_path.is_empty():
		visual.set_meta("asset_path", texture_path)


static func texture_opaque_rect(texture: Texture2D) -> Rect2:
	var cache_key := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
	if TrackBuilderCore._texture_opaque_rect_cache.has(cache_key):
		return TrackBuilderCore._texture_opaque_rect_cache[cache_key]
	var result: Rect2 = texture_alpha_outline(texture)["used"]
	TrackBuilderCore._texture_opaque_rect_cache[cache_key] = result
	return result


static func texture_alpha_outline(texture: Texture2D) -> Dictionary:
	var cache_key := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
	if TrackBuilderCore._texture_outline_cache.has(cache_key):
		return TrackBuilderCore._texture_outline_cache[cache_key]
	TrackBuilderCore.synchronous_outline_builds += 1
	var result := compute_alpha_outline(texture.get_image(), texture.get_width(), texture.get_height())
	TrackBuilderCore._texture_outline_cache[cache_key] = result
	return result


static func has_prepared_outline(texture: Texture2D) -> bool:
	var key := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
	return TrackBuilderCore._texture_outline_cache.has(key)


static func has_prepared_outline_path(path: String) -> bool:
	return TrackBuilderCore._texture_outline_cache.has(path)


static func install_prepared_outline(texture: Texture2D, outline: Dictionary) -> void:
	var key := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
	TrackBuilderCore._texture_outline_cache[key] = outline


static func preparation_texture_paths(value: Variant) -> Array[String]:
	var found: Array[String] = []
	if value is Dictionary:
		for child: Variant in value.values():
			for path in preparation_texture_paths(child):
				if not found.has(path):
					found.append(path)
	elif value is Array:
		for child: Variant in value:
			for path in preparation_texture_paths(child):
				if not found.has(path):
					found.append(path)
	elif value is String or value is StringName:
		var path := String(value)
		if path.begins_with("res://assets/") and path.get_extension() in ["png", "jpg", "webp", "svg"]:
			found.append(path)
	return found


static func compute_alpha_outline(image: Image, width: int, height: int) -> Dictionary:
	var rows_first := PackedInt32Array()
	var rows_last := PackedInt32Array()
	var columns_first := PackedInt32Array()
	var columns_last := PackedInt32Array()
	rows_first.resize(height)
	rows_last.resize(height)
	columns_first.resize(width)
	columns_last.resize(width)
	rows_first.fill(-1)
	rows_last.fill(-1)
	columns_first.fill(-1)
	columns_last.fill(-1)
	var boundary := PackedVector2Array()
	var bounds := Rect2(Vector2.ZERO, Vector2(width, height))
	if image != null and not image.is_empty():
		if image.is_compressed():
			image.decompress()
		var used := image.get_used_rect()
		var byte_alpha := image.get_format() == Image.FORMAT_RGBA8
		var pixels := image.get_data() if byte_alpha else PackedByteArray()
		var threshold := int(floor(TrackBuilderCore.COLLISION_ALPHA_THRESHOLD * 255.0))
		if used.size.x > 0 and used.size.y > 0:
			var minimum := Vector2i(used.end)
			var maximum := Vector2i(used.position - Vector2i.ONE)
			for y in range(used.position.y, used.end.y):
				var offset := (y * width + used.position.x) * 4 + 3
				for x in range(used.position.x, used.end.x):
					var opaque := pixels[offset] > threshold if byte_alpha else image.get_pixel(x, y).a > TrackBuilderCore.COLLISION_ALPHA_THRESHOLD
					if opaque:
						if rows_first[y] < 0:
							rows_first[y] = x
						rows_last[y] = x
						if columns_first[x] < 0:
							columns_first[x] = y
						columns_last[x] = y
					offset += 4
				if rows_first[y] >= 0:
					minimum = minimum.min(Vector2i(rows_first[y], y))
					maximum = maximum.max(Vector2i(rows_last[y], y))
					boundary.append(Vector2(rows_first[y] + 0.5, y + 0.5))
					boundary.append(Vector2(rows_last[y] + 0.5, y + 0.5))
			if maximum.x >= minimum.x and maximum.y >= minimum.y:
				bounds = Rect2(Vector2(minimum), Vector2(maximum - minimum + Vector2i.ONE))
	var result := {"used": bounds, "rows_first": rows_first, "rows_last": rows_last, "columns_first": columns_first, "columns_last": columns_last, "boundary": boundary}
	return result


static func texture_collision_footprint(texture: Texture2D, shape_kind: StringName, force_axis_aligned: bool = false) -> Dictionary:
	var override: Dictionary = TrackBuilderCore.ASSET_FOOTPRINT_OVERRIDES.get(texture.resource_path.get_file(), {})
	var resolved_kind := StringName(override.get("kind", shape_kind))
	var no_rotation := force_axis_aligned or bool(override.get("no_rotation", false))
	var cache_key := "%s:%s:%s" % [texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id()), resolved_kind, no_rotation]
	if TrackBuilderCore._texture_footprint_cache.has(cache_key):
		return TrackBuilderCore._texture_footprint_cache[cache_key]
	var used := texture_opaque_rect(texture)
	var fallback := {"center": used.get_center(), "size": used.size, "rotation": 0.0, "kind": resolved_kind}
	if resolved_kind == &"circle":
		var circle_result := balanced_circle_texture_footprint(texture, used)
		TrackBuilderCore._texture_footprint_cache[cache_key] = circle_result
		return circle_result
	if resolved_kind == &"convex":
		TrackBuilderCore._texture_footprint_cache[cache_key] = fallback
		return fallback
	if no_rotation:
		var forced_axis_result := axis_aligned_texture_footprint(used, resolved_kind)
		TrackBuilderCore._texture_footprint_cache[cache_key] = forced_axis_result
		return forced_axis_result
	var outline := texture_alpha_outline(texture)
	if (outline["boundary"] as PackedVector2Array).is_empty():
		TrackBuilderCore._texture_footprint_cache[cache_key] = fallback
		return fallback
	# Gather the first and last opaque pixel on sampled rows and columns. This
	# keeps diagonal silhouettes tight without scanning every interior pixel or
	# paying the fit cost again for repeated props.
	var points := PackedVector2Array()
	var scan_step := maxi(1, int(ceil(maxf(used.size.x, used.size.y) / 192.0)))
	var left := int(used.position.x)
	var top := int(used.position.y)
	var right := int(used.end.x)
	var bottom := int(used.end.y)
	for y in range(top, bottom, scan_step):
		var first_x: int = outline["rows_first"][y]
		var last_x: int = outline["rows_last"][y]
		if first_x >= 0:
			points.append(Vector2(first_x + 0.5, y + 0.5))
			points.append(Vector2(last_x + 0.5, y + 0.5))
	for x in range(left, right, scan_step):
		var first_y: int = outline["columns_first"][x]
		var last_y: int = outline["columns_last"][x]
		if first_y >= 0:
			points.append(Vector2(x + 0.5, first_y + 0.5))
			points.append(Vector2(x + 0.5, last_y + 0.5))
	if points.size() < 3:
		TrackBuilderCore._texture_footprint_cache[cache_key] = fallback
		return fallback
	# Use principal axis (covariance) of border points for robust long-axis
	# orientation. Finishes the cached alpha-derived oriented footprint so that
	# for rotated sprites the rect aligns with alpha even for paperclip/screw
	# style and diagonal giants.
	var sum := Vector2.ZERO
	var n := 0
	for pt: Vector2 in points:
		sum += pt
		n += 1
	var mean := sum / maxf(n, 1.0)
	var cxx := 0.0
	var cxy := 0.0
	var cyy := 0.0
	for pt: Vector2 in points:
		var d := pt - mean
		cxx += d.x * d.x
		cxy += d.x * d.y
		cyy += d.y * d.y
	cxx /= maxf(n, 1)
	cxy /= maxf(n, 1)
	cyy /= maxf(n, 1)
	var best_rotation := 0.5 * atan2(2.0 * cxy, cxx - cyy)
	# consider both orientations from PCA, pick by largest extent on one axis (robust long)
	var cands := [best_rotation, best_rotation + PI * 0.5]
	var best_max_extent := -1.0
	for c in cands:
		var angle := float(c)
		var axis_x := Vector2(cos(angle), sin(angle))
		var axis_y := axis_x.rotated(PI * 0.5)
		var min_x := INF
		var max_x := -INF
		var min_y := INF
		var max_y := -INF
		for point: Vector2 in points:
			var px := point.dot(axis_x)
			var py := point.dot(axis_y)
			min_x = minf(min_x, px)
			max_x = maxf(max_x, px)
			min_y = minf(min_y, py)
			max_y = maxf(max_y, py)
		var ex := maxf(max_x - min_x, max_y - min_y)
		if ex > best_max_extent:
			best_max_extent = ex
			best_rotation = angle
	var best_axis_x := Vector2(cos(best_rotation), sin(best_rotation))
	var best_axis_y := best_axis_x.rotated(PI * 0.5)
	# Linear projection extrema on each row occur at its first or last opaque
	# pixel. These endpoints preserve the dense scan's exact support bounds.
	var min_projection := Vector2(INF, INF)
	var max_projection := Vector2(-INF, -INF)
	for pt: Vector2 in outline["boundary"]:
		var pr := Vector2(pt.dot(best_axis_x), pt.dot(best_axis_y))
		min_projection = min_projection.min(pr)
		max_projection = max_projection.max(pr)
	var center_projection := (min_projection + max_projection) * 0.5
	var fitted_size := max_projection - min_projection
	var anisotropy := maxf(fitted_size.x, fitted_size.y) / maxf(minf(fitted_size.x, fitted_size.y), 0.001)
	if anisotropy < TrackBuilderCore.ORIENTED_FOOTPRINT_MIN_ANISOTROPY:
		var low_anisotropy_result := axis_aligned_texture_footprint(used, resolved_kind)
		TrackBuilderCore._texture_footprint_cache[cache_key] = low_anisotropy_result
		return low_anisotropy_result
	var result := {
		"center": best_axis_x * center_projection.x + best_axis_y * center_projection.y,
		# A slight symmetric inset balances rounded silhouette corners against
		# cardinal support while staying within the six-unit contact contract.
		"size": fitted_size * 0.98,
		"rotation": best_rotation,
		"kind": resolved_kind,
	}
	# Canonicalize so longer axis on size.x; equivalent rect (rot +90, dims swap).
	var sz: Vector2 = result["size"]
	if sz.x < sz.y:
		result["size"] = Vector2(sz.y, sz.x)
		result["rotation"] = float(result["rotation"]) + PI * 0.5
	TrackBuilderCore._texture_footprint_cache[cache_key] = result
	return result


static func axis_aligned_texture_footprint(used: Rect2, shape_kind: StringName) -> Dictionary:
	return {
		"center": used.get_center(),
		"size": used.size * 0.98,
		"rotation": 0.0,
		"kind": shape_kind,
	}


static func texture_convex_hull(texture: Texture2D) -> PackedVector2Array:
	var cache_key := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
	if TrackBuilderCore._texture_hull_cache.has(cache_key):
		return TrackBuilderCore._texture_hull_cache[cache_key]
	var points: PackedVector2Array = texture_alpha_outline(texture)["boundary"]
	var hull := Geometry2D.convex_hull(points) if points.size() >= 3 else points
	if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.remove_at(hull.size() - 1)
	TrackBuilderCore._texture_hull_cache[cache_key] = hull
	return hull


static func balanced_circle_texture_footprint(texture: Texture2D, used: Rect2) -> Dictionary:
	var center := used.get_center()
	var hull := texture_convex_hull(texture)
	if hull.is_empty():
		return {"center": center, "size": used.size, "rotation": 0.0, "kind": &"circle"}
	var minimum_support := INF
	var maximum_support := -INF
	for direction_index in 8:
		var direction := Vector2.RIGHT.rotated(TAU * float(direction_index) / 8.0)
		var support := -INF
		for point: Vector2 in hull:
			support = maxf(support, (point - center).dot(direction))
		minimum_support = minf(minimum_support, support)
		maximum_support = maxf(maximum_support, support)
	var radius := (minimum_support + maximum_support) * 0.5
	return {"center": center, "size": Vector2.ONE * radius * 2.0, "rotation": 0.0, "kind": &"circle"}


static func record_shape_probe_points(parent: Node, center: Vector2, size: Vector2, shape_kind: StringName, rotation: float = 0.0) -> void:
	var probes := PackedVector2Array([center])
	if shape_kind == &"circle":
		var radius := size.x * 0.5
		probes.append(center + Vector2(radius * 0.86, 0.0))
		probes.append(center - Vector2(radius * 0.86, 0.0))
	elif size.x >= size.y:
		probes.append(center + Vector2(size.x * 0.44, 0.0).rotated(rotation))
		probes.append(center - Vector2(size.x * 0.44, 0.0).rotated(rotation))
	else:
		probes.append(center + Vector2(0.0, size.y * 0.44).rotated(rotation))
		probes.append(center - Vector2(0.0, size.y * 0.44).rotated(rotation))
	parent.set_meta("collision_probe_points", probes)
	parent.set_meta("collision_footprint_size", size)
	parent.set_meta("collision_shape_kind", shape_kind)
	parent.set_meta("collision_footprint_rotation", rotation)


static func record_convex_probe_points(parent: Node, points: PackedVector2Array) -> void:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	var axis := Vector2.RIGHT if bounds.size.x >= bounds.size.y else Vector2.DOWN
	var minimum_point := points[0]
	var maximum_point := points[0]
	for point: Vector2 in points:
		if point.dot(axis) < minimum_point.dot(axis):
			minimum_point = point
		if point.dot(axis) > maximum_point.dot(axis):
			maximum_point = point
	parent.set_meta("collision_probe_points", PackedVector2Array([
		Vector2.ZERO,
		minimum_point.lerp(Vector2.ZERO, 0.14),
		maximum_point.lerp(Vector2.ZERO, 0.14),
	]))
	parent.set_meta("collision_footprint_size", bounds.size)
	parent.set_meta("collision_shape_kind", &"convex")
	parent.set_meta("collision_footprint_rotation", 0.0)


static func add_scaled_texture_collision(parent: Node, texture: Texture2D, sprite_scale: float, shape_kind: StringName) -> Vector2:
	return add_texture_collision(parent, texture, Vector2.ONE * sprite_scale, shape_kind)


static func add_texture_collision(
		parent: Node,
		texture: Texture2D,
		sprite_scale: Vector2,
		shape_kind: StringName,
		force_axis_aligned: bool = false,
		padding: float = 0.0
) -> Vector2:
	var footprint := texture_collision_footprint(texture, shape_kind, force_axis_aligned)
	var footprint_center: Vector2 = footprint["center"]
	var footprint_size: Vector2 = (footprint["size"] as Vector2) * sprite_scale + Vector2.ONE * padding
	var canvas_size := Vector2(texture.get_width(), texture.get_height())
	var visual_center_offset := (footprint_center - canvas_size * 0.5) * sprite_scale
	var resolved_kind := StringName(footprint["kind"])
	if resolved_kind == &"circle":
		var circle := CircleShape2D.new()
		circle.radius = maxf(footprint_size.x, footprint_size.y) * 0.5
		var circle_collision := CollisionShape2D.new()
		circle_collision.name = "AssetCollision"
		circle_collision.shape = circle
		parent.add_child(circle_collision)
		record_shape_probe_points(parent, Vector2.ZERO, Vector2.ONE * circle.radius * 2.0, &"circle")
		return visual_center_offset
	if resolved_kind == &"capsule":
		var capsule := CapsuleShape2D.new()
		capsule.radius = minf(footprint_size.x, footprint_size.y) * 0.5
		capsule.height = maxf(footprint_size.x, footprint_size.y)
		var capsule_collision := CollisionShape2D.new()
		capsule_collision.name = "AssetCollision"
		capsule_collision.rotation = float(footprint["rotation"]) + (PI * 0.5 if footprint_size.x >= footprint_size.y else 0.0)
		capsule_collision.shape = capsule
		parent.add_child(capsule_collision)
		record_shape_probe_points(parent, Vector2.ZERO, footprint_size, &"capsule", float(footprint["rotation"]))
		return visual_center_offset
	if resolved_kind == &"convex":
		var hull := texture_convex_hull(texture)
		var scaled_hull := PackedVector2Array()
		for point: Vector2 in hull:
			scaled_hull.append((point - footprint_center) * sprite_scale)
		var convex := ConvexPolygonShape2D.new()
		convex.points = scaled_hull
		var convex_collision := CollisionShape2D.new()
		convex_collision.name = "AssetCollision"
		convex_collision.shape = convex
		parent.add_child(convex_collision)
		record_convex_probe_points(parent, scaled_hull)
		return visual_center_offset
	var rect := RectangleShape2D.new()
	# The local rectangle follows the texture's alpha-fitted orientation instead
	# of creating invisible AABB corners around diagonal tools and utensils.
	rect.size = footprint_size
	var rect_collision := CollisionShape2D.new()
	rect_collision.name = "AssetCollision"
	rect_collision.rotation = float(footprint["rotation"])
	rect_collision.shape = rect
	parent.add_child(rect_collision)
	record_shape_probe_points(parent, Vector2.ZERO, rect.size, &"rect", rect_collision.rotation)
	return visual_center_offset


static func add_giant_collision(parent: Node, texture_path: String, sprite_scale: float) -> Vector2:
	var entry: Dictionary = TrackBuilderCore.PROP_SHAPES.get(texture_path.get_file(), {})
	if not bool(entry.get("solid", false)):
		push_error("TrackBuilderCore: giant asset is missing an explicit SOLID contract: %s" % texture_path)
		return Vector2.ZERO
	var texture := load(texture_path) as Texture2D
	if texture == null:
		push_error("TrackBuilderCore: giant collision texture is missing: %s" % texture_path)
		return Vector2.ZERO
	return add_scaled_texture_collision(parent, texture, sprite_scale, StringName(entry.get("shape", &"rect")))


static func add_boundary_prop(parent: Node, position: Vector2, radius: float, texture_path: String, rotation: float) -> void:
	var prop := StaticBody2D.new()
	prop.name = "BoundaryProp"
	prop.position = position
	prop.rotation = rotation
	prop.collision_layer = 16
	mark_solid_body(prop, texture_path, &"boundary_prop")
	parent.add_child(prop)
	add_directional_shadow(prop, texture_path, radius * 2.2)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		var sprite_scale := radius * 2.2 / maxf(longest, 1.0)
		sprite.scale = Vector2.ONE * sprite_scale
		var entry: Dictionary = TrackBuilderCore.PROP_SHAPES.get(texture_path.get_file(), {})
		var offset := add_scaled_texture_collision(prop, texture, sprite_scale, StringName(entry.get("shape", &"circle")))
		sprite.position = -offset
		mark_solid_visual(sprite, texture_path, &"boundary_prop")
		prop.add_child(sprite)


static func add_fill_prop(parent: Node, position: Vector2, radius: float, texture_path: String, rotation: float) -> void:
	var prop := StaticBody2D.new()
	prop.name = "IslandFill"
	prop.position = position
	prop.rotation = rotation
	prop.collision_layer = 16
	mark_solid_body(prop, texture_path, &"island_prop")
	parent.add_child(prop)
	add_directional_shadow(prop, texture_path, radius * 2.2)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		var visual := TrackBuilderCore._prop_visual_size(texture_path, radius * 2.2)
		var sprite_scale := visual / maxf(longest, 1.0)
		sprite.scale = Vector2.ONE * sprite_scale
		var entry: Dictionary = TrackBuilderCore.PROP_SHAPES.get(texture_path.get_file(), {})
		var offset := add_scaled_texture_collision(prop, texture, sprite_scale, StringName(entry.get("shape", &"circle")))
		sprite.position = -offset
		mark_solid_visual(sprite, texture_path, &"island_prop")
		prop.add_child(sprite)


static func add_directional_shadow(
		parent: Node2D,
		texture_path: String,
		fallback_diameter: float,
		size_scale: float = 1.0,
		footprint_override: Vector2 = Vector2.ZERO,
		add_cast_shadow: bool = false,
		footprint_rotation: float = 0.0
) -> void:
	var entry: Dictionary = TrackBuilderCore.PROP_SHAPES.get(texture_path.get_file(), {})
	var override: Dictionary = TrackBuilderCore.ASSET_FOOTPRINT_OVERRIDES.get(texture_path.get_file(), {})
	var shape_kind := StringName(entry.get("shadow_shape", override.get("kind", entry.get("shape", "circle"))))
	var footprint: Vector2 = footprint_override
	if footprint.is_zero_approx():
		footprint = (entry.get("size", Vector2.ONE * fallback_diameter) as Vector2) * size_scale
	if footprint.x <= 0.0 or footprint.y <= 0.0:
		footprint = Vector2.ONE * fallback_diameter
	var shadow_path := TrackBuilderCore.SHADOW_CIRCLE_TEXTURE if shape_kind == &"circle" else TrackBuilderCore.SHADOW_RECT_TEXTURE
	var shadow_texture := load(shadow_path) as Texture2D
	if shadow_texture == null:
		push_error("TrackBuilderCore: directional shadow asset is missing: %s" % shadow_path)
		return
	var visual_shadow_kind := &"circle" if shape_kind == &"circle" else &"rect"
	var longest := maxf(footprint.x, footprint.y)
	var local_light_direction := TrackBuilderCore.SHADOW_DIRECTION.rotated(-parent.rotation).normalized()
	var contact := Sprite2D.new()
	contact.name = "ContactShadow"
	contact.texture = shadow_texture
	contact.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	contact.position = local_light_direction * longest * 0.10
	contact.rotation = footprint_rotation
	contact.scale = Vector2(footprint.x * 1.08 / shadow_texture.get_width(), footprint.y * 1.08 / shadow_texture.get_height())
	contact.modulate = TrackBuilderCore.SHADOW_TINT
	contact.z_index = -2
	contact.set_meta("shadow_shape", visual_shadow_kind)
	contact.set_meta("light_direction", TrackBuilderCore.SHADOW_DIRECTION)
	mark_flat_visual(contact, shadow_path, &"shadow")
	parent.add_child(contact)
	if not add_cast_shadow:
		return
	var cast_texture := load(TrackBuilderCore.SHADOW_RECT_TEXTURE) as Texture2D
	if cast_texture == null:
		return
	var cast := Sprite2D.new()
	cast.name = "CastShadow"
	cast.texture = cast_texture
	cast.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	cast.position = local_light_direction * longest * 0.34
	cast.rotation = TrackBuilderCore.SHADOW_DIRECTION.angle() - parent.rotation
	cast.scale = Vector2(longest * 0.56 / cast_texture.get_width(), minf(footprint.x, footprint.y) * 0.66 / cast_texture.get_height())
	cast.modulate = TrackBuilderCore.GIANT_CAST_SHADOW_TINT
	cast.z_index = -3
	cast.set_meta("light_direction", TrackBuilderCore.SHADOW_DIRECTION)
	mark_flat_visual(cast, TrackBuilderCore.SHADOW_RECT_TEXTURE, &"shadow")
	parent.add_child(cast)


static func build_generated_obstacles(root: Node2D, spec: Dictionary) -> void:
	var container := Node2D.new()
	container.name = "PermanentObstacles"
	container.set_meta("seed", int(spec.get("obstacle_seed", 0)))
	container.set_meta("enabled", bool(spec.get("obstacles_enabled", true)))
	container.set_meta("role", &"permanent_obstacle_set")
	root.add_child(container)
	var plan: Array = spec.get("obstacle_plan", [])
	var minimum_clearance := INF
	for entry_value: Variant in plan:
		var entry := entry_value as Dictionary
		add_planned_obstacle(container, entry)
		minimum_clearance = minf(minimum_clearance, float(entry.get("viable_corridor_width", 0.0)))
	container.set_meta("placed_count", container.get_child_count())
	container.set_meta("minimum_viable_corridor_width", minimum_clearance if not plan.is_empty() else TrackBuilderCore.HALF_WIDTH * 2.0)
	root.set_meta("minimum_obstacle_corridor_width", minimum_clearance if not plan.is_empty() else TrackBuilderCore.HALF_WIDTH * 2.0)


static func add_planned_obstacle(parent: Node2D, data: Dictionary) -> void:
	var obstacle := StaticBody2D.new()
	obstacle.name = String(data.get("instance_id", data.get("id", "Obstacle"))).to_pascal_case()
	obstacle.position = data["position"]
	obstacle.rotation = float(data.get("rotation", 0.0))
	obstacle.collision_layer = 16
	var asset_path := String(data["asset"])
	mark_solid_body(obstacle, asset_path, &"permanent_obstacle")
	for key: String in ["id", "instance_id", "role", "footprint_kind", "footprint_size", "visual_bounds", "clearance", "centerline_index", "side", "lateral_footprint_extent", "lateral_center_offset", "viable_corridor_width", "validated_ai_routes"]:
		if data.has(key):
			obstacle.set_meta(key, data[key])
	parent.add_child(obstacle)
	var texture := load(asset_path) as Texture2D
	if texture == null:
		return
	var visual_size: Vector2 = data["visual_size"]
	var sprite_scale := maxf(visual_size.x, visual_size.y) / maxf(texture.get_width(), texture.get_height())
	var shape_kind := StringName(data["footprint_kind"])
	var offset := add_scaled_texture_collision(obstacle, texture, sprite_scale, shape_kind)
	obstacle.set_meta("collision_footprint_size", data["footprint_size"])
	obstacle.set_meta("collision_shape_kind", shape_kind)
	obstacle.set_meta("collision_footprint_rotation", 0.0)
	add_directional_shadow(obstacle, asset_path, maxf(visual_size.x, visual_size.y), 1.0, data["footprint_size"])
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.scale = Vector2.ONE * sprite_scale
	sprite.position = -offset
	mark_solid_visual(sprite, asset_path, &"permanent_obstacle")
	sprite.set_meta("visual_bounds", data["visual_bounds"])
	obstacle.add_child(sprite)


static func add_obstacle(parent: Node, node_name: String, position: Vector2, radius: float, texture_path: String) -> void:
	var obstacle := StaticBody2D.new()
	obstacle.name = node_name
	obstacle.position = position
	obstacle.collision_layer = 2
	mark_solid_body(obstacle, texture_path, &"obstacle")
	parent.add_child(obstacle)
	add_directional_shadow(obstacle, texture_path, radius * 2.4)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		var sprite_scale := radius * 2.4 / maxf(longest, 1.0)
		sprite.scale = Vector2.ONE * sprite_scale
		var entry: Dictionary = TrackBuilderCore.PROP_SHAPES.get(texture_path.get_file(), {})
		var offset := add_scaled_texture_collision(obstacle, texture, sprite_scale, StringName(entry.get("shape", &"circle")))
		sprite.position = -offset
		mark_solid_visual(sprite, texture_path, &"obstacle")
		obstacle.add_child(sprite)


static func add_prop_with_collision(parent: Node, position: Vector2, radius: float, texture_path: String) -> void:
	var prop := StaticBody2D.new()
	prop.name = "ApronProp"
	prop.position = position
	prop.collision_layer = 2
	mark_solid_body(prop, texture_path, &"apron_prop")
	parent.add_child(prop)
	add_directional_shadow(prop, texture_path, radius * 2.4)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		var sprite_scale := radius * 2.4 / maxf(longest, 1.0)
		sprite.scale = Vector2.ONE * sprite_scale
		var entry: Dictionary = TrackBuilderCore.PROP_SHAPES.get(texture_path.get_file(), {})
		var offset := add_scaled_texture_collision(prop, texture, sprite_scale, StringName(entry.get("shape", &"circle")))
		sprite.position = -offset
		mark_solid_visual(sprite, texture_path, &"apron_prop")
		prop.add_child(sprite)


static func add_textured_polygon(
		parent: Node,
		node_name: String,
		points: PackedVector2Array,
		texture_path: String,
		fallback_color: Color,
		z: int,
		tile_world_size: Vector2 = TrackBuilderCore.DEFAULT_FLOOR_TILE_WORLD_SIZE,
		modulate_color: Color = Color.WHITE
) -> void:
	var visual := Polygon2D.new()
	visual.name = node_name
	visual.z_index = z
	visual.polygon = points
	var texture := load(texture_path) as Texture2D if not texture_path.is_empty() else null
	if texture:
		visual.texture = texture
		visual.color = modulate_color
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		visual.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		var uvs := PackedVector2Array()
		# Polygon2D UVs are texture pixels. Track-space coordinates keep adjacent
		# surface pieces in phase instead of stretching a few texels over the room.
		for point: Vector2 in points:
			uvs.append(point / tile_world_size * texture.get_size())
		visual.uv = uvs
	else:
		visual.color = fallback_color
	mark_flat_visual(visual, texture_path, &"ground_surface")
	parent.add_child(visual)


static func expand_loop(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var count := points.size()
	var result := PackedVector2Array()
	for index in count:
		var prev := points[(index - 1 + count) % count]
		var next := points[(index + 1) % count]
		var tangent := (next - prev).normalized()
		var normal := tangent.rotated(-PI * 0.5)
		var centroid := Vector2.ZERO
		for point: Vector2 in points:
			centroid += point
		centroid /= float(count)
		if normal.dot(centroid - points[index]) < 0.0:
			normal = -normal
		result.append(points[index] + normal * distance)
	return result


static func add_centerline_tiles(parent: Node, centerline: PackedVector2Array, texture_path: String, modulate_value: float = 1.35, world_tile_size: Vector2 = Vector2.ZERO, opacity: float = 0.52, tint: Color = Color.WHITE, edge_feather: float = 0.16) -> void:
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return
	# A single textured ribbon avoids the overlapping square cards that made
	# every circuit read as the same scalloped chain of floor tiles.
	var surface := Line2D.new()
	surface.name = "TrackSurface"
	surface.points = centerline
	surface.closed = true
	surface.width = TrackBuilderCore.HALF_WIDTH * 2.0
	surface.texture = texture
	surface.texture_mode = Line2D.LINE_TEXTURE_TILE
	surface.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	surface.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	surface.default_color = Color(tint.r * modulate_value, tint.g * modulate_value, tint.b * modulate_value, opacity)
	if world_tile_size.x > 0 and world_tile_size.y > 0:
		var material := ShaderMaterial.new()
		material.shader = TrackBuilderCore.WORLD_SURFACE_SHADER
		material.set_shader_parameter("tile_world_size", world_tile_size)
		material.set_shader_parameter("edge_feather", edge_feather)
		surface.material = material
	surface.joint_mode = Line2D.LINE_JOINT_ROUND
	surface.begin_cap_mode = Line2D.LINE_CAP_ROUND
	surface.end_cap_mode = Line2D.LINE_CAP_ROUND
	surface.antialiased = true
	surface.z_index = -9
	mark_flat_visual(surface, texture_path, &"track_surface")
	parent.add_child(surface)


static func add_start_banner(parent: Node, start: Vector2, tangent: Vector2, corridor: PackedVector2Array) -> void:
	var normal := tangent.rotated(PI * 0.5)
	var along := Vector2(tangent.y, -tangent.x)
	if Geometry2D.is_point_in_polygon(start + normal * (TrackBuilderCore.HALF_WIDTH + 60.0), corridor):
		normal = -normal
	var banner_center := start - normal * (TrackBuilderCore.HALF_WIDTH + 46.0)
	for block in 6:
		var center := banner_center + along * (float(block) - 2.5) * 22.0
		TrackBuilderCore._add_polygon(parent, "BannerBlock%d" % block, PackedVector2Array([
			center - tangent * 22.0 - along * 11.0,
			center + tangent * 22.0 - along * 11.0,
			center + tangent * 22.0 + along * 11.0,
			center - tangent * 22.0 + along * 11.0,
		]), Color("f2ead7") if block % 2 == 0 else Color("c94f38"), -8)
		mark_flat_visual(parent.get_node("BannerBlock%d" % block) as Polygon2D, "", &"start_banner")


static func add_corridor_patterning(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, room_polygon: PackedVector2Array) -> void:
	# Visual-only overlays inside the corridor band to sell theme material
	# (woodgrain, cork, desk pad) without racing lines or grip changes.
	var patterns: Array = spec.get("corridor_patterns", [])
	if patterns.is_empty():
		return
	var container := Node2D.new()
	container.name = "CorridorPatterns"
	container.z_index = -8
	root.add_child(container)
	var rng := RandomNumberGenerator.new()
	rng.seed = TrackBuilderCore._mix_seed(int(spec.get("material_seed", spec.get("requested_seed", 0))), "corridor_pattern:%s" % String(spec.get("story_id", "")))
	var target := 32
	var placed := 0
	for attempt in 220:
		var t := rng.randf()
		var idx := int(t * centerline.size())
		var pos := centerline[idx]
		var normal := TrackBuilderCore._sample_tangent(centerline, idx).rotated(PI * 0.5)
		var dist := rng.randf_range(18.0, TrackBuilderCore.HALF_WIDTH - 32.0)
		var side := 1 if rng.randf() > 0.5 else -1
		var candidate := pos + normal * dist * side
		if not Geometry2D.is_point_in_polygon(candidate, room_polygon):
			continue
		var tex_path := String(patterns[rng.randi() % patterns.size()])
		var tex := load(tex_path) as Texture2D
		if tex == null:
			continue
		var spr := Sprite2D.new()
		spr.name = "Pattern%02d" % placed
		spr.texture = tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		spr.position = candidate
		spr.rotation = rng.randf_range(0.0, TAU)
		var sz := rng.randf_range(36.0, 68.0)
		var longest := maxf(tex.get_width(), tex.get_height())
		spr.scale = Vector2.ONE * (sz / maxf(longest, 1.0))
		spr.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(0.11, 0.26))
		spr.z_index = -8
		spr.set_meta("asset_path", tex_path)
		spr.set_meta("moment_kind", &"corridor_pattern")
		mark_flat_visual(spr, tex_path, &"corridor_pattern")
		container.add_child(spr)
		placed += 1
		if placed >= target:
			break
	container.set_meta("placed_count", placed)


static func add_boundary_worn_hint(container: Node2D, centerline: PackedVector2Array, boundary: PackedVector2Array, run_center: int, room_polygon: PackedVector2Array) -> void:
	var tex := load("res://assets/textures/edge_dressing/worn_floor_hint.png") as Texture2D
	if tex == null:
		tex = load("res://assets/textures/edge_dressing/shadow_strip.png") as Texture2D
	if tex == null:
		return
	var idx := posmod(run_center + 4, centerline.size())
	var sample := TrackBuilderCore._closest_point_on_loop(centerline[idx], boundary)
	var pos: Vector2 = sample["position"]
	var away := (pos - centerline[idx]).normalized()
	pos += away * 6.0
	if not Geometry2D.is_point_in_polygon(pos, room_polygon):
		pos = sample["position"]
	var spr := Sprite2D.new()
	spr.name = "EmptyRunHint"
	spr.texture = tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	spr.position = pos
	spr.rotation = TrackBuilderCore._sample_tangent(centerline, idx).angle()
	var sc := 220.0 / maxf(tex.get_width(), 1.0)
	spr.scale = Vector2.ONE * sc
	spr.modulate = Color(1.0, 1.0, 1.0, 0.55)
	spr.z_index = -5
	mark_flat_visual(spr, tex.resource_path, &"worn_hint")
	container.add_child(spr)




static func seal_pockets(root: Node2D, spec: Dictionary) -> void:
	# Deep interior bays declare pockets in the route spec. Each pocket mouth is
	# sealed with a solid themed wall so cutting across it is physically
	# impossible; the wall sits on the far side of the mouth, clear of the
	# racing line, and its ends overlap the arm corridors by a car width.
	var pockets: Array = spec.get("pockets", [])
	if pockets.is_empty():
		return
	var edge_texture := String(spec.get("edge_texture", "res://assets/textures/kitchen/counter_edge.png"))
	var container := Node2D.new()
	container.name = "PocketSeals"
	root.add_child(container)
	for pocket_index in pockets.size():
		var pocket: Dictionary = pockets[pocket_index]
		var from: Vector2 = pocket.get("from", Vector2.ZERO)
		var to: Vector2 = pocket.get("to", Vector2.ZERO)
		var chord := to - from
		var length := chord.length()
		if length < 60.0:
			continue
		var direction := chord / length
		var floor_side := Vector2(-direction.y, direction.x)
		var declared_side: Vector2 = pocket.get("side", Vector2.ZERO)
		if declared_side.length_squared() > 1.0:
			floor_side = declared_side.normalized()
		# The wall hugs the room-wall margin (165u off the mouth): its outer face
		# meets the wall margin so no car fits behind it, and its ends stop short
		# of the racing line's corner arcs.
		var wall_position := from.lerp(to, 0.5) - floor_side * 165.0
		TrackBuilderCore._add_wall_segment(
			container,
			"Seal%02d" % pocket_index,
			wall_position,
			length + 240.0,
			direction.angle(),
			edge_texture
		)
