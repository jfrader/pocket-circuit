extends SceneTree

const CORE := preload("res://scripts/race/track_builder_core.gd")
const IDS := preload("res://scripts/race/generated_circuit_identity.gd")

const CASES := {"kitchen":[0,1,4,5,7,8,10,11], "workshop":[0,1,2,4,5,11,13,20], "office":[0,1,3,5,6,8,14,23]}
const SECTOR_COUNT := 8
const MIN_LOOKAHEAD := 5  # mirrors CORE.CUT_MIN_LOOKAHEAD
const MAX_LOOKAHEAD := 32  # mirrors CORE.CUT_MAX_LOOKAHEAD
const CHORD_SAMPLES := 41
## A cut only matters if a whole car fits through it, so colliders are inflated
## by the vehicle's real physical half-width: the Rustbug collision capsule has
## radius 18 (scenes/vehicles/rustbug.tscn), which is what the physics actually
## sweeps — the 44 in TrackBuilderCore.VEHICLE_WIDTH is a corridor-planning figure.
const MIN_CAR_CLEARANCE_MM := CORE.CAR_COLLISION_DIAMETER * 0.5
const TURN_THRESHOLD := 0.18  # mirrors CORE.CUT_TURN_THRESHOLD
## Folds, like the cut definition itself, come from TrackBuilderCore so the
## planner that blocks them and this regression cannot drift apart.
const FOLD_MAX_SPACING_MM := CORE.CUT_FOLD_MAX_SPACING_MM
const FOLD_MIN_LAP_FRACTION := CORE.CUT_FOLD_MIN_LAP_FRACTION
## What makes a cut exploitable is defined once, in TrackBuilderCore, so the
## planner that blocks cuts and this regression cannot drift apart.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not _atomic_sanity(): return
	var total_cuts := 0
	var first_offender := ""
	var counts: Dictionary = {}
	for theme: String in CASES:
		counts[theme] = {}
		for seed_value: int in CASES[theme]:
			var identity := IDS.create(StringName(theme), IDS.room_for_route_seed(seed_value), seed_value)
			var prepared := CORE.prepare_layout(StringName(theme), StringName(identity["room"]), seed_value, IDS.generation_options(identity))
			if not _check(not prepared.is_empty(), "prepare_layout failed for %s seed %d" % [theme, seed_value]): return
			var centerline: PackedVector2Array = prepared["centerline"]
			var spec: Dictionary = prepared["spec"]
			var env: Dictionary = spec.get("environment_plan", {})
			var diags: Dictionary = env.get("diagnostics", {})
			var open_sector: int = int(diags.get("open_sector", -1))
			var built := CORE.build_packed(StringName(theme), StringName(identity["room"]), seed_value, IDS.generation_options(identity))
			var packed: PackedScene = built.get("scene", null)
			if not _check(packed != null, "build_packed returned no scene for %s seed %d" % [theme, seed_value]): return
			var track := packed.instantiate() as Node2D
			if not _check(track != null, "instantiate failed for %s seed %d" % [theme, seed_value]): 
				if track: track.free()
				return
			track.position = Vector2.ZERO
			track.rotation = 0.0
			var island_poly: PackedVector2Array = _extract_island_polygon(track)
			if island_poly.is_empty():
				island_poly = spec.get("environment_island_polygon", PackedVector2Array())
			var colliders: Array = _collect_colliders(track)
			var n := centerline.size()
			var theme_cuts := 0
			for pair: Vector2i in _candidate_pairs(centerline):
				var i := int(pair.x)
				var j := int(pair.y)
				var k := CORE._cyclic_index_distance(i, j, n)
				if true:
					var a: Vector2 = centerline[i]
					var b: Vector2 = centerline[j]
					var samples: PackedVector2Array = []
					for s in CHORD_SAMPLES:
						var t := float(s) / float(CHORD_SAMPLES - 1)
						samples.append(a.lerp(b, t))
					# (a) the shared definition of an exploitable cut
					var verdict: Dictionary = CORE.exploitable_cut(centerline, i, k)
					if not bool(verdict["exploitable"]):
						continue
					var deep := int(verdict["deep"])
					var saved := float(verdict["saved"])
					# (d) open sector
					var in_open := false
					for p in samples:
						var near: Dictionary = CORE._closest_point_on_loop(p, centerline)
						var idx: int = int(near.get("index", 0))
						var sec := mini(SECTOR_COUNT - 1, int(float(idx) / float(n) * float(SECTOR_COUNT)))
						if sec == open_sector:
							in_open = true
							break
					if in_open:
						continue
					# (b) hits island poly via sample
					var hits_island := false
					if island_poly.size() >= 3:
						for p in samples:
							if Geometry2D.is_point_in_polygon(p, island_poly):
								hits_island = true
								break
					if hits_island:
						continue
					# (c) hits any collider
					var hits_solid := false
					for c in colliders:
						var cs: CollisionShape2D = c["cs"]
						var shp: Shape2D = c["shape"]
						if _chord_hits_shape(a, b, cs, shp, MIN_CAR_CLEARANCE_MM):
							hits_solid = true
							break
					if hits_solid:
						continue
					# exploitable cut
					theme_cuts += 1
					total_cuts += 1
					var line := "CUTTABLE %s seed=%d start=%d end=%d gap_indices=%d saved_mm=%.0f deep=%d/%d" % [theme, seed_value, i, j, k, saved, deep, CHORD_SAMPLES]
					print(line)
					if first_offender.is_empty():
						first_offender = "%s seed=%d i=%d j=%d gap=%d" % [theme, seed_value, i, j, k]
			track.free()
			counts[theme][seed_value] = theme_cuts
			await process_frame
	# report counts
	for theme: String in counts:
		for sv: int in counts[theme]:
			print("CUT_COUNT %s seed=%d count=%d" % [theme, sv, int(counts[theme][sv])])
	if not first_offender.is_empty():
		push_error("OUTER_CUT_BLOCK_TEST FAIL: exploitable bare outer corner cut: " + first_offender)
		quit(1)
		return
	print("OUTER_CUT_BLOCK_TEST PASS no_cuttable_outer_chords")
	quit(0)

