extends Control

signal action_requested(action: StringName)
signal vehicle_selected(vehicle_id: String)
signal focus_moved
signal presentation_ready

const CATALOG := preload("res://data/championship/catalog.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const TITLE_ART := preload("res://assets/ui/imagine/motorsport_title.jpg")
const GARAGE_ART := preload("res://assets/ui/imagine/motorsport_garage.jpg")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const BUTTON_SCRIPT := preload("res://scripts/ui/motorsport_button.gd")
const INK := Color("101b21")
const CREAM := Color("fff2ce")
const AMBER := Color("f4bf52")
const TEAL := Color("71c9bc")
const DESIGN_SIZE := Vector2(1280, 720)

var reduced_motion := false
var selected_vehicle_id := "rustbug"
var _canvas: Control
var _hero: TextureRect
var _vehicle_name: Label
var _archetype: Label
var _ratings: Dictionary = {}
var _vehicle_buttons: Dictionary = {}
var _unlocked: Array = []
var _generation := 0
var _entrance: Tween
var _garage_primary: Button
var _garage_back: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), INK)


func clear() -> void:
	_generation += 1
	if _entrance and _entrance.is_valid():
		_entrance.kill()
	if is_instance_valid(_canvas):
		remove_child(_canvas)
		_canvas.queue_free()
	_canvas = null
	_hero = null
	_garage_primary = null
	_garage_back = null
	_vehicle_buttons.clear()
	_ratings.clear()
	visible = false


func show_title(has_progress: bool, read_only: bool) -> void:
	_begin(TITLE_ART)
	_label("POCKET", Rect2(74, 66, 535, 100), 86, CREAM)
	_label("CIRCUIT", Rect2(74, 154, 550, 110), 94, AMBER)
	_label("GRAND HOUSEHOLD CIRCUIT", Rect2(80, 275, 520, 36), 23, TEAL)
	var status := "CONTINUE YOUR CHAMPIONSHIP" if has_progress else "TINY RACING. BIG STAKES."
	if read_only:
		status = "SAVE READ-ONLY · QUICK RACE AVAILABLE"
	_label(status, Rect2(80, 326, 530, 30), 17, CREAM)
	var play := _button("PLAY", Rect2(72, 386, 510, 80), &"championship", true)
	play.disabled = read_only and not has_progress
	var second_row: Array[Button] = []
	if has_progress:
		var new_run := _button("NEW RUN", Rect2(80, 484, 232, 52), &"new_run")
		new_run.disabled = read_only
		second_row.append(new_run)
		second_row.append(_button("QUICK RACE", Rect2(324, 484, 252, 52), &"quick_race"))
	else:
		second_row.append(_button("QUICK RACE", Rect2(80, 484, 496, 52), &"quick_race"))
	var last_row: Array[Button] = []
	for index in 3:
		var actions := [&"options", &"credits", &"quit"]
		last_row.append(_button(String(actions[index]).to_upper(), Rect2(80 + index * 168, 550, 158, 48), actions[index]))
	_wire_rows([[play], second_row, last_row])
	_label("ARROWS / STICK  MOVE   ·   ENTER / A  SELECT", Rect2(80, 654, 730, 30), 16, CREAM)
	_focus_later(play if not play.disabled else second_row.back(), _generation)


