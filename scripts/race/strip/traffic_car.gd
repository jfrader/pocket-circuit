class_name TrafficCar
extends RigidBody2D

const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")

var _sampler: RefCounted
var _half_width := 80.0
var _arc := 0.0
var _base_lane := 0.0
var _lane := 0.0
var _speed := 100.0
var _behavior: StringName = &"cruiser"
var _vehicle_id := "rustbug"
var _active := false
var _cut_done := false
var _cut_arc := 0.0
var _osc_t := 0.0

func configure(arc: float, lane: float, speed: float, behavior: StringName, vehicle_id: String, sampler: RefCounted, half_width: float) -> void:
	_sampler = sampler
	_half_width = half_width
	_arc = arc
	_base_lane = lane
	_lane = lane
	_behavior = behavior
	_vehicle_id = vehicle_id if vehicle_id else "rustbug"
	# small deterministic speed variation from own arc only
	var var_seed := int(arc * 17.0) % 5 - 2
	_speed = speed * (1.0 + float(var_seed) * 0.015)
	_cut_done = false
	_osc_t = 0.0
	if _behavior == &"cutter":
		_cut_arc = _arc + maxf((_sampler.length() - _arc) * 0.35, 120.0)
	# spawn at initial
	var s: Dictionary = _sampler.sample(_arc)
	global_position = (s.pos as Vector2) + (s.perp as Vector2) * (_lane * _half_width)
	rotation = (s.dir as Vector2).angle() if (s.dir as Vector2).length() > 0.1 else 0.0
	_setup_body()
	_active = false
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0

func _setup_body() -> void:
	collision_layer = 1
	collision_mask = 1 | 2
	gravity_scale = 0.0
	can_sleep = false
	mass = 8.0
	linear_damp = 0.8
	# capsule approx car
	var cap := CapsuleShape2D.new()
	cap.radius = 15.0
	cap.height = 42.0
	var cs := CollisionShape2D.new()
	cs.shape = cap
	add_child(cs)
	# visual via procedural, dulled for non-racer traffic
	var sprite := Sprite2D.new()
	var tex := IDENTITIES.car_texture(_vehicle_id)
	if tex:
		sprite.texture = tex
		sprite.scale = Vector2(0.48, 0.48)
	sprite.modulate = Color(0.52, 0.55, 0.60, 1.0)  # duller, non-racer palette
	add_child(sprite)

func start() -> void:
	_active = true

func stop() -> void:
	_active = false
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0

func _physics_process(delta: float) -> void:
	if not _active or _sampler == null or _sampler.length() <= 0.0:
		linear_velocity = Vector2.ZERO
		return
	_arc += _speed * delta
	if _arc > _sampler.length() + 80.0:
		stop()
		return
	var s: Dictionary = _sampler.sample(_arc)
	var target_lane := _base_lane
	if _behavior == &"cutter":
		if not _cut_done and _arc >= _cut_arc:
			var t := clampf((_arc - _cut_arc) / 90.0, 0.0, 1.0)
			target_lane = lerp(_base_lane, -_base_lane, t)
			if t >= 1.0:
				_cut_done = true
				_base_lane = target_lane
	elif _behavior == &"line":
		_osc_t += delta * 1.8
		var osc := sin(_osc_t) * 0.22
		target_lane = _base_lane + osc
	_lane = target_lane
	var target_pos: Vector2 = (s["pos"] as Vector2) + (s["perp"] as Vector2) * (_lane * _half_width)
	var to: Vector2 = target_pos - global_position
	var desired: Vector2 = (s["dir"] as Vector2) * _speed
	if to.length() > 8.0:
		desired = desired * 0.6 + to.normalized() * _speed * 0.7
	linear_velocity = desired
	if desired.length() > 20.0:
		var target_rot: float = desired.angle()
		rotation = lerp_angle(rotation, target_rot, 12.0 * delta)
