class_name VehicleController
extends RigidBody2D

const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const COLLISION_RESPONSE := preload("res://scripts/vehicle/collision_response_policy.gd")
const CONTACT_RELEASE_GRACE := 0.12
const RACER_TAG_Y_OFFSETS := [-64.0, -84.0, -84.0, -64.0]
const MAX_EXTERNAL_POWER_MULTIPLIER := 1.15
const LEGACY_ANGULAR_DAMP := 2.5
const LEGACY_ENGINE_CURVE_MIN := 0.1
const LEGACY_BRAKE_TO_REVERSE_SPEED := 25.0
const LEGACY_REVERSE_ENGINE_FACTOR := 0.55
const LEGACY_HANDBRAKE_MIN_SPEED := 80.0
const LEGACY_LINEAR_DAMPING_RATE := 0.32
const LEGACY_REVERSE_STEER_THRESHOLD := -10.0
const LEGACY_FULL_STEER_SPEED := 70.0
const LEGACY_HIGH_SPEED_STEER_RATIO := 0.52
const LEGACY_DRIFT_ROTATION_MULTIPLIER := 1.65
const LEGACY_BOOST_DRAIN_RATE := 32.0
const LEGACY_BOOST_SLIP_MIN_DEG := 8.0
const LEGACY_BOOST_SLIP_MAX_DEG := 58.0
const LEGACY_SLIP_MEASUREMENT_MIN_SPEED := 2.0
const LEGACY_DRIFT_ENTRY_STEER := 0.2
const LEGACY_DRIFT_MIN_SPEED := 110.0
const NORMAL_SPEED_CAP_MULTIPLIER := 1.0
const BOOST_SPEED_CAP_MULTIPLIER := 1.2

enum ControlMode { PLAYER, EXTERNAL }

@export var stats: VehicleStats = preload("res://data/vehicles/rustbug.tres")
@export var control_mode: ControlMode = ControlMode.PLAYER

var speed: float = 0.0
var current_grip: float = 0.0
var slip_angle: float = 0.0
var is_drifting: bool = false
var boost_amount: float = 0.0
var current_surface: StringName = &"polished counter"
var surface_grip_multiplier: float = 1.0
var surface_speed_multiplier: float = 1.0
var driver_display_name: String = "Driver"
var vehicle_display_name: String = "Rustbug"
var controls_locked: bool = false

var _steer_input: float = 0.0
var _throttle_input: float = 0.0
var _brake_input: float = 0.0
var _handbrake_input: bool = false
var _boosting: bool = false
var _external_steer: float = 0.0
var _external_throttle: float = 0.0
var _external_brake: float = 0.0
var _external_handbrake: bool = false
var _external_boost: bool = false
var _external_power_multiplier: float = 1.0
var _base_surface: StringName = &"polished counter"
var _surface_modifiers: Dictionary = {}
var _surface_sequence: int = 0
var _contact_elapsed := 0.0
var _contact_pair_last_seen: Dictionary = {}
var _last_output_velocity := Vector2.ZERO
var last_collision_response: Dictionary = {}
var has_static_contact := false
var static_contact_normal := Vector2.ZERO
var _racer_tag: Label
var _racer_tag_offset := Vector2(-45.0, -64.0)
var _drift_boost_accumulated := 0.0
var _drift_grace_timer := 0.0
var _front_slip_angle := 0.0
var _rear_slip_angle := 0.0
var _last_speed := 0.0
var _drift_entry_speed := 0.0



func _ready() -> void:
	apply_stats(stats)
	gravity_scale = 0.0
	linear_damp = 0.0
	angular_damp = LEGACY_ANGULAR_DAMP
	var physics_material := PhysicsMaterial.new()
	physics_material.bounce = 0.0
	physics_material.friction = 0.06
	physics_material.absorbent = true
	physics_material_override = physics_material
	_last_output_velocity = linear_velocity


func _physics_process(delta: float) -> void:
	if is_instance_valid(_racer_tag):
		_racer_tag.global_position = global_position + _racer_tag_offset
	_read_input()
	_update_motion_state()
	_apply_drive_forces(delta)
	_apply_lateral_grip()
	_apply_steering(delta)
	_update_boost(delta)
	_limit_top_speed()