func _atomic_sanity() -> bool:
	# basic that core apis are present and a trivial chord test works
	var dummy := PackedVector2Array([Vector2(0,0), Vector2(100,0), Vector2(100,100), Vector2(0,100)])
	if not _check(CORE.HALF_WIDTH == 125.0, "HALF_WIDTH must be 125.0"): return false
	if not _check(CORE.CUT_MIN_OFF_CORRIDOR_MM == 40.0 and CORE.CUT_MIN_DEEP_SAMPLES == 3 and CORE.CUT_MIN_SAVED_MM == 50.0 and CORE.CUT_MIN_ARC_RATIO == 1.25, "the shared cut definition must stay the one the planner blocks"): return false
	var straight := PackedVector2Array()
	for step in 200:
		straight.append(Vector2(step * 10.0, 0.0))
	if not _check(not bool(CORE.exploitable_cut(straight, 0, 20)["exploitable"]), "the shared cut definition must not call a straight road a cut"): return false
	var anchor_identity := IDS.create(&"kitchen", IDS.room_for_route_seed(7), 7)
	var anchor := CORE.prepare_layout(&"kitchen", StringName(anchor_identity["room"]), 7, IDS.generation_options(anchor_identity))
	var anchor_line: PackedVector2Array = anchor["centerline"]
	if not _check(bool(CORE.exploitable_cut(anchor_line, 223, 22)["exploitable"]), "the shared cut definition must recognise the measured kitchen seed 7 bend that can be cut across"): return false
	if not _check(not bool(CORE.exploitable_cut(anchor_line, 223, 2)["exploitable"]), "the shared cut definition must not call a two-step hop a cut"): return false
	var d := CORE._distance_to_centerline(Vector2(0, 300), dummy)
	if not _check(d > 190.0, "distance helper must report far points"): return false
	var ts := CORE._turn_strength(dummy, 1, 1)
	if not _check(ts > 1.0, "turn strength must detect 90deg"): return false
	return true

func _check(ok: bool, message: String) -> bool:
	if ok: return true
	push_error("OUTER_CUT_BLOCK_TEST FAIL: " + message)
	quit(1)
	return false

