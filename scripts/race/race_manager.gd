extends Node

signal checkpoint_passed(checkpoint_index: int)
signal lap_completed(lap: int)
signal race_finished(total_time: float)

@export_range(1, 99) var laps_to_finish: int = 3

var checkpoints: Array[Node] = []
var current_checkpoint_index: int = 0
var lap_count: int = 0
var race_time: float = 0.0
var is_running: bool = false
var last_recovery_transform: Transform2D = Transform2D.IDENTITY


func _ready() -> void:
	call_deferred("_initialize_race")


func _process(delta: float) -> void:
	if is_running:
		race_time += delta


func _initialize_race() -> void:
	checkpoints.assign(get_tree().get_nodes_in_group("track_checkpoints"))
	checkpoints.sort_custom(func(a: Node, b: Node) -> bool: return a.checkpoint_index < b.checkpoint_index)
	var vehicle := get_tree().get_first_node_in_group("player_vehicle") as Node2D
	if vehicle:
		last_recovery_transform = vehicle.global_transform
	start_race()


func start_race() -> void:
	current_checkpoint_index = 1 if checkpoints.size() > 1 else 0
	lap_count = 0
	race_time = 0.0
	is_running = true


func stop_race() -> void:
	is_running = false


func report_checkpoint(checkpoint: Area2D, body: Node2D) -> bool:
	if not is_running or not body.is_in_group("player_vehicle"):
		return false
	if checkpoint.checkpoint_index != current_checkpoint_index:
		return false

	last_recovery_transform = checkpoint.get_recovery_transform()
	checkpoint_passed.emit(current_checkpoint_index)

	if checkpoint.is_finish_line:
		lap_count += 1
		lap_completed.emit(lap_count)
		current_checkpoint_index = 1 if checkpoints.size() > 1 else 0
		if lap_count >= laps_to_finish:
			stop_race()
			race_finished.emit(race_time)
	else:
		current_checkpoint_index = 0 if current_checkpoint_index >= checkpoints.size() - 1 else current_checkpoint_index + 1
	return true


func get_checkpoint_count() -> int:
	return checkpoints.size()


func get_last_recovery_transform() -> Transform2D:
	return last_recovery_transform
