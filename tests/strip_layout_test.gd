extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const LAYOUT := preload("res://scripts/race/strip_layout.gd")
const IDENTITY := preload("res://scripts/race/generated_circuit_identity.gd")
const PREVIEW := preload("res://scripts/race/circuit_route_preview.gd")
const LAYOUT_GATE_SPACING := 1850.0


func _initialize() -> void:
	var identity := IDENTITY.create(&"kitchen", &"classic", 123, false, 0, "", "", {}, "standard", "strip")
	if identity.is_empty() or String(identity["route_shape"]) != "strip" or bool(IDENTITY.encode_share_code(identity).get("ok", false)):
		_fail("Strip identity or share-code rejection")
		return
	var event := IDENTITY.apply_to_event(identity)
	if String(event["race_format"]) != "strip":
		_fail("Strip event format")
		return
	var first := BUILDER.prepare_layout(&"kitchen", &"classic", 123, IDENTITY.generation_options(identity))
	var repeat := BUILDER.prepare_layout(&"kitchen", &"classic", 123, IDENTITY.generation_options(identity))
	if first.is_empty() or first.get("route_shape") != "strip" or first["centerline"] != repeat["centerline"] or first["traffic_plan"] != repeat["traffic_plan"]:
		_fail("Strip layout determinism")
		return
	for key in ["spec", "centerline", "edges", "room_polygon", "theme", "room_shape", "seed", "strip_gates", "strip_grid", "strip_caps", "racing_line", "traffic_plan", "strip_half_width", "strip_length", "strip_time_limit"]:
		if not first.has(key):
			_fail("Missing layout key " + key)
			return
	var gates: Array = first["strip_gates"]
	if gates.size() < 3 or gates[0]["index"] != 0 or not gates[-1]["is_finish_line"] or gates[0]["arc"] >= gates[1]["arc"]:
		_fail("Ordered strip gates")
		return
	if float(first["strip_length"]) < 700.0 or gates.size() < 4:
		_fail("Strip length or distributed gates")
		return
	for index in range(1, gates.size()):
		if int(gates[index]["index"]) != index or float(gates[index]["arc"]) <= float(gates[index - 1]["arc"]) or float(gates[index]["arc"]) - float(gates[index - 1]["arc"]) > LAYOUT_GATE_SPACING:
			_fail("Strip gates must cover the north road in order")
			return
	var grid: Dictionary = first["strip_grid"]
	if (grid["player"] as Transform2D).origin.distance_to((grid["chaser"] as Transform2D).origin) < 90.0:
		_fail("Unsafe starting grid")
		return
	if absf((grid["player"] as Transform2D).get_rotation()) > 0.001 or absf((grid["chaser"] as Transform2D).get_rotation()) > 0.001 or (first["strip_caps"] as Dictionary)["start"].y <= (first["strip_caps"] as Dictionary)["finish"].y:
		_fail("Strip grid must face north from the south cap")
		return
	for traffic: Dictionary in first["traffic_plan"]:
		if absf(float(traffic["lane"])) > 0.5 or float(traffic["arc"]) >= float(gates[-1]["arc"]) or not traffic["behavior"] in [&"cruiser", &"cutter", &"line", &"swerve", &"truck"]:
			_fail("Unsafe traffic plan")
			return
	if (first["traffic_plan"] as Array).size() < 2 or (first["traffic_plan"] as Array).size() > LAYOUT.MAX_TRAFFIC:
		_fail("Traffic should scale with route length without forming a wall")
		return
	var reversed_identity := IDENTITY.create(&"kitchen", &"classic", 123, true, 0, "", "", {}, "standard", "strip")
	var reversed := BUILDER.prepare_layout(&"kitchen", &"classic", 123, IDENTITY.generation_options(reversed_identity))
	if reversed.is_empty() or (reversed["centerline"] as PackedVector2Array)[0] != (first["centerline"] as PackedVector2Array)[-1]:
		_fail("Reverse strip endpoints")
		return
	var preview := PREVIEW.prepare(identity)
	var reverse_preview := PREVIEW.prepare(reversed_identity)
	if preview.is_empty() or reverse_preview.is_empty() or (preview["points"] as PackedVector2Array).size() < 2 or (preview["points"] as PackedVector2Array)[0] == (preview["points"] as PackedVector2Array)[-1] or (reverse_preview["points"] as PackedVector2Array)[0].distance_to((preview["points"] as PackedVector2Array)[-1]) > 1.0:
		_fail("Open preview lost an endpoint or reversal")
		return
	var long_identity := IDENTITY.create(&"kitchen", &"classic", 123, false, 0, "", "", {}, "long", "strip")
	var long_layout := BUILDER.prepare_layout(&"kitchen", &"classic", 123, IDENTITY.generation_options(long_identity))
	if long_layout.is_empty() or float(long_layout["strip_length"]) <= float(first["strip_length"]):
		_fail("Strip length tier does not scale the room")
		return
	var lengths: Array[String] = []
	for theme in [&"kitchen", &"workshop", &"office"]:
		var themed := BUILDER.prepare_layout(theme, &"classic", 42, {"route_shape": "strip"})
		var themed_spec: Dictionary = themed.get("spec", {})
		var themed_plan: Dictionary = themed_spec.get("environment_plan", {})
		if themed.is_empty() or (themed_plan.get("placements", []) as Array).size() < 8 or (themed_spec.get("obstacle_plan", []) as Array).is_empty():
			_fail("Missing story or safe obstacles for " + String(theme))
			return
		var quarters := {}
		var start_y: float = (themed["strip_caps"] as Dictionary)["start"].y
		var finish_y: float = (themed["strip_caps"] as Dictionary)["finish"].y
		for placement: Dictionary in themed_plan["placements"]:
			quarters[clampi(floori((start_y - (placement["position"] as Vector2).y) / (start_y - finish_y) * 4.0), 0, 3)] = true
		if quarters.size() != 4:
			_fail("Room dressing does not span the full runner for " + String(theme))
			return
		for obstacle: Dictionary in themed_spec["obstacle_plan"]:
			if float(obstacle["viable_corridor_width"]) < 90.0 or not BUILDER._line_sweep_clears_footprint(themed["racing_line"], obstacle["position"], obstacle["footprint_size"], obstacle["footprint_kind"], float(obstacle["rotation"]), float(obstacle["clearance"])):
				_fail("Obstacle blocks the racing line in " + String(theme))
				return
	for tier in ["compact", "standard", "long", "endurance", "marathon"]:
		var minimum := INF
		var maximum := 0.0
		var sum := 0.0
		for seed in 3:
			var layout := BUILDER.prepare_layout(&"kitchen", &"classic", seed, {"route_shape": "strip", "length_tier": tier})
			if layout.is_empty():
				_fail("No " + tier + " strip for seed " + str(seed))
				return
			var length := float(layout["strip_length"])
			minimum = minf(minimum, length)
			maximum = maxf(maximum, length)
			sum += length
			if length < 40000.0 or length > 85000.0:
				_fail("Length outside drivable sprint budget: %s %.0f" % [tier, length])
				return
			var road_room: PackedVector2Array = layout["room_polygon"]
			if road_room.size() <= 4 or road_room[0] == road_room[-1]:
				_fail("Runner must have softened corners and a closed polygon boundary")
				return
			var bounds := Rect2(road_room[0], Vector2.ZERO)
			for point: Vector2 in road_room:
				bounds = bounds.expand(point)
			if bounds.size.x < 2100.0 or bounds.size.x > 2900.0 or length < bounds.size.y * 0.89 or absf(bounds.size.y - float(LAYOUT.RUNNER_HEIGHT[tier])) > 1.0:
				_fail("Runner is too wide or road does not fill its height")
				return
			var tier_gates: Array = layout["strip_gates"]
			for gate_index in range(2, tier_gates.size()):
				var gap := float(tier_gates[gate_index]["arc"]) - float(tier_gates[gate_index - 1]["arc"])
				if gap < 1450.0 or gap > LAYOUT_GATE_SPACING:
					_fail("Inconsistent gate spacing on " + tier)
					return
			var limit := float(layout["strip_time_limit"])
			if limit < 75.0 or absf(limit - ceilf(length / LAYOUT.CLEAN_SPEED_ESTIMATE * LAYOUT.TIME_LIMIT_FACTOR)) > 0.01:
				_fail("Strip limit must follow its drivable length")
				return
			var traffic_plan: Array = layout["traffic_plan"]
			if traffic_plan.size() != clampi(floori((length - LAYOUT.TRAFFIC_MIN_ARC - LAYOUT.TRAFFIC_FINISH_CLEARANCE) / LAYOUT.TRAFFIC_SPACING), 2, LAYOUT.MAX_TRAFFIC):
				_fail("Traffic count did not scale with route length")
				return
			var behaviors := {}
			var previous_arc := 0.0
			var cruisers := 0
			var packed_pairs := 0
			for car: Dictionary in traffic_plan:
				behaviors[car["behavior"]] = true
				if car["behavior"] == &"cruiser":
					cruisers += 1
				if float(car["arc"]) - previous_arc <= LAYOUT.TRAFFIC_PACK_SEPARATION + 0.1:
					packed_pairs += 1
				if float(car["speed"]) < 210.0 or float(car["speed"]) > 225.0 or absf(float(car["lane"])) > 0.45 or float(car["arc"]) - previous_arc < LAYOUT.TRAFFIC_PACK_SEPARATION - 0.1 or float(car["arc"]) - previous_arc > length / 10.0 or float(car["arc"]) >= length - LAYOUT.TRAFFIC_FINISH_CLEARANCE:
					_fail("Traffic speed, spacing or lane on %s: arc=%.1f gap=%.1f" % [tier, float(car["arc"]), float(car["arc"]) - previous_arc])
					return
				previous_arc = float(car["arc"])
			if previous_arc < length * 0.82 or cruisers < traffic_plan.size() / 2 or packed_pairs < traffic_plan.size() / 3 or not behaviors.has(&"cutter") or not behaviors.has(&"swerve") or not behaviors.has(&"truck"):
				_fail("Traffic must fill the runner with cruiser packs and lone cutter, swerve, truck")
				return
		lengths.append("%s %.0f/%.0f/%.0f limit=%.0fs" % [tier, minimum, sum / 3.0, maximum, ceilf(sum / 3.0 / LAYOUT.CLEAN_SPEED_ESTIMATE * LAYOUT.TIME_LIMIT_FACTOR)])
	print("STRIP_LAYOUT_TEST PASS gates=%d traffic=%d tier min/avg/max (wu): %s" % [gates.size(), (first["traffic_plan"] as Array).size(), "; ".join(lengths)])
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
