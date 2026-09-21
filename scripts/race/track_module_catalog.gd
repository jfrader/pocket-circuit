class_name TrackModuleCatalog
extends RefCounted

const CATALOG_DATA := preload("res://data/tracks/v8_module_catalog.gd")

const HALF_WIDTH := 125.0
const RESERVED_RADIUS := 135.0
const PORT_WIDTH := HALF_WIDTH * 2.0
const MIN_CONSTRUCTION_RADIUS := 180.0
const POSITION_TOLERANCE := 0.01
const HEADING_TOLERANCE := 0.0001
const WIDTH_TOLERANCE := 0.001

static var _definitions: Dictionary = {}


static func definitions() -> Array[Dictionary]:
	return CATALOG_DATA.definitions()


static func definition(module_id: StringName) -> Dictionary:
	if _definitions.is_empty():
		for item: Dictionary in definitions():
			_definitions[item["id"]] = item
	return (_definitions.get(module_id, {}) as Dictionary).duplicate(true)


static func instantiate(module_id: StringName, parameters: Dictionary, options: Dictionary = {}) -> Dictionary:
	var module_definition := definition(module_id)
	if module_definition.is_empty():
		return _error("unknown_module", "Unknown track module '%s'." % module_id)
	var parameter_check := _validate_parameters(module_id, parameters)
	if not bool(parameter_check.get("valid", false)):
		return parameter_check
	var primitives: Array[Dictionary] = []
	var pose := {"position": Vector2.ZERO, "heading": 0.0}
	var angle := deg_to_rad(float(parameters.get("angle_deg", 0.0))) * signf(float(parameters.get("hand", 1.0)))
	match module_id:
		&"straight_link", &"straight_setup":
			_append_line(primitives, pose, float(parameters["length"]))
		&"corner_tight", &"corner_medium", &"corner_sweeper":
			_append_arc(primitives, pose, float(parameters["radius"]), angle)
		&"corner_opening":
			var split := float(parameters["split"])
			_append_arc(primitives, pose, float(parameters["inner_radius"]), angle * split)
			_append_arc(primitives, pose, float(parameters["outer_radius"]), angle * (1.0 - split))
		&"corner_tightening":
			var split := float(parameters["split"])
			_append_arc(primitives, pose, float(parameters["outer_radius"]), angle * split)
			_append_arc(primitives, pose, float(parameters["inner_radius"]), angle * (1.0 - split))
		&"u_return":
			_append_arc(primitives, pose, float(parameters["radius"]), PI * signf(float(parameters.get("hand", 1.0))))
		&"s_offset":
			_append_arc(primitives, pose, float(parameters["radius"]), angle)
			_append_line(primitives, pose, float(parameters["distance"]))
			_append_arc(primitives, pose, float(parameters["radius"]), -angle)
		&"chicane_return":
			_append_arc(primitives, pose, float(parameters["radius"]), angle)
			_append_arc(primitives, pose, float(parameters["radius"]), -angle)
			_append_line(primitives, pose, float(parameters["distance"]))
			_append_arc(primitives, pose, float(parameters["radius"]), -angle)
			_append_arc(primitives, pose, float(parameters["radius"]), angle)
		&"switchback":
			var hand := signf(float(parameters.get("hand", 1.0)))
			var quarter := hand * PI * 0.5
			_append_arc(primitives, pose, float(parameters["radius"]), quarter)
			_append_line(primitives, pose, float(parameters["depth_1"]))
			_append_arc(primitives, pose, float(parameters["radius"]), -quarter)
			_append_line(primitives, pose, float(parameters["width"]))
			_append_arc(primitives, pose, float(parameters["radius"]), -quarter)
			_append_line(primitives, pose, float(parameters["depth_2"]))
			_append_arc(primitives, pose, float(parameters["radius"]), quarter)
	if bool(options.get("mirror", false)):
		primitives = _mirror_primitives(primitives)
	if bool(options.get("reverse", false)):
		primitives = _reverse_primitives(primitives)
	var module := _describe_instance(module_definition, parameters, primitives, options)
	var validation := validate_instance(module)
	module["local_validation"] = validation
	if not bool(validation.get("valid", false)):
		return validation
	module["ok"] = true
	return module


