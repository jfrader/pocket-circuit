class_name TrafficCar
extends RigidBody2D

const CAR_GEN := preload("res://scripts/vendor/procedural_2d/procedural_car_generator.gd")
const CAR_SPR := preload("res://scripts/vendor/procedural_2d/procedural_car_sprites.gd")

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
var _swerve_phase := 0.0
var _is_truck := false

func configure(arc: float, lane: float, speed: float, behavior: StringName, vehicle_id: String, sampler: RefCounted, half_width: float) -> void:
	_sampler = sampler
	_half_width = half_width
	_arc = arc
	_base_lane = lane
	_lane = lane
	_behavior = behavior if behavior in [&"cruiser", &"cutter", &"line", &"swerve", &"truck"] else &"cruiser"
	_vehicle_id = vehicle_id if vehicle_id else "rustbug"
	_is_truck = _behavior == &"truck"
	# deterministic from entry
	var seed := _stable_seed(_vehicle_id + ":" + str(int(arc)) + ":" + str(int(lane * 100)))
	# small var + behavior adjust
	var var_f := 1.0 + float(seed % 5 - 2) * 0.012
	_speed = speed * var_f
	if _is_truck:
		_speed *= 0.55
	_cut_done = false
	_osc_t = 0.0
	_swerve_phase = 0.0
	if _behavior == &"cutter":
		_cut_arc = _arc + maxf((_sampler.length() - _arc) * 0.35, 120.0)
	elif _behavior == &"swerve":
		# out and back later
		_swerve_phase = 0.0
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
	mass = 8.0 if not _is_truck else 18.0
	linear_damp = 0.8
	# size by behavior
	var r := 15.0
	var h := 42.0
	var vscale := 0.48
	if _is_truck:
		r = 19.0
		h = 58.0
		vscale = 0.62
	var cap := CapsuleShape2D.new()
	cap.radius = r
	cap.height = h
	var cs := CollisionShape2D.new()
	cs.shape = cap
	add_child(cs)
	# visual: procedural civilian car, deterministic from entry, distinct palette/livery from racers
	var sprite := Sprite2D.new()
	var payload := _make_civilian_payload()
	var tex := CAR_SPR.car_texture(payload, 2)
	if tex:
		sprite.texture = tex
		sprite.scale = Vector2(vscale, vscale)
	add_child(sprite)

func _make_civilian_payload() -> Dictionary:
	var seed_val := _stable_seed(_vehicle_id + str(int(_arc)) + str(int(_lane*100)))
	var types := CAR_GEN.available_types()
	var ctype := types[seed_val % types.size()]
	# civilian muted palettes + simple livery, distinct from racer flash
	var pals: Array[String] = ["desert_sage", "midnight_teal", "plum_soda"]
	var pal: String = pals[seed_val % pals.size()]
	var opts := {
		"palette_id": pal,
		"livery": "solid"
	}
	# slight parts civilian
	if seed_val % 3 == 0:
		opts["bumpers"] = "utility"
	return CAR_GEN.generate(seed_val, ctype, opts)

func _stable_seed(text: String) -> int:
	var h := 2166136261
	for b in text.to_utf8_buffer():
		h = ((h ^ int(b)) * 16777619) & 0xffffffff
	return maxi(1, h)

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
	elif _behavior == &"swerve":
		_swerve_phase = fposmod(_swerve_phase + delta * 0.8, 3.0)
		var p := _swerve_phase / 3.0
		if p < 0.25:
			target_lane = _base_lane
		elif p < 0.75:
			target_lane = -_base_lane * 0.9
		else:
			target_lane = _base_lane
	elif _is_truck:
		# slow, heavy, holds lane longer
		target_lane = _base_lane
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
