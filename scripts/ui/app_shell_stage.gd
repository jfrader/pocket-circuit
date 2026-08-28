class_name AppShellStage
extends Control

const CATALOG := preload("res://data/championship/catalog.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")

const INK := Color("101827")
const PANEL := Color("1b2940")
const PAPER := Color("f2ead7")
const CREAM := Color("fff8e8")
const AMBER := Color("f4bf3a")
const CORAL := Color("e96b4c")
const BLUE := Color("55a8c9")
const MUTED := Color("92a2b8")

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
	_draw_stage_frame()
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


func _draw_stage_frame() -> void:
	var frame := Rect2(Vector2(8.0, 8.0), size - Vector2(16.0, 16.0))
	_draw_panel(frame, Color("142137"), Color("394c68"), 18, 2)
	for y in range(38, int(size.y) - 24, 26):
		draw_line(Vector2(20.0, float(y)), Vector2(size.x - 20.0, float(y)), Color(0.55, 0.68, 0.84, 0.035), 1.0)
	_draw_panel(Rect2(24.0, 22.0, minf(188.0, size.x - 48.0), 28.0), AMBER, AMBER, 4)
	_draw_text("GHC / AFTER HOURS", Vector2(34.0, 43.0), 13, INK)
	for bolt_position: Vector2 in [Vector2(26.0, size.y - 28.0), Vector2(size.x - 26.0, size.y - 28.0)]:
		draw_circle(bolt_position, 8.0, Color("75849a"))
		draw_line(bolt_position - Vector2(4.0, 0.0), bolt_position + Vector2(4.0, 0.0), INK, 2.0)
		draw_line(bolt_position - Vector2(0.0, 4.0), bolt_position + Vector2(0.0, 4.0), INK, 2.0)


func _draw_title_stage() -> void:
	_draw_text("BAY 04", Vector2(26.0, 82.0), 18, CREAM)
	_draw_text("THE GRID OPENS AT MIDNIGHT", Vector2(26.0, 103.0), 11, MUTED)
	_draw_track_loop(Vector2(size.x * 0.5, size.y * 0.57), Vector2(size.x * 0.41, size.y * 0.3), Color(BLUE, 0.22))
	_draw_portrait(Vector2(size.x - 86.0, 152.0), 58.0, "rae")
	_draw_vehicle(Vector2(size.x * 0.48, size.y * 0.59), 1.42, "rustbug", -0.12)
	_draw_tape_label(Rect2(30.0, size.y - 112.0, size.x - 60.0, 52.0), "RAE + RUSTBUG", "ROOKIE ENTRY / ALL-ROUND SETUP")


func _draw_vehicle_stage() -> void:
	var vehicle := CATALOG.get_vehicle(vehicle_id)
	var accent := Color.from_string(String(vehicle.get("tint", "f4bf3a")), AMBER)
	_draw_text(String(vehicle.get("name", "RUSTBUG")).to_upper(), Vector2(26.0, 84.0), 24, CREAM)
	_draw_text(String(vehicle.get("archetype", "BALANCED")).to_upper() + " MACHINE", Vector2(26.0, 106.0), 12, accent)
	_draw_portrait(Vector2(size.x - 64.0, 92.0), 34.0, driver_id)
	_draw_track_loop(Vector2(size.x * 0.5, 215.0), Vector2(size.x * 0.38, 112.0), Color(accent, 0.17))
	_draw_vehicle(Vector2(size.x * 0.5, 215.0), 1.15, vehicle_id, -0.1)
	_draw_vehicle_stats(vehicle, Vector2(30.0, 335.0), size.x - 60.0)
	_draw_text("THE FOUR MACHINES", Vector2(28.0, size.y - 116.0), 12, MUTED)
	_draw_vehicle_roster(Vector2(38.0, size.y - 72.0), size.x - 76.0)