static func compose(instances: Array[Dictionary], entry_position: Vector2 = Vector2.ZERO, entry_heading: float = 0.0) -> Dictionary:
	if instances.is_empty():
		return _error("empty_cycle", "A route needs at least one module.")
	var world_pose := {"position": entry_position, "heading": entry_heading}
	var route_primitives: Array[Dictionary] = []
	var modules: Array[Dictionary] = []
	var protected_intervals: Array[Dictionary] = []
	var sweeps: Array[Dictionary] = []
	var return_limb_pairs: Array[Dictionary] = []
	var route_length := 0.0
	var signed_turn := 0.0
	for module_index in instances.size():
		var instance: Dictionary = instances[module_index]
		if not bool(instance.get("ok", false)):
			return _error("invalid_module", "Module %d is not a validated catalog instance." % module_index)
		var module_entry := _port(world_pose["position"], float(world_pose["heading"]))
		var world_primitives: Array[Dictionary] = []
		for local_primitive: Dictionary in instance["primitives"]:
			var primitive := _transform_primitive(local_primitive, world_pose["position"], float(world_pose["heading"]))
			primitive["index"] = route_primitives.size()
			primitive["module_index"] = module_index
			primitive["s_start"] = route_length
			route_length += float(primitive["length"])
			primitive["s_end"] = route_length
			signed_turn += float(primitive["signed_turn"])
			world_primitives.append(primitive)
			route_primitives.append(primitive)
			for radius: float in [HALF_WIDTH, RESERVED_RADIUS]:
				var sweep := _primitive_sweep(primitive, radius)
				sweep["primitive_index"] = int(primitive["index"])
				sweeps.append(sweep)
		var local_exit: Dictionary = instance["exit_port"]
		var exit_position := _transform_point(local_exit["position"], world_pose["position"], float(world_pose["heading"]))
		var exit_heading := float(world_pose["heading"]) + float(local_exit["heading"])
		var module_exit := _port(exit_position, exit_heading)
		var world_module := instance.duplicate(true)
		world_module["index"] = module_index
		world_module["entry_port"] = module_entry
		world_module["exit_port"] = module_exit
		world_module["primitives"] = world_primitives
		world_module["s_start"] = route_length - float(instance["length"])
		world_module["s_end"] = route_length
		modules.append(world_module)
		for interval: Dictionary in instance["protected_setup_intervals"]:
			protected_intervals.append({"from": float(world_module["s_start"]) + float(interval["from"]), "to": float(world_module["s_start"]) + float(interval["to"]), "module_index": module_index})
		for pair: Dictionary in instance["return_limb_pairs"]:
			var world_pair := pair.duplicate(true)
			world_pair["module_index"] = module_index
			return_limb_pairs.append(world_pair)
		world_pose = {"position": exit_position, "heading": exit_heading}
	return {
		"ok": true,
		"entry_port": _port(entry_position, entry_heading),
		"exit_port": _port(world_pose["position"], float(world_pose["heading"])),
		"modules": modules,
		"primitives": route_primitives,
		"length": route_length,
		"signed_turn": signed_turn,
		"straight_intervals": _maximal_straight_intervals(route_primitives, route_length),
		"protected_setup_intervals": protected_intervals,
		"sweeps": sweeps,
		"return_limb_pairs": return_limb_pairs,
	}