func _read_input() -> void:
	if controls_locked:
		_throttle_input = 0.0
		_brake_input = 0.0
		_steer_input = 0.0
		_handbrake_input = false
		_boosting = false
		return

	if control_mode == ControlMode.PLAYER:
		_throttle_input = Input.get_action_strength("accelerate")
		_brake_input = Input.get_action_strength("brake")
		_steer_input = Input.get_axis("steer_left", "steer_right")
		_handbrake_input = Input.is_action_pressed("handbrake")
		_boosting = Input.is_action_pressed("boost") and boost_amount > 0.0
	else:
		_throttle_input = _external_throttle
		_brake_input = _external_brake
		_steer_input = _external_steer
		_handbrake_input = _external_handbrake
		_boosting = _external_boost and boost_amount > 0.0


func set_player_controlled(player_controlled: bool) -> void:
	control_mode = ControlMode.PLAYER if player_controlled else ControlMode.EXTERNAL
	if player_controlled:
		_external_power_multiplier = 1.0


func set_controls_locked(locked: bool) -> void:
	controls_locked = locked
	if locked:
		set_external_controls(0.0, 0.0, 0.0, false, false)


func set_external_controls(
		throttle: float,
		brake: float,
		steer: float,
		handbrake: bool = false,
		boost: bool = false
) -> void:
	_external_throttle = clampf(throttle, 0.0, 1.0)
	_external_brake = clampf(brake, 0.0, 1.0)
	_external_steer = clampf(steer, -1.0, 1.0)
	_external_handbrake = handbrake
	_external_boost = boost


func set_external_power_multiplier(multiplier: float) -> void:
	# External racers may accelerate up to 15% harder, but the shared speed
	# limiter below still enforces the same 1.0x/1.2x normal/boosted caps.
	_external_power_multiplier = clampf(multiplier, 1.0, MAX_EXTERNAL_POWER_MULTIPLIER)


func configure_identity(driver_name: String, racer_vehicle_name: String, vehicle_id: String = "") -> void:
	driver_display_name = driver_name
	vehicle_display_name = racer_vehicle_name
	set_meta(&"driver_display_name", driver_name)
	set_meta(&"vehicle_display_name", racer_vehicle_name)
	configure_visual_identity(vehicle_id)
	_configure_racer_tag(driver_name)


func configure_visual_identity(vehicle_id: String) -> void:
	var visual_root := get_node_or_null("VisualRoot") as Node2D
	if visual_root == null:
		return
	var existing := visual_root.get_node_or_null("IdentityAccents")
	if existing:
		existing.free()
	if vehicle_id.is_empty():
		return
	var texture := IDENTITIES.car_texture(vehicle_id)
	var car_sprite := visual_root.get_node_or_null("CarSprite") as Sprite2D
	if texture == null or car_sprite == null:
		return
	car_sprite.texture = texture
	car_sprite.scale = Vector2.ONE
	car_sprite.self_modulate = Color.WHITE
	car_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var legacy_shadow := visual_root.get_node_or_null("ShadowSprite") as Sprite2D
	if legacy_shadow:
		legacy_shadow.visible = false


func _configure_racer_tag(driver_name: String) -> void:
	var visual_root := get_node_or_null("VisualRoot") as Node2D
	if visual_root == null:
		return
	var existing := visual_root.get_node_or_null("RacerTag")
	if existing:
		existing.free()
	var tag := Label.new()
	tag.name = "RacerTag"
	tag.text = "YOU" if control_mode == ControlMode.PLAYER else driver_name.to_upper()
	tag.position = _racer_tag_offset
	tag.size = Vector2(90.0, 18.0)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 10)
	tag.add_theme_color_override("font_color", Color("f5f0e3"))
	tag.add_theme_color_override("font_outline_color", Color("0e151f"))
	tag.add_theme_constant_override("outline_size", 4)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.top_level = true
	tag.z_index = 4
	visual_root.add_child(tag)
	_racer_tag = tag
	_racer_tag.global_position = global_position + _racer_tag_offset


func configure_racer_marker(marker_color: Color, racer_index: int = 0) -> void:
	_racer_tag_offset.y = RACER_TAG_Y_OFFSETS[clampi(racer_index, 0, RACER_TAG_Y_OFFSETS.size() - 1)]
	if is_instance_valid(_racer_tag):
		_racer_tag.global_position = global_position + _racer_tag_offset
	var visual_root := get_node_or_null("VisualRoot") as Node2D
	if visual_root == null:
		return
	var existing := visual_root.get_node_or_null("RacerMarker")
	if existing:
		existing.free()
	var marker := Line2D.new()
	marker.name = "RacerMarker"
	marker.points = PackedVector2Array([Vector2(-7.0, 29.0), Vector2(0.0, 35.0), Vector2(7.0, 29.0)])
	marker.width = 3.0
	marker.default_color = marker_color
	marker.antialiased = false
	marker.z_index = 3
	visual_root.add_child(marker)


