extends SceneTree

const PROTOTYPE_SCENE := preload("res://scenes/race/prototype_race.tscn")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var prototype := PROTOTYPE_SCENE.instantiate()
	root.add_child(prototype)
	current_scene = prototype
	var manager := prototype.get_node("RaceManager") as RaceManager
	var race_hud := prototype.get("_race_hud") as Control
	if not _expect(race_hud.visible, "race telemetry should be visible while driving"):
		return
	prototype.call("_on_lap_completed", manager.laps_to_finish - 1)
	var race_flash := prototype.get("_race_flash_label") as Label
	if not _expect(race_flash.visible and race_flash.text == "FINAL LAP", "the HUD should clearly announce the final lap"):
		return
	prototype.call("_toggle_pause")
	var overlay := prototype.get("_pause_overlay") as Control
	if not _expect(paused and overlay.visible and not manager.is_running, "countdown should pause before the race starts"):
		return
	for frame in 30:
		await process_frame
	if not _expect(not manager.is_running, "pause-aware countdown timers must not advance while paused"):
		return
	prototype.call("_toggle_pause")
	if not _expect(not paused and not overlay.visible, "countdown should resume from the pause menu"):
		return
	var started := [manager.is_running]
	if not started[0]:
		manager.race_started.connect(func() -> void: started[0] = true, CONNECT_ONE_SHOT)
	var timeout_frames := 300
	while not bool(started[0]) and timeout_frames > 0:
		await physics_frame
		timeout_frames -= 1
	if not _expect(bool(started[0]), "prototype race should start before the timeout"):
		return

	prototype.call("_toggle_pause")
	if not _expect(paused and overlay.visible, "the pause action should pause an active race and show the overlay"):
		return
	prototype.call("_toggle_pause")
	if not _expect(not paused and not overlay.visible, "Resume should unpause the tree and hide the overlay"):
		return

	manager.finalize_remaining_racers_as_dnf()
	await process_frame
	if not _expect(not paused and bool(prototype.get("_finished")) and bool(prototype.get("_results_finalized")), "results_ready should enter an unpaused finished state even when the player DNFed"):
		return
	var results_panel := prototype.get("_results_panel") as Control
	if not _expect(results_panel.visible and not race_hud.visible, "final results should replace live race telemetry instead of overlapping it"):
		return
	prototype.call("_toggle_pause")
	if not _expect(not paused and not overlay.visible, "finished results must not be pausable"):
		return

	print("PROTOTYPE_RACE_STATE_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	paused = false
	push_error("PROTOTYPE_RACE_STATE_TEST FAIL: " + message)
	quit(1)
	return false
