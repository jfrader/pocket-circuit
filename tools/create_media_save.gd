extends SceneTree

const CATALOG := preload("res://data/championship/catalog.gd")
const SAVE_STORE_SCRIPT := preload("res://scripts/persistence/save_store.gd")


func _initialize() -> void:
	var store := SAVE_STORE_SCRIPT.new()
	var progress: Dictionary = store.default_data()
	progress["championship_started"] = true
	progress["first_run"] = false
	for event: Dictionary in CATALOG.EVENTS:
		var summary := CATALOG.apply_event_result(progress, String(event["id"]), 1)
		progress = summary["save"]
	progress["ending_seen"] = true
	progress["selected_vehicle"] = "rustbug"
	if not store.save_data(progress):
		push_error("MEDIA_SAVE FAIL: " + store.last_save_error)
		quit(1)
		return
	print("MEDIA_SAVE PASS: " + ProjectSettings.globalize_path(store.save_path))
	quit(0)
