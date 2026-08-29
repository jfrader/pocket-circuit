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
const HUD_TOP := preload("res://assets/ui/imagine/hud_top_plate.png")
const HUD_BOTTOM := preload("res://assets/ui/imagine/hud_bottom_plate.png")

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
	var top_height := 76.0
	var bottom_top := size.y - 48.0

	draw_rect(Rect2(0.0, 0.0, size.x, top_height), Color(INK, 0.88))
	draw_texture_rect(HUD_TOP, Rect2(0.0, 0.0, size.x, top_height), false)
	draw_rect(Rect2(0.0, top_height - 4.0, size.x, 4.0), AMBER)

	draw_string(font, Vector2(28.0, 25.0), "POSITION", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, MUTED)
	draw_string(font, Vector2(28.0, 65.0), _ordinal(race_position), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 42, RUST)
	draw_string(font, Vector2(166.0, 59.0), "/ %d" % racer_count, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, PAPER)

	draw_string(font, Vector2(276.0, 25.0), "LAP", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, MUTED)
	draw_string(font, Vector2(276.0, 61.0), "%d / %d" % [current_lap, lap_total], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 31, PAPER)
	draw_string(font, Vector2(480.0, 25.0), event_name, HORIZONTAL_ALIGNMENT_LEFT, 390.0, 13, AMBER)
	draw_string(font, Vector2(480.0, 61.0), _format_time(elapsed_seconds), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 31, PAPER)

	var display_speed := roundi(speed_ratio * 180.0)
	draw_string(font, Vector2(936.0, 25.0), "SPEED", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, MUTED)
	draw_string(font, Vector2(936.0, 63.0), "%03d" % display_speed, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 36, CYAN)
	draw_string(font, Vector2(1062.0, 59.0), "KM/H", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, PAPER)
	draw_string(font, Vector2(size.x - 174.0, 25.0), vehicle_name, HORIZONTAL_ALIGNMENT_RIGHT, 150.0, 12, MUTED)

	draw_rect(Rect2(0.0, bottom_top, size.x, 48.0), Color(INK, 0.88))
	draw_texture_rect(HUD_BOTTOM, Rect2(0.0, bottom_top, size.x, 48.0), false)
	draw_string(font, Vector2(24.0, bottom_top + 33.0), "BOOST", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, PAPER)
	_draw_boost_meter(Rect2(112.0, bottom_top + 14.0, 392.0, 20.0))
	draw_string(font, Vector2(size.x - 444.0, bottom_top + 31.0), "R  RECOVER     ESC / START  PAUSE", HORIZONTAL_ALIGNMENT_RIGHT, 420.0, 13, MUTED)

	if wrong_way:
		var warning_rect := Rect2(size.x * 0.5 - 176.0, 96.0, 352.0, 48.0)
		draw_rect(warning_rect, Color(INK, 0.94))
		draw_rect(Rect2(warning_rect.position, Vector2(8.0, warning_rect.size.y)), RUST)
		draw_rect(Rect2(warning_rect.end - Vector2(8.0, warning_rect.size.y), Vector2(8.0, warning_rect.size.y)), RUST)
		draw_string(font, warning_rect.position + Vector2(0.0, 34.0), "WRONG WAY", HORIZONTAL_ALIGNMENT_CENTER, warning_rect.size.x, 26, RUST)


func _draw_boost_meter(rect: Rect2) -> void:
	draw_rect(rect, DARK_METER)
	var segment_count := 10
	var gap := 4.0
	var segment_width := (rect.size.x - gap * float(segment_count + 1)) / float(segment_count)
	var active_segments := ceili(boost_ratio * float(segment_count))
	for index in segment_count:
		var segment_rect := Rect2(rect.position + Vector2(gap + float(index) * (segment_width + gap), gap), Vector2(segment_width, rect.size.y - gap * 2.0))
		var segment_color := AMBER if index < active_segments else Color("39434d")
		if index < active_segments and index >= 7:
			segment_color = RUST
		draw_rect(segment_rect, segment_color)


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
