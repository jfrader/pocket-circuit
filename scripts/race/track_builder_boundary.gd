class_name TrackBuilderBoundary
## Generated outer-boundary furniture and island-region clipping.


static func build_generated_outer_boundary_visuals(
	root: Node2D,
	spec: Dictionary,
	centerline: PackedVector2Array,
	inner_boundary: PackedVector2Array,
	outer_boundary: PackedVector2Array,
	room_polygon: PackedVector2Array,
	moments: Dictionary
) -> void:
	var assets: Dictionary = spec.get("generated_boundary", {})
	var section_path := String(assets.get("section", ""))
	var section_paths: Array = assets.get("sections", [section_path])
	var accent_path := String(assets.get("accent", ""))
	var section_textures: Array[Texture2D] = []
	for candidate_path: String in section_paths:
		var candidate_texture := load(candidate_path) as Texture2D
		if candidate_texture:
			section_textures.append(candidate_texture)
	var accent_texture := load(accent_path) as Texture2D if not accent_path.is_empty() else null
	if section_textures.is_empty() or accent_texture == null:
		push_error("TrackBuilderCore: generated boundary assets are missing")
		return
	var container := Node2D.new()
	container.name = "GeneratedOuterBoundaryVisuals"
	container.set_meta("section_asset", section_path)
	container.set_meta("section_assets", section_paths)
	container.set_meta("accent_asset", accent_path)
	container.set_meta("corridor_clearance", TrackBuilderCore.HALF_WIDTH)
	root.add_child(container)

	# Compose sparse runs instead of lining the whole course. Every seed gets
	# stretches with no furniture, one-sided stretches on each edge, and a small
	# number of both-sided moments. Rotating and mirroring the authored pattern
	# keeps that hierarchy deterministic without reading like a repeating fence.
	var rng := RandomNumberGenerator.new()
	rng.seed = TrackBuilderCore._mix_seed(int(spec.get("dressing_seed", spec["requested_seed"])), "boundary_runs:%s" % String(spec["story_id"]))
	var base_modes: Array[StringName] = [&"both", &"inner", &"both", &"outer", &"both", &"both", &"both", &"none"]
	var mode_offset := rng.randi_range(0, base_modes.size() - 1)
	for trial in base_modes.size():
		var candidate_offset := (mode_offset + trial) % base_modes.size()
		var open_run := posmod(base_modes.find(&"none") - candidate_offset, base_modes.size())
		if _open_run_has_apron(open_run, centerline, inner_boundary, room_polygon, spec.get("pockets", [])):
			mode_offset = candidate_offset
			break
	var swap_sides := rng.randf() < 0.5
	var run_modes: Array[StringName] = []
	var section_count := 0
	var outer_section_count := 0
	var inner_section_count := 0
	var one_sided_runs := 0
	var both_sided_runs := 0
	var empty_runs := 0
	var outer_runs := 0
	var inner_runs := 0
	for run_index in base_modes.size():
		var planned_mode: StringName = base_modes[(run_index + mode_offset) % base_modes.size()]
		var run_center := int(round((float(run_index) + 0.5) * float(centerline.size()) / float(base_modes.size()))) % centerline.size()
		if swap_sides:
			if planned_mode == &"outer":
				planned_mode = &"inner"
			elif planned_mode == &"inner":
				planned_mode = &"outer"
		var run_outer_sections := 0
		var run_inner_sections := 0
		if planned_mode != &"none":
			var run_half_span := rng.randi_range(7, 8)
			for sample_offset in range(-run_half_span, run_half_span + 1, 3):
				var centerline_index := posmod(run_center + sample_offset, centerline.size())
				if TrackBuilderCore._cyclic_index_distance(centerline_index, 0, centerline.size()) < 14:
					continue
				if planned_mode in [&"outer", &"both"]:
					if add_generated_boundary_section(container, section_textures, centerline, outer_boundary, room_polygon, centerline_index, run_index, &"outer", outer_section_count):
						outer_section_count += 1
						run_outer_sections += 1
						section_count += 1
				if planned_mode in [&"inner", &"both"]:
					if add_generated_boundary_section(container, section_textures, centerline, inner_boundary, room_polygon, centerline_index, run_index, &"inner", inner_section_count):
						inner_section_count += 1
						run_inner_sections += 1
						section_count += 1
			if planned_mode in [&"outer", &"both"] and run_outer_sections == 0:
				if add_generated_boundary_run_fallback(container, section_textures, centerline, outer_boundary, room_polygon, run_center, run_index, &"outer", outer_section_count):
					outer_section_count += 1
					run_outer_sections += 1
					section_count += 1
			if planned_mode in [&"inner", &"both"] and run_inner_sections == 0:
				if add_generated_boundary_run_fallback(container, section_textures, centerline, inner_boundary, room_polygon, run_center, run_index, &"inner", inner_section_count):
					inner_section_count += 1
					run_inner_sections += 1
					section_count += 1
			# A tight room edge can make one requested side physically impossible at
			# the full apron margin. Preserve the authored one-sided beat on the safe
			# edge rather than pulling its collider back into the driving corridor.
			if planned_mode == &"outer" and run_outer_sections == 0:
				if add_generated_boundary_run_fallback(container, section_textures, centerline, inner_boundary, room_polygon, run_center, run_index, &"inner", inner_section_count):
					inner_section_count += 1
					run_inner_sections += 1
					section_count += 1
			elif planned_mode == &"inner" and run_inner_sections == 0:
				if add_generated_boundary_run_fallback(container, section_textures, centerline, outer_boundary, room_polygon, run_center, run_index, &"outer", outer_section_count):
					outer_section_count += 1
					run_outer_sections += 1
					section_count += 1
		var actual_mode := &"both" if run_outer_sections > 0 and run_inner_sections > 0 else (&"outer" if run_outer_sections > 0 else (&"inner" if run_inner_sections > 0 else &"none"))
		run_modes.append(actual_mode)
		if actual_mode == &"none":
			empty_runs += 1
			# A flat ground hint gives the single open sector texture without
			# turning it into another barrier run.
			TrackBuilderCore._add_boundary_worn_hint(container, centerline, outer_boundary if rng.randf() > 0.5 else inner_boundary, run_center, room_polygon)
		elif actual_mode == &"both":
			both_sided_runs += 1
		else:
			one_sided_runs += 1
		if actual_mode in [&"outer", &"both"]:
			outer_runs += 1
		if actual_mode in [&"inner", &"both"]:
			inner_runs += 1

	var accent_count := 0
	var corners: PackedInt32Array = moments.get("corners", PackedInt32Array())
	for slot in range(corners.size() - 1, -1, -1):
		if accent_count >= 2 or slot % 2 != 0:
			continue
		var preferred_index := int(corners[slot])
		if TrackBuilderCore._cyclic_index_distance(preferred_index, 0, centerline.size()) < 18:
			continue
		var accent_scale := Vector2(160.0 / accent_texture.get_width(), 70.0 / accent_texture.get_height())
		var accent_footprint := TrackBuilderCore._texture_collision_footprint(accent_texture, &"convex", true)
		var accent_size: Vector2 = (accent_footprint["size"] as Vector2) * accent_scale + Vector2.ONE * 2.0
		var preferred_side := &"outer" if (slot + mode_offset) % 3 != 0 else &"inner"
		var placement := {}
		for index_offset: int in [0, -3, 3, -6, 6, -9, 9]:
			var index := posmod(preferred_index + index_offset, centerline.size())
			for side: StringName in [preferred_side, &"inner" if preferred_side == &"outer" else &"outer"]:
				var boundary := outer_boundary if side == &"outer" else inner_boundary
				var boundary_sample := closest_point_on_loop(centerline[index], boundary)
				var boundary_index := int(boundary_sample["index"])
				var boundary_position: Vector2 = boundary_sample["position"]
				var tangent := (boundary[(boundary_index + 1) % boundary.size()] - boundary[boundary_index]).normalized()
				var away_from_track := (boundary_position - centerline[index]).normalized()
				var position := boundary_position + away_from_track * 8.0
				position = push_footprint_outside_corridor(position, centerline, away_from_track, accent_size, tangent.angle())
				position = advance_footprint_outside_corridor(position, centerline, away_from_track, accent_size, tangent.angle())
				position = pull_inside_room(position, centerline, room_polygon)
				if (
					TrackBuilderCore._oriented_rect_inside_polygon(position, accent_size, tangent.angle(), room_polygon)
					and TrackBuilderCore._line_sweep_clears_footprint(centerline, position, accent_size, &"rect", tangent.angle(), TrackBuilderCore.HALF_WIDTH + TrackBuilderCore.APRON_COLLIDER_CLEARANCE)
				):
					placement = {"index": index, "side": side, "position": position, "rotation": tangent.angle()}
					break
			if not placement.is_empty():
				break
		if placement.is_empty():
			continue
		var index := int(placement["index"])
		var side := StringName(placement["side"])
		var position: Vector2 = placement["position"]
		var accent_body := StaticBody2D.new()
		accent_body.name = "CornerAccent%02d" % accent_count
		accent_body.position = position
		accent_body.rotation = float(placement["rotation"])
		accent_body.collision_layer = 16
		accent_body.z_index = -3
		accent_body.set_meta("boundary_kind", &"corner_mouth_accent")
		accent_body.set_meta("boundary_side", side)
		accent_body.set_meta("centerline_index", index)
		accent_body.set_meta("footprint_size", accent_size)
		TrackBuilderCore._mark_solid_body(accent_body, accent_path, &"boundary_prop")
		container.add_child(accent_body)
		var accent_offset := TrackBuilderCore._add_texture_collision(accent_body, accent_texture, accent_scale, &"convex", true, 2.0)
		TrackBuilderCore._add_directional_shadow(accent_body, accent_path, 160.0, 1.0, accent_size)
		var accent_sprite := Sprite2D.new()
		accent_sprite.name = "Sprite"
		accent_sprite.texture = accent_texture
		accent_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		accent_sprite.scale = accent_scale
		accent_sprite.position = -accent_offset
		TrackBuilderCore._mark_solid_visual(accent_sprite, accent_path, &"boundary_prop")
		accent_body.add_child(accent_sprite)
		accent_count += 1
	container.set_meta("section_count", section_count)
	container.set_meta("outer_section_count", outer_section_count)
	container.set_meta("inner_section_count", inner_section_count)
	container.set_meta("accent_count", accent_count)
	container.set_meta("run_modes", run_modes)
	container.set_meta("one_sided_run_count", one_sided_runs)
	container.set_meta("both_sided_run_count", both_sided_runs)
	container.set_meta("empty_run_count", empty_runs)
	container.set_meta("outer_run_count", outer_runs)
	container.set_meta("inner_run_count", inner_runs)
	container.set_meta("outer_accent_coverage", float(outer_runs) / 8.0 * 0.72)
	container.set_meta("inner_accent_coverage", float(inner_runs) / 8.0 * 0.72)
	root.set_meta("generated_outer_boundary", {
		"section_asset": section_path,
		"section_assets": section_paths,
		"accent_asset": accent_path,
		"section_count": section_count,
		"outer_section_count": outer_section_count,
		"inner_section_count": inner_section_count,
		"accent_count": accent_count,
		"run_modes": run_modes,
	})


