extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const RACING := preload("res://scripts/race/track_builder_racing.gd")
const SEEDGEN := preload("res://scripts/race/track_seed_gen.gd")

# The four real vehicle resources: the guidance floor must cover the widest
# kinematic minimum turn radius (wheelbase / tan(max_steer_angle)).
const VEHICLE_RESOURCES := [
	"res://data/vehicles/rustbug.tres",
	"res://data/vehicles/scrapjaw.tres",
	"res://data/vehicles/pinbolt.tres",
	"res://data/vehicles/flicker.tres",
]

# The known fold case plus representative tiers (standard / long / endurance).
const CASES := [
	{"theme": &"office", "room": &"square", "seed": 41580, "tier": &"standard"},
	{"theme": &"workshop", "room": &"square", "seed": 51940, "tier": &"standard"},
	{"theme": &"kitchen", "room": &"classic", "seed": 70171, "tier": &"standard"},
	{"theme": &"kitchen", "room": &"classic", "seed": 80305, "tier": &"standard"},
	{"theme": &"kitchen", "room": &"long", "seed": 73217, "tier": &"standard"},
	{"theme": &"kitchen", "room": &"long", "seed": 24469, "tier": &"standard"},
	{"theme": &"kitchen", "room": &"wide", "seed": 0, "tier": &"endurance"},
]

# Derivative tolerance: the reconstructed offset is exact to float precision and
# the bound sweeps converge, so a tiny epsilon absorbs dot-product round-off.
const OFFSET_RATE_TOL := 0.02


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var worst_kinematic := 0.0
	for path: String in VEHICLE_RESOURCES:
		var stats: Resource = load(path) as Resource
		if stats == null or not ("wheelbase" in stats) or not ("max_steer_angle_deg" in stats):
			push_error("RACING_LINE_CONTINUITY_TEST FAIL: could not read vehicle resource %s" % path)
			quit(1)
			return
		var wheelbase := float(stats.get("wheelbase"))
		var steer := deg_to_rad(float(stats.get("max_steer_angle_deg")))
		worst_kinematic = maxf(worst_kinematic, wheelbase / maxf(tan(steer), 0.001))
	var floor := float(RACING.GUIDANCE_RADIUS_FLOOR)
	if not _expect(floor > worst_kinematic, "guidance floor %.1f must exceed the widest chassis kinematic radius %.1f" % [floor, worst_kinematic]):
		return
	for case: Dictionary in CASES:
		var options := {"length_tier": StringName(case["tier"])}
		var prepared := BUILDER.prepare_layout(case["theme"], case["room"], int(case["seed"]), options)
		if prepared.is_empty():
			push_error("RACING_LINE_CONTINUITY_TEST FAIL: could not prepare %s/%s/%d" % [case["theme"], case["room"], case["seed"]])
			quit(1)
			return
		var centerline: PackedVector2Array = prepared["centerline"]
		var gate_samples := BUILDER._layout_gate_samples(centerline, prepared["spec"])
		var moments := BUILDER._analyze_track_moments(centerline, gate_samples)
		var safe_line := BUILDER._racing_line_points(centerline, moments, false)
		var shortcut_line := BUILDER._racing_line_points(centerline, moments, true)
		if int(moments.get("shortcut", -1)) >= 0:
			if not _expect(not _arrays_equal(safe_line, shortcut_line), "%s/%s/%d safe and shortcut should be distinct where a shortcut exists" % [case["theme"], case["room"], case["seed"]]):
				return
		for line: Dictionary in [
			{"name": "%s/%s/%d safe" % [case["theme"], case["room"], case["seed"]], "points": safe_line},
			{"name": "%s/%s/%d shortcut" % [case["theme"], case["room"], case["seed"]], "points": shortcut_line},
		]:
			if not _check_line(String(line["name"]), centerline, line["points"]):
				return
	print("RACING_LINE_CONTINUITY_TEST PASS")
	quit(0)


func _arrays_equal(first: PackedVector2Array, second: PackedVector2Array) -> bool:
	if first.size() != second.size():
		return false
	for index in first.size():
		if not first[index].is_equal_approx(second[index]):
			return false
	return true


