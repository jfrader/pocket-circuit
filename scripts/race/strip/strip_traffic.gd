class_name StripTraffic
extends Node

const TRAFFIC_CAR := preload("res://scripts/race/strip/traffic_car.gd")
const ROUTE_SAMPLER := preload("res://scripts/race/strip/strip_route_sampler.gd")

var _sampler := ROUTE_SAMPLER.new()
var _half_width := 80.0
var _plan: Array = []
var _manager: RaceManager
var _cars: Array = []


func configure(route: PackedVector2Array, half_width: float, plan: Array, race_manager: RaceManager) -> void:
	_half_width = half_width
	_plan = plan.duplicate(true)
	_manager = race_manager
	_sampler.configure(route)
	_clear_cars()
	for entry in _plan:
		var e := entry as Dictionary
		var car := TRAFFIC_CAR.new()
		car.configure(
			float(e.get("arc", 0.0)),
			float(e.get("lane", 0.0)),
			float(e.get("speed", 100.0)),
			StringName(e.get("behavior", "cruiser")),
			String(e.get("vehicle_id", "rustbug")),
			_sampler,
			_half_width
		)
		add_child(car)
		car.add_to_group(&"track_traffic")
		_cars.append(car)
	_set_active(false)
	if _manager and is_instance_valid(_manager):
		if not _manager.race_started.is_connected(_on_race_started):
			_manager.race_started.connect(_on_race_started)
		if not _manager.race_finished.is_connected(_on_race_finished):
			_manager.race_finished.connect(_on_race_finished)


func _set_active(active: bool) -> void:
	for car in _cars:
		if active:
			car.start()
		else:
			car.stop()


func _on_race_started() -> void:
	_set_active(true)


func _on_race_finished(_total_time: float = 0.0) -> void:
	_set_active(false)


func _clear_cars() -> void:
	for car in _cars:
		if is_instance_valid(car):
			car.queue_free()
	_cars.clear()


func _exit_tree() -> void:
	_clear_cars()
