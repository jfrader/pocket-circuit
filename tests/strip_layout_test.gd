extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const IDENTITY := preload("res://scripts/race/generated_circuit_identity.gd")
const PREVIEW := preload("res://scripts/race/circuit_route_preview.gd")


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
	for key in ["spec", "centerline", "edges", "room_polygon", "theme", "room_shape", "seed", "strip_gates", "strip_grid", "strip_caps", "racing_line", "traffic_plan", "strip_half_width", "strip_length"]:
		if not first.has(key):
			_fail("Missing layout key " + key)
			return
	var gates: Array = first["strip_gates"]
	if gates.size() < 3 or gates[0]["index"] != 0 or not gates[-1]["is_finish_line"] or gates[0]["arc"] >= gates[1]["arc"]:
		_fail("Ordered strip gates")
		return
	if float(first["strip_length"]) < 10000.0 or gates.size() < 10:
		_fail("Strip length or distributed gates")
		return
	var grid: Dictionary = first["strip_grid"]
	if (grid["player"] as Transform2D).origin.distance_to((grid["chaser"] as Transform2D).origin) < 90.0:
		_fail("Unsafe starting grid")
		return
	for traffic: Dictionary in first["traffic_plan"]:
		if absf(float(traffic["lane"])) > 0.5 or float(traffic["arc"]) >= float(gates[-1]["arc"]) or not traffic["behavior"] in [&"cruiser", &"cutter", &"line"]:
			_fail("Unsafe traffic plan")
			return
	if (first["traffic_plan"] as Array).size() < 4 or (first["traffic_plan"] as Array).size() > 6:
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
			if length < 7500.0 or length > 26000.0:
				_fail("Length outside drivable sprint budget: %s %.0f" % [tier, length])
				return
		lengths.append("%s %.0f/%.0f/%.0f" % [tier, minimum, sum / 3.0, maximum])
	print("STRIP_LAYOUT_TEST PASS gates=%d traffic=%d tier min/avg/max: %s" % [gates.size(), (first["traffic_plan"] as Array).size(), "; ".join(lengths)])
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