static func sample_route(route: Dictionary, minimum_samples: int = 260, maximum_step: float = 35.0, maximum_chord_deviation: float = 0.25) -> Dictionary:
	if not bool(route.get("ok", false)) or (route.get("primitives", []) as Array).is_empty():
		return _error("invalid_route", "Only a composed analytic route can be sampled.")
	var target_step := minf(maximum_step, float(route["length"]) / float(maxi(minimum_samples, 1)))
	var points := PackedVector2Array()
	var primitive_boundaries := PackedInt32Array()
	var max_realized_step := 0.0
	var max_realized_arc_step := 0.0
	var max_realized_deviation := 0.0
	for primitive_index in (route["primitives"] as Array).size():
		var primitive: Dictionary = route["primitives"][primitive_index]
		primitive_boundaries.append(points.size())
		if points.is_empty():
			points.append(primitive["start"])
		var steps := maxi(1, ceili(float(primitive["length"]) / target_step))
		if primitive["kind"] == &"arc":
			var radius := float(primitive["radius"])
			var deviation_angle := 2.0 * acos(clampf(1.0 - maximum_chord_deviation / radius, -1.0, 1.0))
			steps = maxi(steps, ceili(absf(float(primitive["signed_turn"])) / maxf(deviation_angle, 0.000001)))
		for step in range(1, steps + 1):
			if primitive_index == (route["primitives"] as Array).size() - 1 and step == steps:
				continue
			var fraction := float(step) / float(steps)
			var point := _primitive_point(primitive, fraction)
			max_realized_step = maxf(max_realized_step, points[points.size() - 1].distance_to(point))
			points.append(point)
		if primitive["kind"] == &"arc":
			var arc_step := float(primitive["length"]) / float(steps)
			var angle_step := absf(float(primitive["signed_turn"])) / float(steps)
			max_realized_arc_step = maxf(max_realized_arc_step, arc_step)
			max_realized_deviation = maxf(max_realized_deviation, float(primitive["radius"]) * (1.0 - cos(angle_step * 0.5)))
	max_realized_step = maxf(max_realized_step, points[points.size() - 1].distance_to(points[0]))
	if points.size() < minimum_samples:
		return _error("sample_count", "Analytic sampling produced fewer than %d points." % minimum_samples)
	return {
		"ok": true,
		"points": points,
		"sample_count": points.size(),
		"maximum_step": max_realized_step,
		"maximum_arc_step": max_realized_arc_step,
		"maximum_chord_deviation": max_realized_deviation,
		"primitive_boundaries": primitive_boundaries,
	}


static func validate_instance(module: Dictionary) -> Dictionary:
	var primitives: Array = module.get("primitives", [])
	if primitives.is_empty():
		return _error("empty_recipe", "A module recipe must contain an analytic primitive.")
	var expected_position := Vector2.ZERO
	var expected_heading := 0.0
	var length := 0.0
	for index in primitives.size():
		var primitive: Dictionary = primitives[index]
		if not _finite_vector(primitive.get("start", Vector2(INF, INF))) or not _finite_vector(primitive.get("end", Vector2(INF, INF))) or not is_finite(float(primitive.get("length", INF))) or float(primitive.get("length", 0.0)) <= 0.0:
			return _error("invalid_primitive", "Module primitive %d is not finite and positive." % index)
		if (primitive["start"] as Vector2).distance_to(expected_position) > POSITION_TOLERANCE or absf(_wrapped_angle(float(primitive["heading"]) - expected_heading)) > HEADING_TOLERANCE:
			return _error("broken_recipe_join", "Module primitive %d does not share its predecessor pose." % index)
		if primitive["kind"] == &"arc" and float(primitive["radius"]) < MIN_CONSTRUCTION_RADIUS:
			return _error("radius_floor", "Module primitive %d has radius below %.0f." % [index, MIN_CONSTRUCTION_RADIUS])
		expected_position = primitive["end"]
		expected_heading = float(primitive["end_heading"])
		length += float(primitive["length"])
	var exit_port: Dictionary = module["exit_port"]
	if (exit_port["position"] as Vector2).distance_to(expected_position) > POSITION_TOLERANCE or absf(_wrapped_angle(float(exit_port["heading"]) - expected_heading)) > HEADING_TOLERANCE:
		return _error("exit_pose", "Computed exit port does not match the analytic recipe.")
	for pair: Dictionary in module.get("return_limb_pairs", []):
		if not bool(pair.get("certified", false)) or float(pair.get("separation", 0.0)) < 320.0:
			return _error("return_limb_spacing", "Module return limbs do not preserve 320 units.")
	return {"valid": true, "ok": true, "length": length, "minimum_radius": float(module["minimum_radius"]), "signed_turn": float(module["signed_turn"])}


