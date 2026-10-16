extends SceneTree

const RUN_WALK := preload("res://tests/support/run_walk.gd")
const VAN := preload("res://scripts/ui/run_van_scene.gd")
const PART_PROP := preload("res://scripts/ui/run_bench_part.gd")


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
		if not _expect(bool(app.call("update_setting", "reduced_motion", reduced)), "motion fixture setting persists"):
			return
		var session := _find_van(app)
		if not _expect(session != null, "fixture reaches an unused van"):
			return
		session.run_points = 30
		var stock := session.van_stock()
		shell.call("show_run_parts_van")
		for frame in 4:
			await process_frame
		var scene := shell.find_child("RunVanScene", true, false) as Control
		if not _expect(scene != null and scene.get_node_or_null("VanDoor") != null and scene.get_node_or_null("WorkLamp") != null and scene.get_node("VanTabletop").get("act") == session.current_map.act, "van stages its open rear door and work lamp on the act surface"):
			return
		var blisters: Array = scene.get("blisters")
		var table := scene.get_node("VanTabletop")
		if not _expect(table.get_node("BeamDust").get_child_count() == (0 if reduced else 3), "van motes are beam-local and absent with reduced motion"):
			return
		if not _expect((table.get("_lamp_pulse") == null) == reduced, "lamp warmth pulse respects reduced motion"):
			return
		if not _expect(blisters.size() == 3, "van hangs exactly three rolled blister packs"):
			return
		var part_ids: Array[String] = []
		for index in stock.size():
			var part: Dictionary = stock[index]
			var part_id := String(part["part"])
			var buy := shell.find_child("VanBuy_" + part_id, true, false) as Button
			if not _expect(buy != null and buy.get_child(0).get_child(0).text == "%s · %d POINTS" % [RunParts.part_name(part).to_upper(), RunParts.cost(part)], "buy action ids and price copy are unchanged"):
				return
			var printed := buy.find_child("PrintedPrice", true, false) as RichTextLabel
			if not _expect(printed != null and printed.get_parsed_text() == buy.get_child(0).get_child(0).text, "proportional pack title and monospace price retain the exact printed copy"):
				return
			if not _expect(_has_label(buy, "+ " + RunParts.upside_copy(part)) and _has_label(buy, "− " + RunParts.downside_copy(part)), "each hanging pack keeps its signed give/take copy"):
				return
			if not _expect(blisters[index].get_script() == PART_PROP and blisters[index].get("part_id") == part_id and not part_ids.has(part_id), "blisters reuse the existing prop renderer for distinct rolled stock"):
				return
			part_ids.append(part_id)
		var first := shell.find_child("VanBuy_" + part_ids[0], true, false) as Button
		if not _expect(root.gui_get_focus_owner() == first, "first affordable pack takes focus before BACK"):
			return
		var selected: Dictionary = stock[2] if reduced else stock[0]
		var button := shell.find_child("VanBuy_" + String(selected["part"]), true, false) as Button
		var resting_position := button.position
		button.pressed.emit()
		if not _expect(session.parts_held == [selected] and session.run_points == 30 - RunParts.cost(selected) and session.resolved_nodes.has(session.current_node_id), "sale applies and debits immediately before confirmation"):
			return
		await create_timer(0.06).timeout
		if reduced:
			if not _expect(scene.get("confirmation_state") == &"crossfade" and button.scale == Vector2.ONE and button.position == resting_position and is_zero_approx(button.rotation) and is_zero_approx(float(scene.get("stamp_depth"))), "reduced motion fades without stamping or swinging"):
				return
		else:
			var style := button.get_theme_stylebox("disabled") as StyleBoxFlat
			if not _expect(scene.get("confirmation_state") == &"stamp" and button.scale.x < 1.0 and float(scene.get("stamp_depth")) > 0 and style.shadow_offset.y < 5.0, "buy stamps the selected pack and compresses its shadow"):
				return
			await create_timer(VAN.STAMP_TIME).timeout
			if not _expect(scene.get("confirmation_state") == &"swing" and not is_zero_approx(button.rotation) and is_zero_approx(button.pivot_offset.y), "stamped pack swings from its top peg"):
				return
			await create_timer(VAN.SWING_TIME * 0.4).timeout
			if not _expect(button.position.y > resting_position.y, "swinging pack comes off its peg"):
				return
		await create_timer(VAN.STAMP_TIME + VAN.SWING_TIME).timeout
		if not _expect(shell.get("_screen") == "run_board", "confirmation returns to the board"):
			return
		shell.call("show_run_parts_van")
		await process_frame
		for part_id: String in part_ids:
			if not _expect((shell.find_child("VanBuy_" + part_id, true, false) as Button).disabled, "used van disables every sale"):
				return
	print("RUN_VAN_SCENE_TEST PASS door=open blisters=3 stock=preserved buy=stamp+swing reduced_motion=fade_only")
	quit(0)


func _find_van(app: Node) -> RunSession:
	for attempt in 12:
		var session: RunSession = app.call("start_run", 2426200 + attempt)
		if RUN_WALK.walk_to(app, session, "parts_van"):
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
		push_error("RUN_VAN_SCENE_TEST FAIL: " + message)
		quit(1)
	return condition
