extends CanvasLayer

const CATALOG := preload("res://data/championship/catalog.gd")
const CIRCUIT_ROSTER := preload("res://data/circuits/circuit_roster.gd")
const STAGE_SCRIPT := preload("res://scripts/ui/app_shell_stage.gd")
const MENU_BACKGROUND := preload("res://assets/ui/imagine/menu_night_kitchen_cartoon.png")

const INK := Color("0e151f")
const PAPER := Color("f5f0e3")
const CREAM := Color("fff8e8")
const AMBER := Color("f4c65a")
const CORAL := Color("e85a2e")
const BLUE := Color("4a8fb8")
const MUTED := Color("aeb7c8")
const WORKBENCH := Color("5c4638")

var _app: Node
var _root: Control
var _scroll: ScrollContainer
var _content: VBoxContainer
var _stage: AppShellStage
var _footer: Label
var _button_focus_chain: Array[Button] = []
var _screen := "title"
var _event_id := ""
var _quick_race := false
var _map_act_number := 1
var _quick_race_act_number := 1
var _quick_race_circuit_page := 0
var _quick_race_circuit_theme := "workshop"
var _content_tween: Tween
var _entrance_generation := 0
var _save_error_back_action := Callable()
var _current_vehicle_select_id := ""


func configure(app: Node) -> void:
	_app = app
	if _root == null:
		_build_base()


func show_title() -> void:
	_screen = "title"
	_event_id = ""
	_quick_race = false
	_clear_content()
	_content.add_theme_constant_override("separation", 4)
	_configure_stage(&"title")
	_add_title_lockup()
	var save_read_only := bool(_app.call("is_save_read_only"))
	var has_progress := bool(_app.call("has_championship_progress"))
	if save_read_only:
		_add_copy("READ-ONLY SAVE · NEWER FILE DETECTED · FILE UNTOUCHED", CORAL)
	elif has_progress:
		_add_copy("CHAMPIONSHIP IN PROGRESS · PLAY CONTINUES YOUR RUN", AMBER)
	else:
		_add_copy("START YOUR CHAMPIONSHIP", AMBER)
	_add_spacer(8)
	_add_big_play_button(
		Callable(_app, "continue_championship") if has_progress else Callable(_app, "request_new_championship"),
		save_read_only and not has_progress
	)
	_add_spacer(6)
	var race_actions: Array[Dictionary] = []
	if has_progress:
		race_actions.append({"text": "NEW RUN", "callback": Callable(_app, "request_new_championship"), "accent": CREAM, "disabled": save_read_only})
	race_actions.append({"text": "QUICK RACE", "callback": Callable(_app, "open_quick_race"), "accent": CREAM, "disabled": false})
	_add_action_row(race_actions)
	_add_action_row([
		{"text": "OPTIONS", "callback": Callable(self, "show_settings"), "accent": CREAM, "disabled": false},
		{"text": "CREDITS", "callback": Callable(self, "show_credits"), "accent": CREAM, "disabled": false},
		{"text": "QUIT", "callback": Callable(_app, "quit_game"), "accent": CREAM, "disabled": false},
	])
	_footer.text = "ARROWS / STICK  MOVE     ·     ENTER / A  SELECT"
	_focus_first()


func show_reset_confirmation() -> void:
	_screen = "reset_confirmation"
	_clear_content()
	_configure_stage(&"title")
	_add_kicker("NEW CHAMPIONSHIP")
	_add_heading("Erase the current standings?")
	_add_copy("Best finishes, act wins, vehicle unlocks, and the ending flag will be reset. Settings stay exactly as they are.")
	_add_spacer(18)
	_add_button("ERASE & START AGAIN", Callable(_app, "confirm_new_championship"), CORAL)
	_add_button("KEEP CURRENT CHAMPIONSHIP", Callable(self, "show_title"), CREAM)
	_footer.text = "ESC / B  BACK"
	_focus_first()


