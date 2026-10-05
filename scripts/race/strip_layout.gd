extends RefCounted

const ROUTE := preload("res://scripts/race/strip_route.gd")
const VEHICLES := preload("res://data/championship/catalog.gd")
const DRESSING := preload("res://scripts/race/strip_dressing.gd")
const ROAD := preload("res://scripts/race/strip/strip_road_rules.gd")
const THEMES := preload("res://scripts/race/strip_themes.gd")
const GRID_ARC := 210.0
const CHASER_GAP := 120.0
const FINISH_INSET := 145.0
const GATE_SPACING := 1750.0
const MIN_GATE_COUNT := 4
const MAX_GATE_COUNT := 64
const TRAFFIC_MIN_ARC := 460.0
const TRAFFIC_FINISH_CLEARANCE := 340.0
const TRAFFIC_SPACING := 1450.0
const MAX_NORTHBOUND := 30
const MAX_ONCOMING := 12
const MAX_TRAFFIC := MAX_NORTHBOUND + MAX_ONCOMING
const ONCOMING_SPACING := 4400.0
const ONCOMING_START_CLEARANCE := 2600.0
const ONCOMING_SPEED := Vector2(115.0, 140.0)
const TRAFFIC_FIRST_PACK := 420.0
const TRAFFIC_PACK_SEPARATION := 170.0
const SPECIAL_PACK_INTERVAL := 4
const MIN_TIME_LIMIT := 75.0
const CLEAN_SPEED_ESTIMATE := 600.0
const TIME_LIMIT_FACTOR := 1.8
const MIN_RUNNER_WIDTH := 2600.0
const MAX_RUNNER_WIDTH := 3000.0
const CORNER_RADIUS := 170.0
const CORNER_STEPS := 5
const RUNNER_HEIGHT := {
	"compact": 41000.0,
	"standard": 49000.0,
	"long": 57000.0,
	"endurance": 69000.0,
	"marathon": 78000.0,
}


static func runner_room(base_room: PackedVector2Array, length_tier: String) -> PackedVector2Array:
	if base_room.size() < 3 or not RUNNER_HEIGHT.has(length_tier):
		return PackedVector2Array()
	var bounds := Rect2(base_room[0], Vector2.ZERO)
	for point: Vector2 in base_room:
		bounds = bounds.expand(point)
	var width := clampf(minf(bounds.size.x, bounds.size.y), MIN_RUNNER_WIDTH, MAX_RUNNER_WIDTH)
	var height := float(RUNNER_HEIGHT[length_tier])
	var half := Vector2(width, height) * 0.5
	var center := bounds.get_center()
	var corners := [
		Vector2(half.x - CORNER_RADIUS, -half.y + CORNER_RADIUS),
		Vector2(half.x - CORNER_RADIUS, half.y - CORNER_RADIUS),
		Vector2(-half.x + CORNER_RADIUS, half.y - CORNER_RADIUS),
		Vector2(-half.x + CORNER_RADIUS, -half.y + CORNER_RADIUS),
	]
	var room := PackedVector2Array()
	for corner_index in corners.size():
		for step in CORNER_STEPS + 1:
			var angle := -PI * 0.5 + corner_index * PI * 0.5 + step * PI * 0.5 / CORNER_STEPS
			room.append(center + corners[corner_index] + Vector2.RIGHT.rotated(angle) * CORNER_RADIUS)
	return room


