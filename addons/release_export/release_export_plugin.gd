@tool
extends EditorExportPlugin

const RACE_SCENE := "res://scenes/race/prototype_race.tscn"
const CACHE_VERSION := "strip-debug-overlay-v1"


func _get_name() -> String:
	return "PocketCircuitReleaseExport"


func _begin_customize_scenes(_platform: EditorExportPlatform, _features: PackedStringArray) -> bool:
	return true


func _get_customization_configuration_hash() -> int:
	return hash(CACHE_VERSION)


func _customize_scene(scene: Node, path: String) -> Node:
	if path != RACE_SCENE:
		return null
	var debug_overlay := scene.get_node_or_null("DebugOverlay")
	if debug_overlay == null:
		return null
	debug_overlay.free()
	return scene