func show_map(result_summary: Dictionary = {}, requested_act: int = 0) -> void:
	_screen = "map"
	_event_id = ""
	_quick_race = false
	_clear_content()
	var progress: Dictionary = _app.call("get_save_data")
	var best_finishes: Dictionary = progress.get("best_event_finishes", {})
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
	var visible_act := CATALOG.get_act(_map_act_number)
	_configure_stage(&"map")
	_add_kicker("CHAMPIONSHIP · ACT %d OF %d" % [_map_act_number, CATALOG.ACTS.size()])
	_add_heading(String(visible_act.get("name", "Grand Household Circuit")))
	if not result_summary.is_empty():
		_add_result_notice(result_summary)
	if (
		result_summary.is_empty()
		and not recommended_event_id.is_empty()
		and int(CATALOG.get_event(recommended_event_id).get("act", 0)) == _map_act_number
	):
		var recommended_event := CATALOG.get_event(recommended_event_id)
		_add_copy("NEXT  ·  %s  ·  %s" % [String(recommended_event["name"]), String(recommended_event["format"])], AMBER)
	var recommended_button: Button
	var act_complete: bool = String(visible_act.get("id", "")) in progress.get("completed_acts", [])
	var standings := "%d PTS" % CATALOG.act_points(progress, _map_act_number)
	if act_complete:
		standings += "  ·  WON"
	_add_section("EVENTS", standings)
	for event: Dictionary in CATALOG.EVENTS:
		if int(event["act"]) != _map_act_number:
			continue
		var event_id := String(event["id"])
		var unlocked := CATALOG.is_event_unlocked(event_id, progress)
		var finish := int(best_finishes.get(event_id, 0))
		var status := "LOCKED · %s" % String(event["unlock"])
		if unlocked:
			status = "OPEN · %s" % String(event["format"])
		if finish > 0:
			status = "BEST %s · %d PTS" % [_ordinal(finish), int(progress["best_event_points"].get(event_id, 0))]
		var event_button := _add_button(
			"%s\n%s" % [String(event["name"]), status],
			Callable(self, "_open_event").bind(event_id),
			AMBER if unlocked else MUTED,
			not unlocked,
			"Event_%s" % event_id
		)
		if event_id == recommended_event_id:
			recommended_button = event_button
	var act_navigation := _add_act_navigation(_map_act_number, Callable(self, "_show_map_act"))
	var return_button := _add_button("RETURN TO TITLE", Callable(self, "show_title"), CREAM)
	_complete_focus_row(act_navigation, return_button)
	_footer.text = "SELECT AN ACT, THEN AN EVENT  ·  ESC / B  BACK"
	if recommended_button:
		_queue_content_entrance()
		_grab_button_focus_after_layout(recommended_button, _entrance_generation)
	else:
		_focus_first()


func show_quick_race(requested_act: int = 0) -> void:
	_screen = "quick_race"
	_event_id = ""
	_quick_race = true
	_clear_content()
	_content.add_theme_constant_override("separation", 4)
	_configure_stage(&"map")
	var progress: Dictionary = _app.call("get_save_data")
	var completed_events: Array = progress.get("completed_events", [])
	var best_finishes: Dictionary = progress.get("best_event_finishes", {})
	var available_acts: Array[int] = []
	for event: Dictionary in CATALOG.EVENTS:
		var candidate_id := String(event["id"])
		if candidate_id == "kitchen_crumb_rush" or candidate_id in completed_events:
			var act_number := int(event["act"])
			if not act_number in available_acts:
				available_acts.append(act_number)
	if requested_act > 0 and requested_act in available_acts:
		_quick_race_act_number = requested_act
	elif not _quick_race_act_number in available_acts:
		_quick_race_act_number = available_acts[0] if not available_acts.is_empty() else 1
	var visible_act := CATALOG.get_act(_quick_race_act_number)
	_add_kicker("QUICK RACE · RESULTS DO NOT SAVE")
	_add_heading("Pick a circuit")
	if completed_events.is_empty():
		_add_copy("Finish championship events to unlock them here.", MUTED)
	_add_section("ACT %d · %s" % [_quick_race_act_number, String(visible_act.get("name", "EXHIBITION"))], "")
	for event: Dictionary in CATALOG.EVENTS:
		var event_id := String(event["id"])
		if int(event["act"]) != _quick_race_act_number:
			continue
		if event_id != "kitchen_crumb_rush" and not event_id in completed_events:
			continue
		var finish := int(best_finishes.get(event_id, 0))
		var status := "PRACTICE ROUTE"
		if finish > 0:
			status = "BEST %s · %d PTS" % [_ordinal(finish), int(progress["best_event_points"].get(event_id, 0))]
		_add_button(
			"%s\n%s  ·  %s" % [String(event["name"]), String(event["format"]), status],
			Callable(self, "show_vehicle_select").bind(event_id, true),
			BLUE,
			false,
			"QuickRace_%s" % event_id
		)
	var act_navigation := _add_available_act_navigation(available_acts, _quick_race_act_number, Callable(self, "_show_quick_race_act"))
	var circuit_entries: Array = []
	for entry: Dictionary in CIRCUIT_ROSTER.entries():
		if String(entry["theme"]) == _quick_race_circuit_theme:
			circuit_entries.append(entry)
	var page_count := maxi(1, ceili(float(circuit_entries.size()) / 8.0))
	_quick_race_circuit_page = posmod(_quick_race_circuit_page, page_count)
	_add_section("GENERATED CIRCUITS", "%s · PAGE %d OF %d" % [_quick_race_circuit_theme.to_upper(), _quick_race_circuit_page + 1, page_count])
	var page_start := _quick_race_circuit_page * 8
	var page_end := mini(page_start + 8, circuit_entries.size())
	var circuit_buttons := _add_circuit_buttons(circuit_entries, page_start, page_end)
	if not circuit_buttons.is_empty():
		_complete_focus_row(act_navigation, circuit_buttons[0])
	var circuit_navigation := _add_circuit_navigation(page_count)
	if circuit_buttons.size() >= 2:
		_complete_focus_row([circuit_buttons.back(), circuit_buttons[circuit_buttons.size() - 2]], circuit_navigation[0])
	_footer.text = "EXHIBITION RESULTS DO NOT SAVE  ·  ESC / B  BACK"
	_grab_first_focus()
	_focus_first()


