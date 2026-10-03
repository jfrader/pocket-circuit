extends Node2D

signal outcome_resolved(headline: String, elapsed: float)

const CAPTURE := preload("res://scripts/race/strip_capture.gd")
const LIMIT_SECONDS := 75.0
const ARC_RADIUS := 43.0
const ARC_WIDTH := 8.0
const SCENERY_COLLISION_MASK := 2 | 4 | 16
const RECOVERY_GHOST_SECONDS := 1.5

var manager: RaceManager
var player: VehicleController
var chaser: VehicleController
var capture := CAPTURE.new()
var outcome := ""
var _ghost_until := 0.0
var _last_tick := -1


func configure(race_manager: RaceManager, player_vehicle: VehicleController, chaser_vehicle: VehicleController) -> void:
	manager = race_manager
	player = player_vehicle
	chaser = chaser_vehicle
	z_index = 10
	process_physics_priority = -10
	manager.racer_recovered.connect(_on_recovered)


func _physics_process(delta: float) -> void:
	if manager == null or not manager.is_running or not outcome.is_empty():
		return
	_sample_capture(delta)
	if outcome.is_empty() and manager.race_time + delta >= LIMIT_SECONDS:
		_resolve("TIME OUT")
	queue_redraw()


func may_finish() -> bool:
	if not outcome.is_empty():
		return false
	# Sensors may report before this node's physics callback on the same tick.
	_sample_capture(get_physics_process_delta_time())
	return outcome.is_empty()


func win(elapsed: float) -> void:
	if outcome.is_empty():
		_resolve("STRIP WON", elapsed)


func _sample_capture(delta: float) -> void:
	var tick := Engine.get_physics_frames()
	if _last_tick == tick:
		return
	_last_tick = tick
	var suspended := manager.race_time < _ghost_until or player.freeze or chaser.freeze
	var same_section := manager.get_expected_checkpoint(player) == manager.get_expected_checkpoint(chaser)
	var clear_sight := false
	if not suspended and same_section and player.global_position.distance_to(chaser.global_position) <= CAPTURE.CAPTURE_RANGE:
		var query := PhysicsRayQueryParameters2D.create(player.global_position, chaser.global_position)
		query.exclude = [player.get_rid(), chaser.get_rid()]
		query.collision_mask = SCENERY_COLLISION_MASK
		clear_sight = get_world_2d().direct_space_state.intersect_ray(query).is_empty()
	if capture.advance(delta, player.global_position.distance_to(chaser.global_position), same_section, clear_sight, suspended):
		_resolve("CAPTURED")


func _on_recovered(_racer: Node2D) -> void:
	capture.clear()
	_ghost_until = manager.race_time + RECOVERY_GHOST_SECONDS


func _resolve(value: String, elapsed: float = -1.0) -> void:
	if not outcome.is_empty():
		return
	outcome = value
	manager.stop_race()
	if is_instance_valid(chaser):
		chaser.linear_velocity = Vector2.ZERO
		chaser.angular_velocity = 0.0
		chaser.freeze = true
	outcome_resolved.emit(value, manager.race_time if elapsed < 0.0 else elapsed)
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(player) or capture.exposure <= 0.0 or not outcome.is_empty():
		return
	var center := to_local(player.global_position)
	draw_arc(center, ARC_RADIUS, -PI * 0.5, -PI * 0.5 + TAU, 48, Color(0.12, 0.08, 0.12, 0.8), ARC_WIDTH, true)
	draw_arc(center, ARC_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * capture.fraction(), 48, Color(1.0, 0.19, 0.12), ARC_WIDTH, true)
