extends SceneTree

func _init() -> void:
	print("Running VehicleDynamics Unit Test...")
	
	# Torque curve tests
	var t1 = VehicleDynamics.get_engine_torque_curve(0.0, 100.0, 1.2, 0.3, 0.5, 2.0)
	assert(abs(t1 - 1.2) < 0.001, "Launch torque failed")
	var t2 = VehicleDynamics.get_engine_torque_curve(30.0, 100.0, 1.2, 0.3, 0.5, 2.0)
	assert(abs(t2 - 1.0) < 0.001, "Peak torque failed")
	var t3 = VehicleDynamics.get_engine_torque_curve(100.0, 100.0, 1.2, 0.3, 0.5, 2.0)
	assert(abs(t3 - 0.5) < 0.001, "Max speed torque failed")
	
	# Drag force
	var d1 = VehicleDynamics.calculate_drag_force(100.0, 0.001)
	assert(abs(d1 - 10.0) < 0.001, "Drag calculation failed")
	
	# Braking distance
	var b1 = VehicleDynamics.get_braking_distance(100.0, 0.0, 50.0)
	assert(abs(b1 - 100.0) < 0.001, "Braking distance failed")
	var b2 = VehicleDynamics.get_braking_distance(100.0, 50.0, 50.0)
	assert(abs(b2 - 75.0) < 0.001, "Braking distance to target failed")
	var b3 = VehicleDynamics.get_braking_distance(50.0, 100.0, 50.0)
	assert(abs(b3 - 0.0) < 0.001, "Braking distance (accelerating) failed")
	
	# Corner speed
	var c1 = VehicleDynamics.get_safe_corner_speed(100.0, 4.0)
	assert(abs(c1 - 20.0) < 0.001, "Corner speed failed")
	
	# Tire force
	var lat_f1 = VehicleDynamics.calculate_tire_lateral_force(0.1, 5000.0, 1.0, 1000.0, 0.8, 0.5)
	assert(abs(lat_f1 - 500.0) < 0.001, "Linear tire force failed")
	
	var lat_f2 = VehicleDynamics.calculate_tire_lateral_force(0.5, 5000.0, 1.0, 1000.0, 0.8, 0.5)
	# peak = 1000, demand = 2500, ratio = 2.5
	# falloff = max(0.8, 1.0 - 0.5*(2.5-1)) = max(0.8, 1.0 - 0.75) = max(0.8, 0.25) = 0.8
	# force = 1000 * 0.8 = 800
	assert(abs(lat_f2 - 800.0) < 0.001, "Post-peak tire force failed")
	
	print("VehicleDynamics unit tests passed!")
	quit(0)
