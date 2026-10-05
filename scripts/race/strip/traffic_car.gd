class_name TrafficCar
extends RigidBody2D

const VISUALS := preload("res://scripts/race/strip/traffic_visuals.gd")
const ROAD := preload("res://scripts/race/strip/strip_road_rules.gd")
const SCENERY_MASK := 2 | 4 | 16
const ACCELERATION := 180.0
const BRAKING := 480.0
const VELOCITY_RESPONSE := 3.5
const LATERAL_ACCELERATION := 300.0
const LOOKAHEAD_TIME := 0.55
const MIN_LOOKAHEAD := 130.0
const LANE_RATE := 0.28
const FOLLOW_GAP := 42.0
const HEADWAY := 0.65
const MERGE_CLEARANCE := 155.0
const CUT_DISTANCE := 650.0
const SWERVE_DISTANCE := 1800.0
const END_CLEARANCE := 100.0
const RECOVERY_LOOKAHEAD := 15.0
const RECOVERY_SPEED := 85.0
const PROBE_SKIN := 2.0

var _sampler: RefCounted
var _half_width := ROAD.HALF_WIDTH
var _arc := 0.0
var _spawn_arc := 0.0
var _base_lane := 0.0
var _lane := 0.0
var _speed := 220.0
var _behavior: StringName = &"cruiser"
var _active := false
var _is_truck := false
var _cut_requested := false
var _body_length := 52.0
var _body_width := 32.0
var _steer := 0.0
var _avoid_until_arc := 0.0
var _avoid_lane := 0.0
var _visual: Node2D
var _probe: CapsuleShape2D
var neighbors: Array = []
var travel_direction := 1


func configure(arc: float, lane: float, speed: float, behavior: StringName, vehicle_id: String, sampler: RefCounted, half_width: float) -> void:
	_sampler = sampler
	_half_width = half_width
	_arc = arc
	_spawn_arc = arc
	travel_direction = ROAD.direction(lane)
	set_meta("strip_direction", travel_direction)
	_base_lane = ROAD.fraction(lane)
	_lane = _base_lane
	_avoid_until_arc = arc
	_avoid_lane = _base_lane
	_behavior = behavior
	_cut_requested = false
	_is_truck = behavior == &"truck"
	_speed = speed * (0.78 if _is_truck else 1.0)
	var sample: Dictionary = _sampler.sample(_arc)
	position = sample["pos"] + sample["perp"] * (_lane * _half_width)
	rotation = ((sample["dir"] as Vector2) * travel_direction).angle() + PI * 0.5
	collision_layer = 1
	collision_mask = 1 | SCENERY_MASK
	gravity_scale = 0.0
	can_sleep = false
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	mass = 1.6 if _is_truck else 1.0
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.15
	physics_material_override.bounce = 0.0
	_visual = VISUALS.new()
	_visual.configure(vehicle_id, int(arc), _is_truck, travel_direction < 0)
	add_child(_visual)
	var size: Vector2 = _visual.body_size
	_body_width = size.x
	_body_length = size.y
	_probe = CapsuleShape2D.new()
	_probe.radius = _body_width * 0.5
	_probe.height = _body_length
	var collision := CollisionShape2D.new()
	collision.name = "BodyCollision"
	collision.shape = _probe
	add_child(collision)
	# Keep a contact skin inside the authoritative body. cast_motion ignores
	# initially overlapping shapes; a nose resting on a prop must still see it.
	_probe = _probe.duplicate() as CapsuleShape2D
	_probe.radius -= PROBE_SKIN
	_probe.height -= PROBE_SKIN * 2.0
	stop()


func start() -> void:
	_active = true
	freeze = false


func stop() -> void:
	_active = false
	freeze = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0


