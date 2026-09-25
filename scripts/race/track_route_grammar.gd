class_name TrackRouteGrammar
## Circuit plans reserve full-width infield passages before rounding corners.

const NAMES: Array[StringName] = [&"infield", &"switchback", &"dogleg", &"harbour"]
# Marathon-only programs: folded multi-spine layouts that pack roughly twice
# the switchback's turn complexes into the same room bounds. Standard tiers
# never select them, so their seed geometry is untouched.
const MARATHON_NAMES: Array[StringName] = [&"double_switchback", &"deep_comb", &"serpentine", &"multi_comb", &"multi_lobe"]
const MACRO_SALT := 0x36D1A77
const CORNER_RADIUS := 180.0
const CONTROL_SPACING := 55.0
# Both legs of a convex corner must be at least this long before it can host a
# chamfer; shorter legs belong to bays/notches that must stay untouched.
const MIN_CHAMFER_LEG := 1000.0
const SECTIONS := preload("res://scripts/race/track_route_sections.gd")
# Both legs of a convex corner must be at least this long before it can host a
# two-arc opening/tightening profile; shorter legs keep the plain circular fillet.
const MIN_PROFILE_LEG := 700.0


static func count() -> int:
	return NAMES.size()


static func construct(index: int, seed: int, length_bias: float = 0.0, bounds := Rect2(-1300, -800, 2600, 1600)) -> Dictionary:
	var program := NAMES[posmod(index, count())]
	var width := bounds.size.x * _roll(seed, 11, 0.83, 0.94)
	var height := bounds.size.y * _roll(seed, 17, 0.78, 0.88)
	var x := width * 0.5
	var y := height * 0.5
	var lane := maxf(400.0, height * _roll(seed, 19, 0.28, 0.39))
	var vertices := PackedVector2Array()
	match program:
		&"infield":
			var mouth := _roll(seed, 23, 0.25, 0.48) * width
			var shift := _roll(seed, 29, -0.12, 0.12) * width
			var left := maxf(-x + lane, shift - mouth * 0.5)
			var right := minf(x - lane, shift + mouth * 0.5)
			vertices = PackedVector2Array([
				Vector2(-x, -y), Vector2(left, -y), Vector2(left, y - lane),
				Vector2(right, y - lane), Vector2(right, -y), Vector2(x, -y),
				Vector2(x, y), Vector2(-x, y),
			])
		&"switchback":
			var spine := maxf(400.0, width * _roll(seed, 31, 0.15, 0.21))
			var waist := maxf(400.0, width * _roll(seed, 37, 0.16, 0.25))
			var depth := height * _roll(seed, 41, 0.50, 0.63)
			vertices = PackedVector2Array([
				Vector2(-x, -y), Vector2(-x + spine, -y), Vector2(-x + spine, -y + depth),
				Vector2(-waist * 0.5, -y + depth), Vector2(-waist * 0.5, -y), Vector2(x, -y),
				Vector2(x, y), Vector2(x - spine, y), Vector2(x - spine, y - depth),
				Vector2(waist * 0.5, y - depth), Vector2(waist * 0.5, y), Vector2(-x, y),
			])
		&"dogleg":
			var elbow := width * _roll(seed, 43, -0.25, -0.05)
			var step := minf(y - 400.0, height * _roll(seed, 47, 0.06, 0.22))
			vertices = PackedVector2Array([
				Vector2(-x, -y), Vector2(elbow, -y), Vector2(elbow, step),
				Vector2(x, step), Vector2(x, y), Vector2(-x, y),
			])
		&"harbour":
			var end := width * _roll(seed, 53, 0.04, 0.27)
			var upper := -y + maxf(400.0, height * _roll(seed, 59, 0.25, 0.34))
			var lower := y - maxf(400.0, height * _roll(seed, 61, 0.25, 0.34))
			vertices = PackedVector2Array([
				Vector2(-x, -y), Vector2(x, -y), Vector2(x, y), Vector2(-x, y),
				Vector2(-x, lower), Vector2(end, lower), Vector2(end, upper), Vector2(-x, upper),
			])
	# Cut one or two convex corners into unequal chamfers to add a diagonal stem.
	vertices = _compound_chamfer(vertices, seed)
	var heading := _roll(seed, 67, 0.06, 0.11)
	if _roll_int(seed, 71, 2) == 0:
		heading = -heading
	var mirror := -1.0 if _roll_int(seed, 73, 2) == 0 else 1.0
	for i in vertices.size():
		vertices[i] = bounds.get_center() + Vector2(vertices[i].x * mirror, vertices[i].y).rotated(heading)
	var radii := PackedFloat32Array()
	for i in vertices.size():
		radii.append(_roll(seed, 79 + i * 7, CORNER_RADIUS, 225.0 + 25.0 * length_bias))
	return {"program": program, "recipe": StringName("%s_%08x" % [program, seed]), "anchors": vertices, "radii": radii}


