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
const RUN_UI := preload("res://scripts/ui/run_ui.gd")
const DESIGN_SIZE := Vector2(1280, 720)
const COLUMN_X := 72.0
const COLUMN_WIDTH := 510.0
const ROW_GAP := 12
const TITLE_STAGE := Rect2(640, 28, 600, 640)
const GARAGE_STAGE := Rect2(48, 254, 438, 244)
const COLLECTION := Rect2(514, 112, 704, 466)
const GRID_COLUMNS := 5
const GRID_VISIBLE_ROWS := 3
const GRID_GAP := 12.0
const GRID_CARD := Vector2(124, 100)
const GRID_HEADER_HEIGHT := 30.0
const GRID_BLEED := 8.0
const GRID_FADE_HEIGHT := 32.0
const CAR_ICON_WIDTH := 34
const SHAPE_MORPH_SECONDS := 0.18
const PROFILE_TOP := 520.0
const ORIGIN_DROP := 36.0
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
var _garage_actions: Array[Button] = []
var _origin: Label
var _holding_id := ""
var _shapes: Dictionary = {}
var _morph: Tween
var _grid_rows: Array = []
var _grid_scroll_queued := false
var _grid_focus_reveal := ""
var _grid_last_scroll := 0
var _grid_sections: Array[Label] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)


func clear() -> void:
	_generation += 1
	if _entrance and _entrance.is_valid():
		_entrance.kill()
	if _morph and _morph.is_valid():
		_morph.kill()
	if is_instance_valid(_canvas):
		remove_child(_canvas)
		_canvas.queue_free()
	_canvas = null
	_stage = null
	_garage_actions.clear()
	_vehicle_buttons.clear()
	_grid_rows.clear()
	_grid_scroll_queued = false
	_grid_focus_reveal = ""
	_grid_last_scroll = 0
	_grid_sections.clear()
	visible = false


func show_title(has_progress: bool, read_only: bool, vehicle_id: String = "rustbug", unlocked: Array = ["rustbug"], recovery_message: String = "", has_run: bool = false) -> void:
	_begin()
	_add_stage(TITLE_STAGE).configure(&"title", vehicle_id, "rae", "kitchen", TITLE_RIVAL, unlocked)
	_label("POCKET", Rect2(COLUMN_X - 4, 40, 560, 104), 88, SKIN.CREAM)
	_label("CIRCUIT", Rect2(COLUMN_X - 4, 124, 580, 116), 100, SKIN.YELLOW)
	_tape("GRAND HOUSEHOLD CIRCUIT", Vector2(COLUMN_X + 6, 246), SKIN.ORANGE, 17)
	var status := "CONTINUE YOUR RUN" if has_run else "TINY RACING. BIG STAKES."
	if has_progress and not has_run:
		status = "CONTINUE YOUR CHAMPIONSHIP"
	if not recovery_message.is_empty():
		status = recovery_message
	elif read_only:
		status = "SAVE READ-ONLY · QUICK RACE AVAILABLE"
	_label(status, Rect2(COLUMN_X + 4, 290, COLUMN_WIDTH, 30), 18, SKIN.CREAM_DIM)
	var play := _button("PLAY", Rect2(COLUMN_X, 336, COLUMN_WIDTH, 82), &"your_run" if has_run else &"new_run", true)
	var second_actions := [&"championship", &"quick_race", &"quick_strip"]
	var second_row := _button_row(second_actions, Rect2(COLUMN_X, 436, COLUMN_WIDTH, 54), 16)
	second_row[0].disabled = read_only and not has_progress
	var last_row := _button_row([&"options", &"discovery", &"credits", &"quit"], Rect2(COLUMN_X, 504, COLUMN_WIDTH, 48), 16)
	_wire_rows([[play], second_row, last_row])
	_label("ARROWS / STICK  MOVE   ·   ENTER / A  SELECT", Rect2(COLUMN_X + 4, 646, 640, 26), 14, SKIN.CREAM_DIM)
	_focus_later(play, _generation)


