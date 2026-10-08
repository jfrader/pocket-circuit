extends CanvasLayer

const CATALOG := preload("res://data/championship/catalog.gd")
const STAGE_SCRIPT := preload("res://scripts/ui/app_shell_stage.gd")
const RUN_MAP_VIEW := preload("res://scripts/ui/run_map_view.gd")
const RUN_UI := preload("res://scripts/ui/run_ui.gd")
const MENU_SCRIPT := preload("res://scripts/ui/championship_menu.gd")
const ROUTE_SCRIPT := preload("res://scripts/ui/championship_route_menu.gd")
const BUTTON_SCRIPT := preload("res://scripts/ui/motorsport_button.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const DISCOVERY_PANEL := preload("res://scripts/ui/circuit_discovery_panel.gd")
const RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const GENERATED_CIRCUITS := preload("res://scripts/race/generated_circuit_identity.gd")
const RUN_SESSION := preload("res://scripts/progression/run_session.gd")

const PAGE_MARGIN := 48
const PAGE_TOP := 28
const BACK_HINT := "ESC / B  BACK"

var _app: Node
var _root: Control
var _scroll: ScrollContainer
var _content: VBoxContainer
var _stage: AppShellStage
var _route: Control
var _footer: Label
var _run_backdrop: ColorRect
var _run_actions: VBoxContainer
var _button_focus_chain: Array[Button] = []
var _screen := "title"
var _event_id := ""
var _quick_race := false
var _quick_strip := false
var _map_act_number := 1
var _quick_race_theme := StringName(GENERATED_CIRCUITS.THEMES[0])
var _quick_race_room: StringName = &"classic"
var _quick_race_seed := 875
var _quick_race_reverse := false
var _quick_race_length_tier: String = "standard"
var _quick_identity_heading: Label
var _quick_identity_summary: Label
var _content_tween: Tween
var _entrance_generation := 0
var _save_error_back_action := Callable()
var _current_vehicle_select_id := ""
var _quick_race_vehicle_id := ""
var _quick_strip_vehicle_id := ""
## Candidate portrait seed shown on the Driver screen before the player keeps it.
var _preview_avatar_seed := 0
## Where the Driver screen returns to, so it can be opened from more than one screen.
var _driver_return: Callable
var _page: MarginContainer
var _art_menu: Control
var _discovery_panel: CircuitDiscoveryPanel

static var _quick_race_entry_count := 0
static var _quick_race_theme_cursor := -1

func configure(app: Node) -> void:
	_app = app
	if _root == null:
		_build_base()


func show_title() -> void:
	_screen = "title"
	_event_id = ""
	_reset_quick_race_state()
	_clear_content()
	var save_read_only := bool(_app.call("is_save_read_only"))
	var recovery_message := String(_app.call("get_save_recovery_message"))
	var has_progress := bool(_app.call("has_championship_progress"))
	var progress: Dictionary = _app.call("get_save_data")
	_page.hide()
	_art_menu.set("reduced_motion", _reduced_motion_enabled())
	_art_menu.call("show_title", has_progress, save_read_only, _selected_vehicle(progress), progress.get("unlocked_vehicles", ["rustbug"]), recovery_message, _app.call("current_run_session") != null)
	_app.call("prepare_circuit_preview", _current_quick_identity())


func show_reset_confirmation() -> void:
	_screen = "reset_confirmation"
	_clear_content()
	_configure_stage(&"title")
	_add_kicker("NEW CHAMPIONSHIP")
	_add_heading("Erase the current standings?")
	_add_copy("Best finishes, act wins, and car unlocks will be erased.")
	_add_spacer(18)
	_add_button("ERASE & START AGAIN", Callable(_app, "confirm_new_championship"), true)
	_add_button("KEEP CURRENT CHAMPIONSHIP", Callable(self, "show_title"))
	_footer.text = BACK_HINT
	_focus_first()


func show_map(result_summary: Dictionary = {}, requested_act: int = 0) -> void:
	_screen = "map"
	_event_id = ""
	_reset_quick_race_state()
	_clear_content()
	var progress: Dictionary = _app.call("get_save_data")
	var best_finishes: Dictionary = progress.get("best_event_finishes", {})
	var best_points: Dictionary = progress.get("best_event_points", {})
	var recommended_event_id := ""
	for event: Dictionary in CATALOG.EVENTS:
		var candidate_id := String(event["id"])
		if CATALOG.is_event_unlocked(candidate_id, progress) and int(best_finishes.get(candidate_id, 0)) == 0:
			recommended_event_id = candidate_id
			break
	if requested_act > 0:
		_map_act_number = clampi(requested_act, 1, CATALOG.ACTS.size())
	elif not recommended_event_id.is_empty():
		_map_act_number = int(CATALOG.get_event(recommended_event_id).get("act", _map_act_number))
	var focus_id := recommended_event_id
	if requested_act > 0:
		for event: Dictionary in CATALOG.EVENTS:
			if int(event["act"]) == _map_act_number and CATALOG.is_event_unlocked(String(event["id"]), progress):
				focus_id = String(event["id"])
				break
	if not focus_id.is_empty() and _app.has_method("prewarm_championship_event"):
		_app.call("prewarm_championship_event", focus_id)
	var stops: Array[Dictionary] = []
	var seen_acts: Dictionary = {}
	for event: Dictionary in CATALOG.EVENTS:
		var event_id := String(event["id"])
		var unlocked := CATALOG.is_event_unlocked(event_id, progress)
		var finish := int(best_finishes.get(event_id, 0))
		var status := "LOCKED · %s" % String(event["unlock"])
		if unlocked:
			status = "OPEN · %s" % String(event["format"])
		if finish > 0:
			status = _completed_event_status(event_id, finish, int(best_points.get(event_id, 0)))
		var act_number := int(event["act"])
		stops.append({
			"id": event_id,
			"name": String(event["name"]),
			"status": status,
			"unlocked": unlocked,
			"theme": String(event.get("theme", "kitchen")),
			"act": act_number,
			"act_name": String(CATALOG.get_act(act_number).get("name", "")),
			"act_start": not seen_acts.has(act_number),
		})
		seen_acts[act_number] = true
	var notice := ""
	if not result_summary.is_empty():
		notice = _result_notice_text(result_summary)
	_page.hide()
	_route.show()
	_route.call("present", stops, focus_id, _selected_vehicle(progress), notice)
	_footer.text = "ENTER / A  SELECT  ·  " + BACK_HINT


func show_quick_race(_requested_act: int = 0) -> void:
	_screen = "quick_race"
	_event_id = ""
	_quick_race = true
	_quick_strip = false
	_quick_race_reverse = false
	_roll_quick_race()
	_quick_race_length_tier = String(RULES.LENGTH_TIERS[_quick_race_entry_count % RULES.LENGTH_TIERS.size()])
	_quick_race_entry_count += 1
	_clear_content()
	_content.add_theme_constant_override("separation", 4)
	var progress: Dictionary = _app.call("get_save_data")
	if _quick_race_vehicle_id.is_empty():
		_quick_race_vehicle_id = _selected_vehicle(progress)
	_configure_stage(&"map", _quick_race_vehicle_id, "rae", String(_quick_race_theme))
	_add_kicker("QUICK RACE · RESULTS DO NOT SAVE")
	var quick_identity: Dictionary = _current_quick_identity()
	if _app.has_method("prewarm_generated_circuit"):
		_app.call("prewarm_generated_circuit", GENERATED_CIRCUITS.apply_to_event(quick_identity))
	_quick_identity_heading = _label(String(quick_identity.get("display_name", "Build a circuit")), 32, SKIN.CREAM, true)
	_quick_identity_heading.custom_minimum_size = Vector2(0.0, 44.0)
	_content.add_child(_quick_identity_heading)
	_quick_identity_summary = _label(String(quick_identity.get("summary", "")), 13, SKIN.CREAM_DIM)
	_quick_identity_summary.name = "QuickCircuitSummary"
	_quick_identity_summary.custom_minimum_size = Vector2(0.0, 76.0)
	_content.add_child(_quick_identity_summary)
	_register_button_focus(_add_difficulty_picker())
	var play_button := _add_big_play_button(Callable(self, "_start_quick_race"), false)
	var seed_controls: Array[Control] = []
	if OS.is_debug_build():
		var seed_status := _add_section("CIRCUIT SEED", "SEED %d · %s CANVAS" % [_quick_race_seed, String(_quick_race_room).to_upper()])
		seed_controls = _add_quick_race_seed_controls(seed_status)
	_add_button("CHANGE CAR · %s" % String(CATALOG.get_vehicle(_quick_race_vehicle_id).get("name", "Rustbug")).to_upper(), Callable(self, "show_vehicle_select").bind("", true))
	_add_button("BACK TO TITLE", Callable(self, "show_title"))
	_footer.text = "EXHIBITION RESULTS DO NOT SAVE  ·  " + BACK_HINT
	if not seed_controls.is_empty():
		_complete_focus_row(seed_controls, play_button)
	_queue_content_entrance()
	_grab_button_focus_after_layout(play_button, _entrance_generation)


func show_quick_strip(_requested_act: int = 0) -> void:
	_screen = "quick_strip"
	_event_id = ""
	_quick_strip = true
	_quick_race = false
	_quick_race_reverse = false
	_roll_quick_race()
	_quick_race_length_tier = String(RULES.LENGTH_TIERS[_quick_race_entry_count % RULES.LENGTH_TIERS.size()])
	_quick_race_entry_count += 1
	_clear_content()
	_content.add_theme_constant_override("separation", 4)
	var progress: Dictionary = _app.call("get_save_data")
	if _quick_strip_vehicle_id.is_empty():
		_quick_strip_vehicle_id = _selected_vehicle(progress)
	_configure_stage(&"map", _quick_strip_vehicle_id, "rae", String(_quick_race_theme))
	_add_kicker("QUICK STRIP · RESULTS DO NOT SAVE")
	var quick_identity: Dictionary = _current_quick_identity()
	_quick_identity_heading = _label(String(quick_identity.get("display_name", "Build a circuit")), 32, SKIN.CREAM, true)
	_quick_identity_heading.custom_minimum_size = Vector2(0.0, 44.0)
	_content.add_child(_quick_identity_heading)
	_quick_identity_summary = _label(String(quick_identity.get("summary", "")), 13, SKIN.CREAM_DIM)
	_quick_identity_summary.name = "QuickCircuitSummary"
	_quick_identity_summary.custom_minimum_size = Vector2(0.0, 76.0)
	_content.add_child(_quick_identity_summary)
	_register_button_focus(_add_difficulty_picker())
	var play_button := _add_big_play_button(Callable(self, "_start_quick_strip"), false)
	var seed_controls: Array[Control] = []
	if OS.is_debug_build():
		var seed_status := _add_section("CIRCUIT SEED", "SEED %d · %s CANVAS" % [_quick_race_seed, String(_quick_race_room).to_upper()])
		seed_controls = _add_quick_race_seed_controls(seed_status)
	_add_button("CHANGE CAR · %s" % String(CATALOG.get_vehicle(_quick_strip_vehicle_id).get("name", "Rustbug")).to_upper(), Callable(self, "show_vehicle_select").bind("", true))
	_add_button("BACK TO TITLE", Callable(self, "show_title"))
	_footer.text = "EXHIBITION RESULTS DO NOT SAVE  ·  " + BACK_HINT
	if not seed_controls.is_empty():
		_complete_focus_row(seed_controls, play_button)
	_queue_content_entrance()
	_grab_button_focus_after_layout(play_button, _entrance_generation)


func show_discovery() -> void:
	_screen = "discovery"
	_event_id = ""
	_reset_quick_race_state()
	_clear_content()
	_configure_stage(&"map", _selected_vehicle(_app.call("get_save_data")), "rae", "office")
	_discovery_panel = DISCOVERY_PANEL.new() as CircuitDiscoveryPanel
	_discovery_panel.name = "CircuitDiscoveryPanel"
	_discovery_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_discovery_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_discovery_panel.back_requested.connect(show_title)
	_content.add_child(_discovery_panel)
	_discovery_panel.configure(_app)
	_footer.text = BACK_HINT

func show_run_board() -> void:
	_screen = "run_board"
	_event_id = ""
	_reset_quick_race_state()
	_clear_content()
	_content.add_theme_constant_override("separation", 4)
	var sess_var: Variant = _app.call("current_run_session")
	var sess: RunSession = sess_var as RunSession
	if sess == null or sess.current_map == null:
		_configure_stage(&"map", "rustbug", "rae", "workshop")
		_add_kicker("RUN BOARD")
		_add_heading("NO ACTIVE RUN")
		_add_copy("Start a run to see the board.", SKIN.CREAM_DIM)
		_add_spacer(8)
		_add_button("NEW RUN", Callable(self, "_on_new_run_pressed"), true)
		_add_button("BACK TO TITLE", Callable(self, "show_title"))
		_footer.text = BACK_HINT
		_focus_first()
		return
	_run_surface()
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 64)
	_content.add_child(columns)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	var board := RUN_MAP_VIEW.new()
	board.name = "RunBoard"
	left.add_child(board)
	left.add_child(RUN_UI.label("CHOOSE THE NEXT STOP", 11, RUN_UI.MUTED, true))
	var buttons: Array[Button] = board.configure(sess, Callable(self, "_on_run_node_pressed"))
	if _app.has_method("prewarm_run_stops"):
		_app.call("prewarm_run_stops")
	for button: Button in buttons:
		_wire_button_audio(button)
		if not button.disabled:
			_register_button_focus(button)
	var detail := VBoxContainer.new()
	detail.name = "RunDetail"
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	columns.add_child(detail)
	RUN_UI.spacer(detail, 8)
	detail.add_child(RUN_UI.label("THE RUN · ACT %d / 3" % sess.current_map.act, 12, RUN_UI.AMBER, true))
	var heading := RUN_UI.label(String(RUN_UI.ROOMS[sess.current_map.act]).replace(" ", "\n"), 44)
	detail.add_child(heading)
	RUN_UI.spacer(detail, 8)
	RUN_UI.stats(detail, sess)
	RUN_UI.spacer(detail, 8)
	_run_actions = detail
	if sess.is_failed() or sess.is_complete():
		detail.add_child(RUN_UI.label("NIGHT OVER", 12, RUN_UI.AMBER, true))
	var unsaved := String(_app.get("run_save_error"))
	if not unsaved.is_empty():
		detail.add_child(RUN_UI.label("NOT SAVED · " + unsaved.to_upper(), 12, RUN_UI.AMBER, true))
		if not bool(_app.call("is_save_read_only")):
			_run_action("SAVE AGAIN", Callable(self, "_on_save_run_again"), true, false, "ActionSaveAgain")
	_run_action("NEW RUN", Callable(self, "_on_new_run_pressed"), false, false, "ActionNewRun")
	_run_action("ABANDON RUN", Callable(self, "_on_abandon_run"), false, false, "ActionAbandon")
	_run_action("BACK", Callable(self, "show_title"), false, false, "ActionBack")
	RUN_UI.spacer(_content, 10)
	RUN_UI.divider(_content)
	_content.add_child(RUN_UI.legend(sess.current_map))
	_content.add_child(RUN_UI.key_row(["RING · CURRENT STOP", "COLOUR · AVAILABLE", "DIM · LOCKED"]))
	_focus_first()


