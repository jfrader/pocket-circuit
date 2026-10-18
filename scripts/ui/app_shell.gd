extends CanvasLayer

const CATALOG := preload("res://data/championship/catalog.gd")
const STAGE_SCRIPT := preload("res://scripts/ui/app_shell_stage.gd")
const RUN_MAP_VIEW := preload("res://scripts/ui/run_map_view.gd")
const RUN_BOARD_SCENE := preload("res://scripts/ui/run_board_scene.gd")
const RUN_BOARD_INTRO := preload("res://scripts/ui/run_board_intro.gd")
const RUN_BENCH_SCENE := preload("res://scripts/ui/run_bench_scene.gd")
const RUN_VAN_SCENE := preload("res://scripts/ui/run_van_scene.gd")
const RUN_LOCKUP_SCENE := preload("res://scripts/ui/run_lockup_scene.gd")
const RUN_ERRAND_SCENE := preload("res://scripts/ui/run_errand_scene.gd")
const RUN_OFFER_SCENE := preload("res://scripts/ui/run_offer_scene.gd")
const RUN_BOARD_IDENTITY := preload("res://scripts/ui/run_board_identity.gd")
const RUN_STOP_CAR := preload("res://scripts/ui/run_stop_car.gd")
const RUN_MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")
const RUN_UI := preload("res://scripts/ui/run_ui.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const MENU_SCRIPT := preload("res://scripts/ui/championship_menu.gd")
const ROUTE_SCRIPT := preload("res://scripts/ui/championship_route_menu.gd")
const BUTTON_SCRIPT := preload("res://scripts/ui/motorsport_button.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const DISCOVERY_PANEL := preload("res://scripts/ui/circuit_discovery_panel.gd")
const RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const GENERATED_CIRCUITS := preload("res://scripts/race/generated_circuit_identity.gd")
const RUN_SESSION := preload("res://scripts/progression/run_session.gd")
const NIGHT_TRANSITION := preload("res://scripts/ui/night_transition.gd")

const PAGE_MARGIN := 48
const PAGE_TOP := 28
const BACK_HINT := "ESC / B  BACK"
const STEAM_DROP_MARGIN := 24.0
const STEAM_DROP_GAP := 8.0
const RUN_STATE_POSITION := Vector2(24, 58)
const RUN_STATE_WIDTH := 380.0
const TRANSITION_KICKERS := {
	"title": "POCKET CIRCUIT", "vehicle_select": "THE GARAGE",
	"run_bench": "THE BENCH", "run_parts_van": "PARTS VAN",
	"run_lockup": "THE LOCKUP", "run_errand": "THE ERRAND",
	"run_offer": "THE OFFER", "ending": "CHAMPIONSHIP COMPLETE",
	"run_driving_intro": "DRIVING CONTROLS",
}

var _app: Node
var _root: Control
var _scroll: ScrollContainer
var _content: VBoxContainer
var _stage: AppShellStage
var _route: Control
var _footer: Label
var _run_backdrop: ColorRect
var _run_intro: Control
var _run_intro_pending := false
var _driving_intro: Control
var _run_actions: BoxContainer
## The board's map, the picked stop's card, and whether the car is driving to a stop.
var _run_board: RUN_MAP_VIEW
var _run_stop_card: VBoxContainer
var _run_going := false
## The run stats last shown, so the next screen animates what changed.
var _run_stats_seen: Dictionary = {}
var _button_focus_chain: Array[Button] = []
var _screen := "title":
	set(value):
		_screen = value
		if is_instance_valid(_root):
			_present_screen_transition.call_deferred()
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
var _night_transition: CanvasLayer
var _last_transition_destination := "title"

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
	_add_copy("Best finishes, act wins and championship car unlocks will be erased.")
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
	var preserve_route := _screen == "vehicle_select" and _quick_race and not _quick_strip
	_screen = "quick_race"
	_event_id = ""
	_quick_race = true
	_quick_strip = false
	if not preserve_route:
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
	_stage.hide()
	_add_kicker("QUICK RACE · RESULTS DO NOT SAVE")
	var quick_identity: Dictionary = _current_quick_identity()
	if _app.has_method("prewarm_generated_circuit"):
		_app.call("prewarm_generated_circuit", GENERATED_CIRCUITS.apply_to_event(quick_identity))
	_quick_identity_heading = _label(String(quick_identity.get("display_name", "Build a circuit")), 32, SKIN.CREAM, true)
	_quick_identity_heading.custom_minimum_size = Vector2(0.0, 44.0)
	_quick_identity_heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	_quick_identity_heading.clip_text = true
	_content.add_child(_quick_identity_heading)
	_quick_identity_summary = _label(_quick_preview_summary(quick_identity), 13, SKIN.CREAM_DIM)
	_quick_identity_summary.name = "QuickCircuitSummary"
	_quick_identity_summary.max_lines_visible = 3
	_quick_identity_summary.clip_text = true
	_quick_identity_summary.size.x = _content.custom_minimum_size.x
	_quick_identity_summary.custom_minimum_size = Vector2(0.0, 76.0)
	_content.add_child(_quick_identity_summary)
	_register_button_focus(_add_difficulty_picker())
	var play_button := _add_big_play_button(Callable(self, "_start_quick_race"), false)
	var seed_controls: Array[Control] = []
	if OS.is_debug_build():
		var seed_status := _add_section("DEVELOPER SEED", "SEED %d" % _quick_race_seed)
		seed_controls = _add_quick_race_seed_controls(seed_status)
	_add_button("CHANGE CAR · %s" % String(CATALOG.get_vehicle(_quick_race_vehicle_id).get("name", "Rustbug")).to_upper(), Callable(self, "show_vehicle_select").bind("", true))
	_add_button("BACK TO TITLE", Callable(self, "show_title"))
	_footer.text = "EXHIBITION RESULTS DO NOT SAVE  ·  " + BACK_HINT
	if not seed_controls.is_empty():
		_complete_focus_row(seed_controls, play_button)
	_queue_content_entrance()
	_grab_button_focus_after_layout(play_button, _entrance_generation)


func show_quick_strip(_requested_act: int = 0) -> void:
	var preserve_route := _screen == "vehicle_select" and _quick_strip
	_screen = "quick_strip"
	_event_id = ""
	_quick_strip = true
	_quick_race = false
	if not preserve_route:
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
	_stage.hide()
	_add_kicker("QUICK STRIP · RESULTS DO NOT SAVE")
	var quick_identity: Dictionary = _current_quick_identity()
	_quick_identity_heading = _label(String(quick_identity.get("display_name", "Build a circuit")), 32, SKIN.CREAM, true)
	_quick_identity_heading.custom_minimum_size = Vector2(0.0, 44.0)
	_quick_identity_heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	_quick_identity_heading.clip_text = true
	_content.add_child(_quick_identity_heading)
	_quick_identity_summary = _label(_quick_preview_summary(quick_identity), 13, SKIN.CREAM_DIM)
	_quick_identity_summary.name = "QuickCircuitSummary"
	_quick_identity_summary.max_lines_visible = 3
	_quick_identity_summary.clip_text = true
	_quick_identity_summary.size.x = _content.custom_minimum_size.x
	_quick_identity_summary.custom_minimum_size = Vector2(0.0, 76.0)
	_content.add_child(_quick_identity_summary)
	_register_button_focus(_add_difficulty_picker())
	var play_button := _add_big_play_button(Callable(self, "_start_quick_strip"), false)
	var seed_controls: Array[Control] = []
	if OS.is_debug_build():
		var seed_status := _add_section("DEVELOPER SEED", "SEED %d" % _quick_race_seed)
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
	var sess_var: Variant = _app.call("run_board_session")
	var sess: RunSession = sess_var as RunSession
	# A car won on a night that is still going is offered before the next stop.
	if sess != null and not sess.pending_offer.is_empty() and not sess.is_failed() and not sess.is_complete():
		show_run_offer()
		return
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
	var night_over := sess.is_failed() or sess.is_complete()
	if not night_over:
		_page.add_theme_constant_override("margin_left", roundi(RUN_BOARD_SCENE.PAGE_INSET.x))
		_page.add_theme_constant_override("margin_right", roundi(RUN_BOARD_SCENE.PAGE_INSET.x))
		_page.add_theme_constant_override("margin_top", roundi(RUN_BOARD_SCENE.PAGE_INSET.y))
		_page.add_theme_constant_override("margin_bottom", 8)
		_content.add_theme_constant_override("separation", 8)
	var tabletop := RUN_BOARD_SCENE.new()
	tabletop.name = "RunTabletop"
	tabletop.act = sess.current_map.act
	tabletop.scene_mode = &"night_won" if sess.is_complete() else &"night_lost" if sess.is_failed() else &"board"
	tabletop.car_id = sess.current_car_id
	tabletop.reduced_motion = _reduced_motion_enabled()
	tabletop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_run_backdrop.add_child(tabletop)
	if night_over:
		var hero := tabletop.get_node("WinnerCar" if sess.is_complete() else "SolitaryCar") as TextureRect
		hero.texture = IDENTITIES.car_texture_with_wear(sess.current_car_id, sess.run_state.get_car_wear(sess.current_car_id), RUN_MATERIALS.HERO_PIXEL_SCALE, int(RUN_BOARD_SCENE.HERO_LENGTH[tabletop.scene_mode]))
	tabletop.arrive()
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 76 if night_over else RUN_BOARD_SCENE.COLUMN_GAP)
	_content.add_child(columns)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	columns.add_child(left)
	var board := RUN_MAP_VIEW.new()
	board.name = "RunBoard"
	board.tabletop = true
	if not night_over:
		board.map_extent = RUN_BOARD_SCENE.MAP_SIZE
		board.marker_scale = RUN_BOARD_SCENE.MARKER_SCALE
	board.reduced_motion = _reduced_motion_enabled()
	left.add_child(board)
	if not night_over:
		var instructions := RUN_UI.label(RUN_UI.BOARD_CONTROLS, 11, RUN_BOARD_SCENE.CHALK_CAPTION)
		instructions.add_theme_stylebox_override("normal", RUN_BOARD_SCENE.label_tape())
		left.add_child(instructions)
		board.focus_changed.connect(tabletop.set_focus)
	board.configure(sess, not night_over, IDENTITIES.car_texture(sess.current_car_id))
	if night_over:
		board.hide_route_visuals()
	_run_board = board
	if _app.has_method("prewarm_run_stops"):
		_app.call("prewarm_run_stops")
	var detail := VBoxContainer.new()
	detail.name = "RunDetail"
	detail.custom_minimum_size.x = 420 if night_over else RUN_BOARD_SCENE.DETAIL_WIDTH
	detail.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	detail.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	detail.add_theme_constant_override("separation", 6)
	if night_over:
		columns.add_child(detail)
	else:
		var slot := MarginContainer.new()
		slot.name = "RunDetailSlot"
		slot.custom_minimum_size.x = RUN_BOARD_SCENE.DETAIL_WIDTH
		for edge: String in ["left", "right"]:
			slot.add_theme_constant_override("margin_" + edge, RUN_BOARD_SCENE.DETAIL_OUTSET)
		columns.add_child(slot)
		detail.custom_minimum_size.x = RUN_BOARD_SCENE.DETAIL_WIDTH - RUN_BOARD_SCENE.DETAIL_OUTSET * 2
		slot.add_child(detail)
	var chalkboard := RUN_BOARD_SCENE.new()
	chalkboard.name = "RunChalkboard"
	chalkboard.chalkboard = true
	chalkboard.refined_cards = not night_over
	chalkboard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chalkboard.show_behind_parent = true
	detail.add_child(chalkboard)
	var chalk_inset := MarginContainer.new()
	chalk_inset.name = "ChalkboardInset"
	for edge: String in ["left", "right", "top", "bottom"]:
		chalk_inset.add_theme_constant_override("margin_" + edge, RUN_BOARD_SCENE.CHALK_PADDING)
	detail.add_child(chalk_inset)
	var chalk_content := VBoxContainer.new()
	chalk_content.add_theme_constant_override("separation", 6)
	chalk_inset.add_child(chalk_content)
	var act_label := RUN_UI.label("THE RUN · ACT %d / %d · %s" % [sess.current_map.act, RunSession.FINAL_ACT, String(RUN_UI.ROOMS[sess.current_map.act]).to_upper()], 12, SKIN.CREAM, true)
	if not night_over:
		act_label.name = "RunMetadata"
		act_label.text = "THE RUN · ACT %d / %d\n%s" % [sess.current_map.act, RunSession.FINAL_ACT, String(RUN_UI.ROOMS[sess.current_map.act]).to_upper()]
	act_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	act_label.visible = not night_over
	chalk_content.add_child(act_label)
	_run_stats(chalk_content, sess)
	if not night_over:
		var state_lines := {}
		if sess.pending_chaser != null:
			var hauled_car := String(sess.pending_chaser.get("haul_vehicle_id", sess.current_car_id))
			state_lines["RunHaulStatus"] = "HAULING %s - CHASED ON THE NEXT CONNECTOR" % RUN_UI.car_name(hauled_car).to_upper()
		if sess.towed_to_bench:
			state_lines["RunTowStatus"] = "TOWED - THE NEXT BENCH VISIT IS SPENT"
		if not state_lines.is_empty():
			var state_labels := VBoxContainer.new()
			state_labels.name = "RunStateLabels"
			state_labels.position = RUN_STATE_POSITION
			state_labels.custom_minimum_size.x = RUN_STATE_WIDTH
			state_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
			board.add_child(state_labels)
			for node_name: String in state_lines:
				var status := RUN_UI.label(state_lines[node_name], 12, SKIN.CREAM)
				status.name = node_name
				status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				status.add_theme_stylebox_override("normal", RUN_BOARD_SCENE.label_tape())
				state_labels.add_child(status)
		RUN_BOARD_SCENE.compact_labels(chalk_content)
	RUN_BOARD_SCENE.chalk_labels(chalk_content)
	if not night_over:
		RUN_BOARD_SCENE.quiet_captions(chalk_content, RUN_BOARD_SCENE.CHALK_CAPTION)
	_run_stop_card = VBoxContainer.new()
	_run_stop_card.name = "RunStop"
	_run_stop_card.add_theme_constant_override("separation", 6 if night_over else 8)
	_run_stop_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	detail.add_child(_run_stop_card)
	_run_actions = detail
	var unsaved := String(_app.get("run_save_error"))
	if night_over:
		_run_stop_card.add_child(RUN_UI.label("NIGHT OVER", 12, RUN_UI.AMBER, true))
		var verdict := "YOU LEFT THE NIGHT"
		if sess.is_complete():
			verdict = "ALL ACT RIVALS DEFEATED"
		elif RunState.is_worn_out(sess.run_state.get_car_wear(sess.current_car_id)):
			verdict = "THE CAR GAVE OUT"
		elif sess.failed and String(sess.current_node().get("type", "")) == "act_rival" and sess.resolved_nodes.has(sess.current_node_id):
			verdict = "DEFEATED BY THE ACT RIVAL"
		var ending := RUN_UI.label(verdict, 20, RUN_UI.MUTED)
		ending.name = "NightVerdict"
		ending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_run_stop_card.add_child(ending)
		var safe := {}
		for car: Dictionary in sess.collection_safe_cars():
			safe[String(car["id"])] = true
		var banked := safe.size()
		var impounded := sess.impounded_cars.size()
		var lost := sess.won_cars().size() - banked - impounded
		var haul: Array[String] = []
		if banked > 0:
			haul.append("BANKED: %d %s" % [banked, "CAR" if banked == 1 else "CARS"])
		if impounded > 0:
			haul.append("IMPOUNDED: %d %s" % [impounded, "CAR" if impounded == 1 else "CARS"])
		if lost > 0:
			haul.append("LOST: %d %s" % [lost, "CAR" if lost == 1 else "CARS"])
		var haul_summary := RUN_UI.label(" - ".join(haul) if not haul.is_empty() else "NO HAUL", 14, RUN_UI.MUTED)
		haul_summary.name = "HaulSummary"
		haul_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_run_stop_card.add_child(haul_summary)
		for car: Dictionary in sess.won_cars():
			var status := "BANKED · " if safe.has(String(car["id"])) else ("IMPOUNDED · " if sess.impounded_cars.has(String(car["id"])) else "LOST · ")
			var recap := RUN_UI.label(status + RUN_UI.car_name(String(car["id"])).to_upper(), 14, RUN_UI.MUTED)
			recap.name = "HaulRecap_" + String(car["id"])
			recap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_run_stop_card.add_child(recap)
	var haul_note := String(_app.get("run_haul_note"))
	if not haul_note.is_empty():
		var note := RUN_UI.label(haul_note, 14, RUN_UI.AMBER, true)
		note.name = "HaulNote"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_child(note)
	if not unsaved.is_empty():
		detail.add_child(RUN_UI.label("NOT SAVED · " + unsaved.to_upper(), 12, RUN_UI.AMBER, true))
		if not bool(_app.call("is_save_read_only")):
			_run_action("SAVE AGAIN", Callable(self, "_on_save_run_again"), night_over, false, "ActionSaveAgain")
	if night_over:
		_run_action("NEW RUN", Callable(self, "_on_new_run_pressed"), unsaved.is_empty(), false, "ActionNewRun")
		_run_action("VIEW GARAGE", Callable(self, "show_vehicle_select").bind("", true), false, false, "ActionViewGarage")
	var secondary := HBoxContainer.new()
	secondary.add_theme_constant_override("separation", 8)
	detail.add_child(secondary)
	_run_actions = secondary
	if not night_over:
		_run_action("ABANDON RUN", Callable(self, "_on_abandon_run"), false, false, "ActionAbandon")
		_run_action("?", Callable(self, "_show_run_intro").bind(tabletop, board), false, false, "ActionHelp")
	_run_action("BACK", Callable(self, "show_title"), false, false, "ActionBack")
	_run_actions = detail
	if night_over:
		RUN_UI.spacer(_content, 10)
	var legend := RUN_UI.legend(sess.current_map)
	legend.visible = not night_over
	RUN_BOARD_SCENE.chalk_labels(legend)
	legend.draw.connect(func() -> void: SKIN.draw_tape(legend, legend.size * 0.5, legend.size + Vector2(8, 8), 0.0, Color("27332f")))
	_content.add_child(legend)
	if night_over:
		RUN_BOARD_SCENE.ink_labels(_run_stop_card)
	_queue_content_entrance()
	if night_over:
		_grab_button_focus_after_layout(_button_focus_chain[0], _entrance_generation)
		return
	board.stop_selected.connect(_show_run_stop.bind(sess))
	board.stop_selected.connect(func(_stop_id: String) -> void: _play_ui_move())
	board.stop_confirmed.connect(_go_to_run_stop.bind(true))
	var first := sess.current_node_id if sess.is_stop_pending() else String(sess.available_nodes()[0]["id"]) if not sess.available_nodes().is_empty() else sess.current_node_id
	board.preview(first)
	_grab_button_focus_after_layout(board.marker(first), _entrance_generation)
	if _run_intro_pending:
		_run_intro_pending = false
		if not bool((_app.call("get_save_data") as Dictionary).get("run_intro_seen", true)):
			_show_run_intro(tabletop, board)


func _show_run_intro(tabletop: Control, board: Control) -> void:
	if is_instance_valid(_run_intro):
		return
	var note := RUN_BOARD_INTRO.new()
	note.name = "RunIntro"
	note.reduced_motion = _reduced_motion_enabled()
	var marker: Button = board.call("marker", board.call("selected_id"))
	if marker.position.x + marker.size.x * 0.5 < RUN_BOARD_SCENE.MAP_SIZE.x * 0.5:
		note.anchor_position.x = RUN_BOARD_SCENE.PAGE_INSET.x + RUN_BOARD_SCENE.MAP_SIZE.x - RUN_BOARD_INTRO.NOTE_RECT.size.x - RUN_BOARD_INTRO.EDGE_MARGIN
	_run_intro = note
	note.dismissed.connect(func() -> void:
		_run_intro = null)
	tabletop.add_child(note)
	board.connect("stop_selected", note.dismiss.unbind(1))
	for node: Node in _content.find_children("*", "Button", true, false):
		if node.name != "ActionHelp":
			(node as Button).pressed.connect(note.dismiss)


func _dismiss_run_intro() -> void:
	if is_instance_valid(_run_intro):
		_run_intro.call("dismiss")


## The run's stats, animating what changed since they were last shown.
func _run_stats(host: VBoxContainer, sess: RunSession) -> void:
	RUN_UI.stats(host, sess, _run_stats_seen, _reduced_motion_enabled())
	_run_stats_seen = RUN_UI.stats_snapshot(sess)


## The picked stop's card: what it is, what it pays and costs, its circuit when
## it is raced, and the button that goes there when it can be reached.
func _show_run_stop(stop_id: String, sess: RunSession) -> void:
	if not is_instance_valid(_run_stop_card):
		return
	for child: Node in _run_stop_card.get_children():
		_run_stop_card.remove_child(child)
		child.queue_free()
	var node: Dictionary = sess.current_map.get_node(stop_id)
	var kind := String(node.get("type", ""))
	var reachable := _run_board.is_reachable(stop_id)
	var state := "NEXT STOP" if reachable else "DONE" if sess.resolved_nodes.has(stop_id) else "YOU ARE HERE" if stop_id == sess.current_node_id else "OUT OF REACH"
	RUN_UI.spacer(_run_stop_card, 6)
	_run_stop_card.add_child(RUN_UI.label(state, 11, RUN_UI.AMBER if reachable else RUN_UI.MUTED, true))
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 14)
	title.add_child(RUN_UI.icon(kind, 34))
	var title_name := RUN_UI.label(String(RUN_UI.TYPES[kind]["name"]), 38)
	title_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(title_name)
	# Race-type stops show the car they put against you, beside the stop's name.
	var car_look := RUN_BOARD_IDENTITY.look(sess, stop_id)
	if not car_look.is_empty():
		title.add_child(RUN_STOP_CAR.new(car_look))
	_run_stop_card.add_child(title)
	var line := RUN_UI.label(String(RUN_UI.TYPES[kind]["copy"]), 18, RUN_UI.MUTED)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_run_stop_card.add_child(line)
	var circuit: Dictionary = _app.call("run_stop_circuit", stop_id) if kind in RunSession.RACE_NODE_TYPES else {}
	_run_stop_card.add_child(RUN_BOARD_SCENE.facts(RUN_UI.stop_facts(kind, sess, circuit)))
	RUN_UI.spacer(_run_stop_card, 4)
	var go := RUN_UI.action(String(RUN_UI.GO_LABELS[kind]), true, not reachable)
	go.name = "RunGo"
	go.pressed.connect(_go_to_run_stop.bind(stop_id, false))
	_wire_button_audio(go)
	_run_stop_card.add_child(go)
	RUN_BOARD_SCENE.ink_labels(_run_stop_card)
	RUN_BOARD_SCENE.quiet_captions(_run_stop_card, RUN_BOARD_SCENE.PAPER_CAPTION)
	RUN_BOARD_SCENE.compact_labels(_run_stop_card)
	_link_board_focus(stop_id)
	RUN_UI.stagger_in(_run_stop_card.get_children(), _reduced_motion_enabled())


