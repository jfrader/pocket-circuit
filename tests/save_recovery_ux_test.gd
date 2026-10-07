extends SceneTree

const MENU := preload("res://scripts/ui/championship_menu.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var menu := MENU.new() as Control
	menu.size = Vector2(1280, 720)
	root.add_child(menu)

	menu.call("show_title", false, true, "rustbug", ["rustbug"], "Save recovered from backup")
	if not _expect(_has_label(menu, "Save recovered from backup"), "a recovery message must be shown verbatim on the title"):
		return

	menu.call("show_title", false, true, "rustbug", ["rustbug"], "")
	if not _expect(_has_label(menu, "SAVE READ-ONLY · QUICK RACE AVAILABLE"), "read-only without a recovery message keeps the legacy status line"):
		return

	menu.call("show_title", true, false, "rustbug", ["rustbug"], "")
	if not _expect(_has_label(menu, "CONTINUE YOUR CHAMPIONSHIP"), "a healthy save keeps the normal title status"):
		return

	root.remove_child(menu)
	menu.free()
	print("SAVE_RECOVERY_UX_TEST PASS")
	quit(0)


func _has_label(node: Node, text: String) -> bool:
	if node is Label and String((node as Label).text) == text:
		return true
	for child in node.get_children():
		if _has_label(child, text):
			return true
	return false


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("SAVE_RECOVERY_UX_TEST FAIL: " + message)
	quit(1)
	return false