func _run_surface() -> void:
	_configure_stage(&"title")
	_run_backdrop.show()
	_footer.get_parent().hide()
	_content.add_theme_constant_override("separation", 14)


func _run_node_intro(sess: RunSession, kind: String) -> void:
	_run_surface()
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 64)
	_content.add_child(columns)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	columns.add_child(detail)
	RUN_UI.spacer(detail, 8)
	detail.add_child(RUN_UI.label("RUN · ACT %d · %s" % [sess.current_map.act, String(RUN_UI.ROOMS[sess.current_map.act]).to_upper()], 11, RUN_UI.MUTED, true))
	RUN_UI.spacer(detail, 8)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 16)
	title_row.add_child(RUN_UI.icon(kind, 36))
	title_row.add_child(RUN_UI.label(String(RUN_UI.TYPES[kind]["name"]), 48))
	detail.add_child(title_row)
	var copy := RUN_UI.label(String(RUN_UI.TYPES[kind]["copy"]), 20, RUN_UI.MUTED)
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(copy)
	RUN_UI.spacer(detail, 6)
	RUN_UI.stats(detail, sess)
	RUN_UI.spacer(detail, 12)
	_run_actions = detail
	var board := RUN_MAP_VIEW.new()
	board.name = "RunContextMap"
	columns.add_child(board)
	# The context map is read-only; actions on this stop remain the only focus targets.
	var buttons: Array[Button] = board.configure(sess, Callable())
	for button: Button in buttons:
		button.disabled = true
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	RUN_UI.divider(_content)
	_content.add_child(RUN_UI.legend(sess.current_map))


