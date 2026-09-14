extends SceneTree

const SAMPLER := preload("res://scripts/race/track_curve_sampling.gd")
const GEOM := preload("res://scripts/race/track_builder_geometry.gd")
const ROUTE := preload("res://scripts/race/track_route_grammar.gd")

const TOL := 0.5
const SHAPE_TOL := 35.0


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	# invalid args
	if not _expect(SAMPLER.sample(PackedVector2Array()).is_empty(), "empty controls -> empty"):
		return
	if not _expect(SAMPLER.sample(PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.UP])).is_empty(), "<4 controls -> empty"):
		return
	if not _expect(SAMPLER.sample(_make_square_controls(200.0), 0.0).is_empty(), "max_spacing<=0 -> empty"):
		return
	if not _expect(SAMPLER.sample(_make_square_controls(200.0), 10.0, 0).is_empty(), "min_count<1 -> empty"):
		return

	# NaN/INF controls or spacing return empty quickly (before heavy work)
	var good4 := _make_square_controls(200.0)
	var nan_ctrl := PackedVector2Array([Vector2(0,0), Vector2(10,0), Vector2(NAN, 0), Vector2(0,10)])
	if not _expect(SAMPLER.sample(nan_ctrl).is_empty(), "NaN in controls -> empty"):
		return
	var inf_ctrl := PackedVector2Array([Vector2(0,0), Vector2(10,0), Vector2(INF, 0), Vector2(0,10)])
	if not _expect(SAMPLER.sample(inf_ctrl).is_empty(), "INF in controls -> empty"):
		return
	if not _expect(SAMPLER.sample(good4, NAN).is_empty(), "NaN spacing -> empty"):
		return
	if not _expect(SAMPLER.sample(good4, INF).is_empty(), "INF spacing -> empty"):
		return

	# min_count over supported budget -> empty
	if not _expect(SAMPLER.sample(good4, 35.0, 2000000).is_empty(), "min_count over budget -> empty"):
		return

	# huge finite chord pathology returns empty (dense budget hit before alloc blowup)
	var huge := PackedVector2Array([Vector2(0,0), Vector2(1e8,0), Vector2(1e8,10), Vector2(0,10)])
	if not _expect(SAMPLER.sample(huge).is_empty(), "huge finite chord (1e8) -> empty"):
		return

	# degenerate / repeated / zero-length
	var rep := PackedVector2Array()
	for i in 6:
		rep.append(Vector2(10.0, 20.0))
	if not _expect(SAMPLER.sample(rep).is_empty(), "repeated controls -> empty"):
		return
	var tiny := _make_square_controls(0.0001)
	if not _expect(SAMPLER.sample(tiny).is_empty(), "zero-length/tiny loop -> empty"):
		return

	# determinism
	var ctrls := _make_curved_controls(1200.0)
	var a := SAMPLER.sample(ctrls)
	var b := SAMPLER.sample(ctrls)
	if not _expect(a == b, "identical controls must produce identical samples"):
		return
	var a2 := SAMPLER.sample(ctrls, 40.0, 200)
	var b2 := SAMPLER.sample(ctrls, 40.0, 200)
	if not _expect(a2 == b2, "deterministic for non-default params"):
		return

	# translated / rotated equivalence
	var tx := Vector2(123.0, -77.0)
	var rot := 0.37
	var trans := _translate(ctrls, tx)
	var rotd := _rotate(ctrls, rot)
	var sa := SAMPLER.sample(ctrls)
	var sb := SAMPLER.sample(trans)
	var sc := SAMPLER.sample(rotd)
	if not _expect(sa.size() == sb.size() and sa.size() == sc.size(), "isometry preserves count"):
		return
	for i in sa.size():
		if not _expect(sb[i].distance_to(sa[i] + tx) < 0.01, "translate preserved at %d (dist=%.6f)" % [i, sb[i].distance_to(sa[i] + tx)]):
			return
		var exp_rot := sa[i].rotated(rot)
		if not _expect(sc[i].distance_to(exp_rot) < 0.01, "rotate preserved at %d (dist=%.6f)" % [i, sc[i].distance_to(exp_rot)]):
			return

	# 1x/2x/3x length and count grow (fixed max_spacing)
	var base := _make_curved_controls(800.0)
	var s1 := SAMPLER.sample(base, 35.0, 50)
	var s2 := SAMPLER.sample(_scale(base, 2.0), 35.0, 50)
	var s3 := SAMPLER.sample(_scale(base, 3.0), 35.0, 50)
	var l1 := _polyline_length(s1)
	var l2 := _polyline_length(s2)
	var l3 := _polyline_length(s3)
	if not _expect(l2 > l1 * 1.95 and l2 < l1 * 2.05, "length doubles (got %.1f vs 2x%.1f)" % [l2, l1]):
		return
	if not _expect(l3 > l1 * 2.9 and l3 < l1 * 3.1, "length triples"):
		return
	if not _expect(s2.size() >= s1.size() * 1.9, "count grows ~2x"):
		return
	if not _expect(s3.size() >= s1.size() * 2.9, "count grows ~3x"):
		return

	# old geometry approx match for closed curved shape
	var curved := _make_curved_controls(1400.0)
	var old_arr: Array = Array(curved)
	var old_pts := GEOM.sample_centerline(old_arr)
	var new_pts := SAMPLER.sample(curved)
	if not _expect(abs(old_pts.size() - new_pts.size()) <= 20, "count near old 260 (got %d vs %d)" % [new_pts.size(), old_pts.size()]):
		return
	var olen := _polyline_length(old_pts)
	var nlen := _polyline_length(new_pts)
	if not _expect(abs(olen - nlen) < 80.0, "lengths approx (old %.1f new %.1f)" % [olen, nlen]):
		return
	# shape: old points lie close to the new arc-length polyline (hausdorff-ish)
	var maxd := 0.0
	for op in old_pts:
		var md := INF
		for np in new_pts:
			md = minf(md, op.distance_to(np))
		maxd = maxf(maxd, md)
	if not _expect(maxd < SHAPE_TOL, "curved shape approx match (maxd=%.1f)" % maxd):
		return

	# radius 180 circle approximation valid
	var circ := _make_circle_controls(180.0, 12)
	var circ_samples := SAMPLER.sample(circ, 20.0, 100)  # force enough points
	if not _expect(circ_samples.size() >= 100, "circle uses requested count"):
		return
	var center := Vector2.ZERO
	var rmean := 0.0
	var rmaxd := 0.0
	for p in circ_samples:
		var r := p.length()
		rmean += r
		rmaxd = maxf(rmaxd, absf(r - 180.0))
	rmean /= float(circ_samples.size())
	if not _expect(absf(rmean - 180.0) < 3.0 and rmaxd < 6.0, "r180 circle approx (mean=%.2f maxd=%.2f)" % [rmean, rmaxd]):
		return
	var clen := _polyline_length(circ_samples)
	var expect_len := TAU * 180.0
	if not _expect(absf(clen - expect_len) < 30.0, "circle length approx (%.1f vs %.1f)" % [clen, expect_len]):
		return

	# closed spacing <= max + tol, no duplicate first at end
	var spaced := SAMPLER.sample(ctrls, 35.0)
	var scount := spaced.size()
	if not _expect(scount >= 4 and not spaced[0].is_equal_approx(spaced[scount - 1]), "no duplicate endpoint"):
		return
	var max_space := 0.0
	for i in scount:
		var d := spaced[i].distance_to(spaced[(i + 1) % scount])
		max_space = maxf(max_space, d)
	if not _expect(max_space <= 35.0 + 0.5, "closed last-to-first and all spacings <= max+tol (got %.2f)" % max_space):
		return

	# variable N for long tracks ( > min_count when est requires)
	var long_ctrls := _scale(_make_curved_controls(3000.0), 2.0)  # ~12k len target
	var long_s := SAMPLER.sample(long_ctrls)
	if not _expect(long_s.size() > 260, "long track gets N>260 (got %d)" % long_s.size()):
		return

	print("TRACK_CURVE_SAMPLING_TEST PASS samples=%d curved_len=%.0f circle_r=%.2f long_n=%d" % [new_pts.size(), nlen, rmean, long_s.size()])
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_CURVE_SAMPLING_TEST FAIL: " + message)
	quit(1)
	return false


