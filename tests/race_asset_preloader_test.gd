extends SceneTree

## Guards the menu-time race asset preloader (GURI-1627): a full pass must
## finish and retain the race scene's resource set, so the race loading walk
## sees cache hits instead of paying the loads.

const BOOT_SCENE := "res://scenes/boot/boot.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	change_scene_to_file(BOOT_SCENE)
	await process_frame
	await process_frame
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload must exist"):
		return
	var preloader: Node = app.get("_race_asset_preloader")
	if not _expect(preloader != null, "the race asset preloader must exist"):
		return
	var deadline := Time.get_ticks_msec() + 300000
	while not bool(preloader.call("is_finished")) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _expect(bool(preloader.call("is_finished")), "the menu preloader must finish"):
		return
	var metrics: Dictionary = preloader.call("debug_metrics")
	if not _expect(int(metrics.get("prewarmed_resources", 0)) > 0, "the preloader must retain the race resource set"):
		return
	print("RACE_ASSET_PRELOADER_TEST PASS resources=", int(metrics.get("prewarmed_resources", 0)))
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("RACE_ASSET_PRELOADER_TEST FAIL: " + message)
	quit(1)
	return false
