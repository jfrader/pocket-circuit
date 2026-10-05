extends SceneTree
## Road-width review renders. For each room and tier, generates the real route,
## fits TrackWidthProfile at flat/subtle/dramatic amplitude and writes one SVG
## per amplitude, then prints the affordable half-width per room and tier.
## PC_OUT=<dir> (default /tmp/opencode/road-width) PC_SEEDS=<count> (default 2)

const WORLD_SCALE := 1.75
const ROOMS: Array[StringName] = [&"classic", &"wide", &"tall", &"long", &"square", &"el"]
const RENDER_TIERS: Array[StringName] = [&"standard", &"long"]
const AFFORD_TIERS: Array[StringName] = [&"compact", &"standard", &"long", &"endurance", &"marathon"]
const AMPLITUDES := {"flat": 0.0, "subtle": 50.0, "dramatic": 115.0}
const SEED_STRIDE := 7919


func _initialize() -> void:
	var out_dir := OS.get_environment("PC_OUT")
	if out_dir.is_empty():
		out_dir = "/tmp/opencode/road-width"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var seeds := int(OS.get_environment("PC_SEEDS")) if OS.get_environment("PC_SEEDS").is_valid_int() else 2
	for tier in RENDER_TIERS:
		for room in ROOMS:
			for k in seeds:
				var seed := (k + 1) * SEED_STRIDE
				var route := _route(room, tier, seed)
				if route["line"].is_empty():
					continue
				for label: String in AMPLITUDES:
					var widths := TrackWidthProfile.build(route["line"], seed, route["room"], AMPLITUDES[label])
					_write_svg("%s/%s_%s_%d_%s.svg" % [out_dir, tier, room, seed, label], route["room"], route["line"], widths)
	print("| Tier | Room | Median affordable half-width | p90 |")
	print("|---|---|---|---|")
	for tier in AFFORD_TIERS:
		for room in ROOMS:
			var medians := []
			var p90s := []
			for k in seeds:
				var route := _route(room, tier, (k + 1) * SEED_STRIDE)
				if route["line"].is_empty():
					continue
				var line: PackedVector2Array = route["line"]
				var caps := Array(TrackWidthProfile.affordable_caps(line, route["room"], TrackWidthProfile._closed_arc(line)))
				caps.sort()
				medians.append(caps[int(caps.size() * 0.5)])
				p90s.append(caps[int(caps.size() * 0.9)])
			print("| %s | %s | %.0f | %.0f |" % [tier, room, _mean(medians), _mean(p90s)])
	print("ROAD_WIDTH_RENDERS PASS dir=%s" % out_dir)
	quit()


func _route(room: StringName, tier: StringName, seed: int) -> Dictionary:
	var scale := float(TrackSeedGen.length_profile(tier).get("room_scale", 1.0))
	var polygon := PackedVector2Array()
	for point: Vector2 in TrackBuilderCore.ROOM_SHAPES[room]:
		polygon.append(point * scale)
	var params := {
		"margin": 190.0, "min_self_distance": 320.0, "min_loop_length": 1900.0 * WORLD_SCALE,
		"room_polygon": polygon, "room_shape": room, "length_tier": tier,
	}
	var gen := TrackSeedGen.generate_with_retries(seed, Rect2(-940, -540, 1880, 1080), params)
	var points: PackedVector2Array = gen["points"]
	var line := TrackBuilderGeometry.sample_centerline(points) if not points.is_empty() else PackedVector2Array()
	return {"room": polygon, "line": line}


func _write_svg(path: String, room: PackedVector2Array, line: PackedVector2Array, widths: PackedFloat32Array) -> void:
	var bounds := Rect2(room[0], Vector2.ZERO)
	for point: Vector2 in room:
		bounds = bounds.expand(point)
	var edges := TrackBuilderGeometry.corridor_edges(line, widths)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%f %f %f %f">\n' % [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y])
	file.store_string('<polygon points="%s" fill="#efe7d6" stroke="#b9ad96" stroke-width="12"/>\n' % _points(room))
	file.store_string('<path d="M %s Z M %s Z" fill="#4a4640" fill-rule="evenodd"/>\n' % [_points(edges["left"]), _points(edges["right"])])
	file.store_string('<polygon points="%s" fill="none" stroke="#c4552b" stroke-width="6"/>\n' % _points(line))
	file.store_string("</svg>\n")


func _points(points: PackedVector2Array) -> String:
	var parts := PackedStringArray()
	for point: Vector2 in points:
		parts.append("%.1f,%.1f" % [point.x, point.y])
	return " ".join(parts)


func _mean(values: Array) -> float:
	var total := 0.0
	for value: float in values:
		total += value
	return total / maxf(1.0, values.size())
