class_name TrackBuilderRacing
const TrackSeedGen = preload("res://scripts/race/track_seed_gen.gd")
const TrackBuilderCore = preload("res://scripts/race/track_builder_core.gd")
## Canonical island fill, racing line, and leftover static-track dressing.

## Maximum lateral offset change per unit of arc distance when building the
## apex racing line. High enough to keep the entry->apex->exit envelope intact
## on the tightest driveable corners, low enough to reject the abrupt
## sign/amplitude jumps that fold the line back on itself.
const APEX_OFFSET_RATE_LIMIT := 0.5

## Final guidance-radius floor applied to the realized safe/shortcut line, after
## the apex envelope, the lane override, and the slew bound. It sits above the
## widest chassis's kinematic minimum turn radius (Scrapjaw: 43u wheelbase /
## tan(28.5°) ≈ 79u) so every car can hold the racing line at full lock.
const GUIDANCE_RADIUS_FLOOR := 90.0


static func fill_island(root: Node2D, spec: Dictionary, inner_loop: PackedVector2Array, centerline: PackedVector2Array) -> void:
	# The island hosts one authored VIGNETTE per theme (a designed scene, not a
	# random scatter): focal props at hand-authored offsets from the centroid,
	# plus a scatter of tiny many-items for life. The vignette is chosen by the
	# seed so it stays procedural but always reads as a scene.
	var vignettes: Array = []
	match String(spec.get("root_name", "")):
		"WorkshopWorkbench":
			vignettes = TrackBuilderCore.ISLAND_VIGNETTES[&"workshop"]
		"OfficeDesk":
			vignettes = TrackBuilderCore.ISLAND_VIGNETTES[&"office"]
		_:
			vignettes = TrackBuilderCore.ISLAND_VIGNETTES[&"kitchen"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0))
	var vignette: Array = vignettes[posmod(int(spec.get("seed", 0)), vignettes.size())]
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point: Vector2 in inner_loop:
		min_point = min_point.min(point)
		max_point = max_point.max(point)
	var centroid := (min_point + max_point) * 0.5
	var half_extent := (max_point - min_point) * 0.5
	for entry: Dictionary in vignette:
		var offset: Vector2 = entry["pos"]
		var position := centroid + Vector2(offset.x * half_extent.x, offset.y * half_extent.y)
		if not Geometry2D.is_point_in_polygon(position, inner_loop):
			continue
		var center_distance := TrackBuilderCore._distance_to_centerline(position, centerline)
		if center_distance < 125.0 + 40.0:
			continue
		var texture_path := String(entry["tex"])
		if bool(entry.get("decal", false)):
			var sprite := Sprite2D.new()
			sprite.name = "VignetteDecal"
			sprite.texture = load(texture_path) as Texture2D
			if sprite.texture == null:
				sprite.free()
				continue
			sprite.position = position
			sprite.rotation = float(entry.get("rot", 0.0))
			sprite.scale = Vector2.ONE * rng.randf_range(0.7, 1.2)
			sprite.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(0.55, 0.8))
			sprite.z_index = -13
			root.add_child(sprite)
			continue
		var visual := TrackBuilderCore._prop_visual_size(texture_path, 36.0)
		var radius := minf(visual * 0.5, 52.0)
		TrackBuilderCore._add_fill_prop(root, position, radius, texture_path, float(entry.get("rot", 0.0)))
	# Life: a scatter of tiny many-items (paperclips, coins, screws) around the vignette
	var many_pool: Array = spec.get("island_fill_tiny", [])
	if many_pool.is_empty():
		many_pool = ["res://assets/textures/imagine/paperclip.png", "res://assets/textures/imagine/coin.png"]
	for scatter in 12:
		var position := centroid + Vector2(rng.randf_range(-0.85, 0.85) * half_extent.x, rng.randf_range(-0.85, 0.85) * half_extent.y)
		if not Geometry2D.is_point_in_polygon(position, inner_loop):
			continue
		if TrackBuilderCore._distance_to_centerline(position, centerline) < 125.0 + 40.0:
			continue
		var texture_path := String(many_pool[rng.randi_range(0, many_pool.size() - 1)])
		var visual := TrackBuilderCore._prop_visual_size(texture_path, 18.0)
		TrackBuilderCore._add_fill_prop(root, position, minf(visual * 0.5, 20.0), texture_path, rng.randf_range(0.0, TAU))


