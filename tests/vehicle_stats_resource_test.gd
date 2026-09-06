extends SceneTree

const CATALOG := preload("res://data/championship/catalog.gd")
const VEHICLE_SCENE := preload("res://scenes/vehicles/rustbug.tscn")
const VEHICLE_IDS: Array[String] = ["rustbug", "pinbolt", "scrapjaw", "flicker"]
const TARGETS := {
	"rustbug": {
			"mass": 0.88,
			"wheelbase": 39,
			"front_weight_ratio": 0.52,
			"engine_force": 850,
			"launch_torque_multiplier": 1.1,
			"torque_peak_ratio": 0.3,
			"torque_at_max_speed": 0.4,
			"torque_falloff_exponent": 1.65,
			"max_speed": 692,
			"reverse_speed": 240,
			"rolling_resistance": 18,
			"aero_drag_coefficient": 0.00053,
			"front_grip": 1.2,
			"rear_grip": 1.22,
			"front_cornering_stiffness": 4200,
			"rear_cornering_stiffness": 4100,
			"post_peak_grip_ratio": 0.68,
			"slip_falloff_rate": 0.28,
			"max_steer_angle_deg": 34,
			"steering_response": 8.5,
			"high_speed_steer_ratio": 0.58,
			"steer_fade_start_ratio": 0.3,
			"yaw_stability_rate": 5.5,
			"brake_force": 1050,
			"handbrake_force": 270,
			"drift_min_speed": 130,
			"drift_entry_steer": 0.35,
			"drift_rear_grip_ratio": 0.4,
			"drift_yaw_assist": 2,
			"drift_grip_recovery_rate": 7,
			"drift_optimal_slip_deg": 26,
			"drift_boost_max_reward": 16,
			"boost_power": 560,
			"boost_capacity": 100,
			"boost_recharge": 10,
			"boost_drain_rate": 32,
			"durability": 52,
		},
	"pinbolt": {
			"mass": 0.74,
			"wheelbase": 37,
			"front_weight_ratio": 0.54,
			"engine_force": 710,
			"launch_torque_multiplier": 1.12,
			"torque_peak_ratio": 0.27,
			"torque_at_max_speed": 0.35,
			"torque_falloff_exponent": 1.8,
			"max_speed": 655,
			"reverse_speed": 245,
			"rolling_resistance": 16,
			"aero_drag_coefficient": 0.000395,
			"front_grip": 1.38,
			"rear_grip": 1.36,
			"front_cornering_stiffness": 4700,
			"rear_cornering_stiffness": 4100,
			"post_peak_grip_ratio": 0.76,
			"slip_falloff_rate": 0.18,
			"max_steer_angle_deg": 37,
			"steering_response": 11.5,
			"high_speed_steer_ratio": 0.61,
			"steer_fade_start_ratio": 0.38,
			"yaw_stability_rate": 5,
			"brake_force": 1000,
			"handbrake_force": 220,
			"drift_min_speed": 150,
			"drift_entry_steer": 0.42,
			"drift_rear_grip_ratio": 0.5,
			"drift_yaw_assist": 1.2,
			"drift_grip_recovery_rate": 10,
			"drift_optimal_slip_deg": 22,
			"drift_boost_max_reward": 10,
			"boost_power": 480,
			"boost_capacity": 90,
			"boost_recharge": 7.5,
			"boost_drain_rate": 34,
			"durability": 46,
		},
	"scrapjaw": {
			"mass": 1.22,
			"wheelbase": 43,
			"front_weight_ratio": 0.56,
			"engine_force": 1260,
			"launch_torque_multiplier": 1.1,
			"torque_peak_ratio": 0.38,
			"torque_at_max_speed": 0.38,
			"torque_falloff_exponent": 1.35,
			"max_speed": 715,
			"reverse_speed": 220,
			"rolling_resistance": 27,
			"aero_drag_coefficient": 0.00068,
			"front_grip": 1.08,
			"rear_grip": 1.17,
			"front_cornering_stiffness": 4500,
			"rear_cornering_stiffness": 4500,
			"post_peak_grip_ratio": 0.72,
			"slip_falloff_rate": 0.22,
			"max_steer_angle_deg": 28.5,
			"steering_response": 5.5,
			"high_speed_steer_ratio": 0.5,
			"steer_fade_start_ratio": 0.24,
			"yaw_stability_rate": 3.8,
			"brake_force": 1250,
			"handbrake_force": 360,
			"drift_min_speed": 145,
			"drift_entry_steer": 0.4,
			"drift_rear_grip_ratio": 0.42,
			"drift_yaw_assist": 1.4,
			"drift_grip_recovery_rate": 4.5,
			"drift_optimal_slip_deg": 24,
			"drift_boost_max_reward": 12,
			"boost_power": 640,
			"boost_capacity": 95,
			"boost_recharge": 8,
			"boost_drain_rate": 30,
			"durability": 75,
		},
	"flicker": {
			"mass": 0.68,
			"wheelbase": 36,
			"front_weight_ratio": 0.48,
			"engine_force": 695,
			"launch_torque_multiplier": 1.06,
			"torque_peak_ratio": 0.33,
			"torque_at_max_speed": 0.38,
			"torque_falloff_exponent": 2.1,
			"max_speed": 742,
			"reverse_speed": 250,
			"rolling_resistance": 14,
			"aero_drag_coefficient": 0.000355,
			"front_grip": 1.17,
			"rear_grip": 1.19,
			"front_cornering_stiffness": 3400,
			"rear_cornering_stiffness": 2900,
			"post_peak_grip_ratio": 0.56,
			"slip_falloff_rate": 0.48,
			"max_steer_angle_deg": 35,
			"steering_response": 9.5,
			"high_speed_steer_ratio": 0.48,
			"steer_fade_start_ratio": 0.28,
			"yaw_stability_rate": 6,
			"brake_force": 820,
			"handbrake_force": 200,
			"drift_min_speed": 115,
			"drift_entry_steer": 0.28,
			"drift_rear_grip_ratio": 0.3,
			"drift_yaw_assist": 3.2,
			"drift_grip_recovery_rate": 6.5,
			"drift_optimal_slip_deg": 32,
			"drift_boost_max_reward": 28,
			"boost_power": 600,
			"boost_capacity": 110,
			"boost_recharge": 14,
			"boost_drain_rate": 36,
			"durability": 42,
		},
}