func _extract_island_polygon(track: Node2D) -> PackedVector2Array:
	var bc := track.get_node_or_null("InnerBarrier/BoundaryCollision") as CollisionShape2D
	if bc == null or bc.shape == null:
		return PackedVector2Array()
	var sh: Shape2D = bc.shape
	if sh is ConcavePolygonShape2D:
		var segs: PackedVector2Array = (sh as ConcavePolygonShape2D).segments
		var poly := PackedVector2Array()
		for ii in range(0, segs.size(), 2):
			poly.append(segs[ii])
		if poly.size() > 2 and poly[0].distance_to(poly[poly.size() - 1]) < 1.0:
			poly.remove_at(poly.size() - 1)
		return poly
	elif sh is ConvexPolygonShape2D:
		return (sh as ConvexPolygonShape2D).points.duplicate()
	return PackedVector2Array()

func _collect_colliders(track: Node2D) -> Array:
	var res: Array = []
	for bnode in track.find_children("*", "StaticBody2D", true, false):
		var body := bnode as StaticBody2D
		for cnode in body.find_children("*", "CollisionShape2D", true, false):
			var cs := cnode as CollisionShape2D
			if cs != null and cs.shape != null:
				res.append({"cs": cs, "shape": cs.shape})
	return res

## Chords worth testing: a short look-ahead out of a sharp bend, and a fold where
## the lap comes back near itself, which is where crossing the apron skips the most
## track. Folds are the ones a plain look-ahead scan never sees.
func _candidate_pairs(centerline: PackedVector2Array) -> Array[Vector2i]:
	var pairs: Array[Vector2i] = []
	var n := centerline.size()
	var seen: Dictionary = {}
	for i in n:
		if CORE._turn_strength(centerline, i, 6) < TURN_THRESHOLD:
			continue
		for kk in range(MIN_LOOKAHEAD, MAX_LOOKAHEAD + 1):
			var j := (i + kk) % n
			var key := i * n + j
			if seen.has(key):
				continue
			seen[key] = true
			pairs.append(Vector2i(i, j))
	var cell := FOLD_MAX_SPACING_MM
	var buckets: Dictionary = {}
	for index in n:
		var key := Vector2i(floori(centerline[index].x / cell), floori(centerline[index].y / cell))
		if not buckets.has(key):
			buckets[key] = PackedInt32Array()
		buckets[key].append(index)
	var minimum_skip := int(float(n) * FOLD_MIN_LAP_FRACTION)
	for index in n:
		var key := Vector2i(floori(centerline[index].x / cell), floori(centerline[index].y / cell))
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var neighbour := key + Vector2i(dx, dy)
				if not buckets.has(neighbour):
					continue
				for other: int in buckets[neighbour]:
					if other == index:
						continue
					var skip := CORE._cyclic_index_distance(index, other, n)
					if skip < minimum_skip:
						continue
					if centerline[index].distance_to(centerline[other]) > FOLD_MAX_SPACING_MM:
						continue
					var first := mini(index, other)
					var second := maxi(index, other)
					var pair_key := first * n + second
					if seen.has(pair_key):
						continue
					seen[pair_key] = true
					pairs.append(Vector2i(index, other))
	return pairs


func _chord_hits_shape(world_a: Vector2, world_b: Vector2, cs: CollisionShape2D, shape: Shape2D, margin: float = 0.0) -> bool:
	var body := cs.get_parent() as Node2D
	if body == null:
		body = cs
	var body_tf := Transform2D(body.rotation, body.position)
	var cs_tf := Transform2D(cs.rotation, cs.position)
	var full := body_tf * cs_tf
	var inv := full.affine_inverse()
	var la := inv * world_a
	var lb := inv * world_b
	return _seg_hits_local(la, lb, shape, margin)

