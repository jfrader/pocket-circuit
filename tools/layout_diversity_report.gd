extends SceneTree

const TRACK_SEED_GEN = preload("res://scripts/race/track_seed_gen.gd")
const ROOM_RECT = Rect2(-940.0, -540.0, 1880.0, 1080.0)
const WORLD_SCALE = 1.75
var ROOM_SHAPES := {
	"classic": PackedVector2Array([Vector2(-875, -575) * WORLD_SCALE, Vector2(875, -575) * WORLD_SCALE, Vector2(875, 575) * WORLD_SCALE, Vector2(-875, 575) * WORLD_SCALE]),
	"wide": PackedVector2Array([Vector2(-1175, -600) * WORLD_SCALE, Vector2(1175, -600) * WORLD_SCALE, Vector2(1175, 600) * WORLD_SCALE, Vector2(-1175, 600) * WORLD_SCALE]),
	"tall": PackedVector2Array([Vector2(-575, -725) * WORLD_SCALE, Vector2(575, -725) * WORLD_SCALE, Vector2(575, 725) * WORLD_SCALE, Vector2(-575, 725) * WORLD_SCALE]),
	"el": PackedVector2Array([Vector2(-1200, -700) * WORLD_SCALE, Vector2(360, -700) * WORLD_SCALE, Vector2(360, -60) * WORLD_SCALE, Vector2(1200, -60) * WORLD_SCALE, Vector2(1200, 700) * WORLD_SCALE, Vector2(-1200, 700) * WORLD_SCALE]),
	"long": PackedVector2Array([Vector2(-1300, -550) * WORLD_SCALE, Vector2(1300, -550) * WORLD_SCALE, Vector2(1300, 550) * WORLD_SCALE, Vector2(-1300, 550) * WORLD_SCALE]),
	"square": PackedVector2Array([Vector2(-750, -750) * WORLD_SCALE, Vector2(750, -750) * WORLD_SCALE, Vector2(750, 750) * WORLD_SCALE, Vector2(-750, 750) * WORLD_SCALE]),
}

const LENGTH_TIERS = ["compact", "standard", "long", "endurance", "marathon"]
const SEED_COUNT = 10

func _initialize():
	call_deferred("_run_report")

func _room_params(room_name: String, tier: String) -> Dictionary:
	var params := {
		"margin": 190.0,
		"min_self_distance": 320.0,
		"min_loop_length": 1900.0 * WORLD_SCALE,
		"room_polygon": ROOM_SHAPES[room_name],
		"room_shape": StringName(room_name),
		"length_tier": tier,
	}
	match room_name:
		"el":
			params["min_loop_length"] = 1500.0 * WORLD_SCALE
		"long":
			params["min_loop_length"] = 2000.0 * WORLD_SCALE
		"square":
			params["min_loop_length"] = 2200.0 * WORLD_SCALE
	return params

