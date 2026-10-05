class_name CircuitDiscoveryPanel
extends VBoxContainer

signal back_requested

const BUTTON_SCRIPT := preload("res://scripts/ui/motorsport_button.gd")
const PREVIEW_CONTROL := preload("res://scripts/ui/circuit_preview_control.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const GENERATED_RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const GENERATED_CIRCUITS := preload("res://scripts/race/generated_circuit_identity.gd")

var _app: Node
var _mode := "browser"
var _identity: Dictionary = {}
var _preview: Dictionary = {}
var _generation := 0
var _status: Label
var _favorite_button: Button
var _launch_button: Button
var _favorite_status: Label
var _is_favorite := false
var _size_selector: OptionButton
var _preview_control: CircuitPreviewControl
var _share_line: LineEdit
var _back_button: Button


func configure(app: Node) -> void:
	_app = app
	add_theme_constant_override("separation", 7)
	show_browser()


func show_browser() -> void:
	_mode = "browser"
	_identity.clear()
	_preview.clear()
	_generation += 1
	_clear()
	_add_kicker("CIRCUIT DISCOVERY")
	_add_label("Share an offline circuit", 34, SKIN.CREAM, true)
	var code_edit := LineEdit.new()
	code_edit.name = "DiscoveryCode"
	code_edit.placeholder_text = "PC1-…"
	code_edit.custom_minimum_size = Vector2(0.0, 48.0)
	code_edit.focus_mode = Control.FOCUS_ALL
	code_edit.select_all_on_focus = true
	code_edit.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	add_child(code_edit)
	var import_button := _button("PREVIEW CODE", _import_code.bind(code_edit), true, "DiscoveryImport")
	code_edit.text_submitted.connect(func(_text: String) -> void: _import_code(code_edit))
	_status = _add_label("Paste a share code.", 14, SKIN.CREAM_DIM)
	var library: Dictionary = _app.call("get_circuit_library")
	_add_library_section("FAVORITES", library.get("favorites", []), 2)
	_add_library_section("RECENT", library.get("history", []), 2)
	var back := _button("BACK TO TITLE", _request_back, false, "DiscoveryBack")
	var focusables: Array[Control] = [code_edit, import_button]
	for child: Node in get_children():
		if child is Button and child != import_button and child != back:
			focusables.append(child as Button)
	focusables.append(back)
	_wire_vertical(focusables)
	call_deferred("_focus_control", code_edit, _generation)


func show_confirmation(identity_value: Dictionary) -> void:
	_identity = identity_value.duplicate(true)
	# The launch builds the whole circuit layout; start that now so a player who
	# reads the confirmation before pressing Race starts it warm.
	if _app.has_method("prewarm_generated_circuit"):
		_app.call("prewarm_generated_circuit", GENERATED_CIRCUITS.apply_to_event(_identity))
	_preview.clear()
	_mode = "confirmation"
	_generation += 1
	var generation := _generation
	_clear()
	_add_kicker("OFFLINE CIRCUIT PREVIEW")
	_add_label(String(_identity.get("display_name", "Generated Circuit")), 32, SKIN.CREAM, true)
	var summary := _add_label(String(_identity.get("summary", "")), 15, SKIN.CREAM_DIM)
	summary.custom_minimum_size = Vector2(0.0, 58.0)
	_size_selector = _add_size_selector()
	_preview_control = PREVIEW_CONTROL.new() as CircuitPreviewControl
	_preview_control.name = "CircuitRoutePreview"
	_preview_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview_control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_preview_control)
	var encoded: Dictionary = _app.call("circuit_share_code", _identity)
	_share_line = LineEdit.new()
	_share_line.name = "DiscoveryShareCode"
	_share_line.text = String(encoded.get("code", ""))
	_share_line.editable = false
	_share_line.selecting_enabled = true
	_share_line.custom_minimum_size = Vector2(0.0, 38.0)
	_share_line.focus_mode = Control.FOCUS_ALL
	add_child(_share_line)
	var library: Dictionary = _app.call("get_circuit_library")
	_is_favorite = false
	for entry: Dictionary in library.get("favorites", []):
		if String(entry.get("fingerprint", "")) == String(_identity.get("fingerprint", "")):
			_is_favorite = true
			break
	_favorite_button = _button("REMOVE FAVORITE" if _is_favorite else "ADD FAVORITE", _toggle_favorite, false, "DiscoveryFavorite")
	_favorite_status = _add_label("", 13, SKIN.CREAM_DIM)
	_favorite_status.name = "DiscoveryFavoriteStatus"
	if _app.has_method("is_save_read_only") and bool(_app.call("is_save_read_only")):
		_favorite_button.disabled = true
		_set_favorite_error("Favorites are unavailable because this save is read-only. Start with a compatible save to change them.")
	_launch_button = _button("PREPARING PREVIEW…", Callable(), true, "DiscoveryLaunch")
	_launch_button.disabled = true
	_back_button = _button("BACK TO DISCOVERY", show_browser, false, "DiscoveryConfirmationBack")
	_wire_vertical([_size_selector, _share_line, _favorite_button, _launch_button, _back_button])
	call_deferred("_focus_control", _share_line if _favorite_button.disabled else _favorite_button, generation)
	await _refresh_preview(generation)