static func _open_run_has_apron(run: int, centerline: PackedVector2Array, island: PackedVector2Array, room: PackedVector2Array, pockets: Array) -> bool:
	var center := int((float(run) + 0.5) * float(centerline.size()) / 8.0)
	for offset in range(-9, 10, 3):
		var index := posmod(center + offset, centerline.size())
		var normal := TrackBuilderCore._sample_tangent(centerline, index).orthogonal()
		for side: float in [-1.0, 1.0]:
			var target := centerline[index] + normal * side * 250.0
			if not Geometry2D.is_point_in_polygon(target, room) or Geometry2D.is_point_in_polygon(target, island):
				continue
			var in_bay := false
			for pocket: Dictionary in pockets:
				if Geometry2D.is_point_in_polygon(target, pocket.get("polygon", PackedVector2Array())):
					in_bay = true
					break
			if not in_bay:
				return true
	return false


static func add_generated_boundary_section(
	container: Node2D,
	textures: Array[Texture2D],
	centerline: PackedVector2Array,
	boundary: PackedVector2Array,
	room_polygon: PackedVector2Array,
	centerline_index: int,
	run_index: int,
	side: StringName,
	side_index: int
) -> bool:
	var texture := textures[posmod(run_index + side_index, textures.size())]
	var boundary_sample := closest_point_on_loop(centerline[centerline_index], boundary)
	var boundary_index := int(boundary_sample["index"])
	var boundary_position: Vector2 = boundary_sample["position"]
	var tangent := (boundary[(boundary_index + 1) % boundary.size()] - boundary[boundary_index]).normalized()
	var away_from_track := (boundary_position - centerline[centerline_index]).normalized()
	var sprite_scale := Vector2(156.0 / texture.get_width(), 56.0 / texture.get_height())
	var footprint := TrackBuilderCore._texture_collision_footprint(texture, &"convex", true)
	var footprint_size: Vector2 = (footprint["size"] as Vector2) * sprite_scale
	var position := boundary_position + away_from_track * 8.0
	position = push_footprint_outside_corridor(position, centerline, away_from_track, footprint_size, tangent.angle())
	position = advance_footprint_outside_corridor(position, centerline, away_from_track, footprint_size, tangent.angle())
	position = pull_inside_room(position, centerline, room_polygon)
	var nearest_centerline_sample := closest_point_on_loop(position, centerline)
	var nearest_centerline: Vector2 = nearest_centerline_sample["position"]
	var run_center := int(round((float(run_index) + 0.5) * float(centerline.size()) / 8.0)) % centerline.size()
	if (
		position.distance_to(nearest_centerline) < TrackBuilderCore.HALF_WIDTH
		or not TrackBuilderCore._oriented_rect_inside_polygon(position, footprint_size, tangent.angle(), room_polygon)
		or not TrackBuilderCore._line_sweep_clears_footprint(centerline, position, footprint_size, &"rect", tangent.angle(), TrackBuilderCore.HALF_WIDTH + TrackBuilderCore.APRON_COLLIDER_CLEARANCE)
		or TrackBuilderCore._cyclic_index_distance(int(nearest_centerline_sample["index"]), run_center, centerline.size()) >= centerline.size() / 16
	):
		return false
	var body := StaticBody2D.new()
	body.name = "%sSection%03d" % [String(side).capitalize(), side_index]
	body.position = position
	body.rotation = tangent.angle()
	body.collision_layer = 16
	body.z_index = -4
	body.set_meta("boundary_kind", &"partial_section")
	body.set_meta("boundary_side", side)
	body.set_meta("run_index", run_index)
	body.set_meta("centerline_index", centerline_index)
	body.set_meta("asset_path", texture.resource_path)
	body.set_meta("footprint_size", footprint_size)
	body.set_meta("visible_collision_backing", &"rail_sprite")
	TrackBuilderCore._mark_solid_body(body, texture.resource_path, &"rail")
	container.add_child(body)
	var offset := TrackBuilderCore._add_texture_collision(body, texture, sprite_scale, &"convex", true, 0.0)
	(body.get_node("AssetCollision") as CollisionShape2D).name = "RailCollision"
	TrackBuilderCore._add_directional_shadow(body, texture.resource_path, 156.0, 1.0, footprint_size)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.scale = sprite_scale
	sprite.position = -offset
	TrackBuilderCore._mark_solid_visual(sprite, texture.resource_path, &"rail")
	body.add_child(sprite)
	return true