static func validate_join(exit_port: Dictionary, entry_port: Dictionary) -> Dictionary:
	var position_residual := (exit_port.get("position", Vector2(INF, INF)) as Vector2).distance_to(entry_port.get("position", Vector2(-INF, -INF)) as Vector2)
	var heading_residual := absf(_wrapped_angle(float(exit_port.get("heading", INF)) - float(entry_port.get("heading", -INF))))
	var width_residual := absf(float(exit_port.get("width", INF)) - float(entry_port.get("width", -INF)))
	var elevation_equal := float(exit_port.get("elevation", INF)) == 0.0 and float(entry_port.get("elevation", INF)) == 0.0
	var continuity_equal: bool = exit_port.get("surface") == entry_port.get("surface") and exit_port.get("support") == entry_port.get("support")
	return {
		"valid": position_residual <= POSITION_TOLERANCE and heading_residual <= HEADING_TOLERANCE and width_residual <= WIDTH_TOLERANCE and elevation_equal and continuity_equal,
		"position_residual": position_residual,
		"heading_residual": heading_residual,
		"width_residual": width_residual,
	}


static func _describe_instance(module_definition: Dictionary, parameters: Dictionary, primitives: Array[Dictionary], options: Dictionary) -> Dictionary:
	var length := 0.0
	var signed_turn := 0.0
	var minimum_radius := INF
	var minimum_curvature := INF
	var maximum_curvature := -INF
	var straight_intervals: Array[Dictionary] = []
	for primitive: Dictionary in primitives:
		var start_length := length
		length += float(primitive["length"])
		signed_turn += float(primitive["signed_turn"])
		if primitive["kind"] == &"line":
			straight_intervals.append({"from": start_length, "to": length})
			minimum_curvature = minf(minimum_curvature, 0.0)
			maximum_curvature = maxf(maximum_curvature, 0.0)
		else:
			minimum_radius = minf(minimum_radius, float(primitive["radius"]))
			var curvature := signf(float(primitive["signed_turn"])) / float(primitive["radius"])
			minimum_curvature = minf(minimum_curvature, curvature)
			maximum_curvature = maxf(maximum_curvature, curvature)
	var protected: Array[Dictionary] = []
	if module_definition["id"] == &"straight_setup":
		protected.append({"from": 0.0, "to": length, "minimum_clear_length": 450.0, "finish": bool(parameters.get("finish", false))})
	var return_pairs: Array[Dictionary] = []
	if module_definition["id"] == &"u_return":
		return_pairs.append({"kind": &"parallel_return_limbs", "separation": 2.0 * float(parameters["radius"]), "certified": true})
	elif module_definition["id"] == &"switchback":
		return_pairs.append({"kind": &"parallel_return_limbs", "separation": 2.0 * float(parameters["radius"]) + float(parameters["width"]), "certified": true})
	var keep_clear: Array[Dictionary] = []
	if module_definition["id"] == &"straight_setup":
		keep_clear.append({"kind": &"setup", "from": 0.0, "to": length, "half_width": RESERVED_RADIUS})
		if bool(parameters.get("finish", false)):
			keep_clear.append({"kind": &"finish_grid", "from": 0.0, "to": length, "half_width": RESERVED_RADIUS})
	var exit_position: Vector2 = primitives[primitives.size() - 1]["end"]
	var exit_heading := float(primitives[primitives.size() - 1]["end_heading"])
	var family: StringName = module_definition["family"]
	if bool(options.get("reverse", false)):
		if module_definition["id"] == &"corner_opening":
			family = &"tightening"
		elif module_definition["id"] == &"corner_tightening":
			family = &"opening"
	return {
		"id": module_definition["id"],
		"revision": module_definition["revision"],
		"family": family,
		"parameters": parameters.duplicate(true),
		"transform": {"mirror": bool(options.get("mirror", false)), "reverse": bool(options.get("reverse", false))},
		"entry_port": _port(Vector2.ZERO, 0.0),
		"exit_port": _port(exit_position, exit_heading),
		"primitives": primitives,
		"length": length,
		"signed_turn": signed_turn,
		"minimum_radius": minimum_radius,
		"curvature_bounds": Vector2(minimum_curvature, maximum_curvature),
		"straight_intervals": straight_intervals,
		"protected_setup_intervals": protected,
		"sweeps": _local_sweeps(primitives),
		"return_limb_pairs": return_pairs,
		"keep_clear_envelopes": keep_clear,
		"story_sockets": [],
		"finish_checker_s": length * 0.5 if module_definition["id"] == &"straight_setup" and bool(parameters.get("finish", false)) else -1.0,
		"validation_hooks": [&"validate_instance", &"validate_join", &"validate_continuous", &"validate_sampled"],
	}