## Marathon entry point: same contract as construct, but selects among the
## folded MARATHON_NAMES programs. Standard tiers never call this, so their
## seed-to-program mapping is untouched.
static func construct_marathon(index: int, seed: int, length_bias: float = 0.0, bounds := Rect2(-1300, -800, 2600, 1600)) -> Dictionary:
	var program := MARATHON_NAMES[posmod(index, MARATHON_NAMES.size())]
	var width := bounds.size.x * _roll(seed, 0x2A1, 0.83, 0.94)
	var height := bounds.size.y * _roll(seed, 0x2B7, 0.78, 0.88)
	var x := width * 0.5
	var y := height * 0.5
	var vertices := PackedVector2Array()
	match program:
		&"double_switchback":
			vertices = _double_switchback_anchors(seed, x, y, height)
		&"deep_comb":
			vertices = _deep_comb_anchors(seed, x, y, height)
		&"serpentine":
			vertices = _serpentine_anchors(seed, x, y, height)
		&"multi_comb":
			vertices = _multi_comb_anchors(seed, x, y, height)
		&"multi_lobe":
			vertices = _multi_lobe_anchors(seed, x, y, height)
	# Cut several convex corners into chamfers so the folded programs carry a
	# real angle mix instead of an all-90 spine. Corners are spaced at least one
	# edge apart, so no single straight is cut from both ends; the shared fitter
	# still rejects any stem that lands collinear with its neighbour.
	vertices = _compound_chamfer(vertices, seed, 4, false)
	var heading := _roll(seed, 0x2E9, 0.04, 0.08)
	if _roll_int(seed, 0x2F5, 2) == 0:
		heading = -heading
	var mirror := -1.0 if _roll_int(seed, 0x301, 2) == 0 else 1.0
	for i in vertices.size():
		vertices[i] = bounds.get_center() + Vector2(vertices[i].x * mirror, vertices[i].y).rotated(heading)
	# The folded programs share connector lines between adjacent legs, which
	# leaves collinear or duplicated anchor points. The corner fitter rejects
	# those as zero turns, so drop them after the transforms (collinearity is
	# preserved by mirror/rotate) and before the radii are seeded.
	vertices = _drop_collinear_anchors(vertices)
	var radii := PackedFloat32Array()
	for i in vertices.size():
		radii.append(_roll(seed, 0x30D + i * 7, CORNER_RADIUS, 225.0 + 25.0 * length_bias))
	return {"program": program, "recipe": StringName("%s_%08x" % [program, seed]), "anchors": vertices, "radii": radii}


