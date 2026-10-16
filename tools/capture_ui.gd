extends SceneTree

## Renders a shell screen to a PNG so UI changes can be reviewed by eye.
## Usage:
##   PC_SHOT_SCREEN=board PC_SHOT_PATH=/tmp/shot.png \
##     xvfb-run -a godot --path . --script res://tools/capture_ui.gd
## Screens: title, garage, garage_won, offer, board, bench, van, lockup, errand,
## discovery, quick_race, quick_strip, settings, driver, map, briefing, ending,
## save_error, loading, hud, results, results_unsaved, night_won, night_lost.
## Optional PC_SHOT_CROP="x,y,w,h" crops the capture for close review.

const RUN_WALK := preload("res://tests/support/run_walk.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
const WALK := {"bench": "bench", "van": "parts_van", "lockup": "lockup", "errand": "errand"}
const SHELL_SCREENS := {
	"quick_race": "show_quick_race", "quick_strip": "show_quick_strip",
	"settings": "show_settings", "driver": "show_driver", "map": "show_map",
	"ending": "show_ending",
}
const RACE_SCREENS := ["hud", "results", "results_unsaved"]
const RACE_READY_TIMEOUT_MSEC := 30000

class FailingSaveStore extends SaveStore:
	func _init(path: String) -> void:
		super(path)

	func save_data(_data: Dictionary) -> bool:
		last_save_error = "Capture fixture: write unavailable"
		return false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var shot := OS.get_environment("PC_SHOT_SCREEN")
	var out := OS.get_environment("PC_SHOT_PATH")
	if out.is_empty():
		_fail("PC_SHOT_PATH is required")
		return
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
	elif SHELL_SCREENS.has(shot):
		shell.call(SHELL_SCREENS[shot])
	elif shot == "briefing":
		shell.call("show_briefing", CATALOG.event_ids()[0])
	elif shot == "save_error":
		shell.call("show_save_error", "PROGRESS NOT SAVED", "The save folder is read-only.", Callable(shell, "show_title"), Callable(shell, "show_title"))
	elif shot == "loading":
		shell.visible = false
		var loading := (load("res://scripts/ui/race_loading_screen.gd") as Script).new() as CanvasLayer
		root.add_child(loading)
		loading.call("set_phase", "Preparing the circuit")
	elif shot in RACE_SCREENS:
		if not await _prepare_race_capture(shot, app, boot):
			return
	elif shot in ["night_won", "night_lost"]:
		var night: RunSession = app.call("start_run", 1806001) as RunSession
		if shot == "night_won":
			for act in RunSession.FINAL_ACT:
				if not RUN_WALK.walk_to(app, night, "act_rival"):
					_fail("act rival is unreachable")
					return
				RUN_WALK.settle(app, night)
		else:
			app.call("abandon_run")
		shell.call("show_run_board")
	elif shot == "discovery":
		shell.call("show_discovery")
	elif shot == "offer":
		var offered := false
		for attempt in 12:
			var night: RunSession = app.call("start_run", 1827000 + attempt * 31) as RunSession
			if RUN_WALK.walk_to(app, night, "rival"):
				RUN_WALK.settle(app, night)
				offered = not night.pending_offer.is_empty()
				break
		if not offered:
			push_error("no duel win to offer")
			quit(1)
			return
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
		if OS.get_environment("PC_SHOT_FRESH") == "1":
			if bool((app.call("get_save_data") as Dictionary).get("run_intro_seen", true)) or app.call("current_run_session") != null:
				_fail("PC_SHOT_FRESH requires a new profile without an active run")
				return
			shell.call("_on_art_action", &"new_run")
		else:
			app.call("start_run", 424242)
			shell.call("show_run_board")
	elif WALK.has(shot):
		var target := String(WALK[shot])
		var found := false
		var sess: RunSession = null
		for attempt in 6:
			sess = app.call("start_run", 900100 + attempt) as RunSession
			found = RUN_WALK.walk_to(app, sess, target)
			if found:
				break
		if not found:
			push_error("no " + target + " found")
			quit(1)
			return
		# Full screens: points to spend at the van, a pile of parts at the bench.
		sess.run_points = 20
		if shot == "bench":
			sess.parts_held = RunParts.deal(sess.run_seed, sess.car_stats(sess.current_car_id))
		shell.call("show_run_" + ("parts_van" if shot == "van" else shot))
	else:
		_fail("unknown screen: " + shot)
		return
	# Let entrance motion finish before the shot.
	await create_timer(1.0).timeout
	var img := root.get_texture().get_image()
	var crop := OS.get_environment("PC_SHOT_CROP")
	if not crop.is_empty():
		var parts := crop.split(",")
		if parts.size() == 4:
			img = img.get_region(Rect2i(int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3])))
	if img.save_png(out) != OK:
		_fail("could not write " + out)
		return
	print("CAPTURED ", out)
	quit(0)


func _prepare_race_capture(shot: String, app: Node, boot: Node) -> bool:
	var night: RunSession = app.call("start_run", 1806001) as RunSession
	if not bool(app.call("start_run_race", night.current_node_id)):
		_fail("opening race refused")
		return false
	root.remove_child(boot)
	boot.queue_free()
	var race := (load("res://scenes/race/prototype_race.tscn") as PackedScene).instantiate()
	root.add_child(race)
	current_scene = race
	var manager := race.get("race_manager") as Node
	var deadline := Time.get_ticks_msec() + RACE_READY_TIMEOUT_MSEC
	while not bool(manager.get("is_running")) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not bool(manager.get("is_running")):
		_fail("race did not reach its started state")
		return false
	if shot != "hud":
		if shot == "results_unsaved":
			var store: SaveStore = app.get("_save_store") as SaveStore
			app.set("_save_store", FailingSaveStore.new(store.save_path))
		var player := race.get("_player_vehicle") as Node2D
		var state: Dictionary = manager.call("get_racer_state", player)
		manager.call("_finish_racer", player, state)
		manager.call("finalize_remaining_racers_as_dnf")
		await process_frame
		if not bool(race.get("_results_finalized")):
			_fail("results did not finalize")
			return false
	return true


func _fail(message: String) -> void:
	push_error("CAPTURE_UI FAIL: " + message)
	quit(1)
