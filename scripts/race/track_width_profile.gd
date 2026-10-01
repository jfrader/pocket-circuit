class_name TrackWidthProfile
## Per-sample road half-width fitted to an accepted route. Width never rejects a
## route: most of the lap keeps today's width, with a few seeded swells where the
## geometry affords them (turn radius, nearest other leg, room wall) and one
## pinch, eased so the island keeps most of its flat-road area. Pure and
## deterministic.

const GEOMETRY := preload("res://scripts/race/track_builder_geometry.gd")

## Today's fixed road; the widening wave starts here.
const BASE_HALF_WIDTH := GEOMETRY.HALF_WIDTH
const MAX_HALF_WIDTH := 240.0
## Narrowest pinch. Keeps the shortcut lane (70 + 26), the technical strip (92)
## and grip patches (up to 54) inside the road.
const NARROW_HALF_WIDTH := 100.0
## Sporadic width events: 1-2 swells and one pinch per lap; everywhere else the
## road keeps the base width.
const SECOND_SWELL_CHANCE := 0.5
const SWELL_ARC := Vector2(700.0, 1400.0)
const PINCH_ARC := Vector2(400.0, 700.0)
## Short laps shrink the events so at most about 38% of any lap varies.
const SWELL_MAX_LAP_SHARE := 0.15
const PINCH_MAX_LAP_SHARE := 0.08
## Swells vary between this share of the amplitude and all of it.
const SWELL_DEPTH_SPREAD := 0.6
## A swell only goes where the route affords at least this much extra width.
const MIN_SWELL_ROOM := 20.0
const PINCH_DEPTH_SHARE := 0.2
const EVENT_CANDIDATES := 12
const EVENT_GAP := 300.0
## No pinch reaches this close to the finish line, so the start grid keeps a
## full-width straight.
const FINISH_CLEAR_ARC := 500.0
const HULL_RADIUS := 22.0
## Tightest inner road-edge radius allowed. Today's 125 road at its 180 minimum
## fillet leaves 55; tighter, the offset normals cross and the island folds into
## the road.
const MIN_INNER_EDGE_RADIUS := 55.0
const LEG_GAP := 70.0
const WALL_GUARD := 20.0
const NONLOCAL_ARC := 900.0
const RADIUS_SPAN := 3
const CAP_SMOOTH_ARC := 350.0
const ISLAND_KEEP := 0.6
const ISLAND_EASE_STEPS := 5
const ISLAND_EASE := 0.75
const FLAT_SHARE := 0.25
const MIN_SEEDED_AMPLITUDE := 30.0
const SALT := 0x5D1A7E

## Generation option values for `road_width`.
const MODE_FLAT := &"flat"
const MODE_SEEDED := &"seeded"


static func amplitude_for_seed(seed: int) -> float:
	if _unit(seed, 1) < FLAT_SHARE:
		return 0.0
	return lerpf(MIN_SEEDED_AMPLITUDE, MAX_HALF_WIDTH - BASE_HALF_WIDTH, _unit(seed, 2))


## Resolves a `road_width` generation option: MODE_FLAT (default), MODE_SEEDED,
## or a numeric amplitude.
static func amplitude_for_option(option: Variant, seed: int) -> float:
	if option is float or option is int:
		return maxf(0.0, float(option))
	if StringName(str(option)) == MODE_SEEDED:
		return amplitude_for_seed(seed)
	return 0.0


static func flat(count: int) -> PackedFloat32Array:
	var widths := PackedFloat32Array()
	widths.resize(count)
	widths.fill(BASE_HALF_WIDTH)
	return widths


static func build(centerline: PackedVector2Array, seed: int, room_polygon: PackedVector2Array, amplitude: float) -> PackedFloat32Array:
	var n := centerline.size()
	if n < 8 or amplitude <= 0.001:
		return flat(n)
	var arc := _closed_arc(centerline)
	var caps := _smooth_caps(affordable_caps(centerline, room_polygon, arc), arc)
	var flat_island := absf(GEOMETRY.polygon_area(_inner_edge(centerline, flat(n))))
	var a := amplitude
	var widths := _fit(arc, caps, seed, a)
	for step in ISLAND_EASE_STEPS:
		if absf(GEOMETRY.polygon_area(_inner_edge(centerline, widths))) >= flat_island * ISLAND_KEEP:
			break
		a *= ISLAND_EASE
		widths = _fit(arc, caps, seed, a)
	return widths


static func widest(widths: PackedFloat32Array) -> float:
	var w := BASE_HALF_WIDTH
	for value: float in widths:
		w = maxf(w, value)
	return w