## The map's right-hand column leads into the stop's go button (or the first
## live action when it is out of reach), and back to the picked stop.
func _link_board_focus(stop_id: String) -> void:
	var exits: Array[Control] = []
	for node: Node in _content.find_children("*", "Button", true, false):
		var button := node as Button
		if not button.has_meta("stop_id") and button.focus_mode != Control.FOCUS_NONE and button.is_inside_tree():
			exits.append(button)
	if exits.is_empty():
		return
	var picked := _run_board.marker(stop_id)
	for marker: Button in _run_board.right_edge_markers():
		marker.focus_neighbor_right = marker.get_path_to(exits[0])
	for exit: Control in exits:
		exit.focus_neighbor_left = exit.get_path_to(picked)


## Drives the car to the stop on the map, then opens it (a race starts loading).
## Leaving the board on the way drops the go.
func _go_to_run_stop(stop_id: String, play_confirm: bool) -> void:
	if _run_going or not is_instance_valid(_run_board) or not _run_board.is_reachable(stop_id):
		return
	if is_instance_valid(_driving_intro):
		return
	var session: RunSession = _app.call("current_run_session")
	if session != null and session.pending_chaser == null and String(session.current_map.get_node(stop_id).get("type", "")) in ["race", "rival", "act_rival"] and not bool((_app.call("get_save_data") as Dictionary).get("run_intro_seen", true)):
		_show_driving_intro(stop_id, play_confirm)
		return
	_run_going = true
	if play_confirm:
		_play_ui_confirm()
	var sess: RunSession = _app.call("current_run_session")
	if sess != null and sess.pending_chaser != null:
		_app.call("start_run_sprint", stop_id)
		_run_going = false
		return
	var generation := _entrance_generation
	var drive := _run_board.travel_to(stop_id)
	if drive > 0.0:
		await get_tree().create_timer(drive).timeout
	if generation != _entrance_generation or not is_instance_valid(_run_board):
		return
	_run_going = false
	_on_run_node_pressed(stop_id)
	if generation == _entrance_generation and is_instance_valid(_run_board):
		_run_board.reset_token()


