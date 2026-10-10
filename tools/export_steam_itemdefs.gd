extends SceneTree

## Writes the Steamworks item definitions for the car drops, and beside them
## (<path>.tags.txt) the English string for every tag category and value,
## which Steam needs before it applies a tag.
## Usage:
##   PC_STEAM_APP_ID=<app id> PC_ITEMDEFS_PATH=/tmp/itemdefs.json \
##     godot --headless --path . --script res://tools/export_steam_itemdefs.gd
## Upload the file in Steamworks: Inventory Service → Item Definitions.

func _initialize() -> void:
	var app_id := int(OS.get_environment("PC_STEAM_APP_ID"))
	var path := OS.get_environment("PC_ITEMDEFS_PATH")
	if app_id <= 0 or path.is_empty():
		push_error("set PC_STEAM_APP_ID and PC_ITEMDEFS_PATH")
		quit(1)
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s" % path)
		quit(1)
		return
	file.store_string(JSON.stringify(SteamCars.itemdefs(app_id), "\t"))
	file.close()
	var labels := FileAccess.open(path + ".tags.txt", FileAccess.WRITE)
	if labels == null:
		push_error("cannot write %s.tags.txt" % path)
		quit(1)
		return
	var tags := SteamCars.tag_labels()
	for category: String in tags:
		labels.store_line("%s = %s" % [category, tags[category]["name"]])
		for token: String in tags[category]["values"]:
			labels.store_line("%s:%s = %s" % [category, token, tags[category]["values"][token]])
	labels.close()
	print("ITEMDEFS WRITTEN ", path)
	quit(0)
