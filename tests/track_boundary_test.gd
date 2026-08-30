extends SceneTree

const KITCHEN_SCENE := preload("res://scenes/tracks/kitchen_circuit.tscn")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var track := KITCHEN_SCENE.instantiate() as Node2D
	root.add_child(track)
	await physics_frame

	var barrier := track.get_node_or_null("InnerBarrier") as StaticBody2D
	if not _expect(barrier != null, "the painted inner island should have a matching static barrier"):
		return
	if not _expect(barrier.collision_layer == 2, "the inner barrier should live on the track collision layer"):
		return
	var collision_shape: CollisionPolygon2D
	for child: Node in barrier.get_children():
		if child is CollisionPolygon2D:
			collision_shape = child as CollisionPolygon2D
			break
	if not _expect(collision_shape != null and collision_shape.polygon.size() >= 6, "the inner barrier should cover the full painted island"):
		return

	var island := track.get_node_or_null("IslandProp") as Polygon2D
	if not _expect(island != null and island.polygon.size() >= 6, "the collision boundary should be visually communicated by the island prop"):
		return

	var test_vehicle := CharacterBody2D.new()
	test_vehicle.name = "BoundaryProbe"
	test_vehicle.collision_layer = 1
	test_vehicle.collision_mask = 2
	test_vehicle.position = Vector2(-780.0, 0.0)
	var probe_shape := CollisionShape2D.new()
	var probe_rectangle := RectangleShape2D.new()
	probe_rectangle.size = Vector2(56.0, 82.0)
	probe_shape.shape = probe_rectangle
	test_vehicle.add_child(probe_shape)
	track.add_child(test_vehicle)
	await physics_frame

	var hit := test_vehicle.move_and_collide(Vector2(1560.0, 0.0))
	if not _expect(hit != null, "a vehicle crossing the infield should hit the inner barrier instead of cutting the circuit"):
		return

	root.remove_child(track)
	track.free()
	print("TRACK_BOUNDARY_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_BOUNDARY_TEST FAIL: " + message)
	quit(1)
	return false