func show_briefing(event_id: String) -> void:
	var event := CATALOG.get_event(event_id)
	if event.is_empty():
		show_map()
		return
	_screen = "briefing"
	_event_id = event_id
	_quick_race = false
	_clear_content()
	var opponent_ids: Array = event.get("opponents", [])
	var rival_id := String(opponent_ids[0]) if not opponent_ids.is_empty() else "juniper"
	_configure_stage(&"briefing", "rustbug", rival_id, String(event.get("theme", "kitchen")), "rae")
	_add_kicker("ACT %d · EVENT BRIEFING" % int(event["act"]))
	_add_heading(String(event["name"]))
	_add_copy("%s  ·  %s" % [String(event["environment"]), String(event["format"])], AMBER)
	var rival := CATALOG.get_driver(rival_id)
	var rival_vehicle := CATALOG.get_vehicle(String(rival.get("vehicle_id", "rustbug")))
	_add_section("LEAD RIVAL", "%s · %s" % [String(rival.get("name", "RACER")), String(rival_vehicle.get("name", "MACHINE"))])
	var progress: Dictionary = _app.call("get_save_data")
	if event_id == "kitchen_crumb_rush" and int(progress.get("best_event_finishes", {}).get(event_id, 0)) == 0:
		_add_section("FIRST RACE", "LEARN THE LINE, THEN FIND SPEED")
		_add_copy("W / Up or RT accelerate  ·  S / Down or LT brake  ·  A/D or left stick steer")
		_add_copy("Space / A drift  ·  Shift / B boost  ·  R / Y resets at the last legal gate", MUTED)
	_add_spacer(12)
	_add_button("CHOOSE VEHICLE", Callable(self, "show_vehicle_select").bind(event_id, false), AMBER)
	_add_button("BACK TO MAP", Callable(self, "show_map"), CREAM)
	_footer.text = "ESC / B  BACK"
	_focus_first()


