extends Node2D

## RESCUED breaks pursuit, not the drive. ARRIVED/CAUGHT are terminal.
signal sprint_resolved(outcome: String, data: Dictionary)

const SPRITES := preload("res://scripts/vendor/procedural_2d/procedural_car_sprites.gd")
const CAPTURE_RANGE := SPRITES.IMAGE_WIDTH * 2.0
const CAPTURE_SECONDS := 1.5
const LIMIT_SECONDS := 180.0
const ARC_RADIUS := 43.0
const ARC_WIDTH := 8.0
const SCENERY_COLLISION_MASK := 2 | 4 | 16

var manager: RaceManager
var player: VehicleController
var chaser: VehicleController
var reduced_motion := false
var rescued := false
var outcome := ""
var exposure := 0.0
var _last_tick := -1
var _result: Dictionary = {}


func configure(race_manager: RaceManager, player_vehicle: VehicleController, chaser_vehicle: VehicleController, reduce_motion: bool = false) -> void:
	manager = race_manager
	player = player_vehicle
	chaser = chaser_vehicle
	reduced_motion = reduce_motion
	z_index = 10
	process_physics_priority = -10
	manager.racer_recovered.connect(_on_recovered)


func _physics_process(delta: float) -> void:
	_sample_once(delta)


func _sample_once(delta: float) -> void:
	var tick := Engine.get_physics_frames()
	if _last_tick == tick:
		return
	_last_tick = tick
	advance_pursuit(delta)


func advance_pursuit(delta: float) -> void:
	if not manager.is_running or not outcome.is_empty() or rescued:
		return
	var suspended := player.freeze or chaser.freeze
	var same_section := manager.get_expected_checkpoint(player) == manager.get_expected_checkpoint(chaser)
	var clear_sight := false
	if not suspended and same_section and player.global_position.distance_to(chaser.global_position) <= CAPTURE_RANGE:
		var query := PhysicsRayQueryParameters2D.create(player.global_position, chaser.global_position)
		query.exclude = [player.get_rid(), chaser.get_rid()]
		query.collision_mask = SCENERY_COLLISION_MASK
		clear_sight = get_world_2d().direct_space_state.intersect_ray(query).is_empty()
	if not clear_sight:
		exposure = 0.0
	else:
		exposure += maxf(0.0, delta)
	if exposure + 0.00001 >= CAPTURE_SECONDS:
		_resolve("CAUGHT", manager.race_time)
	elif manager.race_time + delta >= LIMIT_SECONDS:
		rescued = true
		exposure = 0.0
		_stop_chaser()
		sprint_resolved.emit("RESCUED", _data("RESCUED", LIMIT_SECONDS, false))
	queue_redraw()


func may_finish() -> bool:
	_sample_once(get_physics_process_delta_time())
	return outcome.is_empty()


func win(elapsed: float) -> void:
	_resolve("ARRIVED", elapsed)


func result() -> Dictionary:
	return _result.duplicate(true)


func capture_fraction() -> float:
	return clampf(exposure / CAPTURE_SECONDS, 0.0, 1.0)


func _resolve(value: String, elapsed: float) -> void:
	if not outcome.is_empty():
		return
	outcome = value
	manager.stop_race()
	_stop_chaser()
	_result = _data(value, elapsed, true)
	sprint_resolved.emit(value, result())
	queue_redraw()


func _data(value: String, elapsed: float, terminal: bool) -> Dictionary:
	return {"outcome": value, "elapsed": elapsed, "rescued": rescued, "terminal": terminal}


func _stop_chaser() -> void:
	chaser.set_controls_locked(true)
	chaser.linear_velocity = Vector2.ZERO
	chaser.angular_velocity = 0.0
	chaser.freeze = true


func _on_recovered(_racer: Node2D) -> void:
	exposure = 0.0
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(player) or exposure <= 0.0 or rescued or not outcome.is_empty():
		return
	var center := to_local(player.global_position)
	draw_arc(center, ARC_RADIUS, -PI * 0.5, -PI * 0.5 + TAU, 48, Color(0.12, 0.08, 0.12, 0.8), ARC_WIDTH, true)
	var fraction := 1.0 if reduced_motion else capture_fraction()
	draw_arc(center, ARC_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * fraction, 48, Color(1.0, 0.19, 0.12), ARC_WIDTH, true)
