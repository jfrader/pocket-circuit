class_name TrackLayoutGraph
extends RefCounted

const MODULES := preload("res://scripts/race/track_module_catalog.gd")
const ROOMS := preload("res://scripts/race/track_room_model.gd")
const RADIUS := MODULES.MIN_CONSTRUCTION_RADIUS
const LINK_MIN := 180.0
const CELL_MIN := 2.0 * RADIUS + LINK_MIN


static func build(room: Dictionary, band: Dictionary, identity: Dictionary, candidate: int) -> Dictionary:
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
	var portal: Dictionary = portals[candidate % portals.size()]
	var origin: Vector2 = (portal["segment_from"] + portal["segment_to"]) * 0.5
	var across: Vector2 = (portal["segment_to"] - portal["segment_from"]).normalized()
	var forward := Vector2(across.y, -across.x)
	var cells: Array[Dictionary] = []
	for region: Dictionary in required:
		var polygon := PackedVector2Array()
		for point: Vector2 in region["polygon"]:
			var delta := point - origin
			polygon.append(Vector2(delta.dot(forward), delta.dot(across)))
		cells.append({"id": region["id"], "polygon": polygon, "bounds": _bounds(polygon).grow(-ROOMS.CONSTRUCTION_MARGIN - 2.0)})
	var unit := _unit(identity, candidate)
	var target := lerpf(float(band["min_length"]), float(band["max_length"]), 0.12 + unit * 0.30)
	var half_height := minf(300.0, (portal["segment_to"] as Vector2).distance_to(portal["segment_from"]) * 0.5 - 10.0)
	var left := 0.0
	var right := 0.0
	for cell: Dictionary in cells:
		var bounds: Rect2 = cell["bounds"]
		left = minf(left, bounds.position.x)
		right = maxf(right, bounds.end.x)
	# Region masks may overlap at a junction. Budget real occupation beyond
	# that overlap, rather than crediting both visits to the same trunk.
	var required_depth := 0.0
	for cell: Dictionary in cells:
		var bounds: Rect2 = cell["bounds"]
		for other: Dictionary in cells:
			if other["id"] == cell["id"]:
				continue
			var overlap := bounds.intersection(other["bounds"])
			if overlap.has_area() and bounds.position.y < overlap.position.y - 450.0:
				required_depth = maxf(required_depth, maxf(CELL_MIN, -half_height - overlap.position.y + 450.0))
	var width := clampf((target - 4.0 * half_height + (8.0 - TAU) * RADIUS - 2.0 * required_depth) * 0.5, 1700.0, right - left)
	var left_share := clampf(-left / maxf(right - left, 1.0), 0.38, 0.62)
	left = maxf(left, -width * left_share)
	right = minf(right, width * (1.0 - left_share))
	var ring := _rectangle(Rect2(Vector2(left, -half_height), Vector2(right - left, 2.0 * half_height)))
	var estimate := 2.0 * (right - left + 2.0 * half_height) - (8.0 - TAU) * RADIUS
	var region_budgets: Array[Dictionary] = []
	for cell_index in cells.size():
		var cell: Dictionary = cells[cell_index]
		var bounds: Rect2 = cell["bounds"]
		var x0 := maxf(left, bounds.position.x)
		var x1 := minf(right, bounds.end.x)
		# Keep the two portal lanes free; excursions belong to one region side.
		if bounds.get_center().x < 0.0:
			x1 = minf(x1, -RADIUS - 10.0)
		else:
			x0 = maxf(x0, RADIUS + 10.0)
		var count := maxi(1, floori((x1 - x0 + CELL_MIN) / (2.0 * CELL_MIN)))
		var allocated := 0
		for index in count:
			var cell_width := (x1 - x0 - float(count - 1) * CELL_MIN) / float(count)
			if cell_width < CELL_MIN:
				continue
			var from_x := x0 + float(index) * (cell_width + CELL_MIN)
			var side := -1.0 if (candidate + cell_index + index) % 2 == 0 else 1.0
			var mandatory := 0.0
			for other: Dictionary in cells:
				if other["id"] == cell["id"]:
					continue
				var overlap := bounds.intersection(other["bounds"])
				if overlap.has_area() and bounds.position.y < overlap.position.y - 450.0:
					side = -1.0
					mandatory = maxf(CELL_MIN, -half_height - overlap.position.y + 450.0)
			var available := -half_height - bounds.position.y if side < 0.0 else bounds.end.y - half_height
			var depth := minf(available, maxf(mandatory, (target - estimate) * 0.5))
			if depth < CELL_MIN:
				continue
			var extension := Rect2(Vector2(from_x, -half_height - depth if side < 0.0 else 0.0), Vector2(cell_width, half_height + depth))
			var merged := Geometry2D.merge_polygons(ring, _rectangle(extension))
			if merged.size() != 1:
				continue
			ring = merged[0]
			estimate += 2.0 * depth - (8.0 - TAU) * RADIUS
			allocated += 1
		region_budgets.append({"region_id": cell["id"], "excursion_count": allocated, "available_area": bounds.get_area()})
	if Geometry2D.is_polygon_clockwise(ring):
		ring.reverse()
	var graph := _embed_ring(ring, identity, candidate)
	if not bool(graph.get("ok", false)):
		return graph
	graph["start_position"] = origin + forward * (graph["start_position"] as Vector2).x + across * (graph["start_position"] as Vector2).y
	graph["start_heading"] = float(graph["start_heading"]) + forward.angle()
	graph["region_budgets"] = region_budgets
	graph["portal_counts"] = {}
	for connection: Dictionary in portals:
		graph["portal_counts"][connection["id"]] = 2
	graph["slot_budget"] = Vector2i(maxi(6, ceili(float(band["min_length"]) / 1500.0)), maxi(12, ceili(float(band["max_length"]) / 750.0)))
	if (graph["ordinary_slots"] as Array).size() + 3 > (graph["slot_budget"] as Vector2i).y:
		return _failure(&"slot_budget", "Region traversal needs %d slots; length-band budget allows %d." % [(graph["ordinary_slots"] as Array).size() + 3, (graph["slot_budget"] as Vector2i).y])
	return graph