static func line_boundary_props(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, outer_loop: PackedVector2Array, corridor: PackedVector2Array, room_polygon: PackedVector2Array) -> void:
	# Props delimiting the OUTER side of the track: long flat props on straights,
	# bulky props on corners, placed just outside the painted corridor. The
	# corridor-band test is distance-to-centerline (polygon membership is
	# unreliable inside the corridor's fold regions).
	var long_pool: Array = spec.get("boundary_long", [])
	var corner_pool: Array = spec.get("boundary_corner", [])
	if long_pool.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0))
	var count := centerline.size()
	var index := 0
	while index < count - 1:
		var tangent := (centerline[(index + 1) % count] - centerline[(index - 1 + count) % count]).normalized()
		var ahead := centerline[(index + 8) % count] - centerline[(index - 8 + count) % count]
		var turn := tangent.angle_to(ahead.normalized())
		var is_corner := absf(turn) > 0.16
		var offset := 78.0 if is_corner else 65.0
		var radius := 34.0 if is_corner else 27.0
		var position := outer_loop[index] + (outer_loop[index] - centerline[index]).normalized() * offset
		if position.distance_to(centerline[0]) < 230.0:
			index += 7
			continue
		if not Geometry2D.is_point_in_polygon(position, room_polygon):
			index += 7
			continue
		if TrackBuilderCore._distance_to_centerline(position, centerline) < 150.0:
			index += 7
			continue
		var pool := corner_pool if is_corner else long_pool
		var texture_path := String(pool[rng.randi_range(0, pool.size() - 1)])
		var prop_rotation := rng.randf_range(0.0, TAU) if is_corner else tangent.angle()
		TrackBuilderCore._add_boundary_prop(root, position, radius, texture_path, prop_rotation)
		index += 7


static func build_racing_line(root: Node2D, centerline: PackedVector2Array, moments: Dictionary = {}) -> void:
	var line_points := racing_line_points(centerline, moments, false)
	var shortcut_index := int(moments.get("shortcut", -1))
	add_hidden_racing_line(root, "RacingLine", line_points)
	if shortcut_index >= 0:
		var shortcut_points := racing_line_points(centerline, moments, true)
		var shortcut_line := add_hidden_racing_line(root, "ShortcutRacingLine", shortcut_points)
		shortcut_line.set_meta("role", &"shortcut")
		shortcut_line.set_meta("centerline_index", shortcut_index)
		shortcut_line.set_meta("ai_path_clear", true)


static func racing_line_points(centerline: PackedVector2Array, moments: Dictionary, use_shortcut: bool) -> PackedVector2Array:
	# The final line is assembled from a signed lateral offset per sample: the
	# apex envelope first, then the shortcut/safe lane override, then a single
	# arc-rate bound applied to the COMBINED offset. Bounding after the override
	# is what guarantees the lane lerp cannot reintroduce a steep offset change.
	var count := centerline.size()
	var offsets := _apex_signed_offsets(centerline)
	var shortcut_index := int(moments.get("shortcut", -1))
	if shortcut_index >= 0:
		var inside_sign := float(TrackBuilderCore._shortcut_lane_geometry(centerline, shortcut_index)["inside_sign"])
		var taper_span := TrackBuilderCore.SHORTCUT_HALF_SPAN + (8 if use_shortcut else 6)
		for index in count:
			var shortcut_distance := TrackBuilderCore._cyclic_index_distance(index, shortcut_index, count)
			if shortcut_distance > taper_span:
				continue
			var influence := 1.0 - smoothstep(float(TrackBuilderCore.SHORTCUT_HALF_SPAN), float(taper_span), float(shortcut_distance))
			var lane_offset := inside_sign * TrackBuilderCore.SHORTCUT_LANE_OFFSET if use_shortcut else -inside_sign * TrackBuilderCore.SAFE_RACING_LINE_OFFSET
			offsets[index] = lerpf(offsets[index], lane_offset, influence)
	offsets = _bounded_lateral_offsets(centerline, offsets)
	offsets = _enforce_guidance_radius(centerline, offsets)
	return _offsets_to_points(centerline, offsets)


static func add_hidden_racing_line(parent: Node2D, line_name: String, points: PackedVector2Array) -> Line2D:
	var line := Line2D.new()
	line.name = line_name
	line.points = points
	line.closed = true
	line.width = 2.0
	line.visible = false
	parent.add_child(line)
	return line


