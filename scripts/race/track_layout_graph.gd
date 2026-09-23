class_name TrackLayoutGraph
extends RefCounted

const MODULES := preload("res://scripts/race/track_module_catalog.gd")
const ROOMS := preload("res://scripts/race/track_room_model.gd")
const VALIDATION := preload("res://scripts/race/track_layout_validation.gd")
const SIGNATURES := preload("res://scripts/race/track_layout_signatures.gd")
const RADIUS := MODULES.MIN_CONSTRUCTION_RADIUS
const LINK_MIN := 180.0
const CELL_MIN := 2.0 * RADIUS + LINK_MIN + 1.0
# A diagonal wedge edge must retain one link between its 45/135-degree bends.
const WEDGE_MIN := LINK_MIN / sqrt(2.0) + 2.0 * RADIUS + MODULES.POSITION_TOLERANCE
const CHAMFER_MIN := (LINK_MIN + 2.0 * RADIUS * tan(PI / 8.0)) / sqrt(2.0) + MODULES.POSITION_TOLERANCE
const FINISH_EDGE_MIN := 1000.0
const SETUP_EDGE_MIN := 520.0
const TECHNICAL_RADII: Array[float] = [RADIUS, 260.0, 360.0, 520.0]
const COMPOSITION_COUNT := 5
const TIER_SLOT_BUDGETS := {
	&"compact": Vector2i(6, 12),
	&"standard": Vector2i(8, 16),
	&"long": Vector2i(12, 24),
	&"endurance": Vector2i(18, 32),
	&"marathon": Vector2i(24, 48),
}


static func prepare(room: Dictionary) -> Dictionary:
	var required: Array[Dictionary] = []
	for region: Dictionary in room["regions"]:
		if bool(region.get("required", false)):
			required.append(region)
	if required.is_empty():
		return _failure(&"region_budget", "The room has no required region cells.")
	var portals: Array[Dictionary] = []
	var ids: Array = required.map(func(region: Dictionary) -> Variant: return region["id"])
	for portal: Dictionary in room["portals"]:
		if ids.has(portal["region_a"]) and ids.has(portal["region_b"]):
			portals.append(portal)
	if portals.is_empty():
		return _failure(&"region_connectivity", "Required regions have no connecting portal.")
	var free_room := ROOMS.erode(room, ROOMS.CONSTRUCTION_MARGIN + 2.0)
	var frames := {}
	for portal: Dictionary in portals:
		frames[portal["id"]] = _prepare_frame(required, free_room, portal)
	return {"ok": true, "portals": portals, "frames": frames}


static func _prepare_frame(required: Array[Dictionary], free_room: Dictionary, portal: Dictionary) -> Dictionary:
	var origin: Vector2 = (portal["segment_from"] + portal["segment_to"]) * 0.5
	var across: Vector2 = (portal["segment_to"] - portal["segment_from"]).normalized()
	var forward := Vector2(across.y, -across.x)
	var cells: Array[Dictionary] = []
	for region: Dictionary in required:
		var polygon := PackedVector2Array()
		for point: Vector2 in region["polygon"]:
			var delta := point - origin
			polygon.append(Vector2(delta.dot(forward), delta.dot(across)))
		var free_bounds := Rect2()
		for component: Dictionary in free_room.get("free_components", []):
			for intersection: PackedVector2Array in Geometry2D.intersect_polygons(region["polygon"], component["outer"]):
				var free_points := PackedVector2Array()
				for point: Vector2 in intersection:
					var delta := point - origin
					free_points.append(Vector2(delta.dot(forward), delta.dot(across)))
				var bounds := _inscribed_bounds(free_points)
				if bounds.get_area() > free_bounds.get_area():
					free_bounds = bounds
		if not free_bounds.has_area():
			return _failure(&"region_budget", "Required region '%s' has no reserved-width free space." % region["id"])
		cells.append({"id": region["id"], "polygon": polygon, "bounds": free_bounds})
	return {"ok": true, "origin": origin, "across": across, "forward": forward, "cells": cells}