func _physics_process(delta: float) -> void:
	if _visual != null:
		_visual.animate(linear_velocity.length(), _steer, delta)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not _active or _sampler == null:
		return
	var point := state.transform.origin
	_arc = float(_sampler.project(point, _arc)["arc"])
	if (travel_direction > 0 and _arc >= _sampler.length() - END_CLEARANCE) or (travel_direction < 0 and _arc <= END_CLEARANCE):
		_active = false
		queue_free()
		return
	var sample: Dictionary = _sampler.sample(_arc)
	var tangent: Vector2 = sample["dir"] * travel_direction
	var normal: Vector2 = sample["perp"]
	var lateral := (point - (sample["pos"] as Vector2)).dot(normal)
	var speed := maxf(0.0, state.linear_velocity.dot(tangent))
	var requested_lane := _behavior_lane()
	if (_avoid_until_arc - _arc) * travel_direction > 0.0:
		requested_lane = _avoid_lane
	if _merge_clear(requested_lane, lateral):
		_lane = move_toward(_lane, requested_lane, LANE_RATE * state.step)
	var lookahead := MIN_LOOKAHEAD + speed * LOOKAHEAD_TIME
	var future: Dictionary = _sampler.sample(_arc + lookahead * travel_direction)
	var goal: Vector2 = future["pos"] + future["perp"] * (_lane * _half_width)
	var target_speed := _following_speed(lateral, speed)
	# Capsule casts include the full vehicle, not just its centre ray. Try a
	# clear passing line around household props; otherwise brake, never phase.
	var clear := _clear_fraction(state, point, goal)
	if clear < 1.0:
		for passing_lane in ROAD.lane_fractions(travel_direction):
			if not _merge_clear(passing_lane, lateral):
				continue
			var passing_goal: Vector2 = future["pos"] + future["perp"] * (passing_lane * _half_width)
			var passing_clear := _clear_fraction(state, point, passing_goal)
			if passing_clear > clear:
				clear = passing_clear
				goal = passing_goal
				_avoid_lane = passing_lane
				_avoid_until_arc = _arc + (lookahead + _body_length) * travel_direction
		# A bump can leave the nose against a prop, where every forward chord
		# intersects it. Steer out locally before resuming the forward line.
		if clear < 1.0:
			var recovery: Dictionary = _sampler.sample(_arc + RECOVERY_LOOKAHEAD * travel_direction)
			for passing_lane in ROAD.lane_fractions(travel_direction):
				if absf(passing_lane * _half_width - lateral) < _body_width or not _merge_clear(passing_lane, lateral):
					continue
				var recovery_goal: Vector2 = recovery["pos"] + recovery["perp"] * (passing_lane * _half_width)
				if _clear_fraction(state, point, recovery_goal) >= 1.0:
					goal = recovery_goal
					clear = 1.0
					target_speed = minf(target_speed, RECOVERY_SPEED)
					_avoid_lane = passing_lane
					_avoid_until_arc = _arc + (lookahead + _body_length) * travel_direction
					break
		if clear < 1.0:
			target_speed = minf(target_speed, sqrt(2.0 * BRAKING * maxf(0.0, point.distance_to(goal) * clear - FOLLOW_GAP)))
	var direction := (goal - point).normalized()
	# Acceleration-limited integration leaves collision impulses intact. No
	# transform snapping, time-driven target, or frame-by-frame velocity reset.
	var desired := direction * target_speed
	var error := (desired - state.linear_velocity) * VELOCITY_RESPONSE
	var longitudinal := clampf(error.dot(tangent), -BRAKING, ACCELERATION)
	var sideways := clampf(error.dot(normal), -LATERAL_ACCELERATION, LATERAL_ACCELERATION)
	state.linear_velocity += (tangent * longitudinal + normal * sideways) * state.step
	var heading_error := wrapf(direction.angle() + PI * 0.5 - state.transform.get_rotation(), -PI, PI)
	_steer = clampf(heading_error * 2.0, -1.0, 1.0)
	state.angular_velocity = move_toward(state.angular_velocity, clampf(heading_error * 5.0, -2.5, 2.5), 8.0 * state.step)


func _behavior_lane() -> float:
	var travel := maxf(0.0, (_arc - _spawn_arc) * travel_direction)
	var alternate := travel_direction * (1.0 - absf(_base_lane))
	if _behavior == &"cutter":
		_cut_requested = _cut_requested or travel >= CUT_DISTANCE
		return alternate if _cut_requested else _base_lane
	if _behavior == &"swerve" or _behavior == &"line":
		return lerpf(_base_lane, alternate, (1.0 - cos(TAU * travel / SWERVE_DISTANCE)) * 0.5)
	return _base_lane


func _merge_clear(lane: float, lateral: float) -> bool:
	var destination := lane * _half_width
	for candidate in neighbors:
		if not is_instance_valid(candidate):
			continue
		var other := candidate as TrafficCar
		if not is_instance_valid(other) or other == self or not other._active:
			continue
		var sample: Dictionary = _sampler.sample(other._arc)
		var gap := (other._arc - _arc) * travel_direction
		var tangent: Vector2 = sample["dir"] * travel_direction
		var closing := maxf(0.0, (linear_velocity - other.linear_velocity).dot(tangent) * signf(gap))
		var required_gap := (_body_length + other._body_length) * 0.5 + FOLLOW_GAP * 0.5 + closing * HEADWAY
		if absf(gap) > required_gap:
			continue
		var other_lateral := (other.global_position - (sample["pos"] as Vector2)).dot(sample["perp"])
		var margin := (_body_width + other._body_width) * 0.5 + 12.0
		if other_lateral > minf(lateral, destination) - margin and other_lateral < maxf(lateral, destination) + margin:
			return false
	return true


func _following_speed(lateral: float, speed: float) -> float:
	var result := _speed
	for candidate in neighbors:
		if not is_instance_valid(candidate):
			continue
		var other := candidate as TrafficCar
		if not is_instance_valid(other) or other == self or not other._active:
			continue
		if other.travel_direction != travel_direction:
			continue
		var gap := (other._arc - _arc) * travel_direction
		if gap <= 0.0 or gap > MERGE_CLEARANCE + speed * 2.0:
			continue
		var sample: Dictionary = _sampler.sample(other._arc)
		var other_lateral := (other.global_position - (sample["pos"] as Vector2)).dot(sample["perp"])
		if absf(other_lateral - lateral) > (_body_width + other._body_width) * 0.5 + 14.0:
			continue
		var free_gap := gap - (_body_length + other._body_length) * 0.5 - FOLLOW_GAP
		var leader_speed := maxf(0.0, other.linear_velocity.dot((sample["dir"] as Vector2) * travel_direction))
		result = minf(result, maxf(0.0, leader_speed + (free_gap - speed * HEADWAY) * 1.5))
	return result


func _clear_fraction(state: PhysicsDirectBodyState2D, from: Vector2, to: Vector2) -> float:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _probe
	query.transform = Transform2D(state.transform.get_rotation(), from)
	query.motion = to - from
	query.collision_mask = collision_mask
	var excluded: Array[RID] = [get_rid()]
	# Platoon headway handles civilians. Cast against racers as well as scenery
	# so a stopped player is not treated as something to continuously push.
	for other in neighbors:
		if is_instance_valid(other) and other != self and other.travel_direction == travel_direction:
			excluded.append(other.get_rid())
	query.exclude = excluded
	var fractions := state.get_space_state().cast_motion(query)
	return fractions[0] if not fractions.is_empty() else 0.0
