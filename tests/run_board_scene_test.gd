extends SceneTree

const SCENE := preload("res://scripts/ui/run_board_scene.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const RUN_WALK := preload("res://tests/support/run_walk.gd")
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
	if not _expect(bool(app.call("update_setting", "reduced_motion", false)), "material-motion fixture enables ambient motion"):
		return
	var session: RunSession = app.call("start_run", 2426001)
	var surfaces: Array[String] = []
	for act: int in SCENE.ROOM_NAMES:
		session.current_map.act = act
		shell.call("show_run_board")
		await process_frame
		await process_frame
		var table := shell.find_child("RunTabletop", true, false) as Control
		if not _expect(table != null and table.get("act") == act, "the tabletop follows the act"):
			return
		if not _expect(table.get_node_or_null("Lamplight") != null, "the table has its warm-to-night light layer"):
			return
		var dressing := table.get_node("RoomDressing")
		if not _expect(dressing.get_child_count() == 18, "table dressing uses a bounded seeded set of painted props"):
			return
		for prop: Node in dressing.get_children():
			if not _expect(MATERIALS.ROOM_DRESSING[act].has((prop as TextureRect).texture), "painted crumbs and debris belong to the current room"):
				return
		if not _expect(table.get_node("BeamDust").get_child_count() == 3 and table.get("_lamp_pulse") != null, "lamp beam has three restrained motes and a warmth pulse"):
			return
		for mote: Node in table.get_node("BeamDust").get_children():
			if not _expect((mote as TextureRect).size.x <= 8 and (mote as TextureRect).size.y <= 8, "painted dust remains tiny rather than inheriting the source texture's minimum size"):
				return
		if not _expect(MATERIALS.chalk_brush() == MATERIALS.chalk_brush() and MATERIALS.chalk_brush().get_image().get_format() == Image.FORMAT_RGBA8, "chalk breakup is baked once with real alpha"):
			return
		var surface: Texture2D = SCENE.SURFACES[act]
		if not _expect(not surfaces.has(surface.resource_path), "each room uses a distinct existing material"):
			return
		surfaces.append(surface.resource_path)
		var board := shell.find_child("RunBoard", true, false) as Control
		var token := board.get_node("CarToken") as TextureRect
		if not _expect(token.texture == IDENTITIES.car_texture(session.current_car_id), "the parked player car uses the identity library"):
			return
		var marker: Button = board.call("marker", session.current_node_id)
		var detail := shell.find_child("RunDetail", true, false) as Control
		var inset := detail.get_node("ChalkboardInset") as MarginContainer
		for edge: String in ["left", "right", "top", "bottom"]:
			if not _expect(inset.get_theme_constant("margin_" + edge) == SCENE.CHALK_PADDING, "chalkboard content has consistent inner padding"):
				return
		var toy := marker.get_node_or_null("ToyToken") as Control
		if not _expect(toy != null and toy.mouse_filter == Control.MOUSE_FILTER_IGNORE, "physical toys leave input on the existing marker"):
			return
		toy.set("reduced_motion", true)
		toy.call("set_selected", true)
		if not _expect(is_zero_approx(float(toy.get("lift"))), "reduced motion selects without token lift"):
			return
		toy.set("reduced_motion", false)
		toy.call("set_selected", true)
		await create_timer(0.4).timeout
		if not _expect(float(toy.get("lift")) > 2.9 and table.modulate.a > 0.99, "arrival fades in and selection lifts the toy"):
			return
		if not _expect(shell.find_children("RunTabletop", "Control", true, false).size() == 1, "reopening replaces rather than stacks scenery"):
			return
		shell.call("show_title")
		await process_frame
		if not _expect(shell.find_child("RunTabletop", true, false) == null, "tabletop scenery does not leak onto other screens"):
			return
	if not _expect(bool(app.call("update_setting", "reduced_motion", true)), "reduced-motion setting is persisted for shell presentation"):
		return
	var victory: RunSession = app.call("start_run", 71717)
	for act in RunSession.FINAL_ACT:
		if not _expect(RUN_WALK.walk_to(app, victory, "act_rival"), "victory fixture reaches each act rival"):
			return
		RUN_WALK.settle(app, victory)
	shell.call("show_run_board")
	await process_frame
	await process_frame
	if not await _expect_ending(shell, &"night_won", "WinnerCar", SCENE.SUNRISE):
		return
	app.call("start_run", 72727)
	app.call("abandon_run")
	shell.call("show_run_board")
	await process_frame
	await process_frame
	if not await _expect_ending(shell, &"night_lost", "SolitaryCar", SCENE.MOONLIGHT):
		return
	var victory_light := SCENE.new()
	victory_light.scene_mode = &"night_won"
	victory_light.act = 3
	victory_light.size = Vector2(1280, 720)
	root.add_child(victory_light)
	if not _expect(victory_light.get_node("RoomDressing").get_child_count() == 0, "victory removes bright static debris rather than presenting it as confetti"):
		return
	var dust := victory_light.get_node("BeamDust")
	if not _expect(dust.get_child_count() == 3, "victory keeps only three sparse light motes"):
		return
	for child: Node in dust.get_children():
		var mote := child as TextureRect
		var mask := mote.material as ShaderMaterial
		var start: Vector2 = mote.get_meta("beam_start")
		var end: Vector2 = mote.get_meta("beam_end")
		if not _expect(mote.texture == MATERIALS.SHADOW_CIRCLE and mote.size.x <= 4 and (mote.modulate.a < 0.14 or is_equal_approx(mote.modulate.a, 0.14)) and bool(mask.get_shader_parameter("sunrise")), "victory uses tiny low-opacity painted motes with the sunlight mask (size=%s alpha=%s sunrise=%s)" % [mote.size, mote.modulate.a, mask.get_shader_parameter("sunrise")]):
			return
		if not _expect(MATERIALS.beam_strength(start / victory_light.size, true) > 0.7 and MATERIALS.beam_strength(end / victory_light.size, true) > 0.7, "mote drift stays inside a sun beam and is masked away from dark zones"):
			return
	root.remove_child(victory_light)
	victory_light.queue_free()
	print("RUN_BOARD_SCENE_TEST PASS rooms=3 endings=2 route=hidden shadow=single reduced_motion=fade_only")
	quit(0)


func _expect_ending(shell: CanvasLayer, mode: StringName, hero_name: String, tint: Color) -> bool:
	var table := shell.find_child("RunTabletop", true, false) as Control
	var board := shell.find_child("RunBoard", true, false) as Control
	if not _expect(table.get("scene_mode") == mode and table.get("lighting_tint") == tint, "ending selects its sunrise or moonlit palette"):
		return false
	if not _expect(not bool(board.get("route_visuals_visible")) and board.is_visible_in_tree(), "terminal retains its map node and layout but disables route drawing"):
		return false
	for visual: Node in board.get_children():
		if visual is CanvasItem and not _expect(not (visual as CanvasItem).is_visible_in_tree(), "terminal hides every marker, token and act header"):
			return false
	var legend := shell.find_child("RunLegend", true, false) as Control
	if not _expect(legend != null and not legend.is_visible_in_tree(), "terminal legend is hidden, not faded"):
		return false
	var hero := table.get_node_or_null(hero_name) as TextureRect
	if not _expect(hero != null and hero.size.y >= 220, "ending retains its large hero car"):
		return false
	if not _expect(MATERIALS.HERO_PIXEL_SCALE > 2 and hero.texture.get_width() == 48 * MATERIALS.HERO_PIXEL_SCALE, "terminal hero uses the high-resolution native renderer"):
		return false
	var shadow := table.get_node_or_null("HeroShadow") as TextureRect
	if not _expect(shadow != null and shadow.texture == MATERIALS.SHADOW_CIRCLE and shadow.get_child_count() == 0 and shadow.draw.get_connections().is_empty(), "hero shadow is one painted soft texture, without stacked custom primitives"):
		return false
	if not _expect(shadow.modulate.r < 0.1 and shadow.modulate.a > 0.3, "white-alpha shadow artwork is tinted dark at runtime"):
		return false
	if not _expect(table.get_node("BeamDust").get_child_count() == 0 and table.get("_lamp_pulse") == null, "reduced motion disables all motes and lamp pulses"):
		return false
	var resting_position := hero.position
	await create_timer(0.4).timeout
	return _expect(hero.position == resting_position and table.modulate.a > 0.99 and bool(table.get("reduced_motion")), "reduced-motion ending crossfades without moving its hero")


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("RUN_BOARD_SCENE_TEST FAIL: " + message)
		quit(1)
	return condition
