extends SceneTree

const RUN_WALK := preload("res://tests/support/run_walk.gd")
const UI := preload("res://scripts/ui/run_ui.gd")
const SCENE := preload("res://scripts/ui/run_errand_scene.gd")
const CASES := [
	{"choice": 0, "reduced": false, "wear": "clean"},
	{"choice": 1, "reduced": false, "wear": "rusty"},
	{"choice": 0, "reduced": true, "wear": "rusty"},
	{"choice": 1, "reduced": true, "wear": "rusty"},
]


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
	for fixture: Dictionary in CASES:
		var choice := int(fixture["choice"])
		var reduced := bool(fixture["reduced"])
		var wear := String(fixture["wear"])
		if not _expect(bool(app.call("update_setting", "reduced_motion", reduced)), "motion fixture setting persists"):
			return
		var session := _find_errand(app)
		if not _expect(session != null, "fixture reaches an unused errand"):
			return
		session.run_state.set_car_wear(session.current_car_id, wear)
		var points_before := session.run_points
		shell.call("show_run_errand")
		for frame in 4:
			await process_frame
		await create_timer(0.5).timeout
		var scene := shell.find_child("RunErrandScene", true, false) as Control
		if not _expect(scene != null and scene.get_node_or_null("ErrandNote") != null and scene.get_node_or_null("ErrandClipboard") != null and scene.get_node_or_null("ErrandCoinCup") != null, "errand stages its folded note, clipboard and coin cup"):
			return
		if not _expect(scene.get_node("ErrandTabletop").get("act") == session.current_map.act and (scene.get("_paper_art") as AtlasTexture).atlas == SCENE.NOTEPAD, "desk uses the current act surface and existing painted paper"):
			return
		var pay := shell.find_child("ErrandPay", true, false) as Button
		var tune := shell.find_child("ErrandTuneUp", true, false) as Button
		var back := shell.find_child("ActionBack", true, false) as Button
		if not _expect(pay.text == "TAKE THE PAY · %d" % RunSession.ERRAND_PAY_POINTS and tune.text == "TAKE A TUNE-UP" and back.text == "BACK" and _has_label(scene.get_node("ErrandNote"), String(UI.TYPES["errand"]["copy"])), "physical slips retain action ids/copy and the note carries the original errand description"):
			return
		if not _expect(root.gui_get_focus_owner() == pay and tune.disabled == (wear == "clean"), "pay remains first focus and clean cars cannot select a tune-up"):
			return
		if not _expect(tune.modulate == Color.WHITE and tune.get_theme_color("font_color") == pay.get_theme_color("font_color") and tune.get_theme_color("font_disabled_color") != tune.get_theme_color("font_color"), "enabled tune-up text matches pay without a disabled opacity treatment"):
			return
		if not _expect(SCENE.choice_ink(tune) == (SCENE.DISABLED_INK if tune.disabled else pay.get_theme_color("font_color")), "wrench uses full enabled ink only when selectable"):
			return
		var next := back if tune.disabled else tune
		if not _expect(pay.get_node(pay.focus_neighbor_bottom) == next and back.get_node(back.focus_neighbor_top) == (pay if tune.disabled else tune), "existing directional focus chain is preserved"):
			return
		var legend := shell.find_child("RunLegend", true, false) as Control
		if not _expect(back.get_global_rect().end.y < legend.get_global_rect().position.y and legend.get_global_rect().end.y <= root.get_visible_rect().end.y and tune.get_global_rect().end.x <= root.get_visible_rect().end.x, "choices, BACK and legend fit the viewport"):
			return
		var button := pay if choice == 0 else tune
		button.pressed.emit()
		var expected_points := points_before + RunSession.ERRAND_PAY_POINTS if choice == 0 else points_before
		var expected_wear := wear if choice == 0 else "dusty"
		if not _expect(session.resolved_nodes.has(session.current_node_id) and session.run_points == expected_points and session.run_state.get_car_wear(session.current_car_id) == expected_wear, "selected reward resolves immediately before its stamp"):
			return
		if not _expect(pay.disabled and tune.disabled and not bool(app.call("run_resolve_errand", 1 - choice)) and session.run_points == expected_points and session.run_state.get_car_wear(session.current_car_id) == expected_wear, "one errand cannot resolve both choices or repeat its reward"):
			return
		if not _expect(SCENE.choice_ink(tune) == SCENE.DISABLED_INK, "resolved errand switches the wrench to disabled ink"):
			return
		var expected_state: StringName = &"crossfade" if reduced else &"pay" if choice == 0 else &"tune_up"
		if not _expect(scene.get("confirmation_state") == expected_state, "choice selects the matching confirmation path"):
			return
		await create_timer(0.06).timeout
		if reduced:
			if not _expect(button.scale == Vector2.ONE and is_zero_approx(float(scene.get("stamp_depth"))), "reduced motion crossfades without stamping"):
				return
		else:
			var style := button.get_theme_stylebox("disabled") as StyleBoxFlat
			if not _expect(button.scale.x < 1.0 and float(scene.get("stamp_depth")) > 0.0 and style.shadow_offset.y < 5.0, "selected slip stamps with contact-shadow compression"):
				return
		await create_timer(SCENE.STAMP_TIME + 0.1).timeout
		if not _expect(shell.get("_screen") == "run_board", "confirmation returns to the board"):
			return
	print("RUN_ERRAND_SCENE_TEST PASS note=painted clipboard=present coin_cup=present choices=once focus=preserved reduced_motion=fade_only")
	quit(0)


func _find_errand(app: Node) -> RunSession:
	for attempt in 8:
		var session: RunSession = app.call("start_run", 900004 + attempt)
		if RUN_WALK.walk_to(app, session, "errand"):
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
		push_error("RUN_ERRAND_SCENE_TEST FAIL: " + message)
		quit(1)
	return condition
