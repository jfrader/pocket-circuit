class_name CarShapeView
extends Control

## A car's six-axis shape on a plate card, optionally drawn against another
## car with per-axis deltas. The garage stage and the run's car offer both draw
## it through draw_card, so the shape reads the same everywhere.

const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const RINGS := 4
## The innermost a shape vertex sits, so a weak axis still reads as a corner.
const FLOOR := 0.14
const DASH := 5.0
const RADIUS_RATIO := 0.33

var shape: Dictionary = {}
var compare_shape: Dictionary = {}
var label := ""


func show_shape(next_shape: Dictionary, next_compare: Dictionary, next_label: String) -> void:
	shape = next_shape
	compare_shape = next_compare
	label = next_label
	queue_redraw()


func _draw() -> void:
	draw_card(self, Rect2(Vector2.ZERO, size), shape, shape, compare_shape, label)


## `shown` is what the polygon draws (it may be mid-morph); `target` is the
## car's real shape the deltas are read from.
static func draw_card(item: CanvasItem, rect: Rect2, shown: Dictionary, target: Dictionary, compare: Dictionary, title: String) -> void:
	SKIN.draw_plate(item, rect, SKIN.CREAM)
	var tape_center := Vector2(rect.get_center().x, rect.position.y + 4.0)
	SKIN.draw_tape(item, tape_center, Vector2(rect.size.x * 0.66, 24.0), -0.03)
	SKIN.draw_text(item, Vector2(rect.position.x, tape_center.y + 5.0), title, 13, SKIN.INK, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if shown.is_empty():
		return
	var center := rect.get_center() + Vector2(0.0, 12.0)
	var radius := minf(rect.size.x, rect.size.y) * RADIUS_RATIO
	for ring in range(1, RINGS + 1):
		var ring_points := _points(center, radius * float(ring) / float(RINGS), {}, 1.0)
		ring_points.append(ring_points[0])
		item.draw_polyline(ring_points, Color(SKIN.INK, 0.12), 1.0, true)
	for corner: Vector2 in _points(center, radius, {}, 1.0):
		item.draw_line(center, corner, Color(SKIN.INK, 0.12), 1.0, true)
	var points := _points(center, radius, shown)
	item.draw_colored_polygon(points, Color(SKIN.ORANGE, 0.82))
	var outline := points.duplicate()
	outline.append(points[0])
	item.draw_polyline(outline, SKIN.INK, 2.0, true)
	for point: Vector2 in points:
		item.draw_circle(point, 3.5, SKIN.INK)
		item.draw_circle(point, 2.0, SKIN.YELLOW)
	if not compare.is_empty():
		var compared := _points(center, radius, compare)
		for index in compared.size():
			item.draw_dashed_line(compared[index], compared[(index + 1) % compared.size()], SKIN.BLUE, 2.5, DASH, true)
	var label_points := _points(center, radius + 22.0, {}, 1.0)
	for index in CarProfile.AXES.size():
		var axis := CarProfile.AXES[index]
		var at := label_points[index]
		SKIN.draw_text(item, at + Vector2(-40.0, 4.0), axis.to_upper(), 12, SKIN.INK, 80.0, HORIZONTAL_ALIGNMENT_CENTER, false)
		if compare.is_empty():
			continue
		var delta := roundi((float(target.get(axis, 0.0)) - float(compare.get(axis, 0.0))) * 100.0)
		if delta != 0:
			SKIN.draw_text(item, at + Vector2(-40.0, 18.0), "%+d" % delta, 12, SKIN.LIME if delta > 0 else SKIN.RED, 80.0, HORIZONTAL_ALIGNMENT_CENTER, false)


## Hexagon corners clockwise from the top; each axis value pushes its corner out.
static func _points(center: Vector2, radius: float, values: Dictionary, fixed: float = -1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in CarProfile.AXES.size():
		var reach := fixed if fixed >= 0.0 else lerpf(FLOOR, 1.0, float(values.get(CarProfile.AXES[index], 0.0)))
		points.append(center + Vector2.from_angle(-PI * 0.5 + TAU * float(index) / float(CarProfile.AXES.size())) * radius * reach)
	return points
