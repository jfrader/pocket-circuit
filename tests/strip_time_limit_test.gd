extends SceneTree

const CONTROLLER := preload("res://scripts/race/strip_controller.gd")
const MARKER := preload("res://scripts/presentation/strip_destination_marker.gd")
const CUSTOM_LIMIT := 123.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var manager := RaceManager.new()
	get_root().add_child(manager)
	var player := VehicleController.new()
	var chaser := VehicleController.new()
	player.freeze = true
	chaser.freeze = true
	get_root().add_child(player)
	get_root().add_child(chaser)
	var controller := CONTROLLER.new()
	get_root().add_child(controller)
	controller.configure(manager, player, chaser, CUSTOM_LIMIT)
	var marker := MARKER.new()
	get_root().add_child(marker)
	var camera := Camera2D.new()
	get_root().add_child(camera)
	marker.configure(Vector2.UP * 1000.0, camera, manager, CUSTOM_LIMIT)
	if controller.time_limit != CUSTOM_LIMIT or marker.time_limit != CUSTOM_LIMIT:
		_fail("Controller and marker disagree on the prepared limit")
		return
	manager.is_running = true
	manager.race_time = 75.0
	controller._physics_process(0.01)
	if not controller.outcome.is_empty():
		_fail("Strip timed out at the legacy limit")
		return
	manager.race_time = CUSTOM_LIMIT - 0.005
	controller._physics_process(0.01)
	if controller.outcome != "TIME OUT":
		_fail("Strip did not time out at its prepared limit")
		return
	print("STRIP_TIME_LIMIT_TEST PASS limit=%.0fs" % CUSTOM_LIMIT)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
