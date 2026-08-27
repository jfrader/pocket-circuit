extends CanvasLayer

const CATALOG := preload("res://data/championship/catalog.gd")

const INK := Color("172033")
const PAPER := Color("f2ead7")
const CREAM := Color("fff8e8")
const AMBER := Color("f4bf3a")
const CORAL := Color("e96b4c")
const BLUE := Color("55a8c9")
const MUTED := Color("aeb7c8")

var _app: Node
var _root: Control
var _scroll: ScrollContainer
var _content: VBoxContainer
var _footer: Label
var _button_focus_chain: Array[Button] = []
var _screen := "title"
var _event_id := ""
var _quick_race := false
var _content_tween: Tween
var _entrance_generation := 0
var _save_error_back_action := Callable()


func configure(app: Node) -> void:
	_app = app
	if _root == null:
		_build_base()


func show_title() -> void:
	_screen = "title"
	_event_id = ""
	_quick_race = false
	_clear_content()
	_add_kicker("GRAND HOUSEHOLD CIRCUIT · OFFLINE CHAMPIONSHIP")
	_add_heading("Tiny racing.\nBig stakes.")
	_add_copy("Win the Grand Household Circuit before sunrise. Three rooms, nine events, four original machines.")
	var save_read_only := bool(_app.call("is_save_read_only"))
	if save_read_only:
		_add_copy("A save from a newer Pocket Circuit version was found. It remains untouched; championship changes are disabled in this version.", CORAL)
	_add_spacer(10)
	if bool(_app.call("has_championship_progress")):
		_add_button("CONTINUE CHAMPIONSHIP", Callable(_app, "continue_championship"), AMBER)
	_add_button("NEW CHAMPIONSHIP", Callable(_app, "request_new_championship"), CREAM, save_read_only)
	_add_button("QUICK RACE", Callable(_app, "open_quick_race"), BLUE)
	_add_button("SETTINGS", Callable(self, "show_settings"), CREAM)
	_add_button("CREDITS", Callable(self, "show_credits"), CREAM)
	_add_button("QUIT", Callable(_app, "quit_game"), CORAL)
	_footer.text = "ARROWS / STICK  MOVE     ·     ENTER / A  SELECT"
	_focus_first()


func show_reset_confirmation() -> void:
	_screen = "reset_confirmation"
	_clear_content()
	_add_kicker("NEW CHAMPIONSHIP")
	_add_heading("Erase the current standings?")
	_add_copy("Best finishes, act wins, vehicle unlocks, and the ending flag will be reset. Settings stay exactly as they are.")
	_add_spacer(18)
	_add_button("ERASE & START AGAIN", Callable(_app, "confirm_new_championship"), CORAL)
	_add_button("KEEP CURRENT CHAMPIONSHIP", Callable(self, "show_title"), CREAM)
	_footer.text = "ESC / B  BACK"
	_focus_first()


func show_map(result_summary: Dictionary = {}) -> void:
	_screen = "map"
	_event_id = ""
	_quick_race = false
	_clear_content()
	_add_kicker("CHAMPIONSHIP MAP")
	_add_heading("Grand Household Circuit")
	if not result_summary.is_empty():
		_add_result_notice(result_summary)
	var progress: Dictionary = _app.call("get_save_data")
	var best_finishes: Dictionary = progress.get("best_event_finishes", {})
	var recommended_event_id := ""
	for event: Dictionary in CATALOG.EVENTS:
		var candidate_id := String(event["id"])
		if CATALOG.is_event_unlocked(candidate_id, progress) and int(best_finishes.get(candidate_id, 0)) == 0:
			recommended_event_id = candidate_id
			break
	if not recommended_event_id.is_empty():
		var recommended_event := CATALOG.get_event(recommended_event_id)
		_add_quote("NEXT UP  ·  %s  ·  %s" % [String(recommended_event["name"]), String(recommended_event["format"])], AMBER)
	var recommended_button: Button
	for act: Dictionary in CATALOG.ACTS:
		var act_number := int(act["number"])
		var act_complete: bool = String(act["id"]) in progress.get("completed_acts", [])
		var standings := "%d PTS" % CATALOG.act_points(progress, act_number)
		if act_complete:
			standings += "  ·  WON"
		_add_section("ACT %d  ·  %s" % [act_number, String(act["name"])], standings)
		for event: Dictionary in CATALOG.EVENTS:
			if int(event["act"]) != act_number:
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
				"%s\n%s  ·  %s" % [String(event["name"]), String(event["environment"]), status],
				Callable(self, "_open_event").bind(event_id),
				AMBER if unlocked else MUTED,
				not unlocked,
				"Event_%s" % event_id
			)
			if event_id == recommended_event_id:
				recommended_button = event_button
	_add_button("RETURN TO TITLE", Callable(self, "show_title"), CREAM)
	_footer.text = "10 POINTS OPENS EVENT TWO  ·  20 POINTS OPENS EACH FINALE  ·  ESC / B BACK"
	if recommended_button:
		_queue_content_entrance()
		_grab_button_focus_after_layout(recommended_button, _entrance_generation)
	else:
		_focus_first()


