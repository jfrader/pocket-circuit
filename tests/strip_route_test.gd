extends SceneTree

const ROUTE := preload("res://scripts/race/strip_route.gd")
const CATALOG := preload("res://scripts/race/track_builder_catalog.gd")
const LAYOUT := preload("res://scripts/race/strip_layout.gd")
const MAX_HEADING_DEGREES := 45.2


func _initialize() -> void:
	var summaries: Array[String] = []
	for room: String in ["classic", "wide", "tall", "el", "long", "square"]:
		var polygon := LAYOUT.runner_room(CATALOG.ROOM_SHAPES[StringName(room)], "standard")
		var generated_count := 0
		var minimum := INF
		var maximum := 0.0
		var sum := 0.0
		var worst_heading := 0.0
		for seed in 20:
			var route := ROUTE.generate(seed, polygon)
			var repeat := ROUTE.generate(seed, polygon)
			if route.is_empty() or route != repeat or not ROUTE.validate(route["centerline"], polygon):
				_fail("Seed %d %s did not produce a deterministic, valid open route" % [seed, room])
				return
			var line: PackedVector2Array = route["centerline"]
			var length := _length(line)
			minimum = minf(minimum, length)
			maximum = maxf(maximum, length)
			sum += length
			for index in range(1, line.size()):
				var segment := line[index] - line[index - 1]
				var heading := rad_to_deg(absf(Vector2.UP.angle_to(segment)))
				worst_heading = maxf(worst_heading, heading)
				if segment.y >= 0.0 or heading > MAX_HEADING_DEGREES:
					_fail("Route reversed or exceeded north cone in %s seed %d: %.1f°" % [room, seed, heading])
					return
				if line[0].y - line[index].y <= ROUTE.START_STRAIGHT and absf(line[index].x - line[0].x) > 1.0:
					_fail("Start bent before straight finished")
					return
			if not route["fallback"]:
				generated_count += 1
			if line[0].distance_to(line[-1]) < ROUTE.MIN_ENDPOINT_DISTANCE:
				_fail("Endpoints nearly meet")
				return
		var fallback := ROUTE.generate(7, polygon, true)
		if fallback.is_empty() or not fallback["fallback"] or not ROUTE.validate(fallback["centerline"], polygon):
			_fail("Safe fallback failed in " + room)
			return
		for index in range(1, (fallback["centerline"] as PackedVector2Array).size()):
			if (fallback["centerline"] as PackedVector2Array)[index].y >= (fallback["centerline"] as PackedVector2Array)[index - 1].y:
				_fail("Fallback reversed in " + room)
				return
		if generated_count == 0:
			_fail("No shaped candidates in " + room)
			return
		summaries.append("%s %.0f/%.0f/%.0f max_heading=%.1f° shaped=%d/20" % [room, minimum, sum / 20.0, maximum, worst_heading, generated_count])
	for tier in LAYOUT.RUNNER_HEIGHT:
		var polygon := LAYOUT.runner_room(CATALOG.ROOM_SHAPES[&"classic"], tier)
		var sum := 0.0
		var minimum := INF
		var maximum := 0.0
		for seed in 3:
			var route := ROUTE.generate(seed, polygon)
			if route.is_empty() or not ROUTE.validate(route["centerline"], polygon):
				_fail("Invalid north strip at %s seed %d" % [tier, seed])
				return
			var length := _length(route["centerline"])
			minimum = minf(minimum, length)
			maximum = maxf(maximum, length)
			sum += length
		summaries.append("%s %.0f/%.0f/%.0f" % [tier, minimum, sum / 3.0, maximum])
	print("STRIP_ROUTE_TEST PASS min/avg/max: " + "; ".join(summaries))
	quit(0)


func _length(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(1, points.size()):
		total += points[index - 1].distance_to(points[index])
	return total


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