func _draw_briefing_stage() -> void:
	var rival := driver_id if not driver_id.is_empty() else "juniper"
	var player := secondary_driver_id if not secondary_driver_id.is_empty() else "rae"
	_draw_text(theme_id.to_upper() + " / GRID CALL", Vector2(26.0, 84.0), 15, AMBER)
	_draw_portrait(Vector2(size.x * 0.31, 190.0), 74.0, player)
	_draw_portrait(Vector2(size.x * 0.69, 190.0), 74.0, rival)
	_draw_text(String(CATALOG.get_driver(player).get("name", "RAE")).to_upper(), Vector2(22.0, 292.0), 13, CREAM, size.x * 0.43, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text(String(CATALOG.get_driver(rival).get("name", "RIVAL")).to_upper(), Vector2(size.x * 0.55, 292.0), 13, CREAM, size.x * 0.43, HORIZONTAL_ALIGNMENT_CENTER)
	draw_line(Vector2(size.x * 0.43, 190.0), Vector2(size.x * 0.57, 190.0), CORAL, 4.0)
	_draw_track_loop(Vector2(size.x * 0.5, 405.0), Vector2(size.x * 0.38, 78.0), Color(BLUE, 0.42))
	_draw_text("READ THE ROOM. HOLD THE LINE.", Vector2(24.0, 510.0), 13, PAPER, size.x - 48.0, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_map_stage() -> void:
	_draw_text("HOUSEHOLD ROUTE", Vector2(26.0, 84.0), 18, CREAM)
	var rooms := [
		{"id": "kitchen", "name": "01  KITCHEN", "color": CORAL},
		{"id": "workshop", "name": "02  WORKSHOP", "color": AMBER},
		{"id": "office", "name": "03  OFFICE", "color": BLUE},
	]
	for index in rooms.size():
		var room: Dictionary = rooms[index]
		var room_rect := Rect2(26.0, 112.0 + index * 132.0, size.x - 52.0, 106.0)
		var room_color: Color = room["color"]
		_draw_panel(room_rect, Color(room_color, 0.1), Color(room_color, 0.62), 10, 2)
		_draw_text(String(room["name"]), room_rect.position + Vector2(16.0, 27.0), 15, CREAM)
		_draw_text("3 EVENTS / NIGHT CIRCUIT", room_rect.position + Vector2(16.0, 51.0), 11, MUTED)
		_draw_mini_room_icon(room_rect.position + Vector2(room_rect.size.x - 64.0, 53.0), String(room["id"]), room_color)
		if index < rooms.size() - 1:
			draw_line(Vector2(size.x * 0.5, room_rect.end.y), Vector2(size.x * 0.5, room_rect.end.y + 26.0), Color(PAPER, 0.34), 3.0)
	_draw_text("COUNTER  >  BENCH  >  DESK", Vector2(24.0, size.y - 62.0), 12, AMBER, size.x - 48.0, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_mechanic_stage() -> void:
	_draw_text("SPANNER'S BENCH", Vector2(26.0, 84.0), 18, CREAM)
	_draw_portrait(Vector2(size.x * 0.5, 205.0), 104.0, "inez")
	_draw_gear(Vector2(78.0, 365.0), 38.0, BLUE)
	_draw_wrench(Vector2(size.x - 84.0, 365.0), 0.9, AMBER)
	_draw_tape_label(Rect2(34.0, 424.0, size.x - 68.0, 72.0), "INEZ 'SPANNER' SOLIS", "TUNE THE FEEL, NOT THE REWARD")


func _draw_cast_stage() -> void:
	_draw_text("THE MIDNIGHT GRID", Vector2(26.0, 84.0), 18, CREAM)
	var cast_ids := ["rae", "inez", "juniper", "milo", "tess", "cass"]
	for index in cast_ids.size():
		var column := index % 2
		var row := floori(float(index) / 2.0)
		var center := Vector2(size.x * (0.3 if column == 0 else 0.7), 143.0 + row * 122.0)
		_draw_portrait(center, 43.0, cast_ids[index])
		_draw_text(String(CATALOG.get_driver(cast_ids[index]).get("name", "DRIVER")).to_upper(), center + Vector2(-72.0, 65.0), 10, PAPER, 144.0, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_text("ORIGINAL DRIVERS / ORIGINAL MACHINES", Vector2(24.0, size.y - 54.0), 11, AMBER, size.x - 48.0, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_ending_stage() -> void:
	_draw_text("SUNRISE / FINAL GRID", Vector2(26.0, 84.0), 18, CREAM)
	_draw_portrait(Vector2(size.x * 0.31, 190.0), 76.0, "rae")
	_draw_portrait(Vector2(size.x * 0.69, 190.0), 76.0, "cass")
	_draw_trophy(Vector2(size.x * 0.5, 370.0), 1.15)
	_draw_text("THE CIRCUIT STAYS OPEN", Vector2(24.0, 500.0), 16, AMBER, size.x - 48.0, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_vehicle_stats(vehicle: Dictionary, origin: Vector2, width: float) -> void:
	var stats: Dictionary = vehicle.get("stats", {})
	var entries := [
		{"label": "SPEED", "value": clampf(float(stats.get("max_speed", 640.0)) / 720.0, 0.0, 1.0)},
		{"label": "GRIP", "value": clampf(float(stats.get("grip", 0.8)), 0.0, 1.0)},
		{"label": "MASS", "value": clampf(float(stats.get("mass", 0.8)) / 1.2, 0.0, 1.0)},
		{"label": "DRIFT", "value": clampf(float(stats.get("drift_factor", 0.25)) / 0.42, 0.0, 1.0)},
	]
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var y := origin.y + index * 26.0
		_draw_text(String(entry["label"]), Vector2(origin.x, y + 11.0), 10, MUTED)
		var bar_rect := Rect2(origin.x + 58.0, y, width - 58.0, 12.0)
		draw_rect(bar_rect, Color("0c1422"))
		draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * float(entry["value"]), bar_rect.size.y)), AMBER if index != 1 else BLUE)


func _draw_vehicle_roster(origin: Vector2, width: float) -> void:
	var ids := ["rustbug", "pinbolt", "scrapjaw", "flicker"]
	var spacing := width / float(ids.size())
	for index in ids.size():
		var roster_id: String = ids[index]
		var center := origin + Vector2(spacing * (float(index) + 0.5), 0.0)
		if roster_id == vehicle_id:
			draw_circle(center, 28.0, Color(AMBER, 0.2))
			draw_arc(center, 28.0, 0.0, TAU, 32, AMBER, 2.0, true)
		_draw_vehicle(center, 0.29, roster_id)
		if not roster_id in unlocked_vehicle_ids:
			draw_rect(Rect2(center + Vector2(12.0, 8.0), Vector2(12.0, 10.0)), INK)
			draw_arc(center + Vector2(18.0, 8.0), 5.0, PI, TAU, 12, MUTED, 2.0, true)
			draw_rect(Rect2(center + Vector2(13.0, 8.0), Vector2(10.0, 9.0)), MUTED)


func _draw_vehicle(center: Vector2, scale_factor: float, id: String, angle: float = 0.0) -> void:
	var texture := IDENTITIES.car_texture(id)
	if texture == null:
		return
	var draw_size := Vector2(48.0, 64.0) * 2.15 * scale_factor
	draw_set_transform(center, angle)
	draw_texture_rect(texture, Rect2(-draw_size * 0.5, draw_size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_portrait(center: Vector2, radius: float, id: String) -> void:
	var payload := IDENTITIES.avatar_payload(id)
	var texture := IDENTITIES.avatar_texture(id)
	if payload.is_empty() or texture == null:
		return
	var accent := Color(String(payload["palette"]["accent"]))
	draw_circle(center, radius + 8.0, Color(accent, 0.18))
	var draw_size := Vector2.ONE * radius * 2.0
	draw_texture_rect(texture, Rect2(center - draw_size * 0.5, draw_size), false)
	draw_arc(center, radius + 8.0, -2.8, 2.8, 40, accent, 4.0, true)


func _draw_track_loop(center: Vector2, radii: Vector2, color: Color) -> void:
	var outer := _ellipse_points(center, radii, 48)
	var inner := _ellipse_points(center, radii - Vector2(24.0, 20.0), 48)
	draw_polyline(outer, color, 8.0, true)
	draw_polyline(inner, Color(PAPER, color.a * 0.45), 2.0, true)
	for angle in [0.4, 2.2, 3.8, 5.4]:
		var point := center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y)
		draw_circle(point, 5.0, AMBER)


func _ellipse_points(center: Vector2, radii: Vector2, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in segments + 1:
		var angle := TAU * float(index) / float(segments)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points


func _draw_mini_room_icon(center: Vector2, room: String, color: Color) -> void:
	draw_circle(center, 34.0, Color(color, 0.17))
	draw_arc(center, 34.0, 0.0, TAU, 28, color, 3.0, true)
	match room:
		"kitchen":
			draw_circle(center, 17.0, PAPER)
			draw_circle(center, 11.0, Color("6d3b2f"))
			draw_arc(center + Vector2(18.0, 0.0), 10.0, -PI * 0.5, PI * 0.5, 12, PAPER, 5.0, true)
		"workshop":
			_draw_gear(center, 18.0, color)
		_:
			for offset in [Vector2(-13, -11), Vector2(7, -11), Vector2(-13, 9), Vector2(7, 9)]:
				draw_rect(Rect2(center + offset, Vector2(12.0, 12.0)), PAPER)


func _draw_gear(center: Vector2, radius: float, color: Color) -> void:
	draw_circle(center, radius, color)
	draw_circle(center, radius * 0.45, INK)
	for index in 8:
		var direction := Vector2.RIGHT.rotated(TAU * float(index) / 8.0)
		draw_rect(Rect2(center + direction * radius - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), color)


func _draw_wrench(center: Vector2, scale_factor: float, color: Color = PAPER) -> void:
	draw_set_transform(center, -0.6, Vector2.ONE * scale_factor)
	draw_rect(Rect2(-5.0, -35.0, 10.0, 70.0), color)
	draw_arc(Vector2(0.0, -37.0), 13.0, 0.55, 2.6, 18, color, 7.0, true)
	draw_circle(Vector2(0.0, 38.0), 10.0, color)
	draw_circle(Vector2(0.0, 38.0), 4.0, INK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_trophy(center: Vector2, scale_factor: float) -> void:
	draw_set_transform(center, 0.0, Vector2.ONE * scale_factor)
	draw_colored_polygon(PackedVector2Array([Vector2(-38, -55), Vector2(38, -55), Vector2(28, 5), Vector2(12, 24), Vector2(-12, 24), Vector2(-28, 5)]), AMBER)
	draw_arc(Vector2(-38, -30), 24.0, PI * 0.5, PI * 1.5, 18, AMBER, 8.0, true)
	draw_arc(Vector2(38, -30), 24.0, -PI * 0.5, PI * 0.5, 18, AMBER, 8.0, true)
	draw_rect(Rect2(-8.0, 22.0, 16.0, 34.0), AMBER)
	draw_rect(Rect2(-32.0, 54.0, 64.0, 12.0), PAPER)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_tape_label(rect: Rect2, title: String, subtitle: String) -> void:
	_draw_panel(rect, Color("f2ead7"), Color("d2c7ae"), 4)
	draw_line(rect.position + Vector2(8.0, 7.0), rect.position + Vector2(rect.size.x - 8.0, 7.0), Color(INK, 0.15), 2.0)
	_draw_text(title, rect.position + Vector2(12.0, 24.0), 14, INK)
	_draw_text(subtitle, rect.position + Vector2(12.0, 42.0), 10, Color("4c5666"))


func _draw_panel(rect: Rect2, fill: Color, border: Color, radius: int, border_width: int = 1) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	draw_style_box(box, rect)


func _draw_text(
		text: String,
		text_position: Vector2,
		font_size: int,
		color: Color,
		width: float = -1.0,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> void:
	draw_string(ThemeDB.fallback_font, text_position, text, alignment, width, font_size, color)
