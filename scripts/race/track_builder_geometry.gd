class_name TrackBuilderGeometry
## Pure loop/corridor math used by TrackBuilderCore. No nodes, no textures.

const HALF_WIDTH := 125.0
const SAMPLE_COUNT := 260


static func sample_centerline(controls: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in SAMPLE_COUNT:
		points.append(catmull_rom_closed(controls, float(index) / float(SAMPLE_COUNT)))
	return points


static func catmull_rom_closed(points: Array, t: float) -> Vector2:
	var count := points.size()
	var scaled := t * float(count)
	var i := int(floor(scaled))
	var local := scaled - float(i)
	var p0: Vector2 = points[posmod(i - 1, count)]
	var p1: Vector2 = points[posmod(i, count)]
	var p2: Vector2 = points[posmod(i + 1, count)]
	var p3: Vector2 = points[posmod(i + 2, count)]
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * local
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * local * local
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * local * local * local
	)


static func corridor_edges(centerline: PackedVector2Array) -> Dictionary:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var count := centerline.size()
	for index in count:
		var tangent := (centerline[(index + 1) % count] - centerline[(index - 1 + count) % count]).normalized()
		var normal := tangent.rotated(PI * 0.5)
		left.append(centerline[index] + normal * HALF_WIDTH)
		right.append(centerline[index] - normal * HALF_WIDTH)
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
		var area := absf(polygon_area(contour))
		if contour.size() >= 3 and area > largest_area:
			largest = contour
			largest_area = area
	return largest if not largest.is_empty() else points


static func simple_island_loop(points: PackedVector2Array) -> PackedVector2Array:
	# Normal offsets fold over themselves at concave corners. Running the contour
	# through Clipper splits those folds into simple polygons; the largest contour
	# is the central island and the smaller pieces are offset artifacts.
	var pieces: Array[PackedVector2Array] = Geometry2D.intersect_polygons(points, points)
	var result := PackedVector2Array()
	var largest_area := 0.0
	for piece: PackedVector2Array in pieces:
		var area := absf(polygon_area(piece))
		if piece.size() >= 3 and area > largest_area:
			result = piece
			largest_area = area
	return result if not result.is_empty() else points


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
		var cleaned := deduplicate_loop(piece)
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
		for index in line.size():
			if point_to_segment_distance(center, line[index], line[(index + 1) % line.size()]) < radius:
				return false
		return true
	var expanded_half_size := size * 0.5 + Vector2.ONE * hull_radius
	for index in line.size():
		var local_from := (line[index] - center).rotated(-rotation)
		var local_to := (line[(index + 1) % line.size()] - center).rotated(-rotation)
		if segment_intersects_axis_rect(local_from, local_to, expanded_half_size):
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