static func build(room: Dictionary, band: Dictionary, identity: Dictionary, candidate: int, spatial: Dictionary = {}) -> Dictionary:
	var prepared := prepare(room) if spatial.is_empty() else spatial
	if not bool(prepared.get("ok", false)):
		return prepared.duplicate(true)
	var portals: Array[Dictionary] = prepared["portals"]
	var portal: Dictionary = portals[candidate % portals.size()]
	var frame: Dictionary = prepared["frames"][portal["id"]]
	if not bool(frame.get("ok", false)):
		return frame.duplicate(true)
	var origin: Vector2 = frame["origin"]
	var across: Vector2 = frame["across"]
	var forward: Vector2 = frame["forward"]
	var cells: Array[Dictionary] = frame["cells"]
	var unit := _unit(identity, candidate)
	var target_fraction := 0.02 + unit * 0.96
	var target := lerpf(float(band["min_length"]), float(band["max_length"]), target_fraction)
	var maximum_half_height := (portal["segment_to"] as Vector2).distance_to(portal["segment_from"]) * 0.5 - 10.0
	for cell: Dictionary in cells:
		var bounds: Rect2 = cell["bounds"]
		maximum_half_height = minf(maximum_half_height, minf(-bounds.position.y, bounds.end.y))
	var minimum_half_height := RADIUS + MODULES.POSITION_TOLERANCE
	if maximum_half_height < minimum_half_height:
		return _failure(&"portal_turn_envelope", "The selected portal cannot carry two turns with an in-domain link between them.")
	var composition_count := COMPOSITION_COUNT
	var composition := candidate % composition_count
	var height_unit := _unit(identity, candidate + 137)
	var half_height := lerpf(minimum_half_height, maximum_half_height, height_unit)
	var left := 0.0
	var right := 0.0
	for cell: Dictionary in cells:
		var bounds: Rect2 = cell["bounds"]
		left = minf(left, bounds.position.x)
		right = maxf(right, bounds.end.x)
	# Region masks may overlap at a junction. Budget real occupation beyond
	# that overlap, rather than crediting both visits to the same trunk.
	var required_depth := 0.0
	var required_cell_index := -1
	var required_outer_y := INF
	for cell_index in cells.size():
		var cell: Dictionary = cells[cell_index]
		var bounds: Rect2 = cell["bounds"]
		for other: Dictionary in cells:
			if other["id"] == cell["id"]:
				continue
			var overlap := bounds.intersection(other["bounds"])
			if overlap.has_area() and bounds.position.y < overlap.position.y - 450.0:
				required_depth = maxf(required_depth, maxf(CELL_MIN, -half_height - overlap.position.y + 450.0))
				required_outer_y = minf(required_outer_y, overlap.position.y - 450.0)
				required_cell_index = cell_index
	var finish_domain: Array = MODULES.definition(&"straight_setup")["parameter_domains"]["finish_length"]
	var minimum_width := float(finish_domain[0]) + 2.0 * RADIUS
	if right - left < minimum_width:
		return _failure(&"finish_budget", "Region span %.2f is below the %.2f finish-and-turn envelope." % [right - left, minimum_width])
	var desired_excursions := int(composition > 0 or required_depth > 0.0)
	var excursion_cell := required_cell_index if required_cell_index >= 0 else int(_unit(identity, candidate + 271) * cells.size()) % cells.size()
	var excursion_side := -1.0 if required_depth > 0.0 or _unit(identity, candidate + 313) < 0.5 else 1.0
	var excursion_bounds: Rect2 = cells[excursion_cell]["bounds"]
	var minimum_excursion_depth := CHAMFER_MIN if composition == 3 else (WEDGE_MIN if composition in [2, 4] else CELL_MIN)
	var side_extent := -excursion_bounds.position.y if excursion_side < 0.0 else excursion_bounds.end.y
	if required_cell_index < 0 and side_extent - minimum_excursion_depth < minimum_half_height:
		excursion_side *= -1.0
		side_extent = -excursion_bounds.position.y if excursion_side < 0.0 else excursion_bounds.end.y
	var extra_excursions: Array[Dictionary] = []
	if composition == 1:
		var extra_count := mini(cells.size() * 2 - 1, floori(float(candidate) / float(composition_count)))
		for extra in extra_count:
			var next_cell := (excursion_cell + extra + 1) % cells.size()
			var first_side := excursion_side if next_cell == excursion_cell or _unit(identity, candidate * 31 + next_cell + 1931) < 0.5 else -excursion_side
			var next_side := first_side if extra + 1 < cells.size() else -first_side
			var bounds: Rect2 = cells[next_cell]["bounds"]
			var extent := -bounds.position.y if next_side < 0.0 else bounds.end.y
			var span := _excursion_range(bounds, left, right)
			if extent - CELL_MIN >= minimum_half_height and span.y - span.x >= CELL_MIN:
				extra_excursions.append({"cell": next_cell, "side": next_side, "extent": extent})
	if desired_excursions > 0 and side_extent - minimum_excursion_depth >= minimum_half_height:
		var height_limit := minf(maximum_half_height, side_extent - minimum_excursion_depth)
		for extra: Dictionary in extra_excursions:
			height_limit = minf(height_limit, float(extra["extent"]) - CELL_MIN)
		var excursion_count := extra_excursions.size() + 1
		if excursion_count > 2:
			var extent_sum := side_extent
			for extra: Dictionary in extra_excursions:
				extent_sum += float(extra["extent"])
			var constant_length := 2.0 * (right - left) + 2.0 * extent_sum - (8.0 - TAU) * RADIUS - float(excursion_count) * (4.0 - PI) * RADIUS
			var height_cost := float(2 * excursion_count - 4)
			var capacity := constant_length - height_cost * minimum_half_height
			if capacity >= float(band["min_length"]):
				target = lerpf(float(band["min_length"]), minf(float(band["max_length"]), capacity), target_fraction)
				height_limit = minf(height_limit, (constant_length - target) / height_cost)
		half_height = lerpf(minimum_half_height, maxf(minimum_half_height, height_limit), height_unit)
		if required_cell_index >= 0:
			required_depth = maxf(CELL_MIN, -half_height - required_outer_y)
	var excursion_available := side_extent - half_height
	if not extra_excursions.is_empty() and excursion_available >= minimum_excursion_depth:
		var base_length := 2.0 * (right - left) + 4.0 * half_height - (8.0 - TAU) * RADIUS
		var other_capacity := _excursion_capacity(extra_excursions, 0, half_height)
		minimum_excursion_depth = minf(excursion_available, maxf(minimum_excursion_depth, (target - base_length - other_capacity + (4.0 - PI) * RADIUS) * 0.5))
	var excursion_depth := 0.0
	if desired_excursions > 0 and excursion_available >= minimum_excursion_depth:
		excursion_depth = maxf(required_depth, lerpf(minimum_excursion_depth, excursion_available, _unit(identity, candidate + 347)))
	var excursion_length_budget := 2.0 * sqrt(2.0) * excursion_depth if composition == 4 else 2.0 * excursion_depth
	var width := clampf((target - 4.0 * half_height + (8.0 - TAU) * RADIUS - excursion_length_budget) * 0.5, minimum_width, right - left)
	var left_share := clampf(-left / maxf(right - left, 1.0), 0.38, 0.62)
	if desired_excursions > 0:
		left_share = 0.62 if excursion_bounds.get_center().x < 0.0 else 0.38
	left = maxf(left, -width * left_share)
	right = minf(right, width * (1.0 - left_share))
	var ring := _rectangle(Rect2(Vector2(left, -half_height), Vector2(right - left, 2.0 * half_height)))
	var region_budgets: Array[Dictionary] = []
	var bevel_cuts: Array[PackedVector2Array] = []
	var attempted_excursion_span := 0.0
	var attempted_excursion_width := 0.0
	for cell_index in cells.size():
		var cell: Dictionary = cells[cell_index]
		var bounds: Rect2 = cell["bounds"]
		if desired_excursions == 0 or cell_index != excursion_cell:
			region_budgets.append({"region_id": cell["id"], "excursion_count": 0, "available_area": bounds.get_area()})
			continue
		var excursion_range := _excursion_range(bounds, left, right)
		var x0 := excursion_range.x
		var x1 := excursion_range.y
		var allocated := 0
		var excursion_span := x1 - x0
		var maximum_bay_width := minf(excursion_span, right - left - CELL_MIN)
		attempted_excursion_span = excursion_span
		attempted_excursion_width = maximum_bay_width
		var minimum_bay_width := CELL_MIN + CHAMFER_MIN if composition == 3 else (WEDGE_MIN if composition in [2, 4] else CELL_MIN)
		if maximum_bay_width >= minimum_bay_width and excursion_depth >= minimum_excursion_depth:
			var bay_width := lerpf(minimum_bay_width, maximum_bay_width, _unit(identity, candidate + 379))
			var can_merge := true
			if composition in [2, 4]:
				bay_width = minf(bay_width, excursion_depth)
				excursion_depth = bay_width
			elif composition == 3:
				excursion_depth = minf(excursion_depth, maximum_bay_width - CELL_MIN)
				if excursion_depth < CHAMFER_MIN:
					can_merge = false
				else:
					bay_width = lerpf(excursion_depth + CELL_MIN, maximum_bay_width, _unit(identity, candidate + 379))
			if excursion_depth < required_depth:
				can_merge = false
			if can_merge:
				var from_x := x0 if excursion_bounds.get_center().x < 0.0 else x1 - bay_width
				var bevel := _excursion_bevel(identity, candidate, cell_index, bay_width, excursion_depth) if composition == 1 else 0.0
				var extension := _excursion_polygon(from_x, bay_width, half_height, excursion_depth, excursion_side, composition, excursion_bounds.get_center().x < 0.0)
				var merged := Geometry2D.merge_polygons(ring, extension)
				if merged.size() == 1:
					ring = merged[0]
					allocated = 1
					if bevel > 0.0:
						bevel_cuts.append(_excursion_cut(from_x, bay_width, half_height, excursion_depth, excursion_side, excursion_bounds.get_center().x < 0.0, bevel))
		region_budgets.append({"region_id": cell["id"], "excursion_count": allocated, "available_area": bounds.get_area()})
	if not extra_excursions.is_empty():
		for extra in extra_excursions.size():
			var next_cell := int(extra_excursions[extra]["cell"])
			var next_side := float(extra_excursions[extra]["side"])
			var next_bounds: Rect2 = cells[next_cell]["bounds"]
			var next_range := _excursion_range(next_bounds, left, right)
			var next_available := -half_height - next_bounds.position.y if next_side < 0.0 else next_bounds.end.y - half_height
			var next_width := next_range.y - next_range.x
			if next_available < CELL_MIN or next_width < CELL_MIN:
				continue
			var remaining := target - _ring_length(_simplify_polygon(ring))
			var future_capacity := _excursion_capacity(extra_excursions, extra + 1, half_height)
			var needed_depth := maxf(CELL_MIN, (remaining - future_capacity + (4.0 - PI) * RADIUS) * 0.5)
			var next_depth := clampf((remaining / float(extra_excursions.size() - extra) + (4.0 - PI) * RADIUS) * 0.5, minf(needed_depth, next_available), next_available)
			next_width = lerpf(CELL_MIN, next_width, _unit(identity, candidate * 17 + extra + 1871))
			var anchored_left := next_bounds.get_center().x < 0.0
			var next_from := next_range.x if anchored_left else next_range.y - next_width
			var bevel := _excursion_bevel(identity, candidate, extra + cells.size(), next_width, next_depth)
			var extension := _excursion_polygon(next_from, next_width, half_height, next_depth, next_side, 1, anchored_left)
			var merged := Geometry2D.merge_polygons(ring, extension)
			if merged.size() == 1:
				ring = merged[0]
				(region_budgets[next_cell] as Dictionary)["excursion_count"] = int(region_budgets[next_cell]["excursion_count"]) + 1
				if bevel > 0.0:
					bevel_cuts.append(_excursion_cut(next_from, next_width, half_height, next_depth, next_side, anchored_left, bevel))
	if composition == 4 and cells.size() > 1:
		var second_cell := (excursion_cell + 1) % cells.size()
		var second_bounds: Rect2 = cells[second_cell]["bounds"]
		var second_side := excursion_side if _unit(identity, candidate + 433) < 0.5 else -excursion_side
		var second_available := -half_height - second_bounds.position.y if second_side < 0.0 else second_bounds.end.y - half_height
		var second_range := _excursion_range(second_bounds, left, right)
		var second_span := second_range.y - second_range.x
		var second_depth := minf(second_available, minf(second_span, excursion_depth))
		if second_depth >= WEDGE_MIN:
			var second_from_x := second_range.x if second_bounds.get_center().x < 0.0 else second_range.y - second_depth
			var second_extension := _excursion_polygon(second_from_x, second_depth, half_height, second_depth, second_side, 2, second_bounds.get_center().x < 0.0)
			var second_merged := Geometry2D.merge_polygons(ring, second_extension)
			if second_merged.size() == 1:
				ring = second_merged[0]
				(region_budgets[second_cell] as Dictionary)["excursion_count"] = 1
	if desired_excursions > 0 and (region_budgets[excursion_cell] as Dictionary)["excursion_count"] == 0:
		return _failure(&"region_excursion_budget", "The selected graph composition could not place its required region excursion (span=%.2f max_width=%.2f depth=%.2f available=%.2f)." % [attempted_excursion_span, attempted_excursion_width, excursion_depth, excursion_available])
	if composition == 4 and cells.size() > 1 and (region_budgets[(excursion_cell + 1) % cells.size()] as Dictionary)["excursion_count"] == 0:
		return _failure(&"region_excursion_budget", "The double-wedge composition could not place its second region excursion.")
	ring = _simplify_polygon(ring)
	var slot_budget: Vector2i = TIER_SLOT_BUDGETS[StringName(identity["length_tier"])]
	# The available span inside the required regions can cap the ring below the
	# length floor (a short or narrow room for the tier). Grow authored lobes
	# until the loop can reach the band, or reject this candidate cheaply instead
	# of spending search budget on a route that can never satisfy the contract.
	var top_up_attempts := 0
	while _ring_length(ring) < float(band["min_length"]) and top_up_attempts < cells.size() * 2:
		top_up_attempts += 1
		var grown := false
		for cell_index in cells.size():
			var bounds: Rect2 = cells[cell_index]["bounds"]
			var range_x := _excursion_range(bounds, left, right)
			var lobe_width := range_x.y - range_x.x
			if lobe_width < CELL_MIN:
				continue
			for for_side: float in [-1.0, 1.0]:
				var available := -half_height - bounds.position.y if for_side < 0.0 else bounds.end.y - half_height
				if available < CELL_MIN:
					continue
				var depth := minf(available, maxf(CELL_MIN, (float(band["min_length"]) - _ring_length(ring)) * 0.5))
				var anchored_left := bounds.get_center().x < 0.0
				var from_x := range_x.x if anchored_left else range_x.y - lobe_width
				var extension := _excursion_polygon(from_x, lobe_width, half_height, depth, for_side, 0, anchored_left)
				var merged := Geometry2D.merge_polygons(ring, extension)
				if merged.size() != 1:
					continue
				var proposed := _simplify_polygon(merged[0])
				# A lobe adds vertices on the edge it attaches to, which would
				# split the long straight that must host the finish. Keep the
				# longest edge able to carry it.
				if proposed.size() * 2 > slot_budget.y or _ring_length(proposed) <= _ring_length(ring) or _longest_edge_length(proposed) < FINISH_EDGE_MIN + 2.0 * RADIUS:
					continue
				ring = proposed
				grown = true
				break
			if grown:
				break
		if not grown:
			break
	if _ring_length(ring) < float(band["min_length"]):
		return _failure(&"length_capacity", "Region span cannot reach the %.0f length floor; best ring reaches %.2f." % [float(band["min_length"]), _ring_length(ring)])
	bevel_cuts.append_array(_ring_chamfer_cuts(ring, identity, candidate))
	for cut: PackedVector2Array in bevel_cuts:
		var pieces := Geometry2D.clip_polygons(ring, cut)
		if pieces.size() != 1:
			continue
		var proposed := _simplify_polygon(pieces[0])
		if proposed.size() * 2 <= slot_budget.y and _ring_length(proposed) >= float(band["min_length"]):
			ring = proposed
	if Geometry2D.is_polygon_clockwise(ring):
		ring.reverse()
	var graph := _embed_ring(ring, identity, candidate, slot_budget.y, float(band["min_length"]))
	if not bool(graph.get("ok", false)):
		return graph
	graph["start_position"] = origin + forward * (graph["start_position"] as Vector2).x + across * (graph["start_position"] as Vector2).y
	graph["start_heading"] = float(graph["start_heading"]) + forward.angle()
	graph["region_budgets"] = region_budgets
	graph["portal_counts"] = {}
	var target_modules: Array[Dictionary] = []
	for slot: Dictionary in (graph["ordinary_slots"] as Array) + (graph["closure_targets"] as Array):
		target_modules.append(MODULES.instantiate(slot["module_id"], slot["parameters"]))
	var target_route := MODULES.compose(target_modules, graph["start_position"], graph["start_heading"])
	graph["target_structure"] = SIGNATURES.describe(target_route)["structural"]
	if float(target_route["length"]) > float(band["max_length"]):
		return _failure(&"module_length_budget", "Proposed modules consume %.2f units; band ceiling is %.2f." % [float(target_route["length"]), float(band["max_length"])])
	for connection: Dictionary in portals:
		var crossings := portal_crossings(target_route, connection)
		var count := (crossings["points"] as PackedVector2Array).size()
		if count < 2 or count % 2 != 0 or count > int(connection["traversal_capacity"]):
			return _failure(&"portal_traversal_budget", "Region cycle crosses portal '%s' %d times; a closed visit needs a positive even count within capacity %d." % [connection["id"], count, int(connection["traversal_capacity"])])
		graph["portal_counts"][connection["id"]] = count
	graph["slot_budget"] = slot_budget
	if (graph["ordinary_slots"] as Array).size() + 3 > (graph["slot_budget"] as Vector2i).y:
		return _failure(&"slot_budget", "Region traversal needs %d slots; length-band budget allows %d." % [(graph["ordinary_slots"] as Array).size() + 3, (graph["slot_budget"] as Vector2i).y])
	return graph


