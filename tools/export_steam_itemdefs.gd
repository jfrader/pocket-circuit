extends SceneTree

## Writes the Steamworks item definitions for the car drops.
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
	print("ITEMDEFS WRITTEN ", path)
	quit(0)