static func curvature_apex_line(centerline: PackedVector2Array) -> PackedVector2Array:
	# Apex-only line: bound the raw apex offsets and build points. Kept as the
	# shared base for callers that do not layer the shortcut/safe override.
	return _offsets_to_points(centerline, _bounded_lateral_offsets(centerline, _apex_signed_offsets(centerline)))


static func _apex_signed_offsets(centerline: PackedVector2Array) -> PackedFloat32Array:
	# Signed lateral offset from the corner apex/setup envelope, one per sample.
	# Not yet rate-limited: the caller layers the shortcut/safe override on top
	# and bounds the combined result.
	var count := centerline.size()
	var offsets := PackedFloat32Array()
	offsets.resize(count)
	if count < TrackBuilderCore.APEX_SAMPLE_SPAN * 2 + 1:
		return offsets
	for index in count:
		var local_turn := signed_turn_at(centerline, index, TrackBuilderCore.APEX_SAMPLE_SPAN)
		var entry_turn := signed_turn_at(centerline, index + TrackBuilderCore.APEX_SAMPLE_SPAN, TrackBuilderCore.APEX_SAMPLE_SPAN)
		var exit_turn := signed_turn_at(centerline, index - TrackBuilderCore.APEX_SAMPLE_SPAN, TrackBuilderCore.APEX_SAMPLE_SPAN)
		var strongest_turn := local_turn
		if absf(entry_turn) > absf(strongest_turn):
			strongest_turn = entry_turn
		if absf(exit_turn) > absf(strongest_turn):
			strongest_turn = exit_turn
		var severity := clampf(absf(strongest_turn) / 0.78, 0.0, 1.0)
		if severity < 0.04:
			offsets[index] = 0.0
			continue
		var apex_weight := clampf(absf(local_turn) / maxf(absf(strongest_turn), 0.001), 0.0, 1.0)
		apex_weight = pow(apex_weight, 1.45)
		var inward_offset := TrackBuilderCore.APEX_MAX_INWARD_OFFSET * severity * apex_weight
		inward_offset = minf(inward_offset, _driveable_inward_cap(centerline, index))
		var setup_offset := TrackBuilderCore.APEX_MAX_ENTRY_OFFSET * severity * (1.0 - apex_weight)
		offsets[index] = signf(strongest_turn) * (inward_offset - setup_offset)
	return _blend_s_curve_inflections(centerline, offsets)


static func _blend_s_curve_inflections(centerline: PackedVector2Array, offsets: PackedFloat32Array) -> PackedFloat32Array:
	# At an opposite-turn transition the outward setup offset flips sign while
	# still near its maximum, which folds the line across the inflection. Blend
	# the lateral offset back toward the centerline over the reversal window,
	# with a taper that peaks where the local turn is straight and fades toward
	# each half's apex. Single corners are untouched (their entry/exit turns
	# share a sign, so the reversal test never fires).
	var count := offsets.size()
	var result := offsets.duplicate()
	var span := TrackBuilderCore.APEX_SAMPLE_SPAN
	for index in count:
		var entry_turn := signed_turn_at(centerline, index + span, span)
		var exit_turn := signed_turn_at(centerline, index - span, span)
		if entry_turn * exit_turn >= 0.0:
			continue
		var local_turn := signed_turn_at(centerline, index, span)
		var weight := clampf(1.0 - absf(local_turn) / 0.25, 0.0, 1.0)
		result[index] = lerpf(result[index], 0.0, weight)
	return result


static func _driveable_inward_cap(centerline: PackedVector2Array, index: int) -> float:
	# Cap only the LOCAL apex budget: the inward cut at this sample may not pull
	# the apex below the geometry's own centerline floor. This bounds the apex
	# magnitude but not the final curve's curvature — the offset's second
	# derivative (setup flip, lane override) can still tighten it, which is what
	# the guidance-radius guard below catches.
	var radius := _centerline_radius(centerline, index)
	return maxf(0.0, radius - TrackSeedGen.MIN_DRIVE_RADIUS)


static func _centerline_radius(centerline: PackedVector2Array, index: int) -> float:
	var count := centerline.size()
	var span := TrackBuilderCore.APEX_SAMPLE_SPAN
	var a := centerline[(index - span + count) % count]
	var b := centerline[index]
	var c := centerline[(index + span) % count]
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ac := a.distance_to(c)
	if ab < 0.001 or bc < 0.001 or ac < 0.001:
		return INF
	var cross := absf((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))
	if cross < 0.001:
		return INF
	return ab * bc * ac / (2.0 * cross)