func _seg_hits_local(la: Vector2, lb: Vector2, shape: Shape2D, margin: float = 0.0) -> bool:
	if shape is CircleShape2D:
		return _seg_circle(la, lb, Vector2.ZERO, (shape as CircleShape2D).radius + margin)
	if shape is RectangleShape2D:
		var half := (shape as RectangleShape2D).size * 0.5 + Vector2.ONE * margin
		var pts := PackedVector2Array([
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
			Vector2(half.x, half.y), Vector2(-half.x, half.y)
		])
		return _seg_poly(la, lb, pts)
	if shape is CapsuleShape2D:
		var cap := shape as CapsuleShape2D
		var rad := cap.radius + margin
		var sh := maxf(0.0, cap.height * 0.5 - rad)
		var m1 := Vector2(0.0, -sh)
		var m2 := Vector2(0.0, sh)
		if _seg_circle(la, lb, m1, rad) or _seg_circle(la, lb, m2, rad):
			return true
		return _seg_to_seg_dist(la, lb, m1, m2) <= rad + 0.01
	if shape is ConvexPolygonShape2D:
		var convex_pts: PackedVector2Array = (shape as ConvexPolygonShape2D).points
		if _seg_poly(la, lb, convex_pts):
			return true
		return _seg_within_poly(la, lb, convex_pts, margin)
	if shape is ConcavePolygonShape2D:
		var segs: PackedVector2Array = (shape as ConcavePolygonShape2D).segments
		for si in range(0, segs.size(), 2):
			var sa := segs[si]
			var sb := segs[si + 1]
			if Geometry2D.segment_intersects_segment(la, lb, sa, sb) != null:
				return true
			if _seg_to_seg_dist(la, lb, sa, sb) <= margin + 0.01:
				return true
		return false
	# unsupported: fail loudly, never green
	push_error("OUTER_CUT_BLOCK_TEST FAIL: unsupported shape type in detector: " + shape.get_class())
	quit(1)
	return true

func _seg_within_poly(la: Vector2, lb: Vector2, points: PackedVector2Array, margin: float) -> bool:
	if margin <= 0.0 or points.size() < 2:
		return false
	for index in points.size():
		var a := points[index]
		var b := points[(index + 1) % points.size()]
		if _seg_to_seg_dist(la, lb, a, b) <= margin + 0.01:
			return true
	return false

func _seg_circle(p1: Vector2, p2: Vector2, c: Vector2, r: float) -> bool:
	var d := p2 - p1
	var f := p1 - c
	var a := d.dot(d)
	if a < 0.0001:
		return f.length() <= r
	var b := 2.0 * f.dot(d)
	var ccv := f.dot(f) - r * r
	var disc := b * b - 4.0 * a * ccv
	if disc < 0.0:
		return false
	disc = sqrt(disc)
	var t1 := (-b - disc) / (2.0 * a)
	var t2 := (-b + disc) / (2.0 * a)
	if (t1 >= 0.0 and t1 <= 1.0) or (t2 >= 0.0 and t2 <= 1.0):
		return true
	if (p1 - c).length() <= r or (p2 - c).length() <= r:
		return true
	return false

func _seg_poly(p1: Vector2, p2: Vector2, poly: PackedVector2Array) -> bool:
	var m := poly.size()
	if m < 3:
		return false
	if Geometry2D.is_point_in_polygon(p1, poly) or Geometry2D.is_point_in_polygon(p2, poly):
		return true
	for ii in m:
		var q1 := poly[ii]
		var q2 := poly[(ii + 1) % m]
		if Geometry2D.segment_intersects_segment(p1, p2, q1, q2) != null:
			return true
	return false

func _seg_to_seg_dist(a1: Vector2, a2: Vector2, b1: Vector2, b2: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a1, a2, b1, b2) != null:
		return 0.0
	var d1 := _pt_seg(a1, b1, b2)
	var d2 := _pt_seg(a2, b1, b2)
	var d3 := _pt_seg(b1, a1, a2)
	var d4 := _pt_seg(b2, a1, a2)
	return minf(minf(d1, d2), minf(d3, d4))

func _pt_seg(p: Vector2, s1: Vector2, s2: Vector2) -> float:
	var v := s2 - s1
	var w := p - s1
	var c1 := w.dot(v)
	if c1 <= 0.0:
		return p.distance_to(s1)
	var c2 := v.dot(v)
	if c2 <= c1:
		return p.distance_to(s2)
	var bb := c1 / c2
	var pb := s1 + bb * v
	return p.distance_to(pb)
