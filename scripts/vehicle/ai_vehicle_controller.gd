class_name AIVehicleController
extends Node

const STUCK_TIMEOUT := 2.2
const STUCK_SPEED := 85.0
const RECOVERY_GHOST_TIME := 1.0
const CORNER_GUIDE_AXIS_THRESHOLD := 180.0
const CORNER_GUIDE_BLEND_DISTANCE := 180.0
const CORNER_GUIDE_REACHED_DISTANCE := 40.0
const CORNER_GUIDE_OUTWARD_OFFSET := 15.0
const CORNER_GUIDE_PASS_WIDTH := 80.0
const LOOK_AHEAD_DISTANCE := 240.0
const MAX_LOOK_AHEAD_WEIGHT := 0.22
const TRACK_COLLISION_MASK := 2
const OBSTACLE_FEELER_ANGLE := 0.52
const OBSTACLE_FEELER_HALF_WIDTH := 16.0
const GATE_TARGET_OFFSETS: Array[float] = [-72.0, -48.0, -24.0, 0.0, 24.0, 48.0, 72.0]

var vehicle: VehicleController
var race_manager: RaceManager
var lane_offset: float = 0.0
var difficulty: String = "club_circuit"
var recovery_count := 0

var _checkpoints_by_index: Dictionary = {}
var _gate_targets: Dictionary = {}
var _stuck_time: float = 0.0
var _recovering: bool = false
var _track_center := Vector2.ZERO
var _guide_checkpoint_index := -1
var _guide_reached := false
var _stuck_target_key := ""
var _best_checkpoint_distance := INF
var _smoothed_steer := 0.0


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
	_gate_targets.clear()
	_track_center = Vector2.ZERO
	for checkpoint: Node in race_manager.get_ordered_checkpoints():
		_checkpoints_by_index[int(checkpoint.get("checkpoint_index"))] = checkpoint
		_track_center += (checkpoint as Node2D).global_position
	if not _checkpoints_by_index.is_empty():
		_track_center /= float(_checkpoints_by_index.size())


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
	var checkpoint_position := target_checkpoint.global_position
	var target_position := _active_target_position(expected_index)
	var targeting_guide := not _guide_reached
	var distance_to_target := vehicle.global_position.distance_to(target_position)
	var distance_to_gate := vehicle.global_position.distance_to(checkpoint_position)
	if next_checkpoint and not targeting_guide and distance_to_gate < LOOK_AHEAD_DISTANCE:
		var look_ahead_weight := clampf(
			(LOOK_AHEAD_DISTANCE - distance_to_gate) / LOOK_AHEAD_DISTANCE,
			0.0,
			MAX_LOOK_AHEAD_WEIGHT
		)
		var next_index := int(next_checkpoint.get("checkpoint_index"))
		var next_guide: Variant = _checkpoint_entry_guide_position(next_index)
		var next_target: Vector2 = _checkpoint_target_position(next_index)
		if next_guide != null:
			next_target = next_guide
		target_position = target_position.lerp(
			next_target,
			look_ahead_weight
		)

	var desired_direction := vehicle.global_position.direction_to(target_position)
	var forward := Vector2.UP.rotated(vehicle.rotation)
	var steering_angle := forward.angle_to(desired_direction)
	var steering_divisor := 0.64 if difficulty == "clockwork" else 0.72
	var requested_steer := clampf(steering_angle / steering_divisor, -1.0, 1.0)
	var obstacle_plan := _obstacle_avoidance(forward, desired_direction)
	requested_steer = lerpf(
		requested_steer,
		float(obstacle_plan["steer"]),
		float(obstacle_plan["weight"])
	)
	var steering_response := 11.0 if difficulty == "sunday_drive" else (16.0 if difficulty == "clockwork" else 13.0)
	_smoothed_steer = lerpf(_smoothed_steer, requested_steer, 1.0 - exp(-steering_response * delta))
	var turn_severity := _checkpoint_turn_severity(expected_index)
	var next_turn_severity := 0.0
	if next_checkpoint:
		next_turn_severity = _checkpoint_turn_severity(int(next_checkpoint.get("checkpoint_index")))
	var planned_turn_severity := maxf(turn_severity, next_turn_severity * 0.84)
	var corner_ratio := clampf(planned_turn_severity / 1.45, 0.0, 1.0)
	var pace_multiplier := 0.82 if difficulty == "sunday_drive" else (1.04 if difficulty == "clockwork" else 1.0)
	var effective_max_speed := vehicle.get_effective_max_speed()
	var handling_pace := clampf(vehicle.stats.steering_rate / 3.75, 0.78, 1.08)
	var target_speed := effective_max_speed * lerpf(0.92, 0.22, corner_ratio) * pace_multiplier
	target_speed *= lerpf(1.0, handling_pace, corner_ratio)
	target_speed *= float(obstacle_plan["speed_scale"])
	if absf(steering_angle) > 1.05:
		target_speed = minf(target_speed, effective_max_speed * 0.36)

	var braking_distance := lerpf(280.0, 560.0, corner_ratio)
	braking_distance *= 1.12 if difficulty == "sunday_drive" else (0.9 if difficulty == "clockwork" else 1.0)
	var should_brake := vehicle.speed > target_speed and distance_to_target < braking_distance
	var throttle := 0.0 if should_brake else 1.0
	var brake := clampf((vehicle.speed - target_speed) / 90.0, 0.0, 1.0) if should_brake else 0.0
	var position := race_manager.get_racer_position(vehicle)
	var catch_up_steps := maxi(0, position - 1)
	var catch_up_power := minf(0.08, float(catch_up_steps) * 0.025) if difficulty == "club_circuit" else 0.0
	vehicle.set_external_power_multiplier(1.0 + catch_up_power)
	var boost := (
		position > 1
		and absf(steering_angle) < 0.26
		and turn_severity < 0.45
		and not should_brake
		and vehicle.speed > 180.0
	)
	vehicle.set_external_controls(throttle, brake, _smoothed_steer, false, boost)
	var stuck_target_key := "%d:%s" % [expected_index, "guide" if targeting_guide else "gate"]
	_update_stuck_recovery(delta, stuck_target_key, distance_to_target)


