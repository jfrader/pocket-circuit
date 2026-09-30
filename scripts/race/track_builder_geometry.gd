class_name TrackBuilderGeometry
## Pure loop/corridor math used by TrackBuilderCore. No nodes, no textures.

const HALF_WIDTH := 125.0
const CURVE_SAMPLING := preload("res://scripts/race/track_curve_sampling.gd")


## Arc-length-uniform centerline via the shared sampler: variable count (>=260),
## closed, no endpoint duplicate, maximum spacing 35.
static func sample_centerline(controls: PackedVector2Array) -> PackedVector2Array:
	return CURVE_SAMPLING.sample(controls)


static func corridor_edges(centerline: PackedVector2Array, half_widths: PackedFloat32Array = PackedFloat32Array()) -> Dictionary:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var count := centerline.size()
	var variable := half_widths.size() == count
	for index in count:
		var tangent := (centerline[(index + 1) % count] - centerline[(index - 1 + count) % count]).normalized()
		var normal := tangent.rotated(PI * 0.5)
		var half := half_widths[index] if variable else HALF_WIDTH
		left.append(centerline[index] + normal * half)
		right.append(centerline[index] - normal * half)
	return {"left": left, "right": right, "centerline": centerline}

static func rounded_rect_points(center: Vector2, size: Vector2, radius: float, corner_segments: int) -> PackedVector2Array:
	var half := size * 0.5 - Vector2(radius, radius)
	var points := PackedVector2Array()
	for corner: Dictionary in [
		{"c": center + Vector2(half.x, half.y), "start": 0.0},
		{"c": center + Vector2(-half.x, half.y), "start": PI * 0.5},
		{"c": center - half, "start": PI},
		{"c": center + Vector2(half.x, -half.y), "start": PI * 1.5},
	]:
		for seg in corner_segments + 1:
			var angle: float = corner["start"] + PI * 0.5 * float(seg) / float(corner_segments)
			points.append(corner["c"] + Vector2(cos(angle), sin(angle)) * radius)
	return points


static func polygon_area(points: PackedVector2Array) -> float:
	var total := 0.0
	for index in points.size():
		var next := (index + 1) % points.size()
		total += points[index].x * points[next].y - points[next].x * points[index].y
	return total * 0.5