func _add_size_selector() -> OptionButton:
	var selector := OptionButton.new()
	selector.name = "DiscoverySize"
	selector.focus_mode = Control.FOCUS_ALL
	selector.custom_minimum_size = Vector2(0.0, 42.0)
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.add_theme_font_size_override("font_size", 16)
	for tier: String in GENERATED_RULES.LENGTH_TIERS:
		selector.add_item(String(GENERATED_RULES.length_profile(tier)["label"]))
	var selected_index := GENERATED_RULES.LENGTH_TIERS.find(String(_identity.get("length_tier", GENERATED_RULES.DEFAULT_LENGTH_TIER)))
	if selected_index >= 0:
		selector.select(selected_index)
	selector.item_selected.connect(_on_size_selected)
	add_child(selector)
	return selector


func _refresh_preview(generation: int) -> void:
	if not is_instance_valid(_launch_button):
		return
	_launch_button.text = "PREPARING PREVIEW…"
	_launch_button.disabled = true
	var preview: Dictionary = await _app.call("prepare_circuit_preview", _identity)
	if generation != _generation or _mode != "confirmation" or not is_instance_valid(_preview_control):
		return
	if preview.is_empty() or String(preview.get("identity_fingerprint", "")) != String(_identity.get("fingerprint", "")):
		_launch_button.text = "PREVIEW FAILED"
		_launch_button.disabled = true
		return
	_preview = preview.duplicate(true)
	_preview_control.set_preview(preview)
	_launch_button.text = "RACE THIS CIRCUIT"
	_launch_button.disabled = false
	if not _launch_button.pressed.is_connected(_launch):
		_launch_button.pressed.connect(_launch)
	_wire_vertical([_size_selector, _share_line, _favorite_button, _launch_button, _back_button])


func _on_size_selected(index: int) -> void:
	if index < 0 or index >= GENERATED_RULES.LENGTH_TIERS.size():
		return
	var tier := String(GENERATED_RULES.LENGTH_TIERS[index])
	if tier == String(_identity.get("length_tier", GENERATED_RULES.DEFAULT_LENGTH_TIER)):
		return
	var regenerated: Dictionary = _app.call("retier_circuit_identity", _identity, tier)
	if regenerated.is_empty():
		var current_index := GENERATED_RULES.LENGTH_TIERS.find(String(_identity.get("length_tier", GENERATED_RULES.DEFAULT_LENGTH_TIER)))
		if current_index >= 0 and is_instance_valid(_size_selector):
			_size_selector.select(current_index)
		return
	_identity = regenerated.duplicate(true)
	if _app.has_method("prewarm_generated_circuit"):
		_app.call("prewarm_generated_circuit", GENERATED_CIRCUITS.apply_to_event(_identity))
	_preview.clear()
	_generation += 1
	var generation := _generation
	if is_instance_valid(_share_line):
		var encoded: Dictionary = _app.call("circuit_share_code", _identity)
		_share_line.text = String(encoded.get("code", ""))
	_refresh_favorite_state()
	await _refresh_preview(generation)


func _refresh_favorite_state() -> void:
	var library: Dictionary = _app.call("get_circuit_library")
	_is_favorite = false
	for entry: Dictionary in library.get("favorites", []):
		if String(entry.get("fingerprint", "")) == String(_identity.get("fingerprint", "")):
			_is_favorite = true
			break
	if is_instance_valid(_favorite_button):
		_favorite_button.text = "REMOVE FAVORITE" if _is_favorite else "ADD FAVORITE"
	if is_instance_valid(_favorite_status):
		_favorite_status.text = ""


func go_back() -> bool:
	if _mode in ["confirmation", "library"]:
		show_browser()
		return true
	return false


func _request_back() -> void:
	back_requested.emit()


func _import_code(code_edit: LineEdit) -> void:
	var result: Dictionary = _app.call("decode_circuit_share_code", code_edit.text)
	if not bool(result.get("ok", false)):
		_status.text = String(result.get("error", "This share code could not be read."))
		_status.add_theme_color_override("font_color", SKIN.ORANGE)
		code_edit.grab_focus()
		return
	show_confirmation(result["identity"])


