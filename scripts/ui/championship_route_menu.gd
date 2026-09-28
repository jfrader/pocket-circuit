class_name ChampionshipRouteMenu
extends Control

signal event_chosen(event_id: String)
signal return_chosen

const STAGE := preload("res://scripts/ui/app_shell_stage.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const BUTTON_SCRIPT := preload("res://scripts/ui/motorsport_button.gd")
const BOARD := Rect2(28, 18, 1224, 640)
const LANE_INSET := 20.0
const LANE_GUTTER := 14.0
const ROAD_AXIS := 58.0
const ROAD_WIDTH := 18.0
const ROAD_WAVE := 12.0
const ROAD_SAMPLES := 12
const ROAD_END_Y := 606.0
const FINISH_DEPTH := 10.0
const STOPS_TOP := 170.0
const STOPS_BOTTOM := 600.0
const STOP_RADIUS := 22.0
const FOCUS_RING := 32.0
const RIVAL_Y := 98.0
const RIVAL_WIDTH := 64.0
const ACT_TAPE_Y := 84.0
const ACT_TAPE_GAP := 22.0
const ACT_TAPE_PADDING := Vector2(16.0, 8.0)
const ACT_FONT_SIZE := 14
const CAR_LENGTH := 52.0
const CAR_CLEARANCE := 6.0
const LABEL_GAP := 14.0
const LABEL_PADDING := 10.0
const STOP_FONT_SIZE := 14
const NOTICE_FONT_SIZE := 14
const NOTICE_HEIGHT := 32.0
const NOTICE_PADDING := 40.0
const HINT := "ARROWS / STICK  MOVE   ·   ENTER / A  RACE   ·   ESC / B  BACK"
const HINT_FONT_SIZE := 13
const RETURN_SIZE := Vector2(250, 52)

var _stops: Array[Dictionary] = []
var _lanes: Array[Dictionary] = []
var _centers: Array[Vector2] = []
var _buttons: Array[Button] = []
var _focused_id := ""
var _vehicle_id := "rustbug"
var _notice := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func present(stops: Array, focus_id: String, vehicle_id: String, notice: String) -> void:
	_stops.assign(stops)
	_vehicle_id = vehicle_id if not vehicle_id.is_empty() else "rustbug"
	_notice = notice
	_focused_id = focus_id
	for child in get_children():
		remove_child(child)
		child.free()
	_buttons.clear()
	_layout_lanes()
	for lane in _lanes:
		var label_left: float = lane["axis"] + ROAD_WAVE + FOCUS_RING + LABEL_GAP
		var label_width: float = lane["right"] - LANE_GUTTER - label_left
		for index: int in lane["stops"]:
			var stop := _stops[index]
			var event_id := String(stop["id"])
			var button := BUTTON_SCRIPT.new() as Button
			button.name = "Stop_%s" % event_id
			button.text = "%s\n%s" % [String(stop["name"]), String(stop["status"])]
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.add_theme_font_size_override("font_size", STOP_FONT_SIZE)
			button.disabled = not bool(stop["unlocked"])
			button.set("selected", event_id == focus_id)
			button.focus_entered.connect(_focus_stop.bind(event_id))
			if not button.disabled:
				button.pressed.connect(event_chosen.emit.bind(event_id))
			add_child(button)
			_fit_label(button, label_left, label_width, _centers[index].y)
			_buttons.append(button)
	var back := BUTTON_SCRIPT.new() as Button
	back.name = "ReturnToTitle"
	back.text = "RETURN TO TITLE"
	back.pressed.connect(return_chosen.emit)
	add_child(back)
	back.size = RETURN_SIZE
	back.position = Vector2(BOARD.end.x - RETURN_SIZE.x - 30.0, BOARD.end.y - 8.0)
	_wire_focus(back)
	queue_redraw()
	var initial := _button_for(focus_id)
	if initial == null and not _buttons.is_empty():
		initial = _buttons[0]
	if initial != null:
		initial.grab_focus.call_deferred()


func _layout_lanes() -> void:
	_lanes.clear()
	_centers.clear()
	_centers.resize(_stops.size())
	for index in _stops.size():
		var stop := _stops[index]
		var act := int(stop.get("act", 0))
		if _lanes.is_empty() or int(_lanes[-1]["act"]) != act:
			_lanes.append({"act": act, "name": String(stop.get("act_name", "")), "stops": []})
		_lanes[-1]["stops"].append(index)
	var lane_width := (BOARD.size.x - LANE_INSET * 2.0) / float(maxi(1, _lanes.size()))
	for lane_index in _lanes.size():
		var lane := _lanes[lane_index]
		var left := BOARD.position.x + LANE_INSET + lane_width * lane_index
		var axis := left + ROAD_AXIS
		lane["right"] = left + lane_width
		lane["axis"] = axis
		var members: Array = lane["stops"]
		for order in members.size():
			var y := STOPS_TOP + (STOPS_BOTTOM - STOPS_TOP) * (order + 0.5) / float(members.size())
			_centers[members[order]] = Vector2(axis + (ROAD_WAVE if order % 2 == 1 else -ROAD_WAVE), y)


func _fit_label(button: Button, left: float, width: float, center_y: float) -> void:
	var margins := button.get_theme_stylebox("normal").get_minimum_size()
	var font := button.get_theme_font("font")
	var text_height := font.get_multiline_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, width - margins.x, button.get_theme_font_size("font_size")).y
	var height := maxf(text_height + margins.y + LABEL_PADDING, button.get_combined_minimum_size().y)
	button.size = Vector2(width, height)
	button.position = Vector2(left, center_y - height * 0.5)


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
	STAGE.draw_map_board(self, BOARD)
	for lane_index in _lanes.size():
		_draw_lane(_lanes[lane_index], lane_index)
	var focused := _index_of(_focused_id)
	if focused >= 0 and bool(_stops[focused]["unlocked"]):
		var heading := (_centers[focused] - _road_before(focused)).normalized()
		var car_center := _centers[focused] - heading * (FOCUS_RING + CAR_LENGTH * 0.5 + CAR_CLEARANCE)
		STAGE.draw_car(self, car_center, CAR_LENGTH, _vehicle_id, heading.angle() - Vector2.UP.angle())
	if not _notice.is_empty():
		var notice_width := SKIN.display_font().get_string_size(_notice, HORIZONTAL_ALIGNMENT_LEFT, -1, NOTICE_FONT_SIZE).x + NOTICE_PADDING
		SKIN.draw_tag(self, Rect2(BOARD.get_center().x - notice_width * 0.5, BOARD.position.y - NOTICE_HEIGHT * 0.3, notice_width, NOTICE_HEIGHT), _notice, SKIN.YELLOW, NOTICE_FONT_SIZE)
	SKIN.draw_text(self, Vector2(BOARD.position.x + 28.0, BOARD.end.y - 18.0), HINT, HINT_FONT_SIZE, SKIN.INK_SOFT)