static func add_generated_boundary_run_fallback(
	container: Node2D,
	textures: Array[Texture2D],
	centerline: PackedVector2Array,
	boundary: PackedVector2Array,
	room_polygon: PackedVector2Array,
	run_center: int,
	run_index: int,
	side: StringName,
	side_index: int
) -> bool:
	# The primary samples preserve authored spacing. Search nearest-first only when
	# a required side had no valid room/corridor placement at those samples.
	var sector_half_span := maxi(1, centerline.size() / 16 - 1)
	for distance in range(0, sector_half_span + 1):
		for direction in [-1, 1]:
			if distance == 0 and direction < 0:
				continue
			var centerline_index := posmod(run_center + distance * direction, centerline.size())
			if TrackBuilderCore._cyclic_index_distance(centerline_index, 0, centerline.size()) < 14:
				continue
			if add_generated_boundary_section(container, textures, centerline, boundary, room_polygon, centerline_index, run_index, side, side_index):
				return true
	return false


static func push_outside_corridor(position: Vector2, centerline: PackedVector2Array, fallback_direction: Vector2) -> Vector2:
	var nearest: Vector2 = closest_point_on_loop(position, centerline)["position"]
	var direction := (position - nearest).normalized()
	if direction.is_zero_approx():
		direction = fallback_direction
	var clearance := position.distance_to(nearest)
	return position + direction * maxf(TrackBuilderCore.HALF_WIDTH + 8.0 - clearance, 0.0)