func show_quick_race() -> void:
	_screen = "quick_race"
	_event_id = ""
	_quick_race = true
	_clear_content()
	_add_kicker("QUICK RACE · EXHIBITION")
	_add_heading("Pick a circuit")
	_add_copy("Practice Crumb Rush or replay a completed event without changing championship standings, points, or unlocks.")
	var progress: Dictionary = _app.call("get_save_data")
	var completed_events: Array = progress.get("completed_events", [])
	var best_finishes: Dictionary = progress.get("best_event_finishes", {})
	for event: Dictionary in CATALOG.EVENTS:
		var event_id := String(event["id"])
		if event_id != "kitchen_crumb_rush" and not event_id in completed_events:
			continue
		var finish := int(best_finishes.get(event_id, 0))
		var status := "PRACTICE ROUTE"
		if finish > 0:
			status = "BEST %s · %d PTS" % [_ordinal(finish), int(progress["best_event_points"].get(event_id, 0))]
		_add_button(
			"%s\n%s  ·  %s  ·  %s" % [String(event["name"]), String(event["environment"]), String(event["format"]), status],
			Callable(self, "show_vehicle_select").bind(event_id, true),
			BLUE,
			false,
			"QuickRace_%s" % event_id
		)
	_add_button("BACK TO TITLE", Callable(self, "show_title"), CREAM)
	_footer.text = "EXHIBITION RESULTS DO NOT SAVE  ·  ESC / B  BACK"
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
	_add_kicker("ACT %d · EVENT BRIEFING" % int(event["act"]))
	_add_heading(String(event["name"]))
	_add_copy("%s  ·  %s" % [String(event["environment"]), String(event["format"])], AMBER)
	_add_spacer(10)
	_add_quote(String(event["story"]))
	_add_quote(String(event["rival_line"]), BLUE)
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
	_add_heading("Choose your machine")
	_add_copy("%s  ·  %s" % [String(event.get("environment", "CIRCUIT")), String(event.get("format", "RACE"))], BLUE)
	_add_copy("Every unlocked vehicle is a side-grade. Pick the handling style that suits your line.")
	var progress: Dictionary = _app.call("get_save_data")
	var selected_vehicle := String(progress.get("selected_vehicle", "rustbug"))
	var selected_button: Button
	for vehicle_id: String in progress.get("unlocked_vehicles", ["rustbug"]):
		var vehicle := CATALOG.get_vehicle(vehicle_id)
		if vehicle.is_empty():
			continue
		var summary := "%s · %s\n%s\nTradeoff: %s" % [
			String(vehicle["name"]), String(vehicle["archetype"]),
			String(vehicle["strength"]), String(vehicle["tradeoff"]),
		]
		var vehicle_button := _add_button(
			summary,
			Callable(self, "_start_with_vehicle").bind(vehicle_id),
			Color.from_string(String(vehicle["tint"]), AMBER),
			false,
			"Vehicle_%s" % vehicle_id
		)
		if vehicle_id == selected_vehicle:
			selected_button = vehicle_button
	_add_button("BACK", Callable(self, "go_back"), CREAM)
	_footer.text = "ENTER / A  RACE     ·     ESC / B  BACK"
	if selected_button:
		_queue_content_entrance()
		_grab_button_focus_after_layout(selected_button, _entrance_generation)
	else:
		_focus_first()


func show_settings() -> void:
	_screen = "settings"
	_clear_content()
	_add_kicker("SETTINGS")
	_add_heading("Race your way")
	var settings: Dictionary = _app.call("get_save_data")
	_add_section("DIFFICULTY", "REWARDS AND ACCESS NEVER CHANGE")
	var difficulty := OptionButton.new()
	difficulty.name = "Difficulty"
	difficulty.custom_minimum_size = Vector2(460.0, 48.0)
	var difficulty_ids := ["sunday_drive", "club_circuit", "clockwork"]
	for label: String in ["Sunday Drive", "Club Circuit", "Clockwork"]:
		difficulty.add_item(label)
	var selected_index := maxi(0, difficulty_ids.find(String(settings["difficulty"])))
	difficulty.select(selected_index)
	difficulty.item_selected.connect(func(index: int) -> void: _app.call("update_setting", "difficulty", difficulty_ids[index]))
	_wire_button_audio(difficulty)
	_content.add_child(difficulty)
	_add_copy("Sunday Drive brakes early. Club Circuit is the intended baseline. Clockwork attacks late and clean.")
	_add_section("AUDIO", "APPLIES IMMEDIATELY WHEN THE BUS EXISTS")
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
	_add_kicker("CREDITS & NOTICES")
	_add_heading("Built after hours")
	_add_section("DEVELOPMENT", "GURISITOS GAMES")
	_add_quote("Pocket Circuit\nCreated and published by Gurisitos Games")
	_add_copy("Championship story, characters, vehicles, event names, dialogue, visual assets, music, and sound effects are original to Pocket Circuit.")
	_add_section("ENGINE", "GODOT ENGINE · MIT LICENSE")
	_add_copy("Godot Engine copyright © 2007-present Juan Linietsky, Ariel Manzur, and Godot Engine contributors.")
	_add_copy("The complete MIT license is included with the game in THIRD_PARTY_NOTICES.md.", MUTED)
	_add_section("PRODUCTION", "AI-ASSISTED ORIGINAL CONTENT")
	_add_copy("AI-assisted production tools supported developer-directed code, graphics, and synthesized sound creation. No third-party source media, samples, characters, vehicles, tracks, or branding are included.")
	_add_copy("Asset provenance and original audio details are included with the game in ASSET_PROVENANCE.md and assets/audio/LICENSE.md.", MUTED)
	_add_button("BACK", Callable(self, "show_title"), CREAM)
	_footer.text = "ESC / B  BACK"
	_focus_first()