func _run_action(text: String, callback: Callable, primary: bool = false, disabled: bool = false, node_name: String = "") -> void:
	var button := RUN_UI.action(text, primary, disabled)
	button.name = node_name
	button.pressed.connect(callback)
	_wire_button_audio(button)
	_run_actions.add_child(button)
	if not disabled:
		_register_button_focus(button)


func show_run_bench() -> void:
	_screen = "run_bench"
	_event_id = ""
	_reset_quick_race_state()
	_clear_content()
	_content.add_theme_constant_override("separation", 4)
	var sess_var: Variant = _app.call("current_run_session")
	var sess: RunSession = sess_var as RunSession
	if sess == null or sess.current_map == null:
		show_run_board()
		return
	_run_node_intro(sess, "bench")
	_run_action("REPAIR", Callable(self, "_on_bench_repair_pressed"), true, false, "BenchRepair")
	_run_action("FIT SPARE", Callable(self, "_on_bench_fit_pressed"), false, false, "BenchFit")
	_run_action("BACK", Callable(self, "show_run_board"), false, false, "ActionBack")
	_focus_first()


func show_run_parts_van() -> void:
	_screen = "run_parts_van"
	_event_id = ""
	_reset_quick_race_state()
	_clear_content()
	_content.add_theme_constant_override("separation", 4)
	var sess_var: Variant = _app.call("current_run_session")
	var sess: RunSession = sess_var as RunSession
	if sess == null or sess.current_map == null:
		show_run_board()
		return
	_run_node_intro(sess, "parts_van")
	_run_actions.add_child(RUN_UI.label("SPEND POINTS", 11, RUN_UI.AMBER, true))
	for part: String in RunSession.VAN_PART_COSTS:
		var cost := int(RunSession.VAN_PART_COSTS[part])
		_run_action("%s · %d" % [String(RUN_UI.VAN_PART_NAMES[part]), cost], Callable(self, "_on_van_buy_pressed").bind(part), false, sess.run_points < cost, "VanBuy_" + part)
	_run_action("BACK", Callable(self, "show_run_board"), false, false, "ActionBack")
	_focus_first()


func show_run_lockup() -> void:
	_screen = "run_lockup"
	_event_id = ""
	_reset_quick_race_state()
	_clear_content()
	_content.add_theme_constant_override("separation", 4)
	var sess_var: Variant = _app.call("current_run_session")
	var sess: RunSession = sess_var as RunSession
	if sess == null or sess.current_map == null:
		show_run_board()
		return
	_run_node_intro(sess, "lockup")
	_run_action("OPEN LOCKUP", Callable(self, "_on_lockup_open_pressed"), true, sess.lockup_used, "LockupOpen")
	_run_action("BACK", Callable(self, "show_run_board"), false, false, "ActionBack")
	_focus_first()


func show_run_errand() -> void:
	_screen = "run_errand"
	_event_id = ""
	_reset_quick_race_state()
	_clear_content()
	_content.add_theme_constant_override("separation", 4)
	var sess_var: Variant = _app.call("current_run_session")
	var sess: RunSession = sess_var as RunSession
	if sess == null or sess.current_map == null:
		show_run_board()
		return
	_run_node_intro(sess, "errand")
	var car_clean := sess.run_state.get_car_wear(sess.current_car_id) == RunState.WEAR_LEVELS[0]
	_run_action("TAKE THE PAY · %d" % RunSession.ERRAND_PAY_POINTS, Callable(self, "_on_errand_choice_pressed").bind(0), true, false, "ErrandPay")
	_run_action("TAKE A TUNE-UP", Callable(self, "_on_errand_choice_pressed").bind(1), false, car_clean, "ErrandTuneUp")
	_run_action("BACK", Callable(self, "show_run_board"), false, false, "ActionBack")
	_focus_first()


func _on_bench_repair_pressed() -> void:
	_play_ui_confirm()
	var sess_var: Variant = _app.call("current_run_session")
	var sess: RunSession = sess_var as RunSession
	if sess != null:
		_app.call("run_bench_repair", sess.current_car_id)
	show_run_board()


func _on_bench_fit_pressed() -> void:
	_play_ui_confirm()
	_app.call("run_bench_fit", "spare")
	show_run_board()


func _on_van_buy_pressed(part_id: String) -> void:
	_play_ui_confirm()
	_app.call("run_buy_part", part_id)
	show_run_board()


func _on_lockup_open_pressed() -> void:
	_play_ui_confirm()
	_app.call("run_open_lockup")
	show_run_board()


func _on_errand_choice_pressed(choice: int) -> void:
	_play_ui_confirm()
	_app.call("run_resolve_errand", choice)
	show_run_board()


func show_briefing(event_id: String) -> void:
	var event: Dictionary = _app.call("get_championship_event", event_id)
	if event.is_empty():
		show_map()
		return
	_screen = "briefing"
	_event_id = event_id
	# Mastery runs use this event's championship circuit, so warm it while the
	# briefing is on screen (the map prewarms its focus, the briefing did not).
	if _app.has_method("prewarm_championship_event"):
		_app.call("prewarm_championship_event", event_id)
	_reset_quick_race_state()
	_clear_content()
	var opponent_ids: Array = event.get("opponents", [])
	var rival_id := String(opponent_ids[0]) if not opponent_ids.is_empty() else ""
	var progress: Dictionary = _app.call("get_save_data")
	_current_vehicle_select_id = _selected_vehicle(progress)
	_configure_stage(&"briefing", _current_vehicle_select_id, rival_id, String(event.get("theme", "kitchen")), "rae")
	_add_kicker("ACT %d · EVENT BRIEFING" % int(event["act"]))
	_add_heading(String(event["name"]))
	_add_copy("%s  ·  %s" % [String(event["environment"]), String(event["format"])], SKIN.YELLOW)
	var rival := CATALOG.get_driver(rival_id)
	var rival_vehicle := CATALOG.get_vehicle(String(rival.get("vehicle_id", "rustbug")))
	_add_section("LEAD RIVAL", "%s · %s" % [String(rival.get("name", "RACER")), String(rival_vehicle.get("name", "MACHINE"))])
	var completed: bool = event_id in progress.get("completed_events", [])
	if event_id == "kitchen_crumb_rush" and int(progress.get("best_event_finishes", {}).get(event_id, 0)) == 0:
		_add_section("FIRST RACE", "LEARN THE LINE, THEN FIND SPEED")
		_add_copy("W / Up or RT accelerate  ·  S / Down or LT brake  ·  A/D or left stick steer")
		_add_copy("Space / A drift  ·  Shift / B boost  ·  R / Y resets at the last legal gate", SKIN.CREAM_DIM)
	_add_spacer(12)
	var mastery_calibrating := false
	var mastery_calibration_failed := false
	if completed:
		var mastery_state: Dictionary = _app.call("get_mastery_state", event_id, _current_vehicle_select_id)
		mastery_calibrating = bool(mastery_state.get("calibrating", false))
		mastery_calibration_failed = bool(mastery_state.get("calibration_failed", false))
		var vehicle_name := String(CATALOG.get_vehicle(_current_vehicle_select_id).get("name", "Rustbug")).to_upper()
		var mastery_status_label := _add_section("MASTERY · " + vehicle_name, _briefing_mastery_status(mastery_state))
		mastery_status_label.name = "MasteryStatus"
		var target_copy := _add_copy(_briefing_mastery_targets(mastery_state), SKIN.YELLOW)
		target_copy.name = "MasteryTargets"
	_add_big_play_button(Callable(self, "_start_current_selected_vehicle"), false).text = "REPLAY EVENT" if completed else "PLAY"
	if completed:
		var mastery_action := "RETRY MASTERY CALIBRATION" if mastery_calibration_failed else "SOLO TIME TRIAL · %s" % String(CATALOG.get_vehicle(_current_vehicle_select_id).get("name", "Rustbug")).to_upper()
		_add_button(mastery_action, Callable(self, "_start_mastery_selected_vehicle"), false, mastery_calibrating, "MasteryRun")
	_add_button("CHOOSE VEHICLE", Callable(self, "show_vehicle_select").bind(event_id, false))
	_add_button("BACK TO MAP", Callable(self, "show_map"))
	_footer.text = BACK_HINT
	_focus_first()