static func outset_polygon(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var contours: Array[PackedVector2Array] = Geometry2D.offset_polygon(points, distance, Geometry2D.JOIN_ROUND)
	var largest := PackedVector2Array()
	var largest_area := 0.0
	for contour: PackedVector2Array in contours:
		# An outward offset folds over a concave notch, and Clipper can hand that
		# folded contour back self-intersecting. Flatten it before it feeds a
		# ConcavePolygonShape2D or a raised rim.
		var cleaned := simple_loop(contour)
		if cleaned.is_empty():
			continue
		var area := absf(polygon_area(cleaned))
		if area > largest_area:
			largest = cleaned
			largest_area = area
	return largest if not largest.is_empty() else points


static func simple_loop(points: PackedVector2Array) -> PackedVector2Array:
	# Union a possibly self-intersecting loop with itself to split folds into
	# simple pieces, drop near-duplicate points, then keep the largest clean piece
	# (the smaller ones are offset/clip artifacts). Returns empty when nothing
	# survives, so callers can fall back to their original contour.
	var resolved: Array[PackedVector2Array] = Geometry2D.intersect_polygons(points, points)
	var largest := PackedVector2Array()
	var largest_area := 0.0
	for piece: PackedVector2Array in (resolved if not resolved.is_empty() else [points]):
		var cleaned := simplify_loop(deduplicate_loop(piece))
		if cleaned.size() < 3 or has_self_intersection(cleaned):
			continue
		var area := absf(polygon_area(cleaned))
		if area > largest_area:
			largest = cleaned
			largest_area = area
	return largest


static func simplify_loop(points: PackedVector2Array, maximum_deviation: float = 0.05) -> PackedVector2Array:
	# Bound error against every skipped point, not just its original neighbors:
	# independently removing locally-flat vertices can erase an entire dense arc.
	var count := points.size()
	if count < 3:
		return points
	var result := PackedVector2Array([points[0]])
	var skipped := PackedVector2Array()
	for index in range(1, count):
		var before := result[result.size() - 1]
		var current := points[index]
		var after := points[(index + 1) % count]
		skipped.append(current)
		var removable := (current - before).dot(after - current) > 0.0
		for point: Vector2 in skipped:
			if point_to_segment_distance(point, before, after) > maximum_deviation:
				removable = false
				break
		if removable:
			continue
		result.append(current)
		skipped.clear()
	return result


static func simple_island_loop(points: PackedVector2Array) -> PackedVector2Array:
	# The central island can fold at concave corners; keep its largest simple piece.
	var cleaned := simple_loop(points)
	return cleaned if not cleaned.is_empty() else points


static func simple_boundary_loop(points: PackedVector2Array, centerline: PackedVector2Array) -> PackedVector2Array:
	return simple_corridor_boundary_loop(points, centerline, true)


static func simple_inner_boundary_loop(points: PackedVector2Array, centerline: PackedVector2Array) -> PackedVector2Array:
	return simple_corridor_boundary_loop(points, centerline, false)


static func simple_corridor_boundary_loop(_points: PackedVector2Array, centerline: PackedVector2Array, select_outer: bool) -> PackedVector2Array:
	# Build the joined stroke through Clipper rather than trusting raw vertex
	# normals. A closed polyline yields simple contours on both sides; comparing
	# them with centerline area selects the matching physical road edge.
	var stroke_contours: Array[PackedVector2Array] = Geometry2D.offset_polyline(
		centerline,
		HALF_WIDTH,
		Geometry2D.JOIN_ROUND,
		Geometry2D.END_JOINED
	)
	var pieces: Array[PackedVector2Array] = []
	for contour: PackedVector2Array in stroke_contours:
		var resolved: Array[PackedVector2Array] = Geometry2D.intersect_polygons(contour, contour)
		pieces.append_array(resolved if not resolved.is_empty() else [contour])
	var centerline_area := absf(polygon_area(centerline))
	var result := PackedVector2Array()
	var largest_area := 0.0
	for piece: PackedVector2Array in pieces:
		# Round-join offset densifies the contour with near-collinear points that
		# read as self-intersections on long loops; simplify first so the join
		# does not fold a valid corridor into an empty boundary.
		var cleaned := simplify_loop(deduplicate_loop(piece), 0.05)
		if cleaned.size() < 3 or has_self_intersection(cleaned):
			continue
		var area := absf(polygon_area(cleaned))
		if (area > centerline_area) != select_outer:
			continue
		if not loop_hugs_centerline(cleaned, centerline):
			continue
		if area > largest_area:
			result = cleaned
			largest_area = area
	return result


## Road edge for a variable-width corridor: the per-sample offset edge itself.
## TrackWidthProfile keeps every width below the local turn radius, so it cannot
## fold; if it ever does, fall back to the fixed-width contour.
static func variable_boundary_loop(points: PackedVector2Array, centerline: PackedVector2Array, select_outer: bool) -> PackedVector2Array:
	var cleaned := simplify_loop(deduplicate_loop(points), 0.05)
	if cleaned.size() >= 3 and not has_self_intersection(cleaned):
		return cleaned
	push_warning("TrackBuilderGeometry: variable road edge folded; using the fixed-width contour")
	return simple_corridor_boundary_loop(points, centerline, select_outer)


static func deduplicate_loop(points: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector2 in points:
		if result.is_empty() or point.distance_squared_to(result[result.size() - 1]) > 0.01:
			result.append(point)
	if result.size() > 1 and result[0].distance_squared_to(result[result.size() - 1]) <= 0.01:
		result.remove_at(result.size() - 1)
	return result


static func has_self_intersection(points: PackedVector2Array) -> bool:
	for first in points.size():
		var first_next := (first + 1) % points.size()
		for second in range(first + 1, points.size()):
			var second_next := (second + 1) % points.size()
			if first_next == second or second_next == first:
				continue
			if Geometry2D.segment_intersects_segment(points[first], points[first_next], points[second], points[second_next]) != null:
				return true
	return false


static func loop_hugs_centerline(loop: PackedVector2Array, centerline: PackedVector2Array) -> bool:
	for index in loop.size():
		var from := loop[index]
		var to := loop[(index + 1) % loop.size()]
		for fraction: float in [0.0, 0.5]:
			var sample := from.lerp(to, fraction)
			var nearest := INF
			for center_index in centerline.size():
				nearest = minf(nearest, point_to_segment_distance(sample, centerline[center_index], centerline[(center_index + 1) % centerline.size()]))
			if nearest < HALF_WIDTH * 0.62 or nearest > HALF_WIDTH * 1.42:
				return false
	return true


static func arc_lengths(centerline: PackedVector2Array) -> PackedFloat32Array:
	var arc := PackedFloat32Array()
	arc.append(0.0)
	var running := 0.0
	for index in range(1, centerline.size()):
		running += centerline[index].distance_to(centerline[index - 1])
		arc.append(running)
	return arc


static func sample_at_arc(centerline: PackedVector2Array, arc: PackedFloat32Array, target: float) -> Vector2:
	for index in range(1, arc.size()):
		if arc[index] >= target:
			var fraction := (target - arc[index - 1]) / maxf(arc[index] - arc[index - 1], 0.001)
			return centerline[index - 1].lerp(centerline[index], fraction)
	return centerline[centerline.size() - 1]


static func tangent_at_arc(centerline: PackedVector2Array, arc: PackedFloat32Array, target: float) -> Vector2:
	for index in range(1, arc.size()):
		if arc[index] >= target:
			return (centerline[index] - centerline[index - 1]).normalized()
	return (centerline[0] - centerline[centerline.size() - 1]).normalized()


static func rect_points(center: Vector2, size: Vector2) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([
		center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y), center + Vector2(-half.x, half.y),
	])

static func turn_strength(centerline: PackedVector2Array, index: int, span: int) -> float:
	var count := centerline.size()
	var behind := (centerline[index] - centerline[posmod(index - span, count)]).normalized()
	var ahead := (centerline[posmod(index + span, count)] - centerline[index]).normalized()
	return absf(behind.angle_to(ahead))


static func cyclic_index_distance(first: int, second: int, count: int) -> int:
	var direct := absi(first - second)
	return mini(direct, count - direct)

static func sample_tangent(centerline: PackedVector2Array, index: int) -> Vector2:
	return (centerline[posmod(index + 1, centerline.size())] - centerline[posmod(index - 1, centerline.size())]).normalized()

static func point_to_segment_distance(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment := to - from
	if segment.length_squared() < 0.001:
		return point.distance_to(from)
	var fraction := clampf((point - from).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(from + segment * fraction)

static func footprint_projected_extent(footprint_size: Vector2, shape_kind: StringName, rotation: float, axis: Vector2) -> float:
	if shape_kind == &"circle":
		return maxf(footprint_size.x, footprint_size.y) * 0.5
	var normalized_axis := axis.normalized()
	var local_x := Vector2.RIGHT.rotated(rotation)
	var local_y := Vector2.DOWN.rotated(rotation)
	return absf(normalized_axis.dot(local_x)) * footprint_size.x * 0.5 + absf(normalized_axis.dot(local_y)) * footprint_size.y * 0.5


static func crossing_path(centerline: PackedVector2Array, center_index: int, half_width: float) -> PackedVector2Array:
	var normal := sample_tangent(centerline, center_index).rotated(PI * 0.5)
	return PackedVector2Array([
		centerline[center_index] - normal * half_width,
		centerline[center_index] + normal * half_width,
	])


static func clear_of_points(point: Vector2, points: PackedVector2Array, clearance: float) -> bool:
	for other: Vector2 in points:
		if point.distance_to(other) < clearance:
			return false
	return true


static func clear_of_occupied(point: Vector2, radius: float, occupied: Array[Dictionary]) -> bool:
	for entry: Dictionary in occupied:
		if point.distance_to(entry["position"]) < radius + float(entry["radius"]) + 7.0:
			return false
	return true


static func line_sweep_clears_footprint(
		line: PackedVector2Array,
		center: Vector2,
		size: Vector2,
		shape_kind: StringName,
		rotation: float,
		hull_radius: float
) -> bool:
	if line.size() < 2:
		return true
	if shape_kind == &"circle":
		var radius := maxf(size.x, size.y) * 0.5 + hull_radius
		var bounds := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
		for index in line.size():
			if not bounds.intersects(Rect2(line[index], line[(index + 1) % line.size()] - line[index]).abs(), true):
				continue
			if point_to_segment_distance(center, line[index], line[(index + 1) % line.size()]) < radius:
				return false
		return true
	var expanded_half_size := size * 0.5 + Vector2.ONE * hull_radius
	var radius := expanded_half_size.length()
	var bounds := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	for index in line.size():
		if not bounds.intersects(Rect2(line[index], line[(index + 1) % line.size()] - line[index]).abs(), true):
			continue
		var local_from := (line[index] - center).rotated(-rotation)
		var local_to := (line[(index + 1) % line.size()] - center).rotated(-rotation)
		if segment_intersects_axis_rect(local_from, local_to, expanded_half_size):
			return false
	return true


## line_sweep_clears_footprint for a variable-width road: each closed-loop
## segment is inflated by its wider endpoint's half-width plus `clearance`.
static func variable_sweep_clears_footprint(
		line: PackedVector2Array,
		half_widths: PackedFloat32Array,
		center: Vector2,
		size: Vector2,
		shape_kind: StringName,
		rotation: float,
		clearance: float
) -> bool:
	var count := line.size()
	if count < 2 or half_widths.size() != count:
		return line_sweep_clears_footprint(line, center, size, shape_kind, rotation, HALF_WIDTH + clearance)
	for index in count:
		var next := (index + 1) % count
		var from := line[index]
		var to := line[next]
		var hull := maxf(half_widths[index], half_widths[next]) + clearance
		var reach := maxf(size.x, size.y) * 0.5 + hull if shape_kind == &"circle" else (size * 0.5 + Vector2.ONE * hull).length()
		if not Rect2(center - Vector2.ONE * reach, Vector2.ONE * reach * 2.0).intersects(Rect2(from, to - from).abs(), true):
			continue
		if shape_kind == &"circle":
			if point_to_segment_distance(center, from, to) < maxf(size.x, size.y) * 0.5 + hull:
				return false
		elif segment_intersects_axis_rect((from - center).rotated(-rotation), (to - center).rotated(-rotation), size * 0.5 + Vector2.ONE * hull):
			return false
	return true


static func segment_intersects_axis_rect(from: Vector2, to: Vector2, half_size: Vector2) -> bool:
	if (
		minf(from.x, to.x) > half_size.x
		or maxf(from.x, to.x) < -half_size.x
		or minf(from.y, to.y) > half_size.y
		or maxf(from.y, to.y) < -half_size.y
	):
		return false
	if absf(from.x) <= half_size.x and absf(from.y) <= half_size.y:
		return true
	if absf(to.x) <= half_size.x and absf(to.y) <= half_size.y:
		return true
	var top_left := Vector2(-half_size.x, -half_size.y)
	var top_right := Vector2(half_size.x, -half_size.y)
	var bottom_right := Vector2(half_size.x, half_size.y)
	var bottom_left := Vector2(-half_size.x, half_size.y)
	return (
		Geometry2D.segment_intersects_segment(from, to, top_left, top_right) != null
		or Geometry2D.segment_intersects_segment(from, to, top_right, bottom_right) != null
		or Geometry2D.segment_intersects_segment(from, to, bottom_right, bottom_left) != null
		or Geometry2D.segment_intersects_segment(from, to, bottom_left, top_left) != null
	)