func _active_target_position(checkpoint_index: int) -> Vector2:
	if checkpoint_index != _guide_checkpoint_index:
		_guide_checkpoint_index = checkpoint_index
		_guide_reached = false
	var guide_position: Variant = _checkpoint_entry_guide_position(checkpoint_index)
	if guide_position == null:
		_guide_reached = true
		return _checkpoint_target_position(checkpoint_index)
	var guide_target: Vector2 = guide_position
	if not _guide_reached:
		var guide_distance := vehicle.global_position.distance_to(guide_target)
		var checkpoint_target := _checkpoint_target_position(checkpoint_index)
		if guide_distance <= CORNER_GUIDE_REACHED_DISTANCE or _has_passed_guide(guide_target, checkpoint_target):
			_guide_reached = true
		else:
			var blend_weight := clampf(
				(CORNER_GUIDE_BLEND_DISTANCE - guide_distance) / CORNER_GUIDE_BLEND_DISTANCE,
				0.0,
				0.68
			)
			return guide_target.lerp(_checkpoint_target_position(checkpoint_index), blend_weight)
	return _checkpoint_target_position(checkpoint_index)


func _has_passed_guide(guide_position: Vector2, checkpoint_position: Vector2) -> bool:
	var outgoing_direction := guide_position.direction_to(checkpoint_position)
	var relative_position := vehicle.global_position - guide_position
	return (
		relative_position.dot(outgoing_direction) > 0.0
		and absf(relative_position.cross(outgoing_direction)) <= CORNER_GUIDE_PASS_WIDTH
	)


