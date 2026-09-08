class_name RaceHUD
extends Control

const INK := Color("0e151f")
const PAPER := Color("f5f0e3")
const MUTED := Color("aeb7c8")
const AMBER := Color("f4c65a")
const DARK_METER := Color("27313a")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")

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
var _position_plate: StyleBoxTexture = SKIN.panel(true)
var _instrument_plate: StyleBoxTexture = SKIN.panel(false)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_position_plate.modulate_color = Color.WHITE
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
	var font := ThemeDB.fallback_font
	var layout := get_layout_rects()
	_draw_position_cluster(font, layout)
	_draw_clock_cluster(font, layout["clock"])
	_draw_speed_cluster(font, layout["speed"], layout["controls_hint"])
	_draw_route_progress(font, layout["progress"])
	if wrong_way:
		_draw_wrong_way(font, layout["warning"])


func _outlined(font: Font, pos: Vector2, text: String, width: float, font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string_outline(font, pos, text, alignment, width, font_size, 2, INK)
	draw_string(font, pos, text, alignment, width, font_size, color)


func get_layout_rects() -> Dictionary:
	return {
		"position": Rect2(24, 24, 168, 72),
		"lap": Rect2(202, 24, 190, 72),
		"clock": Rect2(size.x - 224, 24, 200, 72),
		"speed": Rect2(size.x - 314, size.y - 112, 290, 88),
		"progress": Rect2(size.x * 0.5 - 170, size.y - 76, 340, 52),
		"warning": Rect2(size.x * 0.5 - 170, 116, 340, 48),
		"controls_hint": Rect2(24, size.y - 50, 390, 26),
	}


func _text(font: Font, pos: Vector2, text: String, font_size: int, color: Color, width: float = -1.0, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(font, pos, text, alignment, width, font_size, color)


func _draw_position_cluster(font: Font, layout: Dictionary) -> void:
	var position_rect: Rect2 = layout["position"]
	draw_style_box(_position_plate, position_rect)
	var origin := position_rect.position
	for row in 4:
		for column in 4:
			if (row + column) % 2 == 0:
				draw_rect(Rect2(origin + Vector2(16 + column * 5, 29 + row * 5), Vector2(5, 5)), INK)
	_text(font, origin + Vector2(48, 24), "POSITION", 11, INK)
	_text(font, origin + Vector2(48, 57), str(race_position), 34, INK)
	_text(font, origin + Vector2(89, 57), "/ %d" % racer_count, 20, INK)
	var lap_rect: Rect2 = layout["lap"]
	draw_style_box(_instrument_plate, lap_rect)
	_text(font, lap_rect.position + Vector2(16, 28), "LAP", 12, MUTED)
	_text(font, lap_rect.position + Vector2(67, 29), "%d / %d" % [current_lap, lap_total], 22, PAPER)
	_text(font, lap_rect.position + Vector2(16, 55), "FINISH GATE" if next_checkpoint == 0 else "NEXT GATE %d" % next_checkpoint, 12, AMBER)


func _draw_clock_cluster(font: Font, rect: Rect2) -> void:
	draw_style_box(_instrument_plate, rect)
	_text(font, rect.position + Vector2(16, 23), "RACE TIME", 11, MUTED)
	_text(font, rect.position + Vector2(16, 56), _format_time(elapsed_seconds), 26, PAPER, rect.size.x - 32, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_speed_cluster(font: Font, rect: Rect2, hint_rect: Rect2) -> void:
	var origin := rect.position
	draw_style_box(_instrument_plate, rect)
	var kmh := "%03d" % roundi(speed_ratio * 180.0)
	_text(font, origin + Vector2(18, 25), "SPEED", 11, MUTED)
	_text(font, origin + Vector2(18, 63), kmh, 30, PAPER)
	_text(font, origin + Vector2(88, 61), "KM/H", 11, MUTED)
	_text(font, origin + Vector2(136, 25), "BOOST  %d%%" % roundi(boost_ratio * 100), 12, AMBER)
	for index in 10:
		var segment := Rect2(origin + Vector2(136 + index * 12, 36), Vector2(8, 12))
		draw_rect(segment, DARK_METER)
		segment.size.x *= clampf(boost_ratio * 10 - index, 0, 1)
		if segment.size.x > 0:
			draw_rect(segment, SKIN.TEAL)
	_text(font, origin + Vector2(136, 68), "SHIFT / B", 11, MUTED)
	if elapsed_seconds < 10.0:
		_outlined(font, hint_rect.position + Vector2(0, 18), "R / Y  RECOVER   ·   ESC / START  PAUSE", hint_rect.size.x, 13, PAPER)


func _draw_route_progress(font: Font, rect: Rect2) -> void:
	if route_progress.is_empty():
		return
	draw_style_box(_instrument_plate, rect)
	var origin := rect.position + Vector2(16, 20)
	var length := rect.size.x - 32
	draw_line(origin, origin + Vector2(length, 0), MUTED, 2)
	for index in route_progress.size():
		if index == player_progress_index:
			continue
		draw_circle(origin + Vector2(clampf(route_progress[index], 0, 1) * length, 0), 3, PAPER)
	if player_progress_index >= 0 and player_progress_index < route_progress.size():
		var player_x := clampf(route_progress[player_progress_index], 0, 1) * length
		draw_circle(origin + Vector2(player_x, 0), 6, AMBER)
	_text(font, rect.position + Vector2(16, 43), "RACE PROGRESS", 11, MUTED, length, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_wrong_way(font: Font, warning_rect: Rect2) -> void:
	draw_style_box(_instrument_plate, warning_rect)
	_text(font, warning_rect.position + Vector2(0, 33), "WRONG WAY", 23, AMBER, warning_rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _format_time(total_seconds: float) -> String:
	return "%02d:%04.1f" % [int(total_seconds / 60.0), fmod(total_seconds, 60.0)]