func _show_driving_intro(stop_id: String, play_confirm: bool) -> void:
	_dismiss_run_intro()
	_screen = "run_driving_intro"
	var screen := RUN_BOARD_INTRO.build_driving_screen(_reduced_motion_enabled())
	_driving_intro = screen
	screen.ready_to_race.connect(func() -> void:
		_app.call("dismiss_run_intro")
		_close_driving_intro()
		_screen = "run_board"
		_go_to_run_stop(stop_id, play_confirm))
	screen.back_requested.connect(func() -> void:
		_close_driving_intro()
		_screen = "run_board"
		if is_instance_valid(_run_board):
			_run_board.marker(stop_id).grab_focus())
	_root.add_child(screen)


func _close_driving_intro() -> void:
	if is_instance_valid(_driving_intro):
		_driving_intro.get_parent().remove_child(_driving_intro)
		_driving_intro.queue_free()
	_driving_intro = null


func _run_surface() -> void:
	_configure_stage(&"title")
	_run_backdrop.show()
	_footer.get_parent().hide()
	_content.add_theme_constant_override("separation", 14)
	call_deferred("show_steam_drops")


## Announces each car Steam dropped for a run win, once, over whatever run
## screen is up; ones that dropped during a race wait for the next one.
func show_steam_drops() -> void:
	var queued: Variant = _app.get("steam_drops")
	if queued is not Array or (queued as Array).is_empty() or not visible or not _run_backdrop.visible:
		return
	var drops := queued as Array
	for index: int in drops.size():
		_show_steam_drop(drops[index], index)
	drops.clear()


