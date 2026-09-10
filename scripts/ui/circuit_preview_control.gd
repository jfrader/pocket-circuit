class_name CircuitPreviewControl
extends Control

const INK := Color("101b21")
const AMBER := Color("f4c65a")
const CORAL := Color("e85a2e")
const MUTED := Color("4a5a6c")

var points := PackedVector2Array()


func _ready() -> void:
	custom_minimum_size = Vector2(420.0, 190.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_preview(preview: Dictionary) -> void:
	points = (preview.get("points", PackedVector2Array()) as PackedVector2Array).duplicate()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(INK, 0.92), true)
	draw_rect(Rect2(Vector2.ZERO, size), MUTED, false, 2.0)
	if points.size() < 3:
		draw_string(ThemeDB.fallback_font, Vector2(22.0, size.y * 0.55), "PREPARING ROUTE PREVIEW…", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, AMBER)
		return
	var scaled := PackedVector2Array()
	var source_size := Vector2(420.0, 190.0)
	for point: Vector2 in points:
		scaled.append(point * (size / source_size))
	scaled.append(scaled[0])
	draw_polyline(scaled, Color(INK, 0.9), 15.0, true)
	draw_polyline(scaled, AMBER, 7.0, true)
	draw_circle(scaled[0], 7.0, CORAL)