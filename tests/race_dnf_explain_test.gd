extends SceneTree

class ResultsRace extends "res://scripts/race/prototype_race.gd":
	func _ready() -> void:
		pass


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var race := preload("res://scenes/race/prototype_race.tscn").instantiate()
	race.set_script(ResultsRace)
	race.set_process(false)
	race.set_physics_process(false)
	root.add_child(race)
	var manager := race.get_node("RaceManager") as RaceManager
	var label := Label.new()
	race.add_child(label)
	race.set("_results_label", label)
	race.set("_session", {"mode": "run"})
	var player := VehicleController.new()
	race.set("_player_vehicle", player)
	var opponent := Node2D.new()
	var results: Array = [
		{"vehicle": opponent, "position": 1, "driver_name": "Rival", "vehicle_name": "Car", "time": 62.0, "finished": true, "dnf": false},
		{"vehicle": player, "position": 2, "driver_name": "Rae", "vehicle_name": "Owned car", "time": 70.0, "finished": true, "dnf": true},
	]
	manager.finish_grace_seconds = 8.0
	manager.race_time = 70.0
	race.call("_update_results", results)
	if not _expect(label.text.contains("TIME UP (LIMIT 1:10)") and label.text.contains("2. Rae  ·  Owned car  ·  DNF"), "expired first-finisher grace explains DNF without changing standings"):
		return
	manager.race_time = 65.0
	race.call("_update_results", results)
	if not _expect(label.text.contains("DID NOT FINISH · LIMIT 1:10") and not label.text.contains("TIME UP"), "an unexpired real deadline is shown without inventing a timeout"):
		return
	results[0]["dnf"] = true
	race.call("_update_results", results)
	if not _expect(label.text.contains("DID NOT FINISH") and not label.text.contains("LIMIT"), "DNF without a finisher has no invented deadline"):
		return
	results[0]["dnf"] = false
	manager.race_time = 70.0
	player.free()
	race.call("_update_results", results)
	if not _expect(label.text.contains("CAR WRECKED · LIMIT 1:10") and not label.text.contains("TIME UP"), "race-side destruction takes priority over timeout and retains the deadline"):
		return
	results[1]["dnf"] = false
	race.call("_update_results", results)
	if not _expect(not label.text.contains("CAR WRECKED") and not label.text.contains("DID NOT FINISH"), "a finish does not show a DNF explanation"):
		return
	opponent.free()
	race.free()
	print("RACE_DNF_EXPLAIN_TEST PASS")
	quit(0)


func _expect(ok: bool, message: String) -> bool:
	if not ok:
		push_error("RACE_DNF_EXPLAIN_TEST FAIL: " + message)
		quit(1)
	return ok
