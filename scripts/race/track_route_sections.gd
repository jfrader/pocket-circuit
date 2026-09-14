class_name TrackRouteSections
## Pure, stateless geometry for compound corner profiles and pose-preserving
## straight-replacement motifs. Callers supply corner/segment geometry and get
## back control geometry plus a compact metadata record. No nodes, no textures,
## no scene state.

const MIN_PROFILE_RADIUS := 180.0
const MIN_MOTIF_RADIUS := 147.0
const CONTROL_SPACING := 55.0


## Build a tangent-continuous (G1) two-circular-arc corner. Entry and exit arcs
## turn the same signed direction by `split_fraction` and `1 - split_fraction`
## of the total turn, at radii `entry_radius` and `exit_radius`. Different radii
## produce a true tightening/opening curve; equal radii a symmetric compound
## bend. Setbacks are capped (uniformly scaled about the corner) to the available
## adjacent legs, and the profile is only accepted when both radii stay at or
## above MIN_PROFILE_RADIUS and both setbacks are positive.
##
## Returns {accepted, kind, entry, exit, join, center1, center2, r1, r2, phi,
## turn, d_in, d_out}.
static func corner_profile(
	corner: Vector2,
	incoming: Vector2,
	outgoing: Vector2,
	entry_radius: float,
	exit_radius: float,
	split_fraction: float,
	max_in_setback: float,
	max_out_setback: float
) -> Dictionary:
	var turn := incoming.angle_to(outgoing)
	if absf(turn) < 0.001 or absf(turn) > PI - 0.01:
		return _rejected_profile("degenerate turn")
	var sign := signf(turn)
	var split := turn * clampf(split_fraction, 0.05, 0.95)
	var perp := incoming.rotated(sign * PI * 0.5)
	# Translation-invariant displacement from entry (tangent `incoming`) to exit
	# (tangent `outgoing`) across two same-signed arcs turning `split` then
	# `turn - split`. Entry/exit legs are solved in the (u, v) basis so the
	# profile plugs into a vertex exactly like a circular fillet.
	var delta := entry_radius * (perp - perp.rotated(split)) + exit_radius * (perp.rotated(split) - perp.rotated(turn))
	var denominator := incoming.cross(outgoing)
	if absf(denominator) < 0.001:
		return _rejected_profile("parallel legs")
	var d_out := incoming.cross(delta) / denominator
	var d_in := delta.cross(outgoing) / denominator
	if d_in <= 0.0 or d_out <= 0.0:
		return _rejected_profile("negative setback")
	# Cap tangent setbacks to the available legs. Scaling both radii equally
	# preserves the seeded tightening/opening ratio and both entry/exit tangents.
	var setback_scale := minf(1.0, minf(max_in_setback / d_in, max_out_setback / d_out))
	var r1 := entry_radius * setback_scale
	var r2 := exit_radius * setback_scale
	if r1 < MIN_PROFILE_RADIUS - 0.01 or r2 < MIN_PROFILE_RADIUS - 0.01:
		return _rejected_profile("radius below floor")
	d_in *= setback_scale
	d_out *= setback_scale
	var entry := corner - incoming * d_in
	var exit := corner + outgoing * d_out
	var center1 := entry + perp * r1
	var join := center1 + (entry - center1).rotated(split)
	var midheading := incoming.rotated(split)
	var center2 := join + midheading.rotated(sign * PI * 0.5) * r2
	var kind := "symmetric"
	if r2 < r1 - 0.01:
		kind = "tightening"
	elif r2 > r1 + 0.01:
		kind = "opening"
	return {
		"accepted": true,
		"kind": kind,
		"entry": entry,
		"exit": exit,
		"join": join,
		"center1": center1,
		"center2": center2,
		"r1": r1,
		"r2": r2,
		"phi": split,
		"turn": turn,
		"d_in": d_in,
		"d_out": d_out,
	}


