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

## Drift state machine states.
enum DriftState { NONE, ACTIVE, EXITING }

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

# ── v1 state ──
var _rack_angle := 0.0  # persistent steering rack angle (radians)
var _drift_state: DriftState = DriftState.NONE
var _drift_qualified_time := 0.0  # seconds at optimal slip
var _drift_boost_awarded := false  # once-only flag
var _drift_collision_cancel := false  # collision invalidation
var _drift_requires_release := false  # canceled drifts cannot immediately re-enter
var _drift_yaw_assist_scale := 1.0
var _rear_grip_recovery := 1.0  # 0..1 interpolation factor during recovery
var _front_lateral_force := 0.0  # cached for friction circle
var _rear_lateral_force := 0.0  # cached for friction circle


func _ready() -> void:
	apply_stats(stats)
	gravity_scale = 0.0
	linear_damp = 0.0
	angular_damp = 0.0 if stats.physics_model_version == 1 else LEGACY_ANGULAR_DAMP
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
	if stats.physics_model_version == 1:
		_update_motion_state()
		_v1_physics_step(delta)
	else:
		_v0_update_motion_state()
		_v0_physics_step(delta)


# ═══════════════════════════════════════════════════════════════════════
# Input reading (shared)
# ═══════════════════════════════════════════════════════════════════════

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


# ═══════════════════════════════════════════════════════════════════════
# Public API (preserved)
# ═══════════════════════════════════════════════════════════════════════

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


func is_boost_active() -> bool:
	return _boosting and _throttle_input > 0.0 and boost_amount > 0.0


func get_engine_load() -> float:
	return maxf(_throttle_input, _brake_input * LEGACY_REVERSE_ENGINE_FACTOR)


func get_effective_max_speed() -> float:
	if stats.physics_model_version == 1:
		return VehicleDynamics.get_effective_max_speed(stats, surface_speed_multiplier)
	return stats.get_legacy_max_speed() * surface_speed_multiplier


func get_boost_capacity() -> float:
	if stats.physics_model_version == 1:
		return stats.boost_capacity
	return stats.get_legacy_boost_capacity()


func get_effective_grip() -> float:
	if stats.physics_model_version == 1:
		return VehicleDynamics.get_effective_grip(stats, surface_grip_multiplier)
	return stats.grip * surface_grip_multiplier


func get_safe_corner_speed(radius: float, surface_grip: float = -1.0) -> float:
	## AI/public query: safe cornering speed for given radius and grip.
	var grip := surface_grip if surface_grip >= 0.0 else surface_grip_multiplier
	var lat_accel := VehicleDynamics.get_effective_lat_accel(stats, grip)
	return VehicleDynamics.get_safe_corner_speed(radius, lat_accel)


func get_braking_distance(v_now: float, v_target: float, surface_grip: float = -1.0) -> float:
	## AI/public query: braking distance from v_now to v_target.
	var grip := surface_grip if surface_grip >= 0.0 else surface_grip_multiplier
	if stats.physics_model_version == 1:
		return VehicleDynamics.predict_braking_distance(
			v_now, v_target, stats, grip, surface_speed_multiplier,
		)
	var brake_accel := stats.get_legacy_brake_force() / maxf(stats.get_legacy_mass(), 0.001)
	return VehicleDynamics.get_braking_distance(v_now, v_target, brake_accel)


func add_boost(amount: float, source: String = "general") -> void:
	## Unified boost entry point. Sources: "drift", "clean-line", "drafting", etc.
	if stats.physics_model_version == 1 and is_boost_active() and source != "drift":
		# No recharge while boosting (spec: "No recharge while boosting")
		return
	boost_amount = clampf(boost_amount + amount, 0.0, get_boost_capacity())


func reset_dynamics_state() -> void:
	## Called on recovery/reset to clear all v1 transient state.
	is_drifting = false
	_drift_state = DriftState.NONE
	_drift_boost_accumulated = 0.0
	_drift_qualified_time = 0.0
	_drift_boost_awarded = false
	_drift_collision_cancel = false
	_drift_requires_release = false
	_drift_yaw_assist_scale = 1.0
	_drift_grace_timer = 0.0
	_drift_entry_speed = 0.0
	_rack_angle = 0.0
	_rear_grip_recovery = 1.0
	_front_slip_angle = 0.0
	_rear_slip_angle = 0.0
	_front_lateral_force = 0.0
	_rear_lateral_force = 0.0


func collision_snapshot() -> Dictionary:
	return {"mass": mass}