func show_vehicle_select(event_id: String, quick_race: bool = false) -> void:
	_screen = "vehicle_select"
	_event_id = event_id
	_quick_race = quick_race
	_clear_content()
	var event := CATALOG.get_event(event_id)
	_add_kicker("QUICK RACE · %s" % String(event.get("name", "EVENT")) if quick_race else "GARAGE · %s" % String(event.get("name", "EVENT")))
	_add_heading("Choose machine")
	_add_copy("%s  ·  %s" % [String(event.get("environment", "CIRCUIT")), String(event.get("format", "RACE"))], BLUE)
	var progress: Dictionary = _app.call("get_save_data")
	var selected_vehicle: String = String(progress.get("selected_vehicle", "rustbug"))
	_current_vehicle_select_id = selected_vehicle
	var unlocked_vehicles: Array = progress.get("unlocked_vehicles", ["rustbug"])
	var event_theme := String(event.get("theme", "kitchen"))
	_configure_stage(&"vehicle", selected_vehicle, "rae", event_theme, "", unlocked_vehicles)
	var selected_button: Button
	for vehicle_index in CATALOG.VEHICLES.size():
		var vehicle: Dictionary = CATALOG.VEHICLES[vehicle_index]
		var vehicle_id := String(vehicle["id"])
		var unlocked := vehicle_id in unlocked_vehicles
		var access := "READY" if unlocked else "LOCKED"
		var summary := "%s  ·  %s" % [String(vehicle["name"]), access]
		var vehicle_button := _add_button(
			summary,
			func(): _select_vehicle_for_play(vehicle_id, event_theme, unlocked_vehicles),
			Color.from_string(String(vehicle["tint"]), AMBER),
			not unlocked,
			"Vehicle_%s" % vehicle_id
		)
		vehicle_button.custom_minimum_size = Vector2(0.0, 48.0)
		vehicle_button.add_theme_font_size_override("font_size", 16)
		if unlocked:
			vehicle_button.focus_entered.connect(_preview_vehicle.bind(vehicle_id, event_theme, unlocked_vehicles))
			vehicle_button.mouse_entered.connect(_preview_vehicle.bind(vehicle_id, event_theme, unlocked_vehicles))
		if vehicle_id == selected_vehicle:
			selected_button = vehicle_button
	_add_spacer(8)
	_add_big_play_button(Callable(self, "_start_current_selected_vehicle"), false)
	_add_button("BACK", Callable(self, "go_back"), CREAM)
	_footer.text = "ENTER / A  SELECT     ·     PLAY  RACE     ·     ESC / B  BACK"
	if selected_button:
		_grab_button_focus(selected_button)
		_queue_content_entrance()
		_grab_button_focus_after_layout(selected_button, _entrance_generation)
	else:
		_focus_first()


func show_settings() -> void:
	_screen = "settings"
	_clear_content()
	_content.add_theme_constant_override("separation", 5)
	_configure_stage(&"settings", "rustbug", "inez")
	_add_kicker("SETTINGS")
	_add_heading("Race your way")
	var settings: Dictionary = _app.call("get_save_data")
	_add_section("DIFFICULTY", "PACE ONLY · REWARDS & ACCESS UNCHANGED")
	var difficulty := OptionButton.new()
	difficulty.name = "Difficulty"
	difficulty.custom_minimum_size = Vector2(460.0, 48.0)
	var difficulty_ids := ["sunday_drive", "club_circuit", "clockwork"]
	for label: String in ["Sunday Drive · Earlier braking", "Club Circuit · Balanced", "Clockwork · Later braking"]:
		difficulty.add_item(label)
	var selected_index := maxi(0, difficulty_ids.find(String(settings["difficulty"])))
	difficulty.select(selected_index)
	difficulty.item_selected.connect(func(index: int) -> void: _app.call("update_setting", "difficulty", difficulty_ids[index]))
	_wire_button_audio(difficulty)
	_content.add_child(difficulty)
	_add_section("AUDIO", "")
	_add_slider("Master", float(settings["master_volume"]), "master_volume")
	_add_slider("Music", float(settings["music_volume"]), "music_volume")
	_add_slider("SFX", float(settings["sfx_volume"]), "sfx_volume")
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
	_add_button("BACK", Callable(self, "show_title"), CREAM)
	_footer.text = "CHANGES APPLY FOR THIS SESSION  ·  ESC / B  BACK" if bool(_app.call("is_save_read_only")) else "CHANGES SAVE AUTOMATICALLY  ·  ESC / B  BACK"
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
	_add_section("REVIEW SOUND EFFECTS", "KENNEY · CC0")
	_add_section("PRODUCTION", "DEVELOPER-DIRECTED · AI-ASSISTED")
	_add_copy("Original code, characters, vehicles, tracks, graphics, and music. Selected review effects use edited CC0 Kenney audio.")
	_add_copy("Licenses and provenance are included in THIRD_PARTY_NOTICES.md and ASSET_PROVENANCE.md.", MUTED)
	_add_button("BACK", Callable(self, "show_title"), CREAM)
	_footer.text = "ESC / B  BACK"
	_focus_first()


func show_save_error(title: String, detail: String, retry_action: Callable, back_action: Callable) -> void:
	_screen = "save_error"
	_clear_content()
	_configure_stage(&"title")
	_save_error_back_action = back_action
	_add_kicker("SAVE ERROR")
	_add_heading(title)
	_add_copy("Pocket Circuit could not write the requested change. Existing progress remains unchanged.", CORAL)
	_add_quote(detail if not detail.is_empty() else "The save file could not be written. Check available disk space and folder permissions.", CORAL)
	_add_button("TRY AGAIN", retry_action, AMBER)
	_add_button("BACK", Callable(self, "_leave_save_error"), CREAM)
	_footer.text = "DO NOT CLOSE THE GAME UNTIL PROGRESS IS SAVED  ·  ESC / B  BACK"
	_focus_first()


