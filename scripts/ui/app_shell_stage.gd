class_name AppShellStage
extends Control

const CATALOG := preload("res://data/championship/catalog.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const DriverDirectory := preload("res://scripts/progression/driver_directory.gd")
const CAR_ASPECT := 0.75
const CARD_ASPECT := 1.24
const SHAPE_CARD_MAX_HEIGHT := 330.0
const SHAPE_RINGS := 4
## The innermost a shape vertex sits, so a weak axis still reads as a corner.
const SHAPE_FLOOR := 0.14
const SHAPE_DASH := 5.0
const SHAPE_RADIUS_RATIO := 0.33
const CONFETTI_SEED := 1278
const CONFETTI_PIECES := 46
const ROOM_ICON_RADIUS := 32.0

var mode: StringName = &"title"
var vehicle_id := "rustbug"
var driver_id := "rae"
var secondary_driver_id := ""
var theme_id := "kitchen"
var unlocked_vehicle_ids: Array[String] = ["rustbug"]
## The garage's six-axis shape: the car shown, the car it is compared with,
## and how far the drawing has travelled from the previous car (0..1).
var shape: Dictionary = {}
var compare_shape: Dictionary = {}
var compare_label := ""
var shape_blend := 1.0:
	set(value):
		shape_blend = value
		queue_redraw()
var _shape_from: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func configure(
		next_mode: StringName,
		next_vehicle_id: String = "rustbug",
		next_driver_id: String = "rae",
		next_theme_id: String = "kitchen",
		next_secondary_driver_id: String = "",
		next_unlocked_vehicle_ids: Array = ["rustbug"]
) -> void:
	mode = next_mode
	vehicle_id = next_vehicle_id if not next_vehicle_id.is_empty() else "rustbug"
	driver_id = next_driver_id if not next_driver_id.is_empty() else "rae"
	theme_id = next_theme_id if not next_theme_id.is_empty() else "kitchen"
	secondary_driver_id = next_secondary_driver_id
	unlocked_vehicle_ids.assign(next_unlocked_vehicle_ids)
	queue_redraw()


static func draw_map_board(item: CanvasItem, board: Rect2) -> void:
	SKIN.draw_plate(item, board, SKIN.CREAM, 14)
	SKIN.draw_grid(item, board.grow(-14.0), 26.0)
	SKIN.draw_tape(item, board.position + Vector2(34.0, 6.0), Vector2(92.0, 22.0), -0.6)
	SKIN.draw_tape(item, Vector2(board.end.x - 34.0, board.position.y + 6.0), Vector2(92.0, 22.0), 0.6)


static func draw_car(item: CanvasItem, center: Vector2, length: float, id: String, angle: float = 0.0, locked: bool = false) -> void:
	var texture := IDENTITIES.car_texture(id)
	if texture == null:
		return
	var car_size := Vector2(length * CAR_ASPECT, length)
	item.draw_set_transform(center, angle)
	item.draw_texture_rect(texture, Rect2(-car_size * 0.5, car_size), false, Color(SKIN.INK, 0.92) if locked else Color.WHITE)
	item.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if locked:
		SKIN.draw_padlock(item, center, maxf(12.0, length * 0.24))


static func draw_portrait_card(item: CanvasItem, center: Vector2, width: float, id: String, angle: float, captioned: bool = true) -> void:
	if id.is_empty():
		return
	var payload := IDENTITIES.avatar_payload(id)
	var texture := IDENTITIES.avatar_texture(id)
	if payload.is_empty() or texture == null:
		return
	var inset := maxf(5.0, width * 0.07)
	var height := width * CARD_ASPECT if captioned else width
	var card := Rect2(-width * 0.5, -height * 0.5, width, height)
	var photo := Rect2(card.position + Vector2.ONE * inset, Vector2.ONE * (width - inset * 2.0))
	item.draw_set_transform(center, angle)
	SKIN.draw_plate(item, card, SKIN.CREAM, 6 if width < 80.0 else 8)
	item.draw_rect(photo, Color(String(payload["palette"]["accent"])).darkened(0.1))
	item.draw_texture_rect(texture, photo, false)
	item.draw_rect(photo, SKIN.INK, false, 2.0)
	if captioned:
		var caption_size := clampi(roundi(width * 0.1), 11, 20)
		var caption_y := photo.end.y + (card.end.y - photo.end.y) * 0.5 + caption_size * 0.36
		SKIN.draw_text(item, Vector2(card.position.x, caption_y), _first_name(id), caption_size, SKIN.INK, width, HORIZONTAL_ALIGNMENT_CENTER)
	SKIN.draw_tape(item, Vector2(0.0, card.position.y + 2.0), Vector2(width * 0.42, maxf(12.0, width * 0.12)))
	item.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func draw_room_stop(item: CanvasItem, center: Vector2, radius: float, room: String) -> void:
	SKIN.draw_disc(item, center, radius, room_color(room))
	item.draw_set_transform(center, 0.0, Vector2.ONE * radius / ROOM_ICON_RADIUS)
	_draw_room_icon(item, room)
	item.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func draw_road(item: CanvasItem, points: PackedVector2Array, width: float) -> void:
	item.draw_polyline(points, SKIN.INK, width + SKIN.LINE * 2.0, true)
	item.draw_polyline(points, SKIN.ASPHALT, width, true)
	for index in range(0, points.size() - 1, 2):
		item.draw_line(points[index], points[index + 1], Color(SKIN.CREAM, 0.7), 2.5, true)


static func smooth_path(points: Array[Vector2], samples: int) -> PackedVector2Array:
	var path := PackedVector2Array()
	for index in points.size() - 1:
		var before := points[maxi(0, index - 1)]
		var start := points[index]
		var end := points[index + 1]
		var after := points[mini(points.size() - 1, index + 2)]
		for step in samples:
			path.append(start.cubic_interpolate(end, before, after, float(step) / float(samples)))
	path.append(points[-1])
	return path


## The rival who fronts an act. A generated roster answers first, using the same
## per-act slot the duel itself takes, so the map shows the driver you actually face.
static func act_rival(act_number: int) -> String:
	var installed := DriverDirectory.installed_ids()
	if not installed.is_empty():
		return installed[(maxi(1, act_number) - 1) % installed.size()]
	for event: Dictionary in CATALOG.EVENTS:
		var opponents: Array = event.get("opponents", [])
		if int(event.get("act", 0)) == act_number and not opponents.is_empty():
			return String(opponents[0])
	return ""


static func room_color(room: String) -> Color:
	match room:
		"kitchen":
			return SKIN.ORANGE
		"workshop":
			return SKIN.YELLOW
		"office":
			return SKIN.BLUE
	return SKIN.LIME


func _draw() -> void:
	if size.x < 80.0 or size.y < 120.0:
		return
	match mode:
		&"vehicle":
			_draw_vehicle_stage()
		&"briefing":
			_draw_briefing_stage()
		&"map":
			_draw_map_stage()
		&"settings":
			_draw_mechanic_stage()
		&"driver":
			_draw_driver_stage()
		&"credits":
			_draw_cast_stage()
		&"ending":
			_draw_ending_stage()
		_:
			_draw_title_stage()


func _draw_title_stage() -> void:
	var mat := Rect2(10.0, 10.0, size.x - 20.0, size.y - 20.0)
	SKIN.draw_plate(self, mat, SKIN.CREAM, 18)
	SKIN.draw_tape(self, mat.position + Vector2(78.0, 6.0), Vector2(128.0, 26.0), -0.35)
	_draw_mug(mat.position + Vector2(mat.size.x - 78.0, mat.size.y * 0.62))
	draw_car(self, mat.position + mat.size * Vector2(0.56, 0.42), mat.size.y * 0.48, vehicle_id, -0.42)
	draw_portrait_card(self, mat.position + Vector2(mat.size.x * 0.2, mat.size.y * 0.22), minf(mat.size.x * 0.3, 176.0), driver_id, -0.08)
	if not secondary_driver_id.is_empty():
		draw_portrait_card(self, mat.position + Vector2(mat.size.x * 0.84, mat.size.y * 0.58), minf(mat.size.x * 0.24, 140.0), secondary_driver_id, 0.08)
	_draw_roster(Rect2(mat.position.x + 16.0, mat.end.y - mat.size.y * 0.2, mat.size.x - 32.0, mat.size.y * 0.17), CATALOG.championship_vehicle_ids())


## Moves the garage shape to a new car; the caller animates shape_blend to 1.
func show_shape(next_shape: Dictionary, next_compare: Dictionary, next_compare_label: String) -> void:
	_shape_from = _blended_shape() if not shape.is_empty() else next_shape
	shape = next_shape
	compare_shape = next_compare
	compare_label = next_compare_label
	shape_blend = 0.0


func _blended_shape() -> Dictionary:
	var out := {}
	for axis: String in CarProfile.AXES:
		out[axis] = lerpf(float(_shape_from.get(axis, 0.0)), float(shape.get(axis, 0.0)), shape_blend)
	return out


func _draw_vehicle_stage() -> void:
	var table_radius := minf(size.x * 0.27, size.y * 0.44)
	var table_center := Vector2(size.x * 0.29, size.y * 0.5)
	_draw_turntable(table_center, table_radius)
	draw_car(self, table_center, table_radius * 1.45, vehicle_id, -0.35)
	var card_height := minf(size.y * 0.8, SHAPE_CARD_MAX_HEIGHT)
	_draw_shape_card(Rect2(size.x * 0.6, (size.y - card_height) * 0.5, size.x * 0.38, card_height))


func _draw_briefing_stage() -> void:
	var player := secondary_driver_id if not secondary_driver_id.is_empty() else "rae"
	var card_width := minf(size.x * 0.3, 160.0)
	var card_y := size.y * 0.24
	draw_portrait_card(self, Vector2(size.x * 0.27, card_y), card_width, player, -0.07)
	draw_portrait_card(self, Vector2(size.x * 0.73, card_y), card_width, driver_id, 0.07)
	var badge := Vector2(size.x * 0.5, card_y + 12.0)
	SKIN.draw_disc(self, badge, 26.0, SKIN.ORANGE)
	SKIN.draw_text(self, badge + Vector2(-30.0, 8.0), "VS", 22, SKIN.CREAM, 60.0, HORIZONTAL_ALIGNMENT_CENTER)
	var car_length := minf(size.y * 0.2, 130.0)
	var rival_vehicle := String(CATALOG.get_driver(driver_id).get("vehicle_id", vehicle_id))
	draw_car(self, Vector2(size.x * 0.27, size.y * 0.57), car_length, vehicle_id, -0.14)
	draw_car(self, Vector2(size.x * 0.73, size.y * 0.57), car_length, rival_vehicle, 0.14)
	_draw_track_card(Rect2(size.x * 0.08, size.y * 0.73, size.x * 0.84, size.y * 0.21), theme_id)


func _draw_map_stage() -> void:
	var board := Rect2(size.x * 0.05, size.y * 0.04, size.x * 0.88, size.y * 0.88)
	draw_map_board(self, board)
	var acts: Array = CATALOG.ACTS
	var stops: Array[Vector2] = []
	for index in acts.size():
		var progress := float(index) / float(maxi(1, acts.size() - 1))
		stops.append(board.position + board.size * Vector2(0.3 if index % 2 == 0 else 0.7, 0.2 + 0.6 * progress))
	var route: Array[Vector2] = [Vector2(stops[0].x, board.position.y + 20.0)]
	route.append_array(stops)
	route.append(Vector2(stops[-1].x + board.size.x * 0.3, board.end.y - 20.0))
	draw_road(self, smooth_path(route, 14), 20.0)
	for index in acts.size():
		var act: Dictionary = acts[index]
		var room := String(act["id"])
		var stop := stops[index]
		var active := room == theme_id
		if active:
			draw_arc(stop, 46.0, 0.0, TAU, 40, SKIN.ORANGE, 6.0, true)
		draw_room_stop(self, stop, ROOM_ICON_RADIUS, room)
		var on_left := index % 2 == 0
		var tag_width := board.size.x * 0.38
		var tag_x := stop.x + 50.0 if on_left else stop.x - 50.0 - tag_width
		SKIN.draw_tag(self, Rect2(tag_x, stop.y - 16.0, tag_width, 30.0), String(act["name"]).to_upper(), SKIN.YELLOW if active else SKIN.CREAM, 13)
		var rival := act_rival(int(act["number"]))
		if not rival.is_empty():
			draw_portrait_card(self, Vector2(tag_x + tag_width * (0.8 if on_left else 0.2), stop.y + 58.0), 54.0, rival, 0.08 if on_left else -0.08, false)
		if active:
			draw_car(self, stop + Vector2(-58.0 if on_left else 58.0, 30.0), 64.0, vehicle_id, 0.5 if on_left else -0.5)


func _draw_mechanic_stage() -> void:
	var mat := Rect2(12.0, 12.0, size.x - 24.0, size.y - 24.0)
	SKIN.draw_plate(self, mat, SKIN.CREAM, 16)
	draw_car(self, mat.position + mat.size * Vector2(0.52, 0.74), minf(mat.size.y * 0.32, 190.0), vehicle_id, 1.4)
	_draw_gear(self, mat.position + mat.size * Vector2(0.16, 0.62), minf(mat.size.x * 0.1, 52.0), SKIN.BLUE)
	_draw_gear(self, mat.position + mat.size * Vector2(0.26, 0.78), minf(mat.size.x * 0.06, 34.0), SKIN.YELLOW)
	_draw_wrench(mat.position + mat.size * Vector2(0.84, 0.62), minf(mat.size.y / 420.0, 1.5))
	draw_portrait_card(self, mat.position + mat.size * Vector2(0.5, 0.28), minf(mat.size.x * 0.42, 220.0), driver_id, -0.05)


func _draw_driver_stage() -> void:
	var mat := Rect2(12.0, 12.0, size.x - 24.0, size.y - 24.0)
	SKIN.draw_plate(self, mat, SKIN.CREAM, 16)
	SKIN.draw_tape(self, mat.position + Vector2(mat.size.x * 0.5 - 64.0, 4.0), Vector2(128.0, 26.0), 0.28)
	draw_portrait_card(self, mat.position + mat.size * Vector2(0.5, 0.46), minf(mat.size.x * 0.44, 260.0), driver_id, -0.04)
	_draw_roster(Rect2(mat.position.x + 16.0, mat.end.y - mat.size.y * 0.18, mat.size.x - 32.0, mat.size.y * 0.15), CATALOG.quick_race_vehicle_ids())


func _draw_cast_stage() -> void:
	var cast: Array = CATALOG.CAST
	var columns := 3
	var rows := ceili(float(cast.size()) / float(columns))
	var cell := Vector2(size.x / float(columns), size.y * 0.9 / float(rows))
	var card_width := minf(cell.x * 0.72, cell.y / CARD_ASPECT * 0.86)
	for index in cast.size():
		var column := index % columns
		var row := floori(float(index) / float(columns))
		var center := Vector2(cell.x * (column + 0.5), size.y * 0.05 + cell.y * (row + 0.5))
		draw_portrait_card(self, center, card_width, String(cast[index]["id"]), (-0.07 if (index % 2 == 0) else 0.06))


func _draw_ending_stage() -> void:
	_draw_confetti()
	var champion := secondary_driver_id if not secondary_driver_id.is_empty() else "cass"
	draw_portrait_card(self, size * Vector2(0.25, 0.23), minf(size.x * 0.26, 140.0), driver_id, -0.08)
	draw_portrait_card(self, size * Vector2(0.75, 0.23), minf(size.x * 0.26, 140.0), champion, 0.08)
	_draw_trophy(size * Vector2(0.52, 0.64), minf(size.y / 460.0, 1.5))
	draw_car(self, size * Vector2(0.16, 0.8), minf(size.y * 0.18, 110.0), vehicle_id, -0.35)


func _draw_mug(center: Vector2) -> void:
	var body := Rect2(center + Vector2(-26.0, -16.0), Vector2(52.0, 44.0))
	SKIN.draw_plate(self, body, SKIN.CREAM, 8, 3.0)
	draw_rect(Rect2(body.position + Vector2(7.0, 7.0), Vector2(body.size.x - 14.0, 10.0)), SKIN.WOOD_DEEP)
	draw_arc(center + Vector2(30.0, 6.0), 12.0, -0.7, 0.7, 10, SKIN.INK, 4.0, true)
	draw_line(center + Vector2(-40.0, 18.0), center + Vector2(8.0, 28.0), SKIN.INK, 4.0, true)


func _draw_roster(rect: Rect2, ids: Array[String]) -> void:
	if ids.is_empty():
		return
	var bay_width := rect.size.x / float(ids.size())
	var length := minf(rect.size.y * 0.82, bay_width * 1.1)
	var line_color := Color(SKIN.INK, 0.35)
	for index in ids.size() + 1:
		var x := rect.position.x + bay_width * index
		draw_line(Vector2(x, rect.position.y + 4.0), Vector2(x, rect.end.y - 4.0), line_color, 3.0)
	draw_line(Vector2(rect.position.x, rect.end.y - 4.0), Vector2(rect.end.x, rect.end.y - 4.0), line_color, 3.0)
	for index in ids.size():
		var id := ids[index]
		var center := Vector2(rect.position.x + bay_width * (index + 0.5), rect.position.y + rect.size.y * 0.48)
		if id == vehicle_id:
			draw_rect(Rect2(rect.position.x + bay_width * index + 6.0, rect.end.y - 10.0, bay_width - 12.0, 6.0), SKIN.ORANGE)
		draw_car(self, center, length, id, 0.0, not id in unlocked_vehicle_ids)


func _draw_turntable(center: Vector2, radius: float) -> void:
	SKIN.draw_disc(self, center, radius, SKIN.CREAM)
	draw_arc(center, radius - 10.0, 0.0, TAU, 64, Color(SKIN.INK, 0.25), 2.0, true)
	draw_arc(center, radius * 0.55, 0.0, TAU, 48, Color(SKIN.INK, 0.12), 2.0, true)
	for tick in 36:
		var direction := Vector2.from_angle(TAU * float(tick) / 36.0)
		var inner := radius - (22.0 if tick % 3 == 0 else 16.0)
		draw_line(center + direction * inner, center + direction * (radius - 10.0), Color(SKIN.INK, 0.35), 2.0)
	draw_line(center + Vector2(-radius + 12.0, 0.0), center + Vector2(radius - 12.0, 0.0), Color(SKIN.BLUE, 0.2), 2.0)
	draw_line(center + Vector2(0.0, -radius + 12.0), center + Vector2(0.0, radius - 12.0), Color(SKIN.BLUE, 0.2), 2.0)
	draw_arc(center, radius + SKIN.LINE + 5.0, -PI * 0.9, -PI * 0.35, 24, SKIN.ORANGE, 6.0, true)
	draw_arc(center, radius + SKIN.LINE + 5.0, PI * 0.1, PI * 0.65, 24, SKIN.ORANGE, 6.0, true)


func _draw_shape_card(rect: Rect2) -> void:
	SKIN.draw_plate(self, rect, SKIN.CREAM)
	var tape_center := Vector2(rect.get_center().x, rect.position.y + 4.0)
	SKIN.draw_tape(self, tape_center, Vector2(rect.size.x * 0.66, 24.0), -0.03)
	SKIN.draw_text(self, Vector2(rect.position.x, tape_center.y + 5.0), compare_label, 13, SKIN.INK, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	if shape.is_empty():
		return
	var center := rect.get_center() + Vector2(0.0, 12.0)
	var radius := minf(rect.size.x, rect.size.y) * SHAPE_RADIUS_RATIO
	for ring in range(1, SHAPE_RINGS + 1):
		var ring_points := _shape_points(center, radius * float(ring) / float(SHAPE_RINGS), {}, 1.0)
		ring_points.append(ring_points[0])
		draw_polyline(ring_points, Color(SKIN.INK, 0.12), 1.0, true)
	for corner: Vector2 in _shape_points(center, radius, {}, 1.0):
		draw_line(center, corner, Color(SKIN.INK, 0.12), 1.0, true)
	var shown := _blended_shape()
	var points := _shape_points(center, radius, shown)
	draw_colored_polygon(points, Color(SKIN.ORANGE, 0.82))
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, SKIN.INK, 2.0, true)
	for point: Vector2 in points:
		draw_circle(point, 3.5, SKIN.INK)
		draw_circle(point, 2.0, SKIN.YELLOW)
	if not compare_shape.is_empty():
		var compared := _shape_points(center, radius, compare_shape)
		for index in compared.size():
			draw_dashed_line(compared[index], compared[(index + 1) % compared.size()], SKIN.BLUE, 2.5, SHAPE_DASH, true)
	var label_points := _shape_points(center, radius + 22.0, {}, 1.0)
	for index in CarProfile.AXES.size():
		var axis := CarProfile.AXES[index]
		var at := label_points[index]
		SKIN.draw_text(self, at + Vector2(-40.0, 4.0), axis.to_upper(), 12, SKIN.INK, 80.0, HORIZONTAL_ALIGNMENT_CENTER, false)
		if compare_shape.is_empty():
			continue
		var delta := roundi((float(shape.get(axis, 0.0)) - float(compare_shape.get(axis, 0.0))) * 100.0)
		if delta != 0:
			SKIN.draw_text(self, at + Vector2(-40.0, 18.0), "%+d" % delta, 12, SKIN.LIME if delta > 0 else SKIN.RED, 80.0, HORIZONTAL_ALIGNMENT_CENTER, false)


## Hexagon corners clockwise from the top; each axis value pushes its corner out.
func _shape_points(center: Vector2, radius: float, values: Dictionary, fixed: float = -1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in CarProfile.AXES.size():
		var reach := fixed if fixed >= 0.0 else lerpf(SHAPE_FLOOR, 1.0, float(values.get(CarProfile.AXES[index], 0.0)))
		points.append(center + Vector2.from_angle(-PI * 0.5 + TAU * float(index) / float(CarProfile.AXES.size())) * radius * reach)
	return points


func _draw_track_card(rect: Rect2, room: String) -> void:
	SKIN.draw_plate(self, rect, SKIN.CREAM)
	var loop := rect.grow(-22.0)
	loop.size.x -= SKIN.SHADOW
	loop.size.y -= SKIN.SHADOW
	var corner := roundi(loop.size.y * 0.5)
	draw_style_box(_ring(SKIN.INK, 20, corner + 3), loop.grow(3.0))
	draw_style_box(_ring(SKIN.ASPHALT, 14, corner), loop)
	draw_style_box(_ring(Color(SKIN.CREAM, 0.5), 2, corner - 6), loop.grow(-6.0))
	SKIN.draw_flag(self, Rect2(loop.get_center().x - 7.0, loop.end.y - 15.0, 14.0, 16.0), 4.0)
	SKIN.draw_tag(self, Rect2(loop.get_center().x - 60.0, loop.get_center().y - 14.0, 120.0, 28.0), room.to_upper(), room_color(room), 13)


static func _draw_room_icon(item: CanvasItem, room: String) -> void:
	match room:
		"kitchen":
			item.draw_arc(Vector2(15.0, 0.0), 8.0, -PI * 0.5, PI * 0.5, 12, SKIN.INK, 7.0, true)
			item.draw_arc(Vector2(15.0, 0.0), 8.0, -PI * 0.5, PI * 0.5, 12, SKIN.CREAM, 3.0, true)
			SKIN.draw_disc(item, Vector2.ZERO, 14.0, SKIN.CREAM, 0.0)
			item.draw_circle(Vector2.ZERO, 9.0, SKIN.WOOD_DEEP)
		"workshop":
			_draw_gear(item, Vector2.ZERO, 17.0, SKIN.CREAM)
		_:
			var note := Rect2(-14.0, -14.0, 28.0, 28.0)
			SKIN.draw_plate(item, note, SKIN.CREAM, 3, 0.0)
			item.draw_line(note.position + Vector2(7.0, 11.0), note.position + Vector2(21.0, 11.0), SKIN.INK, 2.0)
			item.draw_line(note.position + Vector2(7.0, 18.0), note.position + Vector2(17.0, 18.0), SKIN.INK, 2.0)


static func _draw_gear(item: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	var teeth := 8
	var points := PackedVector2Array()
	for index in teeth * 4:
		var angle := TAU * float(index) / float(teeth * 4)
		points.append(center + Vector2.from_angle(angle) * (radius if index % 4 < 2 else radius * 0.76))
	var outline := points.duplicate()
	outline.append(points[0])
	item.draw_colored_polygon(points, color)
	item.draw_polyline(outline, SKIN.INK, SKIN.LINE, true)
	SKIN.draw_disc(item, center, radius * 0.28, SKIN.WOOD_DEEP, 0.0)


func _draw_wrench(center: Vector2, scale_factor: float) -> void:
	draw_set_transform(center, -0.6, Vector2.ONE * scale_factor)
	for pass_index in 2:
		var grow := SKIN.LINE if pass_index == 0 else 0.0
		var color := SKIN.INK if pass_index == 0 else SKIN.BLUE.lightened(0.2)
		draw_rect(Rect2(-9.0 - grow, -58.0, 18.0 + grow * 2.0, 116.0), color)
		draw_arc(Vector2(0.0, -64.0), 20.0, 0.5, 2.64, 20, color, 14.0 + grow * 2.0, true)
		draw_circle(Vector2(0.0, 62.0), 17.0 + grow, color)
	draw_circle(Vector2(0.0, 62.0), 7.0, SKIN.INK)
	draw_line(Vector2(0.0, -40.0), Vector2(0.0, 40.0), Color(SKIN.CREAM, 0.45), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_trophy(center: Vector2, scale_factor: float) -> void:
	draw_set_transform(center, 0.0, Vector2.ONE * scale_factor)
	SKIN.draw_plate(self, Rect2(-62.0, 64.0, 124.0, 44.0), SKIN.WOOD)
	SKIN.draw_text(self, Vector2(-62.0, 96.0), "1", 26, SKIN.YELLOW, 124.0, HORIZONTAL_ALIGNMENT_CENTER)
	var cup := PackedVector2Array([Vector2(-44, -62), Vector2(44, -62), Vector2(32, 4), Vector2(12, 24), Vector2(-12, 24), Vector2(-32, 4)])
	for pass_index in 2:
		var grow := SKIN.LINE if pass_index == 0 else 0.0
		var color := SKIN.INK if pass_index == 0 else SKIN.YELLOW
		draw_arc(Vector2(-44, -34), 24.0, PI * 0.5, PI * 1.5, 18, color, 9.0 + grow * 2.0, true)
		draw_arc(Vector2(44, -34), 24.0, -PI * 0.5, PI * 0.5, 18, color, 9.0 + grow * 2.0, true)
		draw_rect(Rect2(-9.0 - grow, 20.0, 18.0 + grow * 2.0, 30.0), color)
		draw_rect(Rect2(-34.0 - grow, 46.0 - grow, 68.0 + grow * 2.0, 18.0 + grow * 2.0), color)
	var outline := cup.duplicate()
	outline.append(cup[0])
	draw_colored_polygon(cup, SKIN.YELLOW)
	draw_polyline(outline, SKIN.INK, SKIN.LINE, true)
	draw_line(Vector2(-26, -48), Vector2(-18, 0), Color(SKIN.CREAM, 0.8), 5.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_confetti() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = CONFETTI_SEED
	var colors: Array[Color] = [SKIN.ORANGE, SKIN.YELLOW, SKIN.LIME, SKIN.BLUE, SKIN.CREAM, SKIN.RED]
	for index in CONFETTI_PIECES:
		var center := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		draw_set_transform(center, rng.randf() * TAU)
		draw_rect(Rect2(-5.0, -2.5, 10.0, 5.0), colors[index % colors.size()])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ring(color: Color, width: int, radius: int) -> StyleBoxFlat:
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = color
	ring.set_border_width_all(width)
	ring.set_corner_radius_all(maxi(0, radius))
	ring.anti_aliasing = true
	return ring


static func _first_name(id: String) -> String:
	return String(CATALOG.get_driver(id).get("name", id)).get_slice(" ", 0).to_upper()
