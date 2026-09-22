extends SceneTree

## Drives a real vehicle through a corner and a slide. A small steer must stay
## silent. The screech belongs to the slide, not to the steering input.

const VEHICLE_SCENE := preload("res://scenes/vehicles/rustbug.tscn")
const CATALOG := preload("res://data/championship/catalog.gd")
const PHYSICS_HZ := 60
## A correction is not tyre sound. Scrub stays under this until the wheel is
## past the onset.
const QUIET_TURN := 0.05

var _world: Node2D
var _errors := PackedStringArray()


func _initialize() -> void:
	Engine.physics_ticks_per_second = PHYSICS_HZ
	call_deferred("_run_test")


func _run_test() -> void:
	_world = Node2D.new()
	root.add_child(_world)
	current_scene = _world
	var vehicle := VEHICLE_SCENE.instantiate() as VehicleController
	vehicle.stats = CATALOG.create_vehicle_stats("rustbug")
	_world.add_child(vehicle)
	vehicle.controls_locked = false
	Input.action_press("accelerate")
	for _frame in 150:
		await physics_frame

	var straight_state: Dictionary = vehicle.call("get_tyre_state")
	_check("straight line makes no tyre sound", float(straight_state["cornering"]) < 0.02, "scrub %.3f" % float(straight_state["cornering"]))
	_check("straight line does not screech", float(straight_state["screech"]) < 0.02, "screech %.3f" % float(straight_state["screech"]))
	_check("straight line agrees with gameplay grip", not bool(straight_state["sliding"]) and not vehicle.is_sliding and not vehicle.is_drifting, str(straight_state))

	var light := await _steer_to(vehicle, 0.08)
	var gentle := await _steer_to(vehicle, 0.16)
	var firm := await _steer_to(vehicle, 0.25)
	_check("a small steer stays silent", light < QUIET_TURN and gentle < QUIET_TURN, "light %.3f gentle %.3f" % [light, gentle])
	_check("a firm corner is still not a slide", firm < 0.45, "scrub %.3f" % firm)
	var gripping_state: Dictionary = vehicle.call("get_tyre_state")
	_check("cornering alone does not screech", float(gripping_state["screech"]) < 0.02, "screech %.3f" % float(gripping_state["screech"]))
	_check("audio cannot call a gripping car sliding", bool(gripping_state["sliding"]) == (vehicle.is_sliding or vehicle.is_drifting), str(gripping_state))
	_check("a firm corner stays below a slide", firm < 0.9, "scrub %.3f" % firm)

	var slide := await _steer_to(vehicle, 0.45)
	_check("a slide is louder than a gripped corner", slide > firm, "slide %.3f firm %.3f" % [slide, firm])
	var sliding_state: Dictionary = vehicle.call("get_tyre_state")
	var screech := float(sliding_state["screech"])
	_check("the real arcade state machine reports a slide", vehicle.is_sliding, str(sliding_state))
	_check("audio reads the same sliding truth", bool(sliding_state["sliding"]) == (vehicle.is_sliding or vehicle.is_drifting), str(sliding_state))
	_check("a slide screeches", screech > 0.08, "screech %.3f" % screech)

	Input.action_release("steer_right")
	Input.action_release("accelerate")
	for _frame in 120:
		await physics_frame
	var released_state: Dictionary = vehicle.call("get_tyre_state")
	_check("the slide clears when it ends", float(released_state["screech"]) < 0.02 and not bool(released_state["sliding"]), str(released_state))

	_world.queue_free()
	await process_frame
	if _errors.is_empty():
		print("TYRE_AUDIO_DRIVER_TEST PASS")
		quit(0)
		return
	for error in _errors:
		push_error("TYRE_AUDIO_DRIVER_TEST FAIL: " + error)
	quit(1)


## Holds a steering input long enough for the physics to settle, then reports the
## resulting scrub level.
func _steer_to(vehicle: VehicleController, steer: float) -> float:
	Input.action_press("steer_right", steer)
	for _frame in 70:
		await physics_frame
	return float(vehicle.call("get_tyre_scrub"))


func _check(label: String, condition: bool, detail: String) -> void:
	if not condition:
		_errors.append("%s (%s)" % [label, detail])