static func prepare(theme: StringName, room_shape: StringName, seed: int, options: Dictionary, base_spec: Dictionary, room_polygon: PackedVector2Array, kits: Array) -> Dictionary:
	# Only civilian traffic may travel south. A reverse strip would invert the
	# fixed camera grammar and the meaning of every signed lane.
	if bool(options.get("reverse", false)):
		return {}
	var theme_b := THEMES.second_theme(theme, String(options.get("theme_b", "")))
	if theme_b == &"":
		return {}
	var route := ROUTE.generate(seed, room_polygon)
	if route.is_empty():
		return {}
	var centerline: PackedVector2Array = (route["centerline"] as PackedVector2Array).duplicate()
	var arcs := _arc_lengths(centerline)
	var total := arcs[-1]
	var spec := base_spec.duplicate(true)
	spec["route_shape"] = "strip"
	spec["requested_seed"] = seed
	spec["seed"] = seed
	spec["seed_obstacles"] = false
	spec["generation_fallback"] = route["fallback"]
	spec["generation_attempt"] = route["attempt"]
	spec["controls"] = route["controls"]
	spec["strip_sections"] = route["sections"]
	spec["length_tier"] = String(options.get("length_tier", "standard"))
	var sub_seeds: Dictionary = options.get("sub_seeds", {})
	spec["material_seed"] = int(sub_seeds.get("material", seed))
	spec["dressing_seed"] = int(sub_seeds.get("dressing", seed))
	spec["obstacle_seed"] = int(sub_seeds.get("obstacle", seed))
	spec["material_id"] = String(options.get("material_id", ""))
	spec["palette_id"] = String(options.get("palette_id", ""))
	spec["half_width"] = ROAD.HALF_WIDTH
	var specs := [THEMES.spec_for(theme, spec, base_spec, kits, true), THEMES.spec_for(theme_b, spec, TrackBuilderCore.LAYOUTS[theme_b], TrackBuilderCore.ROOM_COMPOSITIONS[theme_b], false)]
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for index in centerline.size():
		var tangent := _tangent(centerline, index)
		var normal := tangent.rotated(PI * 0.5) * ROUTE.HALF_WIDTH
		left.append(centerline[index] + normal)
		right.append(centerline[index] - normal)
	var gates: Array[Dictionary] = []
	var gate_count := clampi(ceili((total - FINISH_INSET) / GATE_SPACING) + 1, MIN_GATE_COUNT, MAX_GATE_COUNT)
	for index in gate_count:
		var distance := (total - FINISH_INSET) * float(index) / (gate_count - 1) if index > 0 else 35.0
		var transform := sample_at_arc(centerline, arcs, distance)
		gates.append({"index": index, "arc": distance, "position": transform.origin, "rotation": transform.get_rotation(), "is_finish_line": index == gate_count - 1})
	var grid := {"player": sample_at_arc(centerline, arcs, GRID_ARC), "chaser": sample_at_arc(centerline, arcs, GRID_ARC - CHASER_GAP)}
	for key in grid:
		var transform: Transform2D = grid[key]
		transform.origin += Vector2.RIGHT.rotated(transform.get_rotation()) * ROAD.LANE_WIDTH * 0.5
		grid[key] = transform
	var racing_line := PackedVector2Array()
	for index in centerline.size():
		racing_line.append(centerline[index] + _tangent(centerline, index).rotated(PI * 0.5) * ROAD.NORTH_RACING_OFFSET)
	var switch_arc := THEMES.switch_arc(route["sections"], total)
	var seam := sample_at_arc(centerline, arcs, switch_arc)
	var regions: Array[Dictionary] = []
	var placements: Array[Dictionary] = []
	var obstacles: Array[Dictionary] = []
	for index in 2:
		var from := 0.0 if index == 0 else switch_arc
		var to := switch_arc if index == 0 else total
		var region_line := _route_slice(centerline, arcs, from, to)
		var north := index == 1
		var region_room := THEMES.room_half(room_polygon, seam.origin.y, north)
		var region_theme: StringName = theme if index == 0 else theme_b
		var region_spec: Dictionary = specs[index]
		var environment := DRESSING.plan(region_spec, region_theme, region_line, region_room, gates)
		for entry: Dictionary in environment["placements"]:
			entry["theme"] = region_theme
		for obstacle: Dictionary in environment["obstacles"]:
			obstacle["instance_id"] = "region%d_%s" % [index, obstacle["instance_id"]]
			obstacle["theme"] = region_theme
		region_spec["environment_plan"] = {"placements": environment["placements"], "diagnostics": environment["diagnostics"]}
		region_spec["obstacle_plan"] = environment["obstacles"]
		placements.append_array(environment["placements"])
		obstacles.append_array(environment["obstacles"])
		regions.append({"theme": region_theme, "spec": region_spec, "centerline": region_line, "room_polygon": region_room, "strip_gates": gates, "strip_half_width": ROAD.HALF_WIDTH, "start_arc": from, "end_arc": to})
	spec = specs[0].duplicate(true)
	spec["environment_plan"] = {"placements": placements, "diagnostics": {"total_placed": placements.size()}}
	spec["obstacle_plan"] = obstacles
	return {"spec": spec, "centerline": centerline, "edges": {"left": left, "right": right}, "room_polygon": room_polygon, "theme": theme, "theme_b": theme_b, "strip_theme_switch": {"arc": switch_arc, "position": seam.origin, "rotation": seam.get_rotation()}, "strip_regions": regions, "room_shape": room_shape, "seed": seed, "route_shape": "strip", "strip_length": total, "strip_time_limit": maxf(MIN_TIME_LIMIT, ceilf(total / CLEAN_SPEED_ESTIMATE * TIME_LIMIT_FACTOR)), "strip_gates": gates, "strip_grid": grid, "strip_half_width": ROAD.HALF_WIDTH, "strip_caps": {"start": centerline[0], "finish": centerline[-1]}, "racing_line": racing_line, "traffic_plan": _traffic(seed, total)}