func refresh_mastery_calibration(event_id: String) -> void:
	if _screen == "map":
		var progress: Dictionary = _app.call("get_save_data")
		var finish := int(progress.get("best_event_finishes", {}).get(event_id, 0))
		var button := find_child("Stop_%s" % event_id, true, false) as Button
		var event := CATALOG.get_event(event_id)
		if button and not event.is_empty() and finish > 0:
			button.text = "%s\n%s" % [String(event["name"]), _completed_event_status(event_id, finish, int(progress.get("best_event_points", {}).get(event_id, 0)))]
		return
	if _screen != "briefing" or _event_id != event_id:
		return
	var state: Dictionary = _app.call("get_mastery_state", event_id, _current_vehicle_select_id)
	var status_label := find_child("MasteryStatus", true, false) as Label
	var targets_label := find_child("MasteryTargets", true, false) as Label
	var mastery_button := find_child("MasteryRun", true, false) as Button
	if status_label:
		status_label.text = _briefing_mastery_status(state)
	if targets_label:
		targets_label.text = _briefing_mastery_targets(state)
	if mastery_button:
		mastery_button.text = "RETRY MASTERY CALIBRATION" if bool(state.get("calibration_failed", false)) else "SOLO TIME TRIAL · %s" % String(CATALOG.get_vehicle(_current_vehicle_select_id).get("name", "Rustbug")).to_upper()
		mastery_button.disabled = bool(state.get("calibrating", false))


func _completed_event_status(event_id: String, finish: int, points: int) -> String:
	var state: Dictionary = _app.call("get_mastery_state", event_id)
	var championship_result := "%s · %d PTS" % [_ordinal(finish), points]
	if bool(state.get("calibrating", false)):
		return "%s · MASTERY CALIBRATING" % championship_result
	if bool(state.get("calibration_failed", false)):
		return "%s · CALIBRATION SAVE FAILED" % championship_result
	var record: Dictionary = state.get("record", {})
	if record.is_empty():
		return "%s · MASTERY OPEN" % championship_result
	return "%s · MASTERY %s %s" % [championship_result, String(record.get("medal", "none")).to_upper(), _format_time(float(record["best_race"]))]


func _briefing_mastery_status(state: Dictionary) -> String:
	if bool(state.get("calibrating", false)):
		return "CALIBRATING · TARGETS PREPARING"
	if bool(state.get("calibration_failed", false)):
		return "CALIBRATION SAVE FAILED · RETRY"
	var record: Dictionary = state.get("record", {})
	if record.is_empty():
		return "NO MEDAL · SET A TIME"
	return "%s · LAP %s · RACE %s" % [String(record.get("medal", "none")).to_upper(), _format_time(float(record["best_lap"])), _format_time(float(record["best_race"]))]


func _briefing_mastery_targets(state: Dictionary) -> String:
	if bool(state.get("calibrating", false)):
		return "CALIBRATING CIRCUIT TARGETS…"
	if bool(state.get("calibration_failed", false)):
		return "TARGETS NOT SAVED · RETRY CALIBRATION"
	var targets: Dictionary = state.get("targets", {})
	if targets.is_empty():
		return "TARGETS UNAVAILABLE"
	return "TARGETS  GOLD %s · SILVER %s · BRONZE %s" % [_format_time(float(targets["gold"])), _format_time(float(targets["silver"])), _format_time(float(targets["bronze"]))]


func show_vehicle_select(event_id: String, quick_race: bool = false) -> void:
	_screen = "vehicle_select"
	_event_id = event_id
	_quick_race = quick_race
	_clear_content()
	var event := CATALOG.get_event(event_id)
	var progress: Dictionary = _app.call("get_save_data")
	var selected_vehicle := _selected_vehicle(progress)
	if _quick_strip and not _quick_strip_vehicle_id.is_empty():
		selected_vehicle = _quick_strip_vehicle_id
	elif quick_race and not _quick_race_vehicle_id.is_empty():
		selected_vehicle = _quick_race_vehicle_id
	_current_vehicle_select_id = selected_vehicle
	var unlocked_vehicles: Array = progress.get("unlocked_vehicles", ["rustbug"])
	var roster: Array = []
	if quick_race:
		roster = _app.call("quick_race_roster")
		unlocked_vehicles = roster  # Quick Race accepts any in its roster; no championship unlock required
	else:
		roster = CATALOG.championship_vehicle_ids()
	_page.hide()
	_art_menu.set("reduced_motion", _reduced_motion_enabled())
	var context := "QUICK STRIP · YOUR MACHINE" if _quick_strip else ("QUICK RACE · YOUR MACHINE" if quick_race else String(event.get("name", "CHAMPIONSHIP")).to_upper())
	_art_menu.call("show_garage", selected_vehicle, unlocked_vehicles, context, "NEXT: TRACK" if quick_race and event_id.is_empty() else "PLAY", roster, "THE GARAGE" if quick_race else "SELECT YOUR CAR")


func show_driver(return_action: Callable = Callable()) -> void:
	_screen = "driver"
	_driver_return = return_action if return_action.is_valid() else Callable(self, "show_title")
	_preview_avatar_seed = int(_app.call("get_player_avatar_seed"))
	_render_driver()


func _render_driver() -> void:
	_clear_content()
	_content.add_theme_constant_override("separation", 2)
	var progress: Dictionary = _app.call("get_save_data")
	var player_id := String(CATALOG.player_driver_id())
	_configure_stage(&"driver", _selected_vehicle(progress), player_id)
	_app.call("preview_player_avatar", _preview_avatar_seed)
	_add_kicker("DRIVER")
	_add_heading("Who's behind the wheel?")
	_add_spacer(10)
	_add_button("SHUFFLE LOOK", Callable(self, "_shuffle_driver"))
	var saved_seed := int(_app.call("get_player_avatar_seed"))
	if _preview_avatar_seed != saved_seed:
		_add_button("KEEP THIS LOOK", Callable(self, "_keep_driver"), true)
	_add_button("BACK", Callable(self, "_leave_driver"))
	var suffix := "PORTRAIT SAVED" if _preview_avatar_seed == saved_seed else "UNSAVED LOOK"
	_footer.text = ("SAVE READ-ONLY  ·  " if bool(_app.call("is_save_read_only")) else "") + suffix
	_focus_first()


func _shuffle_driver() -> void:
	_preview_avatar_seed = int(_app.call("random_player_avatar_seed"))
	_render_driver()


func _keep_driver() -> void:
	if not bool(_app.call("save_player_avatar", _preview_avatar_seed)):
		_show_driver_save_error()
		return
	show_driver(_driver_return)


