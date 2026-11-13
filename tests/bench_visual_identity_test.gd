extends SceneTree

const WALK := preload("res://tests/support/run_walk.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const BENCH := preload("res://scripts/ui/run_bench_scene.gd")
const BOARD := preload("res://scripts/ui/run_board_scene.gd")
const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var boot := (preload("res://scenes/boot/boot.tscn") as PackedScene).instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	var app := root.get_node("App")
	var shell := app.get("_shell") as CanvasLayer
	for reduced: bool in [false, true]:
		app.call("update_setting", "reduced_motion", reduced)
		var session: RunSession
		for attempt in 12:
			session = app.call("start_run", 2426100 + attempt)
			if WALK.walk_to(app, session, "bench"):
				break
		if not _expect(session.current_node().get("type") == "bench", "fixture reaches a bench"):
			return
		session.run_state.set_car_wear(session.current_car_id, "dented")
		session.parts_held.clear()
		var spare := session._add_car("visual-spare", RunSession.CAR_ORIGIN_LOCKUP, RunSession.STARTER_TYPES)
		session.boot_cars[spare] = {}
		app.call("_install_held_vehicles")
		shell.call("show_run_bench")
		for frame in 4:
			await process_frame
		var car := shell.find_child("BenchCar", true, false) as TextureRect
		var expected := IDENTITIES.car_texture_with_wear(session.current_car_id, "dented", MATERIALS.HERO_PIXEL_SCALE, int(BENCH.CAR_LENGTH))
		if not _expect(car != null and car.texture == expected, "bench renders current generated car and actual wear in both motion modes"):
			return
		var sheet := shell.find_child("BenchParts", true, false) as Control
		var note := sheet.get_child(0).get_child(0) as Label
		var repair := shell.find_child("BenchRepair", true, false) as Button
		if not _expect(note.text == "NO PARTS HELD - A PARTS VAN SELLS THEM" and sheet.size.y < 100 and repair.size.y >= 64 and repair.get_theme_font_size("font_size") >= 20, "empty parts sheet becomes a compact note with prominent actions"):
			return
		for action_name: String in ["BenchBankHaul", "BenchSwap"]:
			var action := shell.find_child(action_name, true, false) as Button
			if not _expect(action != null and not action.disabled and action.size.y >= 64 and action.get_global_rect().end.y <= root.get_visible_rect().end.y, "empty bench promotes available bank and swap actions within the viewport"):
				return
		(shell.find_child("BenchSwap", true, false) as Button).pressed.emit()
		await process_frame
		if not _expect(not sheet.visible and (shell.find_child("ActionBack", true, false) as Button).is_visible_in_tree(), "swap choices do not hide the bench navigation"):
			return
		(shell.find_child("BenchSwap", true, false) as Button).pressed.emit()
		repair.pressed.emit()
		await create_timer(BENCH.CONFIRM_TIME + 0.15).timeout
		var acknowledgement := shell.find_child("BenchRepairAcknowledgement", true, false) as Label
		if not _expect(acknowledgement != null and acknowledgement.text == "REPAIRED - DENTED -> CLEAN" and shell.get("_screen") == "run_board", "board retains exact repair transition without extending confirmation"):
			return
		session.current_car_id = spare
		shell.call("show_run_bench")
		var swapped := shell.find_child("BenchCar", true, false) as TextureRect
		if not _expect(swapped.texture != expected and swapped.texture == IDENTITIES.car_texture_with_wear(spare, "clean", MATERIALS.HERO_PIXEL_SCALE, int(BENCH.CAR_LENGTH)), "reopening after a car change does not reuse the previous car hero"):
			return
		session.run_state.set_car_wear(session.current_car_id, "rusty")
		for won: bool in [false, true]:
			session.failed = not won
			session.completed = won
			shell.call("show_run_board")
			var recap := shell.find_child("WinnerCar" if won else "SolitaryCar", true, false) as TextureRect
			var mode := &"night_won" if won else &"night_lost"
			if not _expect(recap != null and recap.texture == IDENTITIES.car_texture_with_wear(session.current_car_id, "rusty", MATERIALS.HERO_PIXEL_SCALE, int(BOARD.HERO_LENGTH[mode])), "both terminal recaps render the current car and wear in both motion modes"):
				return
	print("BENCH_VISUAL_IDENTITY_TEST PASS bench=current_car recap=current_car wear=actual motion=both empty=compact repair=exact_transition")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("BENCH_VISUAL_IDENTITY_TEST FAIL: " + message)
		quit(1)
	return condition
