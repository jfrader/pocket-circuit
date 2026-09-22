class_name TrackRoomModel
extends RefCounted

const RECIPE_DATA := preload("res://data/tracks/v8_room_recipes.gd")

const CONSTRUCTION_MARGIN := 135.0
const LANE_SEPARATION := 320.0
const TWO_LANE_PORTAL_WIDTH := 590.0
const GRID_STEP := 1.0 / 16.0
const GEOMETRY_EPSILON := 0.001
const ARC_FLATTEN_ERROR := 0.02

const TIER_SIZE := {
	&"compact": Vector2(0.95, 0.95),
	&"standard": Vector2(1.0, 1.0),
	&"long": Vector2(1.62, 1.50),
	&"endurance": Vector2(2.35, 2.10),
	&"marathon": Vector2(3.35, 2.90),
}


static func legacy_fixture(family: StringName, coordinate_scale: float = 1.75) -> Dictionary:
	var base := RECIPE_DATA.legacy_outer(family)
	if base.is_empty() or not is_finite(coordinate_scale) or coordinate_scale <= 0.0:
		return _error(&"unknown_legacy_fixture", "Unknown legacy room fixture '%s'." % family)
	var outer := PackedVector2Array()
	for point: Vector2 in base:
		outer.append(point * coordinate_scale)
	return create({
		"recipe_id": 0,
		"recipe_revision": 1,
		"recipe_family": family,
		"room_seed": 0,
		"tier": &"fixture",
		"coordinate_scale": coordinate_scale,
		"outer": outer,
		"solid_exclusions": [],
		"regions": [],
		"portals": [],
	})


