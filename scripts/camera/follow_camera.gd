extends Camera2D

@export var look_ahead_distance: float = 145.0
@export var follow_smoothing: float = 7.5
@export var zoom_smoothing: float = 4.5
@export var slow_zoom: float = 1.12
@export var fast_zoom: float = 0.72
@export var speed_for_max_zoom: float = 680.0

var target_vehicle: Node2D
var _boost_pulse: float = 0.0
var _impact_nudge: float = 0.0


func _ready() -> void:
	call_deferred("_find_target")


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target_vehicle):
		return

	var velocity := Vector2.ZERO
	if target_vehicle is RigidBody2D:
		velocity = target_vehicle.linear_velocity
	var speed := velocity.length()
	var look_ahead := Vector2.ZERO
	if speed > 5.0:
		look_ahead = velocity.normalized() * look_ahead_distance * clampf(speed / speed_for_max_zoom, 0.0, 1.0)

	_impact_nudge = lerpf(_impact_nudge, 0.0, 1.0 - exp(-13.0 * delta))
	var nudge := Vector2(3.0, -2.0) * _impact_nudge
	var follow_weight := 1.0 - exp(-follow_smoothing * delta)
	global_position = global_position.lerp(target_vehicle.global_position + look_ahead + nudge, follow_weight)

	var speed_ratio := clampf(speed / speed_for_max_zoom, 0.0, 1.0)
	var boosting := bool(target_vehicle.call("is_boost_active"))
	_boost_pulse = lerpf(_boost_pulse, 1.0 if boosting else 0.0, 1.0 - exp(-8.0 * delta))
	var target_zoom := Vector2.ONE * lerpf(slow_zoom, fast_zoom, speed_ratio) * (1.0 - _boost_pulse * 0.015)
	var zoom_weight := 1.0 - exp(-zoom_smoothing * delta)
	zoom = zoom.lerp(target_zoom, zoom_weight)


func _find_target() -> void:
	target_vehicle = get_tree().get_first_node_in_group("player_vehicle") as Node2D
	if target_vehicle:
		global_position = target_vehicle.global_position


func set_target(vehicle: Node2D) -> void:
	target_vehicle = vehicle
	global_position = vehicle.global_position


func add_impact_nudge(strength: float) -> void:
	_impact_nudge = maxf(_impact_nudge, clampf(strength, 0.0, 1.0))
