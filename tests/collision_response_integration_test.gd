extends SceneTree

const VEHICLE_SCENE := preload("res://scenes/vehicles/rustbug.tscn")
const RESPONSE_POLICY := preload("res://scripts/vehicle/collision_response_policy.gd")


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("_run_test")


func _run_test() -> void:
	if not _test_persistent_policy_sample():
		return
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world
	if not await _test_no_contact_trajectory(world):
		return
	await _clear_world(world)
	if not await _test_rear_contact_and_release_agency(world):
		return
	await _clear_world(world)
	if not await _test_head_on_contact(world):
		return
	await _clear_world(world)
	if not await _test_mass_authority(world):
		return
	await _clear_world(world)
	if not await _test_side_separation(world):
		return
	await _clear_world(world)
	world.queue_free()
	await process_frame
	print("COLLISION_RESPONSE_INTEGRATION_TEST PASS")
	quit(0)


func _test_persistent_policy_sample() -> bool:
	var persistent := RESPONSE_POLICY.resolve_contact({
		"delta": 1.0 / 60.0,
		"intended_forward": Vector2.UP,
		"normal": Vector2.DOWN,
		"relative_velocity": Vector2.UP * 120.0,
		"impulse": Vector2.UP * 80.0,
		"previous_velocity": Vector2.UP * 140.0,
		"solver_velocity": Vector2.UP * 215.0,
		"solver_angular_velocity": 0.0,
		"self_mass": 0.85,
		"other_mass": 1.15,
		"is_new_contact": false,
	})
	var preserved_forward := (persistent["velocity"] as Vector2).dot(Vector2.UP)
	if not _expect(is_equal_approx(preserved_forward, 215.0), "persistent contact discarded solver longitudinal velocity"):
		return false
	var side := RESPONSE_POLICY.resolve_contact({
		"delta": 1.0 / 60.0,
		"intended_forward": Vector2.UP,
		"normal": Vector2.RIGHT,
		"relative_velocity": Vector2.LEFT * 40.0,
		"impulse": Vector2.RIGHT * 60.0,
		"previous_velocity": Vector2.UP * 200.0,
		"solver_velocity": Vector2(90.0, -180.0),
		"solver_angular_velocity": 0.4,
		"self_mass": 1.0,
		"other_mass": 1.0,
		"is_new_contact": false,
	})
	if not _expect((side["velocity"] as Vector2).x >= 36.0, "persistent side contact must keep outward separation instead of heading-locking cars together"):
		return false
	var head_on := RESPONSE_POLICY.resolve_contact({
		"delta": 1.0 / 60.0,
		"intended_forward": Vector2.UP,
		"normal": Vector2.UP,
		"relative_velocity": Vector2.UP * 400.0,
		"impulse": Vector2.DOWN * 200.0,
		"previous_velocity": Vector2.UP * 300.0,
		"solver_velocity": Vector2.DOWN * 40.0,
		"solver_angular_velocity": 0.0,
		"self_mass": 1.0,
		"other_mass": 1.0,
		"is_new_contact": true,
	})
	if not _expect((head_on["velocity"] as Vector2).y >= 0.0, "head-on contact must keep solver rebound instead of inventing extra forward speed"):
		return false
	var light_attacker := _impact_sample(0.72, 1.15)
	var heavy_attacker := _impact_sample(1.15, 0.72)
	if not _expect(float(light_attacker["loss_ratio"]) > float(heavy_attacker["loss_ratio"]), "impact loss did not preserve mass authority"):
		return false
	return true


func _impact_sample(self_mass: float, other_mass: float) -> Dictionary:
	return RESPONSE_POLICY.resolve_contact({
		"delta": 1.0 / 60.0,
		"intended_forward": Vector2.UP,
		"normal": Vector2.DOWN,
		"relative_velocity": Vector2.UP * 220.0,
		"impulse": Vector2.UP * 120.0,
		"previous_velocity": Vector2.UP * 300.0,
		"solver_velocity": Vector2.UP * 190.0,
		"solver_angular_velocity": 0.0,
		"self_mass": self_mass,
		"other_mass": other_mass,
		"is_new_contact": true,
	})