func show_ending() -> void:
	_screen = "ending"
	_clear_content()
	_configure_stage(&"ending", "rustbug", "rae", "office", "cass")
	_add_kicker("CHAMPIONSHIP COMPLETE")
	_add_heading("Champion.")
	_add_copy("Grand Household Circuit complete.", AMBER)
	var progress: Dictionary = _app.call("get_save_data")
	var series_points := 0
	for act: Dictionary in CATALOG.ACTS:
		series_points += CATALOG.act_points(progress, int(act["number"]))
	_add_section("FINAL STANDINGS", "%d / %d SERIES POINTS" % [series_points, CATALOG.EVENTS.size() * 10])
	_add_section("GARAGE UNLOCK", "FLICKER · DRIFT")
	_add_copy("Every completed event is open for immediate replay with any unlocked vehicle.")
	_add_button("REPLAY THE CHAMPIONSHIP", Callable(_app, "finish_ending").bind("map"), AMBER)
	_add_button("RETURN TO TITLE", Callable(_app, "finish_ending").bind("title"), CREAM)
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
		"map", "settings", "credits", "reset_confirmation", "quick_race":
			show_title()
		"save_error":
			_leave_save_error()
		"briefing":
			show_map()
		"vehicle_select":
			if _quick_race:
				show_quick_race()
			else:
				show_briefing(_event_id)
		"ending":
			_app.call("finish_ending", "map")


func _build_base() -> void:
	layer = 100
	_root = Control.new()
	_root.name = "ApplicationShell"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = _make_theme()
	add_child(_root)

	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = INK
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(background)
	var backdrop := TextureRect.new()
	backdrop.texture = MENU_BACKGROUND
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.modulate = Color.WHITE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(backdrop)
	var top_rail := ColorRect.new()
	top_rail.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_rail.offset_bottom = 8.0
	top_rail.color = AMBER
	top_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top_rail)
	var rail_cut := ColorRect.new()
	rail_cut.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	rail_cut.offset_left = -310.0
	rail_cut.offset_bottom = 8.0
	rail_cut.color = CORAL
	rail_cut.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rail_cut)
	var bench_rail := ColorRect.new()
	bench_rail.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bench_rail.offset_top = -22.0
	bench_rail.color = WORKBENCH
	bench_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bench_rail)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_bottom", 28)
	_root.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	margin.add_child(page)
	var brand := Label.new()
	brand.text = "GHC / AFTER HOURS WORKSHOP"
	brand.add_theme_font_size_override("font_size", 13)
	brand.add_theme_color_override("font_color", AMBER)
	page.add_child(brand)
	page.add_child(HSeparator.new())
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
	_footer = Label.new()
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_footer.add_theme_font_size_override("font_size", 12)
	_footer.add_theme_color_override("font_color", MUTED)
	page.add_child(_footer)


func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.set_color("font_color", "Label", PAPER)
	theme.set_color("font_color", "Button", PAPER)
	theme.set_color("font_hover_color", "Button", CREAM)
	theme.set_color("font_focus_color", "Button", CREAM)
	theme.set_color("font_disabled_color", "Button", Color(MUTED, 0.55))
	theme.set_font_size("font_size", "Button", 18)
	theme.set_font_size("font_size", "OptionButton", 18)
	theme.set_font_size("font_size", "CheckButton", 18)
	theme.set_stylebox("normal", "Button", _plate(Color("1c2633"), Color("4a5a6c"), 2))
	theme.set_stylebox("hover", "Button", _plate(Color("2a3646"), AMBER, 2))
	theme.set_stylebox("pressed", "Button", _plate(Color("17202a"), AMBER, 2))
	theme.set_stylebox("focus", "Button", _plate(Color("2a3646"), AMBER, 3))
	theme.set_stylebox("disabled", "Button", _plate(Color("161c24"), Color("2a323c"), 1))
	theme.set_color("font_hover_color", "Button", CREAM)
	theme.set_color("font_focus_color", "Button", CREAM)
	for kind: String in ["OptionButton", "CheckButton"]:
		theme.set_stylebox("normal", kind, _plate(Color("1c2633"), Color("4a5a6c"), 2))
		theme.set_stylebox("hover", kind, _plate(Color("2a3646"), AMBER, 2))
		theme.set_stylebox("pressed", kind, _plate(Color("17202a"), AMBER, 2))
		theme.set_stylebox("focus", kind, _plate(Color("2a3646"), AMBER, 3))
		theme.set_color("font_color", kind, PAPER)
		theme.set_color("font_hover_color", kind, CREAM)
		theme.set_color("font_focus_color", kind, CREAM)
	return theme


