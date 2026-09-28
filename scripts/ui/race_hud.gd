class_name RaceHUD
extends Control

const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const HINT_SECONDS := 10.0
const KMH_AT_FULL_SPEED := 180.0
const SPEED_FORMAT := "%03d"
const SPEED_UNIT := "KM/H"
const SPEED_FONT_SIZE := 26
const CAPTION_FONT_SIZE := 11
const SPEED_PADDING := 14.0
const BOOST_TUBE_HEIGHT := 32.0

var race_position := 1
var racer_count := 4
var current_lap := 1
var lap_total := 3
var elapsed_seconds := 0.0
var speed_ratio := 0.0
var boost_ratio := 0.0
var event_name := "HOUSEHOLD CIRCUIT"
var vehicle_name := "RUSTBUG"
var wrong_way := false
var route_progress := PackedFloat32Array()
var player_progress_index := 0
var next_checkpoint := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	queue_redraw()


func set_context(next_event_name: String, next_vehicle_name: String) -> void:
	event_name = next_event_name.to_upper()
	vehicle_name = next_vehicle_name.to_upper()
	queue_redraw()


func set_telemetry(position_value: int, racer_count_value: int, lap_value: int, lap_total_value: int, elapsed_value: float, speed_value: float, boost_value: float) -> void:
	race_position = maxi(1, position_value)
	racer_count = maxi(1, racer_count_value)
	current_lap = maxi(1, lap_value)
	lap_total = maxi(1, lap_total_value)
	elapsed_seconds = maxf(0.0, elapsed_value)
	speed_ratio = clampf(speed_value, 0.0, 1.2)
	boost_ratio = clampf(boost_value, 0.0, 1.0)
	queue_redraw()


func set_wrong_way(enabled: bool) -> void:
	wrong_way = enabled
	queue_redraw()


func set_route_progress(progress: PackedFloat32Array, player_index: int, checkpoint: int) -> void:
	route_progress = progress
	player_progress_index = player_index
	next_checkpoint = checkpoint
	queue_redraw()


func _draw() -> void:
	if size.x < 640.0 or size.y < 360.0:
		return
	var layout := get_layout_rects()
	_draw_position(layout["position"])
	_draw_lap(layout["lap"])
	_draw_clock(layout["clock"])
	_draw_speed(layout["speed"])
	_draw_route_progress(layout["progress"])
	if elapsed_seconds < HINT_SECONDS:
		var hint_rect: Rect2 = layout["controls_hint"]
		SKIN.draw_plate(self, hint_rect, SKIN.INK, 4, 0.0)
		SKIN.draw_text(self, hint_rect.position + Vector2(10.0, 17.0), "R / Y  RECOVER   ·   ESC / START  PAUSE", 12, SKIN.CREAM, hint_rect.size.x - 16.0)
	if wrong_way:
		_draw_wrong_way(layout["warning"])


func get_layout_rects() -> Dictionary:
	return {
		"position": Rect2(24, 24, 150, 76),
		"lap": Rect2(184, 30, 150, 64),
		"clock": Rect2(size.x - 204, 24, 180, 64),
		"speed": Rect2(size.x - 304, size.y - 104, 280, 80),
		"progress": Rect2(size.x * 0.5 - 170, size.y - 64, 340, 40),
		"warning": Rect2(size.x * 0.5 - 150, 116, 300, 52),
		"controls_hint": Rect2(24, size.y - 48, 380, 24),
	}


func _draw_position(rect: Rect2) -> void:
	SKIN.draw_plate(self, rect, SKIN.CREAM)
	var flag_height := rect.size.y - 24.0
	SKIN.draw_flag(self, Rect2(rect.position + Vector2(12.0, 12.0), Vector2(18.0, flag_height)), 6.0)
	var origin := rect.position + Vector2(42.0, 0.0)
	if racer_count <= 1:
		_caption(origin + Vector2(0.0, 22.0), "TIME TRIAL")
		SKIN.draw_text(self, origin + Vector2(0.0, 58.0), "SOLO", 30, SKIN.INK)
		return
	_caption(origin + Vector2(0.0, 22.0), "POSITION")
	var place := str(race_position)
	SKIN.draw_text(self, origin + Vector2(0.0, 64.0), place, 42, SKIN.INK)
	var place_width := SKIN.display_font().get_string_size(place, HORIZONTAL_ALIGNMENT_LEFT, -1, 42).x
	SKIN.draw_text(self, origin + Vector2(place_width + 6.0, 62.0), "/%d" % racer_count, 22, SKIN.INK_SOFT)


