extends SceneTree
## Refresh only a saved track's materials, preserving authored geometry and UID.
## PC_SCENE_OUT=res://scenes/tracks/example.tscn godot --headless --path . --script res://tools/update_track_materials.gd

const MATERIALS := preload("res://scripts/race/household_surface_materials.gd")
const WORLD_MATERIALS := preload("res://scripts/race/generated_world_materials.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := OS.get_environment("PC_SCENE_OUT")
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("PC_SCENE_OUT must name an existing saved track")
		quit(1)
		return
	var uid := ResourceLoader.get_resource_uid(path)
	var track := (load(path) as PackedScene).instantiate() as Node2D
	var identity: Dictionary = track.get_meta("surface_identity")
	var theme := StringName(identity["theme"])
	var seed_value := int(identity["seed"])
	var world := WORLD_MATERIALS.resolve(theme, &"", seed_value, identity["family"], identity["palette"])
	var resolved := MATERIALS.resolve(theme, seed_value, identity["family"], identity["palette"], world["floor_modulate"])
	for obsolete: String in ["CourseConstruction", "TrackRibbon"]:
		var decoration := track.get_node_or_null(obsolete)
		if decoration:
			track.remove_child(decoration)
			decoration.free()
	MATERIALS.apply(track, resolved)
	var packed := PackedScene.new()
	var error := packed.pack(track)
	if error == OK:
		error = ResourceSaver.save(packed, path)
	if error == OK:
		error = ResourceSaver.set_uid(path, uid)
	track.free()
	print("MATERIAL_UPDATE ", error)
	quit(0 if error == OK else 1)
