extends SceneTree

const ROUTE := preload("res://scripts/race/strip_route.gd")
const CATALOG := preload("res://scripts/race/track_builder_catalog.gd")
const MIN_STANDARD_LENGTH := 7500.0


func _initialize() -> void:
	var summaries: Array[String] = []
	for room: String in ["classic", "wide", "tall", "el", "long", "square"]:
		var polygon: PackedVector2Array = CATALOG.ROOM_SHAPES[StringName(room)]
		var generated_count := 0
		var minimum := INF
		var maximum := 0.0
		var sum := 0.0
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
			if length < MIN_STANDARD_LENGTH:
				_fail("Short strip %.0f in %s seed %d" % [length, room, seed])
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
		if generated_count == 0:
			_fail("No shaped candidates in " + room)
			return
		summaries.append("%s %.0f/%.0f/%.0f shaped=%d/20" % [room, minimum, sum / 20.0, maximum, generated_count])
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
