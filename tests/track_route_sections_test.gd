extends SceneTree

const SECTIONS := preload("res://scripts/race/track_route_sections.gd")
const GRAMMAR := preload("res://scripts/race/track_route_grammar.gd")
const SEED_GEN := preload("res://scripts/race/track_seed_gen.gd")

const ROOM_RECT := Rect2(-940.0, -540.0, 1880.0, 1080.0)
const TOL := 0.5
const RADIUS_TOL := 1.0


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not _test_corner_profile_geometry():
		return
	if not _test_corner_profile_rejection_and_cap():
		return
	if not _test_straight_motif_pose():
		return
	if not _test_straight_motif_rejection():
		return
	if not _test_profile_wiring():
		return
	if not _test_seed_gen_metadata():
		return
	print("TRACK_ROUTE_SECTIONS_TEST PASS")
	quit(0)


func _test_corner_profile_geometry() -> bool:
	# A 90-degree corner: incoming along +X, outgoing along +Y (left turn).
	var corner := Vector2.ZERO
	var incoming := Vector2.RIGHT
	var outgoing := Vector2.DOWN
	var profile := SECTIONS.corner_profile(corner, incoming, outgoing, 220.0, 180.0, 0.5, 500.0, 500.0)
	if not _expect(bool(profile["accepted"]), "distinct radii profile should be accepted"):
		return false
	var entry: Vector2 = profile["entry"]
	var exit: Vector2 = profile["exit"]
	var join: Vector2 = profile["join"]
	var center1: Vector2 = profile["center1"]
	var center2: Vector2 = profile["center2"]
	var r1: float = profile["r1"]
	var r2: float = profile["r2"]
	if not _expect(absf(r1 - 220.0) < RADIUS_TOL and absf(r2 - 180.0) < RADIUS_TOL, "profile should retain entry/exit radii (r1=%.1f r2=%.1f)" % [r1, r2]):
		return false
	# Actual circle radii: every arc point must sit at its declared radius.
	if not _expect(absf(entry.distance_to(center1) - r1) < RADIUS_TOL, "entry radius mismatch"):
		return false
	if not _expect(absf(join.distance_to(center1) - r1) < RADIUS_TOL, "join radius mismatch on arc1"):
		return false
	if not _expect(absf(join.distance_to(center2) - r2) < RADIUS_TOL, "join radius mismatch on arc2"):
		return false
	if not _expect(absf(exit.distance_to(center2) - r2) < RADIUS_TOL, "exit radius mismatch"):
		return false
	if not _expect(String(profile["kind"]) == "tightening", "r2 < r1 should read as tightening (got %s)" % profile["kind"]):
		return false
	# Entry/exit tangents and poses.
	var sign := signf(float(profile["turn"]))
	if not _expect(_arc_tangent(center1, entry, sign).dot(incoming) > 0.999, "entry tangent should match incoming"):
		return false
	if not _expect(_arc_tangent(center2, exit, sign).dot(outgoing) > 0.999, "exit tangent should match outgoing"):
		return false
	if not _expect(entry.distance_to(corner - incoming * float(profile["d_in"])) < TOL, "entry should sit d_in back along incoming"):
		return false
	if not _expect(exit.distance_to(corner + outgoing * float(profile["d_out"])) < TOL, "exit should sit d_out ahead along outgoing"):
		return false
	# Joint G1: both arcs share the same tangent at the join point.
	var midheading := incoming.rotated(float(profile["phi"]))
	var join_tangent1 := _arc_tangent(center1, join, sign)
	var join_tangent2 := _arc_tangent(center2, join, sign)
	if not _expect(join_tangent1.dot(midheading) > 0.999, "arc1 join tangent should match midheading"):
		return false
	if not _expect(join_tangent2.dot(midheading) > 0.999, "arc2 join tangent should match midheading"):
		return false
	if not _expect(join_tangent1.dot(join_tangent2) > 0.999, "joint must be G1 continuous"):
		return false
	# Determinism.
	var again := SECTIONS.corner_profile(corner, incoming, outgoing, 220.0, 180.0, 0.5, 500.0, 500.0)
	if not _expect(again["entry"] == entry and again["exit"] == exit and again["join"] == join, "profile must be deterministic"):
		return false
	# Opening (r2 > r1) should read opening, symmetric radii should read symmetric.
	var opening := SECTIONS.corner_profile(corner, incoming, outgoing, 180.0, 220.0, 0.5, 500.0, 500.0)
	if not _expect(bool(opening["accepted"]) and String(opening["kind"]) == "opening", "r2 > r1 should read as opening"):
		return false
	var symmetric := SECTIONS.corner_profile(corner, incoming, outgoing, 180.0, 180.0, 0.5, 500.0, 500.0)
	if not _expect(bool(symmetric["accepted"]) and String(symmetric["kind"]) == "symmetric", "equal radii should read as symmetric"):
		return false
	return true


