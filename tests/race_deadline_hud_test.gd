extends SceneTree

const PROTOTYPE := preload("res://scenes/race/prototype_race.tscn")
const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const CAMERA := preload("res://scripts/camera/follow_camera.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var race := PROTOTYPE.instantiate()
	race.set("_session", {"event": {"theme": &"kitchen", "circuit": "generated", "room": &"classic", "seed": 42}})
	root.add_child(race)
	current_scene = race
	var manager := race.get_node("RaceManager") as RaceManager
	var hud: Control = race.get("_race_hud")
	var player: Node2D = race.get("_player_vehicle")
	manager.set_physics_process(false)
	manager.race_time = 0.0
	race.call("_update_race_hud")
	if not _expect(hud.call("clock_copy") == "00:00.0" and hud.call("finish_countdown_copy") == "", "elapsed time must be visible before anyone finishes, without an invented deadline"):
		return
	manager.race_time = 52.0
	var opponent: Node2D = manager.get_rankings().filter(func(racer: Node2D) -> bool: return racer != player)[0]
	var first := manager.get_racer_state_ref(opponent)
	first["elapsed"] = manager.race_time
	manager.call("_finish_racer", opponent, first)
	race.call("_update_race_hud")
	var deadline := 52.0 + manager.finish_grace_seconds
	if not _expect(hud.call("clock_copy") == "00:52.0" and hud.call("finish_countdown_copy") == "FINISH IN %ds" % ceili(manager.finish_grace_seconds), "first finisher must start the real grace countdown while preserving elapsed time"):
		return
	if not _expect(hud.call("deadline_warning") == "", "the full grace period must not already carry a low-time warning"):
		return
	manager.race_time = deadline - 2.1
	race.call("_update_race_hud")
	if not _expect(hud.call("finish_countdown_copy") == "FINISH IN 3s" and hud.call("deadline_warning") == "3s LEFT", "countdown must decrease and warn in the final three seconds"):
		return
	manager.race_time = deadline
	var player_state := manager.get_racer_state_ref(player)
	player_state["dnf"] = true
	player_state["finished"] = true
	var expected_limit := "%d:%02d" % [int(deadline) / 60, int(deadline) % 60]
	if not _expect(race.call("_player_dnf_explanation", manager.get_results()) == "TIME UP (LIMIT %s)" % expected_limit, "results must retain TIME UP with the actual first-finish-plus-grace limit"):
		return
	hud.set("finish_grace_countdown", false)
	hud.set("elapsed_seconds", 10.0)
	hud.set("deadline_seconds", 45.0)
	if not _expect(hud.call("clock_copy") == "00:10 / 00:45" and hud.call("finish_countdown_copy") == "", "fixed strip deadlines must keep their elapsed/limit display"):
		return
	var camera := race.get_node("FollowCamera2D") as Camera2D
	var bounds: Rect2 = (race.get("track_root") as Node).get_meta("room_bounds")
	if not _expect(camera.limit_left == floori(bounds.position.x) and camera.limit_right == ceili(bounds.end.x) and camera.limit_top == floori(bounds.position.y) and camera.limit_bottom == ceili(bounds.end.y), "race camera must retain its room bounds"):
		return
	current_scene = null
	root.remove_child(race)
	race.free()
	await process_frame
	# The dark overscan void around the room is deliberate presentation
	# (generated_track_composition_test pins it); the HUD is this test's concern.
	print("RACE_DEADLINE_HUD_TEST PASS elapsed_first_finish_countdown_warning_time_up")
	quit(0)


func _expect(ok: bool, message: String) -> bool:
	if not ok:
		push_error("RACE_DEADLINE_HUD_TEST FAIL: " + message)
		quit(1)
	return ok