static func _embed_ring(ring: PackedVector2Array, identity: Dictionary, candidate: int, slot_limit: int = 64, minimum_length: float = 0.0) -> Dictionary:
	var slots: Array[Dictionary] = []
	var poses: Array[Dictionary] = []
	var mixed := false
	var corners: Array[Dictionary] = []
	var trims: Array[Vector2] = []
	var return_corners := {}
	var return_pairs := 0
	var reserved_length := _ring_length(ring)
	for index in ring.size():
		var incoming := (ring[index] - ring[posmod(index - 1, ring.size())]).normalized()
		var outgoing := (ring[(index + 1) % ring.size()] - ring[index]).normalized()
		var angle_deg := rad_to_deg(absf(atan2(incoming.cross(outgoing), incoming.dot(outgoing))))
		var supported_angle: float = float([45.0, 90.0, 135.0].reduce(func(best: float, value: float) -> float: return value if absf(value - angle_deg) < absf(best - angle_deg) else best, 45.0))
		if absf(supported_angle - angle_deg) > 0.01:
			return _failure(&"unsupported_turn_angle", "Region turn %.3f degrees is outside the catalog's 45/90/135-degree domain." % angle_deg)
		var corner := _slot(&"corner_tight", {"radius": RADIUS, "angle_deg": supported_angle, "hand": signf(incoming.cross(outgoing))}, &"technical")
		corners.append(corner)
		trims.append(_corner_trims(MODULES.instantiate(corner["module_id"], corner["parameters"])))
	for index in ring.size():
		var next := (index + 1) % ring.size()
		var edge_length := ring[index].distance_to(ring[next])
		var required_return := edge_length - trims[index].y - trims[next].x < LINK_MIN or _ring_slot_count(ring, trims) - return_pairs > slot_limit
		if not required_return and _unit(identity, candidate * 61 + index + 2393) >= 0.5:
			continue
		if return_corners.has(index) or return_corners.has(next):
			continue
		var first: Dictionary = corners[index]["parameters"]
		var last: Dictionary = corners[next]["parameters"]
		var radius := edge_length * 0.5
		if not is_equal_approx(float(first["angle_deg"]), 90.0) or not is_equal_approx(float(last["angle_deg"]), 90.0) or first["hand"] != last["hand"] or radius < RADIUS or radius > 520.0:
			continue
		var length_loss := (4.0 - PI) * (radius - RADIUS)
		if not required_return and reserved_length - length_loss < minimum_length:
			continue
		reserved_length -= length_loss
		var module_id := &"corner_tight" if radius < 260.0 else (&"corner_medium" if radius < 520.0 else &"corner_sweeper")
		return_pairs += 1
		for corner_index in [index, next]:
			corners[corner_index] = _slot(module_id, {"radius": radius, "angle_deg": 90.0, "hand": first["hand"]}, &"technical")
			trims[corner_index] = Vector2(radius, radius)
			return_corners[corner_index] = true
	var edge_reservations: Array[float] = []
	var available_edges: Array[Dictionary] = []
	var embedded_length := 0.0
	for index in ring.size():
		var next := (index + 1) % ring.size()
		var length := ring[index].distance_to(ring[next]) - trims[index].y - trims[next].x
		embedded_length += length + float(MODULES.instantiate(corners[index]["module_id"], corners[index]["parameters"])["length"])
		edge_reservations.append(LINK_MIN if length > MODULES.POSITION_TOLERANCE else 0.0)
		available_edges.append({"index": index, "length": length})
	available_edges.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["length"]) > float(b["length"]))
	if float(available_edges[0]["length"]) >= FINISH_EDGE_MIN:
		edge_reservations[int(available_edges[0]["index"])] = FINISH_EDGE_MIN
	if available_edges.size() > 1 and float(available_edges[1]["length"]) >= SETUP_EDGE_MIN:
		edge_reservations[int(available_edges[1]["index"])] = SETUP_EDGE_MIN
	var first_corner := int(_unit(identity, candidate + 2179) * ring.size()) % ring.size()
	for step in ring.size():
		var index := (first_corner + step) % ring.size()
		if return_corners.has(index):
			continue
		var previous := posmod(index - 1, ring.size())
		var next := (index + 1) % ring.size()
		var available := Vector2(ring[index].distance_to(ring[previous]) - trims[previous].y - edge_reservations[previous], ring[index].distance_to(ring[next]) - trims[next].x - edge_reservations[index])
		var parameters: Dictionary = corners[index]["parameters"]
		var prior_length := float(MODULES.instantiate(corners[index]["module_id"], parameters)["length"])
		var prior_loss := trims[index].x + trims[index].y - prior_length
		var maximum_loss := prior_loss + maxf(0.0, embedded_length - minimum_length)
		var corner := _corner_slot(float(parameters["hand"]), float(parameters["angle_deg"]), available, candidate, index, maximum_loss, _unit(identity, candidate + 2281))
		corners[index] = corner
		var module := MODULES.instantiate(corner["module_id"], corner["parameters"])
		trims[index] = _corner_trims(module)
		embedded_length += prior_loss - (trims[index].x + trims[index].y - float(module["length"]))
	for index in ring.size():
		var next := (index + 1) % ring.size()
		var direction := (ring[next] - ring[index]).normalized()
		var outgoing := (ring[(index + 2) % ring.size()] - ring[next]).normalized()
		var length := ring[index].distance_to(ring[next]) - trims[index].y - trims[next].x
		if length < -MODULES.POSITION_TOLERANCE or (length > MODULES.POSITION_TOLERANCE and length < LINK_MIN):
			return _failure(&"cell_turn_envelope", "Region edge %.2f leaves a %.2f link after %.2f/%.2f turn trims; catalog minimum is %.2f." % [ring[index].distance_to(ring[next]), length, trims[index].y, trims[next].x, LINK_MIN])
		var start := ring[index] + direction * trims[index].y
		var count := ceili(length / 2400.0) if length > MODULES.POSITION_TOLERANCE else 0
		for part in count:
			var distance := length / float(count)
			poses.append({"position": start + direction * distance * float(part), "heading": direction.angle()})
			slots.append(_slot(&"straight_setup" if distance >= 520.0 else &"straight_link", {"length": distance}, &"speed" if distance >= 520.0 else &"connection"))
		poses.append({"position": ring[next] - direction * trims[next].x, "heading": direction.angle()})
		var hand := signf(direction.cross(outgoing))
		mixed = mixed or hand < 0.0
		slots.append(corners[next])
	if not slots.any(func(slot: Dictionary) -> bool: return slot["module_id"] in [&"straight_link", &"straight_setup"]):
		return _failure(&"finish_budget", "Region cycle has no straight interval for the finish.")
	while slots[0]["module_id"] not in [&"straight_link", &"straight_setup"]:
		slots.append(slots.pop_front())
		poses.append(poses.pop_front())
	_compact_returns(slots, poses)
	var finish := -1
	for index in slots.size():
		if slots[index]["module_id"] == &"straight_setup" and float(slots[index]["parameters"]["length"]) >= 1000.0:
			finish = index
			break
	if finish < 0:
		return _failure(&"finish_budget", "Region cycle has no length-1000 finish interval.")
	slots[finish]["parameters"]["finish"] = true
	slots[finish]["moment"] = &"finish"
	# Reserve a three-module analytic return before adding ordinary sections.
	var seam := -1
	for index in slots.size():
		var middle := (index + 1) % slots.size()
		var last := (index + 2) % slots.size()
		if _is_turn_slot(slots[index]) and slots[middle]["module_id"] in [&"straight_link", &"straight_setup"] and middle != finish and _is_turn_slot(slots[last]):
			seam = (last + 1) % slots.size()
			break
	if seam < 0:
		return _failure(&"closure_reservation", "No two bends and in-domain link can reserve the closure lane.")
	var ordinary: Array[Dictionary] = []
	for offset in range(slots.size() - 3):
		ordinary.append(slots[(seam + offset) % slots.size()])
	# Always attempt the authored technical section. Skipping it on mixed rings
	# left too many bare perimeter loops that normalized to the same structural
	# word; a straight that cannot host one still declines below.
	var insertions := {}
	var desired_insertions := 1 if candidate % COMPOSITION_COUNT == 4 else 1 + int(_unit(identity, candidate + 877) >= 0.5)
	var first_slot := int(_unit(identity, candidate + 503) * ordinary.size()) % ordinary.size()
	var proposals: Array[Dictionary] = []
	for step in ordinary.size():
		var index := (first_slot + step) % ordinary.size()
		var slot: Dictionary = ordinary[index]
		if slot["module_id"] not in [&"straight_link", &"straight_setup"]:
			continue
		var minimum_remaining := 1000.0 if bool(slot["parameters"].get("finish", false)) else (520.0 if slot["module_id"] == &"straight_setup" else LINK_MIN)
		var technical := _technical_slots(identity, candidate, index, float(slot["parameters"]["length"]) - minimum_remaining)
		if technical.is_empty():
			continue
		var modules: Array[Dictionary] = []
		for section: Dictionary in technical:
			modules.append(MODULES.instantiate(section["module_id"], section["parameters"]))
		var advance := float((MODULES.compose(modules)["exit_port"]["position"] as Vector2).x)
		var remaining := float(slot["parameters"]["length"]) - advance
		if remaining < minimum_remaining:
			continue
		var maximum_radius := RADIUS
		for section: Dictionary in technical:
			maximum_radius = maxf(maximum_radius, float(section["parameters"].get("radius", RADIUS)))
		var trailing := 0.0
		if remaining - minimum_remaining >= LINK_MIN:
			trailing = lerpf(LINK_MIN, remaining - minimum_remaining, _unit(identity, candidate * 97 + index + 1459))
		proposals.append({"index": index, "technical": technical, "remaining": remaining - trailing, "trailing": trailing, "maximum_radius": maximum_radius})
	var target_radius := _technical_radius(identity, candidate)
	proposals.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_distance := absf(float(a["maximum_radius"]) - target_radius)
		var b_distance := absf(float(b["maximum_radius"]) - target_radius)
		if not is_equal_approx(a_distance, b_distance):
			return a_distance < b_distance
		return _unit(identity, candidate * 97 + int(a["index"]) + 1201) < _unit(identity, candidate * 97 + int(b["index"]) + 1201)
	)
	var remaining_slots := slot_limit - ordinary.size() - 3
	for proposal: Dictionary in proposals:
		if insertions.size() >= desired_insertions:
			break
		var added_slots := (proposal["technical"] as Array).size() + int(float(proposal["trailing"]) > 0.0)
		if added_slots > remaining_slots:
			continue
		remaining_slots -= added_slots
		var slot_index := int(proposal["index"])
		ordinary[slot_index]["parameters"]["length"] = float(proposal["remaining"])
		var sections: Array[Dictionary] = (proposal["technical"] as Array[Dictionary]).duplicate(true)
		if float(proposal["trailing"]) > 0.0:
			sections.append(_slot(&"straight_link", {"length": float(proposal["trailing"])}, &"connection"))
		insertions[slot_index] = sections
	if insertions.is_empty() and not mixed:
		return _failure(&"technical_budget", "No unprotected link fits a mixed-handed module and a second setup interval.")
	if not insertions.is_empty():
		var expanded: Array[Dictionary] = []
		for index in ordinary.size():
			expanded.append(ordinary[index])
			for section: Dictionary in insertions.get(index, []):
				expanded.append(section)
		ordinary = expanded
	var closure_targets: Array[Dictionary] = []
	for offset in range(slots.size() - 3, slots.size()):
		closure_targets.append(slots[(seam + offset) % slots.size()])
	return {"ok": true, "ordinary_slots": ordinary, "closure_targets": closure_targets, "start_position": poses[seam]["position"], "start_heading": poses[seam]["heading"], "closure_radius": RADIUS, "id": &"region_cycle"}