# ═══════════════════════════════════════════════════════════════════════
# Identity & presentation (unchanged)
# ═══════════════════════════════════════════════════════════════════════

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
	if stats.physics_model_version == 1:
		mass = stats.mass
		angular_damp = 0.0
		boost_amount = stats.boost_capacity * 0.35
	else:
		mass = stats.get_legacy_mass()
		angular_damp = LEGACY_ANGULAR_DAMP
		boost_amount = stats.get_legacy_boost_capacity() * 0.35


# ═══════════════════════════════════════════════════════════════════════
# Surface management (shared)
# ═══════════════════════════════════════════════════════════════════════

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


# ═══════════════════════════════════════════════════════════════════════
# Motion state update (shared measurement)
# ═══════════════════════════════════════════════════════════════════════

func _update_motion_state() -> void:
	speed = linear_velocity.length()
	if speed > LEGACY_SLIP_MEASUREMENT_MIN_SPEED:
		var forward := Vector2.UP.rotated(rotation)
		slip_angle = rad_to_deg(forward.angle_to(linear_velocity.normalized()))
	else:
		slip_angle = 0.0


# ═══════════════════════════════════════════════════════════════════════
# V1 — Bicycle/tire model (behind physics_model_version == 1)
# ═══════════════════════════════════════════════════════════════════════

