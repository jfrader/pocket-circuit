extends SceneTree

const PROFILE := preload("res://scripts/race/track_width_profile.gd")
const GEOM := preload("res://scripts/race/track_builder_geometry.gd")

const WORLD_SCALE := 1.75
const ROOMS: Array[StringName] = [&"classic", &"wide", &"tall", &"long", &"square", &"el"]
const SEEDS := [7919, 15838, 23757]
const DRAMATIC := 115.0
const TOL := 0.5
## Sampled edges measured against a sampled centerline lose a little to chord
## sag on curves (35-unit samples); a flat 125 road reads the same.
const CHORD_TOL := 3.0
## Width changes are occasional features: most of every lap keeps today's road.
const SPORADIC_BASE_SHARE := 0.55


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var checked := 0
	var pinched := 0
	var widest := PROFILE.BASE_HALF_WIDTH
	var narrowest := PROFILE.BASE_HALF_WIDTH
	var lowest_base_share := 1.0
	for tier: StringName in [&"standard", &"long"]:
		for room in ROOMS:
			for seed: int in SEEDS:
				var route := _route(room, tier, seed)
				var line: PackedVector2Array = route["line"]
				var polygon: PackedVector2Array = route["room"]
				if not _expect(line.size() >= 260, "%s/%s/%d should generate a route" % [tier, room, seed]):
					return
				var flat := PROFILE.build(line, seed, polygon, 0.0)
				for value: float in flat:
					if not _expect(is_equal_approx(value, PROFILE.BASE_HALF_WIDTH), "flat amplitude must keep today's half-width"):
						return
				var widths := PROFILE.build(line, seed, polygon, DRAMATIC)
				if not _expect(widths == PROFILE.build(line, seed, polygon, DRAMATIC), "%s/%s/%d width must be deterministic" % [tier, room, seed]):
					return
				if not _check_limits(line, polygon, widths, "%s/%s/%d" % [tier, room, seed]):
					return
				if not _check_setup_straight(line, widths, "%s/%s/%d" % [tier, room, seed]):
					return
				var base_share := _base_share(widths)
				if not _expect(base_share >= SPORADIC_BASE_SHARE, "%s/%s/%d only %.0f%% of the lap keeps today's width" % [tier, room, seed, base_share * 100.0]):
					return
				lowest_base_share = minf(lowest_base_share, base_share)
				widest = maxf(widest, PROFILE.widest(widths))
				for value: float in widths:
					narrowest = minf(narrowest, value)
				pinched += 1 if _has_pinch(widths) else 0
				checked += 1
	if not _expect(widest > PROFILE.BASE_HALF_WIDTH + 40.0, "dramatic amplitude should visibly widen some road (widest %.0f)" % widest):
		return
	if not _expect(narrowest < PROFILE.BASE_HALF_WIDTH - 15.0 and pinched * 2 >= checked, "dramatic amplitude should pinch most routes somewhere (%d/%d, narrowest %.0f)" % [pinched, checked, narrowest]):
		return
	var flat_seeds := 0
	for seed in 400:
		flat_seeds += 1 if PROFILE.amplitude_for_seed(seed) == 0.0 else 0
	if not _expect(flat_seeds > 60 and flat_seeds < 140, "about a quarter of seeds should stay flat (%d/400)" % flat_seeds):
		return
	if not _expect(PROFILE.amplitude_for_option(PROFILE.MODE_FLAT, 5) == 0.0 and PROFILE.amplitude_for_option(null, 5) == 0.0, "flat is the default road width"):
		return
	print("TRACK_WIDTH_PROFILE_TEST PASS routes=%d widest=%.0f narrowest=%.0f pinched=%d lowest_base_share=%.0f%% flat_seeds=%d/400" % [checked, widest, narrowest, pinched, lowest_base_share * 100.0, flat_seeds])
	quit(0)


func _base_share(widths: PackedFloat32Array) -> float:
	var base := 0
	for value: float in widths:
		base += 1 if absf(value - PROFILE.BASE_HALF_WIDTH) < 0.5 else 0
	return float(base) / float(widths.size())