static func _embed_ring(ring: PackedVector2Array, identity: Dictionary, candidate: int) -> Dictionary:
	var slots: Array[Dictionary] = []
	var poses: Array[Dictionary] = []
	var mixed := false
	for index in ring.size():
		var next := (index + 1) % ring.size()
		var direction := (ring[next] - ring[index]).normalized()
		var outgoing := (ring[(index + 2) % ring.size()] - ring[next]).normalized()
		var length := ring[index].distance_to(ring[next]) - 2.0 * RADIUS
		if length < LINK_MIN - 0.01:
			return _failure(&"cell_turn_envelope", "Region edge %.2f cannot fit two radius-180 bends and a length-180 link." % ring[index].distance_to(ring[next]))
		var start := ring[index] + direction * RADIUS
		var count := ceili(length / 2400.0)
		for part in count:
			var distance := length / float(count)
			poses.append({"position": start + direction * distance * float(part), "heading": direction.angle()})
			slots.append(_slot(&"straight_setup" if distance >= 520.0 else &"straight_link", {"length": distance}, &"speed" if distance >= 520.0 else &"connection"))
		poses.append({"position": ring[next] - direction * RADIUS, "heading": direction.angle()})
		var hand := signf(direction.cross(outgoing))
		mixed = mixed or hand < 0.0
		slots.append(_slot(&"corner_tight", {"radius": RADIUS, "angle_deg": 90.0, "hand": hand}, &"technical" if hand < 0.0 else &"conflict"))
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
		if slots[index]["module_id"] == &"corner_tight" and slots[middle]["module_id"] == &"straight_link" and slots[last]["module_id"] == &"corner_tight":
			seam = (last + 1) % slots.size()
			break
	if seam < 0:
		return _failure(&"closure_reservation", "No two bends and in-domain link can reserve the closure lane.")
	var ordinary: Array[Dictionary] = []
	for offset in range(slots.size() - 3):
		ordinary.append(slots[(seam + offset) % slots.size()])
	if not mixed:
		var inserted := false
		for index in ordinary.size():
			var slot: Dictionary = ordinary[index]
			if slot["module_id"] != &"straight_setup" or bool(slot["parameters"].get("finish", false)):
				continue
			var distance := 180.0 + 80.0 * _unit(identity, candidate + index)
			var advance := 2.0 * RADIUS + distance
			var remaining := float(slot["parameters"]["length"]) - advance
			if remaining < 520.0:
				continue
			slot["parameters"]["length"] = remaining
			ordinary.insert(index + 1, _slot(&"chicane_return", {"radius": RADIUS, "angle_deg": 30.0, "distance": distance, "hand": -1.0}, &"technical"))
			inserted = true
			break
		if not inserted:
			return _failure(&"technical_budget", "No unprotected link fits a mixed-handed module and a second setup interval.")
	return {"ok": true, "ordinary_slots": ordinary, "start_position": poses[seam]["position"], "start_heading": poses[seam]["heading"], "closure_radius": RADIUS, "id": &"region_cycle"}


static func _slot(id: StringName, parameters: Dictionary, moment: StringName) -> Dictionary:
	return {"module_id": id, "parameters": parameters, "moment": moment, "closure": false}


static func _bounds(polygon: PackedVector2Array) -> Rect2:
	var result := Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		result = result.expand(point)
	return result


static func _rectangle(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


static func _unit(identity: Dictionary, index: int) -> float:
	var digest := ("v8-region|%s|%s|%s|%d" % [identity.get("room_shape", ""), identity.get("length_tier", ""), identity.get("seed", 0), index]).sha256_buffer()
	return float((int(digest[0]) << 8) | int(digest[1])) / 65535.0


static func _failure(kind: StringName, reason: String) -> Dictionary:
	return {"ok": false, "kind": kind, "reason": reason}