func _check_line(name: String, centerline: PackedVector2Array, line: PackedVector2Array) -> bool:
	var count := line.size()
	if count != centerline.size():
		push_error("RACING_LINE_CONTINUITY_TEST FAIL: %s point count %d != centerline %d" % [name, count, centerline.size()])
		quit(1)
		return false
	# The FINAL signed lateral offset derivative must respect the arc-rate rule,
	# including the wrap edge. This is the primary invariant: it catches a
	# shortcut/safe lane override that reintroduces a steep offset change after
	# the apex line was already bounded.
	var offsets := _signed_offsets(centerline, line)
	var rate := float(RACING.APEX_OFFSET_RATE_LIMIT)
	for index in count:
		var previous_index := (index - 1 + count) % count
		var arc := centerline[previous_index].distance_to(centerline[index])
		var derivative := absf(offsets[index] - offsets[previous_index]) / maxf(arc, 0.001)
		if derivative > rate + OFFSET_RATE_TOL:
			push_error("RACING_LINE_CONTINUITY_TEST FAIL: %s offset derivative %.3f exceeds rate %.3f at sample %d (arc %.1f)" % [name, derivative, rate, index, arc])
			quit(1)
			return false
		# The racing line must stay inside the legal ribbon.
		if BUILDER._distance_to_centerline(line[index], centerline) > BUILDER.HALF_WIDTH:
			push_error("RACING_LINE_CONTINUITY_TEST FAIL: %s point (%d) leaves the legal ribbon" % [name, index])
			quit(1)
			return false
	# Sanity: no sharp direction reversal (a fold doubles back on itself).
	for index in count:
		var prev := line[(index - 1 + count) % count]
		var here := line[index]
		var next := line[(index + 1) % count]
		var back := (here - prev)
		var fwd := (next - here)
		if back.length() > 0.001 and fwd.length() > 0.001 and back.normalized().dot(fwd.normalized()) < -0.5:
			push_error("RACING_LINE_CONTINUITY_TEST FAIL: %s direction reversal at sample %d" % [name, index])
			quit(1)
			return false
	if _has_self_intersection(line):
		push_error("RACING_LINE_CONTINUITY_TEST FAIL: %s self-intersects (fold)" % name)
		quit(1)
		return false
	# Final guidance radius: the realized line must never dip below the configured
	# floor (which the guard enforces by amplitude bisection). The floor is a
	# physical bound derived from the real chassis, not a post-hoc separator.
	for index in count:
		var radius := _line_radius(line, index)
		if radius < float(RACING.GUIDANCE_RADIUS_FLOOR) - 1.0:
			push_error("RACING_LINE_CONTINUITY_TEST FAIL: %s radius %.1f below guidance floor %.1f at sample %d" % [name, radius, float(RACING.GUIDANCE_RADIUS_FLOOR), index])
			quit(1)
			return false
	return true


func _line_radius(line: PackedVector2Array, index: int) -> float:
	var count := line.size()
	var span := 3
	var a := line[(index - span + count) % count]
	var b := line[index]
	var c := line[(index + span) % count]
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ac := a.distance_to(c)
	if ab < 0.001 or bc < 0.001 or ac < 0.001:
		return INF
	var cross := absf((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))
	if cross < 0.001:
		return INF
	return ab * bc * ac / (2.0 * cross)


func _signed_offsets(centerline: PackedVector2Array, line: PackedVector2Array) -> PackedFloat32Array:
	var count := line.size()
	var offsets := PackedFloat32Array()
	offsets.resize(count)
	for index in count:
		var tangent := (centerline[(index + 1) % count] - centerline[(index - 1 + count) % count]).normalized()
		var normal := tangent.rotated(PI * 0.5)
		offsets[index] = (line[index] - centerline[index]).dot(normal)
	return offsets


func _has_self_intersection(points: PackedVector2Array) -> bool:
	var count := points.size()
	for first in count:
		var first_next := (first + 1) % count
		for second in range(first + 1, count):
			var second_next := (second + 1) % count
			if first_next == second or second_next == first:
				continue
			if Geometry2D.segment_intersects_segment(points[first], points[first_next], points[second], points[second_next]) != null:
				return true
	return false


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("RACING_LINE_CONTINUITY_TEST FAIL: " + message)
	quit(1)
	return false