func _v1_physics_step(delta: float) -> void:
	var forward := Vector2.UP.rotated(rotation)
	var right := Vector2.RIGHT.rotated(rotation)
	var fwd_speed := linear_velocity.dot(forward)
	var lat_speed := linear_velocity.dot(right)
	var yaw_rate := angular_velocity
	var eff_max := get_effective_max_speed()

	# ── Steering rack (persistent angle with response rate) ──
	var target_steer := VehicleDynamics.calculate_target_steer_angle(
		_steer_input, stats.max_steer_angle_deg, fwd_speed, eff_max,
		stats.high_speed_steer_ratio, stats.steer_fade_start_ratio,
	)
	_rack_angle = VehicleDynamics.update_rack_angle(
		_rack_angle, target_steer, stats.steering_response, delta,
	)

	# ── Slip angles ──
	var slips := VehicleDynamics.calculate_slip_angles(
		fwd_speed, lat_speed, yaw_rate,
		stats.wheelbase, stats.front_weight_ratio, _rack_angle,
	)
	_front_slip_angle = float(slips["front"])
	_rear_slip_angle = float(slips["rear"])

	# ── Normal loads (load split) ──
	var front_normal := VehicleDynamics.calculate_axle_normal_load(
		stats.mass, stats.front_weight_ratio, true,
	)
	var rear_normal := VehicleDynamics.calculate_axle_normal_load(
		stats.mass, stats.front_weight_ratio, false,
	)

	# ── Progressive stiffness scaling ──
	var prog := VehicleDynamics.calculate_progressive_stiffness(surface_grip_multiplier)

	# ── Peak grip computation ──
	var front_peak_grip := stats.front_grip * surface_grip_multiplier
	var rear_peak_grip := stats.rear_grip * surface_grip_multiplier
	current_grip = get_effective_grip()

	# ── Drift grip reduction + recovery interpolation ──
	var effective_rear_grip := rear_peak_grip
	if _drift_state == DriftState.ACTIVE or _handbrake_input:
		effective_rear_grip *= stats.drift_rear_grip_ratio
	elif _rear_grip_recovery < 1.0:
		# Exponential recovery after drift exit
		_rear_grip_recovery = minf(1.0, _rear_grip_recovery + (1.0 - _rear_grip_recovery) * (1.0 - exp(-stats.drift_grip_recovery_rate * delta)))
		effective_rear_grip *= lerpf(stats.drift_rear_grip_ratio, 1.0, _rear_grip_recovery)

	# ── Tire lateral forces ──
	_front_lateral_force = VehicleDynamics.calculate_tire_lateral_force(
		_front_slip_angle,
		stats.front_cornering_stiffness * prog,
		front_peak_grip,
		front_normal,
		stats.post_peak_grip_ratio,
		stats.slip_falloff_rate,
	)
	_rear_lateral_force = VehicleDynamics.calculate_tire_lateral_force(
		_rear_slip_angle,
		stats.rear_cornering_stiffness * prog,
		effective_rear_grip,
		rear_normal,
		stats.post_peak_grip_ratio,
		stats.slip_falloff_rate,
	)

	# ── Front force along steered axis at front axle ──
	var front_arm := stats.wheelbase * (1.0 - stats.front_weight_ratio)
	var rear_arm := stats.wheelbase * stats.front_weight_ratio
	var front_pos := forward * front_arm
	var rear_pos := -forward * rear_arm

	# Lateral force follows the steered wheel's right axis.
	var front_right := right.rotated(_rack_angle)
	var front_force_world := front_right * _front_lateral_force
	# Rear force along body lateral
	var rear_force_world := right * _rear_lateral_force

	apply_force(front_force_world, front_pos)
	apply_force(rear_force_world, rear_pos)

	# ── Low-speed kinematic blend / bounded yaw stability ──
	var target_yaw_rate := 0.0
	if absf(fwd_speed) > 1.0:
		target_yaw_rate = fwd_speed * tan(_rack_angle) / maxf(stats.wheelbase, 0.001)
	var estimated_inertia := stats.mass * (stats.wheelbase * stats.wheelbase + 18.0 * 18.0) / 12.0
	var below_peak := (
		absf(_front_lateral_force) < front_peak_grip * front_normal * 0.98
		and absf(_rear_lateral_force) < effective_rear_grip * rear_normal * 0.98
	)
	if below_peak:
		var stability_torque := (
			(target_yaw_rate - yaw_rate)
			* estimated_inertia
			* stats.yaw_stability_rate
		)
		var stability_limit := (front_peak_grip * front_normal + effective_rear_grip * rear_normal) * stats.wheelbase * 0.30
		apply_torque(clampf(stability_torque, -stability_limit, stability_limit))
	if absf(fwd_speed) < VehicleDynamics.KINEMATIC_BLEND_SPEED:
		var blend := 1.0 - clampf(absf(fwd_speed) / VehicleDynamics.KINEMATIC_BLEND_SPEED, 0.0, 1.0)
		angular_velocity = lerpf(angular_velocity, target_yaw_rate, blend * (1.0 - exp(-stats.steering_response * delta)))

	# ── Drift yaw assist ──
	if _drift_state == DriftState.ACTIVE:
		var counter_steering := (
			absf(yaw_rate) > 0.05
			and signf(_steer_input) != 0.0
			and signf(_steer_input) != signf(yaw_rate)
		)
		if counter_steering:
			_drift_yaw_assist_scale *= exp(-8.0 * delta)
		else:
			_drift_yaw_assist_scale = lerpf(
				_drift_yaw_assist_scale, 1.0,
				1.0 - exp(-stats.drift_grip_recovery_rate * delta),
			)
		var assist := stats.drift_yaw_assist * estimated_inertia * signf(_steer_input) * _drift_yaw_assist_scale
		apply_torque(assist)
		if counter_steering:
			var counter_torque := (target_yaw_rate - yaw_rate) * estimated_inertia * stats.yaw_stability_rate
			var counter_limit := (front_peak_grip * front_normal + effective_rear_grip * rear_normal) * stats.wheelbase * 0.45
			apply_torque(clampf(counter_torque, -counter_limit, counter_limit))

	# ── Engine / Drag / Rolling ──
	_v1_apply_longitudinal(delta, forward, fwd_speed, eff_max)

	# ── Braking with friction circle ──
	_v1_apply_braking(forward, fwd_speed, front_pos, rear_pos)

	# ── Handbrake (rear-only) ──
	if _handbrake_input:
		var hb := VehicleDynamics.calculate_handbrake_force(true, fwd_speed, stats)
		apply_force(-forward * hb, rear_pos)
		# Rear lateral grip reduction during handbrake (already handled by drift grip ratio)

	# ── Boost ──
	_v1_apply_boost(delta, forward, fwd_speed)

	# ── Drift state machine ──
	_v1_update_drift(delta, fwd_speed)

	# ── Speed caps (soft + hard) ──
	_v1_apply_speed_caps(forward, fwd_speed, eff_max)