func _leave_driver() -> void:
	_app.call("preview_player_avatar", int(_app.call("get_player_avatar_seed")))
	if _driver_return.is_valid():
		_driver_return.call()
	else:
		show_title()


func _show_driver_save_error() -> void:
	var retry := Callable(self, "_keep_driver")
	var back := Callable(self, "show_driver").bind(_driver_return)
	var detail := "Save is read-only." if bool(_app.call("is_save_read_only")) else String(_app.call("get_last_save_error"))
	show_save_error("Portrait not saved", detail, retry, back)


func show_settings() -> void:
	_screen = "settings"
	_clear_content()
	_content.add_theme_constant_override("separation", 2)
	var settings: Dictionary = _app.call("get_save_data")
	_configure_stage(&"settings", _selected_vehicle(settings), "inez")
	_add_kicker("SETTINGS")
	_add_heading("Race your way")
	_add_difficulty_picker()
	_add_section("AUDIO", "")
	_add_slider("Master", float(settings["master_volume"]), "master_volume")
	_add_slider("Music", float(settings["music_volume"]), "music_volume")
	_add_slider("SFX", float(settings["sfx_volume"]), "sfx_volume")
	_add_slider("Engine", float(settings.get("engine_volume", settings["sfx_volume"])), "engine_volume")
	_add_slider("Tyres", float(settings.get("tyre_volume", settings["sfx_volume"])), "tyre_volume")
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.follow_focus = true
	_add_section("DISPLAY & COMFORT", "")
	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = bool(settings["fullscreen"])
	fullscreen.toggled.connect(func(enabled: bool) -> void: _app.call("update_setting", "fullscreen", enabled))
	_wire_button_audio(fullscreen)
	_content.add_child(fullscreen)
	var shake := CheckButton.new()
	shake.name = "ReducedCameraShake"
	shake.text = "Reduced camera shake"
	shake.button_pressed = bool(settings["reduced_camera_shake"])
	shake.toggled.connect(func(enabled: bool) -> void: _app.call("update_setting", "reduced_camera_shake", enabled))
	_wire_button_audio(shake)
	_content.add_child(shake)
	var motion := CheckButton.new()
	motion.name = "ReducedMotion"
	motion.text = "Reduced motion"
	motion.button_pressed = bool(settings.get("reduced_motion", false))
	motion.toggled.connect(func(enabled: bool) -> void: _app.call("update_setting", "reduced_motion", enabled))
	_wire_button_audio(motion)
	_content.add_child(motion)
	_add_button("BACK", Callable(self, "show_title"))
	_footer.text = ("SAVE READ-ONLY  ·  " if bool(_app.call("is_save_read_only")) else "") + BACK_HINT
	_focus_first()


func show_credits() -> void:
	_screen = "credits"
	_clear_content()
	_configure_stage(&"credits")
	_add_kicker("CREDITS & NOTICES")
	_add_heading("Pocket Circuit")
	_add_section("CREATED & PUBLISHED", "GURISITOS GAMES")
	_add_section("ENGINE", "GODOT · MIT")
	_add_section("PROCEDURAL ART", "PROCEDURAL 2D · MIT")
	_add_section("AUDIO", "GENERATED AT RUNTIME")
	_add_section("PRODUCTION", "DEVELOPER-DIRECTED · AI-ASSISTED")
	_add_copy("Original code, characters, vehicles, tracks, graphics, music and audio. Every shipped sound is generated by project code.")
	_add_copy("Licenses and provenance are included in THIRD_PARTY_NOTICES.md and ASSET_PROVENANCE.md.", SKIN.CREAM_DIM)
	_add_button("BACK", Callable(self, "show_title"))
	_footer.text = BACK_HINT
	_focus_first()


func show_save_error(title: String, detail: String, retry_action: Callable, back_action: Callable) -> void:
	_screen = "save_error"
	_clear_content()
	_configure_stage(&"title")
	_save_error_back_action = back_action
	_add_kicker("SAVE ERROR", SKIN.ORANGE)
	_add_heading(title)
	_add_copy("Pocket Circuit could not write the requested change. Existing progress remains unchanged.", SKIN.ORANGE)
	_add_quote(detail if not detail.is_empty() else "The save file could not be written. Check available disk space and folder permissions.")
	_add_button("TRY AGAIN", retry_action, true)
	_add_button("BACK", Callable(self, "_leave_save_error"))
	_footer.text = "DO NOT CLOSE THE GAME UNTIL PROGRESS IS SAVED  ·  " + BACK_HINT
	_focus_first()


func show_ending() -> void:
	_screen = "ending"
	_clear_content()
	var progress: Dictionary = _app.call("get_save_data")
	var finale: Dictionary = _app.call("get_championship_event", String(CATALOG.ACTS.back()["final_event"]))
	var opponent_ids: Array = finale.get("opponents", [])
	var rival_id := String(opponent_ids[0]) if not opponent_ids.is_empty() else ""
	_configure_stage(&"ending", _selected_vehicle(progress), CATALOG.player_driver_id(), String(finale.get("theme", "")), rival_id)
	_add_kicker("CHAMPIONSHIP COMPLETE")
	_add_heading("Champion.")
	_add_copy("Grand Household Circuit complete.", SKIN.YELLOW)
	var series_points := 0
	for act: Dictionary in CATALOG.ACTS:
		series_points += CATALOG.act_points(progress, int(act["number"]))
	_add_section("FINAL STANDINGS", "%d / %d SERIES POINTS" % [series_points, CATALOG.EVENTS.size() * 10])
	_add_section("GARAGE UNLOCK", "FLICKER · DRIFT")
	_add_button("REPLAY THE CHAMPIONSHIP", Callable(_app, "finish_ending").bind("map"), true)
	_add_button("RETURN TO TITLE", Callable(_app, "finish_ending").bind("title"))
	_footer.text = "POST-CHAMPIONSHIP REPLAY UNLOCKED"
	_focus_first()


func _leave_save_error() -> void:
	var back_action := _save_error_back_action
	_save_error_back_action = Callable()
	if back_action.is_valid():
		back_action.call()
	else:
		show_title()


func go_back() -> void:
	match _screen:
		"title":
			return
		"map", "settings", "credits", "reset_confirmation", "quick_race", "quick_strip":
			show_title()
		"driver":
			_leave_driver()
		"discovery":
			if not is_instance_valid(_discovery_panel) or not _discovery_panel.go_back():
				show_title()
		"save_error":
			_leave_save_error()
		"briefing":
			show_map()
		"vehicle_select":
			if _quick_strip:
				show_quick_strip()
			elif _quick_race:
				show_quick_race()
			else:
				show_briefing(_event_id)
		"run_board":
			show_title()
		"run_bench", "run_parts_van", "run_lockup", "run_errand":
			show_run_board()
		"ending":
			_app.call("finish_ending", "map")


func _build_base() -> void:
	layer = 100
	_root = Control.new()
	_root.name = "ApplicationShell"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = SKIN.make_theme()
	add_child(_root)
	_root.add_child(SKIN.workbench_backdrop())
	_run_backdrop = ColorRect.new()
	_run_backdrop.color = RUN_UI.BG
	_run_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_run_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_run_backdrop.hide()
	_root.add_child(_run_backdrop)
	var margin := MarginContainer.new()
	_page = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", PAGE_MARGIN)
	margin.add_theme_constant_override("margin_top", PAGE_TOP)
	margin.add_theme_constant_override("margin_right", PAGE_MARGIN)
	margin.add_theme_constant_override("margin_bottom", roundi(SKIN.BENCH_LIP) + 6)
	_root.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	margin.add_child(page)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	page.add_child(body)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_stretch_ratio = 1.12
	_scroll.custom_minimum_size = Vector2(590.0, 0.0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = false
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.custom_minimum_size = Vector2(580.0, 0.0)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 9)
	_scroll.add_child(_content)
	_stage = STAGE_SCRIPT.new() as AppShellStage
	_stage.name = "IllustrationStage"
	_stage.custom_minimum_size = Vector2(490.0, 500.0)
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.size_flags_stretch_ratio = 1.0
	body.add_child(_stage)
	var footer_row := HBoxContainer.new()
	footer_row.add_theme_constant_override("separation", 16)
	page.add_child(footer_row)
	var brand := SKIN.style_tape(Label.new(), SKIN.YELLOW, 12)
	brand.text = "POCKET CIRCUIT"
	brand.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer_row.add_child(brand)
	_footer = _label("", 12, SKIN.CREAM_DIM, true)
	_footer.autowrap_mode = TextServer.AUTOWRAP_OFF
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer_row.add_child(_footer)
	_art_menu = MENU_SCRIPT.new()
	_art_menu.name = "ChampionshipPresentation"
	_root.add_child(_art_menu)
	_art_menu.connect("action_requested", _on_art_action)
	_art_menu.connect("vehicle_selected", _on_art_vehicle_selected)
	_art_menu.connect("focus_moved", _play_ui_move)
	_art_menu.connect("presentation_ready", _report_media_screen_ready)
	_art_menu.hide()
	_route = ROUTE_SCRIPT.new()
	_route.name = "ChampionshipRoute"
	_route.hide()
	_route.connect("event_chosen", _open_event)
	_route.connect("return_chosen", _route_return)
	_route.connect("focus_moved", _play_ui_move)
	_root.add_child(_route)


