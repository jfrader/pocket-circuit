class_name RaceHUD
extends Control

const INK := Color("0e151f")
const MIDNIGHT := Color("101722")
const PAPER := Color("f5f0e3")
const MUTED := Color("aeb7c8")
const AMBER := Color("f4c65a")
const RUST := Color("e85a2e")
const CYAN := Color("4a8fb8")
const DARK_METER := Color("27313a")

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


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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


func _draw() -> void:
	if size.x < 640.0 or size.y < 360.0:
		return
	var font := ThemeDB.fallback_font
	_draw_position_cluster(font)
	_draw_clock_cluster(font)
	_draw_speed_cluster(font)
	if wrong_way:
		_draw_wrong_way(font)


func _outlined(font: Font, pos: Vector2, text: String, width: float, font_size: int, color: Color, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string_outline(font, pos, text, alignment, width, font_size, 8, INK)
	draw_string(font, pos, text, alignment, width, font_size, color)


func _draw_position_cluster(font: Font) -> void:
	_outlined(font, Vector2(36.0, 86.0), _ordinal(race_position), -1.0, 72, RUST)
	_outlined(font, Vector2(36.0, 112.0), "POS  %d / %d" % [race_position, racer_count], -1.0, 16, MUTED)


func _draw_clock_cluster(font: Font) -> void:
	var width := 280.0
	var left := size.x - width - 36.0
	_outlined(font, Vector2(left, 48.0), _format_time(elapsed_seconds), width, 30, PAPER, HORIZONTAL_ALIGNMENT_RIGHT)
	_outlined(font, Vector2(left, 76.0), "LAP  %d / %d" % [current_lap, lap_total], width, 18, AMBER, HORIZONTAL_ALIGNMENT_RIGHT)
	_outlined(font, Vector2(left, 98.0), event_name, width, 13, MUTED, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_speed_cluster(font: Font) -> void:
	var center := Vector2(size.x - 158.0, size.y - 142.0)
	var start_angle := deg_to_rad(140.0)
	var end_angle := deg_to_rad(400.0)
	var span := end_angle - start_angle
	var speed := clampf(speed_ratio, 0.0, 1.0)
	var speed_color := CYAN if speed < 0.86 else RUST
	draw_circle(center, 108.0, Color(INK, 0.38))
	draw_arc(center, 92.0, start_angle, end_angle, 52, Color(0.1, 0.133, 0.173, 0.95), 16.0, true)
	draw_arc(center, 92.0, start_angle, start_angle + span * speed, 52, speed_color, 16.0, true)
	draw_arc(center, 74.0, start_angle, end_angle, 36, Color("24303a"), 8.0, true)
	draw_arc(center, 74.0, start_angle, start_angle + span * boost_ratio, 36, AMBER, 8.0, true)
	var kmh := "%03d" % roundi(speed_ratio * 180.0)
	_outlined(font, Vector2(center.x - 90.0, center.y + 8.0), kmh, 180.0, 48, PAPER, HORIZONTAL_ALIGNMENT_CENTER)
	_outlined(font, Vector2(center.x - 90.0, center.y + 34.0), "KM/H", 180.0, 14, CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	_outlined(font, Vector2(center.x - 90.0, center.y + 56.0), vehicle_name, 180.0, 13, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_outlined(font, Vector2(center.x - 90.0, center.y + 80.0), "BOOST  %d%%" % roundi(boost_ratio * 100.0), 180.0, 12, AMBER, HORIZONTAL_ALIGNMENT_CENTER)
	_outlined(font, Vector2(32.0, size.y - 28.0), "R  RECOVER      ESC / START  PAUSE", -1.0, 14, Color(MUTED, 0.9))


func _draw_wrong_way(font: Font) -> void:
	var warning_rect := Rect2(size.x * 0.5 - 176.0, 128.0, 352.0, 48.0)
	draw_rect(warning_rect, Color(INK, 0.86))
	draw_rect(Rect2(warning_rect.position, Vector2(8.0, warning_rect.size.y)), RUST)
	draw_rect(Rect2(warning_rect.end - Vector2(8.0, warning_rect.size.y), Vector2(8.0, warning_rect.size.y)), RUST)
	_outlined(font, warning_rect.position + Vector2(0.0, 34.0), "WRONG WAY", warning_rect.size.x, 26, RUST, HORIZONTAL_ALIGNMENT_CENTER)


func _format_time(total_seconds: float) -> String:
	return "%02d:%04.1f" % [int(total_seconds / 60.0), fmod(total_seconds, 60.0)]


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
