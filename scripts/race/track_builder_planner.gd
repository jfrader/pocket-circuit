class_name TrackBuilderPlanner
## Deterministic obstacle plans. Does not build nodes.

const GENERATED_RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const GEOM := preload("res://scripts/race/track_builder_geometry.gd")
const HALF_WIDTH := 125.0
const VEHICLE_WIDTH := 44.0
const MIN_VIABLE_CORRIDOR_WIDTH := VEHICLE_WIDTH * 1.6
const OBSTACLE_ROUTE_CLEARANCE := VEHICLE_WIDTH * 0.5 + 8.0
const OBSTACLE_EDGE_INSET := 8.0


static func plan_obstacles(
		theme: StringName,
		spec: Dictionary,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		moments: Dictionary,
		roster: Array,
		standard_route: PackedVector2Array,
		shortcut_route: PackedVector2Array
) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	if not bool(spec.get("obstacles_enabled", true)) or roster.is_empty():
		return plan
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("obstacle_seed", 0))
	var act := clampi(int(spec.get("act", GENERATED_RULES.default_act_for_theme(theme))), 1, 3)
	var target_count := GENERATED_RULES.roll_obstacle_count(act, rng)
	var protected_indices := PackedInt32Array([
		0,
		int(moments.get("shortcut", 0)),
		int(moments.get("technical", 0)),
	])
	var occupied: Array[Dictionary] = []
	# Obstacles stay out of corners and out of the braking zone before any corner
	# in either race direction.
	var corner_clearance: PackedFloat32Array = moments.get("corner_clearance", PackedFloat32Array())
	if corner_clearance.size() != centerline.size():
		corner_clearance = TrackCornerMap.clearances(centerline)
	var half_widths: PackedFloat32Array = spec.get("half_widths", PackedFloat32Array())
	for slot in target_count:
		var definition: Dictionary = (roster[posmod(rng.randi(), roster.size())] as Dictionary).duplicate(true)
		var footprint_size := TrackBuilderCore.PROP_SCALE.size_for(String(definition["asset"]), Vector2(40.0, 40.0))
		var shape_kind := &"rect"
		definition["footprint_size"] = footprint_size
		definition["visual_size"] = footprint_size
		definition["footprint_kind"] = shape_kind
		var preferred_index := rng.randi_range(0, centerline.size() - 1)
		var preferred_side := -1.0 if rng.randi() % 2 == 0 else 1.0
		var placed := false
		for attempt in centerline.size():
			var index := posmod(preferred_index + attempt * 37, centerline.size())
			if GEOM.turn_strength(centerline, index, 10) > 0.10 or not TrackCornerMap.is_calm(corner_clearance, index, 0):
				continue
			var protected := false
			for protected_index: int in protected_indices:
				if protected_index >= 0 and GEOM.cyclic_index_distance(index, protected_index, centerline.size()) < 22:
					protected = true
					break
			if protected:
				continue
			var tangent := GEOM.sample_tangent(centerline, index)
			var normal := tangent.rotated(PI * 0.5)
			var rotation := tangent.angle() if footprint_size.x >= footprint_size.y else tangent.angle() - PI * 0.5
			var lateral_extent := GEOM.footprint_projected_extent(footprint_size, shape_kind, rotation, normal)
			var route_offset := (standard_route[index] - centerline[index]).dot(normal)
			var side := -signf(route_offset) if not is_zero_approx(route_offset) else preferred_side
			var local_half := half_widths[index] if half_widths.size() == centerline.size() else HALF_WIDTH
			var lateral_offset := local_half - OBSTACLE_EDGE_INSET - lateral_extent
			var candidate := centerline[index] + normal * side * lateral_offset
			var viable_width := local_half + absf(lateral_offset) - lateral_extent
			if viable_width + 0.001 < MIN_VIABLE_CORRIDOR_WIDTH:
				continue
			if not GEOM.clear_of_points(candidate, gate_samples, maxf(90.0, footprint_size.length())):
				continue
			if not GEOM.clear_of_occupied(candidate, footprint_size.length() * 0.5, occupied):
				continue
			var route_clearance := float(definition.get("clearance", OBSTACLE_ROUTE_CLEARANCE))
			if not GEOM.line_sweep_clears_footprint(standard_route, candidate, footprint_size, shape_kind, rotation, route_clearance):
				continue
			if not GEOM.line_sweep_clears_footprint(shortcut_route, candidate, footprint_size, shape_kind, rotation, route_clearance):
				continue
			definition["instance_id"] = "%s_%02d" % [String(definition["id"]), slot]
			definition["position"] = candidate
			definition["rotation"] = rotation
			definition["centerline_index"] = index
			definition["side"] = side
			definition["visual_bounds"] = Rect2(-(definition["visual_size"] as Vector2) * 0.5, definition["visual_size"])
			definition["lateral_footprint_extent"] = lateral_extent
			definition["lateral_center_offset"] = absf((candidate - centerline[index]).dot(normal))
			definition["viable_corridor_width"] = viable_width
			definition["validated_ai_routes"] = PackedStringArray(["RacingLine", "ShortcutRacingLine"])
			plan.append(definition)
			occupied.append({"position": candidate, "radius": footprint_size.length() * 0.5})
			placed = true
			break
		if not placed:
			push_warning("TrackBuilderPlanner: skipped an obstacle that had no AI-safe placement")
	return plan