## Line2D width curve for a closed road through `centerline`. Godot samples it
## by distance along the line (closing segment included), so points are placed
## at each sample's arc fraction and scaled against the widest sample.
static func line_width_curve(centerline: PackedVector2Array, widths: PackedFloat32Array) -> Curve:
	var arc := _closed_arc(centerline)
	var total: float = arc[centerline.size()]
	var peak := widest(widths)
	var curve := Curve.new()
	curve.bake_resolution = maxi(256, centerline.size() * 2)
	for index in centerline.size():
		curve.add_point(Vector2(arc[index] / total, widths[index] / peak), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(1.0, widths[0] / peak), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return curve


## Half-width of the sample nearest to `point`; BASE_HALF_WIDTH for flat roads.
static func at_point(centerline: PackedVector2Array, widths: PackedFloat32Array, point: Vector2) -> float:
	if widths.size() != centerline.size() or widths.is_empty():
		return BASE_HALF_WIDTH
	var best := 0
	var best_distance := INF
	for index in centerline.size():
		var distance := point.distance_squared_to(centerline[index])
		if distance < best_distance:
			best_distance = distance
			best = index
	return widths[best]


## Largest half-width each sample can take without pinching a turn, merging
## with another leg or crossing the room wall.
static func affordable_caps(centerline: PackedVector2Array, room_polygon: PackedVector2Array, arc: PackedFloat32Array) -> PackedFloat32Array:
	var n := centerline.size()
	var total: float = arc[n]
	var reach := MAX_HALF_WIDTH * 2.0 + LEG_GAP
	var buckets := _point_buckets(centerline, reach)
	var caps := PackedFloat32Array()
	caps.resize(n)
	for i in n:
		var cap := minf(MAX_HALF_WIDTH, _local_radius(centerline, i) - maxf(HULL_RADIUS, MIN_INNER_EDGE_RADIUS))
		var cell := Vector2i(floori(centerline[i].x / reach), floori(centerline[i].y / reach))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for j: int in buckets.get(cell + Vector2i(dx, dy), []):
					var along := absf(arc[i] - arc[j])
					if minf(along, total - along) < NONLOCAL_ARC:
						continue
					cap = minf(cap, (centerline[i].distance_to(centerline[j]) - LEG_GAP) * 0.5)
		if not room_polygon.is_empty():
			cap = minf(cap, _distance_to_polygon(centerline[i], room_polygon) - WALL_GUARD)
		caps[i] = cap
	return caps


## Most of the lap keeps the base width. A few seeded events swell or pinch it:
## swells go where the route affords the most extra width, the pinch stays off
## the start/finish straight and clear of the swells.
static func _fit(arc: PackedFloat32Array, caps: PackedFloat32Array, seed: int, amplitude: float) -> PackedFloat32Array:
	var n := caps.size()
	var total: float = arc[n]
	var events := _place_events(arc, caps, seed, amplitude)
	var widths := PackedFloat32Array()
	widths.resize(n)
	for i in n:
		var swell := 0.0
		var pinch := 0.0
		for event: Dictionary in events:
			var along := fposmod(arc[i] - float(event["start"]), total)
			if along > float(event["length"]):
				continue
			var shape := 0.5 - 0.5 * cos(TAU * along / float(event["length"]))
			if float(event["depth"]) > 0.0:
				swell = maxf(swell, float(event["depth"]) * shape)
			else:
				pinch = maxf(pinch, -float(event["depth"]) * shape)
		widths[i] = clampf(BASE_HALF_WIDTH + swell, BASE_HALF_WIDTH, maxf(BASE_HALF_WIDTH, caps[i])) - pinch
	return widths


## Events as {start, length, depth}: positive depth swells, negative pinches.
static func _place_events(arc: PackedFloat32Array, caps: PackedFloat32Array, seed: int, amplitude: float) -> Array[Dictionary]:
	var total: float = arc[caps.size()]
	var events: Array[Dictionary] = []
	var swell_count := 1 + int(_unit(seed, 3) < SECOND_SWELL_CHANCE)
	var candidates: Array[Dictionary] = []
	for k in EVENT_CANDIDATES:
		var length := minf(lerpf(SWELL_ARC.x, SWELL_ARC.y, _unit(seed, 20 + k)), total * SWELL_MAX_LAP_SHARE)
		var start := total * _unit(seed, 40 + k)
		candidates.append({"start": start, "length": length, "room": _mean_cap(arc, caps, start, length) - BASE_HALF_WIDTH})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["room"]) > float(b["room"]))
	for candidate: Dictionary in candidates:
		if events.size() >= swell_count or float(candidate["room"]) < MIN_SWELL_ROOM:
			break
		if _overlaps(candidate, events, total):
			continue
		candidate["depth"] = amplitude * lerpf(SWELL_DEPTH_SPREAD, 1.0, _unit(seed, 60 + events.size()))
		events.append(candidate)
	var pinch_depth := minf(BASE_HALF_WIDTH - NARROW_HALF_WIDTH, amplitude * PINCH_DEPTH_SHARE)
	for k in EVENT_CANDIDATES:
		var length := minf(lerpf(PINCH_ARC.x, PINCH_ARC.y, _unit(seed, 80 + k)), total * PINCH_MAX_LAP_SHARE)
		var start := total * _unit(seed, 100 + k)
		var center := fposmod(start + length * 0.5, total)
		if minf(center, total - center) < FINISH_CLEAR_ARC + length * 0.5:
			continue
		var pinch := {"start": start, "length": length, "depth": -pinch_depth}
		if not _overlaps(pinch, events, total):
			events.append(pinch)
			break
	return events


