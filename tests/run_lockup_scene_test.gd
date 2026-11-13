extends SceneTree

const RUN_WALK := preload("res://tests/support/run_walk.gd")
const UI := preload("res://scripts/ui/run_ui.gd")
const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")
const SCENE := preload("res://scripts/ui/run_lockup_scene.gd")


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
	var can_bounds := SCENE.PAINT_CAN.get_image().get_used_rect()
	var can_base := SCENE.PAINT_CAN_RECT.position.y + float(can_bounds.end.y) / SCENE.PAINT_CAN.get_height() * SCENE.PAINT_CAN_RECT.size.y
	if not _expect(absf(SCENE.PAINT_CAN_SHADOW_RECT.get_center().y - can_base) < 3 and SCENE.PAINT_CAN_SHADOW_RECT.size.y <= 16, "paint-can contact shadow meets the painted bottom edge with a tight spread"):
		return
	for reduced: bool in [false, true]:
		if not _expect(bool(app.call("update_setting", "reduced_motion", reduced)), "motion fixture setting persists"):
			return
		var session := _find_lockup(app)
		if not _expect(session != null, "fixture reaches an unused lockup"):
			return
		var owned_before := session.owned_cars.size()
		var original_car := session.current_car_id
		shell.call("show_run_lockup")
		for frame in 4:
			await process_frame
		var scene := shell.find_child("RunLockupScene", true, false) as Control
		if not _expect(scene != null and scene.get_node_or_null("LockupDoor") != null and scene.get_node_or_null("LockupPadlock") != null and scene.get_node_or_null("LockupChain") != null, "lockup stages its garage door, padlock and chain"):
			return
		if not _expect(scene.get_node("LockupTabletop").get("act") == session.current_map.act, "garage stands on the current act's table surface"):
			return
		var open := shell.find_child("LockupOpen", true, false) as Button
		var back := shell.find_child("ActionBack", true, false) as Button
		var context := shell.find_child("RunContextMap", true, false) as Control
		if not _expect(open.text == "OPEN LOCKUP" and back.text == "BACK" and _has_label(shell, String(UI.TYPES["lockup"]["copy"])) and context != null, "existing action ids, copy and context-map node remain present"):
			return
		if not _expect(root.gui_get_focus_owner() == open, "OPEN LOCKUP remains the first focused action"):
			return
		if not _expect(open.get_node(open.focus_neighbor_bottom) == back and back.get_node(back.focus_neighbor_top) == open, "existing open/back directional focus chain is preserved"):
			return
		var car := scene.get_node("LockupCar") as TextureRect
		if not _expect(car.texture == null and not car.visible, "the closed garage does not roll or disclose a speculative reward"):
			return
		open.pressed.emit()
		var won := session.pending_offer
		if not _expect(session.lockup_used and session.owned_cars.size() == owned_before + 1 and not won.is_empty() and session.current_car_id == original_car, "opening immediately grants one car but preserves the drive/keep decision"):
			return
		if not _expect(car.texture == MATERIALS.hero_texture(won) and car.texture.get_width() == 48 * MATERIALS.HERO_PIXEL_SCALE and MATERIALS.HERO_PIXEL_SCALE > 2, "revealed car uses the actual granted identity at hero resolution"):
			return
		if not _expect(open.disabled and session.open_lockup().is_empty() and session.owned_cars.size() == owned_before + 1, "confirmation cannot grant a second car"):
			return
		var start := car.position
		if reduced:
			if not _expect(scene.get("confirmation_state") == &"crossfade", "reduced motion selects the fade-only path"):
				return
			await create_timer(0.06).timeout
			if not _expect(car.position == start and open.scale == Vector2.ONE and is_zero_approx(float(scene.get("door_progress"))) and is_zero_approx(float(scene.get("lock_progress"))), "reduced motion changes opacity without stamping, sliding or rolling"):
				return
		else:
			if not _expect(scene.get("confirmation_state") == &"stamp", "opening starts with the physical confirmation stamp"):
				return
			await create_timer(SCENE.STAMP_TIME + SCENE.UNLOCK_TIME + 0.08).timeout
			if not _expect(float(scene.get("lock_progress")) > 0.95 and float(scene.get("door_progress")) > 0.0 and (scene.get_node("LockupDoor/ShutterPaint") as Control).position.y < 0, "padlock springs open before the shutter slides upward"):
				return
			await create_timer(SCENE.DOOR_TIME + 0.02).timeout
			if not _expect(car.position.y > start.y, "granted car rolls out after the shutter opens"):
				return
			var deadline := Time.get_ticks_msec() + 2000
			while is_instance_valid(scene) and scene.get("confirmation_state") != &"hold" and Time.get_ticks_msec() < deadline:
				await process_frame
			if not _expect(is_instance_valid(scene) and scene.get("confirmation_state") == &"hold", "rollout holds its completed pose before the offer"):
				return
			var used := car.texture.get_image().get_used_rect()
			var local_paint := Rect2(Vector2(used.position) / car.texture.get_size() * car.size, Vector2(used.size) / car.texture.get_size() * car.size)
			var painted: Rect2 = car.get_global_transform() * local_paint
			var ratio := scene.size / SCENE.REFERENCE_SIZE
			var sill: Rect2 = scene.get_global_transform() * Rect2(SCENE.SILL_RECT.position * ratio, SCENE.SILL_RECT.size * ratio)
			var legend := shell.find_child("RunLegend", true, false) as Control
			if not _expect(painted.position.y >= sill.end.y + 4 and painted.end.y <= legend.get_global_rect().position.y - 6, "completed car is wholly beyond the sill with clearance above the legend"):
				return
			var shadow := scene.get_node("LockupCarShadow") as TextureRect
			if not _expect((shadow.position + shadow.size * 0.5 - car.position - car.size * 0.5).is_equal_approx(SCENE.CAR_SHADOW_OFFSET * ratio) and shadow.size.y < car.size.y, "rolled-out car keeps a tight shadow directly beneath its tabletop footprint"):
				return
		await create_timer(SCENE.STAMP_TIME + SCENE.UNLOCK_TIME + SCENE.DOOR_TIME + SCENE.ROLL_TIME + SCENE.HOLD_TIME).timeout
		if not _expect(shell.get("_screen") == "run_offer" and shell.find_child("ActionTakeOffer", true, false) != null and shell.find_child("ActionKeepCar", true, false) != null, "returning through the board retains the existing drive/keep offer"):
			return
		var choice := shell.find_child("ActionTakeOffer" if reduced else "ActionKeepCar", true, false) as Button
		choice.pressed.emit()
		await process_frame
		if not _expect(shell.get("_screen") == "run_board" and session.pending_offer.is_empty() and session.current_car_id == (won if reduced else original_car), "existing take and keep actions still return to the board with the selected car"):
			return
		shell.call("show_run_lockup")
		await process_frame
		if not _expect((shell.find_child("LockupOpen", true, false) as Button).disabled, "used lockup offers no second opening"):
			return
	print("RUN_LOCKUP_SCENE_TEST PASS door=sliding padlock=spring chain=present car=hero rollout=clear_sill offer=preserved reduced_motion=fade_only")
	quit(0)


func _find_lockup(app: Node) -> RunSession:
	for attempt in 8:
		var session: RunSession = app.call("start_run", 900003 + attempt * 101)
		if RUN_WALK.walk_to(app, session, "lockup"):
			return session
	return null


func _has_label(host: Node, text: String) -> bool:
	for child: Node in host.get_children():
		if child is Label and (child as Label).text == text:
			return true
		if _has_label(child, text):
			return true
	return false


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("RUN_LOCKUP_SCENE_TEST FAIL: " + message)
		quit(1)
	return condition