func apply_stats(new_stats: VehicleStats) -> void:
	if new_stats == null:
		return
	stats = new_stats
	mass = stats.get_legacy_mass()
	boost_amount = stats.get_legacy_boost_capacity() * 0.35


func configure_base_surface(surface_name: StringName) -> void:
	_base_surface = surface_name
	_refresh_surface_modifier()


func apply_surface_modifier(source_id: int, surface_name: StringName, grip_multiplier: float, speed_multiplier: float) -> void:
	_surface_sequence += 1
	_surface_modifiers[source_id] = {
		"name": surface_name,
		"grip": clampf(grip_multiplier, 0.2, 1.5),
		"speed": clampf(speed_multiplier, 0.2, 1.5),
		"sequence": _surface_sequence,
	}
	_refresh_surface_modifier()


func clear_surface_modifier(source_id: int) -> void:
	_surface_modifiers.erase(source_id)
	_refresh_surface_modifier()


func reset_surface_modifiers() -> void:
	_surface_modifiers.clear()
	_refresh_surface_modifier()


func get_effective_max_speed() -> float:
	if stats.physics_model_version == 1:
		return VehicleDynamics.get_effective_max_speed(stats, surface_speed_multiplier)
	return stats.get_legacy_max_speed() * surface_speed_multiplier


func get_boost_capacity() -> float:
	if stats.physics_model_version == 1:
		return stats.boost_capacity
	return stats.get_legacy_boost_capacity()

func add_boost(amount: float, source: String = "general") -> void:
	boost_amount = clampf(boost_amount + amount, 0.0, get_boost_capacity())

func reset_dynamics_state() -> void:
	is_drifting = false
	_drift_boost_accumulated = 0.0
	_drift_grace_timer = 0.0
	_drift_entry_speed = 0.0


func _refresh_surface_modifier() -> void:
	current_surface = _base_surface
	surface_grip_multiplier = 1.0
	surface_speed_multiplier = 1.0
	var selected_sequence := -1
	for modifier: Dictionary in _surface_modifiers.values():
		if int(modifier["sequence"]) <= selected_sequence:
			continue
		selected_sequence = int(modifier["sequence"])
		current_surface = modifier["name"]
		surface_grip_multiplier = float(modifier["grip"])
		surface_speed_multiplier = float(modifier["speed"])


func is_boost_active() -> bool:
	return _boosting and _throttle_input > 0.0 and boost_amount > 0.0


func get_engine_load() -> float:
	return maxf(_throttle_input, _brake_input * LEGACY_REVERSE_ENGINE_FACTOR)


func collision_snapshot() -> Dictionary:
	return {"mass": mass}



