extends SceneTree

const SCENE := preload("res://scripts/ui/run_board_scene.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const RUN_WALK := preload("res://tests/support/run_walk.gd")


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
	var shadow := table.get_node_or_null("HeroShadow") as TextureRect
	if not _expect(shadow != null and shadow.texture is GradientTexture2D and shadow.get_child_count() == 0 and shadow.draw.get_connections().is_empty(), "hero shadow is one built-in texture draw, without stacked custom primitives"):
		return false
	var gradient := shadow.texture as GradientTexture2D
	if not _expect(gradient.fill == GradientTexture2D.FILL_RADIAL and is_zero_approx(gradient.gradient.get_color(2).a), "single ellipse falls off smoothly to transparency"):
		return false
	var resting_position := hero.position
	await create_timer(0.4).timeout
	return _expect(hero.position == resting_position and table.modulate.a > 0.99 and bool(table.get("reduced_motion")), "reduced-motion ending crossfades without moving its hero")


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("RUN_BOARD_SCENE_TEST FAIL: " + message)
		quit(1)
	return condition