static func _enforce_guidance_radius(centerline: PackedVector2Array, offsets: PackedFloat32Array) -> PackedFloat32Array:
	# The apex cap and slew bound cannot alone guarantee the FINAL curve's local
	# radius (offset second derivatives still tighten it). Enforce the floor by
	# repeatedly relaxing the worst offending sample toward the centerline with an
	# arc-length taper, then re-applying the slew bound, until every sample meets
	# the floor. This keeps the correction inside the offending window instead of
	# scaling the whole line, so the rest of the racing line — apex cut, lane
	# override, straights — is preserved.
	var result := offsets.duplicate()
	var count := result.size()
	var radius_span := 3
	var relax_span := 6
	for _iteration in 40:
		var points := _offsets_to_points(centerline, result)
		var worst_index := -1
		var worst_radius := INF
		for index in count:
			var radius := _radius_at(points, index, radius_span)
			if radius < worst_radius:
				worst_radius = radius
				worst_index = index
		if worst_radius >= GUIDANCE_RADIUS_FLOOR - 1.0:
			break
		for offset in range(-relax_span, relax_span + 1):
			var index := (worst_index + offset + count) % count
			var taper := clampf(1.0 - absf(offset) / float(relax_span), 0.0, 1.0)
			result[index] = lerpf(result[index], 0.0, 0.4 * taper)
		result = _bounded_lateral_offsets(centerline, result)
	return result


static func _radius_at(points: PackedVector2Array, index: int, span: int) -> float:
	var count := points.size()
	var a := points[(index - span + count) % count]
	var b := points[index]
	var c := points[(index + span) % count]
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ac := a.distance_to(c)
	if ab < 0.001 or bc < 0.001 or ac < 0.001:
		return INF
	var cross := absf((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))
	if cross < 0.001:
		return INF
	return ab * bc * ac / (2.0 * cross)


static func _offsets_to_points(centerline: PackedVector2Array, offsets: PackedFloat32Array) -> PackedVector2Array:
	var line_points := PackedVector2Array()
	for index in centerline.size():
		var normal := TrackBuilderCore._sample_tangent(centerline, index).rotated(PI * 0.5)
		line_points.append(centerline[index] + normal * offsets[index])
	return line_points


static func _bounded_lateral_offsets(centerline: PackedVector2Array, offsets: PackedFloat32Array) -> PackedFloat32Array:
	# Bound the lateral-offset change per unit arc so an abrupt per-sample sign
	# or amplitude transition cannot fold the racing line back on itself. The
	# offset stays within the existing APEX_MAX_* envelope, so this only smooths
	# the transition into/out of corners and never pushes the line through the
	# island or outside the corridor. Forward/backward sweeps over the closed
	# loop repeat until every edge satisfies the bound, including the wrap.
	var count := offsets.size()
	var result := offsets.duplicate()
	var arc := PackedFloat32Array()
	arc.resize(count)
	for index in count:
		arc[index] = centerline[index].distance_to(centerline[(index + 1) % count])
	var changed := true
	var iterations := 0
	while changed and iterations < count * 2:
		changed = false
		iterations += 1
		for index in count:
			var previous_index := (index - 1 + count) % count
			var limit := arc[previous_index] * APEX_OFFSET_RATE_LIMIT
			var clamped := clampf(result[index], result[previous_index] - limit, result[previous_index] + limit)
			if not is_equal_approx(clamped, result[index]):
				changed = true
			result[index] = clamped
		for index in range(count - 1, -1, -1):
			var limit := arc[index] * APEX_OFFSET_RATE_LIMIT
			var clamped := clampf(result[index], result[(index + 1) % count] - limit, result[(index + 1) % count] + limit)
			if not is_equal_approx(clamped, result[index]):
				changed = true
			result[index] = clamped
	return result


static func signed_turn_at(centerline: PackedVector2Array, index: int, span: int) -> float:
	var count := centerline.size()
	var wrapped := posmod(index, count)
	var incoming := (
		centerline[wrapped]
		- centerline[posmod(wrapped - span, count)]
	).normalized()
	var outgoing := (
		centerline[posmod(wrapped + span, count)]
		- centerline[wrapped]
	).normalized()
	return incoming.angle_to(outgoing)