func _show_steam_drop(car: Dictionary, slot: int) -> void:
	var banner := RUN_UI.action(RUN_UI.STEAM_DROP_LINE % String(CATALOG.generated_vehicle(car).get("name", "")).to_upper(), true)
	banner.name = "SteamDrop%d" % slot
	banner.focus_mode = Control.FOCUS_NONE
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(banner)
	banner.reset_size()
	var rest := Vector2(_root.size.x - banner.size.x - STEAM_DROP_MARGIN, STEAM_DROP_MARGIN + slot * (banner.size.y + STEAM_DROP_GAP))
	banner.position = rest
	if _reduced_motion_enabled():
		get_tree().create_timer(RUN_UI.BANNER_HOLD).timeout.connect(banner.queue_free)
		return
	banner.position = rest - Vector2(0.0, banner.size.y + STEAM_DROP_MARGIN)
	var tween := banner.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(banner, "position", rest, RUN_UI.BANNER_IN)
	tween.tween_interval(RUN_UI.BANNER_HOLD)
	tween.tween_property(banner, "modulate:a", 0.0, RUN_UI.BANNER_OUT)
	tween.tween_callback(banner.queue_free)


## A stop's screen: its copy, the run's stats and its actions on the left;
## `side` on the right, or the read-only map when there is none.
func _run_node_intro(sess: RunSession, kind: String, side: Control = null) -> void:
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
	_run_stats(detail, sess)
	RUN_UI.spacer(detail, 12)
	_run_actions = detail
	if side != null:
		columns.add_child(side)
	else:
		var board := RUN_MAP_VIEW.new()
		board.name = "RunContextMap"
		board.reduced_motion = _reduced_motion_enabled()
		columns.add_child(board)
		# The context map is read-only; actions on this stop remain the only focus targets.
		board.configure(sess, false)
	RUN_UI.divider(_content)
	_content.add_child(RUN_UI.legend(sess.current_map))


func _run_action(text: String, callback: Callable, primary: bool = false, disabled: bool = false, node_name: String = "") -> void:
	_add_run_button(_run_actions, RUN_UI.action(text, primary, disabled), callback, node_name)


func _add_run_button(parent: Node, button: Button, callback: Callable, node_name: String) -> void:
	button.name = node_name
	button.pressed.connect(callback)
	_wire_button_audio(button)
	parent.add_child(button)
	if not button.disabled:
		_register_button_focus(button)