func _polygon_area(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in points.size():
		var next := (index + 1) % points.size()
		total += points[index].x * points[next].y - points[next].x * points[index].y
	return total * 0.5

func _silhouette_features(controls: PackedVector2Array) -> Dictionary:
	var points: PackedVector2Array = TRACK_SEED_GEN.centerline_checkpoints(controls)
	var bounds := Rect2(points[0], Vector2.ZERO)
	var center := Vector2.ZERO
	for point: Vector2 in points:
		bounds = bounds.expand(point)
		center += point
	center /= float(points.size())
	var hull := Geometry2D.convex_hull(points)
	var hull_area := absf(_polygon_area(hull))
	var area := absf(_polygon_area(points))
	var center_band_min := INF
	var center_band_max := -INF
	var top_min := INF
	var top_max := -INF
	var bottom_min := INF
	var bottom_max := -INF
	var top_x := 0.0
	var top_count := 0
	var bottom_x := 0.0
	var bottom_count := 0
	var upper_mid_min := INF
	var upper_mid_max := -INF
	var lower_mid_min := INF
	var lower_mid_max := -INF
	var minimum_radius := INF
	var maximum_radius := 0.0
	for point: Vector2 in points:
		if absf(point.x - center.x) < bounds.size.x * 0.12:
			center_band_min = minf(center_band_min, point.y)
			center_band_max = maxf(center_band_max, point.y)
		if point.y < bounds.position.y + bounds.size.y * 0.22:
			top_min = minf(top_min, point.x)
			top_max = maxf(top_max, point.x)
			top_x += point.x
			top_count += 1
		if point.y > bounds.end.y - bounds.size.y * 0.22:
			bottom_min = minf(bottom_min, point.x)
			bottom_max = maxf(bottom_max, point.x)
			bottom_x += point.x
			bottom_count += 1
		var y_fraction := (point.y - bounds.position.y) / maxf(bounds.size.y, 1.0)
		if y_fraction > 0.28 and y_fraction < 0.48:
			upper_mid_min = minf(upper_mid_min, point.x)
			upper_mid_max = maxf(upper_mid_max, point.x)
		if y_fraction > 0.52 and y_fraction < 0.72:
			lower_mid_min = minf(lower_mid_min, point.x)
			lower_mid_max = maxf(lower_mid_max, point.x)
		var radius := point.distance_to(center)
		minimum_radius = minf(minimum_radius, radius)
		maximum_radius = maxf(maximum_radius, radius)
	var top_span := top_max - top_min
	var bottom_span := bottom_max - bottom_min
	var mirror_error := 0.0
	var sample_step = maxi(1, points.size() / 50)
	var sample_count = 0
	for i in range(0, points.size(), sample_step):
		var point = points[i]
		var reflected := Vector2(point.x, bounds.get_center().y * 2.0 - point.y)
		var nearest := INF
		for j in range(0, points.size(), sample_step):
			var other = points[j]
			nearest = minf(nearest, reflected.distance_to(other))
		mirror_error += nearest
		sample_count += 1
	mirror_error /= float(sample_count) * maxf(bounds.size.length(), 1.0)
	
	return {
		"aspect": snappedf(bounds.size.x / maxf(bounds.size.y, 1.0), 0.01),
		"concavity": snappedf(1.0 - area / maxf(hull_area, 1.0), 0.01),
		"waist": snappedf((center_band_max - center_band_min) / maxf(bounds.size.y, 1.0), 0.01),
		"alternation": snappedf(absf(top_x / maxf(float(top_count), 1.0) - bottom_x / maxf(float(bottom_count), 1.0)) / maxf(bounds.size.x, 1.0), 0.01),
		"mid_shift": snappedf(absf((upper_mid_min + upper_mid_max) * 0.5 - (lower_mid_min + lower_mid_max) * 0.5) / maxf(bounds.size.x, 1.0), 0.01),
		"triangle_taper": snappedf(minf(top_span, bottom_span) / maxf(maxf(top_span, bottom_span), 1.0), 0.01),
		"radial_min": snappedf(minimum_radius / maxf(maximum_radius, 1.0), 0.01),
		"centroid_offset": snappedf(center.distance_to(bounds.get_center()) / maxf(bounds.size.length(), 1.0), 0.01),
		"mirror_error": snappedf(mirror_error, 0.001),
	}

func _feature_distance(first: Dictionary, second: Dictionary) -> float:
	var keys := ["concavity", "waist", "triangle_taper", "radial_min", "mirror_error", "alternation"]
	var weights := [1.0, 1.0, 1.0, 1.0, 5.0, 3.0]
	var squared := 0.0
	for index in keys.size():
		var delta := (float(first[keys[index]]) - float(second[keys[index]])) * float(weights[index])
		squared += delta * delta
	return sqrt(squared)

func _run_report():
	print("--- Layout Diversity Report ---")
	var generated_tracks = []
	var total_requests = 0
	var fallbacks = 0
	var genuine_sequences = {}
	var raw_sequences = {}
	for room_name in ROOM_SHAPES.keys():
		for tier in LENGTH_TIERS:
			var params = _room_params(String(room_name), String(tier))
			print("Generating ", room_name, " ", tier, " ...")
			for seed in SEED_COUNT:
				total_requests += 1
				var result = TRACK_SEED_GEN.generate_with_retries(seed, ROOM_RECT, params)
				if result.get("points", []).is_empty():
					continue
				
				if result.get("fallback", false):
					fallbacks += 1
					
				var controls = result["points"]
				var features = _silhouette_features(controls)
				var canonical_seq = result["route_sequence"]
				var raw_seq = ".".join(TRACK_SEED_GEN._raw_turn_tokens(controls))
				var corner_profiles = result.get("corner_profiles", {})
				var changing_radius = corner_profiles.get("tightening", 0) + corner_profiles.get("opening", 0)
				
				genuine_sequences[canonical_seq] = genuine_sequences.get(canonical_seq, 0) + 1
				raw_sequences[raw_seq] = raw_sequences.get(raw_seq, 0) + 1
				
				generated_tracks.append({
					"id": "%s_%s_%d" % [room_name, tier, seed],
					"features": features,
					"canonical_seq": canonical_seq,
					"raw_seq": raw_seq,
					"changing_radius": changing_radius,
					"points": controls
				})
				
	# Pairwise similarity
	var distances = []
	var visited = {}
	var clusters = []
	var threshold = 0.1 # Distance threshold for near-duplicates
	for i in generated_tracks.size():
		for j in range(i + 1, generated_tracks.size()):
			var dist = _feature_distance(generated_tracks[i]["features"], generated_tracks[j]["features"])
			distances.append(dist)
			
	for i in generated_tracks.size():
		if visited.has(i):
			continue
		var dup_cluster = [generated_tracks[i]["id"]]
		for j in range(i + 1, generated_tracks.size()):
			if visited.has(j):
				continue
			if _feature_distance(generated_tracks[i]["features"], generated_tracks[j]["features"]) < threshold:
				dup_cluster.append(generated_tracks[j]["id"])
				visited[j] = true
		if dup_cluster.size() > 1:
			clusters.append(dup_cluster)
			visited[i] = true

	distances.sort()
	var p25 = distances[distances.size() / 4] if distances.size() > 0 else 0
	var median = distances[distances.size() / 2] if distances.size() > 0 else 0
	var p75 = distances[distances.size() * 3 / 4] if distances.size() > 0 else 0
	
	print("Fallback Rate: %.1f%% (%d / %d)" % [float(fallbacks) / float(total_requests) * 100.0, fallbacks, total_requests])
	print("Genuine Sequences: %d (vs %d raw sequences, %.1f%% of raw variation is pure rotation/mirroring)" % [genuine_sequences.size(), raw_sequences.size(), (1.0 - float(genuine_sequences.size()) / maxf(float(raw_sequences.size()), 1.0)) * 100.0])
	
	print("Similarity Distribution:")
	print("  p25: %.3f" % p25)
	print("  Median: %.3f" % median)
	print("  p75: %.3f" % p75)
	
	print("Near-duplicate clusters (dist < %.1f):" % threshold)
	clusters.sort_custom(func(a, b): return a.size() > b.size())
	for i in mini(5, clusters.size()):
		var display_cluster = clusters[i]
		if display_cluster.size() > 8:
			display_cluster = display_cluster.slice(0, 8)
			display_cluster.append("... (%d total)" % clusters[i].size())
		print("  - %s" % str(display_cluster))
		
	if generated_tracks.size() > 0:
		# Pick a sample track to print signature
		var sample = generated_tracks[0]
		var tokens = TRACK_SEED_GEN._raw_turn_tokens(sample["points"])
		var turns = 0
		for t in tokens:
			if t.begins_with("L") or t.begins_with("R"):
				turns += 1
		var metrics = TRACK_SEED_GEN.gameplay_metrics(sample["points"])
		print("\nSample Track Signature (%s):" % sample["id"])
		print("  Turn Count: %d" % turns)
		print("  Sequence: %s" % sample["raw_seq"])
		print("  Setup Straights: %d" % metrics.get("setup_straight_count", 0))
		print("  Literal Straights: %d" % metrics.get("literal_straight_count", 0))
		print("  Changing-radius bends: %d" % sample["changing_radius"])
	
	quit(0)
