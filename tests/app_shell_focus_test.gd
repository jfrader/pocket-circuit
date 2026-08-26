extends SceneTree

const APP_SHELL_SCRIPT := preload("res://scripts/ui/app_shell.gd")

class TestApp extends Node:
	func get_save_data() -> Dictionary:
		return {
			"unlocked_vehicles": ["rustbug", "pinbolt"],
			"selected_vehicle": "pinbolt",
		}

	func start_race(_event_id: String, _vehicle_id: String, _quick_race: bool) -> void:
		pass


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := TestApp.new()
	var shell := APP_SHELL_SCRIPT.new() as CanvasLayer
	root.add_child(app)
	root.add_child(shell)
	shell.call("configure", app)
	shell.call("show_vehicle_select", "kitchen_crumb_rush", false)
	await process_frame
	await process_frame
	var focus_owner := root.get_viewport().gui_get_focus_owner()
	if focus_owner == null or focus_owner.name != "Vehicle_pinbolt":
		push_error("APP_SHELL_FOCUS_TEST FAIL: persisted selected vehicle should receive focus")
		quit(1)
		return
	root.remove_child(shell)
	root.remove_child(app)
	shell.free()
	app.free()
	print("APP_SHELL_FOCUS_TEST PASS")
	quit(0)
