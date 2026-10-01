extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const PROFILE := preload("res://scripts/race/track_width_profile.gd")

const THEMES: Array[StringName] = [&"kitchen", &"workshop", &"office"]
const ROOMS: Array[StringName] = [&"classic", &"wide", &"tall"]
const SEED := 23757
const DRAMATIC := 115.0
const TOL := 1.0
## The raised island's collider reaches this far past its visible contact edge.
const ISLAND_COLLIDER_OUTSET := 14.0
## ±8 samples is about ±280 units of lap at the 35-unit sample spacing.
const NEARBY_SAMPLES := 8
## Bodies that sit on or at the road by design and are checked on their own.
const ON_ROAD_CONTAINERS: Array[String] = ["PermanentObstacles", "GatePosts", "GeneratedMoments", "InnerBarrier"]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	if not _check_flat_is_default():
		return
	var widened := 0
	var bodies := 0
	for theme in THEMES:
		for room in ROOMS:
			var label := "%s/%s/%d" % [theme, room, SEED]
			var options := {"road_width": DRAMATIC}
			var prepared := BUILDER.prepare_layout(theme, room, SEED, options)
			if not _expect(not prepared.is_empty(), "%s should prepare" % label):
				return
			var centerline: PackedVector2Array = prepared["centerline"]
			var widths: PackedFloat32Array = (prepared["spec"] as Dictionary).get("half_widths", PackedFloat32Array())
			if not _expect(widths.size() == centerline.size(), "%s should carry one half-width per centerline sample" % label):
				return
			var built := BUILDER.build_packed(theme, room, SEED, options)
			var track := (built["scene"] as PackedScene).instantiate() as Node2D
			root.add_child(track)
			var widest := PROFILE.widest(widths)
			widened += 1 if widest > PROFILE.BASE_HALF_WIDTH + 20.0 else 0
			if not _check_surface(track, widest, label):
				return
			if not _check_island(track, centerline, widths, label):
				return
			if not _check_gates(track, centerline, widths, label):
				return
			var checked := _check_off_road_bodies(track, centerline, widths, label)
			if checked < 0:
				return
			bodies += checked
			if not _check_obstacles(track, centerline, widths, label):
				return
			track.free()
	if not _expect(widened >= THEMES.size() * ROOMS.size() - 2, "dramatic amplitude should widen most tracks (%d)" % widened):
		return
	print("GENERATED_TRACK_ROAD_WIDTH_TEST PASS builds=%d widened=%d off_road_bodies=%d" % [THEMES.size() * ROOMS.size(), widened, bodies])
	quit(0)


func _check_flat_is_default() -> bool:
	var default_track := (BUILDER.build_packed(&"kitchen", &"classic", SEED)["scene"] as PackedScene).instantiate() as Node2D
	var flat_track := (BUILDER.build_packed(&"kitchen", &"classic", SEED, {"road_width": PROFILE.MODE_FLAT})["scene"] as PackedScene).instantiate() as Node2D
	var same := _signature(default_track) == _signature(flat_track)
	var surface := default_track.get_node("TrackSurface") as Line2D
	var flat_surface := surface.width_curve == null and is_equal_approx(surface.width, BUILDER.HALF_WIDTH * 2.0)
	default_track.free()
	flat_track.free()
	return _expect(same, "road_width flat must build exactly the default track") and _expect(flat_surface, "the default road stays a fixed 250-wide surface")


func _check_surface(track: Node2D, widest: float, label: String) -> bool:
	var surface := track.get_node_or_null("TrackSurface") as Line2D
	return _expect(surface != null and surface.width_curve != null and absf(surface.width - widest * 2.0) < 0.1, "%s surface should be as wide as the widest road with a width curve" % label) \
		and _expect(absf(float(track.get_meta("corridor_max_half_width", 0.0)) - widest) < 0.01, "%s root should record its widest half-width" % label)


func _check_island(track: Node2D, centerline: PackedVector2Array, widths: PackedFloat32Array, label: String) -> bool:
	var barrier := track.find_child("InnerBarrier", true, false) as StaticBody2D
	if not _expect(barrier != null, "%s should have an island" % label):
		return false
	var points := _body_outline(barrier)
	if not _expect(points.size() >= 3, "%s island collider should not be empty" % label):
		return false
	for point in points:
		# On the inside of a curve the island edge comes from a neighbouring
		# sample's offset, so compare against the narrowest nearby width.
		var local := _narrowest_nearby(centerline, widths, point)
		if not _expect(_distance_to_loop(point, centerline) >= local - ISLAND_COLLIDER_OUTSET - TOL, "%s island reaches into the road at %s" % [label, point]):
			return false
	return true


func _narrowest_nearby(centerline: PackedVector2Array, widths: PackedFloat32Array, point: Vector2) -> float:
	var nearest := 0
	var best := INF
	for index in centerline.size():
		var distance := point.distance_squared_to(centerline[index])
		if distance < best:
			best = distance
			nearest = index
	var narrowest := widths[nearest]
	for offset in range(-NEARBY_SAMPLES, NEARBY_SAMPLES + 1):
		narrowest = minf(narrowest, widths[posmod(nearest + offset, widths.size())])
	return narrowest


