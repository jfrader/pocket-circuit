class_name VehicleController
extends RigidBody2D

@export var stats: VehicleStats = preload("res://data/vehicles/rustbug.tres")

var speed: float = 0.0
var current_grip: float = 0.0
var slip_angle: float = 0.0
var is_drifting: bool = false
var boost_amount: float = 0.0
var current_surface: StringName = &"polished counter"

var _steer_input: float = 0.0
var _throttle_input: float = 0.0
var _brake_input: float = 0.0
var _boosting: bool = false


func _ready() -> void:
	mass = stats.mass
	boost_amount = stats.boost_capacity * 0.35
	gravity_scale = 0.0
	linear_damp = 0.0
	angular_damp = 2.5


func _physics_process(delta: float) -> void:
	_read_input()
	_update_debug_state()
	_apply_drive_forces(delta)
	_apply_lateral_grip()
	_apply_steering(delta)
	_update_boost(delta)
	_limit_top_speed()


func _read_input() -> void:
	_throttle_input = Input.get_action_strength("accelerate")
	_brake_input = Input.get_action_strength("brake")
	_steer_input = Input.get_axis("steer_left", "steer_right")
	_boosting = Input.is_action_pressed("boost") and boost_amount > 0.0


func _apply_drive_forces(_delta: float) -> void:
	var forward := Vector2.UP.rotated(rotation)
	var forward_speed := linear_velocity.dot(forward)
	var speed_ratio: float = clampf(absf(forward_speed) / stats.max_speed, 0.0, 1.0)

	if _throttle_input > 0.0 and forward_speed < stats.max_speed:
		var power_curve: float = maxf(0.1, 1.0 - speed_ratio)
		apply_central_force(forward * stats.engine_power * stats.acceleration * _throttle_input * power_curve)

	if _brake_input > 0.0:
		if forward_speed > 25.0:
			apply_central_force(-forward * stats.brake_force * _brake_input)
		elif forward_speed > -stats.reverse_speed:
			apply_central_force(-forward * stats.engine_power * 0.55 * _brake_input)

	if _boosting and _throttle_input > 0.0:
		apply_central_force(forward * stats.boost_power)

	if Input.is_action_pressed("handbrake") and speed > 80.0:
		apply_central_force(-linear_velocity.normalized() * stats.handbrake_force)

	apply_central_force(-linear_velocity * stats.grip * mass * 0.32)


func _apply_lateral_grip() -> void:
	var right := Vector2.RIGHT.rotated(rotation)
	var lateral_speed := linear_velocity.dot(right)
	current_grip = stats.lateral_grip
	if is_drifting:
		current_grip *= stats.drift_factor
	apply_central_force(-right * lateral_speed * current_grip * mass)


func _apply_steering(delta: float) -> void:
	var forward := Vector2.UP.rotated(rotation)
	var forward_speed := linear_velocity.dot(forward)
	var direction_sign: float = -1.0 if forward_speed < -10.0 else 1.0
	var speed_ratio: float = clampf(speed / stats.max_speed, 0.0, 1.0)
	var rolling_factor: float = clampf(speed / 70.0, 0.0, 1.0)
	var high_speed_response: float = lerpf(1.0, 0.52, speed_ratio)
	var drift_rotation: float = 1.65 if is_drifting else 1.0
	var target_angular_velocity := _steer_input * stats.steering_rate * rolling_factor * high_speed_response * drift_rotation * direction_sign
	var response := 1.0 - exp(-stats.steering_response * delta)
	angular_velocity = lerpf(angular_velocity, target_angular_velocity, response)


func _update_boost(delta: float) -> void:
	if _boosting and _throttle_input > 0.0:
		boost_amount = maxf(0.0, boost_amount - 32.0 * delta)
	elif is_drifting and absf(slip_angle) > 8.0 and absf(slip_angle) < 58.0:
		boost_amount = minf(stats.boost_capacity, boost_amount + stats.boost_recharge * delta)


func _update_debug_state() -> void:
	speed = linear_velocity.length()
	if speed > 2.0:
		var forward := Vector2.UP.rotated(rotation)
		slip_angle = rad_to_deg(forward.angle_to(linear_velocity.normalized()))
	else:
		slip_angle = 0.0
	is_drifting = (
		Input.is_action_pressed("handbrake")
		and absf(_steer_input) > 0.2
		and speed > 110.0
	)


func _limit_top_speed() -> void:
	var speed_limit := stats.max_speed * (1.2 if _boosting else 1.0)
	if linear_velocity.length() > speed_limit:
		linear_velocity = linear_velocity.limit_length(speed_limit)