func _apply_compact_button_art(button: Button) -> void:
	for state: String in SKIN.BUTTON_STATES:
		var compact := button.get_theme_stylebox(state).duplicate() as StyleBox
		compact.content_margin_left = 8.0
		compact.content_margin_right = 8.0 + SKIN.SHADOW
		compact.content_margin_top = 4.0
		compact.content_margin_bottom = 4.0 + SKIN.SHADOW
		button.add_theme_stylebox_override(state, compact)


func _clear_content() -> void:
	_page.show()
	_run_backdrop.hide()
	_footer.get_parent().show()
	_run_actions = null
	if is_instance_valid(_route):
		_route.hide()
	_art_menu.call("clear")
	_discovery_panel = null
	_entrance_generation += 1
	_save_error_back_action = Callable()
	_button_focus_chain.clear()
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.follow_focus = false
	_scroll.scroll_vertical = 0
	_scroll.set_deferred("scroll_vertical", 0)
	if _content_tween and _content_tween.is_valid():
		_content_tween.kill()
	_content.modulate = Color.WHITE
	_content.add_theme_constant_override("separation", 10)
	for child: Node in _content.get_children():
		_content.remove_child(child)
		child.queue_free()


func _configure_stage(
		mode: StringName,
		vehicle_id: String = "rustbug",
		driver_id: String = "rae",
		theme_id: String = "kitchen",
		secondary_driver_id: String = "",
		unlocked_vehicle_ids: Array = ["rustbug"]
) -> void:
	if is_instance_valid(_stage):
		_stage.visible = mode != &"title"
		_stage.configure(mode, vehicle_id, driver_id, theme_id, secondary_driver_id, unlocked_vehicle_ids)


func _on_art_vehicle_selected(vehicle_id: String) -> void:
	_current_vehicle_select_id = vehicle_id
	if _quick_strip:
		_quick_strip_vehicle_id = vehicle_id
	elif _quick_race:
		_quick_race_vehicle_id = vehicle_id


func _on_art_action(action: StringName) -> void:
	_play_ui_confirm()
	match action:
		&"championship":
			_app.call("continue_championship" if _app.call("has_championship_progress") else "request_new_championship")
		&"new_run":
			_app.call("start_new_run")
			show_run_board()
		&"your_run":
			show_run_board()
		&"quick_race":
			_app.call("open_quick_race")
		&"quick_strip":
			_app.call("open_quick_strip")
		&"discovery":
			_app.call("open_discovery")
		&"options":
			show_settings()
		&"driver":
			if _screen == "vehicle_select":
				show_driver(Callable(self, "show_vehicle_select").bind(_event_id, _quick_race))
			else:
				show_driver()
		&"credits":
			show_credits()
		&"quit":
			_app.call("quit_game")
		&"back":
			go_back()
		&"play_vehicle":
			if _quick_strip and _event_id.is_empty():
				show_quick_strip()
			elif _quick_race and _event_id.is_empty():
				show_quick_race()
			else:
				_start_current_selected_vehicle()


func _add_big_play_button(callback: Callable, disabled: bool) -> Button:
	var button := _make_button("PLAY", callback, true, disabled)
	button.custom_minimum_size = Vector2(0.0, 72.0)
	button.add_theme_font_size_override("font_size", 28)
	_content.add_child(button)
	if not disabled:
		_register_button_focus(button)
	return button


func _add_kicker(text: String, fill: Color = SKIN.YELLOW) -> void:
	var label := SKIN.style_tape(_label(text, 15, SKIN.INK), fill, 15)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_content.add_child(label)


func _add_heading(text: String) -> void:
	var label := _label(text, 36, SKIN.CREAM, true)
	label.custom_minimum_size = Vector2(0.0, 52.0)
	_content.add_child(label)


func _add_copy(text: String, color: Color = SKIN.CREAM) -> Label:
	var label := _label(text, 18, color)
	label.custom_minimum_size = Vector2(0.0, 34.0)
	_content.add_child(label)
	return label


func _add_quote(text: String) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", SKIN.card_style(SKIN.CREAM, 14.0))
	var label := _label(text, 17, SKIN.INK)
	label.custom_minimum_size = Vector2(0.0, 48.0)
	panel.add_child(label)
	_content.add_child(panel)


func _add_section(left: String, right: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var left_label := _label(left, 19, SKIN.CREAM, true)
	left_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left_label)
	var right_label := _label(right, 14, SKIN.CREAM_DIM, true)
	right_label.custom_minimum_size = Vector2(320.0, 0.0)
	right_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	right_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(right_label)
	_content.add_child(row)
	return right_label


func _add_difficulty_picker() -> OptionButton:
	## One difficulty control shared by Settings and Quick Race. It reads and
	## writes the single persisted difficulty through update_setting, so both
	## screens present the same stored value instead of duplicating state.
	_add_section("DIFFICULTY", "")
	var difficulty := OptionButton.new()
	difficulty.name = "Difficulty"
	difficulty.custom_minimum_size = Vector2(460.0, 48.0)
	var difficulty_ids := ["sunday_drive", "club_circuit", "clockwork"]
	for label: String in ["Sunday Drive · Earlier braking", "Club Circuit · Balanced", "Clockwork · Later braking"]:
		difficulty.add_item(label)
	var settings: Dictionary = _app.call("get_save_data")
	difficulty.select(maxi(0, difficulty_ids.find(String(settings.get("difficulty", "club_circuit")))))
	difficulty.item_selected.connect(func(index: int) -> void: _app.call("update_setting", "difficulty", difficulty_ids[index]))
	_wire_button_audio(difficulty)
	_content.add_child(difficulty)
	return difficulty


func _result_notice_text(summary: Dictionary) -> String:
	if bool(summary.get("mastery", false)):
		if bool(summary.get("mastery_dnf", false)):
			return "TIME TRIAL · DID NOT FINISH"
		var record: Dictionary = summary.get("mastery_record", {})
		var message := "TIME TRIAL SAVED"
		if not record.is_empty():
			message = "TIME TRIAL %s · LAP %s · RACE %s" % [String(record.get("medal", "none")).to_upper(), _format_time(float(record["best_lap"])), _format_time(float(record["best_race"]))]
		if bool(summary.get("ghost_saved", false)):
			message += " · GHOST SAVED"
		return message
	var message := "RESULT SAVED"
	if int(summary.get("points_gained", 0)) > 0:
		message += "  ·  +%d POINTS" % int(summary["points_gained"])
	if bool(summary.get("act_completed", false)):
		message += "  ·  ACT WON"
	var unlocked: Array = summary.get("unlocked_vehicles", [])
	if not unlocked.is_empty():
		message += "  ·  %s UNLOCKED" % String(CATALOG.get_vehicle(String(unlocked[0]))["name"]).to_upper()
	return message