static func _ring_slot_count(ring: PackedVector2Array, trims: Array[Vector2]) -> int:
	var count := ring.size()
	for index in ring.size():
		var next := (index + 1) % ring.size()
		var length := ring[index].distance_to(ring[next]) - trims[index].y - trims[next].x
		if length > MODULES.POSITION_TOLERANCE:
			count += ceili(length / 2400.0)
	return count


static func _corner_slot(hand: float, angle_deg: float, available: Vector2, candidate: int, index: int, maximum_loss: float = INF, parameter_unit: float = 0.0) -> Dictionary:
	var choices: Array[Dictionary] = []
	for definition: Dictionary in MODULES.definitions():
		if definition["family"] not in [&"corner", &"profile"]:
			continue
		var selected := {}
		var selected_distance := INF
		for unit: float in [0.0, 0.5, 1.0]:
			var parameters := MODULES.proposal_parameters(definition["id"], {"hand": hand}, {"radius": unit, "inner_radius": unit, "outer_radius": unit, "split": unit})
			parameters["angle_deg"] = angle_deg
			var module := MODULES.instantiate(definition["id"], parameters)
			var trims := _corner_trims(module)
			if trims.x <= available.x and trims.y <= available.y and trims.x + trims.y - float(module["length"]) <= maximum_loss and absf(unit - parameter_unit) < selected_distance:
				selected = _slot(definition["id"], parameters, &"technical" if hand < 0.0 else &"conflict")
				selected_distance = absf(unit - parameter_unit)
		if not selected.is_empty():
			choices.append(selected)
	if choices.is_empty() or candidate < 4:
		return _slot(&"corner_tight", {"radius": RADIUS, "angle_deg": angle_deg, "hand": hand}, &"technical" if hand < 0.0 else &"conflict")
	return choices[(candidate + index) % choices.size()]