func _add_library_section(title: String, entries_value: Variant, count: int) -> void:
	var entries: Array = entries_value if entries_value is Array else []
	_add_label(title, 14, SKIN.YELLOW, true)
	if entries.is_empty():
		_add_label("NONE YET", 13, SKIN.CREAM_DIM)
		return
	for index in mini(count, entries.size()):
		var identity: Dictionary = entries[index]
		_button(
			"%s · %s · %s" % [String(identity.get("display_name", "CIRCUIT")).to_upper(), _profile_label(identity), String(identity.get("fingerprint", "")).substr(0, 6).to_upper()],
			show_confirmation.bind(identity),
			false,
			"Discovery%s%d" % [title.capitalize(), index]
		)
	if entries.size() > count:
		_button("VIEW ALL %s · %d" % [title, entries.size()], _show_library.bind(title, entries, 0), false, "DiscoveryAll%s" % title.capitalize())


func _show_library(title: String, entries: Array, page: int) -> void:
	_mode = "library"
	_generation += 1
	var generation := _generation
	_clear()
	var page_size := 6
	var page_count := maxi(1, ceili(float(entries.size()) / float(page_size)))
	var current_page := clampi(page, 0, page_count - 1)
	_add_kicker("CIRCUIT DISCOVERY · %s" % title)
	_add_label("Saved circuits", 34, SKIN.CREAM, true)
	_add_label("PAGE %d OF %d" % [current_page + 1, page_count], 14, SKIN.CREAM_DIM, true)
	var focusables: Array[Control] = []
	var start := current_page * page_size
	for index in range(start, mini(entries.size(), start + page_size)):
		var identity: Dictionary = entries[index]
		var entry_button := _button(
			"%s\n%s · %s · %s · %s" % [
				String(identity.get("display_name", "CIRCUIT")).to_upper(),
				_profile_label(identity),
				String(identity.get("theme", "")).to_upper(),
				String(identity.get("room", "")).to_upper(),
				String(identity.get("fingerprint", "")).substr(0, 8).to_upper(),
			],
			show_confirmation.bind(identity),
			false,
			"DiscoveryLibrary%d" % index
		)
		entry_button.custom_minimum_size.y = 52.0
		focusables.append(entry_button)
	if current_page > 0:
		focusables.append(_button("← PREVIOUS PAGE", _show_library.bind(title, entries, current_page - 1), false, "DiscoveryPreviousPage"))
	if current_page + 1 < page_count:
		focusables.append(_button("NEXT PAGE →", _show_library.bind(title, entries, current_page + 1), false, "DiscoveryNextPage"))
	var back := _button("BACK TO DISCOVERY", show_browser, false, "DiscoveryLibraryBack")
	focusables.append(back)
	_wire_vertical(focusables)
	call_deferred("_focus_control", focusables[0], generation)


func _toggle_favorite() -> void:
	var adding := not _is_favorite
	if bool(_app.call("set_circuit_favorite", _identity, adding)):
		_is_favorite = adding
		_favorite_button.text = "REMOVE FAVORITE" if adding else "ADD FAVORITE"
		_favorite_status.text = ""
	else:
		var detail := String(_app.call("get_last_save_error")) if _app.has_method("get_last_save_error") else ""
		_set_favorite_error("Favorite was not saved. %s" % (detail if not detail.is_empty() else "Check save access and try again."))


func _set_favorite_error(message: String) -> void:
	_favorite_status.text = message
	_favorite_status.add_theme_color_override("font_color", SKIN.ORANGE)


func _launch() -> void:
	if _preview.is_empty():
		return
	var progress: Dictionary = _app.call("get_save_data")
	var vehicle_id := String(progress.get("selected_vehicle", "rustbug"))
	_app.call("start_discovery_race", _identity, vehicle_id, String(_preview["loaded_fingerprint"]))


func _profile_label(identity: Dictionary) -> String:
	var profile: Dictionary = GENERATED_RULES.length_profile(String(identity.get("length_tier", GENERATED_RULES.DEFAULT_LENGTH_TIER)))
	return String(profile.get("label", "Standard")).to_upper()


func _button(text: String, callback: Callable, primary: bool, node_name: String) -> Button:
	var button := BUTTON_SCRIPT.new() as Button
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 42.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	SKIN.apply_button(button, primary)
	if callback.is_valid():
		button.pressed.connect(callback)
	add_child(button)
	return button


func _add_label(text: String, font_size: int, color: Color, display: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	SKIN.style_label(label, font_size, color, display)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
	return label


func _add_kicker(text: String) -> void:
	var label := Label.new()
	label.text = text
	add_child(SKIN.style_tape(label, SKIN.YELLOW, 15))


func _wire_vertical(controls: Array[Control]) -> void:
	for index in controls.size():
		var control := controls[index]
		if index > 0:
			control.focus_neighbor_top = control.get_path_to(controls[index - 1])
		if index < controls.size() - 1:
			control.focus_neighbor_bottom = control.get_path_to(controls[index + 1])


func _focus_control(control: Control, generation: int) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	if generation == _generation and is_instance_valid(control) and control.visible:
		control.grab_focus()


func _clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()