func _v1_apply_longitudinal(delta: float, forward: Vector2, fwd_speed: float, eff_max: float) -> void:
	# Engine
	if _throttle_input > 0.0 and fwd_speed < eff_max:
		var engine := VehicleDynamics.calculate_engine_force(
			_throttle_input, fwd_speed, stats,
			surface_speed_multiplier, _external_power_multiplier,
		)
		apply_central_force(forward * engine)
	elif _brake_input > 0.0 and fwd_speed <= VehicleDynamics.HOLD_SPEED_THRESHOLD and fwd_speed > -stats.reverse_speed:
		# Reverse after hold
		var rev_force := -stats.engine_force * LEGACY_REVERSE_ENGINE_FACTOR * _brake_input * surface_speed_multiplier
		apply_central_force(forward * rev_force)

	# Rolling resistance (scaled by 1/surface_speed_mult)
	var rolling := VehicleDynamics.calculate_rolling_resistance(fwd_speed, stats.rolling_resistance)
	rolling *= 1.0 / maxf(surface_speed_multiplier, 0.01)
	apply_central_force(-forward * rolling)

	# Drag (scaled by 1/surface_speed_mult^2, opposes travel direction)
	var drag := VehicleDynamics.calculate_drag_force(speed, stats.aero_drag_coefficient)
	drag *= 1.0 / maxf(surface_speed_multiplier * surface_speed_multiplier, 0.0001)
	if speed > 0.001:
		apply_central_force(-linear_velocity.normalized() * drag)

	# Soft overspeed cap
	var soft := VehicleDynamics.calculate_soft_cap_force(fwd_speed, eff_max, stats.mass)
	if absf(soft) > 0.0:
		apply_central_force(-forward * soft)


func _v1_apply_braking(forward: Vector2, fwd_speed: float, front_pos: Vector2, rear_pos: Vector2) -> void:
	if _brake_input <= 0.0 or fwd_speed <= VehicleDynamics.HOLD_SPEED_THRESHOLD:
		# Hold / reverse handled in longitudinal
		if _brake_input > 0.0 and absf(fwd_speed) <= VehicleDynamics.HOLD_SPEED_THRESHOLD:
			# Hold in place
			linear_velocity *= 0.9
		return

	var brakes := VehicleDynamics.calculate_brake_forces(
		_brake_input, fwd_speed, stats, surface_grip_multiplier,
		_front_lateral_force, _rear_lateral_force,
	)
	var front_forward := forward.rotated(_rack_angle)
	apply_force(-front_forward * float(brakes["front_brake"]), front_pos)
	apply_force(-forward * float(brakes["rear_brake"]), rear_pos)


func _v1_apply_boost(delta: float, forward: Vector2, _fwd_speed: float) -> void:
	if is_boost_active():
		apply_central_force(forward * stats.boost_power)
		boost_amount = maxf(0.0, boost_amount - stats.boost_drain_rate * delta)


func _v1_update_drift(delta: float, fwd_speed: float) -> void:
	var rear_slip_deg := rad_to_deg(absf(_rear_slip_angle))

	match _drift_state:
		DriftState.NONE:
			_v1_drift_try_entry(fwd_speed, rear_slip_deg)

		DriftState.ACTIVE:
			_v1_drift_during(delta, fwd_speed, rear_slip_deg)

		DriftState.EXITING:
			# Recovery interpolation handled by _rear_grip_recovery above
			_drift_state = DriftState.NONE

	is_drifting = _drift_state == DriftState.ACTIVE


func _v1_drift_try_entry(fwd_speed: float, _rear_slip_deg: float) -> void:
	## Entry: handbrake held AND |steer|>=drift_entry_steer AND speed>=drift_min_speed
	## AND rear slip growing in steering direction.
	if _drift_requires_release:
		if _handbrake_input:
			return
		_drift_requires_release = false
	if not _handbrake_input:
		return
	if absf(_steer_input) < stats.drift_entry_steer:
		return
	if speed < stats.drift_min_speed:
		return
	# With the body-right slip convention, rear slip during turn-in has the
	# opposite sign to steering input while yaw grows into the corner.
	var rear_slip_growing := signf(_steer_input) == -signf(_rear_slip_angle) and absf(_rear_slip_angle) > 0.01
	if not rear_slip_growing:
		return

	_drift_state = DriftState.ACTIVE
	_drift_entry_speed = speed
	_drift_boost_accumulated = 0.0
	_drift_qualified_time = 0.0
	_drift_boost_awarded = false
	_drift_collision_cancel = false
	_drift_yaw_assist_scale = 1.0
	_drift_grace_timer = VehicleDynamics.DRIFT_GRACE_DURATION
	_rear_grip_recovery = 0.0