## A car just won: drive it from now on, or keep the current one. Its shape is
## drawn against the car the player is driving.
func show_run_offer() -> void:
	_screen = "run_offer"
	_event_id = ""
	_reset_quick_race_state()
	_clear_content()
	_content.add_theme_constant_override("separation", 4)
	var sess: RunSession = _app.call("current_run_session") as RunSession
	if sess == null or sess.pending_offer.is_empty():
		show_run_board()
		return
	var offered := CATALOG.get_vehicle(sess.pending_offer)
	var current_name := RUN_UI.car_name(sess.current_car_id)
	_run_surface()
	var scene := RUN_OFFER_SCENE.new()
	scene.name = "RunOfferScene"
	scene.act = sess.current_map.act
	scene.car_id = sess.pending_offer
	scene.rival_car_id = sess.current_car_id
	scene.reduced_motion = _reduced_motion_enabled()
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_run_backdrop.add_child(scene)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 72)
	_content.add_child(columns)
	var detail := VBoxContainer.new()
	detail.name = "RunOffer"
	detail.custom_minimum_size.x = 440
	detail.add_theme_constant_override("separation", 6)
	columns.add_child(detail)
	var header := PanelContainer.new()
	header.name = "OfferChalkboard"
	header.add_theme_stylebox_override("panel", RUN_VAN_SCENE.header_style())
	RUN_MATERIALS.finish_panel(header, true)
	detail.add_child(header)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 4)
	header.add_child(heading)
	heading.add_child(RUN_UI.label(RUN_UI.origin_line(offered), 11, SKIN.CREAM, true))
	var title := RUN_UI.label(String(offered.get("name", "")), 30, SKIN.CREAM)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(title)
	heading.add_child(RUN_UI.label(String(offered.get("archetype", "")).to_upper(), 14, SKIN.CREAM, true))
	var line := RUN_UI.label(String(offered.get("strength", "")), 16, SKIN.CREAM)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(line)
	_run_stats(heading, sess)
	RUN_BOARD_SCENE.chalk_labels(heading)
	var card := CarShapeView.new()
	card.name = "OfferShape"
	card.plot_bottom_padding = RUN_OFFER_SCENE.SHAPE_BOTTOM_PADDING
	card.show_delta_caption = true
	card.custom_minimum_size = RUN_OFFER_SCENE.SHAPE_SIZE
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	detail.add_child(card)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	columns.add_child(right)
	RUN_UI.spacer(right, 330)
	_run_actions = right
	if sess.pending_offer_driver.is_empty() and sess.pending_offer_points == 0:
		# Clean cars (lockups) keep the legacy choice: no chase, no cost.
		_run_action("DRIVE IT", Callable(self, "_on_legacy_offer_pressed").bind(true), true, false, "ActionTakeOffer")
		scene.register_control(right.get_child(1) as Button, true)
		_run_action("SEND IT HOME", Callable(self, "_on_legacy_offer_pressed").bind(false), false, false, "ActionKeepCar")
		scene.register_control(right.get_child(2) as Button)
	else:
		if not sess.pending_offer_driver.is_empty():
			var driver := HBoxContainer.new()
			driver.name = "OfferDriver"
			var portrait := TextureRect.new()
			portrait.custom_minimum_size = Vector2(48, 48)
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			portrait.texture = IDENTITIES.avatar_texture(String(sess.pending_offer_driver.get("id", "")))
			driver.add_child(portrait)
			driver.add_child(RUN_UI.label(String(sess.pending_offer_driver.get("name", "")), 18, SKIN.CREAM))
			right.add_child(driver)
		var can_race_hot := sess.can_race_hot(sess.pending_offer)
		var hot_copy := "The driver you took it from chases you on the next sprint" if can_race_hot else "NO SPARE CAR FOR THE CHASE"
		_offer_choice(scene, "RACE IT NOW", hot_copy, "run_race_it_now", "ActionTakeOffer", can_race_hot, not can_race_hot)
		_offer_choice(scene, "SEND IT AHEAD · %d POINTS" % sess.pending_offer_points, "Spend this win's points, nobody chases you", "run_send_it_ahead", "ActionSendAhead", not can_race_hot, sess.run_points < sess.pending_offer_points)
		_offer_choice(scene, "SEND IT HOME", "In your collection next night, keep your points", "run_send_it_home", "ActionKeepCar")
	var current_shape := CarProfile.shape(CATALOG.create_vehicle_stats(sess.current_car_id))
	card.show_shape(
		CarProfile.shape(CATALOG.create_vehicle_stats(sess.pending_offer)),
		current_shape,
		"VS " + current_name.to_upper(),
		{} if _reduced_motion_enabled() else current_shape
	)
	_focus_first()


func _offer_choice(scene: Control, title: String, copy: String, action: String, node_name: String, primary: bool = false, disabled: bool = false) -> void:
	_run_action(title, Callable(self, "_on_offer_pressed").bind(action), primary, disabled, node_name)
	scene.register_control(_run_actions.get_child(_run_actions.get_child_count() - 1) as Button, primary)
	var label := RUN_UI.label(copy, 14, SKIN.CREAM)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_run_actions.add_child(label)


func _on_offer_pressed(action: String) -> void:
	_play_ui_confirm()
	if bool(_app.call(action)):
		show_run_board()


