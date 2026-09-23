extends SceneTree

## Narrow regression for the room-wall runtime fix: room polygons denote interior
## free space, so each wall body sits half its thickness outside an edge and is
## clipped against the room interior at concave corners. Proves, for convex and
## concave polygons in either winding, that wall collision (a) never intrudes
## into the interior and (b) still closes the room boundary.

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const WALL_MASK := 2
const SAMPLE_FRACTIONS: Array[float] = [0.05, 0.25, 0.5, 0.75, 0.95]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var polygons: Array[PackedVector2Array] = [
		# Convex rectangle.
		PackedVector2Array([Vector2(-600, -400), Vector2(600, -400), Vector2(600, 400), Vector2(-600, 400)]),
		# Concave L-shape (reflex corner at the notch).
		PackedVector2Array([Vector2(-600, -400), Vector2(200, -400), Vector2(200, -50), Vector2(600, -50), Vector2(600, 400), Vector2(-600, 400)]),
		# Concave slit: a 20-wide notch narrower than the 50u wall, forcing clipping.
		PackedVector2Array([
			Vector2(-500, -500), Vector2(500, -500), Vector2(500, 500),
			Vector2(10, 500), Vector2(10, 100), Vector2(-10, 100), Vector2(-10, 500),
			Vector2(-500, 500),
		]),
	]
	var checked := 0
	for polygon: PackedVector2Array in polygons:
		for winding: PackedVector2Array in [polygon, _reversed(polygon)]:
			if not await _check_polygon(winding):
				return
			checked += 1
	if not await _check_negative():
		return
	print("TRACK_ROOM_WALL_COLLISION_TEST PASS polygons=%d windings=%d" % [polygons.size(), checked])
	quit(0)


func _reversed(polygon: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in range(polygon.size() - 1, -1, -1):
		result.append(polygon[index])
	return result


func _check_polygon(polygon: PackedVector2Array) -> bool:
	var fixture := Node2D.new()
	fixture.name = "WallFixture"
	root.add_child(fixture)
	var walls_ok: bool = BUILDER._build_room_walls(fixture, polygon, "res://assets/textures/kitchen/counter_edge.png")
	await physics_frame
	if not _expect(walls_ok, "valid polygon should build room walls"):
		await _cleanup(fixture)
		return false
	var walls: Array[StaticBody2D] = []
	for child: Node in fixture.get_children():
		if child is StaticBody2D and StringName(child.get_meta("solid_class", &"")) == &"room_wall":
			walls.append(child as StaticBody2D)
	if not _expect(walls.size() == polygon.size(), "polygon with %d edges should build %d walls (got %d)" % [polygon.size(), polygon.size(), walls.size()]):
		await _cleanup(fixture)
		return false
	for edge_index in polygon.size():
		var from: Vector2 = polygon[edge_index]
		var to: Vector2 = polygon[(edge_index + 1) % polygon.size()]
		var tangent: Vector2 = (to - from).normalized()
		var perpendicular := tangent.rotated(PI * 0.5)
		var midpoint := from.lerp(to, 0.5)
		var inward := perpendicular
		if not Geometry2D.is_point_in_polygon(midpoint + inward * 2.0, polygon):
			inward = -perpendicular
		for fraction: float in SAMPLE_FRACTIONS:
			var base := from.lerp(to, fraction)
			var interior_point := base + inward * 2.0
			if _hits_wall(interior_point, walls):
				await _cleanup(fixture)
				return _expect(false, "wall intrudes into room interior near edge %d fraction %.2f (%s)" % [edge_index, fraction, str(interior_point)])
			var exterior_point := base - inward * 2.0
			if not _hits_wall(exterior_point, walls):
				await _cleanup(fixture)
				return _expect(false, "room boundary left open near edge %d fraction %.2f (%s)" % [edge_index, fraction, str(exterior_point)])
	await _cleanup(fixture)
	return true


func _check_negative() -> bool:
	# A wall whose outward rectangle lies entirely inside the room (a malformed
	# winding/degenerate input) must fail rather than fabricate a hull or a plain
	# rectangle. The clip yields nothing, so no collision may be accepted.
	var room := PackedVector2Array([Vector2(-600, -400), Vector2(600, -400), Vector2(600, 400), Vector2(-600, 400)])
	var from := Vector2(-600, -400)
	var to := Vector2(600, -400)
	var inward := Vector2(0, 1)
	if not _expect(BUILDER._wall_collision_pieces(from, to, inward, BUILDER.ROOM_WALL_THICKNESS, room).is_empty(), "a fully-interior wall rectangle should yield no collision pieces"):
		return false
	var fixture := Node2D.new()
	fixture.name = "BadWallFixture"
	root.add_child(fixture)
	var ok: bool = BUILDER._add_wall_segment(fixture, "BadWall", Vector2(0, -400), 1200.0, 0.0, "res://assets/textures/kitchen/counter_edge.png", room, inward)
	if not _expect(not ok and fixture.get_child_count() == 0, "failed wall geometry must not leave a fabricated wall node (ok=%s children=%d)" % [str(ok), fixture.get_child_count()]):
		await _cleanup(fixture)
		return false
	await _cleanup(fixture)
	return true


func _hits_wall(point: Vector2, walls: Array[StaticBody2D]) -> bool:
	var params := PhysicsPointQueryParameters2D.new()
	params.position = point
	params.collision_mask = WALL_MASK
	params.collide_with_areas = false
	params.collide_with_bodies = true
	for hit: Dictionary in root.world_2d.direct_space_state.intersect_point(params, 32):
		if walls.has(hit.get("collider")):
			return true
	return false


func _cleanup(fixture: Node2D) -> void:
	if is_instance_valid(fixture):
		fixture.queue_free()
		await process_frame


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_ROOM_WALL_COLLISION_TEST FAIL: " + message)
	quit(1)
	return false
