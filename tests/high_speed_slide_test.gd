extends SceneTree

const PHYSICS_HZ := 60
const VEHICLE_SCENE := "res://scenes/vehicles/rustbug.tscn"
const FLICKER_STATS := "res://data/vehicles/flicker.tres"

var _world: Node2D


func _initialize() -> void:
	Engine.physics_ticks_per_second = PHYSICS_HZ
	Engine.time_scale = 1.0
	call_deferred("_run")


func _run() -> void:
	_world = Node2D.new()
	root.add_child(_world)
	current_scene = _world
	var stats: VehicleStats = load(FLICKER_STATS).duplicate()
	stats.physics_model_version = 1
	var vehicle := load(VEHICLE_SCENE).instantiate() as VehicleController
	vehicle.stats = stats
	vehicle.surface_speed_multiplier = 1.0
	vehicle.surface_grip_multiplier = 1.0
	vehicle.freeze = false
	vehicle.sleeping = false
	vehicle.set_player_controlled(false)
	vehicle.reset_dynamics_state()
	var vfx := vehicle.get_node_or_null("VFX")
	if vfx:
		vfx.queue_free()
	_world.add_child(vehicle)
	vehicle.global_position = Vector2.ZERO
	vehicle.rotation = 0.0
	var cruise := stats.max_speed * 0.90
	# Forward plus a lateral kick so the rear starts past its tire peak.
	vehicle.linear_velocity = Vector2.UP * cruise + Vector2.RIGHT * cruise * 0.38
	vehicle.angular_velocity = 0.8
	for _settle in 4:
		await physics_frame
	vehicle.set_external_controls(0.7, 0.0, 1.0, false, false)
	var entered_slide := false
	var max_heading := 0.0
	var start_rot := vehicle.rotation
	var last_slip := 0.0
	for _step in 180:
		await physics_frame
		max_heading = maxf(max_heading, absf(angle_difference(start_rot, vehicle.rotation)))
		last_slip = rad_to_deg(absf(float(vehicle.get("_rear_slip_angle"))))
		if bool(vehicle.is_sliding):
			entered_slide = true
			break
	if not entered_slide:
		push_error("HIGH_SPEED_SLIDE_TEST FAIL: flicker should enter a recoverable slide when pushed at speed (speed=%.1f slip=%.1f heading=%.2f)" % [vehicle.speed, last_slip, max_heading])
		quit(1)
		return
	vehicle.set_external_controls(0.45, 0.0, -0.75, false, false)
	var recovered := false
	for _recover in 150:
		await physics_frame
		max_heading = maxf(max_heading, absf(angle_difference(start_rot, vehicle.rotation)))
		var forward := Vector2.UP.rotated(vehicle.rotation)
		if not bool(vehicle.is_sliding) and vehicle.linear_velocity.dot(forward) > stats.max_speed * 0.30:
			recovered = true
			break
	if max_heading > 1.6:
		push_error("HIGH_SPEED_SLIDE_TEST FAIL: slide spun out (%.2f rad)" % max_heading)
		quit(1)
		return
	if not recovered:
		push_error("HIGH_SPEED_SLIDE_TEST FAIL: counter-steer should save the slide without a crash")
		quit(1)
		return
	print("HIGH_SPEED_SLIDE_TEST PASS heading=%.2f" % max_heading)
	quit(0)