func _on_legacy_offer_pressed(take: bool) -> void:
	_play_ui_confirm()
	_app.call("run_take_offer" if take else "run_decline_offer")
	show_run_board()


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
	var used := sess.bench_action_done
	_run_surface()
	var scene := RUN_BENCH_SCENE.new()
	scene.name = "RunBenchScene"
	scene.act = sess.current_map.act
	scene.car_id = sess.current_car_id
	scene.car_wear = sess.run_state.get_car_wear(sess.current_car_id)
	scene.held_parts = sess.parts_held.duplicate(true)
	scene.reduced_motion = _reduced_motion_enabled()
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_run_backdrop.add_child(scene)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 76)
	_content.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 520
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	var header := PanelContainer.new()
	header.name = "BenchChalkboard"
	var chalk := StyleBoxFlat.new()
	chalk.bg_color = Color("26362f")
	chalk.border_color = Color("806446")
	chalk.set_border_width_all(5)
	chalk.set_content_margin_all(14)
	chalk.shadow_color = Color(0.01, 0.02, 0.04, 0.55)
	chalk.shadow_size = 4
	chalk.shadow_offset = Vector2(5, 7)
	header.add_theme_stylebox_override("panel", chalk)
	RUN_MATERIALS.finish_panel(header, true)
	left.add_child(header)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 4)
	header.add_child(heading)
	heading.add_child(RUN_UI.label("RUN · ACT %d · %s" % [sess.current_map.act, String(RUN_UI.ROOMS[sess.current_map.act]).to_upper()], 11, SKIN.CREAM, true))
	heading.add_child(RUN_UI.label(String(RUN_UI.TYPES["bench"]["name"]), 30, SKIN.CREAM))
	var copy := RUN_UI.label(String(RUN_UI.TYPES["bench"]["copy"]), 16, SKIN.CREAM)
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(copy)
	_run_stats(heading, sess)
	RUN_BOARD_SCENE.chalk_labels(heading)
	RUN_UI.spacer(left, 228)
	var empty_parts := sess.parts_held.is_empty()
	var actions: BoxContainer = VBoxContainer.new() if empty_parts else HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	left.add_child(actions)
	_run_actions = actions
	var card := RUN_UI.parts_card("YOUR PARTS · FIT ONE" if not empty_parts else "NO PARTS HELD - A PARTS VAN SELLS THEM")
	card[0].name = "BenchParts"
	card[0].custom_minimum_size = Vector2(420, 0 if empty_parts else 516)
	card[0].size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("d8c89f")
	paper.border_color = SKIN.INK
	paper.set_border_width_all(2)
	paper.set_content_margin_all(14)
	paper.shadow_color = Color(0.01, 0.02, 0.04, 0.5)
	paper.shadow_size = 4
	paper.shadow_offset = Vector2(6, 8)
	card[0].add_theme_stylebox_override("panel", paper)
	RUN_MATERIALS.finish_panel(card[0] as PanelContainer)
	RUN_BOARD_SCENE.ink_labels(card[0])
	var parts_column := VBoxContainer.new()
	if empty_parts:
		parts_column.add_theme_constant_override("separation", 12)
		columns.add_child(parts_column)
		parts_column.add_child(card[0])
	else:
		columns.add_child(card[0])
		parts_column.free()
	var car_clean := sess.run_state.get_car_wear(sess.current_car_id) == RunState.WEAR_LEVELS[0]
	_run_action("REPAIR", Callable(self, "_on_bench_repair_pressed"), true, used or car_clean, "BenchRepair")
	RUN_BENCH_SCENE.dress_button(actions.get_child(0) as Button, true)
	for index: int in sess.parts_held.size():
		var part: Dictionary = sess.parts_held[index]
		var fit := RUN_UI.part_button(part, "FIT %s" % RunParts.part_name(part).to_upper(), used)
		RUN_BENCH_SCENE.dress_part(fit, part)
		_add_run_button(card[1], fit, Callable(self, "_on_bench_fit_pressed").bind(index), "BenchFit_%d" % index)
	_run_action("BACK", Callable(self, "show_run_board"), false, false, "ActionBack")
	RUN_BENCH_SCENE.dress_button(actions.get_child(1) as Button)
	var extra_actions: BoxContainer = VBoxContainer.new() if empty_parts else HBoxContainer.new()
	extra_actions.add_theme_constant_override("separation", 12)
	extra_actions.visible = not sess.boot_cars.is_empty() or (not used and sess.owned_cars.size() > 1)
	left.add_child(extra_actions)
	_run_actions = extra_actions
	if not sess.boot_cars.is_empty():
		_run_action("BANK THE HAUL", Callable(self, "_on_bench_bank_pressed"), false, used, "BenchBankHaul")
		RUN_BENCH_SCENE.dress_button(extra_actions.get_child(extra_actions.get_child_count() - 1) as Button)
	if not used and sess.owned_cars.size() > 1:
		var spares := RUN_UI.parts_card("SWAP CAR")
		spares[0].name = "BenchSwapCars"
		spares[0].custom_minimum_size = Vector2(420, 240 if empty_parts else 516)
		spares[0].size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		spares[0].add_theme_stylebox_override("panel", paper.duplicate())
		RUN_MATERIALS.finish_panel(spares[0] as PanelContainer)
		RUN_BOARD_SCENE.ink_labels(spares[0])
		if empty_parts:
			parts_column.add_child(spares[0])
		else:
			columns.add_child(spares[0])
		spares[0].hide()
		for vehicle_id: String in sess.owned_cars:
			if vehicle_id == sess.current_car_id:
				continue
			var choice := RUN_UI.action(RUN_UI.car_name(vehicle_id))
			choice.icon = IDENTITIES.car_texture(vehicle_id)
			choice.expand_icon = true
			choice.add_theme_constant_override("icon_max_width", 64)
			choice.custom_minimum_size = Vector2(340, 80)
			RUN_BENCH_SCENE.dress_button(choice)
			_add_run_button(spares[1], choice, Callable(self, "_on_bench_swap_pressed").bind(vehicle_id), "BenchSwapCar_%d" % spares[1].get_child_count())
		_run_action("SWAP CAR", func() -> void:
			card[0].visible = not card[0].visible
			spares[0].visible = not card[0].visible
			if spares[0].visible:
				(spares[1].get_child(0) as Button).grab_focus()
		, false, false, "BenchSwap")
		RUN_BENCH_SCENE.dress_button(extra_actions.get_child(extra_actions.get_child_count() - 1) as Button)
	if empty_parts:
		actions.reparent(parts_column)
		extra_actions.reparent(parts_column)
		for row: BoxContainer in [actions, extra_actions]:
			for action: Node in row.get_children():
				var button := action as Button
				button.custom_minimum_size.y = 64
				button.add_theme_font_size_override("font_size", 20)
	var legend := RUN_UI.legend(sess.current_map)
	RUN_BOARD_SCENE.chalk_labels(legend)
	legend.draw.connect(func() -> void: SKIN.draw_tape(legend, legend.size * 0.5, legend.size + Vector2(8, 8), 0.0, Color("27332f")))
	_content.add_child(legend)
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
	var bought := sess.resolved_nodes.has(sess.current_node_id)
	_run_surface()
	var scene := RUN_VAN_SCENE.new()
	scene.name = "RunVanScene"
	scene.act = sess.current_map.act
	scene.reduced_motion = _reduced_motion_enabled()
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_run_backdrop.add_child(scene)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 110)
	_content.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 420
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	var header := PanelContainer.new()
	header.name = "VanChalkboard"
	header.add_theme_stylebox_override("panel", RUN_VAN_SCENE.header_style())
	RUN_MATERIALS.finish_panel(header, true)
	left.add_child(header)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 4)
	header.add_child(heading)
	heading.add_child(RUN_UI.label("RUN · ACT %d · %s" % [sess.current_map.act, String(RUN_UI.ROOMS[sess.current_map.act]).to_upper()], 11, SKIN.CREAM, true))
	heading.add_child(RUN_UI.label(String(RUN_UI.TYPES["parts_van"]["name"]), 30, SKIN.CREAM))
	var copy := RUN_UI.label(String(RUN_UI.TYPES["parts_van"]["copy"]), 16, SKIN.CREAM)
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(copy)
	_run_stats(heading, sess)
	RUN_BOARD_SCENE.chalk_labels(heading)
	left.custom_minimum_size.y = RUN_UI.CARD_SIZE.y
	var action_space := Control.new()
	action_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(action_space)
	_run_actions = left
	var rack := VBoxContainer.new()
	rack.add_theme_constant_override("separation", 0)
	columns.add_child(rack)
	RUN_UI.spacer(rack, 64)
	var card := RUN_UI.parts_card("IN THE VAN · ONE PER VISIT")
	card[0].name = "VanParts"
	card[0].custom_minimum_size = Vector2(520, 456)
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color.TRANSPARENT
	rail.set_content_margin_all(14)
	card[0].add_theme_stylebox_override("panel", rail)
	RUN_BOARD_SCENE.chalk_labels(card[0])
	rack.add_child(card[0])
	for part: Dictionary in sess.van_stock():
		var cost := RunParts.cost(part)
		var buy := RUN_UI.part_button(part, "%s · %d POINTS" % [RunParts.part_name(part).to_upper(), cost], bought or sess.run_points < cost)
		scene.register_pack(buy, part)
		_add_run_button(card[1], buy, Callable(self, "_on_van_buy_pressed").bind(String(part["part"])), "VanBuy_" + String(part["part"]))
	for vehicle_id: String in sess.impounded_cars:
		var ransom := RUN_UI.action("RANSOM %s · %d POINTS" % [RUN_UI.car_name(vehicle_id).to_upper(), RunSession.HAUL_RANSOM_POINTS], false, bought or sess.run_points < RunSession.HAUL_RANSOM_POINTS)
		_add_run_button(card[1], ransom, Callable(self, "_on_van_ransom_pressed").bind(vehicle_id), "VanRansom_" + vehicle_id)
	var consumables := HBoxContainer.new()
	consumables.add_theme_constant_override("separation", 12)
	left.add_child(consumables)
	for offer: Dictionary in sess.van_offer_consumables():
		var item := String(offer["item"])
		var buy := RUN_UI.action("%s · %d POINTS" % [item.to_upper(), int(offer["price"])], false, sess.run_points < int(offer["price"]))
		RUN_BENCH_SCENE.dress_button(buy)
		_add_run_button(consumables, buy, Callable(self, "_on_van_consumable_pressed").bind(item), "VanBuy_" + item)
	_run_action("BACK", Callable(self, "show_run_board"), false, false, "ActionBack")
	RUN_BENCH_SCENE.dress_button(left.get_child(left.get_child_count() - 1) as Button)
	var legend := RUN_UI.legend(sess.current_map)
	RUN_BOARD_SCENE.chalk_labels(legend)
	legend.draw.connect(func() -> void: SKIN.draw_tape(legend, legend.size * 0.5, legend.size + Vector2(8, 8), 0.0, Color("27332f")))
	_content.add_child(legend)
	# The first part the points can buy takes focus, not BACK on the left.
	_queue_content_entrance()
	_grab_button_focus_after_layout(_button_focus_chain[0], _entrance_generation)


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
	_run_surface()
	var scene := RUN_LOCKUP_SCENE.new()
	scene.name = "RunLockupScene"
	scene.act = sess.current_map.act
	scene.reduced_motion = _reduced_motion_enabled()
	scene.already_open = sess.lockup_used
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_run_backdrop.add_child(scene)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 110)
	_content.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(420, RUN_LOCKUP_SCENE.UI_COLUMN_HEIGHT)
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	var header := PanelContainer.new()
	header.name = "LockupChalkboard"
	header.add_theme_stylebox_override("panel", RUN_VAN_SCENE.header_style())
	RUN_MATERIALS.finish_panel(header, true)
	left.add_child(header)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 4)
	header.add_child(heading)
	heading.add_child(RUN_UI.label("RUN · ACT %d · %s" % [sess.current_map.act, String(RUN_UI.ROOMS[sess.current_map.act]).to_upper()], 11, SKIN.CREAM, true))
	heading.add_child(RUN_UI.label(String(RUN_UI.TYPES["lockup"]["name"]), 30, SKIN.CREAM))
	var copy := RUN_UI.label(String(RUN_UI.TYPES["lockup"]["copy"]), 16, SKIN.CREAM)
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(copy)
	_run_stats(heading, sess)
	RUN_BOARD_SCENE.chalk_labels(heading)
	var action_space := Control.new()
	action_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(action_space)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	left.add_child(actions)
	_run_actions = actions
	var context := RUN_MAP_VIEW.new()
	context.name = "RunContextMap"
	context.reduced_motion = _reduced_motion_enabled()
	columns.add_child(context)
	context.configure(sess, false)
	context.hide_route_visuals()
	_run_action("OPEN LOCKUP", Callable(self, "_on_lockup_open_pressed"), true, sess.lockup_used, "LockupOpen")
	RUN_BENCH_SCENE.dress_button(actions.get_child(0) as Button, true)
	_run_action("BACK", Callable(self, "show_run_board"), false, false, "ActionBack")
	RUN_BENCH_SCENE.dress_button(actions.get_child(1) as Button)
	RUN_UI.spacer(_content, RUN_LOCKUP_SCENE.LEGEND_SPACER)
	var legend := RUN_UI.legend(sess.current_map)
	RUN_BOARD_SCENE.chalk_labels(legend)
	legend.draw.connect(func() -> void: SKIN.draw_tape(legend, legend.size * 0.5, legend.size + Vector2(8, 8), 0.0, Color("27332f")))
	_content.add_child(legend)
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
	_run_surface()
	var scene := RUN_ERRAND_SCENE.new()
	scene.name = "RunErrandScene"
	scene.act = sess.current_map.act
	scene.reduced_motion = _reduced_motion_enabled()
	scene.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_run_backdrop.add_child(scene)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 110)
	_content.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(420, RUN_ERRAND_SCENE.UI_COLUMN_HEIGHT)
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	var header := PanelContainer.new()
	header.name = "ErrandChalkboard"
	header.add_theme_stylebox_override("panel", RUN_VAN_SCENE.header_style())
	RUN_MATERIALS.finish_panel(header, true)
	left.add_child(header)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 4)
	header.add_child(heading)
	heading.add_child(RUN_UI.label("RUN · ACT %d · %s" % [sess.current_map.act, String(RUN_UI.ROOMS[sess.current_map.act]).to_upper()], 11, SKIN.CREAM, true))
	heading.add_child(RUN_UI.label(String(RUN_UI.TYPES["errand"]["name"]), 30, SKIN.CREAM))
	_run_stats(heading, sess)
	RUN_BOARD_SCENE.chalk_labels(heading)
	var action_space := Control.new()
	action_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(action_space)
	var back_row := HBoxContainer.new()
	left.add_child(back_row)
	var context := RUN_MAP_VIEW.new()
	context.name = "RunContextMap"
	context.reduced_motion = _reduced_motion_enabled()
	columns.add_child(context)
	context.configure(sess, false)
	context.hide_route_visuals()
	var request := RUN_ERRAND_SCENE.request_for_node(sess, sess.current_node_id)
	var slips := VBoxContainer.new()
	slips.name = "ErrandSlips"
	slips.add_theme_constant_override("separation", 12)
	slips.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slips.offset_left = 24
	slips.offset_right = -24
	slips.offset_top = 128
	slips.offset_bottom = -100
	context.add_child(slips)
	var requester := RUN_UI.label("FROM: " + String(request["requester"]["name"]).to_upper(), 16, SKIN.INK, true)
	requester.name = "ErrandRequester"
	requester.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slips.add_child(requester)
	var task := RUN_UI.label(String(request["task"]), 16, SKIN.INK)
	task.name = "ErrandTask"
	task.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	slips.add_child(task)
	_run_actions = slips
	var car_clean := sess.run_state.get_car_wear(sess.current_car_id) == RunState.WEAR_LEVELS[0]
	_run_action("TAKE THE PAY · %d" % RunSession.ERRAND_PAY_POINTS, Callable(self, "_on_errand_choice_pressed").bind(0), true, false, "ErrandPay")
	scene.register_choice(slips.get_node("ErrandPay") as Button, 0)
	_run_action("TAKE A TUNE-UP", Callable(self, "_on_errand_choice_pressed").bind(1), false, car_clean, "ErrandTuneUp")
	scene.register_choice(slips.get_node("ErrandTuneUp") as Button, 1)
	_run_actions = back_row
	_run_action("BACK", Callable(self, "show_run_board"), false, false, "ActionBack")
	RUN_BENCH_SCENE.dress_button(back_row.get_child(0) as Button)
	var legend := RUN_UI.legend(sess.current_map)
	RUN_BOARD_SCENE.chalk_labels(legend)
	legend.draw.connect(func() -> void: SKIN.draw_tape(legend, legend.size * 0.5, legend.size + Vector2(8, 8), 0.0, Color("27332f")))
	_content.add_child(legend)
	_queue_content_entrance()
	_grab_button_focus_after_layout(_button_focus_chain[0], _entrance_generation)


