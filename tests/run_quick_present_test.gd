extends SceneTree

const BOOT := preload("res://scenes/boot/boot.tscn")
const WALK := preload("res://tests/support/run_walk.gd")
const RULES := preload("res://scripts/race/generated_circuit_rules.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var boot := BOOT.instantiate()
	root.add_child(boot)
	current_scene = boot
	for frame in 3:
		await process_frame
	var app := root.get_node("App")
	var shell := app.get("_shell") as CanvasLayer
	for strip: bool in [false, true]:
		for theme: String in ["kitchen", "workshop", "office"]:
			for tier: String in RULES.LENGTH_TIERS:
				shell.set("_quick_race", not strip)
				shell.set("_quick_strip", strip)
				shell.set("_quick_race_theme", StringName(theme))
				shell.set("_quick_race_length_tier", tier)
				shell.call("show_quick_strip" if strip else "show_quick_race")
				var identity: Dictionary = shell.call("_current_quick_identity")
				if not _expect(not identity.is_empty(), "quick fixture has a valid event identity"):
					return
				var summary := shell.find_child("QuickCircuitSummary", true, false) as Label
				var expected := theme.capitalize()
				if strip:
					expected += " → " + String(identity["theme_b"]).capitalize()
				expected += " · " + tier.capitalize()
				if not _expect(summary != null and summary.text == expected, "quick preview names actual rooms and length: " + expected):
					return
				if not _expect(not (shell.get("_stage") as Control).visible, "quick preview does not show the championship route"):
					return
				var labels := _player_text(shell.get("_content"))
				for forbidden: String in ["Route ", "Material ", "palette ", String(identity["fingerprints"]["route"]).substr(0, 8).to_upper(), String(identity["material_id"]), String(identity["palette_id"])]:
					if not forbidden.is_empty() and not _expect(not labels.contains(forbidden), "player labels omit generator internals: " + forbidden):
						return
				var seed := shell.find_child("QuickRaceSeed", true, false) as LineEdit
				if seed != null:
					if not _expect(labels.contains("DEVELOPER SEED"), "seed controls explicitly marked developer-only"):
						return
					seed.text_submitted.emit(str(int(seed.text) + 1))
					if not _expect(summary.text == expected and not (shell.get("_stage") as Control).visible, "seed refresh preserves room preview without championship decoration"):
						return
	var session: RunSession
	for attempt in 12:
		session = app.call("start_run", 1827000 + attempt * 31)
		if WALK.walk_to(app, session, "rival"):
			WALK.settle(app, session)
			if not session.pending_offer.is_empty():
				break
	if not _expect(session != null and not session.pending_offer.is_empty(), "offer fixture wins a car"):
		return
	shell.call("show_run_board")
	await process_frame
	var card := shell.find_child("OfferShape", true, false) as CarShapeView
	if not _expect(card != null, "offer contains shared shape card"):
		return
	var caption: Dictionary = card.call("caption_geometry", Rect2(Vector2.ZERO, card.size))
	if not _expect(caption.get("text") == "SHAPE DELTAS, NOT PERCENTAGES" and (caption["bounds"] as Rect2).size.x <= card.size.x and (caption["bounds"] as Rect2).position.y >= card.size.y, "shared offer/garage renderer captions deltas below the card"):
		return
	if not _expect((caption["bounds"] as Rect2).end.y + card.global_position.y <= root.get_visible_rect().end.y, "offer caption stays within the viewport"):
		return
	var garage_caption: Dictionary = card.call("caption_geometry", Rect2(0, 0, 247, 330))
	if not _expect((garage_caption["bounds"] as Rect2).position.x >= 0 and (garage_caption["bounds"] as Rect2).end.x <= 247, "caption fits the narrower garage card"):
		return
	print("RUN_QUICK_PRESENT_TEST PASS race=actual_room strip=two_rooms labels=player_copy shape=delta_units")
	quit(0)


func _player_text(node: Node) -> String:
	var text := ""
	if node is Label or node is Button:
		text = String(node.get("text")) + "\n"
	for child: Node in node.get_children():
		text += _player_text(child)
	return text


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("RUN_QUICK_PRESENT_TEST FAIL: " + message)
		quit(1)
	return condition