func _v1_drift_during(delta: float, fwd_speed: float, rear_slip_deg: float) -> void:
	# ── Boost accumulation: qualified time at optimal slip ──
	if absf(rear_slip_deg - stats.drift_optimal_slip_deg) <= 12.0 and _throttle_input > 0.0 and speed >= _drift_entry_speed:
		_drift_qualified_time += delta
		_drift_boost_accumulated = minf(
			stats.drift_boost_max_reward,
			_drift_qualified_time * stats.boost_recharge,
		)

	# ── Exit checks ──
	var controlled_exit := false
	var cancel_exit := false

	# Controlled exit: handbrake released + slip < 6deg for 0.20s
	if not _handbrake_input and rear_slip_deg < VehicleDynamics.DRIFT_EXIT_SLIP_DEG:
		_drift_grace_timer -= delta
		if _drift_grace_timer <= 0.0:
			controlled_exit = true
	else:
		# Reset grace timer when conditions not met
		_drift_grace_timer = VehicleDynamics.DRIFT_GRACE_DURATION

	# Speed loss exit: speed < 80% entry speed
	if speed < 0.8 * _drift_entry_speed:
		cancel_exit = true

	# Spin exit: slip > 60deg & forward v not positive
	if rear_slip_deg > VehicleDynamics.DRIFT_SPIN_SLIP_DEG and fwd_speed <= 0.0:
		cancel_exit = true
		_drift_collision_cancel = true  # spin = no boost

	# Collision invalidation
	if _drift_collision_cancel:
		cancel_exit = true

	if cancel_exit:
		# No boost on cancel (spin/collision/speed loss)
		_drift_state = DriftState.EXITING
		_rear_grip_recovery = 0.0
		_drift_requires_release = _handbrake_input
		_drift_boost_accumulated = 0.0

	elif controlled_exit:
		# Award boost ONCE on controlled exit
		if not _drift_boost_awarded and _drift_qualified_time >= VehicleDynamics.DRIFT_MIN_QUALIFIED_TIME:
			var reward := minf(_drift_qualified_time * stats.boost_recharge, stats.drift_boost_max_reward)
			add_boost(reward, "drift")
			_drift_boost_awarded = true
		_drift_state = DriftState.EXITING
		_rear_grip_recovery = 0.0  # start recovery interpolation


func _v1_apply_speed_caps(forward: Vector2, fwd_speed: float, eff_max: float) -> void:
	# HARD legal caps: 1.0x eff_max normal, 1.2x boosted
	var cap_mult := BOOST_SPEED_CAP_MULTIPLIER if is_boost_active() else NORMAL_SPEED_CAP_MULTIPLIER
	var hard_limit := eff_max * cap_mult
	if linear_velocity.length() > hard_limit:
		linear_velocity = linear_velocity.limit_length(hard_limit)


# ═══════════════════════════════════════════════════════════════════════
# V0 — Legacy model (default/release behavior, unchanged)
# ═══════════════════════════════════════════════════════════════════════

func _v0_physics_step(delta: float) -> void:
	_v0_apply_drive_forces(delta)
	_v0_apply_lateral_grip()
	_v0_apply_steering(delta)
	_v0_update_boost(delta)
	_v0_limit_top_speed()


func _v0_apply_drive_forces(_delta: float) -> void:
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


func _v0_apply_lateral_grip() -> void:
	var right := Vector2.RIGHT.rotated(rotation)
	var lateral_speed := linear_velocity.dot(right)
	current_grip = stats.lateral_grip * surface_grip_multiplier
	if is_drifting:
		current_grip *= stats.drift_factor
	apply_central_force(-right * lateral_speed * current_grip * mass)


func _v0_apply_steering(delta: float) -> void:
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


func _v0_update_boost(delta: float) -> void:
	if is_boost_active():
		boost_amount = maxf(0.0, boost_amount - LEGACY_BOOST_DRAIN_RATE * delta)
	elif is_drifting and absf(slip_angle) > LEGACY_BOOST_SLIP_MIN_DEG and absf(slip_angle) < LEGACY_BOOST_SLIP_MAX_DEG:
		boost_amount = minf(get_boost_capacity(), boost_amount + stats.get_legacy_boost_recharge() * delta)


func _v0_update_motion_state() -> void:
	speed = linear_velocity.length()
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


func _v0_limit_top_speed() -> void:
	var cap_multiplier := BOOST_SPEED_CAP_MULTIPLIER if is_boost_active() else NORMAL_SPEED_CAP_MULTIPLIER
	var speed_limit := get_effective_max_speed() * cap_multiplier
	if linear_velocity.length() > speed_limit:
		linear_velocity = linear_velocity.limit_length(speed_limit)


# ═══════════════════════════════════════════════════════════════════════
# Collision handling (shared, unchanged)
# ═══════════════════════════════════════════════════════════════════════

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
				if stats.physics_model_version == 1 and _drift_state == DriftState.ACTIVE:
					_drift_collision_cancel = true
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

		# Collision invalidates active drift boost (v1)
		if stats.physics_model_version == 1 and _drift_state == DriftState.ACTIVE:
			_drift_collision_cancel = true

	_last_output_velocity = state.linear_velocity