static func _route_slice(line: PackedVector2Array, arcs: PackedFloat32Array, from: float, to: float) -> PackedVector2Array:
	var result := PackedVector2Array([sample_at_arc(line, arcs, from).origin])
	for index in line.size():
		if arcs[index] > from and arcs[index] < to:
			result.append(line[index])
	result.append(sample_at_arc(line, arcs, to).origin)
	return result


static func _traffic(seed: int, total: float) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed ^ 0x524F4144) & 0x7FFFFFFF
	var result: Array[Dictionary] = []
	var vehicle_ids := VEHICLES.quick_race_vehicle_ids()
	var available := total - TRAFFIC_MIN_ARC - TRAFFIC_FINISH_CLEARANCE
	if available <= 0.0:
		return result
	var count := clampi(floori(available / TRAFFIC_SPACING), 2, MAX_NORTHBOUND)
	var pack_sizes: Array[int] = []
	var remaining := count
	while remaining > 0:
		var pack_size := 1 if pack_sizes.size() % SPECIAL_PACK_INTERVAL == SPECIAL_PACK_INTERVAL - 1 else mini(remaining, 2 + int(pack_sizes.size() % 3 == 2))
		pack_sizes.append(pack_size)
		remaining -= pack_size
	var special_behaviors := [&"cutter", &"swerve", &"truck"]
	var special_offset := rng.randi_range(0, special_behaviors.size() - 1)
	for pack_index in pack_sizes.size():
		var pack_arc := TRAFFIC_MIN_ARC + TRAFFIC_FIRST_PACK + (available - TRAFFIC_FIRST_PACK - TRAFFIC_FINISH_CLEARANCE) * float(pack_index) / pack_sizes.size()
		var lane: int = ROAD.NORTHBOUND[rng.randi_range(0, ROAD.NORTHBOUND.size() - 1)]
		for member in pack_sizes[pack_index]:
			result.append({"arc": pack_arc + member * TRAFFIC_PACK_SEPARATION, "lane": lane, "speed": rng.randf_range(210.0, 225.0), "behavior": special_behaviors[(pack_index / SPECIAL_PACK_INTERVAL + special_offset) % special_behaviors.size()] if pack_sizes[pack_index] == 1 else &"cruiser", "vehicle_id": vehicle_ids[rng.randi_range(0, vehicle_ids.size() - 1)]})
	var oncoming_count := mini(MAX_ONCOMING, floori(available / ONCOMING_SPACING))
	for index in oncoming_count:
		var arc := lerpf(ONCOMING_START_CLEARANCE, total - TRAFFIC_FINISH_CLEARANCE, float(index) / maxf(1.0, oncoming_count))
		result.append({"arc": arc, "lane": ROAD.SOUTHBOUND[rng.randi_range(0, ROAD.SOUTHBOUND.size() - 1)], "speed": rng.randf_range(ONCOMING_SPEED.x, ONCOMING_SPEED.y), "behavior": &"truck" if index % SPECIAL_PACK_INTERVAL == special_offset else &"cruiser", "vehicle_id": vehicle_ids[rng.randi_range(0, vehicle_ids.size() - 1)]})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["arc"]) < float(b["arc"]))
	return result


static func _arc_lengths(points: PackedVector2Array) -> PackedFloat32Array:
	var arcs := PackedFloat32Array([0.0])
	for index in range(1, points.size()):
		arcs.append(arcs[-1] + points[index - 1].distance_to(points[index]))
	return arcs


static func sample_at_arc(points: PackedVector2Array, arcs: PackedFloat32Array, distance: float) -> Transform2D:
	for index in range(1, arcs.size()):
		if distance <= arcs[index]:
			var tangent := (points[index] - points[index - 1]).normalized()
			return Transform2D(tangent.angle() + PI * 0.5, points[index - 1].lerp(points[index], (distance - arcs[index - 1]) / maxf(arcs[index] - arcs[index - 1], 0.001)))
	return Transform2D(_tangent(points, points.size() - 1).angle() + PI * 0.5, points[-1])


static func _tangent(points: PackedVector2Array, index: int) -> Vector2:
	return (points[mini(points.size() - 1, index + 1)] - points[maxi(0, index - 1)]).normalized()
