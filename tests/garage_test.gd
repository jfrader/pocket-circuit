extends SceneTree

## GURI-1741 (Run rewards and Quick Race as the garage): Quick Race shows the
## shipped cars and every won car on one shelf grouped by type; a won car tells
## where it came from and its six-axis shape is drawn against the car the
## player came in with.

const CATALOG := preload("res://data/championship/catalog.gd")
const RUN_WALK := preload("res://tests/support/run_walk.gd")

var _failed := false


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	var shell := app.get("_shell") as CanvasLayer
	var won_id := ""
	for attempt in 12:
		var night: RunSession = app.call("start_run", 1741000 + attempt * 31) as RunSession
		if RUN_WALK.walk_to(app, night, "rival"):
			RUN_WALK.settle(app, night)
			won_id = String(night.won_cars()[0]["id"])
			app.call("abandon_run")
			break
		app.call("abandon_run")
	if not _expect(not won_id.is_empty() and won_id in (app.call("garage_car_ids") as Array), "an abandoned night still banks its won car"):
		return

	shell.call("show_vehicle_select", "", true)
	for frame in 4:
		await process_frame
	var menu := shell.get("_art_menu") as Control
	var buttons: Dictionary = menu.get("_vehicle_buttons")
	var roster: Array = app.call("quick_race_roster")
	if not _expect(buttons.size() == roster.size() and buttons.has(won_id) and not (buttons[won_id] as Button).disabled, "the shelf holds every shipped and won car, the won one enabled"):
		return
	var last_type := -1
	var last_x := -INF
	for id: String in roster:
		var button := buttons[id] as Button
		var type_index := ProceduralCarGenerator.SUPPORTED_TYPES.find(String(CATALOG.get_vehicle(id)["car_art"]["type"]))
		if not _expect(type_index >= last_type and button.position.x > last_x, "the shelf runs left to right grouped by type"):
			return
		last_type = type_index
		last_x = button.position.x

	var stage := menu.get("_stage") as Control
	var origin := menu.find_child("GarageOrigin", true, false) as Label
	(buttons[won_id] as Button).grab_focus()
	await process_frame
	if not _expect(String(menu.get("selected_vehicle_id")) == won_id, "focusing a won car selects it"):
		return
	if not _expect(origin.visible and origin.text.begins_with("WON IN A DUEL"), "a won car says where it came from"):
		return
	if not _expect(String(stage.get("compare_label")) == "VS RUSTBUG" and not (stage.get("compare_shape") as Dictionary).is_empty(), "a won car is drawn against the car the player came in with"):
		return
	var shape: Dictionary = stage.get("shape")
	if not _expect(shape.keys() == CarProfile.AXES, "the shape has the six axes"):
		return
	for axis: String in CarProfile.AXES:
		if not _expect(float(shape[axis]) >= 0.0 and float(shape[axis]) <= 1.0, "%s sits inside the shape" % axis):
			return

	(buttons["rustbug"] as Button).grab_focus()
	await process_frame
	if not _expect(not origin.visible and String(stage.get("compare_label")) == "YOUR CAR" and (stage.get("compare_shape") as Dictionary).is_empty(), "the car the player holds is drawn alone"):
		return

	var scroll := menu.find_child("ShelfScroll", true, false) as ScrollContainer
	var bar := scroll.get_h_scroll_bar()
	var after := menu.find_child("ShelfMoreAfter", true, false) as Control
	if not _expect(after.visible == (bar.value + bar.page < bar.max_value - 0.5), "the MORE cue matches what the shelf hides"):
		return

	if _failed:
		return
	print("GARAGE_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error("GARAGE_TEST FAIL: " + message)
		quit(1)
	return condition