func _initialize() -> void:
	if not _test_catalog_resources():
		return
	if not _test_scene_default_parity():
		return
	if not _test_validation_diagnostics():
		return
	print("VEHICLE_STATS_RESOURCE_TEST PASS")
	quit(0)


func _test_catalog_resources() -> bool:
	for vehicle_id: String in VEHICLE_IDS:
		var definition := CATALOG.get_vehicle(vehicle_id)
		var stats_path := String(definition.get("stats_path", ""))
		if not _expect(stats_path == "res://data/vehicles/%s.tres" % vehicle_id, "%s should reference its canonical VehicleStats resource" % vehicle_id):
			return false
		var source := load(stats_path) as VehicleStats
		if not _expect(source != null, "%s stats resource should load" % vehicle_id):
			return false
		if not _expect(source.physics_model_version == VehicleStats.BICYCLE_MODEL_VERSION, "%s should be bicycle v1 (P3 default)" % vehicle_id):
			return false
		if not _expect(source.get_validation_errors().is_empty(), "%s target parameters should pass schema validation: %s" % [vehicle_id, ", ".join(source.get_validation_errors())]):
			return false
		var expected: Dictionary = TARGETS[vehicle_id]
		if not _expect(expected.size() == VehicleStats.PARAMETER_RANGES.size(), "%s target fixture should cover every versioned parameter" % vehicle_id):
			return false
		for property_name: String in VehicleStats.PARAMETER_RANGES:
			if not _expect(expected.has(property_name), "%s target fixture is missing %s" % [vehicle_id, property_name]):
				return false
			if not _expect(is_equal_approx(float(source.get(property_name)), float(expected[property_name])), "%s %s should match the GURI-557 target" % [vehicle_id, property_name]):
				return false
		var ratings: Dictionary = definition.get("ratings", {})
		if not _expect(ratings.keys().size() == 4, "%s should expose four presentation-only ratings" % vehicle_id):
			return false
		for rating_name: String in ["speed", "grip", "mass", "drift"]:
			var rating := float(ratings.get(rating_name, -1.0))
			if not _expect(rating >= 0.0 and rating <= 1.0, "%s %s presentation rating should be normalized" % [vehicle_id, rating_name]):
				return false
		var first := CATALOG.create_vehicle_stats(vehicle_id)
		var second := CATALOG.create_vehicle_stats(vehicle_id)
		if not _expect(first != source and second != source and first != second, "%s callers should receive independent deep duplicates" % vehicle_id):
			return false
		first.mass = VehicleStats.PARAMETER_RANGES["mass"][0]
		if not _expect(is_equal_approx(second.mass, source.mass), "%s duplicate mutation should not alter catalog data" % vehicle_id):
			return false
		# Legacy baseline tests explicitly select v0 (do not rely on default after P3 cutover;
		# do not alter expected numeric outputs or TARGETS).
		var leg := source.duplicate(true) as VehicleStats
		leg.physics_model_version = VehicleStats.LEGACY_MODEL_VERSION
		if not _expect(leg.physics_model_version == VehicleStats.LEGACY_MODEL_VERSION, "%s legacy baseline explicitly selects v0" % vehicle_id):
			return false
	return true


func _test_scene_default_parity() -> bool:
	var scene_vehicle := VEHICLE_SCENE.instantiate() as VehicleController
	var catalog_path := String(CATALOG.get_vehicle("rustbug").get("stats_path", ""))
	var matches := scene_vehicle != null and scene_vehicle.stats != null and scene_vehicle.stats.resource_path == catalog_path
	if scene_vehicle != null:
		scene_vehicle.free()
	return _expect(matches, "the shared vehicle scene default should reference the catalog Rustbug resource")


func _test_validation_diagnostics() -> bool:
	var invalid := CATALOG.create_vehicle_stats("rustbug")
	invalid.physics_model_version = 7
	invalid.mass = 0.0
	invalid.wheelbase = 10.0
	invalid.front_grip = 0.0
	invalid.torque_peak_ratio = 0.9
	invalid.drift_entry_steer = 0.9
	var diagnostics := "\n".join(invalid.get_validation_errors())
	for property_name: String in ["physics_model_version", "mass", "wheelbase", "front_grip", "torque_peak_ratio", "drift_entry_steer"]:
		if not _expect(diagnostics.contains(property_name) and diagnostics.contains("must be"), "invalid %s should produce an actionable range diagnostic" % property_name):
			return false
	return true


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("VEHICLE_STATS_RESOURCE_TEST FAIL: " + message)
	quit(1)
	return false
