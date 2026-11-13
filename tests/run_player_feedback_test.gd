extends SceneTree

const UI := preload("res://scripts/ui/run_ui.gd")
const RACE := preload("res://scripts/race/prototype_race.gd")
var _failed := false

class FeedbackRace extends "res://scripts/race/prototype_race.gd":
	func _ready() -> void:
		pass

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var run := RunSession.create(61)
	if not _expect(_fact(UI.stop_facts("race", run, {}), "STOP") == "OPENING RACE", "opening race is labelled"):
		return
	for wear: String in RunState.WEAR_LEVELS:
		if RunState.is_worn_out(wear):
			continue
		for points: int in [0, RunSession.RIVAL_LOSS_POINTS_COST - 1, RunSession.RIVAL_LOSS_POINTS_COST]:
			for tows: int in [0, 1]:
				run = RunSession.create(61)
				for node: Dictionary in run.current_map.nodes.values():
					if node["type"] == "rival":
						run.current_node_id = node["id"]
						break
				run.run_state.set_car_wear(run.current_car_id, wear)
				run.run_points = points
				run.tow_count = tows
				var warning := _fact(UI.stop_facts("rival", run, {}), "RISK")
				var loss := run.resolve_rival(run.current_node_id, false)
				if not _expect(not loss.has("error") and (warning == "A LOSS CAN END THE NIGHT") == run.is_failed(), "duel warning matches actual loss: %s points %d tows %d" % [wear, points, tows]):
					return
	var clock := RACE.DeadlineHUD.new()
	clock.deadline_seconds = 150.0
	clock.elapsed_seconds = 42.0
	if not _expect(clock.clock_copy() == "00:42 / 02:30" and clock.deadline_warning().is_empty(), "HUD names the fixed limit before warning window"):
		return
	clock.elapsed_seconds = 120.0
	if not _expect(clock.deadline_warning() == "30s LEFT", "last thirty seconds are literal and static"):
		return
	clock.elapsed_seconds = 149.1
	if not _expect(clock.deadline_warning() == "1s LEFT", "warning counts down without rounding to zero early"):
		return
	clock.deadline_seconds = INF
	if not _expect(clock.deadline_warning().is_empty(), "unlimited races do not show a deadline warning"):
		return
	clock.free()
	var deadline_race := RACE.new()
	deadline_race.set("_session", {"mode": "strip"})
	deadline_race.set("_strip_prepared", {"strip_time_limit": 150.0})
	if not _expect(float(deadline_race.call("_race_deadline")) == 150.0, "fixed HUD deadline comes from the strip's real limit"):
		return
	deadline_race.set("_session", {"mode": "chase_sprint"})
	if not _expect(is_inf(float(deadline_race.call("_race_deadline"))), "rescue time is not a chase deadline"):
		return
	deadline_race.free()
	var app := root.get_node("App")
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	run = app.call("start_run", 61)
	var rival_id := ""
	for node: Dictionary in run.current_map.nodes.values():
		if node["type"] == "rival":
			rival_id = node["id"]
			break
	if not _expect(not rival_id.is_empty(), "fixture has a rival"):
		return
	run.current_node_id = rival_id
	run.run_points = 2
	run.run_state.set_car_wear(run.current_car_id, "rusty")
	if not _expect(bool(app.call("start_run_rival", rival_id)), "fatal duel starts through the app"):
		return
	var race := preload("res://scenes/race/prototype_race.tscn").instantiate()
	race.set_script(FeedbackRace)
	race.set_process(false)
	race.set_physics_process(false)
	root.add_child(race)
	race.set("_session", app.call("get_current_race_session"))
	var player := VehicleController.new()
	race.set("_player_vehicle", player)
	if not _expect(bool(race.call("_report_result_to_app", [{"vehicle": player, "position": 2, "time": 42.0, "dnf": false}])), "fatal duel result commits through the presenter"):
		return
	var shell := app.get("_shell") as CanvasLayer
	shell.call("show_run_board")
	await process_frame
	var breakdown := shell.find_child("NightBreakdown", true, false) as Label
	var verdict := shell.find_child("NightVerdict", true, false) as Label
	if not _expect(breakdown != null and "WEAR: RUSTY -> DENTED" in breakdown.text and "RIVAL LOSS: -2 POINTS" in breakdown.text and "NO TOW" in breakdown.text and verdict.text == "THE CAR GAVE OUT", "wear-out recap retains the paid points, wear transition, no tow and verdict"):
		return
	player.free()
	race.free()
	print("RUN_PLAYER_FEEDBACK_TEST PASS")
	quit(0)

func _fact(rows: Array, key: String) -> String:
	for row: Array in rows:
		if row[0] == key:
			return row[1]
	return ""

func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	_failed = true
	push_error("RUN_PLAYER_FEEDBACK_TEST FAIL: " + message)
	quit(1)
	return false