static func _validate_parameters(module_id: StringName, parameters: Dictionary) -> Dictionary:
	var hand := float(parameters.get("hand", 1.0))
	if hand not in [-1.0, 1.0]:
		return _error("invalid_hand", "Module hand must be -1 or +1.")
	match module_id:
		&"straight_link", &"straight_setup":
			var minimum := 520.0 if module_id == &"straight_setup" else 180.0
			if not _in_range(parameters.get("length"), minimum, 2400.0):
				return _error("parameter_domain", "%s length is outside its authored domain." % module_id)
			if module_id == &"straight_setup" and bool(parameters.get("finish", false)) and float(parameters["length"]) < 1000.0:
				return _error("parameter_domain", "A finish setup straight must be at least 1000 units.")
		&"corner_tight", &"corner_medium", &"corner_sweeper":
			var bounds := {&"corner_tight": Vector2(180.0, 260.0), &"corner_medium": Vector2(260.0, 520.0), &"corner_sweeper": Vector2(520.0, 1000.0)}[module_id] as Vector2
			if not _in_range(parameters.get("radius"), bounds.x, bounds.y, module_id != &"corner_sweeper") or not _allowed_angle(parameters.get("angle_deg"), [45.0, 90.0, 135.0]):
				return _error("parameter_domain", "%s parameters are outside the authored domain." % module_id)
		&"corner_opening", &"corner_tightening":
			if not _in_range(parameters.get("inner_radius"), 180.0, 560.0) or not _in_range(parameters.get("outer_radius"), 225.0, 700.0) or float(parameters["outer_radius"]) / float(parameters["inner_radius"]) < 1.25 or not _allowed_angle(parameters.get("angle_deg"), [45.0, 90.0, 135.0]) or not _allowed_angle(parameters.get("split"), [0.35, 0.5, 0.65]):
				return _error("parameter_domain", "%s parameters are outside the authored domain." % module_id)
		&"u_return":
			if not _in_range(parameters.get("radius"), 180.0, 520.0):
				return _error("parameter_domain", "u_return radius is outside its authored domain.")
		&"s_offset", &"chicane_return":
			if not _in_range(parameters.get("radius"), 180.0, 520.0) or not _in_range(parameters.get("distance"), 180.0, 900.0) or not _allowed_angle(parameters.get("angle_deg"), [30.0, 45.0, 60.0]):
				return _error("parameter_domain", "%s parameters are outside the authored domain." % module_id)
		&"switchback":
			if not _in_range(parameters.get("radius"), 180.0, 360.0) or not _in_range(parameters.get("depth_1"), 450.0, 1600.0) or not _in_range(parameters.get("depth_2"), 450.0, 1600.0) or not _in_range(parameters.get("width"), 400.0, 1200.0):
				return _error("parameter_domain", "switchback parameters are outside the authored domain.")
	return {"valid": true, "ok": true}