static func _corner_trims(module: Dictionary) -> Vector2:
	var exit: Vector2 = module["exit_port"]["position"]
	var angle := absf(float(module["signed_turn"]))
	var outgoing := absf(exit.y) / sin(angle)
	return Vector2(exit.x - outgoing * cos(angle), outgoing)


static func _longest_edge_length(ring: PackedVector2Array) -> float:
	var longest := 0.0
	for index in ring.size():
		longest = maxf(longest, ring[index].distance_to(ring[(index + 1) % ring.size()]))
	return longest


static func _ring_length(ring: PackedVector2Array) -> float:
	var length := 0.0
	for index in ring.size():
		var previous := ring[posmod(index - 1, ring.size())]
		var next := ring[(index + 1) % ring.size()]
		var incoming := (ring[index] - previous).normalized()
		var outgoing := (next - ring[index]).normalized()
		var angle := absf(atan2(incoming.cross(outgoing), incoming.dot(outgoing)))
		length += ring[index].distance_to(next) + RADIUS * (angle - 2.0 * tan(angle * 0.5))
	return length


static func _excursion_capacity(excursions: Array[Dictionary], start: int, half_height: float) -> float:
	var capacity := 0.0
	for index in range(start, excursions.size()):
		capacity += 2.0 * (float(excursions[index]["extent"]) - half_height) - (4.0 - PI) * RADIUS
	return capacity