func _apply_drive_forces(_delta: float) -> void:
	if stats.physics_model_version == 1:
		var forward := Vector2.UP.rotated(rotation)
		var forward_speed := linear_velocity.dot(forward)
		var effective_max_speed := get_effective_max_speed()
		
		var engine_force := 0.0
		if _throttle_input > 0.0 and forward_speed < effective_max_speed:
			var curve_mult := VehicleDynamics.get_engine_torque_curve(absf(forward_speed), effective_max_speed, stats.launch_torque_multiplier, stats.torque_peak_ratio, stats.torque_at_max_speed, stats.torque_falloff_exponent)
			engine_force = _throttle_input * stats.engine_force * curve_mult * _external_power_multiplier * surface_speed_multiplier
		
		var rolling_force := VehicleDynamics.calculate_rolling_resistance(forward_speed, stats.rolling_resistance) * (1.0 / maxf(surface_speed_multiplier, 0.01))
		var drag_mult := 1.0 / maxf(surface_speed_multiplier * surface_speed_multiplier, 0.0001)
		var drag_force := VehicleDynamics.calculate_drag_force(forward_speed, stats.aero_drag_coefficient) * drag_mult
		
		var brake_force := 0.0
		if _brake_input > 0.0:
			if forward_speed > 12.0:
				var max_brake := stats.brake_force * surface_grip_multiplier * mass * 0.62 / maxf(stats.mass, 0.01)
				brake_force = -signf(forward_speed) * stats.brake_force * _brake_input
			elif forward_speed > -stats.reverse_speed:
				engine_force = -stats.engine_force * LEGACY_REVERSE_ENGINE_FACTOR * _brake_input * surface_speed_multiplier
		
		if _handbrake_input:
			brake_force -= signf(forward_speed) * stats.handbrake_force
		
		var boost_force := 0.0
		if is_boost_active():
			boost_force = stats.boost_power
			
		apply_central_force(forward * (engine_force - rolling_force - drag_force + brake_force + boost_force))
		return

	var forward := Vector2.UP.rotated(rotation)
	var forward_speed := linear_velocity.dot(forward)
	var effective_max_speed := get_effective_max_speed()
	var speed_ratio: float = clampf(absf(forward_speed) / maxf(effective_max_speed, 0.001), 0.0, 1.0)

	if _throttle_input > 0.0 and forward_speed < effective_max_speed:
		var power_curve: float = maxf(LEGACY_ENGINE_CURVE_MIN, 1.0 - speed_ratio)
		apply_central_force(
			forward
			* stats.engine_power
			* stats.acceleration
			* _throttle_input
			* power_curve
			* _external_power_multiplier
		)

	if _brake_input > 0.0:
		if forward_speed > LEGACY_BRAKE_TO_REVERSE_SPEED:
			apply_central_force(-forward * stats.get_legacy_brake_force() * _brake_input)
		elif forward_speed > -stats.get_legacy_reverse_speed():
			apply_central_force(-forward * stats.engine_power * LEGACY_REVERSE_ENGINE_FACTOR * _brake_input)

	if is_boost_active():
		apply_central_force(forward * stats.get_legacy_boost_power())

	if _handbrake_input and speed > LEGACY_HANDBRAKE_MIN_SPEED:
		apply_central_force(-linear_velocity.normalized() * stats.get_legacy_handbrake_force())

	apply_central_force(-linear_velocity * stats.grip * surface_grip_multiplier * mass * LEGACY_LINEAR_DAMPING_RATE)


func _apply_lateral_grip() -> void:
	if stats.physics_model_version == 1:
		var forward := Vector2.UP.rotated(rotation)
		var right := Vector2.RIGHT.rotated(rotation)
		var fwd_speed := linear_velocity.dot(forward)
		var lat_speed := linear_velocity.dot(right)
		var yaw_rate := angular_velocity
		
		var front_pos := forward * (stats.wheelbase * (1.0 - stats.front_weight_ratio))
		var rear_pos := -forward * (stats.wheelbase * stats.front_weight_ratio)
		var v_front_lat := lat_speed + yaw_rate * front_pos.length()
		var v_rear_lat := lat_speed - yaw_rate * rear_pos.length()
		
		_front_slip_angle = 0.0
		_rear_slip_angle = 0.0
		if absf(fwd_speed) > 1.0:
			var target_angle := _steer_input * deg_to_rad(stats.max_steer_angle_deg)
			var speed_ratio := clampf(absf(fwd_speed) / maxf(get_effective_max_speed(), 0.001), 0.0, 1.0)
			if speed_ratio > stats.steer_fade_start_ratio:
				var fade := (speed_ratio - stats.steer_fade_start_ratio) / (1.0 - stats.steer_fade_start_ratio)
				target_angle *= lerpf(1.0, stats.high_speed_steer_ratio, fade)
			
			_front_slip_angle = atan2(v_front_lat, absf(fwd_speed)) - target_angle * signf(fwd_speed)
			_rear_slip_angle = atan2(v_rear_lat, absf(fwd_speed))
		
		var prog_stiffness := sqrt(maxf(surface_grip_multiplier, 0.01))
		var front_peak := stats.front_grip * surface_grip_multiplier * stats.front_weight_ratio * mass * 980.0
		var rear_peak := stats.rear_grip * surface_grip_multiplier * (1.0 - stats.front_weight_ratio) * mass * 980.0
		if is_drifting:
			rear_peak *= stats.drift_rear_grip_ratio
		
		var f_front := -VehicleDynamics.calculate_tire_lateral_force(_front_slip_angle, stats.front_cornering_stiffness * prog_stiffness, front_peak / maxf(mass * 980.0, 0.01), mass * 980.0 * stats.front_weight_ratio, stats.post_peak_grip_ratio, stats.slip_falloff_rate)
		var f_rear := -VehicleDynamics.calculate_tire_lateral_force(_rear_slip_angle, stats.rear_cornering_stiffness * prog_stiffness, rear_peak / maxf(mass * 980.0, 0.01), mass * 980.0 * (1.0 - stats.front_weight_ratio), stats.post_peak_grip_ratio, stats.slip_falloff_rate)
		
		var steer_angle := _steer_input * deg_to_rad(stats.max_steer_angle_deg)
		var front_force_world := right * (f_front * cos(steer_angle)) + forward * (f_front * sin(steer_angle))
		var rear_force_world := right * f_rear
		
		apply_force(front_force_world, front_pos)
		apply_force(rear_force_world, rear_pos)
		
		if absf(fwd_speed) < 35.0:
			apply_torque(-yaw_rate * stats.yaw_stability_rate * mass * 980.0)
			
		if is_drifting:
			var assist := stats.drift_yaw_assist * mass * 980.0 * signf(_steer_input)
			if signf(_steer_input) != signf(yaw_rate) and signf(_steer_input) != 0.0:
				assist *= 0.5
			apply_torque(assist)
		return

	var right := Vector2.RIGHT.rotated(rotation)
	var lateral_speed := linear_velocity.dot(right)
	current_grip = stats.lateral_grip * surface_grip_multiplier
	if is_drifting:
		current_grip *= stats.drift_factor
	apply_central_force(-right * lateral_speed * current_grip * mass)