## Sample a circular arc from `start` around `center` through signed `turn`,
## emitting spacing-bounded points that exclude the start point and include the
## end point. Matches the control-stream shape used by the route grammar.
static func arc_samples(center: Vector2, start: Vector2, turn: float, spacing: float = CONTROL_SPACING) -> PackedVector2Array:
	var radial := start - center
	var steps := maxi(1, ceili(radial.length() * absf(turn) / maxf(spacing, 1.0)))
	var points := PackedVector2Array()
	for step in range(1, steps + 1):
		points.append(center + radial.rotated(turn * float(step) / float(steps)))
	return points


## Pose-preserving out-and-back straight replacement. Replaces a straight run
## `start` -> `start + tangent * run_length` with a symmetric four-arc excursion
## that returns to the exact endpoint with the exact tangent while adding arc
## length. Every arc uses radius `radius` (>= MIN_MOTIF_RADIUS), so the minimum
## turn radius is preserved. `bulge_normal` selects which side of the run the
## excursion bulges toward (defaults to tangent.rotated(PI/2)).
##
## Returns {accepted, kind, reason, points, radius, added_length, excursion},
## where `points` is the full polyline (start .. end inclusive) in world space.
static func straight_motif(start: Vector2, tangent: Vector2, run_length: float, radius: float = -1.0, bulge_normal: Vector2 = Vector2.ZERO) -> Dictionary:
	if run_length < 2.0:
		return _rejected_motif("run too short")
	var r := radius if radius > 0.0 else maxf(MIN_MOTIF_RADIUS, run_length * 0.5)
	if r < MIN_MOTIF_RADIUS - 0.001:
		return _rejected_motif("radius below floor")
	var half := run_length * 0.5
	var sin_theta := half / (2.0 * r)
	if sin_theta > 1.0:
		return _rejected_motif("radius too small for run")
	var theta := asin(sin_theta)
	var normal := bulge_normal if bulge_normal != Vector2.ZERO else tangent.rotated(PI * 0.5)
	# Left half in local space (+X = tangent, +Y = normal): a two-arc S rising
	# from (0,0) to (run_length/2, excursion) with tangent +X at both ends.
	var left := PackedVector2Array([Vector2.ZERO])
	var c1 := Vector2(0.0, r)
	left.append_array(arc_samples(c1, Vector2.ZERO, theta))
	var p1 := left[left.size() - 1]
	var tangent1 := Vector2.RIGHT.rotated(theta)
	var c2 := p1 + tangent1.rotated(-PI * 0.5) * r
	left.append_array(arc_samples(c2, p1, -theta))
	# Mirror the left half across x = run_length/2, reverse, and drop the shared
	# peak so the right half descends back to the original line and tangent.
	var right := PackedVector2Array()
	for index in range(left.size() - 1, -1, -1):
		var local := left[index]
		right.append(Vector2(run_length - local.x, local.y))
	var local_points := PackedVector2Array()
	local_points.append_array(left)
	for index in range(1, right.size()):
		local_points.append(right[index])
	var points := PackedVector2Array()
	for local: Vector2 in local_points:
		points.append(start + tangent * local.x + normal * local.y)
	var excursion := 2.0 * r * (1.0 - cos(theta))
	var added_length := 4.0 * r * theta - run_length
	return {
		"accepted": true,
		"kind": "excursion",
		"reason": "",
		"points": points,
		"radius": r,
		"added_length": added_length,
		"excursion": excursion,
	}


static func _rejected_profile(reason: String) -> Dictionary:
	return {"accepted": false, "kind": "circular", "reason": reason, "r1": 0.0, "r2": 0.0}


static func _rejected_motif(reason: String) -> Dictionary:
	return {
		"accepted": false,
		"kind": "excursion",
		"reason": reason,
		"points": PackedVector2Array(),
		"radius": 0.0,
		"added_length": 0.0,
		"excursion": 0.0,
	}