static func _technical_slots(identity: Dictionary, candidate: int, index: int, span: float) -> Array[Dictionary]:
	var hand := -1.0 if _unit(identity, candidate * 31 + index + 601) < 0.5 else 1.0
	var choices: Array[Dictionary] = []
	for pattern_offset in 3:
		var pattern := (candidate + pattern_offset) % 3
		var radii: Array[float] = [RADIUS, 260.0, 360.0]
		if pattern != 2:
			radii.append(520.0)
		for radius: float in radii:
			if pattern == 2:
				var switchback: Array[Dictionary] = [_slot(&"switchback", {"radius": radius, "depth_1": 450.0, "depth_2": 450.0, "width": 400.0, "hand": hand}, &"technical")]
				var switchback_modules: Array[Dictionary] = [MODULES.instantiate(switchback[0]["module_id"], switchback[0]["parameters"])]
				var switchback_route := MODULES.compose(switchback_modules)
				if bool(switchback_route.get("ok", false)) and float((switchback_route["exit_port"]["position"] as Vector2).x) <= span:
					choices.append({"sections": switchback, "radius": radius, "pattern": pattern})
				continue
			var angles: Array[float] = []
			for angle: float in [30.0, 45.0, 60.0]:
				var distance_factor := 2.0 * cos(deg_to_rad(angle)) if pattern == 1 else 1.0
				if 4.0 * radius * sin(deg_to_rad(angle)) + 180.0 * distance_factor <= span:
					angles.append(angle)
			if angles.is_empty():
				continue
			var angle_index := mini(angles.size() - 1, int(_unit(identity, candidate * 31 + index + 211) * angles.size()))
			if _unit(identity, candidate * 31 + index + 997) < 0.5:
				angle_index = angles.size() - 1
			var angle := angles[angle_index]
			var distance_factor := 2.0 * cos(deg_to_rad(angle)) if pattern == 1 else 1.0
			var distance_ceiling := 900.0
			var maximum_distance := minf(distance_ceiling, (span - 4.0 * radius * sin(deg_to_rad(angle))) / distance_factor)
			var parameters := {"radius": radius, "angle_deg": angle, "distance": lerpf(180.0, maximum_distance, _unit(identity, candidate * 31 + index + 307)), "hand": hand}
			if pattern == 1:
				var returning := parameters.duplicate(true)
				returning["hand"] = -hand
				var offsets: Array[Dictionary] = [_slot(&"s_offset", parameters, &"opening"), _slot(&"s_offset", returning, &"technical")]
				choices.append({"sections": offsets, "radius": radius, "pattern": pattern})
			else:
				var chicane: Array[Dictionary] = [_slot(&"chicane_return", parameters, &"technical")]
				choices.append({"sections": chicane, "radius": radius, "pattern": pattern})
	if choices.is_empty():
		return []
	var target_radius := _technical_radius(identity, candidate)
	choices.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_distance := absf(float(a["radius"]) - target_radius)
		var b_distance := absf(float(b["radius"]) - target_radius)
		if not is_equal_approx(a_distance, b_distance):
			return a_distance < b_distance
		return posmod(int(a["pattern"]) - candidate, 3) < posmod(int(b["pattern"]) - candidate, 3)
	)
	return choices[0]["sections"]