## Double switchback: two full-height switchback spines side by side, joined
## through a narrow waist. Every anchor is a 90-degree corner (the switchback's
## own proven shape), so no near-180-degree turn ever reaches the fitter. The
## two spines plus the waist double the switchback's turn count inside the same
## room bounds.
static func _double_switchback_anchors(seed: int, x: float, y: float, height: float) -> PackedVector2Array:
	var spine := maxf(400.0, x * _roll(seed, 0x411, 0.28, 0.34))
	var waist := maxf(400.0, x * _roll(seed, 0x425, 0.14, 0.18))
	# Depth is capped so the two opposing notch floors keep at least 0.2h
	# (>> the 320u self-distance floor) between them.
	var depth := maxf(380.0, height * _roll(seed, 0x43B, 0.30, 0.38))
	if spine - waist * 0.5 < 380.0:
		spine = waist * 0.5 + 380.0
	return PackedVector2Array([
		Vector2(-x, -y),
		Vector2(-spine, -y),
		Vector2(-spine, -y + depth),
		Vector2(-waist * 0.5, -y + depth),
		Vector2(-waist * 0.5, -y),
		Vector2(waist * 0.5, -y),
		Vector2(waist * 0.5, -y + depth),
		Vector2(spine, -y + depth),
		Vector2(spine, -y),
		Vector2(x, -y),
		Vector2(x, y),
		Vector2(spine, y),
		Vector2(spine, y - depth),
		Vector2(waist * 0.5, y - depth),
		Vector2(waist * 0.5, y),
		Vector2(-waist * 0.5, y),
		Vector2(-waist * 0.5, y - depth),
		Vector2(-spine, y - depth),
		Vector2(-spine, y),
		Vector2(-x, y),
	])


## Asymmetric comb: the double-switchback topology with unequal notch depths
## (one side bites much deeper than the other) so it reads as a distinct
## layout. Kept inside the same self-distance limits the symmetric variant
## proved: waist >= 0.14x and the two notch floors together stay well clear.
static func _deep_comb_anchors(seed: int, x: float, y: float, height: float) -> PackedVector2Array:
	var spine := maxf(400.0, x * _roll(seed, 0x451, 0.28, 0.34))
	var waist := maxf(400.0, x * _roll(seed, 0x465, 0.15, 0.19))
	var deep := maxf(380.0, height * _roll(seed, 0x47B, 0.30, 0.38))
	var shallow := maxf(380.0, height * _roll(seed, 0x491, 0.16, 0.22))
	if spine - waist * 0.5 < 380.0:
		spine = waist * 0.5 + 380.0
	return PackedVector2Array([
		Vector2(-x, -y),
		Vector2(-spine, -y),
		Vector2(-spine, -y + shallow),
		Vector2(-waist * 0.5, -y + shallow),
		Vector2(-waist * 0.5, -y),
		Vector2(waist * 0.5, -y),
		Vector2(waist * 0.5, -y + deep),
		Vector2(spine, -y + deep),
		Vector2(spine, -y),
		Vector2(x, -y),
		Vector2(x, y),
		Vector2(spine, y),
		Vector2(spine, y - deep),
		Vector2(waist * 0.5, y - deep),
		Vector2(waist * 0.5, y),
		Vector2(-waist * 0.5, y),
		Vector2(-waist * 0.5, y - shallow),
		Vector2(-spine, y - shallow),
		Vector2(-spine, y),
		Vector2(-x, y),
	])




## Interlocking teeth on both sides: a barcode silhouette, distinct from the
## double switchback. Anchors span the full room so the lap reaches the
## marathon band; every leg clears the 375u the 180u fillet needs.
static func _serpentine_anchors(seed: int, x: float, y: float, height: float) -> PackedVector2Array:
	var teeth := 3
	var pitch := (2.0 * x) / float(teeth + 1)
	var half_slot := pitch * 0.22
	var depth := height * _roll(seed, 0x5A1, 0.26, 0.32)
	var pts := PackedVector2Array()
	pts.append(Vector2(-x, -y))
	for i in teeth:
		var cx := -x + pitch * float(i + 1)
		pts.append(Vector2(cx - half_slot, -y))
		pts.append(Vector2(cx - half_slot, -y + depth))
		pts.append(Vector2(cx + half_slot, -y + depth))
		pts.append(Vector2(cx + half_slot, -y))
	pts.append(Vector2(x, -y))
	pts.append(Vector2(x, y))
	for i in range(teeth - 1, -1, -1):
		var cx := -x + pitch * float(i + 1) + pitch * 0.5
		pts.append(Vector2(cx + half_slot, y))
		pts.append(Vector2(cx + half_slot, y - depth))
		pts.append(Vector2(cx - half_slot, y - depth))
		pts.append(Vector2(cx - half_slot, y))
	pts.append(Vector2(-x, y))
	return pts


