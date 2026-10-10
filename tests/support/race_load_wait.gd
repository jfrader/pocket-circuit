extends RefCounted

## Test support: waits for a race load to finish, up to the App's own load
## timeout, so a test never fails a load the game itself would still wait for.

const APP := preload("res://scripts/autoload/app.gd")


static func finished(tree: SceneTree, app: Object) -> bool:
	var deadline := Time.get_ticks_msec() + APP.RACE_LOAD_TIMEOUT_MSEC
	while app.call("is_race_loading") and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	return not app.call("is_race_loading")
