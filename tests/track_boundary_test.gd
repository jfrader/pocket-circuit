extends SceneTree

const KITCHEN_SCENE := preload("res://scenes/tracks/kitchen_graybox.tscn")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var track := KITCHEN_SCENE.instantiate() as Node2D
	root.add_child(track)
	await physics_frame

	var barrier := track.get_node_or_null("InnerCircuitBarrier") as StaticBody2D
	if not _expect(barrier != null, "the painted inner island should have a matching static barrier"):
		return
	if not _expect(barrier.collision_layer == 2 and barrier.collision_mask == 1, "the inner barrier should collide with race vehicles on the track layer"):
		return
	var collision_shape := barrier.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var rectangle := collision_shape.shape as RectangleShape2D if collision_shape else null
	if not _expect(rectangle != null and rectangle.size.is_equal_approx(Vector2(1180.0, 450.0)), "the inner barrier should cover the full painted island"):
		return

	var guardrail := track.get_node_or_null("InnerCircuitGuardrail") as Line2D
	if not _expect(guardrail != null and guardrail.closed and is_equal_approx(guardrail.width, 16.0), "the collision boundary should be visually communicated by a continuous guardrail"):
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
	if not _expect(hit != null and hit.get_collider() == barrier, "a vehicle crossing the infield should hit the inner barrier instead of cutting the circuit"):
		return
	if not _expect(test_vehicle.position.x <= -617.0, "the collision response should stop the vehicle at the visible left guardrail"):
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
