extends SceneTree

const RUN_WALK := preload("res://tests/support/run_walk.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const BENCH := preload("res://scripts/ui/run_bench_scene.gd")
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
	if not _expect(bool(app.call("update_setting", "reduced_motion", false)), "motion fixture setting persists"):
		return
	for kind: StringName in [&"repair", &"fit", &"crossfade"]:
		if kind == &"crossfade":
			if not _expect(bool(app.call("update_setting", "reduced_motion", true)), "reduced motion setting persists"):
				return
		var session := _find_bench(app)
		if not _expect(session != null, "fixture reaches an unused bench"):
			return
		session.run_state.set_car_wear(session.current_car_id, "rusty")
		session.parts_held = RunParts.deal(session.run_seed, session.car_stats(session.current_car_id))
		var held_count := session.parts_held.size()
		shell.call("show_run_bench")
		for frame in 4:
			await process_frame
		var scene := shell.find_child("RunBenchScene", true, false) as Control
		if not _expect(scene != null and scene.get_node_or_null("RepairMat") != null and scene.get_node_or_null("BenchTabletop") != null, "bench stages a rubber mat on the act tabletop"):
			return
		var car := scene.get_node("BenchCar") as TextureRect
		if not _expect(car.texture == MATERIALS.hero_texture(session.current_car_id), "bench car reuses the hero cache for its identity payload"):
			return
		if not _expect(MATERIALS.HERO_PIXEL_SCALE > 2 and car.texture.get_width() == 48 * MATERIALS.HERO_PIXEL_SCALE and IDENTITIES.car_texture(session.current_car_id).get_width() == 96, "hero uses native high-resolution rasterization while small car sprites stay unchanged"):
			return
		if not _expect((scene.get_node("PaintedWrench") as TextureRect).texture == MATERIALS.WRENCH and (scene.get_node("BenchCarShadow") as TextureRect).texture == MATERIALS.SHADOW_CIRCLE, "bench uses the painted wrench and a tinted painted car shadow"):
			return
		var repair := shell.find_child("BenchRepair", true, false) as Button
		var fit := shell.find_child("BenchFit_0", true, false) as Button
		var back := shell.find_child("ActionBack", true, false) as Button
		var title := fit.get_child(0).get_child(0) as Label
		if not _expect(title.get_theme_font("font") == ThemeDB.fallback_font, "part title typography uses the proportional fallback font"):
			return
		if not _expect(repair.text == "REPAIR" and back.text == "BACK" and fit.get_child(0).get_child(0).text == "FIT " + RunParts.part_name(session.parts_held[0]).to_upper(), "physical actions preserve their names and copy"):
			return
		if not _expect(root.gui_get_focus_owner() == repair, "repair remains the first focused action"):
			return
		var button := fit if kind == &"fit" else repair
		button.pressed.emit()
		if not _expect(session.bench_action_done and scene.get("confirmation_state") == kind, "domain action applies immediately while its presentation confirms"):
			return
		if kind == &"fit" and not _expect(session.parts_held.size() == held_count - 1, "fitting consumes exactly the selected held part"):
			return
		await create_timer(0.07).timeout
		var moving := scene.get_node("FittingPart") as Control
		if kind == &"crossfade":
			if not _expect(button.scale == Vector2.ONE and is_zero_approx(float(scene.get("stamp_depth"))) and not moving.visible, "reduced motion crossfades without stamp or part travel"):
				return
		else:
			if not _expect(button.scale.x < 1.0 and float(scene.get("stamp_depth")) > 0.0, "repair and fit physically stamp the button"):
				return
			var style := button.get_theme_stylebox("disabled") as StyleBoxFlat
			if not _expect(style.shadow_offset.y < 5.0, "stamp compresses the contact shadow"):
				return
			if kind == &"fit" and not _expect(moving.visible and moving.get_index() < car.get_index(), "selected blister slides beneath the car shell"):
				return
		await create_timer(BENCH.CONFIRM_TIME + 0.1).timeout
		if not _expect(shell.get("_screen") == "run_board", "confirmation returns to the board"):
			return
	print("RUN_BENCH_SCENE_TEST PASS mat=present car=identity repair=stamp fit=slide reduced_motion=fade_only")
	quit(0)


func _find_bench(app: Node) -> RunSession:
	for attempt in 12:
		var session: RunSession = app.call("start_run", 2426100 + attempt)
		if RUN_WALK.walk_to(app, session, "bench"):
			return session
	return null


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("RUN_BENCH_SCENE_TEST FAIL: " + message)
		quit(1)
	return condition