func _test_corner_profile_rejection_and_cap() -> bool:
	var corner := Vector2.ZERO
	var incoming := Vector2.RIGHT
	var outgoing := Vector2.DOWN
	# Degenerate (parallel) legs must be rejected.
	var degenerate := SECTIONS.corner_profile(corner, incoming, incoming, 200.0, 160.0, 0.5, 500.0, 500.0)
	if not _expect(not bool(degenerate["accepted"]), "parallel legs must be rejected"):
		return false
	# Setbacks must be capped to the available adjacent legs (no neighbor overlap).
	var capped := SECTIONS.corner_profile(corner, incoming, outgoing, 300.0, 300.0, 0.5, 250.0, 250.0)
	if not _expect(bool(capped["accepted"]), "cap-to-leg profile should still be accepted"):
		return false
	if not _expect(float(capped["d_in"]) <= 250.0 + TOL and float(capped["d_out"]) <= 250.0 + TOL, "setbacks should cap to the available legs (in=%.1f out=%.1f)" % [capped["d_in"], capped["d_out"]]):
		return false
	if not _expect(float(capped["r1"]) >= SECTIONS.MIN_PROFILE_RADIUS - 0.01 and float(capped["r2"]) >= SECTIONS.MIN_PROFILE_RADIUS - 0.01, "capped radii must stay at or above the floor"):
		return false
	# A profile that would require both radii below the floor must fall back.
	var too_tight := SECTIONS.corner_profile(corner, incoming, outgoing, 181.0, 181.0, 0.5, 40.0, 40.0)
	if not _expect(not bool(too_tight["accepted"]), "over-tight legs must reject the profile"):
		return false
	return true


func _test_straight_motif_pose() -> bool:
	var start := Vector2(100.0, 50.0)
	var tangent := Vector2.RIGHT
	var run_length := 600.0
	var motif := SECTIONS.straight_motif(start, tangent, run_length)
	if not _expect(bool(motif["accepted"]), "motif should be accepted for a long run"):
		return false
	var points: PackedVector2Array = motif["points"]
	if not _expect(points.size() >= 4, "motif should emit several arc points"):
		return false
	if not _expect(points[0].distance_to(start) < TOL, "motif should start at the run start"):
		return false
	if not _expect(points[points.size() - 1].distance_to(start + tangent * run_length) < TOL, "motif should end at the run end (pose preserved)"):
		return false
	# Endpoint tangents must head along the run tangent and be mirror-symmetric
	# about it (the excursion is a mirror-symmetric out-and-back). Arc sampling
	# resolves the true tangent to within one step, so a ~8 deg chord tolerance
	# is the discrete equivalent of exact pose preservation.
	var start_dir := (points[1] - points[0]).normalized()
	var end_dir := (points[points.size() - 1] - points[points.size() - 2]).normalized()
	if not _expect(start_dir.dot(tangent) > 0.98 and end_dir.dot(tangent) > 0.98, "motif endpoint tangents must head along the run tangent (s=%.3f e=%.3f)" % [start_dir.dot(tangent), end_dir.dot(tangent)]):
		return false
	if not _expect(absf(start_dir.cross(tangent) + end_dir.cross(tangent)) < 0.05, "motif endpoint tangents must be mirror-symmetric about the run tangent"):
		return false
	# Geometric length must exceed the replaced straight.
	if not _expect(float(motif["added_length"]) > 0.0, "motif must add arc length (added=%.1f)" % motif["added_length"]):
		return false
	var polyline_length := 0.0
	for index in range(points.size() - 1):
		polyline_length += points[index].distance_to(points[index + 1])
	if not _expect(polyline_length > run_length + 0.5, "motif polyline must be longer than the straight run (%.1f vs %.1f)" % [polyline_length, run_length]):
		return false
	# Minimum accepted radius preserved.
	if not _expect(float(motif["radius"]) >= SECTIONS.MIN_MOTIF_RADIUS - 0.001, "motif radius must respect the 147 floor"):
		return false
	# Determinism.
	var again := SECTIONS.straight_motif(start, tangent, run_length)
	if not _expect(again["points"] == points, "motif must be deterministic"):
		return false
	return true