## The setup straight keeps today's width: nothing may widen within the finish
## clear zone, so the gate, grid and finish landmarks do not move with the
## amplitude, while pinches may still narrow it like today's geometry.
func _check_setup_straight(line: PackedVector2Array, widths: PackedFloat32Array, label: String) -> bool:
	var arc := PackedFloat32Array([0.0])
	var total := 0.0
	for i in line.size():
		total += line[i].distance_to(line[(i + 1) % line.size()])
		arc.append(total)
	for i in line.size():
		var center := minf(arc[i], total - arc[i])
		if center < PROFILE.FINISH_CLEAR_ARC and widths[i] > PROFILE.BASE_HALF_WIDTH + 0.5:
			return _expect(false, "%s widened the setup straight at sample %d (%.1f vs base %.1f)" % [label, i, widths[i], PROFILE.BASE_HALF_WIDTH])
	return true


func _has_pinch(widths: PackedFloat32Array) -> bool:
	for value: float in widths:
		if value < PROFILE.BASE_HALF_WIDTH - 10.0:
			return true
	return false


func _check_limits(line: PackedVector2Array, polygon: PackedVector2Array, widths: PackedFloat32Array, label: String) -> bool:
	var n := line.size()
	var arc := PROFILE._closed_arc(line)
	var total: float = arc[n]
	for i in n:
		var w := widths[i]
		if not _expect(w >= PROFILE.NARROW_HALF_WIDTH - TOL and w <= PROFILE.MAX_HALF_WIDTH + TOL, "%s half-width %.1f outside [100, 240]" % [label, w]):
			return false
		if w < PROFILE.BASE_HALF_WIDTH - TOL:
			if not _expect(minf(arc[i], total - arc[i]) >= PROFILE.FINISH_CLEAR_ARC - TOL, "%s pinch at sample %d reaches the start/finish straight" % [label, i]):
				return false
			continue
		if w <= PROFILE.BASE_HALF_WIDTH + TOL:
			continue
		if not _expect(w <= PROFILE._local_radius(line, i) - maxf(PROFILE.HULL_RADIUS, PROFILE.MIN_INNER_EDGE_RADIUS) + TOL, "%s widened sample %d pinches its turn" % [label, i]):
			return false
		if not _expect(PROFILE._distance_to_polygon(line[i], polygon) >= w + PROFILE.WALL_GUARD - TOL, "%s widened sample %d crosses the room wall" % [label, i]):
			return false
		for j in n:
			var along := absf(arc[i] - arc[j])
			if minf(along, total - along) < PROFILE.NONLOCAL_ARC:
				continue
			var gap := line[i].distance_to(line[j]) - w - widths[j]
			if not _expect(gap >= PROFILE.LEG_GAP - TOL, "%s samples %d/%d merge (gap %.1f)" % [label, i, j, gap]):
				return false
	# The inner edge must never come closer to the centerline than today's flat
	# edge at the same sample, less any intended pinch; closer means it folded.
	var inner := PROFILE._inner_edge(line, widths)
	var flat_inner := PROFILE._inner_edge(line, PROFILE.flat(n))
	for i in n:
		var fitted := _distance_to_line(inner[i], line)
		var flat := _distance_to_line(flat_inner[i], line)
		var pinch := maxf(0.0, PROFILE.BASE_HALF_WIDTH - widths[i])
		if not _expect(fitted >= flat - pinch - CHORD_TOL, "%s inner road edge folds at sample %d (%.1f vs flat %.1f)" % [label, i, fitted, flat]):
			return false
	var flat_island := absf(GEOM.polygon_area(PROFILE._inner_edge(line, PROFILE.flat(n))))
	var island := absf(GEOM.polygon_area(PROFILE._inner_edge(line, widths)))
	return _expect(island >= flat_island * PROFILE.ISLAND_KEEP - TOL, "%s island shrank to %.0f%% of flat" % [label, 100.0 * island / flat_island])


func _distance_to_line(point: Vector2, line: PackedVector2Array) -> float:
	var best := INF
	for k in line.size():
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, line[k], line[(k + 1) % line.size()])))
	return best


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
	return {"room": polygon, "line": GEOM.sample_centerline(points) if not points.is_empty() else PackedVector2Array()}


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_WIDTH_PROFILE_TEST FAIL: " + message)
	quit(1)
	return false