func _style(fill: Color, border: Color, radius: int, width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 12.0
	box.content_margin_bottom = 12.0
	return box


func _plate(fill: Color, border: Color, width: int = 2, radius: int = 8) -> StyleBoxFlat:
	return _style(fill, border, radius, width)


func _apply_button_art(button: Button, primary: bool) -> void:
	var fill := CORAL if primary else Color("1c2633")
	var border := AMBER if primary else Color("4a5a6c")
	var active_fill := Color("f6a43d") if primary else Color("2a3646")
	button.add_theme_color_override("font_color", INK if primary else CREAM)
	button.add_theme_color_override("font_hover_color", INK if primary else AMBER)
	button.add_theme_color_override("font_focus_color", INK if primary else AMBER)
	button.add_theme_color_override("font_pressed_color", INK if primary else CREAM)
	button.add_theme_color_override("font_disabled_color", Color(MUTED, 0.55))
	button.add_theme_stylebox_override("normal", _plate(fill, border, 2))
	button.add_theme_stylebox_override("hover", _plate(active_fill, AMBER, 2))
	button.add_theme_stylebox_override("pressed", _plate(fill.darkened(0.16), AMBER, 2))
	button.add_theme_stylebox_override("focus", _plate(active_fill, AMBER, 3))
	button.add_theme_stylebox_override("disabled", _plate(Color("161c24"), Color("2a323c"), 1))


func _apply_compact_button_art(button: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := button.get_theme_stylebox(state) as StyleBoxFlat
		var compact := style.duplicate() as StyleBoxFlat
		compact.content_margin_left = 8.0
		compact.content_margin_right = 8.0
		compact.content_margin_top = 4.0
		compact.content_margin_bottom = 4.0
		button.add_theme_stylebox_override(state, compact)


func _clear_content() -> void:
	_entrance_generation += 1
	_save_error_back_action = Callable()
	_button_focus_chain.clear()
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


func _preview_vehicle(vehicle_id: String, event_theme: String, unlocked_vehicles: Array) -> void:
	_configure_stage(&"vehicle", vehicle_id, "rae", event_theme, "", unlocked_vehicles)


func _select_vehicle_for_play(vehicle_id: String, event_theme: String, unlocked_vehicles: Array) -> void:
	_current_vehicle_select_id = vehicle_id
	_configure_stage(&"vehicle", vehicle_id, "rae", event_theme, "", unlocked_vehicles)


func _add_title_lockup() -> void:
	var pocket := _label("POCKET", 54, CREAM)
	pocket.add_theme_constant_override("outline_size", 8)
	pocket.custom_minimum_size = Vector2(0.0, 60.0)
	_content.add_child(pocket)
	var circuit := _label("CIRCUIT", 64, AMBER)
	circuit.add_theme_constant_override("outline_size", 8)
	circuit.custom_minimum_size = Vector2(0.0, 70.0)
	_content.add_child(circuit)
	var tagline := _label("TINY RACING  /  BIG HOUSE", 15, PAPER)
	tagline.custom_minimum_size = Vector2(0.0, 26.0)
	_content.add_child(tagline)


func _add_big_play_button(callback: Callable, disabled: bool) -> Button:
	var button := _make_button("PLAY", callback, CORAL, disabled)
	button.custom_minimum_size = Vector2(0.0, 72.0)
	button.add_theme_font_size_override("font_size", 28)
	_content.add_child(button)
	if not disabled:
		_register_button_focus(button)
	return button


func _add_action_row(actions: Array[Dictionary]) -> void:
	if actions.is_empty():
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_content.add_child(row)
	var row_buttons: Array[Button] = []
	for action: Dictionary in actions:
		var button := _make_button(
			String(action.get("text", "ACTION")),
			action.get("callback", Callable()) as Callable,
			action.get("accent", CREAM) as Color,
			bool(action.get("disabled", false))
		)
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.custom_minimum_size = Vector2(0.0, 44.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 15)
		row.add_child(button)
		if not button.disabled:
			row_buttons.append(button)
	if not row_buttons.is_empty():
		var previous_focus: Button = _button_focus_chain.back() if not _button_focus_chain.is_empty() else null
		_register_button_focus(row_buttons[0])
		for button: Button in row_buttons.slice(1):
			if previous_focus:
				button.focus_neighbor_top = button.get_path_to(previous_focus)
	for index in row_buttons.size():
		if index > 0:
			row_buttons[index].focus_neighbor_left = row_buttons[index].get_path_to(row_buttons[index - 1])
		if index < row_buttons.size() - 1:
			row_buttons[index].focus_neighbor_right = row_buttons[index].get_path_to(row_buttons[index + 1])


func _add_kicker(text: String) -> void:
	var label := _label(text, 15, AMBER)
	label.uppercase = true
	_content.add_child(label)


func _add_heading(text: String) -> void:
	var label := _label(text, 36, CREAM)
	label.custom_minimum_size = Vector2(0.0, 52.0)
	_content.add_child(label)


func _add_copy(text: String, color: Color = PAPER) -> void:
	var label := _label(text, 18, color)
	label.custom_minimum_size = Vector2(0.0, 34.0)
	_content.add_child(label)


func _add_quote(text: String, color: Color = PAPER) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color("202a3e"), color, 6, 2))
	var label := _label(text, 19, color)
	label.custom_minimum_size = Vector2(0.0, 62.0)
	panel.add_child(label)
	_content.add_child(panel)