func show_garage(selected: String, unlocked: Array, context: String, next_text: String) -> void:
	_begin(GARAGE_ART)
	_unlocked = unlocked
	_label("SELECT YOUR CAR", Rect2(86, 65, 720, 58), 40, CREAM)
	_label(context, Rect2(88, 121, 1040, 30), 17, TEAL)
	_vehicle_name = _label("", Rect2(88, 195, 266, 50), 32, AMBER)
	_archetype = _label("", Rect2(88, 251, 250, 42), 18, CREAM)
	_hero = _texture(IDENTITIES.car_texture("rustbug"), Rect2(493, 169, 286, 307))
	_hero.name = "SelectedCarArtwork"
	_hero.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for index in 3:
		var key: String = ["speed", "grip", "drift"][index]
		_label(key.to_upper(), Rect2(88, 310 + index * 57, 200, 25), 16, CREAM)
		var bar := ProgressBar.new()
		bar.position = Vector2(88, 338 + index * 57)
		bar.size = Vector2(238, 12)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fill := StyleBoxFlat.new()
		fill.bg_color = TEAL if index == 1 else AMBER
		fill.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("fill", fill)
		var background := StyleBoxFlat.new()
		background.bg_color = Color("17262d")
		background.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("background", background)
		_canvas.add_child(bar)
		_ratings[key] = bar
	var car_row: Array[Button] = []
	for index in CATALOG.VEHICLES.size():
		var vehicle: Dictionary = CATALOG.VEHICLES[index]
		var id := String(vehicle["id"])
		var available := id in unlocked
		var button := _button(String(vehicle["name"]).to_upper(), Rect2(408 + index * 180, 484, 166, 90), &"")
		button.name = "Vehicle_" + id
		button.text = String(vehicle["name"]).to_upper() + ("" if available else "\nLOCKED")
		button.add_theme_font_size_override("font_size", 15)
		button.icon = IDENTITIES.car_texture(id)
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 42)
		button.disabled = not available
		if available:
			button.focus_entered.connect(_choose_vehicle.bind(id))
			button.pressed.connect(_choose_vehicle.bind(id))
		_vehicle_buttons[id] = button
		car_row.append(button)
	var back := _button("BACK", Rect2(88, 618, 242, 64), &"back")
	var next := _button(next_text, Rect2(828, 618, 364, 64), &"play_vehicle", true)
	_garage_primary = next
	_garage_back = back
	next.name = "GaragePrimaryAction"
	_wire_rows([car_row, [back, next]])
	for button: Button in car_row:
		button.focus_neighbor_bottom = button.get_path_to(next)
	_label("SELECTED CAR RACES · ENTER / A CONFIRM", Rect2(358, 638, 450, 24), 14, CREAM)
	var initial := selected if selected in unlocked else "rustbug"
	_choose_vehicle(initial)
	_focus_later(_vehicle_buttons.get(initial, next), _generation)


func _choose_vehicle(id: String) -> void:
	if not id in _unlocked:
		return
	selected_vehicle_id = id
	var vehicle := CATALOG.get_vehicle(id)
	_hero.texture = IDENTITIES.car_texture(id)
	_vehicle_name.text = String(vehicle["name"]).to_upper()
	_archetype.text = String(vehicle["archetype"]).to_upper() + "\nSELECTED"
	for key: String in _ratings:
		_ratings[key].value = float(vehicle["ratings"][key]) * 100.0
	for candidate: String in _vehicle_buttons:
		var button: Button = _vehicle_buttons[candidate]
		button.set("selected", candidate == id)
		button.add_theme_color_override("font_color", AMBER if candidate == id else CREAM)
	if is_instance_valid(_garage_primary):
		_garage_primary.focus_neighbor_top = _garage_primary.get_path_to(_vehicle_buttons[id])
		_garage_back.focus_neighbor_top = _garage_back.get_path_to(_vehicle_buttons[id])
	vehicle_selected.emit(id)


func _begin(art: Texture2D) -> void:
	clear()
	visible = true
	_canvas = Control.new()
	_canvas.name = "Composition"
	_canvas.size = DESIGN_SIZE
	add_child(_canvas)
	_texture(art, Rect2(Vector2.ZERO, DESIGN_SIZE)).stretch_mode = TextureRect.STRETCH_SCALE
	_layout()
	if not reduced_motion:
		_canvas.modulate.a = 0.0
		_entrance = create_tween()
		_entrance.tween_property(_canvas, "modulate:a", 1.0, 0.16)


func _layout() -> void:
	queue_redraw()
	if not is_instance_valid(_canvas):
		return
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	_canvas.scale = Vector2.ONE * factor
	_canvas.position = (size - DESIGN_SIZE * factor) * 0.5


func _texture(texture: Texture2D, rect: Rect2) -> TextureRect:
	var view := TextureRect.new()
	view.texture = texture
	view.position = rect.position
	view.size = rect.size
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(view)
	return view


func _label(text: String, rect: Rect2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 5 if font_size >= 40 else 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(label)
	return label


func _button(text: String, rect: Rect2, action: StringName, primary: bool = false) -> Button:
	var button := BUTTON_SCRIPT.new() as Button
	button.set("reduced_motion", reduced_motion)
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 30 if primary else 20)
	apply_button_art(button, primary)
	button.focus_entered.connect(func(): focus_moved.emit())
	if not action.is_empty():
		button.pressed.connect(func(): action_requested.emit(action))
	_canvas.add_child(button)
	return button


static func apply_button_art(button: Button, primary: bool) -> void:
	SKIN.apply_button(button, primary)


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