static func _append_line(primitives: Array[Dictionary], pose: Dictionary, length: float) -> void:
	var start: Vector2 = pose["position"]
	var heading := float(pose["heading"])
	var finish := start + Vector2.RIGHT.rotated(heading) * length
	primitives.append({"kind": &"line", "start": start, "end": finish, "heading": heading, "end_heading": heading, "length": length, "signed_turn": 0.0, "minimum_radius": INF})
	pose["position"] = finish


static func _append_arc(primitives: Array[Dictionary], pose: Dictionary, radius: float, turn: float) -> void:
	var start: Vector2 = pose["position"]
	var heading := float(pose["heading"])
	var center := start + Vector2.RIGHT.rotated(heading + signf(turn) * PI * 0.5) * radius
	var finish := center + (start - center).rotated(turn)
	primitives.append({"kind": &"arc", "start": start, "end": finish, "heading": heading, "end_heading": heading + turn, "center": center, "radius": radius, "start_angle": (start - center).angle(), "length": radius * absf(turn), "signed_turn": turn, "minimum_radius": radius})
	pose["position"] = finish
	pose["heading"] = heading + turn


static func _mirror_primitives(primitives: Array[Dictionary]) -> Array[Dictionary]:
	var mirrored: Array[Dictionary] = []
	for original: Dictionary in primitives:
		var primitive := original.duplicate(true)
		primitive["start"] = Vector2((original["start"] as Vector2).x, -(original["start"] as Vector2).y)
		primitive["end"] = Vector2((original["end"] as Vector2).x, -(original["end"] as Vector2).y)
		primitive["heading"] = -float(original["heading"])
		primitive["end_heading"] = -float(original["end_heading"])
		primitive["signed_turn"] = -float(original["signed_turn"])
		if original["kind"] == &"arc":
			primitive["center"] = Vector2((original["center"] as Vector2).x, -(original["center"] as Vector2).y)
			primitive["start_angle"] = ((primitive["start"] as Vector2) - (primitive["center"] as Vector2)).angle()
		mirrored.append(primitive)
	return mirrored


static func _reverse_primitives(primitives: Array[Dictionary]) -> Array[Dictionary]:
	var old_exit: Vector2 = primitives[primitives.size() - 1]["end"]
	var old_exit_heading := float(primitives[primitives.size() - 1]["end_heading"])
	var reversed: Array[Dictionary] = []
	for index in range(primitives.size() - 1, -1, -1):
		var original: Dictionary = primitives[index]
		var primitive := original.duplicate(true)
		primitive["start"] = _transform_point(original["end"], -old_exit.rotated(-(old_exit_heading + PI)), -(old_exit_heading + PI))
		primitive["end"] = _transform_point(original["start"], -old_exit.rotated(-(old_exit_heading + PI)), -(old_exit_heading + PI))
		primitive["heading"] = float(original["end_heading"]) + PI - (old_exit_heading + PI)
		primitive["end_heading"] = float(original["heading"]) + PI - (old_exit_heading + PI)
		primitive["signed_turn"] = -float(original["signed_turn"])
		if original["kind"] == &"arc":
			primitive["center"] = _transform_point(original["center"], -old_exit.rotated(-(old_exit_heading + PI)), -(old_exit_heading + PI))
			primitive["start_angle"] = ((primitive["start"] as Vector2) - (primitive["center"] as Vector2)).angle()
		reversed.append(primitive)
	return reversed


static func _transform_primitive(local: Dictionary, origin: Vector2, rotation: float) -> Dictionary:
	var result := local.duplicate(true)
	result["start"] = _transform_point(local["start"], origin, rotation)
	result["end"] = _transform_point(local["end"], origin, rotation)
	result["heading"] = float(local["heading"]) + rotation
	result["end_heading"] = float(local["end_heading"]) + rotation
	if local["kind"] == &"arc":
		result["center"] = _transform_point(local["center"], origin, rotation)
		result["start_angle"] = float(local["start_angle"]) + rotation
	return result