static func _technical_radius(identity: Dictionary, candidate: int) -> float:
	return TECHNICAL_RADII[mini(TECHNICAL_RADII.size() - 1, int(_unit(identity, candidate + 1709) * TECHNICAL_RADII.size()))]


static func _compact_returns(slots: Array[Dictionary], poses: Array[Dictionary]) -> void:
	var index := 0
	while index + 1 < slots.size():
		var first: Dictionary = slots[index]
		var last: Dictionary = slots[index + 1]
		if StringName(MODULES.definition(first["module_id"])["family"]) != &"corner" or first["module_id"] != last["module_id"] or first["parameters"] != last["parameters"] or not is_equal_approx(float(first["parameters"].get("angle_deg", 0.0)), 90.0):
			index += 1
			continue
		var radius := float(first["parameters"]["radius"])
		var parameters := {"radius": radius, "hand": first["parameters"]["hand"]}
		if not bool(MODULES.instantiate(&"u_return", parameters).get("ok", false)):
			index += 1
			continue
		slots[index] = _slot(&"u_return", parameters, &"technical")
		slots.remove_at(index + 1)
		poses.remove_at(index + 1)
		index += 1


static func portal_crossings(route: Dictionary, portal: Dictionary) -> Dictionary:
	var portal_line := {"kind": &"line", "start": portal["segment_from"], "end": portal["segment_to"]}
	var records: Array[Dictionary] = []
	var segment: Vector2 = portal["segment_to"] - portal["segment_from"]
	for primitive: Dictionary in route["primitives"]:
		for point: Vector2 in VALIDATION._primitive_intersections(primitive, portal_line):
			var fraction := (point - (portal["segment_from"] as Vector2)).dot(segment) / segment.length_squared()
			records.append({"point": point, "fraction": fraction, "module_index": int(primitive["module_index"])})
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["fraction"]) < float(b["fraction"]))
	var points := PackedVector2Array()
	var slots := PackedInt32Array()
	for record: Dictionary in records:
		if not points.is_empty() and points[points.size() - 1].distance_to(record["point"]) <= MODULES.POSITION_TOLERANCE:
			continue
		points.append(record["point"])
		slots.append(int(record["module_index"]))
	return {"points": points, "slot_indices": slots}


static func _slot(id: StringName, parameters: Dictionary, moment: StringName) -> Dictionary:
	var tags: Array = MODULES.definition(id)["allowed_moment_tags"]
	if not tags.has(moment):
		moment = tags[0]
	return {"module_id": id, "parameters": parameters, "moment": moment, "closure": false}


static func _is_turn_slot(slot: Dictionary) -> bool:
	return StringName(MODULES.definition(slot["module_id"])["family"]) in [&"corner", &"profile", &"return"]


static func _bounds(polygon: PackedVector2Array) -> Rect2:
	var result := Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		result = result.expand(point)
	return result


static func _inscribed_bounds(polygon: PackedVector2Array) -> Rect2:
	var bounds := _bounds(polygon)
	if Geometry2D.clip_polygons(_rectangle(bounds), polygon).is_empty():
		return bounds
	var result := Rect2()
	for mask in range(1, 16):
		var sides := Vector4(float(mask & 1 != 0), float(mask & 2 != 0), float(mask & 4 != 0), float(mask & 8 != 0))
		var horizontal := sides.x + sides.z
		var vertical := sides.y + sides.w
		var lower := 0.0
		var upper := minf(bounds.size.x / horizontal if horizontal > 0.0 else INF, bounds.size.y / vertical if vertical > 0.0 else INF)
		for iteration in 16:
			var inset := (lower + upper) * 0.5
			var offset := Vector2(sides.x, sides.y) * inset
			var rectangle := Rect2(bounds.position + offset, bounds.size - Vector2(horizontal, vertical) * inset)
			if Geometry2D.clip_polygons(_rectangle(rectangle), polygon).is_empty():
				if rectangle.get_area() > result.get_area():
					result = rectangle
				upper = inset
			else:
				lower = inset
	return result


