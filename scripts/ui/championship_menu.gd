extends Control

signal action_requested(action: StringName)
signal vehicle_selected(vehicle_id: String)
signal focus_moved
signal presentation_ready

const CATALOG := preload("res://data/championship/catalog.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const BUTTON_SCRIPT := preload("res://scripts/ui/motorsport_button.gd")
const STAGE_SCRIPT := preload("res://scripts/ui/app_shell_stage.gd")
const DESIGN_SIZE := Vector2(1280, 720)
const COLUMN_X := 72.0
const COLUMN_WIDTH := 510.0
const ROW_GAP := 12
const TITLE_STAGE := Rect2(640, 28, 600, 640)
const GARAGE_STAGE := Rect2(590, 30, 650, 420)
const SHELF := Rect2(72, 460, 1136, 106)
const SHELF_GAP := 14.0
const CAR_ICON_WIDTH := 34
const TITLE_RIVAL := "cass"

var reduced_motion := false
var selected_vehicle_id := "rustbug"
var _canvas: Control
var _stage: AppShellStage
var _vehicle_name: Label
var _archetype: Label
var _profile: Label
var _vehicle_buttons: Dictionary = {}
var _unlocked: Array = []
var _generation := 0
var _entrance: Tween
var _garage_primary: Button
var _garage_back: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)


func clear() -> void:
	_generation += 1
	if _entrance and _entrance.is_valid():
		_entrance.kill()
	if is_instance_valid(_canvas):
		remove_child(_canvas)
		_canvas.queue_free()
	_canvas = null
	_stage = null
	_garage_primary = null
	_garage_back = null
	_vehicle_buttons.clear()
	visible = false


func show_title(has_progress: bool, read_only: bool, vehicle_id: String = "rustbug", unlocked: Array = ["rustbug"]) -> void:
	_begin()
	_add_stage(TITLE_STAGE).configure(&"title", vehicle_id, "rae", "kitchen", TITLE_RIVAL, unlocked)
	_label("POCKET", Rect2(COLUMN_X - 4, 40, 560, 104), 88, SKIN.CREAM)
	_label("CIRCUIT", Rect2(COLUMN_X - 4, 124, 580, 116), 100, SKIN.YELLOW)
	_tape("GRAND HOUSEHOLD CIRCUIT", Vector2(COLUMN_X + 6, 246), SKIN.ORANGE, 17)
	var status := "CONTINUE YOUR CHAMPIONSHIP" if has_progress else "TINY RACING. BIG STAKES."
	if read_only:
		status = "SAVE READ-ONLY · QUICK RACE AVAILABLE"
	_label(status, Rect2(COLUMN_X + 4, 290, COLUMN_WIDTH, 30), 18, SKIN.CREAM_DIM)
	var play := _button("PLAY", Rect2(COLUMN_X, 336, COLUMN_WIDTH, 82), &"championship", true)
	play.disabled = read_only and not has_progress
	var second_actions := [&"new_run", &"quick_race"] if has_progress else [&"quick_race"]
	var second_row := _button_row(second_actions, Rect2(COLUMN_X, 436, COLUMN_WIDTH, 54), 20)
	if has_progress:
		second_row[0].disabled = read_only
	var last_row := _button_row([&"options", &"discovery", &"credits", &"quit"], Rect2(COLUMN_X, 504, COLUMN_WIDTH, 48), 16)
	_wire_rows([[play], second_row, last_row])
	_label("ARROWS / STICK  MOVE   ·   ENTER / A  SELECT", Rect2(COLUMN_X + 4, 646, 640, 26), 14, SKIN.CREAM_DIM)
	_focus_later(play if not play.disabled else second_row.back(), _generation)


func show_garage(selected: String, unlocked: Array, context: String, next_text: String, roster: Array = []) -> void:
	_begin()
	_unlocked = unlocked
	_stage = _add_stage(GARAGE_STAGE)
	_label("SELECT YOUR CAR", Rect2(COLUMN_X, 40, COLUMN_WIDTH, 58), 40, SKIN.CREAM)
	_tape(context, Vector2(COLUMN_X + 6, 104), SKIN.YELLOW, 15)
	_vehicle_name = _label("", Rect2(COLUMN_X, 150, COLUMN_WIDTH, 70), 54, SKIN.YELLOW)
	_archetype = _label("", Rect2(COLUMN_X + 4, 226, COLUMN_WIDTH, 30), 20, SKIN.ORANGE)
	_profile = _label("", Rect2(COLUMN_X + 4, 264, 480, 150), 16, SKIN.CREAM_DIM, false)
	_profile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var display_ids: Array[String] = []
	if roster.is_empty():
		display_ids.assign(CATALOG.vehicle_ids())
	else:
		for item in roster:
			display_ids.append(String(item))
	_shelf(Rect2(SHELF.position.x - 16, SHELF.end.y - 2, SHELF.size.x + 32, 26))
	var pitch := (SHELF.size.x + SHELF_GAP) / float(display_ids.size())
	var car_row: Array[Button] = []
	for index in display_ids.size():
		var id := display_ids[index]
		var vehicle: Dictionary = CATALOG.get_vehicle(id)
		var available := id in unlocked
		var slot := Rect2(SHELF.position.x + pitch * index, SHELF.position.y, pitch - SHELF_GAP, SHELF.size.y)
		var button := _button("", slot, &"")
		button.name = "Vehicle_" + id
		button.text = String(vehicle.get("name", id)).to_upper() + ("" if available else "\n" + String(vehicle.get("unlock", "")).to_upper())
		button.add_theme_font_size_override("font_size", 14)
		button.icon = IDENTITIES.car_texture(id)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.add_theme_constant_override("icon_max_width", CAR_ICON_WIDTH)
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		button.disabled = not available
		if available:
			button.focus_entered.connect(_choose_vehicle.bind(id))
			button.pressed.connect(_choose_vehicle.bind(id))
		_vehicle_buttons[id] = button
		car_row.append(button)
	var back := _button("BACK", Rect2(COLUMN_X, 612, 240, 64), &"back")
	var next := _button(next_text, Rect2(868, 612, 340, 64), &"play_vehicle", true)
	_garage_primary = next
	_garage_back = back
	next.name = "GaragePrimaryAction"
	_wire_rows([car_row, [back, next]])
	for button: Button in car_row:
		button.focus_neighbor_bottom = button.get_path_to(next)
	_label("ENTER / A  CONFIRM", Rect2(330, 632, 520, 26), 14, SKIN.CREAM_DIM).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var initial := selected if selected in unlocked else "rustbug"
	_choose_vehicle(initial)
	_focus_later(_vehicle_buttons.get(initial, next), _generation)


