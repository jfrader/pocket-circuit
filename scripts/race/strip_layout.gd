extends RefCounted

const ROUTE := preload("res://scripts/race/strip_route.gd")
const GENERATED_RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const WORLD_MATERIALS := preload("res://scripts/race/generated_world_materials.gd")
const SURFACES := preload("res://scripts/race/household_surface_materials.gd")
const VEHICLES := preload("res://data/championship/catalog.gd")
const GRID_ARC := 210.0
const CHASER_GAP := 120.0
const FINISH_INSET := 145.0
const GATE_SPACING := 850.0
const AXIS_SCALE_GAIN := 0.4
const CROSS_SCALE_GAIN := 0.07
const MIN_GATE_COUNT := 6
const MAX_GATE_COUNT := 64
const TRAFFIC_MIN_ARC := 460.0
const TRAFFIC_FINISH_CLEARANCE := 340.0


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
	spec["story_kit"] = {"id": spec["story_id"], "object_line": (kit.get("object_line", {}) as Dictionary).duplicate(true)}
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
	return {"spec": spec, "centerline": centerline, "edges": {"left": left, "right": right}, "room_polygon": room_polygon, "theme": theme, "room_shape": room_shape, "seed": seed, "route_shape": "strip", "strip_length": total, "strip_gates": gates, "strip_grid": grid, "strip_half_width": ROUTE.HALF_WIDTH, "strip_caps": {"start": centerline[0], "finish": centerline[-1]}, "racing_line": centerline.duplicate(), "traffic_plan": _traffic(seed, total)}


static func _traffic(seed: int, total: float) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed ^ 0x524F4144) & 0x7FFFFFFF
	var result: Array[Dictionary] = []
	var vehicle_ids := VEHICLES.quick_race_vehicle_ids()
	var available := total - TRAFFIC_MIN_ARC - TRAFFIC_FINISH_CLEARANCE
	if available <= 0.0:
		return result
	var count := clampi(floori(available / 1800.0), 2, 6)
	for index in count:
		result.append({"arc": TRAFFIC_MIN_ARC + available * (index + 1.0) / (count + 1.0), "lane": rng.randf_range(-0.45, 0.45), "speed": rng.randf_range(180.0, 290.0), "behavior": [&"cruiser", &"cutter", &"line"][rng.randi_range(0, 2)], "vehicle_id": vehicle_ids[rng.randi_range(0, vehicle_ids.size() - 1)]})
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
