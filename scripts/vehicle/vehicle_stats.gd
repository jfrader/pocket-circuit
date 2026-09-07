class_name VehicleStats
extends Resource

const LEGACY_MODEL_VERSION := 0
const BICYCLE_MODEL_VERSION := 1
const PARAMETER_RANGES := {
	"mass": [0.65, 1.30, "sm"],
	"wheelbase": [34.0, 46.0, "wu"],
	"front_weight_ratio": [0.45, 0.58, "ratio"],
	"engine_force": [600.0, 1300.0, "sf"],
	"launch_torque_multiplier": [0.90, 1.20, "multiplier"],
	"torque_peak_ratio": [0.20, 0.45, "speed ratio"],
	"torque_at_max_speed": [0.25, 0.45, "multiplier"],
	"torque_falloff_exponent": [1.10, 2.50, "exponent"],
	"max_speed": [600.0, 750.0, "wu/s"],
	"reverse_speed": [180.0, 280.0, "wu/s"],
	"rolling_resistance": [10.0, 35.0, "sf"],
	"aero_drag_coefficient": [0.00035, 0.00095, "sm/wu"],
	"front_grip": [0.85, 1.40, "mu"],
	"rear_grip": [0.85, 1.40, "mu"],
	"front_cornering_stiffness": [2500.0, 5000.0, "sf/rad"],
	"rear_cornering_stiffness": [2500.0, 5000.0, "sf/rad"],
	"post_peak_grip_ratio": [0.50, 0.80, "ratio"],
	"slip_falloff_rate": [0.15, 0.60, "rate"],
	"max_steer_angle_deg": [26.0, 38.0, "deg"],
	"steering_response": [5.0, 13.0, "1/s"],
	"high_speed_steer_ratio": [0.38, 0.62, "ratio"],
	"steer_fade_start_ratio": [0.22, 0.45, "speed ratio"],
	"yaw_stability_rate": [3.0, 11.0, "1/s"],
	"brake_force": [800.0, 1400.0, "sf"],
	"handbrake_force": [180.0, 420.0, "sf"],
	"drift_min_speed": [100.0, 170.0, "wu/s"],
	"drift_entry_steer": [0.25, 0.48, "input ratio"],
	"drift_rear_grip_ratio": [0.25, 0.55, "ratio"],
	"drift_yaw_assist": [1.0, 3.5, "rad/s^2"],
	"drift_grip_recovery_rate": [4.0, 11.0, "1/s"],
	"drift_optimal_slip_deg": [20.0, 36.0, "deg"],
	"drift_boost_max_reward": [8.0, 30.0, "units"],
	"boost_power": [450.0, 700.0, "sf"],
	"boost_capacity": [85.0, 115.0, "units"],
	"boost_recharge": [7.0, 14.0, "units/s"],
	"boost_drain_rate": [28.0, 38.0, "units/s"],
	"durability": [40.0, 80.0, "rating"],
}

@export_category("Physics model")
@export_enum("Legacy:0", "Bicycle:1") var physics_model_version: int = BICYCLE_MODEL_VERSION

@export_category("Chassis and powertrain")
@export_range(0.65, 1.30) var mass: float = 1.0
@export_range(34.0, 46.0) var wheelbase: float = 39.0
@export_range(0.45, 0.58) var front_weight_ratio: float = 0.52
@export_range(600.0, 1300.0) var engine_force: float = 820.0
@export_range(0.90, 1.20) var launch_torque_multiplier: float = 1.08
@export_range(0.20, 0.45) var torque_peak_ratio: float = 0.30
@export_range(0.25, 0.45) var torque_at_max_speed: float = 0.37
@export_range(1.10, 2.50) var torque_falloff_exponent: float = 1.65
@export_range(600.0, 750.0) var max_speed: float = 680.0
@export_range(180.0, 280.0) var reverse_speed: float = 240.0
@export_range(10.0, 35.0) var rolling_resistance: float = 18.0
@export_range(0.00035, 0.00095, 0.000001) var aero_drag_coefficient: float = 0.000617