func _on_bench_repair_pressed() -> void:
	_play_ui_confirm()
	var sess_var: Variant = _app.call("current_run_session")
	var sess: RunSession = sess_var as RunSession
	if sess == null:
		return
	var old_wear := sess.run_state.get_car_wear(sess.current_car_id)
	if not bool(_app.call("run_bench_repair", sess.current_car_id)):
		return
	var new_wear := sess.run_state.get_car_wear(sess.current_car_id)
	if await _finish_bench_confirmation(&"repair", "BenchRepair"):
		var acknowledgement := RUN_UI.label("REPAIRED - %s -> %s" % [old_wear.to_upper(), new_wear.to_upper()], 16, SKIN.CREAM, true)
		acknowledgement.name = "BenchRepairAcknowledgement"
		acknowledgement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_run_stop_card.add_child(acknowledgement)
		_run_stop_card.move_child(acknowledgement, 0)


func _on_bench_bank_pressed() -> void:
	_play_ui_confirm()
	if bool(_app.call("run_bench_bank_haul")):
		show_run_board()


func _on_bench_swap_pressed(vehicle_id: String) -> void:
	_play_ui_confirm()
	if bool(_app.call("run_bench_swap", vehicle_id)):
		show_run_board()


func _on_van_ransom_pressed(vehicle_id: String) -> void:
	_play_ui_confirm()
	if bool(_app.call("run_ransom_car", vehicle_id)):
		show_run_board()


func _on_bench_fit_pressed(held_index: int) -> void:
	_play_ui_confirm()
	var scene := _run_backdrop.get_node_or_null("RunBenchScene") as RUN_BENCH_SCENE
	var part_id := String(scene.held_parts[held_index]["part"]) if scene != null and held_index >= 0 and held_index < scene.held_parts.size() else ""
	_app.call("run_bench_fit", held_index)
	_finish_bench_confirmation(&"fit", "BenchFit_%d" % held_index, part_id)


func _finish_bench_confirmation(kind: StringName, button_name: String, part_id: String = "") -> bool:
	var generation := _entrance_generation
	var scene := _run_backdrop.get_node_or_null("RunBenchScene") as RUN_BENCH_SCENE
	var button := _content.find_child(button_name, true, false) as Button
	if scene != null and button != null:
		for action: Node in _content.find_children("Bench*", "Button", true, false):
			(action as Button).disabled = true
		var duration := scene.confirm(button, kind, part_id)
		if duration > 0.0:
			await get_tree().create_timer(duration).timeout
	if generation == _entrance_generation and _screen == "run_bench":
		show_run_board()
		return true
	return false


func _on_van_buy_pressed(part_id: String) -> void:
	_play_ui_confirm()
	_app.call("run_buy_part", part_id)
	_finish_van_confirmation(part_id)


func _on_van_consumable_pressed(item: String) -> void:
	_play_ui_confirm()
	if bool(_app.call("run_buy_" + item)):
		show_run_board()