## One-sided comb: repeated rectangular teeth along the bottom, flat return.
static func _multi_comb_anchors(seed: int, x: float, y: float, height: float) -> PackedVector2Array:
	var teeth := 3
	var pitch := (2.0 * x) / float(teeth + 1)
	var half_slot := pitch * 0.26
	var depth := height * _roll(seed, 0x6B1, 0.30, 0.38)
	var pts := PackedVector2Array()
	pts.append(Vector2(-x, -y))
	for i in teeth:
		var cx := -x + pitch * float(i + 1)
		pts.append(Vector2(cx - half_slot, -y))
		pts.append(Vector2(cx - half_slot, -y + depth))
		pts.append(Vector2(cx + half_slot, -y + depth))
		pts.append(Vector2(cx + half_slot, -y))
	pts.append(Vector2(x, -y))
	pts.append(Vector2(x, y))
	pts.append(Vector2(-x, y))
	return pts


## Four-lobe cross: deep pockets on every side, a silhouette no other program
## produces. The arm half-width keeps every leg clear of the fillet floor.
static func _multi_lobe_anchors(seed: int, x: float, y: float, _height: float) -> PackedVector2Array:
	var arm := minf(x, y) * _roll(seed, 0x7C1, 0.34, 0.44)
	return PackedVector2Array([
		Vector2(-arm, -y), Vector2(arm, -y), Vector2(arm, -arm), Vector2(x, -arm),
		Vector2(x, arm), Vector2(arm, arm), Vector2(arm, y), Vector2(-arm, y),
		Vector2(-arm, arm), Vector2(-x, arm), Vector2(-x, -arm), Vector2(-arm, -arm),
	])

static func round_corners(vertices: PackedVector2Array, radii: PackedFloat32Array) -> PackedVector2Array:

	return round_corners_profiled(vertices, radii, -1)["controls"]