@export_category("Tires and steering")
@export_range(0.85, 1.40) var front_grip: float = 1.15
@export_range(0.85, 1.40) var rear_grip: float = 1.18
@export_range(2500.0, 5000.0) var front_cornering_stiffness: float = 3600.0
@export_range(2500.0, 5000.0) var rear_cornering_stiffness: float = 3500.0
@export_range(0.50, 0.80) var post_peak_grip_ratio: float = 0.68
@export_range(0.15, 0.60) var slip_falloff_rate: float = 0.28
@export_range(26.0, 38.0) var max_steer_angle_deg: float = 32.0
@export_range(5.0, 13.0) var steering_response: float = 8.5
@export_range(0.38, 0.62) var high_speed_steer_ratio: float = 0.48
@export_range(0.22, 0.45) var steer_fade_start_ratio: float = 0.30
@export_range(3.0, 11.0) var yaw_stability_rate: float = 8.0

@export_category("Brakes and drift")
@export_range(800.0, 1400.0) var brake_force: float = 1050.0
@export_range(180.0, 420.0) var handbrake_force: float = 270.0
@export_range(100.0, 170.0) var drift_min_speed: float = 130.0
@export_range(0.25, 0.48) var drift_entry_steer: float = 0.35
@export_range(0.25, 0.55) var drift_rear_grip_ratio: float = 0.40
@export_range(1.0, 3.5) var drift_yaw_assist: float = 2.0
@export_range(4.0, 11.0) var drift_grip_recovery_rate: float = 7.0
@export_range(20.0, 36.0) var drift_optimal_slip_deg: float = 26.0
@export_range(8.0, 30.0) var drift_boost_max_reward: float = 16.0

@export_category("Boost and durability")
@export_range(450.0, 700.0) var boost_power: float = 560.0
@export_range(85.0, 115.0) var boost_capacity: float = 100.0
@export_range(7.0, 14.0) var boost_recharge: float = 10.0
@export_range(28.0, 38.0) var boost_drain_rate: float = 32.0
@export_range(40.0, 80.0) var durability: float = 52.0

@export_category("Legacy model v0")
@export var engine_power: float = 650.0
@export var acceleration: float = 1.0
@export var steering_rate: float = 3.5
@export var grip: float = 0.9
@export var lateral_grip: float = 11.0
@export_range(0.05, 1.0) var drift_factor: float = 0.3
@export var legacy_mass: float = 1.0
@export var legacy_max_speed: float = 650.0
@export var legacy_reverse_speed: float = 250.0
@export var legacy_steering_response: float = 9.0
@export var legacy_brake_force: float = 1000.0
@export var legacy_handbrake_force: float = 260.0
@export var legacy_boost_power: float = 500.0
@export var legacy_boost_capacity: float = 100.0
@export var legacy_boost_recharge: float = 9.0
@export var legacy_durability: float = 55.0


func get_validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if physics_model_version != LEGACY_MODEL_VERSION and physics_model_version != BICYCLE_MODEL_VERSION:
		errors.append("physics_model_version must be 0 (legacy) or 1 (bicycle); got %d" % physics_model_version)
	for property_name: String in PARAMETER_RANGES:
		var bounds: Array = PARAMETER_RANGES[property_name]
		var value := float(get(property_name))
		var minimum := float(bounds[0])
		var maximum := float(bounds[1])
		if is_nan(value) or is_inf(value) or value < minimum or value > maximum:
			errors.append(
				"%s must be between %s and %s %s; got %s"
				% [property_name, str(minimum), str(maximum), String(bounds[2]), str(value)]
			)
	return errors


func is_valid() -> bool:
	return get_validation_errors().is_empty()


func get_legacy_mass() -> float:
	return legacy_mass


func get_legacy_max_speed() -> float:
	return legacy_max_speed


func get_legacy_reverse_speed() -> float:
	return legacy_reverse_speed


func get_legacy_steering_response() -> float:
	return legacy_steering_response


func get_legacy_brake_force() -> float:
	return legacy_brake_force


func get_legacy_handbrake_force() -> float:
	return legacy_handbrake_force


func get_legacy_boost_power() -> float:
	return legacy_boost_power


func get_legacy_boost_capacity() -> float:
	return legacy_boost_capacity


func get_legacy_boost_recharge() -> float:
	return legacy_boost_recharge


func get_legacy_durability() -> float:
	return legacy_durability
