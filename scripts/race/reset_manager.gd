extends Node

@export var valid_bounds: Rect2 = Rect2(-1020.0, -620.0, 2040.0, 1240.0)
@export var valid_polygon := PackedVector2Array()
@export var valid_polygon_margin := 0.0
@export var ghost_duration: float = 1.5
@export var stuck_timeout: float = 2.4

var _vehicle: RigidBody2D
var _race_manager: Node
var _stuck_time: float = 0.0
var _recovering: bool = false


func _ready() -> void:
	call_deferred("_find_dependencies")


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_vehicle) or _recovering:
		return
	if not _can_recover():
		_stuck_time = 0.0
		return
	if Input.is_action_just_pressed("reset") or not is_position_valid(_vehicle.global_position):
		recover_vehicle()
		return

	var trying_to_move := Input.get_action_strength("accelerate") > 0.7
	if trying_to_move and _vehicle.linear_velocity.length() < 18.0:
		_stuck_time += delta
		if _stuck_time >= stuck_timeout:
			recover_vehicle()
	else:
		_stuck_time = 0.0


func is_position_valid(position: Vector2) -> bool:
	if valid_polygon.is_empty():
		return valid_bounds.has_point(position)
	if Geometry2D.is_point_in_polygon(position, valid_polygon):
		return true
	for index in valid_polygon.size():
		if _point_segment_distance(position, valid_polygon[index], valid_polygon[(index + 1) % valid_polygon.size()]) <= valid_polygon_margin:
			return true
	return false


func _point_segment_distance(point: Vector2, from: Vector2, to: Vector2) -> float:
	var segment := to - from
	if segment.length_squared() < 0.001:
		return point.distance_to(from)
	var fraction := clampf((point - from).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(from + segment * fraction)


func _find_dependencies() -> void:
	_vehicle = get_tree().get_first_node_in_group("player_vehicle") as RigidBody2D
	_race_manager = get_tree().get_first_node_in_group("race_manager")


func recover_vehicle() -> void:
	if _recovering or not is_instance_valid(_vehicle) or not _can_recover():
		return
	_recovering = true
	_stuck_time = 0.0

	var saved_layer := _vehicle.collision_layer
	var saved_mask := _vehicle.collision_mask
	var recovery_transform: Transform2D = _race_manager.get_last_recovery_transform()
	var recovery_forward := Vector2.UP.rotated(recovery_transform.get_rotation())

	_vehicle.freeze = true
	_vehicle.global_transform = recovery_transform
	_vehicle.linear_velocity = Vector2.ZERO
	_vehicle.angular_velocity = 0.0
	if _vehicle.has_method("reset_surface_modifiers"):
		_vehicle.call("reset_surface_modifiers")
	_vehicle.collision_layer = 0
	_vehicle.collision_mask = 0
	_vehicle.modulate.a = 0.45
	_vehicle.freeze = false
	_vehicle.linear_velocity = recovery_forward * 55.0
	if "boost_amount" in _vehicle:
		_vehicle.boost_amount *= 0.5

	await get_tree().create_timer(ghost_duration, false).timeout
	if is_instance_valid(_vehicle):
		_vehicle.collision_layer = saved_layer
		_vehicle.collision_mask = saved_mask
		_vehicle.modulate.a = 1.0
	_recovering = false


func _can_recover() -> bool:
	if not is_instance_valid(_vehicle) or not is_instance_valid(_race_manager):
		return false
	if not bool(_race_manager.get("is_running")):
		return false
	if _race_manager.has_method("is_racer_finished") and bool(_race_manager.call("is_racer_finished", _vehicle)):
		return false
	return true