func show_garage(selected: String, unlocked: Array, context: String, next_text: String, roster: Array = [], title: String = "SELECT YOUR CAR") -> void:
	_begin()
	_unlocked = unlocked
	_shapes.clear()
	_stage = _add_stage(GARAGE_STAGE)
	_label(title, Rect2(COLUMN_X, 40, 700, 58), 40, SKIN.CREAM)
	_tape(context, Vector2(COLUMN_X + 6, 104), SKIN.YELLOW, 15)
	_vehicle_name = _label("", Rect2(56, 156, 430, 60), 38, SKIN.YELLOW)
	_vehicle_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_archetype = _label("", Rect2(60, 222, 430, 30), 18, SKIN.ORANGE)
	_origin = _tape("", Vector2(COLUMN_X + 6, PROFILE_TOP), SKIN.CREAM, 13)
	_origin.name = "GarageOrigin"
	_profile = _label("", Rect2(60, PROFILE_TOP, 430, 76), 15, SKIN.CREAM_DIM, false)
	_profile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var display_ids: Array[String] = []
	if roster.is_empty():
		display_ids.assign(CATALOG.vehicle_ids())
	else:
		for item in roster:
			display_ids.append(String(item))
	var counter := _tape("%d CARS" % display_ids.size(), Vector2(1040, 64), SKIN.CREAM, 18)
	counter.name = "GarageCarCounter"
	_shelf(COLLECTION.grow(12))
	_grid_cards(display_ids, unlocked)
	var back := _button("BACK", Rect2(COLUMN_X, 612, 240, 64), &"back")
	var driver := _button("DRIVER LOOK", Rect2(COLUMN_X + 258, 612, 300, 64), &"driver")
	var next := _button(next_text, Rect2(868, 612, 340, 64), &"play_vehicle", true)
	_garage_actions = [back, driver, next]
	next.name = "GaragePrimaryAction"
	var rows := _grid_rows.duplicate()
	rows.append([back, driver, next])
	_wire_rows(rows)
	# Leaving the collection goes straight to its primary action.
	for row_index in range(_grid_rows.size() - 1, -1, -1):
		var has_available := false
		for button: Button in _grid_rows[row_index]:
			if not button.disabled:
				button.focus_neighbor_bottom = button.get_path_to(next)
				has_available = true
		if has_available:
			break
	_label("LB / RB · PGUP / PGDN  PAGE", Rect2(524, 582, 680, 24), 13, SKIN.CREAM_DIM).name = "GaragePagingHint"
	_label("ENTER / A  CONFIRM", Rect2(630, 632, 238, 26), 14, SKIN.CREAM_DIM).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var initial := selected if selected in unlocked and _vehicle_buttons.has(selected) else "rustbug"
	_holding_id = initial
	_choose_vehicle(initial)
	_focus_later(_vehicle_buttons.get(initial, next), _generation)


## Type sections share a five-column focus lattice, including partial rows.
func _grid_cards(display_ids: Array[String], unlocked: Array) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "GridScroll"
	scroll.position = COLLECTION.position
	scroll.size = COLLECTION.size
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.focus_mode = Control.FOCUS_NONE
	_canvas.add_child(scroll)
	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(content)
	var row: Array[Button] = []
	var y := GRID_BLEED
	var section_y := y
	var group := ""
	var single_row := display_ids.size() <= GRID_COLUMNS
	for id in display_ids:
		var vehicle: Dictionary = CATALOG.get_vehicle(id)
		var car_type := String((vehicle.get("car_art", {}) as Dictionary).get("type", ""))
		if car_type != group:
			if not row.is_empty() and not single_row:
				_grid_rows.append(row)
				row = []
				y += GRID_CARD.y + GRID_GAP
			group = car_type
			section_y = GRID_BLEED if single_row else y
			var tape := Label.new()
			tape.text = car_type.to_upper()
			tape.position = Vector2(GRID_BLEED + 4.0 + (row.size() * (GRID_CARD.x + GRID_GAP) if single_row else 0.0), section_y)
			tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
			SKIN.style_tape(tape, SKIN.YELLOW, 12)
			content.add_child(tape)
			_grid_sections.append(tape)
			y = section_y + GRID_HEADER_HEIGHT
		var available := id in unlocked
		var button := _make_button("", &"")
		button.name = "Vehicle_" + id
		button.position = Vector2(GRID_BLEED + row.size() * (GRID_CARD.x + GRID_GAP), y)
		button.size = GRID_CARD
		if y == section_y + GRID_HEADER_HEIGHT:
			button.set_meta("section_header_y", section_y)
		button.text = String(vehicle.get("name", id)).to_upper() + ("" if available else "\n" + String(vehicle.get("unlock", "")).to_upper())
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 13)
		button.icon = IDENTITIES.car_icon_placeholder()
		button.set_meta("pending_icon", id)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.add_theme_constant_override("icon_max_width", CAR_ICON_WIDTH)
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		button.disabled = not available
		if available:
			button.focus_entered.connect(_focus_vehicle.bind(id))
			button.pressed.connect(_choose_vehicle.bind(id))
		content.add_child(button)
		if vehicle.has("won_from"):
			var mark := Label.new()
			mark.text = String(RUN_UI.SHELF_MARKS.get(String(vehicle["won_from"]), ""))
			mark.position = Vector2(-4.0, -10.0)
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			SKIN.style_tape(mark, SKIN.ORANGE, 11)
			button.add_child(mark)
		_vehicle_buttons[id] = button
		row.append(button)
		if row.size() == GRID_COLUMNS:
			_grid_rows.append(row)
			row = []
			y += GRID_CARD.y + GRID_GAP
	if not row.is_empty():
		_grid_rows.append(row)
		y += GRID_CARD.y + GRID_GAP
	content.custom_minimum_size = Vector2(GRID_COLUMNS * (GRID_CARD.x + GRID_GAP) - GRID_GAP + GRID_BLEED * 2, y + GRID_FADE_HEIGHT)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color(SKIN.CREAM, 0.0), Color(SKIN.CREAM, 0.3), Color(SKIN.CREAM, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.5, 0.0)
	texture.fill_to = Vector2(0.5, 1.0)
	var fade := TextureRect.new()
	fade.name = "GridContinuation"
	fade.texture = texture
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.size = Vector2(COLLECTION.size.x - GRID_BLEED * 2, GRID_FADE_HEIGHT)
	_canvas.add_child(fade)
	var cue := Label.new()
	cue.text = "MORE ↓"
	cue.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cue.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	SKIN.style_label(cue, 12, SKIN.CREAM)
	fade.add_child(cue)
	scroll.get_v_scroll_bar().value_changed.connect(func(_value: float): _queue_grid_scroll())
	_refresh_grid_visibility(scroll)
	_queue_grid_scroll()


