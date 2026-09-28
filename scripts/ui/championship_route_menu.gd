class_name ChampionshipRouteMenu
extends Control

signal event_chosen(event_id: String)
signal return_chosen

const CATALOG := preload("res://data/championship/catalog.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const BUTTON_SCRIPT := preload("res://scripts/ui/motorsport_button.gd")
const BOARD := Rect2(28, 18, 1224, 640)
const STOP_SIZE := Vector2(250, 58)

var _stops: Array[Dictionary] = []
var _buttons: Array[Button] = []
var _focused_id := ""
var _vehicle_id := "rustbug"
var _notice := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func present(stops: Array, focus_id: String, vehicle_id: String, notice: String) -> void:
	_stops = []
	for item in stops:
		_stops.append(item)
	_vehicle_id = vehicle_id if not vehicle_id.is_empty() else "rustbug"
	_notice = notice
	_focused_id = focus_id
	var previous := get_children()
	for child in previous:
		remove_child(child)
		child.free()
	_buttons.clear()
	var centers := _centers()
	for index in _stops.size():
		var stop: Dictionary = _stops[index]
		var button := BUTTON_SCRIPT.new() as Button
		button.name = "Stop_%s" % String(stop["id"])
		button.text = "%s\n%s" % [String(stop["name"]), String(stop["status"])]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = not bool(stop["unlocked"])
		button.set("selected", String(stop["id"]) == focus_id)
		var place_left := index >= 6
		button.position = centers[index] + (Vector2(-STOP_SIZE.x - 22.0, -STOP_SIZE.y * 0.5) if place_left else Vector2(26.0, -STOP_SIZE.y * 0.5))
		button.size = STOP_SIZE
		button.focus_entered.connect(_focus_stop.bind(String(stop["id"])))
		if not button.disabled:
			button.pressed.connect(event_chosen.emit.bind(String(stop["id"])))
		add_child(button)
		_buttons.append(button)
	var back := BUTTON_SCRIPT.new() as Button
	back.name = "ReturnToTitle"
	back.text = "RETURN TO TITLE"
	back.position = Vector2(BOARD.end.x - 280, BOARD.end.y - 8)
	back.size = Vector2(250, 52)
	back.pressed.connect(return_chosen.emit)
	add_child(back)
	_wire_focus(back)
	queue_redraw()
	var initial := _button_for(focus_id)
	if initial == null and not _buttons.is_empty():
		initial = _buttons[0]
	if initial != null:
		initial.grab_focus.call_deferred()


func _focus_stop(event_id: String) -> void:
	_focused_id = event_id
	for button in _buttons:
		button.set("selected", button.name == "Stop_%s" % event_id)
	queue_redraw()


func _wire_focus(back: Button) -> void:
	for index in _buttons.size():
		var button := _buttons[index]
		if index > 0:
			button.focus_neighbor_top = button.get_path_to(_buttons[index - 1])
			_buttons[index - 1].focus_neighbor_bottom = _buttons[index - 1].get_path_to(button)
		button.focus_neighbor_left = button.get_path()
		button.focus_neighbor_right = button.get_path()
	if _buttons.is_empty():
		return
	var last := _buttons[-1]
	last.focus_neighbor_bottom = last.get_path_to(back)
	back.focus_neighbor_top = back.get_path_to(last)
	back.focus_neighbor_left = back.get_path()
	back.focus_neighbor_right = back.get_path()


func _draw() -> void:
	SKIN.draw_workbench(self, Rect2(Vector2.ZERO, size))
	SKIN.draw_plate(self, BOARD, SKIN.CREAM, 18)
	SKIN.draw_grid(self, BOARD.grow(-16), 28)
	SKIN.draw_tape(self, BOARD.position + Vector2(86, 4), Vector2(150, 24), -0.4)
	SKIN.draw_tape(self, Vector2(BOARD.end.x - 90, BOARD.position.y + 4), Vector2(130, 24), 0.35, SKIN.ORANGE)
	if not _notice.is_empty():
		SKIN.draw_tag(self, Rect2(BOARD.position.x + 36, BOARD.position.y + 18, 420, 32), _notice, SKIN.YELLOW, 14)
	var centers := _centers()
	if centers.size() >= 2:
		_draw_road(_smooth(centers))
	for index in _stops.size():
		_draw_stop(centers[index], _stops[index])
	SKIN.draw_text(self, Vector2(BOARD.position.x + 28, BOARD.end.y - 18), "ARROWS / STICK  FOLLOW THE ROAD    ENTER / A  RACE", 13, SKIN.INK_SOFT)


func _draw_road(points: PackedVector2Array) -> void:
	if points.size() < 2:
		return
	draw_polyline(points, SKIN.INK, 22.0, true)
	draw_polyline(points, SKIN.ASPHALT, 14.0, true)
	draw_polyline(points, Color(SKIN.YELLOW, 0.85), 3.0, true)


func _draw_stop(center: Vector2, stop: Dictionary) -> void:
	var theme := String(stop.get("theme", "kitchen"))
	var focused := String(stop["id"]) == _focused_id
	var fill := _room_color(theme)
	if not bool(stop["unlocked"]):
		fill = SKIN.WOOD_EDGE
	if focused:
		draw_arc(center, 30.0, 0.0, TAU, 32, SKIN.ORANGE, 5.0, true)
	SKIN.draw_disc(self, center, 18.0, fill)
	if not bool(stop["unlocked"]):
		SKIN.draw_padlock(self, center, 16.0)
	elif focused:
		var texture := IDENTITIES.car_texture(_vehicle_id)
		if texture != null:
			var car_size := Vector2(42, 56)
			draw_texture_rect(texture, Rect2(center + Vector2(-78, -28) - car_size * 0.5, car_size), false)
	if int(stop.get("act", 0)) > 0 and bool(stop.get("act_start", false)):
		SKIN.draw_tag(self, Rect2(center + Vector2(-118, -46), Vector2(150, 26)), String(stop.get("act_name", "")).to_upper(), SKIN.YELLOW, 12)


func _centers() -> Array[Vector2]:
	var centers: Array[Vector2] = []
	var count := _stops.size()
	if count == 0:
		return centers
	var columns := 3
	var rows := ceili(float(count) / float(columns))
	for index in count:
		var column := index / rows
		var row := index % rows
		var x := BOARD.position.x + BOARD.size.x * (0.18 + 0.30 * column)
		var y := BOARD.position.y + BOARD.size.y * (0.2 + 0.28 * row)
		centers.append(Vector2(x, y))
	return centers


func _smooth(points: Array[Vector2]) -> PackedVector2Array:
	var path := PackedVector2Array()
	if points.size() < 2:
		return path
	var samples := 8
	for index in points.size() - 1:
		var start: Vector2 = points[index]
		var end: Vector2 = points[index + 1]
		var before: Vector2 = points[maxi(0, index - 1)]
		var after: Vector2 = points[mini(points.size() - 1, index + 2)]
		for step in samples:
			path.append(start.cubic_interpolate(end, before, after, float(step) / float(samples)))
	path.append(points[-1])
	return path


func _button_for(event_id: String) -> Button:
	for button in _buttons:
		if button.name == "Stop_%s" % event_id:
			return button
	return null


func _room_color(room: String) -> Color:
	match room:
		"kitchen":
			return SKIN.ORANGE
		"workshop":
			return SKIN.YELLOW
		"office":
			return SKIN.BLUE
	return SKIN.LIME