func _check_gates(track: Node2D, centerline: PackedVector2Array, widths: PackedFloat32Array, label: String) -> bool:
	for gate_index in BUILDER.GATE_COUNT:
		var checkpoint := track.get_node_or_null("Checkpoint0Finish" if gate_index == 0 else "Checkpoint%d" % gate_index) as Node2D
		if not _expect(checkpoint != null, "%s gate %d missing" % [label, gate_index]):
			return false
		var local := PROFILE.at_point(centerline, widths, checkpoint.position)
		var inner: Vector2 = checkpoint.get_meta("sensor_inner_endpoint", checkpoint.position)
		if not _expect(checkpoint.position.distance_to(inner) <= local + 0.5, "%s gate %d island side should stop at the local road edge" % [label, gate_index]):
			return false
	var posts := track.get_node_or_null("GatePosts")
	if not _expect(posts != null and posts.get_child_count() == BUILDER.GATE_COUNT * 2, "%s should place every gate post" % label):
		return false
	for post: Node in posts.get_children():
		var position := (post as Node2D).global_position
		if not _expect(_distance_to_loop(position, centerline) >= PROFILE.at_point(centerline, widths, position) - TOL, "%s %s should stand off the road" % [label, post.name]):
			return false
	return true


## Every solid body except the on-road sets must keep its collider off the
## local road. Returns the number of bodies checked, or -1 on failure.
func _check_off_road_bodies(track: Node2D, centerline: PackedVector2Array, widths: PackedFloat32Array, label: String) -> int:
	var checked := 0
	for node: Node in track.find_children("*", "StaticBody2D", true, false):
		if _under_any(node, track, ON_ROAD_CONTAINERS):
			continue
		for point in _body_outline(node as StaticBody2D):
			var local := PROFILE.at_point(centerline, widths, point)
			if not _expect(_distance_to_loop(point, centerline) >= local - TOL, "%s %s collider reaches into the road" % [label, track.get_path_to(node)]):
				return -1
		checked += 1
	return checked


func _check_obstacles(track: Node2D, centerline: PackedVector2Array, widths: PackedFloat32Array, label: String) -> bool:
	var obstacles := track.find_child("PermanentObstacles", true, false)
	if obstacles == null:
		return true
	for obstacle: Node in obstacles.get_children():
		var position := (obstacle as Node2D).global_position
		if not _expect(_distance_to_loop(position, centerline) <= PROFILE.at_point(centerline, widths, position) + TOL, "%s obstacle %s should sit on the road edge" % [label, obstacle.name]):
			return false
	return true


func _body_outline(body: StaticBody2D) -> PackedVector2Array:
	var points := PackedVector2Array()
	for child: Node in body.get_children():
		if child is CollisionPolygon2D:
			var polygon := child as CollisionPolygon2D
			for point in polygon.polygon:
				points.append(polygon.global_transform * point)
		elif child is CollisionShape2D:
			var holder := child as CollisionShape2D
			var xform := holder.global_transform
			var shape := holder.shape
			if shape is CircleShape2D:
				for step in 16:
					points.append(xform * Vector2.RIGHT.rotated(TAU * step / 16.0) * (shape as CircleShape2D).radius)
			elif shape is RectangleShape2D:
				var half := (shape as RectangleShape2D).size * 0.5
				for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
					points.append(xform * corner)
			elif shape is CapsuleShape2D:
				var capsule := shape as CapsuleShape2D
				for step in 16:
					var direction := Vector2.RIGHT.rotated(TAU * step / 16.0)
					points.append(xform * (direction * capsule.radius + Vector2(0.0, signf(direction.y) * (capsule.height * 0.5 - capsule.radius))))
			elif shape is ConvexPolygonShape2D:
				for point in (shape as ConvexPolygonShape2D).points:
					points.append(xform * point)
			elif shape is ConcavePolygonShape2D:
				for point in (shape as ConcavePolygonShape2D).segments:
					points.append(xform * point)
	return points


func _under_any(node: Node, track: Node, names: Array[String]) -> bool:
	var cursor := node
	while cursor != null and cursor != track:
		if String(cursor.name) in names:
			return true
		cursor = cursor.get_parent()
	return false


func _distance_to_loop(point: Vector2, loop: PackedVector2Array) -> float:
	var best := INF
	for index in loop.size():
		best = minf(best, point.distance_to(Geometry2D.get_closest_point_to_segment(point, loop[index], loop[(index + 1) % loop.size()])))
	return best


func _signature(node: Node) -> String:
	var parts := PackedStringArray()
	_append_signature(node, parts)
	return "\n".join(parts)


func _append_signature(node: Node, parts: PackedStringArray) -> void:
	# Engine-generated names (@Class@N) differ between identical builds.
	var name := "@" if String(node.name).begins_with("@") else String(node.name)
	var line := "%s:%s" % [name, node.get_class()]
	if node is Node2D:
		line += ":%s" % str((node as Node2D).position.snapped(Vector2.ONE * 0.01))
	parts.append(line)
	for child: Node in node.get_children():
		_append_signature(child, parts)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("GENERATED_TRACK_ROAD_WIDTH_TEST FAIL: " + message)
	quit(1)
	return false
