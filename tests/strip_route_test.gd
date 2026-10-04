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
		var tightest_radius := INF
		var least_width := INF
		for seed in 20:
			var route := ROUTE.generate(seed, polygon)
			var repeat := ROUTE.generate(seed, polygon)
			if route.is_empty() or route != repeat or not ROUTE.validate(route["centerline"], polygon):
				_fail("Seed %d %s did not produce a deterministic, valid open route" % [seed, room])
				return
			var line: PackedVector2Array = route["centerline"]
			if not route.has("sections") or (route["sections"] as Array).is_empty():
				_fail("Route needs measured section grammar, not an undifferentiated wave")
				return
			var kinds := {}
			var held_bend := false
			var previous_section := {}
			for section: Dictionary in route["sections"]:
				kinds[section["kind"]] = true
				if not previous_section.is_empty():
					if not is_equal_approx(float(section["start_arc"]), float(previous_section["end_arc"])):
						_fail("Section measurements leave a gap in the route")
						return
					if section["kind"] == "chicane" and previous_section["kind"] == "chicane" and float(section["heading_degrees"]) * float(previous_section["heading_degrees"]) >= 0.0:
						_fail("Chicane pair must alternate its heading")
						return
				previous_section = section
				if section["kind"] == "sweeper" and float(section["hold_length"]) >= 500.0 and float(section["max_heading_degrees"]) >= 25.0:
					held_bend = true
			if not held_bend or not kinds.has("chicane") or not kinds.has("finish"):
				_fail("Missing held sweeper, chicane or finish approach")
				return
			if room == "classic" and seed == 0:
				var grammar: Array[String] = []
				for section: Dictionary in (route["sections"] as Array).slice(0, 10):
					grammar.append("%s length=%.0f heading=%.1f° hold=%.0f" % [section["kind"], section["length"], section["heading_degrees"], section["hold_length"]])
				print("STRIP_ROUTE_GRAMMAR classic seed=0 first_sections: " + "; ".join(grammar))
			var length := _length(line)
			var bounds := Rect2(line[0], Vector2.ZERO)
			for point in line:
				bounds = bounds.expand(point)
			least_width = minf(least_width, bounds.size.x)
			for index in range(2, line.size()):
				var a := line[index - 1] - line[index - 2]
				var b := line[index] - line[index - 1]
				var sine := absf(a.normalized().cross(b.normalized()))
				if sine > 0.001:
					tightest_radius = minf(tightest_radius, minf(a.length(), b.length()) / sine)
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
		if least_width < 1200.0:
			_fail("Section grammar must use the room width")
			return
		summaries.append("%s %.0f/%.0f/%.0f max_heading=%.1f° min_radius=%.0f width_use>=%.0f shaped=%d/20" % [room, minimum, sum / 20.0, maximum, worst_heading, tightest_radius, least_width, generated_count])
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