static func _port(position: Vector2, heading: float) -> Dictionary:
	var tangent := Vector2.RIGHT.rotated(heading)
	var normal := tangent.rotated(PI * 0.5)
	return {"position": position, "heading": heading, "tangent": tangent, "left": position + normal * HALF_WIDTH, "right": position - normal * HALF_WIDTH, "width": PORT_WIDTH, "elevation": 0.0, "surface": &"road", "support": &"floor"}


static func _local_sweeps(primitives: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for index in primitives.size():
		for radius: float in [HALF_WIDTH, RESERVED_RADIUS]:
			var sweep := _primitive_sweep(primitives[index], radius)
			sweep["primitive_index"] = index
			result.append(sweep)
	return result


static func _primitive_sweep(primitive: Dictionary, sweep_radius: float) -> Dictionary:
	if primitive["kind"] == &"line":
		return {
			"kind": &"line_capsule",
			"from": primitive["start"],
			"to": primitive["end"],
			"radius": sweep_radius,
		}
	return {
		"kind": &"arc_annular_sector",
		"center": primitive["center"],
		"centerline_radius": primitive["radius"],
		"inner_radius": maxf(0.0, float(primitive["radius"]) - sweep_radius),
		"outer_radius": float(primitive["radius"]) + sweep_radius,
		"start_angle": primitive["start_angle"],
		"signed_turn": primitive["signed_turn"],
		"radius": sweep_radius,
	}


static func _maximal_straight_intervals(primitives: Array[Dictionary], route_length: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var previous_was_line := false
	var previous_heading := 0.0
	for primitive: Dictionary in primitives:
		if primitive["kind"] != &"line":
			previous_was_line = false
			continue
		var heading := float(primitive["heading"])
		if previous_was_line and absf(_wrapped_angle(heading - previous_heading)) <= HEADING_TOLERANCE:
			result[result.size() - 1]["to"] = float(primitive["s_end"])
		else:
			result.append({"from": float(primitive["s_start"]), "to": float(primitive["s_end"]), "heading": heading})
		previous_was_line = true
		previous_heading = heading
	if result.size() > 1 and primitives[0]["kind"] == &"line" and primitives[primitives.size() - 1]["kind"] == &"line":
		var first: Dictionary = result[0]
		var last: Dictionary = result[result.size() - 1]
		if absf(_wrapped_angle(float(first["heading"]) - float(last["heading"]))) <= HEADING_TOLERANCE:
			first["from"] = float(last["from"]) - route_length
			result[0] = first
			result.remove_at(result.size() - 1)
	return result


static func _primitive_point(primitive: Dictionary, fraction: float) -> Vector2:
	if primitive["kind"] == &"line":
		return (primitive["start"] as Vector2).lerp(primitive["end"], fraction)
	return (primitive["center"] as Vector2) + ((primitive["start"] as Vector2) - (primitive["center"] as Vector2)).rotated(float(primitive["signed_turn"]) * fraction)


static func _transform_point(point: Vector2, origin: Vector2, rotation: float) -> Vector2:
	return origin + point.rotated(rotation)


static func _in_range(value: Variant, minimum: float, maximum: float, maximum_exclusive: bool = false) -> bool:
	if value is not int and value is not float:
		return false
	var number := float(value)
	return is_finite(number) and number >= minimum and (number < maximum if maximum_exclusive else number <= maximum)


static func _allowed_angle(value: Variant, allowed: Array) -> bool:
	if value is not int and value is not float:
		return false
	for candidate: float in allowed:
		if is_equal_approx(float(value), candidate):
			return true
	return false


static func _finite_vector(value: Vector2) -> bool:
	return is_finite(value.x) and is_finite(value.y)


static func _wrapped_angle(angle: float) -> float:
	return wrapf(angle, -PI, PI)


static func _error(kind: String, message: String) -> Dictionary:
	return {"ok": false, "valid": false, "kind": kind, "reason": message, "error": message}
