extends Area2D

@export var checkpoint_index: int = 0
@export var is_finish_line: bool = false
@export var recovery_rotation: float = 0.0
@export var recovery_offset: float = 65.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player_vehicle"):
		return
	var race_manager := get_tree().get_first_node_in_group("race_manager")
	if race_manager:
		race_manager.report_checkpoint(self, body)


func get_recovery_transform() -> Transform2D:
	var forward := Vector2.UP.rotated(recovery_rotation)
	return Transform2D(recovery_rotation, global_position + forward * recovery_offset)