func _finish_van_confirmation(part_id: String) -> void:
	var generation := _entrance_generation
	var scene := _run_backdrop.get_node_or_null("RunVanScene") as RUN_VAN_SCENE
	var button := _content.find_child("VanBuy_" + part_id, true, false) as Button
	if scene != null and button != null:
		for action: Node in _content.find_children("VanBuy_*", "Button", true, false):
			(action as Button).disabled = true
		var duration := scene.confirm(button)
		if duration > 0.0:
			await get_tree().create_timer(duration).timeout
	if generation == _entrance_generation and _screen == "run_parts_van":
		show_run_board()


func _on_lockup_open_pressed() -> void:
	_play_ui_confirm()
	var opened := bool(_app.call("run_open_lockup"))
	_finish_lockup_confirmation(opened)


func _finish_lockup_confirmation(opened: bool) -> void:
	var generation := _entrance_generation
	var scene := _run_backdrop.get_node_or_null("RunLockupScene") as RUN_LOCKUP_SCENE
	var button := _content.find_child("LockupOpen", true, false) as Button
	var sess: RunSession = _app.call("current_run_session") as RunSession
	if opened and scene != null and button != null and sess != null and not sess.pending_offer.is_empty():
		button.disabled = true
		var duration := scene.confirm(button, sess.pending_offer)
		if duration > 0.0:
			await get_tree().create_timer(duration).timeout
	if generation == _entrance_generation and _screen == "run_lockup":
		show_run_board()


func _on_errand_choice_pressed(choice: int) -> void:
	_play_ui_confirm()
	var resolved := bool(_app.call("run_resolve_errand", choice))
	_finish_errand_confirmation(choice, resolved)


func _finish_errand_confirmation(choice: int, resolved: bool) -> void:
	var generation := _entrance_generation
	var scene := _run_backdrop.get_node_or_null("RunErrandScene") as RUN_ERRAND_SCENE
	var button := _content.find_child("ErrandPay" if choice == 0 else "ErrandTuneUp", true, false) as Button
	if resolved and scene != null and button != null:
		for action: Node in _content.find_children("Errand*", "Button", true, false):
			(action as Button).disabled = true
		var duration := scene.confirm(button, choice)
		if duration > 0.0:
			await get_tree().create_timer(duration).timeout
	if generation == _entrance_generation and _screen == "run_errand":
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
	# Cars traded in or out since the last read show next time the garage opens.
	var steam: Variant = _app.get("steam")
	if steam is Node:
		(steam as Node).call("refresh")
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
		"run_driving_intro":
			_driving_intro.call("cancel")
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
		"run_board", "run_offer":
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
	margin.minimum_size_changed.connect(func() -> void: margin.set_deferred("size", _root.size))
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
	var confirmation := _root.get_node_or_null("AbandonConfirm")
	if confirmation != null:
		_root.remove_child(confirmation)
		confirmation.queue_free()
	if is_instance_valid(_driving_intro):
		_close_driving_intro()
	_dismiss_run_intro()
	_page.add_theme_constant_override("margin_left", PAGE_MARGIN)
	_page.add_theme_constant_override("margin_right", PAGE_MARGIN)
	_page.add_theme_constant_override("margin_top", PAGE_TOP)
	_page.add_theme_constant_override("margin_bottom", roundi(SKIN.BENCH_LIP) + 6)
	_run_going = false
	_page.show()
	_run_backdrop.hide()
	for dressing: Node in _run_backdrop.get_children():
		_run_backdrop.remove_child(dressing)
		dressing.queue_free()
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


func _present_screen_transition() -> void:
	var destination := _screen
	var kicker: String = TRANSITION_KICKERS.get(_screen, _screen.replace("_", " ").to_upper())
	if _screen == "run_board":
		var sess: RunSession = _app.call("run_board_session") as RunSession
		if sess != null and sess.current_map != null:
			var room: String = RUN_BOARD_SCENE.ROOM_NAMES.get(sess.current_map.act, "Kitchen Counter")
			kicker = "NIGHT OVER" if sess.is_failed() or sess.is_complete() else "%s - ACT %d" % [room.to_upper(), sess.current_map.act]
			destination += ":" + kicker
	if destination == _last_transition_destination:
		return
	_last_transition_destination = destination
	if not is_instance_valid(_night_transition):
		_night_transition = NIGHT_TRANSITION.new()
		_night_transition.name = "NightTransition"
		add_child(_night_transition)
	_night_transition.call("play", kicker, NIGHT_TRANSITION.instant_for(_app), _reduced_motion_enabled())


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
			_on_new_run_pressed()
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
	left_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	left_label.clip_text = true
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
	RUN_UI.stagger_in(_button_focus_chain, false)


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
	seed_status.text = "SEED %d" % _quick_race_seed
	_stage.configure(&"map", _quick_strip_vehicle_id if _quick_strip else _quick_race_vehicle_id, "rae", String(_quick_race_theme))
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
		_quick_identity_summary.text = _quick_preview_summary(identity)


func _quick_preview_summary(identity: Dictionary) -> String:
	var rooms := String(identity.get("theme", _quick_race_theme)).capitalize()
	if String(identity.get("route_shape", "circuit")) == "strip":
		rooms += " → " + String(identity.get("theme_b", "")).capitalize()
	return "%s · %s" % [rooms, String(identity.get("length_tier", _quick_race_length_tier)).capitalize()]


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
	var session: RunSession = _app.call("start_new_run")
	var progress: Dictionary = _app.call("get_save_data")
	_run_intro_pending = session != null and not bool(progress.get("run_intro_seen", true))
	show_run_board()


func _on_save_run_again() -> void:
	_play_ui_confirm()
	_app.call("persist_current_run")
	show_run_board()


func _on_abandon_run() -> void:
	var abandon := _content.find_child("ActionAbandon", true, false) as Button
	if abandon == null or _root.find_child("AbandonConfirm", true, false) != null:
		return
	var strip := CenterContainer.new()
	strip.name = "AbandonConfirm"
	strip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(strip)
	strip.draw.connect(func() -> void: strip.draw_rect(Rect2(Vector2.ZERO, strip.size), Color(0.02, 0.03, 0.04, 0.8)))
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 620
	panel.add_theme_stylebox_override("panel", SKIN.card_style(SKIN.CREAM, 0.0))
	strip.add_child(panel)
	var inset := MarginContainer.new()
	for edge: String in ["left", "right", "top", "bottom"]:
		inset.add_theme_constant_override("margin_" + edge, 24)
	panel.add_child(inset)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	inset.add_child(content)
	var warning := RUN_UI.label("THE NIGHT ENDS - CARS NOT BANKED ARE LOST", 13, Color("8d322a"), true)
	warning.name = "AbandonWarning"
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(warning)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 16)
	content.add_child(actions)
	var confirm := RUN_UI.action("ABANDON THE NIGHT")
	confirm.name = "ActionConfirmAbandon"
	confirm.pressed.connect(_confirm_abandon_run)
	_wire_button_audio(confirm)
	actions.add_child(confirm)
	var keep := RUN_UI.action("KEEP DRIVING", true)
	keep.name = "ActionKeepDriving"
	keep.pressed.connect(func() -> void:
		strip.get_parent().remove_child(strip)
		strip.queue_free()
		abandon.grab_focus())
	_wire_button_audio(keep)
	actions.add_child(keep)
	for button: Button in [confirm, keep]:
		var other := keep if button == confirm else confirm
		button.focus_next = button.get_path_to(other)
		button.focus_previous = button.get_path_to(other)
		button.focus_neighbor_left = button.get_path_to(other)
		button.focus_neighbor_right = button.get_path_to(other)
		button.focus_neighbor_top = button.get_path_to(other)
		button.focus_neighbor_bottom = button.get_path_to(other)
	keep.grab_focus()


func _confirm_abandon_run() -> void:
	_app.call("abandon_run")
	show_title()
