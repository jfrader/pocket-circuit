class_name TrackWidthProfile
## Per-sample road half-width fitted to an accepted route. Width never rejects a
## route: a seeded desired width is clamped to what the geometry affords at each
## centerline sample (turn radius, nearest other leg, room wall), then eased so
## the island keeps most of its flat-road area. Pure and deterministic.

const GEOMETRY := preload("res://scripts/race/track_builder_geometry.gd")

const MIN_HALF_WIDTH := GEOMETRY.HALF_WIDTH
const MAX_HALF_WIDTH := 240.0
const HULL_RADIUS := 22.0
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
	return lerpf(MIN_SEEDED_AMPLITUDE, MAX_HALF_WIDTH - MIN_HALF_WIDTH, _unit(seed, 2))


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
	widths.fill(MIN_HALF_WIDTH)
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
	var w := MIN_HALF_WIDTH
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


## Half-width of the sample nearest to `point`; MIN_HALF_WIDTH for flat roads.
static func at_point(centerline: PackedVector2Array, widths: PackedFloat32Array, point: Vector2) -> float:
	if widths.size() != centerline.size() or widths.is_empty():
		return MIN_HALF_WIDTH
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
		var cap := minf(MAX_HALF_WIDTH, _local_radius(centerline, i) - HULL_RADIUS)
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


static func _fit(arc: PackedFloat32Array, caps: PackedFloat32Array, seed: int, amplitude: float) -> PackedFloat32Array:
	var n := caps.size()
	var total: float = arc[n]
	var f1 := 1.0 + floorf(_unit(seed, 3) * 3.0)
	var f2 := 3.0 + floorf(_unit(seed, 4) * 4.0)
	var phase1 := _unit(seed, 5) * TAU
	var phase2 := _unit(seed, 6) * TAU
	var widths := PackedFloat32Array()
	widths.resize(n)
	for i in n:
		var t := arc[i] / total
		var wave := 0.65 * (0.5 + 0.5 * sin(TAU * f1 * t + phase1)) + 0.35 * (0.5 + 0.5 * sin(TAU * f2 * t + phase2))
		widths[i] = clampf(MIN_HALF_WIDTH + amplitude * wave, MIN_HALF_WIDTH, maxf(MIN_HALF_WIDTH, caps[i]))
	return widths


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
