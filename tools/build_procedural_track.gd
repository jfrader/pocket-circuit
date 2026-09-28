extends SceneTree

## CLI wrapper for TrackBuilderCore — builds and SAVES a track scene to disk.
## Headless: PC_THEME=workshop|office, PC_SEED=N, PC_ROOM=classic|wide|tall|el,
## PC_SCENE_OUT=res://path.tscn (defaults to the theme's canonical scene).

var _theme: StringName = &"workshop"
var _seed: int = -1
var _room_shape: StringName = &"classic"


func _init() -> void:
	var env := OS.get_environment("PC_THEME")
	if env in [&"kitchen", &"workshop", &"office"]:
		_theme = StringName(env)
	var seed_env := OS.get_environment("PC_SEED")
	if not seed_env.is_empty():
		_seed = int(seed_env)
	var room_env := OS.get_environment("PC_ROOM")
	if room_env in GeneratedCircuitRules.ROOMS:
		_room_shape = StringName(room_env)
	call_deferred("_run")


func _run() -> void:
	var result := TrackBuilderCore.build_packed(_theme, _room_shape, _seed)
	if result["scene"] == null:
		quit(1)
		return
	if _seed >= 0:
		print("SEED_USED ", result["seed"])
	var out_path := OS.get_environment("PC_SCENE_OUT")
	if out_path.is_empty():
		out_path = String(TrackBuilderCore.LAYOUTS[_theme]["scene"])
	var uid := ResourceLoader.get_resource_uid(out_path) if FileAccess.file_exists(out_path) else ResourceUID.INVALID_ID
	if uid == ResourceUID.INVALID_ID:
		uid = ResourceUID.create_id()
	var error := ResourceSaver.save(result["scene"] as PackedScene, out_path)
	if error == OK:
		error = ResourceSaver.set_uid(out_path, uid)
	print("SAVE ", error)
	quit(0 if error == OK else 1)