func _make_square_controls(size: float) -> PackedVector2Array:
	var s := size * 0.5
	return PackedVector2Array([
		Vector2(-s, -s), Vector2(s, -s), Vector2(s, s), Vector2(-s, s)
	])


func _make_curved_controls(scale: float) -> PackedVector2Array:
	# Simple kidney-like curved loop using rounded corners
	var v := PackedVector2Array([
		Vector2(-scale * 0.9, -scale * 0.6),
		Vector2(scale * 0.2, -scale * 0.7),
		Vector2(scale * 0.9, -scale * 0.2),
		Vector2(scale * 0.6, scale * 0.5),
		Vector2(-scale * 0.3, scale * 0.7),
		Vector2(-scale * 0.8, scale * 0.1),
	])
	return _rounded_corner_controls(v, scale * 0.22)


func _make_circle_controls(r: float, n: int) -> PackedVector2Array:
	var c := PackedVector2Array()
	for i in n:
		var a := float(i) / float(n) * TAU
		c.append(Vector2(cos(a), sin(a)) * r)
	return c


func _rounded_corner_controls(vertices: PackedVector2Array, radius: float) -> PackedVector2Array:
	if vertices.size() < 3:
		return PackedVector2Array()
	var entries := PackedVector2Array()
	var exits := PackedVector2Array()
	var centers := PackedVector2Array()
	var turns := PackedFloat32Array()
	for i in vertices.size():
		var prev := vertices[posmod(i - 1, vertices.size())]
		var cor := vertices[i]
		var nxt := vertices[(i + 1) % vertices.size()]
		var inc := prev.direction_to(cor)
		var outg := cor.direction_to(nxt)
		var turn := inc.angle_to(outg)
		var tanf := radius * tan(absf(turn) * 0.5)
		tanf = minf(tanf, minf(prev.distance_to(cor), cor.distance_to(nxt)) * 0.45)
		entries.append(cor - inc * tanf)
		exits.append(cor + outg * tanf)
		centers.append(entries[i] + inc.rotated(signf(turn) * PI * 0.5) * radius)
		turns.append(turn)
	var ctrls := PackedVector2Array()
	for i in vertices.size():
		var rad := entries[i] - centers[i]
		var asteps := maxi(4, ceili(radius * absf(turns[i]) / 40.0))
		for st in asteps:
			ctrls.append(centers[i] + rad.rotated(turns[i] * float(st) / float(asteps)))
		var ne := entries[(i + 1) % vertices.size()]
		var sl := exits[i].distance_to(ne)
		var lst := maxi(1, ceili(sl / 40.0))
		for st in lst:
			ctrls.append(exits[i].lerp(ne, float(st) / float(lst)))
	return ctrls


func _polyline_length(pts: PackedVector2Array) -> float:
	if pts.is_empty():
		return 0.0
	var tot := 0.0
	for i in pts.size():
		tot += pts[i].distance_to(pts[(i + 1) % pts.size()])
	return tot


func _translate(pts: PackedVector2Array, off: Vector2) -> PackedVector2Array:
	var r := PackedVector2Array()
	for p in pts:
		r.append(p + off)
	return r


func _rotate(pts: PackedVector2Array, ang: float) -> PackedVector2Array:
	var r := PackedVector2Array()
	for p in pts:
		r.append(p.rotated(ang))
	return r


func _scale(pts: PackedVector2Array, k: float) -> PackedVector2Array:
	var r := PackedVector2Array()
	for p in pts:
		r.append(p * k)
	return r