func _focus_vehicle(id: String) -> void:
	_choose_vehicle(id)
	_grid_focus_reveal = id
	_queue_grid_scroll()


func _queue_grid_scroll() -> void:
	if _grid_scroll_queued:
		return
	_grid_scroll_queued = true
	_settle_grid_scroll.call_deferred(_generation)


func _settle_grid_scroll(generation: int) -> void:
	if generation != _generation:
		return
	var scroll := _canvas.get_node("GridScroll") as ScrollContainer
	var bar := scroll.get_v_scroll_bar()
	var maximum := maxi(0, roundi(bar.max_value - bar.page))
	var anchors: Array[int] = [0, maximum]
	for row: Array in _grid_rows:
		var first := row[0] as Button
		anchors.append(clampi(roundi(float(first.get_meta("section_header_y", first.position.y)) - GRID_BLEED), 0, maximum))
	anchors.sort()
	var raw := scroll.scroll_vertical
	var target := raw
	var usable_height := scroll.size.y - GRID_FADE_HEIGHT
	var focused := _vehicle_buttons.get(_grid_focus_reveal) as Button
	if is_instance_valid(focused) and focused.has_focus():
		var best_distance := INF
		for anchor in anchors:
			if anchor > focused.position.y - GRID_BLEED or anchor + usable_height < focused.position.y + GRID_CARD.y + GRID_BLEED:
				continue
			var distance := absf(float(anchor - raw))
			if distance < best_distance:
				best_distance = distance
				target = anchor
	else:
		# Wheel and scrollbar movement settle in their direction, even for a small wheel tick.
		for anchor in anchors:
			if raw > _grid_last_scroll and anchor >= raw:
				target = anchor
				break
			if raw < _grid_last_scroll and anchor <= raw:
				target = anchor
	scroll.scroll_vertical = target
	_grid_last_scroll = scroll.scroll_vertical
	_grid_focus_reveal = ""
	_refresh_grid_visibility(scroll)
	_grid_scroll_queued = false


func _resolve_grid_icon(button: Button) -> void:
	if button.has_meta("pending_icon"):
		button.icon = IDENTITIES.car_texture(String(button.get_meta("pending_icon")))
		button.remove_meta("pending_icon")


