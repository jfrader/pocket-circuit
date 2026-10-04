extends RefCounted

const ROUTE := preload("res://scripts/race/strip_route.gd")
const GENERATED_RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const WORLD_MATERIALS := preload("res://scripts/race/generated_world_materials.gd")
const SURFACES := preload("res://scripts/race/household_surface_materials.gd")
const VEHICLES := preload("res://data/championship/catalog.gd")
const DRESSING := preload("res://scripts/race/strip_dressing.gd")
const GRID_ARC := 210.0
const CHASER_GAP := 120.0
const FINISH_INSET := 145.0
const GATE_SPACING := 1750.0
const MIN_GATE_COUNT := 4
const MAX_GATE_COUNT := 64
const TRAFFIC_MIN_ARC := 460.0
const TRAFFIC_FINISH_CLEARANCE := 340.0
const TRAFFIC_SPACING := 1750.0
const MAX_TRAFFIC := 12
const MIN_TIME_LIMIT := 75.0
const CLEAN_SPEED_ESTIMATE := 600.0
const TIME_LIMIT_FACTOR := 1.8
const MIN_RUNNER_WIDTH := 2200.0
const MAX_RUNNER_WIDTH := 2800.0
const CORNER_RADIUS := 170.0
const CORNER_STEPS := 5
const RUNNER_HEIGHT := {
	"compact": 41000.0,
	"standard": 49000.0,
	"long": 57000.0,
	"endurance": 69000.0,
	"marathon": 81000.0,
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
	var route := ROUTE.generate(seed, room_polygon)
	if route.is_empty():
		return {}
	var centerline: PackedVector2Array = (route["centerline"] as PackedVector2Array).duplicate()
	if bool(options.get("reverse", false)):
		centerline.reverse()
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
	spec["length_tier"] = String(options.get("length_tier", "standard"))
	var sub_seeds: Dictionary = options.get("sub_seeds", {})
	spec["material_seed"] = int(sub_seeds.get("material", seed))
	spec["dressing_seed"] = int(sub_seeds.get("dressing", seed))
	spec["obstacle_seed"] = int(sub_seeds.get("obstacle", seed))
	spec["material_id"] = String(options.get("material_id", ""))
	spec["palette_id"] = String(options.get("palette_id", ""))
	spec["story_id"] = GENERATED_RULES.story_id(theme, spec["dressing_seed"])
	var kit_index := GENERATED_RULES.story_index(theme, spec["dressing_seed"])
	var kit: Dictionary = kits[kit_index]
	spec["story_kit"] = kit.duplicate(true)
	spec["story_kit"]["id"] = spec["story_id"]
	WORLD_MATERIALS.apply_to_spec(spec, WORLD_MATERIALS.resolve(theme, spec["story_id"], spec["material_seed"], spec["material_id"], spec["palette_id"]))
	var surface: Dictionary = SURFACES.resolve(theme, spec["material_seed"], spec["material_id"], spec["palette_id"], spec.get("floor_modulate", Color.WHITE))
	spec["surface_identity"] = surface
	spec["floor_texture"] = surface["floor"]["texture"]
	spec["track_texture"] = surface["course"]["texture"]
	spec["floor_modulate"] = Color.WHITE
	spec["obstacle_plan"] = []
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
	var environment := DRESSING.plan(spec, theme, centerline, room_polygon, gates)
	spec["environment_plan"] = {"placements": environment["placements"], "diagnostics": environment["diagnostics"]}
	spec["obstacle_plan"] = environment["obstacles"]
	return {"spec": spec, "centerline": centerline, "edges": {"left": left, "right": right}, "room_polygon": room_polygon, "theme": theme, "room_shape": room_shape, "seed": seed, "route_shape": "strip", "strip_length": total, "strip_time_limit": maxf(MIN_TIME_LIMIT, ceilf(total / CLEAN_SPEED_ESTIMATE * TIME_LIMIT_FACTOR)), "strip_gates": gates, "strip_grid": grid, "strip_half_width": ROUTE.HALF_WIDTH, "strip_caps": {"start": centerline[0], "finish": centerline[-1]}, "racing_line": centerline.duplicate(), "traffic_plan": _traffic(seed, total)}


static func _traffic(seed: int, total: float) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed ^ 0x524F4144) & 0x7FFFFFFF
	var result: Array[Dictionary] = []
	var vehicle_ids := VEHICLES.quick_race_vehicle_ids()
	var available := total - TRAFFIC_MIN_ARC - TRAFFIC_FINISH_CLEARANCE
	if available <= 0.0:
		return result
	var count := clampi(floori(available / TRAFFIC_SPACING), 2, MAX_TRAFFIC)
	var behaviors := [&"cruiser", &"cutter", &"line"]
	var behavior_offset := rng.randi_range(0, behaviors.size() - 1)
	for index in count:
		result.append({"arc": TRAFFIC_MIN_ARC + available * (index + 1.0) / (count + 1.0), "lane": rng.randf_range(-0.45, 0.45), "speed": rng.randf_range(210.0, 225.0), "behavior": behaviors[(index + behavior_offset) % behaviors.size()], "vehicle_id": vehicle_ids[rng.randi_range(0, vehicle_ids.size() - 1)]})
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
