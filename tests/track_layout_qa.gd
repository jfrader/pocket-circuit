extends SceneTree

## World-space track QA: run headless with PC_THEME=workshop|office.
## Verifies the geometry contracts the visual layer can't see: grid placement,
## collision coverage, prop/corridor separation, checker alignment, gate
## placement. Prints PASS or the first failing check.

const THEME_SCENES := {
	&"workshop": "res://scenes/tracks/workshop_workbench.tscn",
	&"office": "res://scenes/tracks/office_desk.tscn",
}

var _theme: StringName = &"workshop"
var _failures: Array[String] = []


func _initialize() -> void:
	var env := OS.get_environment("PC_THEME")
	if env in [&"workshop", &"office"]:
		_theme = StringName(env)
	call_deferred("_run")


func _run() -> void:
	var scene_path := String(THEME_SCENES[_theme])
	var track := (load(scene_path) as PackedScene).instantiate() as Node2D
	root.add_child(track)

	var ribbon := track.get_node_or_null("TrackSurface") as Line2D
	var barrier := track.get_node_or_null("InnerBarrier") as StaticBody2D
	var finish := track.get_node_or_null("Checkpoint0Finish") as Area2D
	var white := track.get_node_or_null("StartFinishWhite") as Polygon2D
	var black := track.get_node_or_null("StartFinishBlack") as Polygon2D

	_check(ribbon != null, "painted ribbon exists")
	_check(barrier != null, "island prop barrier exists")
	_check(finish != null and bool(finish.get("is_finish_line")), "finish gate exists")
	_check(white != null and black != null and white.visible and black.visible, "checker strip exists and visible")

	if barrier != null:
		var boundary_collision := barrier.get_node_or_null("BoundaryCollision") as CollisionShape2D
		_check(
			boundary_collision != null
			and boundary_collision.shape is ConcavePolygonShape2D
			and barrier_collision_polygon(barrier).size() > 20,
			"island prop has a complete concave collision boundary"
		)

	if ribbon != null:
		for container_name: String in ["GridForward", "GridReverse"]:
			var container := track.get_node_or_null(container_name) as Node2D
			_check(container != null and container.get_child_count() == 4, "%s has four markers" % container_name)
			if container:
				for marker in container.get_children():
					var marker_node := marker as Node2D
					if marker_node == null:
						continue
					_check(_inside_course(marker_node.position, ribbon), "%s marker %s is inside the painted track" % [container_name, marker.name])
					if barrier != null:
						_check(not Geometry2D.is_point_in_polygon(marker_node.position, barrier_collision_polygon(barrier)), "%s marker %s stays outside the inner barrier" % [container_name, marker.name])
					var clearance := _clearance_from_colliders(track, marker_node.position)
					if clearance < 55.0:
						_check(false, "%s marker %s keeps clearance from props/walls (%.0f near %s)" % [container_name, marker.name, clearance, _nearest_collider(track, marker_node.position)])

		for gate_name: String in ["Checkpoint0Finish", "Checkpoint1", "Checkpoint2", "Checkpoint3", "Checkpoint4", "Checkpoint5", "Checkpoint6", "Checkpoint7"]:
			var gate := track.get_node_or_null(gate_name) as Area2D
			if gate == null:
				continue
			var corners := _gate_corners(gate)
			var center := gate.position
			_check(_inside_course(center, ribbon), "%s sits on the painted track" % gate_name)
			var gate_size := ((gate.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D).size
			var span := maxf(gate_size.x, gate_size.y)
			var min_span := 272.0 if gate_name == "Checkpoint0Finish" else 250.0
			_check(span >= min_span, "%s spans the corridor (%.0f)" % [gate_name, span])

	var obstacles := _obstacle_bodies(track)
	_check(obstacles.size() >= 11, "at least eleven physical scenery objects present")
	for first in obstacles.size():
		for second in range(first + 1, obstacles.size()):
			var a := TrackBuilderBoundary._footprint_polygon(obstacles[first].global_position, obstacles[first].get_meta("physical_dimensions_mm"), obstacles[first].global_rotation)
			var b := TrackBuilderBoundary._footprint_polygon(obstacles[second].global_position, obstacles[second].get_meta("physical_dimensions_mm"), obstacles[second].global_rotation)
			_check(Geometry2D.intersect_polygons(a,b).is_empty(), "physical scenery %s and %s must not overlap" % [obstacles[first].name, obstacles[second].name])

	if white != null and finish != null:
		var minimum := INF
		var maximum := -INF
		for cell: Node in track.get_children():
			if cell is Polygon2D and String(cell.name).begins_with("StartFinish"):
				for point: Vector2 in cell.polygon:
					var across := finish.to_local(cell.to_global(point)).y
					minimum = minf(minimum, across)
					maximum = maxf(maximum, across)
		_check(maximum - minimum >= TrackBuilderCore.HALF_WIDTH * 2.0 - 2.0, "checker cells collectively cover the complete corridor")

	# Walls cover the room perimeter
	for wall_name: String in ["Wall0", "Wall1", "Wall2", "Wall3"]:
		_check(track.get_node_or_null(wall_name) != null, "%s present" % wall_name)

	if _failures.is_empty():
		print("TRACK_LAYOUT_QA PASS %s" % _theme)
		track.queue_free()
		await physics_frame
		quit(0)
		return
	for failure: String in _failures:
		push_error("TRACK_LAYOUT_QA FAIL: " + failure)
	quit(1)


func _inside_course(point: Vector2, surface: Line2D) -> bool:
	var closest := TrackBuilderCore._closest_point_on_loop(point, surface.points)
	return point.distance_to(closest["position"]) <= surface.width * 0.5


func barrier_collision_polygon(barrier: StaticBody2D) -> PackedVector2Array:
	var metadata_polygon: PackedVector2Array = barrier.get_meta("boundary_polygon", PackedVector2Array())
	if not metadata_polygon.is_empty():
		var transformed := PackedVector2Array()
		for point: Vector2 in metadata_polygon:
			transformed.append(barrier.transform * point)
		return transformed
	for child in barrier.get_children():
		if child is CollisionPolygon2D:
			var transformed := PackedVector2Array()
			for point: Vector2 in (child as CollisionPolygon2D).polygon:
				transformed.append(barrier.transform * (child as CollisionPolygon2D).transform * point)
			return transformed
		elif child is CollisionShape2D:
			var shape: Shape2D = (child as CollisionShape2D).shape
			if shape.get_class() == "RectangleShape2D":
				var rect_shape: RectangleShape2D = shape
				var rect := Rect2(barrier.position + (child as CollisionShape2D).position - rect_shape.size * 0.5, rect_shape.size)
				return PackedVector2Array([
					rect.position, Vector2(rect.end.x, rect.position.y),
					rect.end, Vector2(rect.position.x, rect.end.y),
				])
	return PackedVector2Array()


func _clearance_from_colliders(track: Node2D, point: Vector2) -> float:
	var best := INF
	for node in track.find_children("*", "StaticBody2D", true, false):
		var body := node as StaticBody2D
		for child in body.get_children():
			if child is CollisionShape2D:
				var shape: Shape2D = (child as CollisionShape2D).shape
				if shape.get_class() == "CircleShape2D":
					var circle: CircleShape2D = shape
					best = minf(best, point.distance_to(body.position + (child as CollisionShape2D).position) - circle.radius)
				elif shape.get_class() == "RectangleShape2D":
					var rect_shape: RectangleShape2D = shape
					var rect := Rect2(body.position + (child as CollisionShape2D).position - rect_shape.size * 0.5, rect_shape.size)
					var nearest := Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
					best = minf(best, point.distance_to(nearest))
				elif shape.get_class() == "CollisionPolygon2D":
					var polygon: Variant = shape.get("polygon")
					if polygon is PackedVector2Array:
						var transformed := PackedVector2Array()
						for p: Vector2 in polygon:
							transformed.append(body.position + p)
						if Geometry2D.is_point_in_polygon(point, transformed):
							return 0.0
	return best


func _nearest_collider(track: Node2D, point: Vector2) -> String:
	var best_name := ""
	var best := INF
	for node in track.find_children("*", "StaticBody2D", true, false):
		var body := node as StaticBody2D
		var distance := point.distance_to(body.position)
		if distance < best:
			best = distance
			best_name = body.name
	return "%s (%.0f)" % [best_name, best]


func _obstacle_bodies(track: Node2D) -> Array[StaticBody2D]:
	var bodies: Array[StaticBody2D] = []
	for obstacle: Node in track.find_children("*", "StaticBody2D", true, false):
		if obstacle.has_meta("environment_asset_id"):
			bodies.append(obstacle as StaticBody2D)
	return bodies


func _obstacle_radius(obstacle: StaticBody2D) -> float:
	for child in obstacle.get_children():
		if child is CollisionShape2D:
			var shape: Shape2D = (child as CollisionShape2D).shape
			if shape.get_class() == "CircleShape2D":
				return (shape as CircleShape2D).radius
	return 30.0


func _gate_corners(gate: Area2D) -> Dictionary:
	var shape := (gate.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	var half := shape.size * 0.5
	var corners := [
		Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
		Vector2(half.x, half.y), Vector2(-half.x, half.y),
	]
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for corner: Vector2 in corners:
		var world := gate.position + corner.rotated(gate.rotation)
		min_x = minf(min_x, world.x)
		max_x = maxf(max_x, world.x)
		min_y = minf(min_y, world.y)
		max_y = maxf(max_y, world.y)
	return {"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y}


func _polygon_bounds(points: PackedVector2Array) -> Dictionary:
	var min_x := INF
	var max_x := -INF
	for point: Vector2 in points:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
	return {"min_x": min_x, "max_x": max_x}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