func _test_no_contact_trajectory(world: Node2D) -> bool:
	var first := _spawn_vehicle(world, "ControlA", Vector2(180.0, 180.0), Vector2(24.0, -280.0))
	var second := _spawn_vehicle(world, "ControlB", Vector2(980.0, 580.0), Vector2(24.0, -280.0))
	var initial_offset := second.position - first.position
	for _frame in 45:
		await physics_frame
	var velocity_error := first.linear_velocity.distance_to(second.linear_velocity)
	var offset_error := (second.position - first.position).distance_to(initial_offset)
	print("COLLISION_RESPONSE_INTEGRATION_TEST NO_CONTACT velocity_error=%.6f offset_error=%.6f" % [velocity_error, offset_error])
	if not _expect(velocity_error <= 0.001 and offset_error <= 0.001, "no-contact twins diverged from the same production trajectory"):
		return false
	if not _expect((first.get("last_collision_response") as Dictionary).is_empty() and (second.get("last_collision_response") as Dictionary).is_empty(), "no-contact vehicle entered collision policy"):
		return false
	return true


func _test_rear_contact_and_release_agency(world: Node2D) -> bool:
	var lead := _spawn_vehicle(world, "Lead", Vector2(500.0, 300.0), Vector2(0.0, -250.0))
	var trailing := _spawn_vehicle(world, "Trailing", Vector2(500.0, 346.0), Vector2(0.0, -410.0))
	var maximum_nudge := 0.0
	for _frame in 90:
		await physics_frame
		maximum_nudge = maxf(maximum_nudge, float((lead.get("last_collision_response") as Dictionary).get("nudge_ratio", 0.0)))
	var lead_response: Dictionary = lead.get("last_collision_response")
	var trailing_response: Dictionary = trailing.get("last_collision_response")
	var contact_distance := lead.position.distance_to(trailing.position)
	var speed_gap := lead.linear_velocity.distance_to(trailing.linear_velocity)
	print("COLLISION_RESPONSE_INTEGRATION_TEST REAR distance=%.2f speed_gap=%.3f nudge=%.4f lead=%s trailing=%s" % [contact_distance, speed_gap, maximum_nudge, str(lead.position), str(trailing.position)])
	if not _expect(not lead_response.is_empty() and not trailing_response.is_empty(), "rear-shunt vehicles did not record production contact"):
		return false
	if not _expect(not bool(lead_response.get("is_new_contact", true)) and not bool(trailing_response.get("is_new_contact", true)), "sustained rear contact never reached the persistent path"):
		return false
	if not _expect(maximum_nudge <= 0.10 and float(trailing_response.get("loss_ratio", 0.0)) <= 0.28, "rear-shunt policy cap was exceeded"):
		return false
	if not _expect(contact_distance <= 53.0 and speed_gap <= 3.0, "persistent contact failed to transfer solver velocity between vehicles"):
		return false

	trailing.queue_free()
	await physics_frame
	lead.position = Vector2(360.0, 420.0)
	lead.rotation = 0.0
	lead.linear_velocity = Vector2.UP * 260.0
	lead.angular_velocity = 0.0
	lead.set("controls_locked", false)
	lead.call("set_external_controls", 0.0, 0.0, 1.0, true, false)
	var control := _spawn_vehicle(world, "SteeringControl", Vector2(900.0, 420.0), Vector2.UP * 260.0)
	control.set("controls_locked", false)
	control.call("set_external_controls", 0.0, 0.0, 1.0, true, false)
	for _frame in 10:
		await physics_frame
	var rotation_error := absf(lead.rotation - control.rotation)
	var angular_error := absf(lead.angular_velocity - control.angular_velocity)
	print("COLLISION_RESPONSE_INTEGRATION_TEST RELEASE rotation_error=%.6f angular_error=%.6f drifting=%s/%s" % [rotation_error, angular_error, str(lead.get("is_drifting")), str(control.get("is_drifting"))])
	if not _expect(absf(control.rotation) > 0.01 and bool(lead.get("is_drifting")), "steering command did not establish the release-agency baseline"):
		return false
	if not _expect(rotation_error <= 0.002 and angular_error <= 0.02, "post-contact settling suppressed steering after separation"):
		return false
	return true


func _test_head_on_contact(world: Node2D) -> bool:
	var lower := _spawn_vehicle(world, "HeadOnLower", Vector2(500.0, 400.0), Vector2.UP * 320.0)
	var upper := _spawn_vehicle(world, "HeadOnUpper", Vector2(500.0, 240.0), Vector2.DOWN * 320.0, PI)
	for _frame in 60:
		await physics_frame
	var lower_response: Dictionary = lower.get("last_collision_response")
	var upper_response: Dictionary = upper.get("last_collision_response")
	print("COLLISION_RESPONSE_INTEGRATION_TEST HEAD_ON lower=%s upper=%s velocities=%s/%s" % [str(lower.position), str(upper.position), str(lower.linear_velocity), str(upper.linear_velocity)])
	if not _expect(not lower_response.is_empty() and not upper_response.is_empty(), "head-on vehicles never entered production contact response"):
		return false
	if not _expect(upper.position.y < lower.position.y, "head-on vehicles passed through each other"):
		return false
	if not _expect(lower.linear_velocity.y == lower.linear_velocity.y and upper.linear_velocity.y == upper.linear_velocity.y, "head-on response produced invalid velocity"):
		return false
	return true


