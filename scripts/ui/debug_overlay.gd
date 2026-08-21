extends CanvasLayer

@onready var debug_label: Label = $Panel/DebugLabel

var _vehicle: RigidBody2D
var _race_manager: Node


func _ready() -> void:
	visible = false
	if not OS.is_debug_build():
		queue_free()
		return
	call_deferred("_find_dependencies")


func _process(_delta: float) -> void:
	if not visible or not is_instance_valid(_vehicle) or not is_instance_valid(_race_manager):
		return

	var speed: float = _vehicle.get("speed")
	var grip: float = _vehicle.get("current_grip")
	var slip_angle: float = _vehicle.get("slip_angle")
	var drifting: bool = _vehicle.get("is_drifting")
	var boost: float = _vehicle.get("boost_amount")
	var surface: String = str(_vehicle.get("current_surface"))
	debug_label.text = (
		"PHASE 0 TELEMETRY [F3]\n"
		+ "speed      %6.1f px/s\n" % speed
		+ "velocity   (%6.1f, %6.1f)\n" % [_vehicle.linear_velocity.x, _vehicle.linear_velocity.y]
		+ "grip       %6.2f\n" % grip
		+ "slip       %+6.1f deg\n" % slip_angle
		+ "drifting   %s\n" % ("YES" if drifting else "no")
		+ "boost      %5.1f%%\n" % boost
		+ "surface    %s\n" % surface
		+ "next gate  %d\n" % _race_manager.current_checkpoint_index
		+ "lap        %d / %d\n" % [_race_manager.lap_count, _race_manager.laps_to_finish]
		+ "render fps %d\n" % Engine.get_frames_per_second()
		+ "physics hz %d" % Engine.physics_ticks_per_second
	)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		visible = not visible
		get_viewport().set_input_as_handled()


func _find_dependencies() -> void:
	_vehicle = get_tree().get_first_node_in_group("player_vehicle") as RigidBody2D
	_race_manager = get_tree().get_first_node_in_group("race_manager")