static func generate_recipe(family: StringName, room_seed: int, tier: StringName) -> Dictionary:
	var definition := RECIPE_DATA.recipe(family)
	if definition.is_empty():
		return _error(&"unknown_recipe", "Unknown polygon room recipe '%s'." % family)
	if not TIER_SIZE.has(tier):
		return _error(&"unknown_tier", "Unknown room tier '%s'." % tier)
	var tier_size: Vector2 = TIER_SIZE[tier]
	var base_half: Vector2 = definition["half_size"]
	var half := Vector2(
		base_half.x * tier_size.x * lerpf(0.94, 1.08, _hash_unit(room_seed, 0x31)),
		base_half.y * tier_size.y * lerpf(0.94, 1.08, _hash_unit(room_seed, 0x53))
	)
	var outer: PackedVector2Array
	var regions: Array[Dictionary]
	var portals: Array[Dictionary]
	var boundary_style := &"el_notch" if family == &"el" else &"paired_bays"
	if family == &"el":
		var base_notch: Vector2 = definition["notch"]
		var notch := Vector2(
			base_notch.x * tier_size.x + lerpf(-150.0, 150.0, _hash_unit(room_seed, 0x71)),
			base_notch.y * tier_size.y + lerpf(-125.0, 125.0, _hash_unit(room_seed, 0x97))
		)
		# The two arm dimensions and the notch move independently. Compact keeps
		# more than 450 units beyond the common junction in both required arms.
		notch.x = clampf(notch.x, -half.x + 900.0, half.x - 900.0)
		notch.y = clampf(notch.y, -half.y + 900.0, half.y - 900.0)
		outer = PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(notch.x, -half.y),
			Vector2(notch.x, notch.y), Vector2(half.x, notch.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y),
		])
		var portal_x := notch.x - 360.0
		var portal_center_y := clampf(notch.y + 470.0, -half.y + 310.0, half.y - 310.0)
		regions = [
			_region(&"vertical_arm", PackedVector2Array([Vector2(-half.x, -half.y), Vector2(notch.x, -half.y), Vector2(notch.x, half.y), Vector2(-half.x, half.y)]), true, half.y - notch.y),
			_region(&"horizontal_arm", PackedVector2Array([Vector2(-half.x, notch.y), Vector2(half.x, notch.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]), true, half.x - notch.x),
		]
		portals = [_portal_definition(&"el_junction", &"vertical_arm", &"horizontal_arm", Vector2(portal_x, portal_center_y - 330.0), Vector2(portal_x, portal_center_y + 330.0), 2)]
	else:
		var bevel := float(definition["bevel"]) * minf(tier_size.x, tier_size.y)
		var styles: Array = definition["boundary_styles"]
		boundary_style = styles[mini(styles.size() - 1, floori(_hash_unit(room_seed, 0x8B) * styles.size()))]
		var left_half_height := maxf(350.0, half.y * lerpf(0.34, 0.42, _hash_unit(room_seed, 0xA1)))
		var right_half_height := maxf(350.0, half.y * lerpf(0.34, 0.42, _hash_unit(room_seed, 0xC5)))
		var left_center_y := 0.0
		var right_center_y := 0.0
		var base_depth := maxf(380.0, half.x * 0.14)
		var left_depth := base_depth * lerpf(0.85, 1.25, _hash_unit(room_seed, 0xB3))
		var right_depth := base_depth * lerpf(0.85, 1.25, _hash_unit(room_seed, 0xD7))
		match boundary_style:
			&"offset_bays":
				left_half_height = maxf(520.0, half.y * 0.56)
				right_half_height = maxf(520.0, half.y * 0.56)
				var offset := minf(half.y * 0.18, minf(left_half_height, right_half_height) - 320.0)
				left_center_y = offset
				right_center_y = -offset
			&"asymmetric_bays":
				left_half_height = maxf(620.0, half.y * 0.68)
				right_half_height = maxf(350.0, half.y * 0.36)
				if _hash_unit(room_seed, 0xE9) < 0.5:
					var swapped_height := left_half_height
					left_half_height = right_half_height
					right_half_height = swapped_height
					left_depth *= 0.72
					right_depth *= 1.45
				else:
					left_depth *= 1.45
					right_depth *= 0.72
		left_half_height = minf(left_half_height, half.y - bevel - 20.0)
		right_half_height = minf(right_half_height, half.y - bevel - 20.0)
		left_center_y = clampf(left_center_y, -half.y + bevel + left_half_height, half.y - bevel - left_half_height)
		right_center_y = clampf(right_center_y, -half.y + bevel + right_half_height, half.y - bevel - right_half_height)
		var left_lower := left_center_y - left_half_height
		var left_upper := left_center_y + left_half_height
		var right_lower := right_center_y - right_half_height
		var right_upper := right_center_y + right_half_height
		outer = PackedVector2Array([
			Vector2(-half.x + bevel, -half.y), Vector2(half.x - bevel, -half.y),
			Vector2(half.x, -half.y + bevel), Vector2(half.x, right_lower),
			Vector2(half.x + right_depth, right_lower), Vector2(half.x + right_depth, right_upper),
			Vector2(half.x, right_upper), Vector2(half.x, half.y - bevel),
			Vector2(half.x - bevel, half.y), Vector2(-half.x + bevel, half.y),
			Vector2(-half.x, half.y - bevel), Vector2(-half.x, left_upper),
			Vector2(-half.x - left_depth, left_upper), Vector2(-half.x - left_depth, left_lower),
			Vector2(-half.x, left_lower), Vector2(-half.x, -half.y + bevel),
		])
		regions = [
			_region(&"west", PackedVector2Array([Vector2(-half.x + bevel, -half.y + bevel), Vector2(0, -half.y + bevel), Vector2(0, half.y - bevel), Vector2(-half.x + bevel, half.y - bevel)]), true, half.x),
			_region(&"east", PackedVector2Array([Vector2(0, -half.y + bevel), Vector2(half.x - bevel, -half.y + bevel), Vector2(half.x - bevel, half.y - bevel), Vector2(0, half.y - bevel)]), true, half.x),
			_region(&"west_bay", _rectangle_ring(Vector2(-half.x - left_depth * 0.5, left_center_y), Vector2(left_depth, left_half_height * 2.0)), false, left_depth),
			_region(&"east_bay", _rectangle_ring(Vector2(half.x + right_depth * 0.5, right_center_y), Vector2(right_depth, right_half_height * 2.0)), false, right_depth),
		]
		portals = [
			_portal_definition(&"core", &"west", &"east", Vector2(0, -310.0), Vector2(0, 310.0), 2),
			_portal_definition(&"west_bay_mouth", &"west", &"west_bay", Vector2(-half.x, -310.0), Vector2(-half.x, 310.0), 2),
			_portal_definition(&"east_bay_mouth", &"east", &"east_bay", Vector2(half.x, -310.0), Vector2(half.x, 310.0), 2),
		]
	var room := create({
		"recipe_id": int(definition["id"]),
		"recipe_revision": int(definition["revision"]),
		"recipe_family": family,
		"room_seed": room_seed,
		"tier": tier,
		"coordinate_scale": 1.0,
		"boundary_style": boundary_style,
		"outer": outer,
		"solid_exclusions": [],
		"regions": regions,
		"portals": portals,
	})
	if not bool(room.get("ok", false)):
		return room
	var checked_portals: Array[Dictionary] = []
	for portal: Dictionary in portals:
		var query := query_portal(room, portal["segment_from"], portal["segment_to"], int(portal["traversal_capacity"]))
		if not bool(query.get("valid", false)):
			return _error(&"recipe_portal", "Recipe '%s' does not preserve its two-lane portal." % family)
		var checked := portal.duplicate(true)
		checked.merge(query, true)
		checked_portals.append(checked)
	room["portals"] = checked_portals
	return room


static func create(source: Dictionary) -> Dictionary:
	var outer_value: Variant = source.get("outer", PackedVector2Array())
	if outer_value is not PackedVector2Array:
		return _error(&"invalid_outer", "Room outer ring must be a PackedVector2Array.")
	var outer_check := _validate_ring(outer_value, &"outer")
	if not bool(outer_check.get("valid", false)):
		return outer_check
	var outer := _canonical_ring(outer_value, true)
	outer_check = _validate_ring(outer, &"canonical outer")
	if not bool(outer_check.get("valid", false)):
		return outer_check
	var holes: Array[PackedVector2Array] = []
	var exclusions_value: Variant = source.get("solid_exclusions", [])
	if exclusions_value is not Array:
		return _error(&"invalid_holes", "Room exclusions must be an array of polygon rings.")
	for value: Variant in exclusions_value:
		if value is not PackedVector2Array:
			return _error(&"invalid_hole", "Every room exclusion must be a PackedVector2Array.")
		var check := _validate_ring(value, &"hole")
		if not bool(check.get("valid", false)):
			return check
		var hole := _canonical_ring(value, false)
		check = _validate_ring(hole, &"canonical hole")
		if not bool(check.get("valid", false)):
			return check
		if not _ring_strictly_inside(hole, outer):
			return _error(&"hole_outside", "Every solid exclusion must lie strictly inside the outer ring.")
		for previous: PackedVector2Array in holes:
			if _rings_intersect(hole, previous) or Geometry2D.is_point_in_polygon(hole[0], previous) or Geometry2D.is_point_in_polygon(previous[0], hole):
				return _error(&"holes_overlap", "Solid exclusions must be disjoint and may not contain one another.")
		holes.append(hole)
	holes.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool: return _ring_key(a) < _ring_key(b))
	var room := {
		"ok": true,
		"valid": true,
		"recipe_id": int(source.get("recipe_id", 0)),
		"recipe_revision": int(source.get("recipe_revision", 1)),
		"recipe_family": StringName(source.get("recipe_family", &"fixture")),
		"room_seed": int(source.get("room_seed", 0)),
		"tier": StringName(source.get("tier", &"fixture")),
		"coordinate_scale": float(source.get("coordinate_scale", 1.0)),
		"boundary_style": StringName(source.get("boundary_style", &"fixture")),
		"outer": outer,
		"solid_exclusions": holes,
		"regions": (source.get("regions", []) as Array).duplicate(true),
		"portals": (source.get("portals", []) as Array).duplicate(true),
		"free_components": [],
		"reserved_passages": [],
	}
	room["polygon_digest"] = polygon_digest(room)
	return room