func _draw_lap(rect: Rect2) -> void:
	var final_lap := current_lap == lap_total
	SKIN.draw_plate(self, rect, SKIN.YELLOW if final_lap else SKIN.CREAM)
	_caption(rect.position + Vector2(16.0, 22.0), "LAP")
	var lap_hint := "TO FINISH" if next_checkpoint == 0 else ("FINAL" if final_lap else "")
	if not lap_hint.is_empty():
		SKIN.draw_text(self, rect.position + Vector2(16.0, 22.0), lap_hint, 11, SKIN.ORANGE.darkened(0.35), rect.size.x - 32.0 - SKIN.SHADOW, HORIZONTAL_ALIGNMENT_RIGHT)
	SKIN.draw_text(self, rect.position + Vector2(16.0, 52.0), "%d / %d" % [current_lap, lap_total], 26, SKIN.INK)


func _draw_clock(rect: Rect2) -> void:
	SKIN.draw_plate(self, rect, SKIN.CREAM)
	_caption(rect.position + Vector2(16.0, 22.0), "TIME")
	SKIN.draw_text(self, rect.position + Vector2(16.0, 52.0), _format_time(elapsed_seconds), 26, SKIN.INK, rect.size.x - 32.0 - SKIN.SHADOW, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_speed(rect: Rect2) -> void:
	SKIN.draw_plate(self, rect, SKIN.CREAM)
	var face := Rect2(rect.position, rect.size - Vector2.ONE * SKIN.SHADOW).grow(-SPEED_PADDING)
	var font := SKIN.display_font()
	var readout_width := maxf(
		font.get_string_size(SPEED_FORMAT % 0, HORIZONTAL_ALIGNMENT_LEFT, -1, SPEED_FONT_SIZE).x,
		font.get_string_size(SPEED_UNIT, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_FONT_SIZE).x
	)
	SKIN.draw_text(self, Vector2(face.position.x, rect.position.y + 38.0), SPEED_FORMAT % roundi(speed_ratio * KMH_AT_FULL_SPEED), SPEED_FONT_SIZE, SKIN.INK)
	_caption(Vector2(face.position.x, rect.position.y + 58.0), SPEED_UNIT)
	var tube_left := face.position.x + readout_width + SPEED_PADDING
	SKIN.draw_tube(self, Rect2(tube_left, face.get_center().y - BOOST_TUBE_HEIGHT * 0.5, face.end.x - tube_left, BOOST_TUBE_HEIGHT), boost_ratio)


func _draw_route_progress(rect: Rect2) -> void:
	if route_progress.is_empty():
		return
	SKIN.draw_plate(self, rect, SKIN.CREAM, roundi(rect.size.y * 0.5))
	var line_y := rect.position.y + (rect.size.y - SKIN.SHADOW) * 0.5 + 1.0
	var start := Vector2(rect.position.x + 22.0, line_y)
	var length := rect.size.x - 60.0
	draw_line(start, start + Vector2(length, 0.0), SKIN.INK_SOFT, 3.0, true)
	SKIN.draw_flag(self, Rect2(start + Vector2(length + 6.0, -8.0), Vector2(12.0, 16.0)), 4.0)
	for index in route_progress.size():
		if index != player_progress_index:
			SKIN.draw_disc(self, start + Vector2(clampf(route_progress[index], 0.0, 1.0) * length, 0.0), 4.0, SKIN.BLUE, 0.0)
	if player_progress_index >= 0 and player_progress_index < route_progress.size():
		SKIN.draw_disc(self, start + Vector2(clampf(route_progress[player_progress_index], 0.0, 1.0) * length, 0.0), 7.0, SKIN.ORANGE, 2.0)


func _draw_wrong_way(rect: Rect2) -> void:
	SKIN.draw_plate(self, rect, SKIN.RED)
	SKIN.draw_text(self, rect.position + Vector2(0.0, 36.0), "WRONG WAY", 28, SKIN.CREAM, rect.size.x - SKIN.SHADOW, HORIZONTAL_ALIGNMENT_CENTER)


func _caption(text_position: Vector2, text: String) -> void:
	SKIN.draw_text(self, text_position, text, CAPTION_FONT_SIZE, SKIN.INK_SOFT)


func _format_time(total_seconds: float) -> String:
	return "%02d:%04.1f" % [int(total_seconds / 60.0), fmod(total_seconds, 60.0)]
