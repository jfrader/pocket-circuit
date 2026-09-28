class_name CircuitPreviewControl
extends Control

const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const SOURCE_SIZE := Vector2(420.0, 190.0)
const GRID_CELL := 20.0
const ROAD_WIDTH := 11.0
const START_MARKER := 14.0

var points := PackedVector2Array()


func _ready() -> void:
	custom_minimum_size = SOURCE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_preview(preview: Dictionary) -> void:
	points = (preview.get("points", PackedVector2Array()) as PackedVector2Array).duplicate()
	queue_redraw()


func _draw() -> void:
	var card := Rect2(Vector2.ZERO, size - Vector2.ONE * SKIN.SHADOW)
	SKIN.draw_plate(self, card, SKIN.CREAM)
	SKIN.draw_grid(self, card.grow(-SKIN.LINE - 4.0), GRID_CELL)
	if points.size() < 3:
		SKIN.draw_text(self, Vector2(22.0, card.size.y * 0.55), "PREPARING ROUTE PREVIEW…", 16, SKIN.INK)
		return
	var scaled := PackedVector2Array()
	var scale_factor := card.size / SOURCE_SIZE
	for point: Vector2 in points:
		scaled.append(point * scale_factor)
	scaled.append(scaled[0])
	draw_polyline(scaled, SKIN.INK, ROAD_WIDTH + SKIN.LINE * 2.0, true)
	draw_polyline(scaled, SKIN.ASPHALT, ROAD_WIDTH, true)
	draw_polyline(scaled, Color(SKIN.CREAM, 0.55), 1.5, true)
	SKIN.draw_flag(self, Rect2(scaled[0] - Vector2.ONE * START_MARKER * 0.5, Vector2.ONE * START_MARKER), START_MARKER * 0.25)