func _apply_steering(delta: float) -> void:
	if stats.physics_model_version == 1:
		return
		
	var forward := Vector2.UP.rotated(rotation)
	var forward_speed := linear_velocity.dot(forward)
	var direction_sign: float = -1.0 if forward_speed < LEGACY_REVERSE_STEER_THRESHOLD else 1.0
	var speed_ratio: float = clampf(speed / maxf(get_effective_max_speed(), 0.001), 0.0, 1.0)
	var rolling_factor: float = clampf(speed / LEGACY_FULL_STEER_SPEED, 0.0, 1.0)
	var high_speed_response: float = lerpf(1.0, LEGACY_HIGH_SPEED_STEER_RATIO, speed_ratio)
	var drift_rotation: float = LEGACY_DRIFT_ROTATION_MULTIPLIER if is_drifting else 1.0
	var target_angular_velocity := _steer_input * stats.steering_rate * rolling_factor * high_speed_response * drift_rotation * direction_sign
	var response := 1.0 - exp(-stats.get_legacy_steering_response() * delta)
	angular_velocity = lerpf(angular_velocity, target_angular_velocity, response)


func _update_boost(delta: float) -> void:
	if stats.physics_model_version == 1:
		if is_boost_active():
			boost_amount = maxf(0.0, boost_amount - stats.boost_drain_rate * delta)
		elif is_drifting:
			var slip_deg := rad_to_deg(absf(_rear_slip_angle))
			if absf(slip_deg - stats.drift_optimal_slip_deg) <= 12.0 and _throttle_input > 0.0 and speed >= _drift_entry_speed:
				_drift_boost_accumulated += stats.boost_recharge * delta
		return

	if is_boost_active():
		boost_amount = maxf(0.0, boost_amount - LEGACY_BOOST_DRAIN_RATE * delta)
	elif is_drifting and absf(slip_angle) > LEGACY_BOOST_SLIP_MIN_DEG and absf(slip_angle) < LEGACY_BOOST_SLIP_MAX_DEG:
		boost_amount = minf(get_boost_capacity(), boost_amount + stats.get_legacy_boost_recharge() * delta)