func _test_mass_authority(world: Node2D) -> bool:
	var heavy_target := _spawn_vehicle(world, "HeavyTarget", Vector2(320.0, 300.0), Vector2.UP * 140.0, 0.0, 1.15)
	var light_attacker := _spawn_vehicle(world, "LightAttacker", Vector2(320.0, 390.0), Vector2.UP * 360.0, 0.0, 0.72)
	var light_target := _spawn_vehicle(world, "LightTarget", Vector2(850.0, 300.0), Vector2.UP * 140.0, 0.0, 0.72)
	var heavy_attacker := _spawn_vehicle(world, "HeavyAttacker", Vector2(850.0, 390.0), Vector2.UP * 360.0, 0.0, 1.15)
	var heavy_target_nudge := 0.0
	var light_target_nudge := 0.0
	var light_attacker_loss := 0.0
	var heavy_attacker_loss := 0.0
	for _frame in 60:
		await physics_frame
		heavy_target_nudge = maxf(heavy_target_nudge, float((heavy_target.get("last_collision_response") as Dictionary).get("nudge_ratio", 0.0)))
		light_target_nudge = maxf(light_target_nudge, float((light_target.get("last_collision_response") as Dictionary).get("nudge_ratio", 0.0)))
		light_attacker_loss = maxf(light_attacker_loss, float((light_attacker.get("last_collision_response") as Dictionary).get("loss_ratio", 0.0)))
		heavy_attacker_loss = maxf(heavy_attacker_loss, float((heavy_attacker.get("last_collision_response") as Dictionary).get("loss_ratio", 0.0)))
	print("COLLISION_RESPONSE_INTEGRATION_TEST MASS target_nudge=%.4f/%.4f attacker_loss=%.4f/%.4f" % [heavy_target_nudge, light_target_nudge, light_attacker_loss, heavy_attacker_loss])
	if not _expect(heavy_target_nudge > 0.0 and light_target_nudge > heavy_target_nudge, "lighter target did not receive the larger rear-contact nudge"):
		return false
	if not _expect(light_attacker_loss > heavy_attacker_loss, "lighter attacker did not pay the larger impact loss"):
		return false
	return true


func _test_side_separation(world: Node2D) -> bool:
	var left := _spawn_vehicle(world, "SideLeft", Vector2(500.0, 400.0), Vector2.UP * 260.0)
	var right := _spawn_vehicle(world, "SideRight", Vector2(534.0, 400.0), Vector2.UP * 260.0)
	for _frame in 45:
		await physics_frame
	var gap := absf(right.position.x - left.position.x)
	print("COLLISION_RESPONSE_INTEGRATION_TEST SIDE gap=%.2f left=%s right=%s" % [gap, str(left.linear_velocity), str(right.linear_velocity)])
	if not _expect(gap >= 36.0, "side contact glued vehicles together instead of separating"):
		return false
	if not _expect(left.linear_velocity.y < -40.0 and right.linear_velocity.y < -40.0, "side contact stopped forward travel"):
		return false
	return true


func _spawn_vehicle(
		world: Node2D,
		vehicle_name: String,
		spawn_position: Vector2,
		velocity: Vector2,
		rotation_value: float = 0.0,
		mass_value: float = -1.0
) -> RigidBody2D:
	var vehicle := VEHICLE_SCENE.instantiate() as RigidBody2D
	vehicle.name = vehicle_name
	vehicle.position = spawn_position
	vehicle.rotation = rotation_value
	vehicle.linear_velocity = velocity
	vehicle.set("control_mode", 1)
	vehicle.set("controls_locked", true)
	vehicle.collision_layer |= 1
	vehicle.collision_mask |= 1
	vehicle.add_to_group("race_vehicle")
	world.add_child(vehicle)
	if mass_value > 0.0:
		vehicle.mass = mass_value
	return vehicle


func _clear_world(world: Node2D) -> void:
	for child: Node in world.get_children():
		child.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("COLLISION_RESPONSE_INTEGRATION_TEST FAIL: " + message)
	quit(1)
	return false