func _test_straight_motif_rejection() -> bool:
	var start := Vector2.ZERO
	var tangent := Vector2.RIGHT
	if not _expect(not bool(SECTIONS.straight_motif(start, tangent, 1.0)["accepted"]), "too-short run must be rejected"):
		return false
	if not _expect(not bool(SECTIONS.straight_motif(start, tangent, 600.0, 100.0)["accepted"]), "radius below the 147 floor must be rejected"):
		return false
	if not _expect(not bool(SECTIONS.straight_motif(start, tangent, 600.0, 140.0)["accepted"]), "radius below floor with explicit arg must be rejected"):
		return false
	return true


func _test_profile_wiring() -> bool:
	# A roomy convex polygon should realize opening/tightening profiles and expose
	# per-kind counts, deterministically.
	var roomy := PackedVector2Array([
		Vector2(-1000, -700), Vector2(1000, -700), Vector2(1000, 700), Vector2(-1000, 700),
	])
	var radii := PackedFloat32Array()
	for i in roomy.size():
		radii.append(200.0)
	var result := GRAMMAR.round_corners_profiled(roomy, radii, 7)
	var controls: PackedVector2Array = result["controls"]
	var profiles: Dictionary = result["profiles"]
	if not _expect(not controls.is_empty(), "roomy polygon should round successfully"):
		return false
	if not _expect(int(profiles.get("tightening", 0)) + int(profiles.get("opening", 0)) + int(profiles.get("symmetric", 0)) > 0, "roomy convex corners should realize at least one two-arc profile (got %s)" % [profiles]):
		return false
	var again := GRAMMAR.round_corners_profiled(roomy, radii, 7)
	if not _expect(again["controls"] == controls and again["profiles"] == profiles, "profile choices must be deterministic"):
		return false
	# A tight polygon (no roomy legs) should keep every corner circular.
	var tight := PackedVector2Array([
		Vector2(-300, -300), Vector2(300, -300), Vector2(300, 300), Vector2(-300, 300),
	])
	var tight_radii := PackedFloat32Array()
	for i in tight.size():
		tight_radii.append(200.0)
	var tight_result := GRAMMAR.round_corners_profiled(tight, tight_radii, 7)
	if not _expect(int(tight_result["profiles"].get("circular", 0)) == tight.size(), "tight polygon should stay fully circular (got %s)" % [tight_result["profiles"]]):
		return false
	return true


func _test_seed_gen_metadata() -> bool:
	var params := {
		"margin": 190.0,
		"min_self_distance": 320.0,
		"min_loop_length": 1900.0 * SEED_GEN.WORLD_SCALE,
		"room_polygon": PackedVector2Array([Vector2(-875, -575) * SEED_GEN.WORLD_SCALE, Vector2(875, -575) * SEED_GEN.WORLD_SCALE, Vector2(875, 575) * SEED_GEN.WORLD_SCALE, Vector2(-875, 575) * SEED_GEN.WORLD_SCALE]),
		"room_shape": StringName("classic"),
	}
	var profiled_seeds := 0
	var motif_seeds := 0
	for seed in 40:
		var result := SEED_GEN.generate_with_retries(seed, ROOM_RECT, params)
		if not _expect(int(result["seed"]) == seed, "seed %d must be preserved" % seed):
			return false
		var points: PackedVector2Array = result["points"]
		if points.is_empty():
			continue
		if not _expect(result.has("corner_profiles") and result.has("motifs") and result.has("motif_rejections"), "seed %d should expose profile/motif metadata" % seed):
			return false
		var profiles: Dictionary = result["corner_profiles"]
		if int(profiles.get("tightening", 0)) + int(profiles.get("opening", 0)) > 0:
			profiled_seeds += 1
		if (result["motifs"] as Array).size() > 0:
			motif_seeds += 1
		var repeated := SEED_GEN.generate_with_retries(seed, ROOM_RECT, params)
		if not _expect(repeated["points"] == points, "seed %d must stay deterministic with profiles/motifs" % seed):
			return false
	if not _expect(profiled_seeds > 0, "some generated routes should realize opening/tightening corners (got %d/40)" % profiled_seeds):
		return false
	if not _expect(motif_seeds > 0, "some generated routes should apply the straight motif (got %d/40)" % motif_seeds):
		return false
	return true


func _arc_tangent(center: Vector2, point: Vector2, sign: float) -> Vector2:
	return (point - center).normalized().rotated(sign * PI * 0.5)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_ROUTE_SECTIONS_TEST FAIL: " + message)
	quit(1)
	return false