func _draw_lane(lane: Dictionary, lane_index: int) -> void:
	var axis: float = lane["axis"]
	var members: Array = lane["stops"]
	var road: Array[Vector2] = [Vector2(axis, RIVAL_Y)]
	for index: int in members:
		road.append(_centers[index])
	road.append(Vector2(axis, ROAD_END_Y))
	STAGE.draw_road(self, STAGE.smooth_path(road, ROAD_SAMPLES), ROAD_WIDTH)
	var finish_half := ROAD_WIDTH * 0.5 + SKIN.LINE
	SKIN.draw_flag(self, Rect2(axis - finish_half, ROAD_END_Y - FINISH_DEPTH, finish_half * 2.0, FINISH_DEPTH), FINISH_DEPTH * 0.5)
	var rival := STAGE.act_rival(int(lane["act"]))
	if not rival.is_empty():
		STAGE.draw_portrait_card(self, Vector2(axis, RIVAL_Y), RIVAL_WIDTH, rival, -0.06 if lane_index % 2 == 0 else 0.06)
	_draw_act_tape(Vector2(axis + RIVAL_WIDTH * 0.5 + ACT_TAPE_GAP, ACT_TAPE_Y), String(lane["name"]).to_upper())
	for index: int in members:
		_draw_stop(index)


func _draw_act_tape(anchor: Vector2, text: String) -> void:
	if text.is_empty():
		return
	var text_width := SKIN.display_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, ACT_FONT_SIZE).x
	var tape_size := Vector2(text_width, ACT_FONT_SIZE) + ACT_TAPE_PADDING * 2.0
	draw_set_transform(anchor + Vector2(tape_size.x * 0.5, 0.0), -0.03)
	SKIN.draw_tape(self, Vector2.ZERO, tape_size)
	SKIN.draw_text(self, Vector2(-text_width * 0.5, ACT_FONT_SIZE * 0.36), text, ACT_FONT_SIZE, SKIN.INK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_stop(index: int) -> void:
	var stop := _stops[index]
	var center := _centers[index]
	if String(stop["id"]) == _focused_id:
		draw_arc(center, FOCUS_RING, 0.0, TAU, 40, SKIN.ORANGE, 5.0, true)
	if bool(stop["unlocked"]):
		STAGE.draw_room_stop(self, center, STOP_RADIUS, String(stop.get("theme", "kitchen")))
	else:
		SKIN.draw_disc(self, center, STOP_RADIUS, SKIN.WOOD_EDGE)
		SKIN.draw_padlock(self, center, STOP_RADIUS * 0.8)


func _road_before(index: int) -> Vector2:
	for lane in _lanes:
		var members: Array = lane["stops"]
		var order := members.find(index)
		if order > 0:
			return _centers[members[order - 1]]
		if order == 0:
			return Vector2(lane["axis"], RIVAL_Y)
	return _centers[index] + Vector2.UP


func _index_of(event_id: String) -> int:
	for index in _stops.size():
		if String(_stops[index]["id"]) == event_id:
			return index
	return -1


func _button_for(event_id: String) -> Button:
	for button in _buttons:
		if button.name == "Stop_%s" % event_id:
			return button
	return null