static func _rectangle(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


static func _simplify_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var simplified := PackedVector2Array()
	for point: Vector2 in polygon:
		if simplified.is_empty() or simplified[simplified.size() - 1].distance_to(point) > MODULES.POSITION_TOLERANCE:
			simplified.append(point)
	if simplified.size() > 1 and simplified[0].distance_to(simplified[simplified.size() - 1]) <= MODULES.POSITION_TOLERANCE:
		simplified.remove_at(simplified.size() - 1)
	var changed := true
	while changed and simplified.size() > 3:
		changed = false
		for index in simplified.size():
			var incoming := simplified[index] - simplified[posmod(index - 1, simplified.size())]
			var outgoing := simplified[(index + 1) % simplified.size()] - simplified[index]
			var aligned := incoming.length_squared() > 0.0 and outgoing.length_squared() > 0.0 and absf(incoming.normalized().cross(outgoing.normalized())) <= MODULES.HEADING_TOLERANCE and incoming.dot(outgoing) >= 0.0
			if aligned:
				simplified.remove_at(index)
				changed = true
				break
	return simplified


static func _excursion_range(bounds: Rect2, left: float, right: float) -> Vector2:
	var x0 := maxf(left, bounds.position.x)
	var x1 := minf(right, bounds.end.x)
	# Keep both portal lanes free; each excursion remains on one region side.
	if bounds.get_center().x < 0.0:
		var junction_half := minf(CELL_MIN * 0.5, maxf(RADIUS + 10.0, -x0 - CELL_MIN - 1.0))
		x1 = minf(x1, -junction_half)
	else:
		var junction_half := minf(CELL_MIN * 0.5, maxf(RADIUS + 10.0, x1 - CELL_MIN - 1.0))
		x0 = maxf(x0, junction_half)
	return Vector2(x0, x1)


static func _excursion_bevel(identity: Dictionary, candidate: int, index: int, width: float, depth: float) -> float:
	var minimum := CHAMFER_MIN
	var maximum := minf(width - CELL_MIN, depth - CELL_MIN)
	if maximum < minimum or _unit(identity, candidate * 43 + index + 2017) < 0.5:
		return 0.0
	return lerpf(minimum, maximum, _unit(identity, candidate * 43 + index + 2069))


static func _excursion_cut(from_x: float, width: float, half_height: float, depth: float, side: float, anchored_left: bool, bevel: float) -> PackedVector2Array:
	var corner := Vector2(from_x + width if anchored_left else from_x, side * (half_height + depth))
	return PackedVector2Array([corner, corner + Vector2(-bevel if anchored_left else bevel, 0.0), corner - Vector2(0.0, side * bevel)])


## Chamfers a hash-seeded subset of the ring's own 90-degree convex corners.
## Each accepted chamfer replaces one class-2 corner with a 45-degree link and a
## 45-degree corner pair, so the structural word gains angle classes instead of
## only varying its run count. Corners bordering the two longest edges are kept
## so the finish and second setup intervals survive, adjacent corners are never
## both cut, and every cut still passes the shared length/slot guard.
static func _ring_chamfer_cuts(ring: PackedVector2Array, identity: Dictionary, candidate: int) -> Array[PackedVector2Array]:
	var cuts: Array[PackedVector2Array] = []
	if ring.size() < 4:
		return cuts
	var winding := signf(_signed_area(ring))
	var floors := _edge_length_floors(ring)
	var previous_chamfered := false
	for index in ring.size():
		if previous_chamfered:
			previous_chamfered = false
			continue
		var previous := ring[posmod(index - 1, ring.size())]
		var vertex := ring[index]
		var next := ring[(index + 1) % ring.size()]
		var incoming_edge := posmod(index - 1, ring.size())
		if previous.distance_to(vertex) - CHAMFER_MIN < floors[incoming_edge] or vertex.distance_to(next) - CHAMFER_MIN < floors[index]:
			continue
		var incoming := (vertex - previous).normalized()
		var outgoing := (next - vertex).normalized()
		var cross := incoming.cross(outgoing)
		if signf(cross) != winding:
			continue
		if absf(absf(atan2(cross, incoming.dot(outgoing))) - PI * 0.5) > deg_to_rad(1.0):
			continue
		if _unit(identity, candidate * 71 + index + 2617) >= 0.5:
			continue
		var first := vertex - incoming * CHAMFER_MIN
		var second := vertex + outgoing * CHAMFER_MIN
		if not Geometry2D.is_point_in_polygon((first + second + vertex) / 3.0, ring):
			continue
		cuts.append(PackedVector2Array([first, second, vertex]))
		previous_chamfered = true
	return cuts


## Minimum length each ring edge must retain after chamfering so the edge that
## carries the finish (longest) or the second protected setup (next longest)
## still satisfies its reservation plus the two corner trims it will hold.
static func _edge_length_floors(ring: PackedVector2Array) -> Array[float]:
	var lengths: Array[Dictionary] = []
	for index in ring.size():
		lengths.append({"index": index, "length": ring[index].distance_to(ring[(index + 1) % ring.size()])})
	lengths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["length"]) > float(b["length"]))
	var floors: Array[float] = []
	floors.resize(ring.size())
	floors.fill(LINK_MIN + 2.0 * RADIUS)
	for rank in mini(2, lengths.size()):
		floors[int(lengths[rank]["index"])] = (FINISH_EDGE_MIN if rank == 0 else SETUP_EDGE_MIN) + 2.0 * RADIUS
	return floors


static func _signed_area(ring: PackedVector2Array) -> float:
	var area := 0.0
	for index in ring.size():
		area += ring[index].cross(ring[(index + 1) % ring.size()])
	return area * 0.5


static func _excursion_polygon(from_x: float, width: float, half_height: float, depth: float, side: float, composition: int, anchored_left: bool) -> PackedVector2Array:
	var to_x := from_x + width
	var base_y := side * half_height
	var outer_y := side * (half_height + depth)
	if composition < 2:
		return PackedVector2Array([Vector2(from_x, 0.0), Vector2(to_x, 0.0), Vector2(to_x, outer_y), Vector2(from_x, outer_y)])
	if composition == 3:
		if anchored_left:
			return PackedVector2Array([Vector2(from_x, 0.0), Vector2(to_x, 0.0), Vector2(to_x, base_y), Vector2(to_x - depth, outer_y), Vector2(from_x, outer_y)])
		return PackedVector2Array([Vector2(from_x, 0.0), Vector2(to_x, 0.0), Vector2(to_x, outer_y), Vector2(from_x + depth, outer_y), Vector2(from_x, base_y)])
	if anchored_left:
		return PackedVector2Array([Vector2(from_x, 0.0), Vector2(to_x, 0.0), Vector2(to_x, base_y), Vector2(from_x, outer_y)])
	return PackedVector2Array([Vector2(from_x, 0.0), Vector2(to_x, 0.0), Vector2(to_x, outer_y), Vector2(from_x, base_y)])


static func _unit(identity: Dictionary, index: int) -> float:
	var digest := ("v8-region|%s|%s|%s|%d" % [identity.get("room_shape", ""), identity.get("length_tier", ""), identity.get("seed", 0), index]).sha256_buffer()
	return float((int(digest[0]) << 8) | int(digest[1])) / 65535.0


static func _failure(kind: StringName, reason: String) -> Dictionary:
	return {"ok": false, "kind": kind, "reason": reason}