static func erode(room: Dictionary, distance: float = CONSTRUCTION_MARGIN) -> Dictionary:
	if not bool(room.get("valid", false)) or not is_finite(distance) or distance < 0.0:
		return _error(&"invalid_erosion", "Erosion needs a valid room and non-negative distance.")
	var outer_offsets: Array[PackedVector2Array] = Geometry2D.offset_polygon(room["outer"], -distance, Geometry2D.JOIN_MITER)
	var components: Array[Dictionary] = []
	for contour: PackedVector2Array in outer_offsets:
		if contour.size() >= 3 and absf(_area(contour)) > GEOMETRY_EPSILON:
			components.append({"outer": _canonical_ring(contour, true), "holes": []})
	var inflated_exclusions: Array[PackedVector2Array] = []
	for hole: PackedVector2Array in room.get("solid_exclusions", []):
		var inflated: Array[PackedVector2Array] = Geometry2D.offset_polygon(hole, distance, Geometry2D.JOIN_MITER)
		for exclusion: PackedVector2Array in inflated:
			inflated_exclusions.append(_canonical_ring(exclusion, true))
	for exclusion: PackedVector2Array in _merge_exclusions(inflated_exclusions):
		components = _subtract_exclusion(components, exclusion)
	components.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _ring_key(a["outer"]) < _ring_key(b["outer"]))
	for component: Dictionary in components:
		(component["holes"] as Array).sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool: return _ring_key(a) < _ring_key(b))
	var result := room.duplicate(true)
	result["erosion_distance"] = distance
	result["free_components"] = components
	result["valid"] = not components.is_empty()
	result["ok"] = result["valid"]
	if components.is_empty():
		result["kind"] = &"empty_erosion"
		result["reason"] = "Room erosion removed every free-space component."
	return result


