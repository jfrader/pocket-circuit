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
## Seconds a shape takes to grow out of the one it is shown against.
const MORPH_TIME := 0.45
const HEADER_FONT_SIZE := 13
const HEADER_TAPE_HEIGHT := 24.0
const HEADER_TAPE_WIDTH_RATIO := 0.66
const HEADER_TAPE_ANGLE := -0.03
const AXIS_LABEL_GAP := 22.0
const AXIS_FONT_SIZE := 12
const DELTA_BASELINE := 18.0
const DELTA_CAPTION := "SHAPE DELTAS, NOT PERCENTAGES"
const CAPTION_FONT_SIZE := 10
const CAPTION_GAP := 4.0

var shape: Dictionary = {}
var compare_shape: Dictionary = {}
var label := ""
var plot_bottom_padding := 0.0
var _morph_from: Dictionary = {}
var _morph := 1.0


## Shows a shape; given `morph_from`, the polygon grows out of that shape.
func show_shape(next_shape: Dictionary, next_compare: Dictionary, next_label: String, morph_from: Dictionary = {}) -> void:
	shape = next_shape
	compare_shape = next_compare
	label = next_label
	_morph_from = morph_from
	_morph = 1.0
	if not morph_from.is_empty():
		_morph = 0.0
		var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_method(func(at: float) -> void:
			_morph = at
			queue_redraw(), 0.0, 1.0, MORPH_TIME)
	queue_redraw()


func _draw() -> void:
	var shown := shape
	if _morph < 1.0:
		shown = {}
		for axis: Variant in shape:
			shown[axis] = lerpf(float(_morph_from.get(axis, shape[axis])), float(shape[axis]), _morph)
	draw_card(self, Rect2(Vector2.ZERO, size), shown, shape, compare_shape, label, plot_bottom_padding)


## `shown` is what the polygon draws (it may be mid-morph); `target` is the
## car's real shape the deltas are read from.
static func draw_card(item: CanvasItem, rect: Rect2, shown: Dictionary, target: Dictionary, compare: Dictionary, title: String, bottom_padding: float = 0.0) -> void:
	SKIN.draw_plate(item, rect, SKIN.CREAM)
	var header := header_geometry(rect, title)
	SKIN.draw_tape(item, header.tape_center, header.tape_size, HEADER_TAPE_ANGLE)
	SKIN.draw_text(item, header.text_position, title, HEADER_FONT_SIZE, SKIN.INK, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var caption := caption_geometry(rect)
	SKIN.draw_text(item, caption.text_position, caption.text, CAPTION_FONT_SIZE, SKIN.CREAM_DIM, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER, false)
	if shown.is_empty():
		return
	var plot := plot_geometry(rect, bottom_padding)
	var center: Vector2 = plot["center"]
	var radius: float = plot["radius"]
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
	var label_points := _points(center, radius + AXIS_LABEL_GAP, {}, 1.0)
	for index in CarProfile.AXES.size():
		var axis := CarProfile.AXES[index]
		var at := label_points[index]
		SKIN.draw_text(item, at + Vector2(-40.0, 4.0), axis.to_upper(), AXIS_FONT_SIZE, SKIN.INK, 80.0, HORIZONTAL_ALIGNMENT_CENTER, false)
		if compare.is_empty():
			continue
		var delta := roundi((float(target.get(axis, 0.0)) - float(compare.get(axis, 0.0))) * 100.0)
		if delta != 0:
			SKIN.draw_text(item, at + Vector2(-40.0, DELTA_BASELINE), "%+d" % delta, AXIS_FONT_SIZE, SKIN.LIME if delta > 0 else SKIN.RED, 80.0, HORIZONTAL_ALIGNMENT_CENTER, false)


static func caption_geometry(rect: Rect2) -> Dictionary:
	var font := ThemeDB.fallback_font
	var ascent := font.get_ascent(CAPTION_FONT_SIZE)
	var descent := font.get_descent(CAPTION_FONT_SIZE)
	var width := font.get_string_size(DELTA_CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_FONT_SIZE).x
	return {
		"text": DELTA_CAPTION,
		"text_position": Vector2(rect.position.x, rect.end.y + CAPTION_GAP + ascent),
		"bounds": Rect2(Vector2(rect.get_center().x - width * 0.5, rect.end.y + CAPTION_GAP), Vector2(width, ascent + descent)),
	}


static func plot_geometry(rect: Rect2, bottom_padding: float = 0.0) -> Dictionary:
	var center := rect.get_center() + Vector2(0.0, 12.0)
	var radius := minf(rect.size.x, rect.size.y) * RADIUS_RATIO
	if bottom_padding > 0.0:
		var lowest := center.y + radius + AXIS_LABEL_GAP + DELTA_BASELINE + ThemeDB.fallback_font.get_descent(AXIS_FONT_SIZE)
		var inset := minf(radius, maxf(0.0, lowest - (rect.end.y - bottom_padding)) * 0.5)
		center.y -= inset
		radius -= inset
	return {"center": center, "radius": radius}


## Bounds include clearance around the tape's torn edges.
static func header_geometry(rect: Rect2, title: String) -> Dictionary:
	var font := SKIN.display_font()
	var ascent := font.get_ascent(HEADER_FONT_SIZE)
	var descent := font.get_descent(HEADER_FONT_SIZE)
	var tape_size := Vector2(rect.size.x * HEADER_TAPE_WIDTH_RATIO, maxf(HEADER_TAPE_HEIGHT, ascent + descent + SKIN.LINE * 2.0))
	var tape_bounds := (Transform2D(HEADER_TAPE_ANGLE, Vector2.ZERO) * Rect2(-tape_size * 0.5, tape_size)).grow(SKIN.LINE)
	var tape_center := Vector2(rect.get_center().x, rect.position.y + SKIN.LINE - tape_bounds.position.y)
	tape_bounds.position += tape_center
	var text_position := Vector2(rect.position.x, tape_center.y + (ascent - descent) * 0.5)
	var text_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, HEADER_FONT_SIZE).x
	var text_bounds := Rect2(Vector2(rect.get_center().x - text_width * 0.5, text_position.y - ascent), Vector2(text_width, ascent + descent))
	return {
		"tape_center": tape_center,
		"tape_size": tape_size,
		"tape_bounds": tape_bounds,
		"text_position": text_position,
		"text_bounds": text_bounds,
	}


## Hexagon corners clockwise from the top; each axis value pushes its corner out.
static func _points(center: Vector2, radius: float, values: Dictionary, fixed: float = -1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in CarProfile.AXES.size():
		var reach := fixed if fixed >= 0.0 else lerpf(FLOOR, 1.0, float(values.get(CarProfile.AXES[index], 0.0)))
		points.append(center + Vector2.from_angle(-PI * 0.5 + TAU * float(index) / float(CarProfile.AXES.size())) * radius * reach)
	return points