func _checkpoint_entry_guide_position(checkpoint_index: int) -> Variant:
	var checkpoint := _checkpoints_by_index.get(checkpoint_index) as Node2D
	var previous := race_manager.get_checkpoint_before(checkpoint_index) as Node2D
	if checkpoint == null or previous == null:
		return null
	var segment := checkpoint.global_position - previous.global_position
	if (
		absf(segment.x) < CORNER_GUIDE_AXIS_THRESHOLD
		or absf(segment.y) < CORNER_GUIDE_AXIS_THRESHOLD
	):
		return null
	var x_then_y := Vector2(checkpoint.global_position.x, previous.global_position.y)
	var y_then_x := Vector2(previous.global_position.x, checkpoint.global_position.y)
	var guide_position := y_then_x
	if x_then_y.distance_squared_to(_track_center) > y_then_x.distance_squared_to(_track_center):
		guide_position = x_then_y
	var outward_offset := Vector2.ZERO
	if absf(segment.x) >= absf(segment.y):
		outward_offset.y = signf(guide_position.y - _track_center.y) * CORNER_GUIDE_OUTWARD_OFFSET
	else:
		outward_offset.x = signf(guide_position.x - _track_center.x) * CORNER_GUIDE_OUTWARD_OFFSET
	return guide_position + outward_offset


func _checkpoint_target_position(checkpoint_index: int) -> Vector2:
	if _gate_targets.has(checkpoint_index):
		return _gate_targets[checkpoint_index]
	var checkpoint := _checkpoints_by_index.get(checkpoint_index) as Node2D
	if checkpoint == null:
		return vehicle.global_position if is_instance_valid(vehicle) else Vector2.ZERO
	var corner_ratio := clampf(_checkpoint_turn_severity(checkpoint_index) / 1.45, 0.0, 1.0)
	var gate_lane_direction := Vector2.DOWN.rotated(checkpoint.global_rotation)
	var lane_scale := lerpf(1.0, 0.1, corner_ratio)
	var preferred_target := (
		checkpoint.global_position
		+ gate_lane_direction * lane_offset * lane_scale
	)
	var selected_target := _select_clear_gate_target(
		checkpoint_index,
		checkpoint.global_position,
		gate_lane_direction,
		preferred_target
	)
	_gate_targets[checkpoint_index] = selected_target
	return selected_target


func _select_clear_gate_target(
		checkpoint_index: int,
		checkpoint_position: Vector2,
		gate_lane_direction: Vector2,
		preferred_target: Vector2
) -> Vector2:
	if not vehicle.is_inside_tree():
		return preferred_target
	var entry_position: Vector2
	var guide_position: Variant = _checkpoint_entry_guide_position(checkpoint_index)
	if guide_position != null:
		entry_position = guide_position
	else:
		var previous := race_manager.get_checkpoint_before(checkpoint_index) as Node2D
		entry_position = previous.global_position if previous else vehicle.global_position
	var best_target := preferred_target
	var best_score := -INF
	for offset: float in GATE_TARGET_OFFSETS:
		var candidate := checkpoint_position + gate_lane_direction * offset
		var path := entry_position.direction_to(candidate)
		var path_length := entry_position.distance_to(candidate)
		var clearance := _ray_clearance_from(entry_position, path, path_length)
		var preference_penalty := candidate.distance_to(preferred_target) / 10000.0
		var score := clearance - preference_penalty
		if score > best_score:
			best_score = score
			best_target = candidate
	return best_target


func _checkpoint_turn_severity(checkpoint_index: int) -> float:
	var checkpoint := _checkpoints_by_index.get(checkpoint_index) as Node2D
	var previous := race_manager.get_checkpoint_before(checkpoint_index) as Node2D
	var next := race_manager.get_checkpoint_after(checkpoint_index) as Node2D
	if checkpoint == null or previous == null or next == null:
		return 0.0
	var guide_position: Variant = _checkpoint_entry_guide_position(checkpoint_index)
	if guide_position != null:
		var guide: Vector2 = guide_position
		var guide_path_in := (guide - previous.global_position).normalized()
		var guide_path_out := (checkpoint.global_position - guide).normalized()
		return absf(guide_path_in.angle_to(guide_path_out))
	var path_in := (checkpoint.global_position - previous.global_position).normalized()
	var path_out := (next.global_position - checkpoint.global_position).normalized()
	return absf(path_in.angle_to(path_out))