## Round every corner with a plain circular fillet, except convex corners whose
## two legs are both at least MIN_PROFILE_LEG long: those get a seeded
## tangent-continuous two-arc opening/tightening profile when it fits, falling
## back to the circular fillet otherwise. Returns {controls, profiles} where
## `profiles` is a compact per-kind count (never an unbounded debug history).
static func round_corners_profiled(vertices: PackedVector2Array, radii: PackedFloat32Array, seed: int) -> Dictionary:
	var counts := {"circular": 0, "tightening": 0, "opening": 0, "symmetric": 0}
	var n := vertices.size()
	var winding := 1.0 if _polygon_area(vertices) > 0.0 else -1.0
	var leg_len: Array[float] = []
	for i in n:
		leg_len.append(vertices[i].distance_to(vertices[(i + 1) % n]))
	var entries := PackedVector2Array()
	var exits := PackedVector2Array()
	# Per-corner arc data: baseline -> {center, radial, turn}; profile ->
	# {center1, center2, join, phi, turn}. Both are resolved in a single pass so
	# adjacent corner setbacks never overlap (both use <=0.48 of a shared leg).
	var arcs: Array = []
	for i in n:
		var previous := vertices[posmod(i - 1, n)]
		var corner := vertices[i]
		var next := vertices[(i + 1) % n]
		var incoming := previous.direction_to(corner)
		var outgoing := corner.direction_to(next)
		var turn := incoming.angle_to(outgoing)
		var tangent_factor := tan(absf(turn) * 0.5)
		if tangent_factor < 0.001 or absf(turn) > PI - 0.01:
			return {"controls": PackedVector2Array(), "profiles": counts}
		var in_leg := leg_len[posmod(i - 1, n)]
		var out_leg := leg_len[i]
		var convex := (corner - previous).cross(next - corner) * winding > 0.001
		var profiled := false
		if seed >= 0 and convex and in_leg >= MIN_PROFILE_LEG and out_leg >= MIN_PROFILE_LEG:
			var base := maxf(radii[i], SECTIONS.MIN_PROFILE_RADIUS)
			# Keep both arc radii within [MIN_PROFILE_RADIUS, base] so the compound
			# curve never bulges further into the infield than the baseline
			# circular fillet of `base` would. Tightening/opening comes from the
			# radii differing, not from widening the corner.
			var r1 := lerpf(SECTIONS.MIN_PROFILE_RADIUS, base, _roll(seed, 0x7E1 + i * 7, 0.0, 1.0))
			var r2 := lerpf(SECTIONS.MIN_PROFILE_RADIUS, base, _roll(seed, 0x8F3 + i * 7, 0.0, 1.0))
			var split := lerpf(0.30, 0.70, _roll(seed, 0x9A5 + i * 7, 0.0, 1.0))
			var profile := SECTIONS.corner_profile(
				corner, incoming, outgoing, r1, r2, split,
				in_leg * 0.48, out_leg * 0.48
			)
			if bool(profile["accepted"]):
				entries.append(profile["entry"])
				exits.append(profile["exit"])
				arcs.append({
					"center1": profile["center1"],
					"center2": profile["center2"],
					"join": profile["join"],
					"phi": profile["phi"],
					"turn": profile["turn"],
				})
				counts[String(profile["kind"])] = int(counts.get(String(profile["kind"]), 0)) + 1
				profiled = true
		if not profiled:
			var radius := minf(radii[i], minf(in_leg, out_leg) * 0.48 / tangent_factor)
			if radius < CORNER_RADIUS:
				return {"controls": PackedVector2Array(), "profiles": counts}
			var entry := corner - incoming * radius * tangent_factor
			var exit := corner + outgoing * radius * tangent_factor
			entries.append(entry)
			exits.append(exit)
			arcs.append({
				"center": entry + incoming.rotated(signf(turn) * PI * 0.5) * radius,
				"radial": entry - (entry + incoming.rotated(signf(turn) * PI * 0.5) * radius),
				"turn": turn,
			})
			counts["circular"] += 1
	var controls := PackedVector2Array()
	for i in n:
		var arc: Dictionary = arcs[i]
		if arc.has("center1"):
			controls.append_array(SECTIONS.arc_samples(arc["center1"], entries[i], float(arc["phi"])))
			controls.append_array(SECTIONS.arc_samples(arc["center2"], arc["join"], float(arc["turn"]) - float(arc["phi"])))
		else:
			var center: Vector2 = arc["center"]
			var radial: Vector2 = arc["radial"]
			var turn: float = arc["turn"]
			var arc_steps := maxi(4, ceili(radial.length() * absf(turn) / CONTROL_SPACING))
			for step in arc_steps:
				controls.append(center + radial.rotated(turn * float(step) / float(arc_steps)))
		var next_entry := entries[(i + 1) % n]
		var line_steps := maxi(1, ceili(exits[i].distance_to(next_entry) / CONTROL_SPACING))
		for step in line_steps:
			controls.append(exits[i].lerp(next_entry, float(step) / float(line_steps)))
	return {"controls": controls, "profiles": counts}


static func _roll(seed: int, salt: int, minimum: float, maximum: float) -> float:
	return lerpf(minimum, maximum, float(_hash32(seed ^ MACRO_SALT ^ salt)) / 2147483647.0)


static func _roll_int(seed: int, salt: int, maximum: int) -> int:
	return posmod(_hash32(seed ^ MACRO_SALT ^ salt), maximum)


static func _hash32(value: int) -> int:
	var mixed := value & 0x7FFFFFFF
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
	return (mixed ^ (mixed >> 16)) & 0x7FFFFFFF


