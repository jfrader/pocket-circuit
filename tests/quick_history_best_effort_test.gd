extends SceneTree

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")

class FailingSaveStore extends SaveStore:
	var save_count := 0

	func _init() -> void:
		super("user://tests/pocket_circuit_quick_history_best_effort_test.json")

	func save_data(_data: Dictionary) -> bool:
		save_count += 1
		last_save_error = "Injected history failure"
		return false

class TestShell extends CanvasLayer:
	var save_error_shown := false

	func show_save_error(_title: String, _detail: String, _retry: Callable, _back: Callable) -> void:
		save_error_shown = true


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload should be available"):
		return
	var store := FailingSaveStore.new()
	var shell := TestShell.new()
	root.add_child(shell)
	app.set("_save_store", store)
	app.set("_save_data", store.default_data())
	app.set("_shell", shell)
	var seed := 424242
	var room: StringName = app.call("circuit_room_for_seed", seed)
	var launched: bool = app.call("start_circuit_race", &"kitchen", room, seed, "rustbug", false)
	var session: Dictionary = app.call("get_current_race_session")
	if not _expect(launched and String(session.get("mode", "")) == "quick" and int(session.get("event", {}).get("seed", -1)) == seed, "Quick Race should launch even when recent-history persistence fails"):
		return
	if not _expect(store.save_count == 1 and (app.call("get_save_data").get("circuit_history", []) as Array).is_empty() and not shell.save_error_shown, "best-effort Quick Race history must stay unsaved without showing a blocking save screen"):
		return
	app.set("_loading_cancelled", true)
	if is_instance_valid(app.get("_loading_screen")):
		(app.get("_loading_screen") as Node).queue_free()
	app.set("_loading_screen", null)
	app.set("_transitioning_to_race", false)
	app.current_race_session.clear()
	var identity: Dictionary = app.call("generated_circuit_identity", &"kitchen", room, seed, false)
	var discovery_launched: bool = app.call("start_discovery_race", identity, "rustbug", "0123456789abcdef")
	if not _expect(not discovery_launched and app.current_race_session.is_empty() and shell.save_error_shown and store.save_count == 2, "Discovery should preserve its blocking history-save behavior"):
		return
	root.remove_child(shell)
	shell.free()
	print("QUICK_HISTORY_BEST_EFFORT_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("QUICK_HISTORY_BEST_EFFORT_TEST FAIL: " + message)
	quit(1)
	return false