class_name AppShellStage
extends Control

const CATALOG := preload("res://data/championship/catalog.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const CAR_ASPECT := 0.75
const CARD_ASPECT := 1.24
const STAT_KEYS: Array[String] = ["speed", "grip", "mass", "drift"]
const SPEC_CARD_MAX_HEIGHT := 300.0
const CONFETTI_SEED := 1278
const CONFETTI_PIECES := 46

var mode: StringName = &"title"
var vehicle_id := "rustbug"
var driver_id := "rae"
var secondary_driver_id := ""
var theme_id := "kitchen"
var unlocked_vehicle_ids: Array[String] = ["rustbug"]


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
		&"credits":
			_draw_cast_stage()
		&"ending":
			_draw_ending_stage()
		_:
			_draw_title_stage()


func _draw_title_stage() -> void:
	_draw_car(size * Vector2(0.54, 0.42), size.y * 0.42, vehicle_id, -0.42)
	_draw_portrait_card(size * Vector2(0.17, 0.2), minf(size.x * 0.22, 132.0), driver_id, -0.1)
	if not secondary_driver_id.is_empty():
		_draw_portrait_card(size * Vector2(0.87, 0.64), minf(size.x * 0.18, 108.0), secondary_driver_id, 0.09)
	_draw_roster(Rect2(size.x * 0.02, size.y * 0.8, size.x * 0.96, size.y * 0.19), CATALOG.championship_vehicle_ids())


func _draw_vehicle_stage() -> void:
	var table_radius := minf(size.x * 0.34, size.y * 0.46)
	var table_center := Vector2(size.x * 0.36, size.y * 0.5)
	_draw_turntable(table_center, table_radius)
	_draw_car(table_center, table_radius * 1.45, vehicle_id, -0.35)
	var card_height := minf(size.y * 0.76, SPEC_CARD_MAX_HEIGHT)
	_draw_spec_card(Rect2(size.x * 0.7, (size.y - card_height) * 0.5, size.x * 0.28, card_height), CATALOG.get_vehicle(vehicle_id))


func _draw_briefing_stage() -> void:
	var player := secondary_driver_id if not secondary_driver_id.is_empty() else "rae"
	var card_width := minf(size.x * 0.3, 160.0)
	var card_y := size.y * 0.24
	_draw_portrait_card(Vector2(size.x * 0.27, card_y), card_width, player, -0.07)
	_draw_portrait_card(Vector2(size.x * 0.73, card_y), card_width, driver_id, 0.07)
	var badge := Vector2(size.x * 0.5, card_y + 12.0)
	SKIN.draw_disc(self, badge, 26.0, SKIN.ORANGE)
	SKIN.draw_text(self, badge + Vector2(-30.0, 8.0), "VS", 22, SKIN.CREAM, 60.0, HORIZONTAL_ALIGNMENT_CENTER)
	var car_length := minf(size.y * 0.2, 130.0)
	var rival_vehicle := String(CATALOG.get_driver(driver_id).get("vehicle_id", vehicle_id))
	_draw_car(Vector2(size.x * 0.27, size.y * 0.57), car_length, vehicle_id, -0.14)
	_draw_car(Vector2(size.x * 0.73, size.y * 0.57), car_length, rival_vehicle, 0.14)
	_draw_track_card(Rect2(size.x * 0.08, size.y * 0.73, size.x * 0.84, size.y * 0.21), theme_id)


func _draw_map_stage() -> void:
	var board := Rect2(size.x * 0.05, size.y * 0.04, size.x * 0.88, size.y * 0.88)
	SKIN.draw_plate(self, board, SKIN.CREAM, 14)
	SKIN.draw_grid(self, board.grow(-14.0), 26.0)
	SKIN.draw_tape(self, board.position + Vector2(34.0, 6.0), Vector2(92.0, 22.0), -0.6)
	SKIN.draw_tape(self, Vector2(board.end.x - 34.0, board.position.y + 6.0), Vector2(92.0, 22.0), 0.6)
	var acts: Array = CATALOG.ACTS
	var stops: Array[Vector2] = []
	for index in acts.size():
		var progress := float(index) / float(maxi(1, acts.size() - 1))
		stops.append(board.position + board.size * Vector2(0.3 if index % 2 == 0 else 0.7, 0.2 + 0.6 * progress))
	var route: Array[Vector2] = [Vector2(stops[0].x, board.position.y + 20.0)]
	route.append_array(stops)
	route.append(Vector2(stops[-1].x + board.size.x * 0.3, board.end.y - 20.0))
	_draw_road(_smooth_path(route, 14), 20.0)
	for index in acts.size():
		var act: Dictionary = acts[index]
		var room := String(act["id"])
		var stop := stops[index]
		var active := room == theme_id
		if active:
			draw_arc(stop, 46.0, 0.0, TAU, 40, SKIN.ORANGE, 6.0, true)
		SKIN.draw_disc(self, stop, 32.0, _room_color(room))
		_draw_room_icon(stop, room)
		var on_left := index % 2 == 0
		var tag_width := board.size.x * 0.38
		var tag_x := stop.x + 50.0 if on_left else stop.x - 50.0 - tag_width
		SKIN.draw_tag(self, Rect2(tag_x, stop.y - 16.0, tag_width, 30.0), String(act["name"]).to_upper(), SKIN.YELLOW if active else SKIN.CREAM, 13)
		var rival := _act_rival(int(act["number"]))
		if not rival.is_empty():
			_draw_portrait_card(Vector2(tag_x + tag_width * (0.8 if on_left else 0.2), stop.y + 58.0), 54.0, rival, 0.08 if on_left else -0.08, false)
		if active:
			_draw_car(stop + Vector2(-58.0 if on_left else 58.0, 30.0), 64.0, vehicle_id, 0.5 if on_left else -0.5)


func _draw_mechanic_stage() -> void:
	_draw_car(size * Vector2(0.52, 0.74), minf(size.y * 0.26, 170.0), vehicle_id, 1.4)
	_draw_gear(size * Vector2(0.16, 0.62), minf(size.x * 0.08, 44.0), SKIN.BLUE)
	_draw_gear(size * Vector2(0.24, 0.78), minf(size.x * 0.05, 28.0), SKIN.YELLOW)
	_draw_wrench(size * Vector2(0.85, 0.6), minf(size.y / 520.0, 1.3))
	_draw_portrait_card(size * Vector2(0.5, 0.3), minf(size.x * 0.36, 196.0), driver_id, -0.05)


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
		_draw_portrait_card(center, card_width, String(cast[index]["id"]), (-0.07 if (index % 2 == 0) else 0.06))


func _draw_ending_stage() -> void:
	_draw_confetti()
	var champion := secondary_driver_id if not secondary_driver_id.is_empty() else "cass"
	_draw_portrait_card(size * Vector2(0.25, 0.23), minf(size.x * 0.26, 140.0), driver_id, -0.08)
	_draw_portrait_card(size * Vector2(0.75, 0.23), minf(size.x * 0.26, 140.0), champion, 0.08)
	_draw_trophy(size * Vector2(0.52, 0.64), minf(size.y / 460.0, 1.5))
	_draw_car(size * Vector2(0.16, 0.8), minf(size.y * 0.18, 110.0), vehicle_id, -0.35)


func _draw_car(center: Vector2, length: float, id: String, angle: float = 0.0, locked: bool = false) -> void:
	var texture := IDENTITIES.car_texture(id)
	if texture == null:
		return
	var car_size := Vector2(length * CAR_ASPECT, length)
	draw_set_transform(center, angle)
	draw_texture_rect(texture, Rect2(-car_size * 0.5, car_size), false, Color(SKIN.INK, 0.92) if locked else Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if locked:
		SKIN.draw_padlock(self, center, maxf(12.0, length * 0.24))


func _draw_portrait_card(center: Vector2, width: float, id: String, angle: float, captioned: bool = true) -> void:
	var payload := IDENTITIES.avatar_payload(id)
	var texture := IDENTITIES.avatar_texture(id)
	if payload.is_empty() or texture == null:
		return
	var inset := maxf(5.0, width * 0.07)
	var height := width * CARD_ASPECT if captioned else width
	var card := Rect2(-width * 0.5, -height * 0.5, width, height)
	var photo := Rect2(card.position + Vector2.ONE * inset, Vector2.ONE * (width - inset * 2.0))
	draw_set_transform(center, angle)
	SKIN.draw_plate(self, card, SKIN.CREAM, 6 if width < 80.0 else 8)
	draw_rect(photo, Color(String(payload["palette"]["accent"])).darkened(0.1))
	draw_texture_rect(texture, photo, false)
	draw_rect(photo, SKIN.INK, false, 2.0)
	if captioned:
		var caption_size := clampi(roundi(width * 0.1), 11, 20)
		var caption_y := photo.end.y + (card.end.y - photo.end.y) * 0.5 + caption_size * 0.36
		SKIN.draw_text(self, Vector2(card.position.x, caption_y), _first_name(id), caption_size, SKIN.INK, width, HORIZONTAL_ALIGNMENT_CENTER)
	SKIN.draw_tape(self, Vector2(0.0, card.position.y + 2.0), Vector2(width * 0.42, maxf(12.0, width * 0.12)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_roster(rect: Rect2, ids: Array[String]) -> void:
	if ids.is_empty():
		return
	var bay_width := rect.size.x / float(ids.size())
	var length := minf(rect.size.y * 0.82, bay_width * 1.1)
	var line_color := Color(SKIN.CREAM, 0.4)
	for index in ids.size() + 1:
		var x := rect.position.x + bay_width * index
		draw_line(Vector2(x, rect.position.y + 4.0), Vector2(x, rect.end.y - 4.0), line_color, 3.0)
	draw_line(Vector2(rect.position.x, rect.end.y - 4.0), Vector2(rect.end.x, rect.end.y - 4.0), line_color, 3.0)
	for index in ids.size():
		var id := ids[index]
		var center := Vector2(rect.position.x + bay_width * (index + 0.5), rect.position.y + rect.size.y * 0.48)
		if id == vehicle_id:
			draw_rect(Rect2(rect.position.x + bay_width * index + 6.0, rect.end.y - 10.0, bay_width - 12.0, 6.0), SKIN.ORANGE)
		_draw_car(center, length, id, 0.0, not id in unlocked_vehicle_ids)


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


func _draw_spec_card(rect: Rect2, vehicle: Dictionary) -> void:
	SKIN.draw_plate(self, rect, SKIN.CREAM)
	SKIN.draw_tape(self, Vector2(rect.get_center().x, rect.position.y + 2.0), Vector2(rect.size.x * 0.5, 20.0), -0.05)
	var ratings: Dictionary = vehicle.get("ratings", {})
	var row_height := (rect.size.y - 30.0) / float(STAT_KEYS.size())
	var tube_width := rect.size.x - 28.0 - SKIN.SHADOW
	for index in STAT_KEYS.size():
		var key := STAT_KEYS[index]
		var top := rect.position.y + 22.0 + row_height * index
		SKIN.draw_text(self, Vector2(rect.position.x + 15.0, top + 18.0), key.to_upper(), 14, SKIN.INK)
		SKIN.draw_tube(self, Rect2(rect.position.x + 14.0, top + 26.0, tube_width, 18.0), float(ratings.get(key, 0.0)), _stat_color(key), SKIN.CREAM)


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
	SKIN.draw_tag(self, Rect2(loop.get_center().x - 60.0, loop.get_center().y - 14.0, 120.0, 28.0), room.to_upper(), _room_color(room), 13)


func _draw_room_icon(center: Vector2, room: String) -> void:
	match room:
		"kitchen":
			draw_arc(center + Vector2(15.0, 0.0), 8.0, -PI * 0.5, PI * 0.5, 12, SKIN.INK, 7.0, true)
			draw_arc(center + Vector2(15.0, 0.0), 8.0, -PI * 0.5, PI * 0.5, 12, SKIN.CREAM, 3.0, true)
			SKIN.draw_disc(self, center, 14.0, SKIN.CREAM, 0.0)
			draw_circle(center, 9.0, SKIN.WOOD_DEEP)
		"workshop":
			_draw_gear(center, 17.0, SKIN.CREAM)
		_:
			var note := Rect2(center - Vector2(14.0, 14.0), Vector2(28.0, 28.0))
			SKIN.draw_plate(self, note, SKIN.CREAM, 3, 0.0)
			draw_line(note.position + Vector2(7.0, 11.0), note.position + Vector2(21.0, 11.0), SKIN.INK, 2.0)
			draw_line(note.position + Vector2(7.0, 18.0), note.position + Vector2(17.0, 18.0), SKIN.INK, 2.0)


func _draw_road(points: PackedVector2Array, width: float) -> void:
	draw_polyline(points, SKIN.INK, width + SKIN.LINE * 2.0, true)
	draw_polyline(points, SKIN.ASPHALT, width, true)
	for index in range(0, points.size() - 1, 2):
		draw_line(points[index], points[index + 1], Color(SKIN.CREAM, 0.7), 2.5, true)


func _draw_gear(center: Vector2, radius: float, color: Color) -> void:
	var teeth := 8
	var points := PackedVector2Array()
	for index in teeth * 4:
		var angle := TAU * float(index) / float(teeth * 4)
		points.append(center + Vector2.from_angle(angle) * (radius if index % 4 < 2 else radius * 0.76))
	var outline := points.duplicate()
	outline.append(points[0])
	draw_colored_polygon(points, color)
	draw_polyline(outline, SKIN.INK, SKIN.LINE, true)
	SKIN.draw_disc(self, center, radius * 0.28, SKIN.WOOD_DEEP, 0.0)


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


func _smooth_path(points: Array[Vector2], samples: int) -> PackedVector2Array:
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


func _ring(color: Color, width: int, radius: int) -> StyleBoxFlat:
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = color
	ring.set_border_width_all(width)
	ring.set_corner_radius_all(maxi(0, radius))
	ring.anti_aliasing = true
	return ring


func _act_rival(act_number: int) -> String:
	for event: Dictionary in CATALOG.EVENTS:
		var opponents: Array = event.get("opponents", [])
		if int(event.get("act", 0)) == act_number and not opponents.is_empty():
			return String(opponents[0])
	return ""


func _first_name(id: String) -> String:
	return String(CATALOG.get_driver(id).get("name", id)).get_slice(" ", 0).to_upper()


func _room_color(room: String) -> Color:
	match room:
		"kitchen":
			return SKIN.ORANGE
		"workshop":
			return SKIN.YELLOW
		"office":
			return SKIN.BLUE
	return SKIN.LIME


func _stat_color(key: String) -> Color:
	match key:
		"speed":
			return SKIN.ORANGE
		"grip":
			return SKIN.LIME
		"mass":
			return SKIN.BLUE
	return SKIN.YELLOW