static func _mean_cap(arc: PackedFloat32Array, caps: PackedFloat32Array, start: float, length: float) -> float:
	var total: float = arc[caps.size()]
	var sum := 0.0
	var count := 0
	for i in caps.size():
		if fposmod(arc[i] - start, total) <= length:
			sum += minf(caps[i], MAX_HALF_WIDTH)
			count += 1
	return sum / float(count) if count > 0 else BASE_HALF_WIDTH


static func _overlaps(candidate: Dictionary, events: Array[Dictionary], total: float) -> bool:
	for event: Dictionary in events:
		var a_start := float(candidate["start"]) - EVENT_GAP
		var a_length := float(candidate["length"]) + EVENT_GAP * 2.0
		var b_start := float(event["start"])
		var b_length := float(event["length"])
		if fposmod(b_start - a_start, total) < a_length or fposmod(a_start - b_start, total) < b_length:
			return true
	return false


## Sliding minimum then box blur over CAP_SMOOTH_ARC, never above the raw cap,
## so the road tapers into tight spots instead of stepping.
static func _smooth_caps(caps: PackedFloat32Array, arc: PackedFloat32Array) -> PackedFloat32Array:
	var n := caps.size()
	var half := maxi(1, ceili(CAP_SMOOTH_ARC * 0.5 / (arc[n] / float(n))))
	var minned := PackedFloat32Array()
	minned.resize(n)
	for i in n:
		var m := caps[i]
		for k in range(-half, half + 1):
			m = minf(m, caps[posmod(i + k, n)])
		minned[i] = m
	var smoothed := PackedFloat32Array()
	smoothed.resize(n)
	for i in n:
		var sum := 0.0
		for k in range(-half, half + 1):
			sum += minned[posmod(i + k, n)]
		smoothed[i] = minf(sum / float(half * 2 + 1), caps[i])
	return smoothed


static func _inner_edge(centerline: PackedVector2Array, widths: PackedFloat32Array) -> PackedVector2Array:
	var edges := GEOMETRY.corridor_edges(centerline, widths)
	var left: PackedVector2Array = edges["left"]
	var right: PackedVector2Array = edges["right"]
	return left if absf(GEOMETRY.polygon_area(left)) < absf(GEOMETRY.polygon_area(right)) else right


static func _point_buckets(points: PackedVector2Array, cell_size: float) -> Dictionary:
	var buckets := {}
	for index in points.size():
		var key := Vector2i(floori(points[index].x / cell_size), floori(points[index].y / cell_size))
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(index)
	return buckets


static func _local_radius(line: PackedVector2Array, i: int) -> float:
	var n := line.size()
	var a := line[posmod(i - RADIUS_SPAN, n)]
	var b := line[i]
	var c := line[(i + RADIUS_SPAN) % n]
	var area2 := absf((b - a).cross(c - a))
	if area2 < 0.01:
		return INF
	return a.distance_to(b) * b.distance_to(c) * a.distance_to(c) / (2.0 * area2)


## Cumulative arc length including the closing segment: size n + 1.
static func _closed_arc(line: PackedVector2Array) -> PackedFloat32Array:
	var arc := PackedFloat32Array([0.0])
	for i in line.size():
		arc.append(arc[i] + line[i].distance_to(line[(i + 1) % line.size()]))
	return arc


static func _distance_to_polygon(point: Vector2, polygon: PackedVector2Array) -> float:
	var best := INF
	for i in polygon.size():
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, polygon[i], polygon[(i + 1) % polygon.size()])))
	return best


static func _unit(seed: int, salt: int) -> float:
	var mixed := (seed ^ SALT ^ (salt * 0x9E3779B1)) & 0x7FFFFFFF
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
	return float((mixed ^ (mixed >> 16)) & 0x7FFFFFFF) / 2147483647.0
