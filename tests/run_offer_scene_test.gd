extends SceneTree

const WALK := preload("res://tests/support/run_walk.gd")
const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")
const SCENE := preload("res://scripts/ui/run_offer_scene.gd")
const UI := preload("res://scripts/ui/run_ui.gd")


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
		if not _expect(bool(app.call("update_setting", "reduced_motion", reduced)), "motion fixture persists"):
			return
		var session := _offer(app)
		if not _expect(session != null, "fixture wins a car"):
			return
		var original := session.current_car_id
		var won := session.pending_offer
		shell.call("show_run_board")
		var scene := shell.find_child("RunOfferScene", true, false) as Control
		if not _expect(scene != null and scene.get_node_or_null("OfferTurntable") != null and scene.get_node_or_null("OfferLamp") != null and scene.get_node_or_null("OfferRivalCar") != null, "offer stages turntable, work lamp and shadowed comparison car"):
			return
		var hero := scene.get_node("OfferedCar") as TextureRect
		var rival := scene.get_node("OfferRivalCar") as TextureRect
		if not _expect(hero.texture == MATERIALS.hero_texture(won) and MATERIALS.HERO_PIXEL_SCALE > 2 and hero.texture.get_width() == 48 * MATERIALS.HERO_PIXEL_SCALE and scene.get("rival_car_id") == original and rival.modulate.r < 0.5, "actual won car uses hero raster while comparison car stays in shadow"):
			return
		if not _expect(scene.get_node("OfferTabletop").get("act") == session.current_map.act and shell.find_child("RunBoard", true, false) == null, "offer uses act surface without board route clutter"):
			return
		if reduced:
			if not _expect(scene.get("reveal_state") == &"crossfade" and hero.scale == scene.size / SCENE.REFERENCE_SIZE and is_zero_approx(hero.rotation), "reduced-motion hero reveals by opacity only"):
				return
		elif not _expect(scene.get("reveal_state") == &"turn_in" and hero.scale.x < 1.0 and hero.rotation < 0.0, "hero keeps the grow-and-turn reveal"):
			return
		await create_timer(SCENE.REVEAL_TIME + 0.2).timeout
		var card := shell.find_child("OfferShape", true, false) as CarShapeView
		var take := shell.find_child("ActionTakeOffer", true, false) as Button
		var keep := shell.find_child("ActionKeepCar", true, false) as Button
		if not _expect(shell.find_child("RunOffer", true, false) != null and card.label == "VS " + UI.car_name(original).to_upper() and take.text == "DRIVE IT" and keep.text == "KEEP THE %s" % UI.car_name(original).to_upper(), "pinned offer nodes, exact actions and VS comparison survive"):
			return
		if not _expect(root.gui_get_focus_owner() == take and take.get_node(take.focus_neighbor_bottom) == keep and keep.get_node(keep.focus_neighbor_top) == take, "original first and directional focus are preserved"):
			return
		var local := Rect2(Vector2.ZERO, card.size)
		var geometry := CarShapeView.header_geometry(local, card.label)
		var plot := CarShapeView.plot_geometry(local, card.plot_bottom_padding)
		var lowest := (plot["center"] as Vector2).y + float(plot["radius"]) + CarShapeView.AXIS_LABEL_GAP + CarShapeView.DELTA_BASELINE + ThemeDB.fallback_font.get_descent(CarShapeView.AXIS_FONT_SIZE)
		var default_plot := CarShapeView.plot_geometry(local)
		if not _expect(card.size.y == SCENE.SHAPE_SIZE.y and lowest <= card.size.y - SCENE.SHAPE_BOTTOM_PADDING + 0.01 and is_equal_approx((plot["center"] as Vector2).y - float(plot["radius"]), (default_plot["center"] as Vector2).y - float(default_plot["radius"])), "radar signed values keep bottom padding without growing card bounds or crowding the heading"):
			return
		if not _expect(local.encloses(geometry["text_bounds"]) and local.encloses(geometry["tape_bounds"]) and card.get_global_rect().end.y <= root.get_visible_rect().end.y and not card.get_global_rect().intersects(take.get_global_rect()), "unaltered shape-card heading stays readable inside its bounds and clear of controls"):
			return
		if not _expect(hero.scale.is_equal_approx(scene.size / SCENE.REFERENCE_SIZE) and is_zero_approx(hero.rotation) and keep.get_global_rect().end.y <= root.get_visible_rect().end.y, "reveal settles and controls remain in viewport"):
			return
		take.button_down.emit()
		await create_timer(SCENE.STAMP_TIME + 0.02).timeout
		if not _expect(session.pending_offer == won and (take.scale == Vector2.ONE and take.modulate.a < 1.0 if reduced else take.scale.x < 1.0), "held controls stamp or crossfade without resolving the offer early"):
			return
		take.button_up.emit()
		await create_timer(SCENE.STAMP_TIME + 0.02).timeout
		(keep if reduced else take).pressed.emit()
		await process_frame
		if not _expect(session.pending_offer.is_empty() and session.current_car_id == (original if reduced else won) and shell.get("_screen") == "run_board", "drive/keep retain their immediate domain and navigation contract"):
			return
	print("RUN_OFFER_SCENE_TEST PASS turntable=present lamp=present rival=shadowed hero=native shape=readable actions=preserved reduced_motion=fade_only")
	quit(0)


func _offer(app: Node) -> RunSession:
	for attempt in 12:
		var session: RunSession = app.call("start_run", 1827000 + attempt * 31)
		if WALK.walk_to(app, session, "rival"):
			WALK.settle(app, session)
			if not session.pending_offer.is_empty():
				return session
	return null


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("RUN_OFFER_SCENE_TEST FAIL: " + message)
		quit(1)
	return condition
