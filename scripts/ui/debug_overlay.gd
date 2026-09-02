extends CanvasLayer

var _vehicle: RigidBody2D
var _race_manager: Node
var debug_label: Label


func _ready() -> void:
	visible = false
	if not OS.is_debug_build():
		queue_free()
		return
	_build_ui()
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
	var surface_grip: float = _vehicle.get("surface_grip_multiplier")
	var surface_speed: float = _vehicle.get("surface_speed_multiplier")
	debug_label.text = (
		"PHASE 0 TELEMETRY [F3]\n"
		+ "speed      %6.1f px/s\n" % speed
		+ "velocity   (%6.1f, %6.1f)\n" % [_vehicle.linear_velocity.x, _vehicle.linear_velocity.y]
		+ "grip       %6.2f\n" % grip
		+ "slip       %+6.1f deg\n" % slip_angle
		+ "drifting   %s\n" % ("YES" if drifting else "no")
		+ "boost      %5.1f%%\n" % boost
		+ "surface    %s  ·  %.2fx grip / %.2fx speed\n" % [surface, surface_grip, surface_speed]
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


func _build_ui() -> void:
	layer = 20
	var panel := Panel.new()
	panel.name = "Panel"
	panel.modulate = Color(0.08, 0.1, 0.14, 0.9)
	panel.position = Vector2(16.0, 72.0)
	panel.size = Vector2(310.0, 300.0)
	add_child(panel)
	debug_label = Label.new()
	debug_label.name = "DebugLabel"
	debug_label.position = Vector2(12.0, 10.0)
	debug_label.size = Vector2(285.0, 275.0)
	debug_label.add_theme_color_override("font_color", Color(0.75, 0.96, 1.0))
	debug_label.add_theme_font_size_override("font_size", 14)
	debug_label.text = "PHASE 0 TELEMETRY"
	panel.add_child(debug_label)
