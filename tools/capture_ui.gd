extends SceneTree

## Renders a shell screen to a PNG so UI changes can be reviewed by eye.
## Usage:
##   PC_SHOT_SCREEN=board PC_SHOT_PATH=/tmp/shot.png \
##     xvfb-run -a godot --path . --script res://tools/capture_ui.gd
## Screens: title, garage, garage_won, offer, board, bench, van, lockup, errand, discovery.
## Optional PC_SHOT_CROP="x,y,w,h" crops the capture for close review.

const RUN_WALK := preload("res://tests/support/run_walk.gd")
const WALK := {"bench": "bench", "van": "parts_van", "lockup": "lockup", "errand": "errand"}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var shot := OS.get_environment("PC_SHOT_SCREEN")
	var out := OS.get_environment("PC_SHOT_PATH")
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for i in 8:
		await process_frame
	var app := root.get_node_or_null("App")
	var shell := app.get("_shell") as CanvasLayer
	if shell == null:
		push_error("no shell")
		quit(1)
		return
	if shot == "title":
		shell.call("show_title")
	elif shot == "discovery":
		shell.call("show_discovery")
	elif shot == "offer":
		for attempt in 12:
			var night: RunSession = app.call("start_run", 1827000 + attempt * 31) as RunSession
			if RUN_WALK.walk_to(app, night, "rival"):
				RUN_WALK.settle(app, night)
				break
		shell.call("show_run_board")
	elif shot == "garage":
		shell.call("show_vehicle_select", "", true)
	elif shot == "garage_won":
		# Win a duel on a few nights and abandon each, so the garage holds won cars.
		for attempt in 12:
			var night: RunSession = app.call("start_run", 1741000 + attempt * 31) as RunSession
			if RUN_WALK.walk_to(app, night, "rival"):
				RUN_WALK.settle(app, night)
			app.call("abandon_run")
		shell.call("show_vehicle_select", "", true)
		for i in 4:
			await process_frame
		var won: Array[String] = app.call("garage_car_ids")
		var menu := shell.get("_art_menu") as Control
		var focus_id := OS.get_environment("PC_SHOT_CAR")
		((menu.get("_vehicle_buttons") as Dictionary)[focus_id if not focus_id.is_empty() else won[won.size() - 1]] as Button).grab_focus()
	elif shot == "board":
		app.call("start_run", 424242)
		shell.call("show_run_board")
	elif WALK.has(shot):
		var target := String(WALK[shot])
		var found := false
		for attempt in 6:
			var sess: RunSession = app.call("start_run", 900100 + attempt) as RunSession
			found = RUN_WALK.walk_to(app, sess, target)
			if found:
				break
		if not found:
			push_error("no " + target + " found")
			quit(1)
			return
		shell.call("show_run_" + ("parts_van" if shot == "van" else shot))
	for i in 8:
		await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	var crop := OS.get_environment("PC_SHOT_CROP")
	if not crop.is_empty():
		var parts := crop.split(",")
		if parts.size() == 4:
			img = img.get_region(Rect2i(int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3])))
	img.save_png(out)
	print("CAPTURED ", out)
	quit(0)