static func _compound_chamfer(vertices: PackedVector2Array, seed: int, maximum: int = 2, require_roll: bool = true) -> PackedVector2Array:
	# Cut convex corners into unequal chamfers: corner -> entry vertex, a
	# diagonal stem, an exit vertex. The diagonal gains a third heading family
	# (>=11 deg off both legs) while the two longest straight corridors and the
	# concave bays stay intact. Chosen corners never share an edge, so no single
	# straight is cut from both ends. Standard programs use the legacy 1-2 cut;
	# the folded marathon programs pass a higher `maximum` for a real angle mix.
	var n := vertices.size()
	if n < 4:
		return vertices
	var area := _polygon_area(vertices)
	var winding := 1.0 if area > 0.0 else -1.0
	var edge_len: Array[float] = []
	for i in n:
		edge_len.append(vertices[i].distance_to(vertices[(i + 1) % n]))
	var eligible: Array[int] = []
	for i in n:
		var prev := vertices[posmod(i - 1, n)]
		var corner := vertices[i]
		var next := vertices[(i + 1) % n]
		if (corner - prev).cross(next - corner) * winding <= 0.001:
			continue
		if edge_len[posmod(i - 1, n)] >= MIN_CHAMFER_LEG and edge_len[i] >= MIN_CHAMFER_LEG:
			eligible.append(i)
	if eligible.is_empty():
		return vertices
	var chosen: Dictionary = {}
	var start := _roll_int(seed, 0x6D, eligible.size())
	chosen[eligible[start]] = true
	if require_roll:
		if _roll_int(seed, 0x6B, 2) == 1:
			for k in range(1, eligible.size()):
				var candidate: int = eligible[(start + k) % eligible.size()]
				var circular := mini(absi(candidate - eligible[start]), n - absi(candidate - eligible[start]))
				if circular >= 2:
					chosen[candidate] = true
					break
	else:
		var offset := 1
		while chosen.size() < maximum and offset < eligible.size():
			var candidate: int = eligible[(start + offset) % eligible.size()]
			offset += 1
			var separated := true
			for picked: int in chosen:
				var circular := mini(absi(candidate - picked), n - absi(candidate - picked))
				if circular < 2:
					separated = false
					break
			if separated:
				chosen[candidate] = true
	var result := PackedVector2Array()
	for i in n:
		if not chosen.has(i):
			result.append(vertices[i])
			continue
		var prev := vertices[posmod(i - 1, n)]
		var corner := vertices[i]
		var next := vertices[(i + 1) % n]
		var incoming := prev.direction_to(corner)
		var outgoing := corner.direction_to(next)
		var s_in := _roll(seed, 0x71 + i * 3, 0.24, 0.32) * edge_len[posmod(i - 1, n)]
		var s_out := _roll(seed, 0x89 + i * 3, 0.28, 0.38) * edge_len[i]
		result.append(corner - incoming * s_in)
		result.append(corner + outgoing * s_out)
	return result


static func _polygon_area(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in points.size():
		total += points[i].cross(points[(i + 1) % points.size()])
	return total * 0.5


## Remove anchors whose position duplicates their predecessor or whose turn is
## near-collinear, so the corner fitter only sees real corners. The folded
## marathon programs emit both: shared connector lines and repeated leg ends.
static func _drop_collinear_anchors(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 4:
		return points
	var deduped := PackedVector2Array()
	for index in points.size():
		var current := points[index]
		if deduped.is_empty() or current.distance_squared_to(deduped[deduped.size() - 1]) > 0.01:
			deduped.append(current)
	var result := PackedVector2Array()
	var count := deduped.size()
	for index in count:
		var previous := deduped[posmod(index - 1, count)]
		var current := deduped[index]
		var next := deduped[(index + 1) % count]
		var turn := absf(previous.direction_to(current).angle_to(current.direction_to(next)))
		if turn > 0.02:
			result.append(current)
	if result.size() < 4:
		return points
	return result