static func add_corner_set_pieces(root: Node2D, spec: Dictionary, room_polygon: PackedVector2Array, corridor: PackedVector2Array) -> void:
	var giants: Array = spec.get("corner_giants", [])
	if giants.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0)) * 7 + 3
	var candidates := PackedVector2Array()
	var count := room_polygon.size()
	for index in count:
		var corner: Vector2 = room_polygon[index]
		var toward_center := Vector2.ZERO
		for point: Vector2 in room_polygon:
			toward_center += point
		toward_center /= float(count)
		var inward := (toward_center - corner).normalized()
		candidates.append(corner + inward * 190.0)
	var placed := 0
	for candidate: Vector2 in candidates:
		if placed >= 3:
			break
		if Geometry2D.is_point_in_polygon(candidate, corridor):
			continue
		if TrackBuilderCore._distance_to_centerline(candidate, TrackBuilderCore._sample_centerline(spec["controls"])) < 200.0:
			continue
		var texture_path := String(giants[placed % giants.size()])
		var texture := load(texture_path) as Texture2D
		if texture == null:
			continue
		var prop := StaticBody2D.new()
		prop.name = "CornerGiant"
		prop.position = candidate
		prop.rotation = rng.randf_range(0.0, TAU)
		prop.collision_layer = 4
		TrackBuilderCore._mark_solid_body(prop, texture_path, &"corner_giant")
		root.add_child(prop)
		TrackBuilderCore._add_directional_shadow(prop, texture_path, 168.0, 1.0, Vector2(168.0, 168.0), true)
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		var sprite_scale := 215.0 / maxf(longest, 1.0)
		sprite.scale = Vector2.ONE * sprite_scale
		var entry: Dictionary = TrackBuilderCore.PROP_SHAPES.get(texture_path.get_file(), {})
		var offset := TrackBuilderCore._add_scaled_texture_collision(prop, texture, sprite_scale, StringName(entry.get("shape", &"circle")))
		sprite.position = -offset
		TrackBuilderCore._mark_solid_visual(sprite, texture_path, &"corner_giant")
		prop.add_child(sprite)
		placed += 1


static func island_apexes(inner_loop: PackedVector2Array) -> PackedVector2Array:
	var apexes := PackedVector2Array()
	var count := inner_loop.size()
	for index in count:
		var behind := (inner_loop[index] - inner_loop[(index - 12 + count) % count]).normalized()
		var ahead := (inner_loop[(index + 12) % count] - inner_loop[index]).normalized()
		var turn := behind.angle_to(ahead)
		if absf(turn) > 0.18 and (apexes.is_empty() or apexes[apexes.size() - 1].distance_to(inner_loop[index]) > 120.0):
			apexes.append(inner_loop[index])
	return apexes


static func add_paperclip_line(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, outer_loop: PackedVector2Array, room_polygon: PackedVector2Array) -> void:
	var count := centerline.size()
	var best_start := 0
	var best_straight := -1.0
	for index in count:
		var chord := centerline[(index + 20) % count].distance_to(centerline[(index + count - 20) % count])
		if chord > best_straight:
			best_straight = chord
			best_start = index
	var index := best_start
	var placed := 0
	var attempts := 0
	while placed < 18 and attempts < count:
		var tangent := (centerline[(index + 1) % count] - centerline[(index - 1 + count) % count]).normalized()
		var position := outer_loop[index] + (outer_loop[index] - centerline[index]).normalized() * 58.0
		if Geometry2D.is_point_in_polygon(position, room_polygon) and TrackBuilderCore._distance_to_centerline(position, centerline) >= 165.0:
			var clip := StaticBody2D.new()
			clip.name = "PaperclipLine"
			clip.position = position
			clip.rotation = tangent.angle()
			clip.collision_layer = 16
			TrackBuilderCore._mark_solid_body(clip, "res://assets/textures/imagine/paperclip.png", &"boundary_prop")
			root.add_child(clip)
			var shape := RectangleShape2D.new()
			shape.size = Vector2(16.0, 7.0)
			var cs := CollisionShape2D.new()
			cs.shape = shape
			clip.add_child(cs)
			TrackBuilderCore._record_shape_probe_points(clip, Vector2.ZERO, shape.size, &"rect")
			var texture := load("res://assets/textures/imagine/paperclip.png") as Texture2D
			if texture:
				var sprite := Sprite2D.new()
				sprite.texture = texture
				sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
				sprite.scale = Vector2.ONE * (16.0 / maxf(texture.get_width(), texture.get_height()))
				TrackBuilderCore._mark_solid_visual(sprite, "res://assets/textures/imagine/paperclip.png", &"boundary_prop")
				clip.add_child(sprite)
			placed += 1
		index = (index + 2) % count
		attempts += 1