func _add_button(text: String, callback: Callable, primary: bool = false, disabled: bool = false, node_name: String = "") -> Button:
	var button := _make_button(text, callback, primary, disabled, node_name)
	_content.add_child(button)
	if not disabled:
		_register_button_focus(button)
	return button


func _make_button(text: String, callback: Callable, primary: bool = false, disabled: bool = false, node_name: String = "") -> Button:
	var button := BUTTON_SCRIPT.new() as Button
	button.set("reduced_motion", _reduced_motion_enabled())
	if not node_name.is_empty():
		button.name = node_name
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(0.0, 44.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.disabled = disabled
	SKIN.apply_button(button, primary)
	_wire_button_audio(button)
	if callback.is_valid():
		button.pressed.connect(callback)
	return button


func _add_act_navigation(act_number: int, callback: Callable) -> Array[Button]:
	var act_numbers: Array[int] = []
	for act: Dictionary in CATALOG.ACTS:
		act_numbers.append(int(act["number"]))
	return _add_available_act_navigation(act_numbers, act_number, callback)


func _add_available_act_navigation(act_numbers: Array[int], act_number: int, callback: Callable) -> Array[Button]:
	var current_index := act_numbers.find(act_number)
	var previous_focus: Button = _button_focus_chain.back() if not _button_focus_chain.is_empty() else null
	var focusable_buttons: Array[Button] = []
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_content.add_child(row)
	var previous_disabled := current_index <= 0
	var previous_act := act_numbers[maxi(0, current_index - 1)] if not act_numbers.is_empty() else act_number
	var previous := _make_button("← PREVIOUS ACT", callback.bind(previous_act), false, previous_disabled)
	previous.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(previous)
	if not previous_disabled:
		focusable_buttons.append(previous)
	var next_disabled := current_index < 0 or current_index >= act_numbers.size() - 1
	var next_act := act_numbers[mini(act_numbers.size() - 1, current_index + 1)] if not act_numbers.is_empty() else act_number
	var next := _make_button("NEXT ACT →", callback.bind(next_act), false, next_disabled)
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(next)
	if not next_disabled:
		focusable_buttons.append(next)
	if not focusable_buttons.is_empty():
		_register_button_focus(focusable_buttons[0])
		for button: Button in focusable_buttons.slice(1):
			if previous_focus:
				button.focus_neighbor_top = button.get_path_to(previous_focus)
	if focusable_buttons.size() == 2:
		focusable_buttons[0].focus_neighbor_right = focusable_buttons[0].get_path_to(focusable_buttons[1])
		focusable_buttons[1].focus_neighbor_left = focusable_buttons[1].get_path_to(focusable_buttons[0])
	return focusable_buttons


func _add_quick_race_seed_controls(seed_status: Label) -> Array[Control]:
	var previous_focus: Button = _button_focus_chain.back() if not _button_focus_chain.is_empty() else null
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_content.add_child(row)
	var seed_edit := LineEdit.new()
	seed_edit.name = "QuickRaceSeed"
	seed_edit.text = str(_quick_race_seed)
	seed_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_edit.custom_minimum_size = Vector2(92.0, 44.0)
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.focus_mode = Control.FOCUS_ALL
	seed_edit.select_all_on_focus = true
	seed_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	seed_edit.add_theme_font_size_override("font_size", 14)
	var controls: Array[Control] = []
	for adjustment: int in [-100, -10, -1, 1, 10, 100]:
		var prefix := "+" if adjustment > 0 else ""
		var button := _make_button(
			"%s%d" % [prefix, adjustment],
			Callable(self, "_adjust_quick_race_seed").bind(adjustment, seed_edit, seed_status)
		)
		button.custom_minimum_size = Vector2(48.0, 44.0)
		button.add_theme_font_size_override("font_size", 12)
		_apply_compact_button_art(button)
		row.add_child(button)
		controls.append(button)
	var reroll := _make_button("REROLL", Callable(self, "_reroll_quick_race_seed").bind(seed_edit, seed_status))
	reroll.custom_minimum_size = Vector2(72.0, 44.0)
	reroll.add_theme_font_size_override("font_size", 12)
	_apply_compact_button_art(reroll)
	row.add_child(reroll)
	controls.append(reroll)
	row.add_child(seed_edit)
	controls.append(seed_edit)
	seed_edit.text_submitted.connect(
		func(text: String) -> void: _commit_quick_race_seed_text(text, seed_edit, seed_status)
	)
	seed_edit.focus_exited.connect(
		func() -> void: _commit_quick_race_seed_text(seed_edit.text, seed_edit, seed_status)
	)
	_register_button_focus(controls[0] as Button)
	for index in controls.size():
		var control := controls[index]
		if index > 0 and previous_focus:
			control.focus_neighbor_top = control.get_path_to(previous_focus)
		if index > 0:
			control.focus_neighbor_left = control.get_path_to(controls[index - 1])
		if index < controls.size() - 1:
			control.focus_neighbor_right = control.get_path_to(controls[index + 1])
	return controls


func _complete_focus_row(focusable_controls: Array, following_control: Control) -> void:
	for control: Control in focusable_controls.slice(1):
		control.focus_neighbor_bottom = control.get_path_to(following_control)


func _register_button_focus(button: Button) -> void:
	if not _button_focus_chain.is_empty():
		var previous: Button = _button_focus_chain.back()
		previous.focus_neighbor_bottom = previous.get_path_to(button)
		button.focus_neighbor_top = button.get_path_to(previous)
	_button_focus_chain.append(button)


func _add_slider(label_text: String, value: float, setting_key: String) -> void:
	var row := HBoxContainer.new()
	var label := _label(label_text, 18, SKIN.CREAM, true)
	label.custom_minimum_size = Vector2(140.0, 0.0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(420.0, 36.0)
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = value * 100.0
	slider.value_changed.connect(func(new_value: float) -> void: _app.call("update_setting", setting_key, new_value / 100.0))
	row.add_child(slider)
	_content.add_child(row)


func _add_spacer(height: float) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	_content.add_child(spacer)


func _label(text: String, size: int, color: Color, display: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	SKIN.style_label(label, size, color, display)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _selected_vehicle(progress: Dictionary) -> String:
	return String(progress.get("selected_vehicle", "rustbug"))


func _focus_first() -> void:
	_queue_content_entrance()
	_grab_first_focus_after_layout(_entrance_generation)


func _grab_first_focus_after_layout(generation: int) -> void:
	await get_tree().process_frame
	if generation == _entrance_generation:
		_grab_first_focus()
		_report_media_screen_ready()


func _grab_first_focus() -> void:
	_scroll.scroll_vertical = 0
	for node: Node in _content.find_children("*", "BaseButton", true, false):
		var button := node as BaseButton
		if button and not button.is_queued_for_deletion() and not button.disabled and button.visible:
			button.grab_focus()
			return


func _grab_button_focus(button: BaseButton) -> void:
	if is_instance_valid(button) and not button.disabled and button.visible:
		button.grab_focus()


func _grab_button_focus_after_layout(button: BaseButton, generation: int) -> void:
	await get_tree().process_frame
	if generation == _entrance_generation:
		_grab_button_focus(button)
		_report_media_screen_ready()


func _report_media_screen_ready() -> void:
	if "--media-capture" in OS.get_cmdline_user_args():
		print("MEDIA_SCREEN_READY " + _screen)


func _wire_button_audio(button: BaseButton) -> void:
	var focus_callback := Callable(self, "_play_ui_move")
	var press_callback := Callable(self, "_play_ui_confirm")
	if not button.focus_entered.is_connected(focus_callback):
		button.focus_entered.connect(focus_callback)
	if not button.pressed.is_connected(press_callback):
		button.pressed.connect(press_callback)


func _play_ui_move() -> void:
	_play_sfx(&"ui_move", 0.62)


func _play_ui_confirm() -> void:
	_play_sfx(&"ui_confirm", 0.78)


func _play_sfx(sound_name: StringName, volume_scale: float = 1.0) -> void:
	if is_instance_valid(_app) and _app.has_method("play_sfx"):
		_app.call("play_sfx", sound_name, volume_scale)


func _queue_content_entrance() -> void:
	call_deferred("_run_content_entrance", _entrance_generation)


func _run_content_entrance(generation: int) -> void:
	if generation != _entrance_generation or not is_instance_valid(_content):
		return
	if _reduced_motion_enabled():
		_content.modulate = Color.WHITE
		return
	var resting_position := _content.position
	_content.position = resting_position + Vector2(-18.0, 0.0)
	_content.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_content_tween = create_tween().set_parallel(true)
	_content_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_content_tween.tween_property(_content, "position", resting_position, 0.18)
	_content_tween.tween_property(_content, "modulate:a", 1.0, 0.16)


func _reduced_motion_enabled() -> bool:
	if not is_instance_valid(_app) or not _app.has_method("get_save_data"):
		return false
	var settings: Dictionary = _app.call("get_save_data")
	return bool(settings.get("reduced_motion", false))


func _open_event(event_id: String) -> void:
	_play_ui_confirm()
	show_briefing(event_id)


func _route_return() -> void:
	_play_ui_confirm()
	show_title()


func _show_map_act(act_number: int) -> void:
	show_map({}, act_number)


func _reset_quick_race_state() -> void:
	_quick_race = false
	_quick_strip = false
	_quick_race_theme = StringName(GENERATED_CIRCUITS.THEMES[0])
	_quick_race_room = &"classic"
	_quick_race_seed = 875
	_quick_race_reverse = false
	_quick_race_length_tier = "standard"
	_quick_race_vehicle_id = ""
	_quick_strip_vehicle_id = ""
	_quick_identity_heading = null
	_quick_identity_summary = null


func _adjust_quick_race_seed(adjustment: int, seed_edit: LineEdit, seed_status: Label) -> void:
	_quick_race_seed = clampi(_quick_race_seed + adjustment, 0, 999999)
	_refresh_quick_race_seed(seed_edit, seed_status)


func _reroll_quick_race_seed(seed_edit: LineEdit, seed_status: Label) -> void:
	_roll_quick_race()
	_refresh_quick_race_seed(seed_edit, seed_status)


func _commit_quick_race_seed_text(text: String, seed_edit: LineEdit, seed_status: Label) -> void:
	var normalized := text.strip_edges()
	if normalized.is_valid_int():
		_quick_race_seed = clampi(int(normalized), 0, 999999)
	_refresh_quick_race_seed(seed_edit, seed_status)


func _refresh_quick_race_seed(seed_edit: LineEdit, seed_status: Label) -> void:
	_quick_race_room = StringName(_app.call("circuit_room_for_seed", _quick_race_seed))
	seed_edit.text = str(_quick_race_seed)
	seed_status.text = "SEED %d · %s CANVAS" % [_quick_race_seed, String(_quick_race_room).to_upper()]
	_configure_stage(&"map", _quick_race_vehicle_id, "rae", String(_quick_race_theme))
	_refresh_quick_identity_labels()


func _current_quick_identity() -> Dictionary:
	# route_shape only when the Quick Strip toggle is on: mock apps implement the
	# five-argument form, and the circuit path is the long-standing contract.
	if _quick_strip:
		return _app.call(
			"generated_circuit_identity",
			_quick_race_theme,
			_quick_race_room,
			_quick_race_seed,
			_quick_race_reverse,
			_quick_race_length_tier,
			"strip"
		)
	return _app.call(
		"generated_circuit_identity",
		_quick_race_theme,
		_quick_race_room,
		_quick_race_seed,
		_quick_race_reverse,
		_quick_race_length_tier
	)


func _refresh_quick_identity_labels() -> void:
	var identity := _current_quick_identity()
	if is_instance_valid(_quick_identity_heading):
		_quick_identity_heading.text = String(identity.get("display_name", "Build a circuit"))
	if is_instance_valid(_quick_identity_summary):
		_quick_identity_summary.text = String(identity.get("summary", ""))


func _roll_quick_race() -> void:
	if _quick_race_theme_cursor < 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_quick_race_theme_cursor = rng.randi_range(0, GENERATED_CIRCUITS.THEMES.size() - 1)
	_quick_race_theme = StringName(GENERATED_CIRCUITS.THEMES[_quick_race_theme_cursor])
	_quick_race_theme_cursor = (_quick_race_theme_cursor + 1) % GENERATED_CIRCUITS.THEMES.size()
	var draw: Dictionary = _app.call("random_circuit_seed", _quick_race_theme)
	_quick_race_room = StringName(draw.get("room", "classic"))
	_quick_race_seed = int(draw.get("seed", 0))


func _start_quick_race() -> void:
	var progress: Dictionary = _app.call("get_save_data")
	var vehicle_id := _quick_race_vehicle_id if not _quick_race_vehicle_id.is_empty() else _selected_vehicle(progress)
	var qids: Array[String] = _app.call("quick_race_roster")
	if not vehicle_id in qids:
		vehicle_id = qids[0] if not qids.is_empty() else "rustbug"
	_app.call("start_circuit_race", _quick_race_theme, _quick_race_room, _quick_race_seed, vehicle_id, _quick_race_reverse, _quick_race_length_tier)


func _start_quick_strip() -> void:
	var progress: Dictionary = _app.call("get_save_data")
	var vehicle_id := _quick_strip_vehicle_id if not _quick_strip_vehicle_id.is_empty() else _selected_vehicle(progress)
	var qids: Array[String] = _app.call("quick_race_roster")
	if not vehicle_id in qids:
		vehicle_id = qids[0] if not qids.is_empty() else "rustbug"
	_app.call("start_strip_race", _quick_race_theme, _quick_race_room, _quick_race_seed, vehicle_id, _quick_race_reverse, _quick_race_length_tier)


func _start_with_vehicle(vehicle_id: String) -> void:
	_app.call("start_race", _event_id, vehicle_id, _quick_race)


func _start_current_selected_vehicle() -> void:
	if not _current_vehicle_select_id.is_empty():
		_start_with_vehicle(_current_vehicle_select_id)


func _start_mastery_selected_vehicle() -> void:
	if not _event_id.is_empty() and not _current_vehicle_select_id.is_empty():
		_app.call("start_mastery_run", _event_id, _current_vehicle_select_id)


func _format_time(total_seconds: float) -> String:
	if total_seconds <= 0.0:
		return "--:--.-"
	return "%02d:%04.1f" % [int(total_seconds / 60.0), fmod(total_seconds, 60.0)]


func _ordinal(value: int) -> String:
	match value:
		1:
			return "1ST"
		2:
			return "2ND"
		3:
			return "3RD"
		_:
			return "%dTH" % value

func _on_run_node_pressed(node_id: String) -> void:
	_play_ui_confirm()
	var node_type := ""
	var sess_var: Variant = _app.call("current_run_session")
	var sess: RunSession = sess_var as RunSession
	if sess != null and sess.current_map != null:
		var node: Dictionary = sess.current_map.get_node(node_id) as Dictionary
		node_type = String(node.get("type", ""))
	if node_type == "race" or node_type == "act_rival":
		# Race nodes hand over to the real race flow; the result resolves the run.
		_app.call("start_run_race", node_id)
		return
	if node_type == "rival":
		_app.call("start_run_rival", node_id)
		return
	if not bool(_app.call("enter_run_node", node_id)):
		return
	match node_type:
		"bench":
			show_run_bench()
		"parts_van":
			show_run_parts_van()
		"lockup":
			show_run_lockup()
		"errand":
			show_run_errand()
		_:
			# position-only default for unknown node types
			show_run_board()


func _on_new_run_pressed() -> void:
	_app.call("start_new_run")
	show_run_board()


func _on_save_run_again() -> void:
	_play_ui_confirm()
	_app.call("persist_current_run")
	if _app.call("current_run_session") == null:
		show_title()
	else:
		show_run_board()


func _on_abandon_run() -> void:
	_app.call("abandon_run")
	show_title()