static func push_footprint_outside_corridor(
		position: Vector2,
		centerline: PackedVector2Array,
		fallback_direction: Vector2,
		footprint_size: Vector2,
		rotation: float
) -> Vector2:
	var nearest: Vector2 = closest_point_on_loop(position, centerline)["position"]
	var direction := (position - nearest).normalized()
	if direction.is_zero_approx():
		direction = fallback_direction
	var local_direction := direction.rotated(-rotation)
	var half_size := footprint_size * 0.5
	var footprint_extent := absf(local_direction.x) * half_size.x + absf(local_direction.y) * half_size.y
	var required := TrackBuilderCore.HALF_WIDTH + TrackBuilderCore.APRON_COLLIDER_CLEARANCE + footprint_extent
	return position + direction * maxf(required - position.distance_to(nearest), 0.0)


static func advance_footprint_outside_corridor(
		position: Vector2,
		centerline: PackedVector2Array,
		fallback_direction: Vector2,
		footprint_size: Vector2,
		rotation: float
) -> Vector2:
	var result := position
	var direction := fallback_direction.normalized()
	for _attempt in 12:
		if TrackBuilderCore._line_sweep_clears_footprint(centerline, result, footprint_size, &"rect", rotation, TrackBuilderCore.HALF_WIDTH + TrackBuilderCore.APRON_COLLIDER_CLEARANCE):
			break
		var nearest: Vector2 = closest_point_on_loop(result, centerline)["position"]
		var updated_direction := (result - nearest).normalized()
		if not updated_direction.is_zero_approx():
			direction = updated_direction
		result += direction * 8.0
	return result