static func offset_ring(ring: PackedVector2Array, distance: float) -> Array[PackedVector2Array]:
	var check := _validate_ring(ring, &"offset")
	if not bool(check.get("valid", false)) or not is_finite(distance):
		return []
	var contours: Array[PackedVector2Array] = []
	for contour: PackedVector2Array in Geometry2D.offset_polygon(ring, distance, Geometry2D.JOIN_MITER):
		if contour.size() >= 3 and absf(_area(contour)) > GEOMETRY_EPSILON:
			contours.append(_canonical_ring(contour, _area(contour) > 0.0))
	contours.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool: return _ring_key(a) < _ring_key(b))
	return contours


static func contains_point(room: Dictionary, point: Vector2) -> bool:
	if not bool(room.get("valid", false)) or not Geometry2D.is_point_in_polygon(point, room["outer"]):
		return false
	for hole: PackedVector2Array in room.get("solid_exclusions", []):
		if Geometry2D.is_point_in_polygon(point, hole):
			return false
	return true


static func query_portal(room: Dictionary, segment_from: Vector2, segment_to: Vector2, traversals: int = 1) -> Dictionary:
	if not bool(room.get("valid", false)) or traversals < 1 or segment_from.distance_to(segment_to) <= GEOMETRY_EPSILON:
		return _error(&"invalid_portal", "Portal query needs a valid nonzero segment and at least one traversal.")
	var segment := segment_to - segment_from
	var parameters := PackedFloat64Array([0.0, 1.0])
	var boundaries: Array[PackedVector2Array] = [room["outer"]]
	boundaries.append_array(room.get("solid_exclusions", []))
	for ring: PackedVector2Array in boundaries:
		for index in ring.size():
			var crossing: Variant = Geometry2D.segment_intersects_segment(segment_from, segment_to, ring[index], ring[(index + 1) % ring.size()])
			if crossing is Vector2:
				parameters.append(clampf((crossing - segment_from).dot(segment) / segment.length_squared(), 0.0, 1.0))
	parameters.sort()
	var unique := PackedFloat64Array()
	for value: float in parameters:
		if unique.is_empty() or absf(value - unique[unique.size() - 1]) > 0.000001:
			unique.append(value)
	var intervals: Array[Vector2] = []
	for index in range(unique.size() - 1):
		var start := float(unique[index])
		var finish := float(unique[index + 1])
		if finish - start <= 0.000001 or not contains_point(room, segment_from.lerp(segment_to, (start + finish) * 0.5)):
			continue
		if not intervals.is_empty() and absf(intervals[intervals.size() - 1].y - start) <= 0.000001:
			intervals[intervals.size() - 1].y = finish
		else:
			intervals.append(Vector2(start, finish))
	var best := Vector2.ZERO
	var clear_width := 0.0
	for interval: Vector2 in intervals:
		var width := (interval.y - interval.x) * segment.length()
		if width > clear_width:
			clear_width = width
			best = interval
	var required_width := TWO_LANE_PORTAL_WIDTH if traversals == 2 else 2.0 * CONSTRUCTION_MARGIN + float(traversals - 1) * LANE_SEPARATION
	var capacity := 0 if clear_width + GEOMETRY_EPSILON < 2.0 * CONSTRUCTION_MARGIN else 1 + int(floor((clear_width - 2.0 * CONSTRUCTION_MARGIN + GEOMETRY_EPSILON) / LANE_SEPARATION))
	var valid := clear_width + GEOMETRY_EPSILON >= required_width
	var lanes := PackedVector2Array()
	if valid:
		var interval_center := (best.x + best.y) * 0.5
		for lane in traversals:
			var lane_offset := (float(lane) - float(traversals - 1) * 0.5) * LANE_SEPARATION / segment.length()
			lanes.append(segment_from.lerp(segment_to, interval_center + lane_offset))
	return {
		"ok": valid,
		"valid": valid,
		"kind": &"portal" if valid else &"portal_too_narrow",
		"clear_width": clear_width,
		"required_width": required_width,
		"traversal_capacity": capacity,
		"clear_interval": PackedVector2Array([segment_from.lerp(segment_to, best.x), segment_from.lerp(segment_to, best.y)]) if clear_width > 0.0 else PackedVector2Array(),
		"lane_centers": lanes,
	}


