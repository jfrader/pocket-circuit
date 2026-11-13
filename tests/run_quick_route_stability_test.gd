extends SceneTree

const BOOT_SCENE := preload("res://scenes/boot/boot.tscn")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node("App")
	var boot := BOOT_SCENE.instantiate()
	root.add_child(boot)
	current_scene = boot
	await _wait_frames(3)
	var shell := app.get("_shell") as CanvasLayer
	for mode in ["quick_race", "quick_strip"]:
		shell.call("show_" + mode)
		await _wait_frames(3)
		var original: Dictionary = shell.call("_current_quick_identity")
		var original_code: Dictionary = app.call("circuit_share_code", original)
		var original_length := String(shell.get("_quick_race_length_tier"))
		for return_action in ["back", "play_vehicle"]:
			if not _press_button(shell, "CHANGE CAR"):
				return
			await _wait_frames(2)
			if not _expect(String(shell.get("_screen")) == "vehicle_select", mode + " opens vehicle selection"):
				return
			shell.call("_on_art_action", StringName(return_action))
			await _wait_frames(3)
			var returned: Dictionary = shell.call("_current_quick_identity")
			if not _expect(returned == original and app.call("circuit_share_code", returned) == original_code and String(shell.get("_quick_race_length_tier")) == original_length, mode + " preserves route, code and length after " + return_action):
				return
		if OS.is_debug_build():
			if not _press_button(shell, "REROLL"):
				return
			var rerolled: Dictionary = shell.call("_current_quick_identity")
			if not _expect(rerolled != original, mode + " explicitly rerolls the route"):
				return
			shell.call("show_vehicle_select", "", true)
			shell.call("go_back")
			if not _expect(shell.call("_current_quick_identity") == rerolled, mode + " preserves the rerolled route"):
				return
		var before_leaving: Dictionary = shell.call("_current_quick_identity")
		shell.call("go_back")
		if not _expect(String(shell.get("_screen")) == "title", mode + " leaves to title"):
			return
		shell.call("show_" + mode)
		if not _expect(shell.call("_current_quick_identity") != before_leaving, mode + " generates a fresh route after leaving"):
			return
		shell.call("go_back")
	await _wait_frames(10)
	print("RUN_QUICK_ROUTE_STABILITY_TEST PASS")
	quit(0)


func _press_button(shell: Node, prefix: String) -> bool:
	for node in shell.find_children("*", "Button", true, false):
		var button := node as Button
		if button.is_visible_in_tree() and button.text.begins_with(prefix):
			button.pressed.emit()
			return true
	return _expect(false, "missing button " + prefix)


func _wait_frames(count: int) -> void:
	for _frame in count:
		await process_frame


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("RUN_QUICK_ROUTE_STABILITY_TEST FAIL: " + message)
	quit(1)
	return false
