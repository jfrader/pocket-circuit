class_name AIVehicleController
extends Node

const STUCK_SPEED := 18.0
const STUCK_TIMEOUT := 2.2
const RECOVERY_GHOST_TIME := 1.0

var vehicle: VehicleController
var race_manager: RaceManager
var lane_offset: float = 0.0
var difficulty: String = "club_circuit"

var _checkpoints_by_index: Dictionary = {}
var _stuck_time: float = 0.0
var _recovering: bool = false


func configure(
		controlled_vehicle: VehicleController,
		manager: RaceManager,
		preferred_lane_offset: float,
		difficulty_id: String = "club_circuit"
) -> void:
	vehicle = controlled_vehicle
	race_manager = manager
	lane_offset = preferred_lane_offset
	difficulty = difficulty_id
	_cache_checkpoints()
	if not race_manager.race_started.is_connected(_cache_checkpoints):
		race_manager.race_started.connect(_cache_checkpoints)
	vehicle.set_player_controlled(false)


func _cache_checkpoints() -> void:
	_checkpoints_by_index.clear()
	for checkpoint: Node in race_manager.get_ordered_checkpoints():
		_checkpoints_by_index[int(checkpoint.get("checkpoint_index"))] = checkpoint


func _physics_process(delta: float) -> void:
	if not is_instance_valid(vehicle) or not is_instance_valid(race_manager) or _recovering:
		return
	if vehicle.controls_locked or not race_manager.is_running or race_manager.is_racer_finished(vehicle):
		vehicle.set_external_controls(0.0, 0.0, 0.0)
		_stuck_time = 0.0
		return

	var expected_index := race_manager.get_expected_checkpoint(vehicle)
	var target_checkpoint := _checkpoints_by_index.get(expected_index) as Node2D
	if target_checkpoint == null:
		vehicle.set_external_controls(0.0, 1.0, 0.0)
		return

	var next_checkpoint := race_manager.get_checkpoint_after(expected_index) as Node2D
	var previous_checkpoint := race_manager.get_checkpoint_before(expected_index) as Node2D
	var checkpoint_position := target_checkpoint.global_position
	var path_out := Vector2.UP.rotated(target_checkpoint.global_rotation)
	if next_checkpoint:
		path_out = (next_checkpoint.global_position - checkpoint_position).normalized()
	var path_in := path_out
	if previous_checkpoint:
		path_in = (checkpoint_position - previous_checkpoint.global_position).normalized()

	var lane_normal := path_out.orthogonal()
	var target_position := checkpoint_position + lane_normal * lane_offset
	var distance_to_gate := vehicle.global_position.distance_to(checkpoint_position)
	if next_checkpoint and distance_to_gate < 240.0:
		var look_ahead_weight := clampf((240.0 - distance_to_gate) / 520.0, 0.0, 0.4)
		target_position = target_position.lerp(next_checkpoint.global_position + lane_normal * lane_offset, look_ahead_weight)

	var desired_direction := vehicle.global_position.direction_to(target_position)
	var forward := Vector2.UP.rotated(vehicle.rotation)
	var steering_angle := forward.angle_to(desired_direction)
	var steering_divisor := 0.64 if difficulty == "clockwork" else 0.72
	var steer := clampf(steering_angle / steering_divisor, -1.0, 1.0)
	var turn_severity := absf(path_in.angle_to(path_out))
	var pace_multiplier := 0.82 if difficulty == "sunday_drive" else (1.04 if difficulty == "clockwork" else 1.0)
	var effective_max_speed := vehicle.get_effective_max_speed()
	var target_speed := effective_max_speed * lerpf(0.92, 0.46, clampf(turn_severity / 1.8, 0.0, 1.0)) * pace_multiplier
	if absf(steering_angle) > 1.05:
		target_speed = minf(target_speed, effective_max_speed * 0.38)

	var braking_distance := 390.0 if difficulty == "sunday_drive" else (275.0 if difficulty == "clockwork" else 330.0)
	var should_brake := vehicle.speed > target_speed and distance_to_gate < braking_distance
	var throttle := 0.28 if should_brake else 1.0
	var brake := clampf((vehicle.speed - target_speed) / 180.0, 0.0, 1.0) if should_brake else 0.0
	var handbrake := turn_severity > 0.82 and distance_to_gate < 230.0 and vehicle.speed > 170.0
	var position := race_manager.get_racer_position(vehicle)
	var catch_up_steps := maxi(0, position - 1)
	var catch_up_power := minf(0.08, float(catch_up_steps) * 0.025) if difficulty == "club_circuit" else 0.0
	vehicle.set_external_power_multiplier(1.0 + catch_up_power)
	var boost := (
		position > 1
		and absf(steering_angle) < 0.18
		and turn_severity < 0.38
		and not should_brake
		and vehicle.speed > 220.0
	)
	vehicle.set_external_controls(throttle, brake, steer, handbrake, boost)

	if throttle > 0.7 and vehicle.speed < STUCK_SPEED:
		_stuck_time += delta
		if _stuck_time >= STUCK_TIMEOUT:
			_recover_vehicle()
	else:
		_stuck_time = maxf(0.0, _stuck_time - delta * 2.0)


func _recover_vehicle() -> void:
	if _recovering:
		return
	_recovering = true
	_stuck_time = 0.0
	vehicle.set_external_controls(0.0, 0.0, 0.0)
	var saved_layer := vehicle.collision_layer
	var saved_mask := vehicle.collision_mask
	var recovery_transform := race_manager.get_last_recovery_transform(vehicle)
	var recovery_forward := Vector2.UP.rotated(recovery_transform.get_rotation())
	vehicle.freeze = true
	vehicle.global_transform = recovery_transform
	vehicle.linear_velocity = Vector2.ZERO
	vehicle.angular_velocity = 0.0
	vehicle.reset_surface_modifiers()
	vehicle.collision_layer = 0
	vehicle.collision_mask = 0
	vehicle.modulate.a = 0.45
	vehicle.freeze = false
	vehicle.linear_velocity = recovery_forward * 55.0
	vehicle.boost_amount *= 0.5

	await get_tree().create_timer(RECOVERY_GHOST_TIME, false).timeout
	if is_instance_valid(vehicle):
		vehicle.collision_layer = saved_layer
		vehicle.collision_mask = saved_mask
		vehicle.modulate.a = 1.0
	_recovering = false
