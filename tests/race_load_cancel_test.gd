extends SceneTree

## GURI-1857 (Race loading compiles its scripts off the main thread): a cancelled
## race load stops waiting on its worker at once instead of holding the
## loading screen until the compile ends.

const RACE_SCENE := "res://scenes/race/prototype_race.tscn"
## A cancelled load returns within this many frames, far below a cold compile.
const CANCEL_FRAME_LIMIT := 3

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload must exist"):
		return
	if not _expect(not ResourceLoader.has_cached(RACE_SCENE), "the race scene starts uncached in a fresh process"):
		return
	# Cancel once the load is under way, the way ESC on the loading screen does.
	var result := {}
	var frames := [0]
	var load_and_record := func() -> void: result["scene"] = await app.call("_load_race_scene")
	load_and_record.call()
	await process_frame
	if not _expect(not result.has("scene") and app.get("_race_scene_thread") != null, "a cold load is still running on its worker"):
		return
	app.set("_loading_cancelled", true)
	while not result.has("scene") and frames[0] <= CANCEL_FRAME_LIMIT:
		await process_frame
		frames[0] += 1
	app.set("_loading_cancelled", false)
	if not _expect(result.has("scene") and result["scene"] == null, "a cancelled load returns at once (still waiting after %d frames)" % frames[0]):
		return
	# The load keeps running in the background and the next race joins it.
	var again: Resource = await app.call("_load_race_scene")
	if not _expect(again is PackedScene, "the next load gets the race scene"):
		return
	if _failed:
		return
	print("RACE_LOAD_CANCEL_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error("RACE_LOAD_CANCEL_TEST FAIL: " + message)
		quit(1)
	return condition