func show_save_error(title: String, detail: String, retry_action: Callable, back_action: Callable) -> void:
	_screen = "save_error"
	_clear_content()
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
	_add_kicker("CHAMPIONSHIP COMPLETE")
	_add_heading("The circuit stays open.")
	_add_quote("The office clock ticks into sunrise as Cass rolls aside. Rae's Rustbug crosses the last pool of lamplight, and every rookie waiting below the desk gets a place on next year's grid.", AMBER)
	_add_quote("Cass: The circuit needed a champion. Turns out it needed a newcomer more.", BLUE)
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
	var rail := ColorRect.new()
	rail.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	rail.offset_right = 24.0
	rail.color = AMBER
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(rail)
	var corner := ColorRect.new()
	corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	corner.offset_left = -240.0
	corner.offset_bottom = 12.0
	corner.color = CORAL
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(corner)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 72)
	margin.add_theme_constant_override("margin_top", 42)
	margin.add_theme_constant_override("margin_right", 72)
	margin.add_theme_constant_override("margin_bottom", 32)
	_root.add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	margin.add_child(page)
	var brand := Label.new()
	brand.text = "POCKET / CIRCUIT"
	brand.add_theme_font_size_override("font_size", 18)
	brand.add_theme_color_override("font_color", AMBER)
	page.add_child(brand)
	var separator := HSeparator.new()
	page.add_child(separator)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.custom_minimum_size = Vector2(760.0, 0.0)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	_scroll.add_child(_content)
	_footer = Label.new()
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_footer.add_theme_font_size_override("font_size", 13)
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
	theme.set_stylebox("normal", "Button", _style(Color("242f46"), Color("46536b"), 8))
	theme.set_stylebox("hover", "Button", _style(Color("303f5b"), AMBER, 8))
	theme.set_stylebox("pressed", "Button", _style(Color("1e293d"), AMBER, 8))
	theme.set_stylebox("focus", "Button", _style(Color("344761"), AMBER, 8, 4))
	theme.set_stylebox("disabled", "Button", _style(Color("20283a"), Color("30394d"), 8))
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


func _clear_content() -> void:
	_entrance_generation += 1
	_save_error_back_action = Callable()
	_button_focus_chain.clear()
	_scroll.scroll_vertical = 0
	_scroll.set_deferred("scroll_vertical", 0)
	if _content_tween and _content_tween.is_valid():
		_content_tween.kill()
	_content.modulate = Color.WHITE
	for child: Node in _content.get_children():
		child.queue_free()


func _add_kicker(text: String) -> void:
	var label := _label(text, 15, AMBER)
	label.uppercase = true
	_content.add_child(label)


func _add_heading(text: String) -> void:
	var label := _label(text, 44, CREAM)
	label.custom_minimum_size = Vector2(0.0, 70.0)
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
	_add_quote(message, AMBER)


func _add_button(text: String, callback: Callable, accent: Color, disabled: bool = false, node_name: String = "") -> Button:
	var button := Button.new()
	if not node_name.is_empty():
		button.name = node_name
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(560.0, 52.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.disabled = disabled
	button.add_theme_color_override("font_hover_color", accent)
	button.add_theme_color_override("font_focus_color", accent)
	_wire_button_audio(button)
	if callback.is_valid():
		button.pressed.connect(callback)
	_content.add_child(button)
	if not disabled:
		_register_button_focus(button)
	return button


func _register_button_focus(button: Button) -> void:
	if not _button_focus_chain.is_empty():
		var previous: Button = _button_focus_chain.back()
		previous.focus_neighbor_bottom = previous.get_path_to(button)
		button.focus_neighbor_top = button.get_path_to(previous)
	_button_focus_chain.append(button)
	button.focus_entered.connect(_queue_control_visible.bind(button, _entrance_generation))


func _queue_control_visible(control: Control, generation: int) -> void:
	call_deferred("_ensure_control_visible", control, generation)


func _ensure_control_visible(control: Control, generation: int) -> void:
	if generation == _entrance_generation and is_instance_valid(_scroll) and is_instance_valid(control):
		_scroll.ensure_control_visible(control)


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


func _start_with_vehicle(vehicle_id: String) -> void:
	_app.call("start_race", _event_id, vehicle_id, _quick_race)


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