func _update_motion_state() -> void:
	speed = linear_velocity.length()
	if stats.physics_model_version == 1:
		if speed > LEGACY_SLIP_MEASUREMENT_MIN_SPEED:
			var forward := Vector2.UP.rotated(rotation)
			slip_angle = rad_to_deg(forward.angle_to(linear_velocity.normalized()))
		else:
			slip_angle = 0.0
			
		if not is_drifting:
			var rear_slip_growing := signf(_steer_input) == signf(_rear_slip_angle) and absf(_rear_slip_angle) > 0.01
			if _handbrake_input and absf(_steer_input) >= stats.drift_entry_steer and speed >= stats.drift_min_speed and rear_slip_growing:
				is_drifting = true
				_drift_entry_speed = speed
				_drift_boost_accumulated = 0.0
				_drift_grace_timer = 0.20
		else:
			var forward := Vector2.UP.rotated(rotation)
			var forward_speed := linear_velocity.dot(forward)
			var exit_condition := false
			if not _handbrake_input and rad_to_deg(absf(_rear_slip_angle)) < 6.0:
				_drift_grace_timer -= get_physics_process_delta_time()
				if _drift_grace_timer <= 0.0:
					exit_condition = true
			elif speed < 0.8 * _drift_entry_speed:
				exit_condition = true
			elif rad_to_deg(absf(_rear_slip_angle)) > 60.0 and forward_speed <= 0.0:
				exit_condition = true
				_drift_boost_accumulated = 0.0
				
			if exit_condition:
				is_drifting = false
				if _drift_boost_accumulated >= stats.boost_recharge * 0.35:
					add_boost(minf(_drift_boost_accumulated, stats.drift_boost_max_reward), "drift")
				_drift_boost_accumulated = 0.0
		return

	if speed > LEGACY_SLIP_MEASUREMENT_MIN_SPEED:
		var forward := Vector2.UP.rotated(rotation)
		slip_angle = rad_to_deg(forward.angle_to(linear_velocity.normalized()))
	else:
		slip_angle = 0.0
	is_drifting = (
		_handbrake_input
		and absf(_steer_input) > LEGACY_DRIFT_ENTRY_STEER
		and speed > LEGACY_DRIFT_MIN_SPEED
	)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var delta := state.step
	_contact_elapsed += delta
	var intended_forward := Vector2.UP.rotated(state.transform.get_rotation())
	var strongest_contact: Dictionary = {}
	var strongest_score := -1.0
	var strongest_static_score := -1.0
	var seen_pairs: Dictionary = {}
	has_static_contact = false
	static_contact_normal = Vector2.ZERO

	for contact_index in state.get_contact_count():
		var collider := state.get_contact_collider_object(contact_index)
		if not collider is Node or collider == self:
			continue
		var world_normal := state.get_contact_local_normal(contact_index).normalized()
		var impulse := state.get_contact_impulse(contact_index)
		if not (collider as Node).is_in_group("race_vehicle"):
			var static_score := impulse.length()
			if static_score > strongest_static_score:
				strongest_static_score = static_score
				has_static_contact = true
				static_contact_normal = world_normal
			continue
		if not collider.has_method("collision_snapshot"):
			continue
		var collider_id := collider.get_instance_id()
		seen_pairs[collider_id] = true
		var own_contact_velocity := state.get_contact_local_velocity_at_position(contact_index)
		var collider_velocity := state.get_contact_collider_velocity_at_position(contact_index)
		var relative_velocity := own_contact_velocity - collider_velocity
		var score := maxf(0.0, -relative_velocity.dot(world_normal)) + impulse.length() / maxf(mass, 0.01)
		if score <= strongest_score:
			continue
		strongest_score = score
		strongest_contact = {
			"collider_id": collider_id,
			"other_mass": float((collider.call("collision_snapshot") as Dictionary).get("mass", 1.0)),
			"normal": world_normal,
			"relative_velocity": relative_velocity,
			"impulse": impulse,
		}

	for pair_id: int in _contact_pair_last_seen.keys():
		if not seen_pairs.has(pair_id) and _contact_elapsed - float(_contact_pair_last_seen[pair_id]) > CONTACT_RELEASE_GRACE:
			_contact_pair_last_seen.erase(pair_id)

	if not strongest_contact.is_empty():
		var collider_id := int(strongest_contact["collider_id"])
		var is_new_contact := not _contact_pair_last_seen.has(collider_id)
		_contact_pair_last_seen[collider_id] = _contact_elapsed
		last_collision_response = COLLISION_RESPONSE.resolve_contact({
			"delta": delta,
			"intended_forward": intended_forward,
			"normal": strongest_contact["normal"],
			"relative_velocity": strongest_contact["relative_velocity"],
			"impulse": strongest_contact["impulse"],
			"previous_velocity": _last_output_velocity,
			"solver_velocity": state.linear_velocity,
			"solver_angular_velocity": state.angular_velocity,
			"self_mass": mass,
			"other_mass": strongest_contact["other_mass"],
			"is_new_contact": is_new_contact,
		})
		state.linear_velocity = last_collision_response["velocity"]
		state.angular_velocity = float(last_collision_response["angular_velocity"])

	_last_output_velocity = state.linear_velocity


func _limit_top_speed() -> void:
	var cap_multiplier := BOOST_SPEED_CAP_MULTIPLIER if is_boost_active() else NORMAL_SPEED_CAP_MULTIPLIER
	var speed_limit := get_effective_max_speed() * cap_multiplier
	if linear_velocity.length() > speed_limit:
		linear_velocity = linear_velocity.limit_length(speed_limit)