func _add_section(left: String, right: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var left_label := _label(left, 19, CREAM)
	left_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left_label)
	var right_label := _label(right, 14, MUTED)
	right_label.custom_minimum_size = Vector2(320.0, 0.0)
	right_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	right_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(right_label)
	_content.add_child(row)


func _add_result_notice(summary: Dictionary) -> void:
	var message := "RESULT FILED"
	if int(summary.get("points_gained", 0)) > 0:
		message += "  ·  +%d POINTS" % int(summary["points_gained"])
	if bool(summary.get("act_completed", false)):
		message += "  ·  ACT WON"
	var unlocked: Array = summary.get("unlocked_vehicles", [])
	if not unlocked.is_empty():
		message += "  ·  %s UNLOCKED" % String(CATALOG.get_vehicle(String(unlocked[0]))["name"]).to_upper()
	_add_copy(message, AMBER)


func _add_button(text: String, callback: Callable, accent: Color, disabled: bool = false, node_name: String = "") -> Button:
	var button := _make_button(text, callback, accent, disabled, node_name)
	_content.add_child(button)
	if not disabled:
		_register_button_focus(button)
	return button


func _make_button(text: String, callback: Callable, accent: Color, disabled: bool = false, node_name: String = "") -> Button:
	var button := Button.new()
	if not node_name.is_empty():
		button.name = node_name
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(0.0, 44.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.disabled = disabled
	_apply_button_art(button, accent == CORAL)
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
	var previous := _make_button("← PREVIOUS ACT", callback.bind(previous_act), CREAM, previous_disabled)
	previous.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(previous)
	if not previous_disabled:
		focusable_buttons.append(previous)
	var next_disabled := current_index < 0 or current_index >= act_numbers.size() - 1
	var next_act := act_numbers[mini(act_numbers.size() - 1, current_index + 1)] if not act_numbers.is_empty() else act_number
	var next := _make_button("NEXT ACT →", callback.bind(next_act), CREAM, next_disabled)
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


func _add_circuit_buttons(circuit_entries: Array, page_start: int, page_end: int) -> Array[Button]:
	var buttons: Array[Button] = []
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	_content.add_child(grid)
	for entry_index in range(page_start, page_end):
		var entry: Dictionary = circuit_entries[entry_index]
		var button := _make_button(
			"%s · SEED %d" % [String(entry["label"]).to_upper(), int(entry["seed"])],
			Callable(self, "_start_circuit").bind(entry),
			BLUE,
			false,
			"Circuit_%s_%d" % [String(entry["theme"]), int(entry["seed"])]
		)
		button.custom_minimum_size = Vector2(0.0, 30.0)
		button.add_theme_font_size_override("font_size", 13)
		_apply_compact_button_art(button)
		grid.add_child(button)
		_register_button_focus(button)
		buttons.append(button)
	for index in buttons.size():
		if index % 2 == 1:
			buttons[index].focus_neighbor_left = buttons[index].get_path_to(buttons[index - 1])
			buttons[index - 1].focus_neighbor_right = buttons[index - 1].get_path_to(buttons[index])
		if index >= 2:
			buttons[index].focus_neighbor_top = buttons[index].get_path_to(buttons[index - 2])
			buttons[index - 2].focus_neighbor_bottom = buttons[index - 2].get_path_to(buttons[index])
	return buttons


func _add_circuit_navigation(page_count: int) -> Array[Button]:
	var previous_focus: Button = _button_focus_chain.back() if not _button_focus_chain.is_empty() else null
	var focusable_buttons: Array[Button] = []
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_content.add_child(row)
	var previous_page := posmod(_quick_race_circuit_page - 1, page_count)
	var previous := _make_button("PREV CIRCUITS", Callable(self, "_show_quick_race_circuit_page").bind(previous_page), CREAM)
	previous.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(previous)
	focusable_buttons.append(previous)
	var next_page := posmod(_quick_race_circuit_page + 1, page_count)
	var next := _make_button("NEXT CIRCUITS", Callable(self, "_show_quick_race_circuit_page").bind(next_page), CREAM)
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(next)
	focusable_buttons.append(next)
	var theme_button_label := "OFFICE CIRCUITS" if _quick_race_circuit_theme == "workshop" else "WORKSHOP CIRCUITS"
	var theme := _make_button(theme_button_label, Callable(self, "_toggle_quick_race_circuit_theme"), AMBER)
	theme.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(theme)
	focusable_buttons.append(theme)
	var back := _make_button("BACK TO TITLE", Callable(self, "show_title"), CREAM)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(back)
	focusable_buttons.append(back)
	for button: Button in focusable_buttons:
		button.custom_minimum_size = Vector2(0.0, 30.0)
		button.add_theme_font_size_override("font_size", 13)
		_apply_compact_button_art(button)
	_register_button_focus(focusable_buttons[0])
	for button: Button in focusable_buttons.slice(1):
		if previous_focus:
			button.focus_neighbor_top = button.get_path_to(previous_focus)
	for index in focusable_buttons.size():
		if index > 0:
			focusable_buttons[index].focus_neighbor_left = focusable_buttons[index].get_path_to(focusable_buttons[index - 1])
		if index < focusable_buttons.size() - 1:
			focusable_buttons[index].focus_neighbor_right = focusable_buttons[index].get_path_to(focusable_buttons[index + 1])
	return focusable_buttons


func _complete_focus_row(focusable_buttons: Array[Button], following_button: Button) -> void:
	for button: Button in focusable_buttons.slice(1):
		button.focus_neighbor_bottom = button.get_path_to(following_button)


func _register_button_focus(button: Button) -> void:
	if not _button_focus_chain.is_empty():
		var previous: Button = _button_focus_chain.back()
		previous.focus_neighbor_bottom = previous.get_path_to(button)
		button.focus_neighbor_top = button.get_path_to(previous)
	_button_focus_chain.append(button)


func _add_slider(label_text: String, value: float, setting_key: String) -> void:
	var row := HBoxContainer.new()
	var label := _label(label_text, 18, PAPER)
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


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 4 if size > 20 else 2)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


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
			_scroll.scroll_vertical = 0
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
	show_briefing(event_id)


