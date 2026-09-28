extends SceneTree

const PROTOTYPE_SCENE := preload("res://scenes/race/prototype_race.tscn")


class FakeAudioDirector extends Node:
	var calls: Array[String] = []

	func cue_live_section(section: String) -> bool:
		calls.append("cue:%s" % section)
		return true

	func cue_live_section_timed(section: String, _hold_seconds: float) -> bool:
		calls.append("timed:%s" % section)
		return true

	func begin_live_rotation(_deck: Array[String], _dwell: float, _first: String = "") -> void:
		calls.append("begin")

	func advance_live_rotation() -> void:
		calls.append("advance")

	func stop_live_rotation() -> void:
		calls.append("stop")


func _initialize() -> void:
	var app := root.get_node("App")
	var prototype := PROTOTYPE_SCENE.instantiate()
	root.add_child(prototype)
	current_scene = prototype
	await process_frame
	var original_director: Node = app.get("audio_director") as Node
	var fake := FakeAudioDirector.new()
	app.add_child(fake)
	app.set("audio_director", fake)
	var manager := prototype.get("race_manager") as RaceManager
	var player := prototype.get("_player_vehicle") as Node2D
	prototype.set("_countdown_active", false)

	fake.calls.clear()
	manager.lap_count = 0
	prototype.call("_on_position_changed", player, 2, 4)
	prototype.call("_on_racer_recovered", player)
	prototype.call("_on_wrong_way_changed", player, true)
	if not _expect(fake.calls.is_empty(), "position, recovery, and wrong-way cues must not escape during lap one"):
		return

	manager.laps_to_finish = 3
	prototype.call("_on_lap_completed", 1)
	if not _expect(fake.calls == ["begin"], "lap one should start the adaptive race rotation; got %s" % [fake.calls]):
		return

	fake.calls.clear()
	manager.lap_count = 1
	prototype.call("_on_position_changed", player, 2, 4)
	prototype.call("_on_racer_recovered", player)
	prototype.call("_on_wrong_way_changed", player, true)
	if not _expect(fake.calls == ["advance", "timed:recovery", "timed:wrong-way"], "adaptive cues should resume after lap one"):
		return

	fake.calls.clear()
	manager.laps_to_finish = 1
	prototype.call("_on_lap_completed", 1)
	if not _expect(fake.calls.is_empty(), "a one-lap race must stay on Starting Grid until the finish cue"):
		return

	app.set("audio_director", original_director)
	print("OPENING_LAP_MUSIC_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("OPENING_LAP_MUSIC_TEST FAIL: " + message)
	quit(1)
	return false