static func route_fits(room: Dictionary, route: Dictionary, clearance: float = CONSTRUCTION_MARGIN) -> Dictionary:
	if not bool(room.get("valid", false)) or not bool(route.get("ok", false)):
		return _error(&"invalid_placement", "Route placement needs a valid room and analytic route.")
	var eroded := erode(room, clearance + ARC_FLATTEN_ERROR)
	if not bool(eroded.get("valid", false)):
		return eroded
	var cells := _flatten_route(route)
	for component_index in (eroded["free_components"] as Array).size():
		var component: Dictionary = eroded["free_components"][component_index]
		var fits := true
		for cell: Dictionary in cells:
			if not _segment_in_component(cell["from"], cell["to"], component):
				fits = false
				break
		if fits:
			return {"ok": true, "valid": true, "component_index": component_index, "clearance": clearance, "cell_count": cells.size(), "method": &"eroded_free_polygon"}
	return _error(&"route_outside_free_space", "The analytic route sweep does not fit one eroded free-space component.")


static func polygon_digest(room: Dictionary) -> String:
	var fields := PackedStringArray()
	fields.append("outer:%s" % _ring_key(room["outer"]))
	for hole: PackedVector2Array in room.get("solid_exclusions", []):
		fields.append("hole:%s" % _ring_key(hole))
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update("|".join(fields).to_utf8_buffer())
	return context.finish().hex_encode()