static func pull_inside_room(position: Vector2, centerline: PackedVector2Array, room_polygon: PackedVector2Array) -> Vector2:
	if Geometry2D.is_point_in_polygon(position, room_polygon):
		return position
	var nearest: Vector2 = closest_point_on_loop(position, centerline)["position"]
	var offset := position - nearest
	var direction := offset.normalized()
	for clearance in range(int(floor(offset.length())), int(TrackBuilderCore.HALF_WIDTH) - 1, -2):
		var candidate := nearest + direction * float(clearance)
		var candidate_nearest: Vector2 = closest_point_on_loop(candidate, centerline)["position"]
		if Geometry2D.is_point_in_polygon(candidate, room_polygon) and candidate.distance_to(candidate_nearest) >= TrackBuilderCore.HALF_WIDTH:
			return candidate
	return position


static func closest_point_on_loop(point: Vector2, loop: PackedVector2Array) -> Dictionary:
	var result := {"index": 0, "position": loop[0]}
	var nearest_distance := INF
	for index in loop.size():
		var from := loop[index]
		var to := loop[(index + 1) % loop.size()]
		var segment := to - from
		var fraction := clampf((point - from).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
		var candidate := from + segment * fraction
		var distance := point.distance_squared_to(candidate)
		if distance < nearest_distance:
			nearest_distance = distance
			result = {"index": index, "position": candidate}
	return result


static func island_region(room_polygon: PackedVector2Array, ribbon: PackedVector2Array, hint_polygon: PackedVector2Array) -> PackedVector2Array:
	var pieces: Array[PackedVector2Array] = Geometry2D.clip_polygons(room_polygon, ribbon)
	var hint_centroid := Vector2.ZERO
	for point: Vector2 in hint_polygon:
		hint_centroid += point
	hint_centroid /= float(hint_polygon.size())
	var best := PackedVector2Array()
	var best_score := -1.0
	for piece: PackedVector2Array in pieces:
		var score := 0.0
		for sample in 40:
			var index := int(float(sample) * float(hint_polygon.size()) / 40.0)
			var hint_point: Vector2 = hint_polygon[index].lerp(hint_centroid, 0.3)
			if Geometry2D.is_point_in_polygon(hint_point, piece):
				score += 1.0
		if score > best_score:
			best_score = score
			best = piece
	return best