func _show_map_act(act_number: int) -> void:
	show_map({}, act_number)


func _show_quick_race_act(act_number: int) -> void:
	show_quick_race(act_number)


func _show_quick_race_circuit_page(page: int) -> void:
	_quick_race_circuit_page = page
	show_quick_race()


func _toggle_quick_race_circuit_theme() -> void:
	_quick_race_circuit_theme = "office" if _quick_race_circuit_theme == "workshop" else "workshop"
	_quick_race_circuit_page = 0
	show_quick_race()


func _start_circuit(entry: Dictionary) -> void:
	var progress: Dictionary = _app.call("get_save_data")
	var vehicle_id := String(progress.get("selected_vehicle", "rustbug"))
	if not vehicle_id in progress.get("unlocked_vehicles", ["rustbug"]):
		vehicle_id = "rustbug"
	_app.call("start_circuit_race", StringName(entry["theme"]), StringName(entry.get("room", "classic")), int(entry["seed"]), vehicle_id)


func _start_with_vehicle(vehicle_id: String) -> void:
	_app.call("start_race", _event_id, vehicle_id, _quick_race)


func _start_current_selected_vehicle() -> void:
	if not _current_vehicle_select_id.is_empty():
		_start_with_vehicle(_current_vehicle_select_id)


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
