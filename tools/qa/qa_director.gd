extends "res://tools/promo/boss_ai.gd"
## Read-only route planner, player-input driver. Unlike the promo director this
## never installs AI assists, refills boost, teleports, or takes over the car.

const PROMO_STYLE := {"corner_pace": 1.04, "brake_timing": 1.1, "boost_eagerness": 1.18, "overtake_aggression": 1.13, "shortcut_preference": 1.16, "line_commitment": 1.06}
const FLICK_HOLD := 0.15
const FLICK_COOLDOWN := 0.8
## RaceManager progress is checkpoint units, not world pixels.
const PROGRESS_EPSILON := 0.02
var _clock := 0.0
var _flick_until := -1.0
var _flick_cooldown := -1.0
var _flick_steer := 0.0
var _braking := false
var _last_progress := 0.0
var _stalled := 0.0
var _reset_held := false
var reset_count := 0
var input_ticks := 0
var _held_keys: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100
	set_physics_process(false)


func watch(car: VehicleController, manager: RaceManager) -> void:
	release_inputs()
	vehicle = car
	race_manager = manager
	difficulty = "clockwork"
	lane_offset = 0.0
	_configure_personality("qa-player", PROMO_STYLE)
	_cache_checkpoints()
	_last_progress = manager.get_racer_progress(car)
	_stalled = 0.0
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_clock += delta
	if not is_instance_valid(vehicle) or not is_instance_valid(race_manager) or not race_manager.is_running or vehicle.controls_locked or race_manager.is_racer_finished(vehicle):
		release_inputs()
		return
	input_ticks += 1
	var expected := race_manager.get_expected_checkpoint(vehicle)
	var forward := Vector2.UP.rotated(vehicle.rotation)
	var radius := _racing_line_radius(vehicle.global_position)
	var lookahead := _lookahead_distance()
	if radius > 0.0:
		var minimum := vehicle.stats.wheelbase / maxf(tan(deg_to_rad(vehicle.stats.max_steer_angle_deg)), 0.001)
		lookahead = minf(lookahead, maxf(radius, minimum))
	var target: Vector2 = _reference_goal(forward, lookahead)["goal"]
	var traffic := _traffic_plan(delta, forward, target, radius)
	target = traffic["target_position"]
	var direction := vehicle.global_position.direction_to(target)
	var surface := _surface_anticipation(direction)
	_anticipated_grip = _planned_surface_grip(surface)
	direction = direction.lerp(surface["avoid_direction"], float(surface["weight"])).normalized()
	var obstacle := _obstacle_avoidance(forward, direction)
	if float(obstacle["weight"]) > 0.35:
		direction = direction.lerp(obstacle["avoid_direction"], float(obstacle["weight"])).normalized()
	var angle := forward.angle_to(direction)
	var max_speed := vehicle.get_effective_max_speed()
	var tuning := _difficulty_tuning()
	var requested := clampf(angle / float(tuning["steering_divisor"]), -1.0, 1.0)
	if vehicle.stats.physics_model_version != 0 and absf(angle) < TURN_AROUND_HEADING:
		var curvature := 2.0 * sin(angle) / maxf(vehicle.global_position.distance_to(target), 5.0)
		var wheel := atan(vehicle.stats.wheelbase * curvature)
		var stiffness := DYNAMICS.calculate_progressive_stiffness(vehicle.surface_grip_multiplier)
		var front := vehicle.stats.front_weight_ratio / (vehicle.stats.front_cornering_stiffness * stiffness)
		var rear := (1.0 - vehicle.stats.front_weight_ratio) / (vehicle.stats.rear_cornering_stiffness * stiffness)
		wheel += clampf(vehicle.stats.mass * vehicle.speed * vehicle.speed * curvature * (front - rear), -0.1, 0.1)
		var rack := DYNAMICS.calculate_target_steer_angle(1.0, vehicle.stats.max_steer_angle_deg, vehicle.speed, max_speed, vehicle.stats.high_speed_steer_ratio, vehicle.stats.steer_fade_start_ratio)
		requested = clampf(wheel / maxf(absf(rack), 0.001), -1.0, 1.0)
	_smoothed_steer = lerpf(_smoothed_steer, requested, 1.0 - exp(-float(tuning["steering_response"]) * delta))
	var hazard := _v1_curvature_hazard(expected)
	var target_speed := float(hazard.get("speed_limit", max_speed))
	target_speed = minf(target_speed, vehicle.stats.max_speed * float(surface["speed_scale"]))
	target_speed = minf(target_speed, minf(float(obstacle["speed_limit"]), float(traffic["speed_limit"])))
	if absf(angle) > 1.05:
		target_speed = minf(target_speed, max_speed * float(tuning["heading_cap"]))
	if absf(angle) > TURN_AROUND_HEADING:
		target_speed = minf(target_speed, max_speed * 0.12)
	var braking := vehicle.speed > target_speed + 3.0
	var brake := clampf((vehicle.speed - target_speed) / float(tuning["brake_response"]), 0.0, 1.0) if braking else 0.0
	var throttle := 0.0 if braking else 1.0
	var boost := absf(_smoothed_steer) < 0.15 and not vehicle.is_drifting and not braking and float(surface["risk"]) < 0.12
	if brake > 0.2 and not _braking and vehicle.speed / maxf(max_speed, 0.001) > 0.5 and absf(_smoothed_steer) > 0.2 and _clock > _flick_cooldown:
		_flick_until = _clock + FLICK_HOLD
		_flick_cooldown = _clock + FLICK_COOLDOWN
		_flick_steer = signf(_smoothed_steer)
	_braking = brake > 0.2
	var flick := _clock < _flick_until
	if flick:
		throttle = 1.0
		brake = 0.0
		boost = false
	if absf(vehicle.slip_angle) > SPIN_LIFT_SLIP_DEG and vehicle.speed > SPIN_MIN_SPEED and not flick:
		throttle = 0.0
		boost = false
	_axis(JOY_AXIS_LEFT_X, _flick_steer if flick else _smoothed_steer, true)
	_axis(JOY_AXIS_TRIGGER_RIGHT, throttle)
	_axis(JOY_AXIS_TRIGGER_LEFT, brake)
	_key(KEY_SPACE, flick)
	_key(KEY_SHIFT, boost)
	# The same R recovery available to a player, not AI's private recovery path.
	var progress := race_manager.get_racer_progress(vehicle)
	if _reset_held:
		_last_progress = progress
		_stalled = 0.0
	_stalled = _stalled + delta if progress < _last_progress + PROGRESS_EPSILON else 0.0
	if progress >= _last_progress + PROGRESS_EPSILON:
		_last_progress = progress
	var reset := _stalled > 6.0 and not _reset_held
	_key(KEY_R, reset)
	if reset:
		reset_count += 1
		_stalled = 0.0
		_last_progress = progress
	_reset_held = reset


func release_inputs() -> void:
	_axis(JOY_AXIS_LEFT_X, 0.0, true)
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	for key in [KEY_SPACE, KEY_SHIFT, KEY_R]:
		_key(key, false)


func _axis(axis: JoyAxis, value: float, signed_axis := false) -> void:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	var action: StringName = &"steer_left" if signed_axis and value < 0.0 else &"steer_right" if signed_axis else &"accelerate" if axis == JOY_AXIS_TRIGGER_RIGHT else &"brake"
	var deadzone := InputMap.action_get_deadzone(action)
	var strength := deadzone + (1.0 - deadzone) * absf(value)
	event.axis_value = signf(value) * strength if absf(value) > 0.001 else 0.0
	Input.parse_input_event(event)


func _key(code: Key, pressed: bool) -> void:
	if bool(_held_keys.get(code, false)) == pressed:
		return
	_held_keys[code] = pressed
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