func _choose_vehicle(id: String) -> void:
	if not id in _unlocked:
		return
	selected_vehicle_id = id
	var vehicle := CATALOG.get_vehicle(id)
	_stage.configure(&"vehicle", id, "rae", "kitchen", "", _unlocked)
	_vehicle_name.text = String(vehicle["name"]).to_upper()
	_archetype.text = String(vehicle["archetype"]).to_upper()
	_profile.text = "+ %s\n– %s" % [String(vehicle.get("strength", "")), String(vehicle.get("tradeoff", ""))]
	for candidate: String in _vehicle_buttons:
		(_vehicle_buttons[candidate] as Button).set("selected", candidate == id)
	if is_instance_valid(_garage_primary):
		_garage_primary.focus_neighbor_top = _garage_primary.get_path_to(_vehicle_buttons[id])
		_garage_back.focus_neighbor_top = _garage_back.get_path_to(_vehicle_buttons[id])
	vehicle_selected.emit(id)


func _begin() -> void:
	clear()
	visible = true
	_canvas = Control.new()
	_canvas.name = "Composition"
	_canvas.size = DESIGN_SIZE
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_layout()
	if not reduced_motion:
		_canvas.modulate.a = 0.0
		_entrance = create_tween()
		_entrance.tween_property(_canvas, "modulate:a", 1.0, 0.16)


func _layout() -> void:
	if not is_instance_valid(_canvas):
		return
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (size - DESIGN_SIZE * factor) * 0.5


func _add_stage(rect: Rect2) -> AppShellStage:
	var stage := STAGE_SCRIPT.new() as AppShellStage
	stage.name = "Stage"
	stage.position = rect.position
	stage.size = rect.size
	_canvas.add_child(stage)
	return stage


func _shelf(rect: Rect2) -> void:
	var shelf := Panel.new()
	shelf.name = "Shelf"
	shelf.position = rect.position
	shelf.size = rect.size
	shelf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shelf.add_theme_stylebox_override("panel", SKIN.card_style(SKIN.WOOD_EDGE, 0.0))
	_canvas.add_child(shelf)


func _label(text: String, rect: Rect2, font_size: int, color: Color, display: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	SKIN.style_label(label, font_size, color, display)
	_canvas.add_child(label)
	return label


func _tape(text: String, origin: Vector2, fill: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.position = origin
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	SKIN.style_tape(label, fill, font_size)
	_canvas.add_child(label)
	return label


func _button(text: String, rect: Rect2, action: StringName, primary: bool = false) -> Button:
	var button := _make_button(text, action, primary)
	button.position = rect.position
	button.size = rect.size
	_canvas.add_child(button)
	return button


func _button_row(actions: Array, rect: Rect2, font_size: int) -> Array[Button]:
	var row := HBoxContainer.new()
	row.position = rect.position
	row.size = rect.size
	row.add_theme_constant_override("separation", ROW_GAP)
	_canvas.add_child(row)
	var buttons: Array[Button] = []
	for action: StringName in actions:
		var button := _make_button(String(action).replace("_", " ").to_upper(), action)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", font_size)
		row.add_child(button)
		buttons.append(button)
	return buttons


func _make_button(text: String, action: StringName, primary: bool = false) -> Button:
	var button := BUTTON_SCRIPT.new() as Button
	button.set("reduced_motion", reduced_motion)
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 32 if primary else 20)
	SKIN.apply_button(button, primary)
	button.focus_entered.connect(func(): focus_moved.emit())
	if not action.is_empty():
		button.pressed.connect(func(): action_requested.emit(action))
	return button


func _wire_rows(rows: Array) -> void:
	var active_rows: Array = []
	for row: Array in rows:
		var enabled: Array[Button] = []
		for button: Button in row:
			if not button.disabled:
				enabled.append(button)
		if not enabled.is_empty():
			active_rows.append(enabled)
	for row_index in active_rows.size():
		var row: Array = active_rows[row_index]
		for index in row.size():
			var button: Button = row[index]
			button.focus_neighbor_left = button.get_path_to(row[maxi(0, index - 1)])
			button.focus_neighbor_right = button.get_path_to(row[mini(row.size() - 1, index + 1)])
			var above: Array = active_rows[maxi(0, row_index - 1)]
			var below: Array = active_rows[mini(active_rows.size() - 1, row_index + 1)]
			button.focus_neighbor_top = button.get_path_to(above[mini(index, above.size() - 1)])
			button.focus_neighbor_bottom = button.get_path_to(below[mini(index, below.size() - 1)])


func _focus_later(button: Button, generation: int) -> void:
	await get_tree().process_frame
	if generation == _generation and is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled:
		button.grab_focus()
		presentation_ready.emit()
