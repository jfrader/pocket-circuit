class_name VehicleController
extends RigidBody2D

const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")

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


func _ready() -> void:
	apply_stats(stats)
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
	_external_power_multiplier = clampf(multiplier, 1.0, 1.08)


func configure_identity(driver_name: String, racer_vehicle_name: String, vehicle_id: String = "") -> void:
	driver_display_name = driver_name
	vehicle_display_name = racer_vehicle_name
	set_meta(&"driver_display_name", driver_name)
	set_meta(&"vehicle_display_name", racer_vehicle_name)
	configure_visual_identity(vehicle_id)


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


func configure_racer_marker(marker_color: Color) -> void:
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
	mass = stats.mass
	boost_amount = stats.boost_capacity * 0.35


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
	return stats.max_speed * surface_speed_multiplier


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


func _apply_drive_forces(_delta: float) -> void:
	var forward := Vector2.UP.rotated(rotation)
	var forward_speed := linear_velocity.dot(forward)
	var effective_max_speed := get_effective_max_speed()
	var speed_ratio: float = clampf(absf(forward_speed) / maxf(effective_max_speed, 0.001), 0.0, 1.0)

	if _throttle_input > 0.0 and forward_speed < effective_max_speed:
		var power_curve: float = maxf(0.1, 1.0 - speed_ratio)
		apply_central_force(
			forward
			* stats.engine_power
			* stats.acceleration
			* _throttle_input
			* power_curve
			* _external_power_multiplier
		)

	if _brake_input > 0.0:
		if forward_speed > 25.0:
			apply_central_force(-forward * stats.brake_force * _brake_input)
		elif forward_speed > -stats.reverse_speed:
			apply_central_force(-forward * stats.engine_power * 0.55 * _brake_input)

	if is_boost_active():
		apply_central_force(forward * stats.boost_power)

	if _handbrake_input and speed > 80.0:
		apply_central_force(-linear_velocity.normalized() * stats.handbrake_force)

	apply_central_force(-linear_velocity * stats.grip * surface_grip_multiplier * mass * 0.32)


func _apply_lateral_grip() -> void:
	var right := Vector2.RIGHT.rotated(rotation)
	var lateral_speed := linear_velocity.dot(right)
	current_grip = stats.lateral_grip * surface_grip_multiplier
	if is_drifting:
		current_grip *= stats.drift_factor
	apply_central_force(-right * lateral_speed * current_grip * mass)


func _apply_steering(delta: float) -> void:
	var forward := Vector2.UP.rotated(rotation)
	var forward_speed := linear_velocity.dot(forward)
	var direction_sign: float = -1.0 if forward_speed < -10.0 else 1.0
	var speed_ratio: float = clampf(speed / maxf(get_effective_max_speed(), 0.001), 0.0, 1.0)
	var rolling_factor: float = clampf(speed / 70.0, 0.0, 1.0)
	var high_speed_response: float = lerpf(1.0, 0.52, speed_ratio)
	var drift_rotation: float = 1.65 if is_drifting else 1.0
	var target_angular_velocity := _steer_input * stats.steering_rate * rolling_factor * high_speed_response * drift_rotation * direction_sign
	var response := 1.0 - exp(-stats.steering_response * delta)
	angular_velocity = lerpf(angular_velocity, target_angular_velocity, response)


func _update_boost(delta: float) -> void:
	if is_boost_active():
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
		_handbrake_input
		and absf(_steer_input) > 0.2
		and speed > 110.0
	)


func _limit_top_speed() -> void:
	var speed_limit := get_effective_max_speed() * (1.2 if is_boost_active() else 1.0)
	if linear_velocity.length() > speed_limit:
		linear_velocity = linear_velocity.limit_length(speed_limit)