func _refresh_grid_visibility(scroll: ScrollContainer) -> void:
	var usable_height := scroll.size.y - GRID_FADE_HEIGHT
	var has_after := false
	for row: Array in _grid_rows:
		var first := row[0] as Button
		var top := first.position.y - GRID_BLEED - scroll.scroll_vertical
		var bottom := first.position.y + GRID_CARD.y + GRID_BLEED - scroll.scroll_vertical
		var complete := top >= 0.0 and bottom <= usable_height
		for button: Button in row:
			if complete:
				_resolve_grid_icon(button)
			button.modulate.a = 1.0 if complete else 0.0
			button.mouse_filter = Control.MOUSE_FILTER_STOP if complete else Control.MOUSE_FILTER_IGNORE
		has_after = has_after or bottom > usable_height
	for section: Label in _grid_sections:
		var card_top := section.position.y + GRID_HEADER_HEIGHT - scroll.scroll_vertical
		section.visible = card_top - GRID_BLEED >= 0.0 and card_top + GRID_CARD.y + GRID_BLEED <= usable_height
	var fade := _canvas.get_node("GridContinuation") as TextureRect
	fade.visible = has_after
	fade.position = COLLECTION.position + Vector2(GRID_BLEED, usable_height)


func _input(event: InputEvent) -> void:
	if not visible or _grid_rows.is_empty():
		return
	var direction := 0
	if event.is_action_pressed(&"ui_page_down"):
		direction = 1
	elif event.is_action_pressed(&"ui_page_up"):
		direction = -1
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			direction = 1
		elif event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			direction = -1
	if direction != 0 and page_collection(direction):
		get_viewport().set_input_as_handled()


func page_collection(direction: int) -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	for row_index in _grid_rows.size():
		var column := (_grid_rows[row_index] as Array).find(focused)
		if column < 0:
			continue
		var target_row := clampi(row_index + direction * GRID_VISIBLE_ROWS, 0, _grid_rows.size() - 1)
		while target_row >= 0 and target_row < _grid_rows.size():
			var row: Array = _grid_rows[target_row]
			for offset in row.size():
				var candidate := row[(mini(column, row.size() - 1) + offset) % row.size()] as Button
				if not candidate.disabled:
					candidate.grab_focus()
					return true
			target_row += direction
		return true
	return false


func _choose_vehicle(id: String) -> void:
	if not id in _unlocked:
		return
	_resolve_grid_icon(_vehicle_buttons[id] as Button)
	if _vehicle_buttons.has(selected_vehicle_id):
		(_vehicle_buttons[selected_vehicle_id] as Button).set("selected", false)
	selected_vehicle_id = id
	var vehicle := CATALOG.get_vehicle(id)
	_stage.configure(&"vehicle", id, "rae", "kitchen", "", _unlocked)
	_vehicle_name.text = String(vehicle["name"]).to_upper()
	var name_width := SKIN.display_font().get_string_size(_vehicle_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 38).x
	_vehicle_name.add_theme_font_size_override("font_size", clampi(floori(38.0 * _vehicle_name.size.x / maxf(name_width, 1.0)), 24, 38))
	_archetype.text = String(vehicle["archetype"]).to_upper()
	var collected := VehicleDirectory.get_vehicle(id)
	var origin := String(collected.get("won_from", vehicle.get("won_from", "")))
	_origin.visible = id != _holding_id and RUN_UI.ORIGIN_COPY.has(origin)
	if _origin.visible:
		_origin.text = RUN_UI.origin_line(collected if not collected.is_empty() else vehicle)
		_origin.reset_size()
	_profile.position.y = PROFILE_TOP + (ORIGIN_DROP if _origin.visible else 0.0)
	var tradeoff := String(vehicle.get("tradeoff", ""))
	_profile.text = "+ %s" % String(vehicle.get("strength", "")) + ("" if tradeoff.is_empty() else "\n– %s" % tradeoff)
	_show_shape(id)
	(_vehicle_buttons[id] as Button).set("selected", true)
	# Up from any action returns to the chosen car, wherever the grid is scrolled.
	for action: Button in _garage_actions:
		action.focus_neighbor_top = action.get_path_to(_vehicle_buttons[id])
	vehicle_selected.emit(id)


## Draws the car's six-axis shape against the car the player came in with.
func _show_shape(id: String) -> void:
	var compare := {} if id == _holding_id else _shape_of(_holding_id)
	var label := "YOUR CAR" if id == _holding_id else "VS " + String(CATALOG.get_vehicle(_holding_id).get("name", _holding_id)).to_upper()
	_stage.show_shape(_shape_of(id), compare, label)
	if _morph and _morph.is_valid():
		_morph.kill()
	if reduced_motion:
		_stage.shape_blend = 1.0
		return
	_morph = create_tween()
	_morph.tween_property(_stage, "shape_blend", 1.0, SHAPE_MORPH_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _shape_of(id: String) -> Dictionary:
	if not _shapes.has(id):
		_shapes[id] = CarProfile.shape(CATALOG.create_vehicle_stats(id))
	return _shapes[id]


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
	label.reset_size()
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