static func _subtract_exclusion(components: Array[Dictionary], exclusion: PackedVector2Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for component: Dictionary in components:
		var outer: PackedVector2Array = component["outer"]
		var clipped: Array[PackedVector2Array] = Geometry2D.clip_polygons(outer, exclusion)
		if clipped.is_empty():
			continue
		var parsed := _components_from_contours(clipped)
		for next_component: Dictionary in parsed:
			for old_hole: PackedVector2Array in component["holes"]:
				if Geometry2D.is_point_in_polygon(old_hole[0], next_component["outer"]):
					next_component["holes"].append(old_hole)
			result.append(next_component)
	return result


static func _merge_exclusions(exclusions: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var disjoint: Array[PackedVector2Array] = []
	for exclusion: PackedVector2Array in exclusions:
		var pending := exclusion
		var index := 0
		while index < disjoint.size():
			var previous := disjoint[index]
			if not _rings_intersect(pending, previous) and not Geometry2D.is_point_in_polygon(pending[0], previous) and not Geometry2D.is_point_in_polygon(previous[0], pending):
				index += 1
				continue
			var merged: Array[PackedVector2Array] = Geometry2D.merge_polygons(pending, previous)
			if merged.is_empty():
				index += 1
				continue
			pending = _largest_ring(merged)
			disjoint.remove_at(index)
			index = 0
		disjoint.append(_canonical_ring(pending, true))
	disjoint.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool: return _ring_key(a) < _ring_key(b))
	return disjoint


static func _largest_ring(rings: Array[PackedVector2Array]) -> PackedVector2Array:
	var largest := PackedVector2Array()
	var largest_area := 0.0
	for ring: PackedVector2Array in rings:
		var area := absf(_area(ring))
		if area > largest_area:
			largest = ring
			largest_area = area
	return largest


static func _components_from_contours(contours: Array[PackedVector2Array]) -> Array[Dictionary]:
	var rings: Array[PackedVector2Array] = []
	for contour: PackedVector2Array in contours:
		if contour.size() >= 3 and absf(_area(contour)) > GEOMETRY_EPSILON:
			rings.append(_canonical_ring(contour, _area(contour) > 0.0))
	rings.sort_custom(func(a: PackedVector2Array, b: PackedVector2Array) -> bool:
		var area_a := absf(_area(a))
		var area_b := absf(_area(b))
		return area_a > area_b if not is_equal_approx(area_a, area_b) else _ring_key(a) < _ring_key(b)
	)
	var components: Array[Dictionary] = []
	for ring: PackedVector2Array in rings:
		var parent_index := -1
		var parent_area := INF
		for index in components.size():
			var candidate: PackedVector2Array = components[index]["outer"]
			var candidate_area := absf(_area(candidate))
			if candidate_area < parent_area and Geometry2D.is_point_in_polygon(ring[0], candidate):
				parent_index = index
				parent_area = candidate_area
		if parent_index < 0:
			components.append({"outer": _canonical_ring(ring, true), "holes": []})
		else:
			components[parent_index]["holes"].append(_canonical_ring(ring, false))
	return components


static func _segment_in_component(from: Vector2, to: Vector2, component: Dictionary) -> bool:
	if not Geometry2D.is_point_in_polygon(from, component["outer"]) or not Geometry2D.is_point_in_polygon(to, component["outer"]):
		return false
	var rings: Array[PackedVector2Array] = [component["outer"]]
	rings.append_array(component["holes"])
	for hole: PackedVector2Array in component["holes"]:
		if Geometry2D.is_point_in_polygon(from, hole) or Geometry2D.is_point_in_polygon(to, hole):
			return false
	for ring: PackedVector2Array in rings:
		for index in ring.size():
			var crossing: Variant = Geometry2D.segment_intersects_segment(from, to, ring[index], ring[(index + 1) % ring.size()])
			if crossing is Vector2 and crossing.distance_to(from) > GEOMETRY_EPSILON and crossing.distance_to(to) > GEOMETRY_EPSILON:
				return false
	return true


static func _flatten_route(route: Dictionary) -> Array[Dictionary]:
	var cells: Array[Dictionary] = []
	for primitive: Dictionary in route["primitives"]:
		var steps := 1
		if primitive["kind"] == &"arc":
			var radius := float(primitive["radius"])
			var angle_step := 2.0 * acos(clampf(1.0 - ARC_FLATTEN_ERROR / radius, -1.0, 1.0))
			steps = maxi(1, ceili(absf(float(primitive["signed_turn"])) / maxf(angle_step, 0.000001)))
		for step in steps:
			cells.append({"from": _primitive_point(primitive, float(step) / float(steps)), "to": _primitive_point(primitive, float(step + 1) / float(steps))})
	return cells


static func _primitive_point(primitive: Dictionary, fraction: float) -> Vector2:
	if primitive["kind"] == &"line":
		return (primitive["start"] as Vector2).lerp(primitive["end"], fraction)
	return (primitive["center"] as Vector2) + ((primitive["start"] as Vector2) - (primitive["center"] as Vector2)).rotated(float(primitive["signed_turn"]) * fraction)


static func _validate_ring(value: PackedVector2Array, role: StringName) -> Dictionary:
	if value.size() < 3:
		return _error(&"ring_too_small", "%s ring needs at least three vertices." % role)
	for index in value.size():
		var point := value[index]
		if not is_finite(point.x) or not is_finite(point.y):
			return _error(&"non_finite_ring", "%s ring contains a non-finite coordinate." % role)
		if point.distance_to(value[(index + 1) % value.size()]) <= GEOMETRY_EPSILON:
			return _error(&"zero_edge", "%s ring contains a zero-length edge." % role)
	if absf(_area(value)) <= GEOMETRY_EPSILON or _ring_self_intersects(value):
		return _error(&"invalid_ring", "%s ring must be simple and have nonzero area." % role)
	return {"ok": true, "valid": true}


static func _ring_strictly_inside(inner: PackedVector2Array, outer: PackedVector2Array) -> bool:
	for point: Vector2 in inner:
		if not Geometry2D.is_point_in_polygon(point, outer) or _distance_to_ring(point, outer) <= GEOMETRY_EPSILON:
			return false
	return not _rings_intersect(inner, outer)


static func _ring_self_intersects(ring: PackedVector2Array) -> bool:
	for first in ring.size():
		var first_next := (first + 1) % ring.size()
		for second in range(first + 1, ring.size()):
			var second_next := (second + 1) % ring.size()
			if first_next == second or second_next == first:
				continue
			if Geometry2D.segment_intersects_segment(ring[first], ring[first_next], ring[second], ring[second_next]) != null:
				return true
	return false


static func _rings_intersect(first: PackedVector2Array, second: PackedVector2Array) -> bool:
	for first_index in first.size():
		for second_index in second.size():
			if Geometry2D.segment_intersects_segment(first[first_index], first[(first_index + 1) % first.size()], second[second_index], second[(second_index + 1) % second.size()]) != null:
				return true
	return false


static func _canonical_ring(source: PackedVector2Array, positive_winding: bool) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for point: Vector2 in source:
		ring.append(Vector2(round(point.x / GRID_STEP) * GRID_STEP, round(point.y / GRID_STEP) * GRID_STEP))
	if (_area(ring) > 0.0) != positive_winding:
		ring.reverse()
	var start := 0
	for index in range(1, ring.size()):
		if ring[index].x < ring[start].x or (is_equal_approx(ring[index].x, ring[start].x) and ring[index].y < ring[start].y):
			start = index
	var canonical := PackedVector2Array()
	for index in ring.size():
		canonical.append(ring[(start + index) % ring.size()])
	return canonical


static func _area(ring: PackedVector2Array) -> float:
	var area := 0.0
	for index in ring.size():
		area += ring[index].cross(ring[(index + 1) % ring.size()])
	return area * 0.5


static func _distance_to_ring(point: Vector2, ring: PackedVector2Array) -> float:
	var minimum := INF
	for index in ring.size():
		minimum = minf(minimum, _point_segment_distance(point, ring[index], ring[(index + 1) % ring.size()]))
	return minimum


static func _point_segment_distance(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment := to - from
	var fraction := clampf((point - from).dot(segment) / maxf(segment.length_squared(), GEOMETRY_EPSILON), 0.0, 1.0)
	return point.distance_to(from + segment * fraction)


static func _ring_key(ring: PackedVector2Array) -> String:
	var values := PackedStringArray()
	for point: Vector2 in ring:
		values.append("%d,%d" % [roundi(point.x / GRID_STEP), roundi(point.y / GRID_STEP)])
	return ";".join(values)


static func _region(id: StringName, polygon: PackedVector2Array, required: bool, available_route_depth: float) -> Dictionary:
	return {"id": id, "polygon": polygon, "required": required, "available_route_depth": available_route_depth}


static func _rectangle_ring(center: Vector2, size: Vector2) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([center - half, center + Vector2(half.x, -half.y), center + half, center + Vector2(-half.x, half.y)])


static func _portal_definition(id: StringName, first: StringName, second: StringName, from: Vector2, to: Vector2, capacity: int) -> Dictionary:
	return {"id": id, "region_a": first, "region_b": second, "segment_from": from, "segment_to": to, "traversal_capacity": capacity}


static func _hash_unit(seed: int, salt: int) -> float:
	var value := seed ^ salt
	value = int((value ^ (value >> 16)) * 0x45D9F3B) & 0x7fffffff
	value = int((value ^ (value >> 16)) * 0x45D9F3B) & 0x7fffffff
	value = (value ^ (value >> 16)) & 0x7fffffff
	return float(value) / 2147483647.0


static func _error(kind: StringName, reason: String) -> Dictionary:
	return {"ok": false, "valid": false, "kind": kind, "reason": reason, "error": reason}