func _obstacle_avoidance(forward: Vector2, desired_direction: Vector2) -> Dictionary:
	var plan := {"steer": 0.0, "weight": 0.0, "speed_scale": 1.0}
	if not vehicle.is_inside_tree():
		return plan
	var feeler_length := clampf(vehicle.speed * 0.6, 140.0, 300.0)
	var center_clearance := _ray_clearance(desired_direction, feeler_length)
	if center_clearance >= 0.98:
		return plan
	var left_direction := desired_direction.rotated(-OBSTACLE_FEELER_ANGLE)
	var right_direction := desired_direction.rotated(OBSTACLE_FEELER_ANGLE)
	var left_clearance := _ray_clearance(left_direction, feeler_length)
	var right_clearance := _ray_clearance(right_direction, feeler_length)
	var chosen_direction := left_direction if left_clearance > right_clearance else right_direction
	if is_equal_approx(left_clearance, right_clearance):
		chosen_direction = left_direction if left_direction.dot(desired_direction) > right_direction.dot(desired_direction) else right_direction
	var obstruction := 1.0 - center_clearance
	plan["steer"] = clampf(forward.angle_to(chosen_direction) / OBSTACLE_FEELER_ANGLE, -1.0, 1.0)
	plan["weight"] = clampf(0.38 + obstruction * 0.52, 0.0, 0.9)
	plan["speed_scale"] = lerpf(0.72, 0.46, obstruction)
	return plan


func _ray_clearance(direction: Vector2, feeler_length: float) -> float:
	return _ray_clearance_from(vehicle.global_position, direction, feeler_length)


func _ray_clearance_from(origin: Vector2, direction: Vector2, feeler_length: float) -> float:
	if feeler_length <= 0.001:
		return 1.0
	var side_offset := direction.orthogonal() * OBSTACLE_FEELER_HALF_WIDTH
	return minf(
		_single_ray_clearance(origin, direction, feeler_length),
		minf(
			_single_ray_clearance(origin + side_offset, direction, feeler_length),
			_single_ray_clearance(origin - side_offset, direction, feeler_length)
		)
	)


func _single_ray_clearance(origin: Vector2, direction: Vector2, feeler_length: float) -> float:
	var query := PhysicsRayQueryParameters2D.create(
		origin,
		origin + direction * feeler_length,
		TRACK_COLLISION_MASK,
		[vehicle.get_rid()]
	)
	var hit := vehicle.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return 1.0
	return origin.distance_to(hit["position"]) / feeler_length


func _update_stuck_recovery(delta: float, target_key: String, distance_to_target: float) -> void:
	if target_key != _stuck_target_key:
		_stuck_target_key = target_key
		_best_checkpoint_distance = distance_to_target
		_stuck_time = 0.0
		return
	if distance_to_target < _best_checkpoint_distance - 18.0:
		_best_checkpoint_distance = distance_to_target
		_stuck_time = 0.0
		return
	if vehicle.speed >= STUCK_SPEED:
		_stuck_time = 0.0
		return
	_stuck_time += delta
	if _stuck_time >= STUCK_TIMEOUT:
		_recover_vehicle()


func _recover_vehicle() -> void:
	if _recovering:
		return
	_recovering = true
	recovery_count += 1
	_stuck_time = 0.0
	_guide_checkpoint_index = -1
	_guide_reached = false
	_stuck_target_key = ""
	_best_checkpoint_distance = INF
	_smoothed_steer = 0.0
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
	vehicle.linear_velocity = recovery_forward * 85.0
	vehicle.boost_amount *= 0.5

	await get_tree().create_timer(RECOVERY_GHOST_TIME, false).timeout
	if is_instance_valid(vehicle):
		vehicle.collision_layer = saved_layer
		vehicle.collision_mask = saved_mask
		vehicle.modulate.a = 1.0
	_recovering = false
