class_name EngineDrivetrainModel
extends RefCounted

## Maps the arcade vehicle's speed and inputs onto shaft RPM and gears. The game
## has no gearbox; this is the sound-side one, so the engine note gets the
## sawtooth pull-and-drop a racer expects. It never touches gameplay.

## RPM at max_speed in top gear, as a fraction of redline.
const TOP_GEAR_RPM_RATIO := 0.85
const SHIFT_UP_RATIO := 0.94
const SHIFT_DOWN_RATIO := 0.42
## Below this fraction of max_speed the clutch is still slipping.
const CLUTCH_SPEED_RATIO := 0.10
## Free-rev ceiling while the clutch slips, as a fraction of redline.
const LAUNCH_RPM_RATIO := 0.45
const SHIFT_CUT_SECONDS := 0.16
const RISE_TAU := 0.055
const FALL_TAU := 0.085
const MAX_DELTA := 0.25

var _idle_rpm := 1050.0
var _redline_rpm := 7600.0
var _ratios := PackedFloat32Array()
var _top_ratio := 1.0
var _rpm := 1050.0
var _gear := 0
var _shift_timer := 0.0
var _shift_count := 0
var _throttle := 0.0
var _load := 0.0


func configure(recipe: EngineRecipe) -> void:
	_idle_rpm = recipe.idle_rpm
	_redline_rpm = recipe.redline_rpm
	_ratios = recipe.gear_ratios
	_top_ratio = _ratios[_ratios.size() - 1]
	_rpm = _idle_rpm
	_gear = 0
	_shift_timer = 0.0
	_shift_count = 0
	_throttle = 0.0
	_load = 0.0


func step(speed: float, max_speed: float, load: float, throttle: float, delta: float) -> void:
	var safe_delta := clampf(delta, 0.0, MAX_DELTA)
	_load = clampf(load, 0.0, 1.0)
	var pedal := clampf(throttle, 0.0, 1.0)
	var speed_ratio := clampf(speed / maxf(max_speed, 1.0), 0.0, 1.25)
	var target := _geared_rpm(speed_ratio)
	var clutch := clampf(speed_ratio / CLUTCH_SPEED_RATIO, 0.0, 1.0)
	if clutch < 1.0:
		var launch_rpm := _idle_rpm + pedal * (LAUNCH_RPM_RATIO * _redline_rpm - _idle_rpm)
		target = lerpf(launch_rpm, target, clutch)
	target = clampf(target, _idle_rpm, _redline_rpm)
	_update_shift(safe_delta, pedal)
	_throttle = 0.0 if _shift_timer > 0.0 else pedal
	var tau := RISE_TAU if target > _rpm else FALL_TAU
	_rpm = lerpf(_rpm, target, 1.0 - exp(-safe_delta / tau))


func get_rpm() -> float:
	return _rpm


func get_gear() -> int:
	return _gear


func get_gear_count() -> int:
	return _ratios.size()


## Throttle after the shift cut, so the synth ducks turbo and air on a shift.
func get_throttle() -> float:
	return _throttle


func get_load() -> float:
	return _load


func get_shift_count() -> int:
	return _shift_count


func is_shifting() -> bool:
	return _shift_timer > 0.0


func _geared_rpm(speed_ratio: float) -> float:
	return _redline_rpm * TOP_GEAR_RPM_RATIO * speed_ratio * (_ratios[_gear] / _top_ratio)


func _update_shift(delta: float, pedal: float) -> void:
	if _shift_timer > 0.0:
		_shift_timer = maxf(0.0, _shift_timer - delta)
		return
	# A lifted throttle must not upshift on a falling rev.
	if _rpm >= SHIFT_UP_RATIO * _redline_rpm and _gear < _ratios.size() - 1 and pedal > 0.0:
		_gear += 1
		_begin_shift()
	elif _rpm <= SHIFT_DOWN_RATIO * _redline_rpm and _gear > 0:
		_gear -= 1
		_begin_shift()


func _begin_shift() -> void:
	_shift_timer = SHIFT_CUT_SECONDS
	_shift_count += 1
