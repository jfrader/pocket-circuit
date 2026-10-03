extends CanvasLayer

signal cancel_requested

const BUTTON_SCRIPT := preload("res://scripts/ui/motorsport_button.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const STEPS: Array[String] = ["LOAD", "TRACK", "CARS", "GRID"]
const COLUMN_X := 72.0
const GRID_RECT := Rect2(660, 150, 520, 380)
const GRID_COLUMNS := 2
const GRID_STAGGER := 0.35
const CAR_LENGTH := 104.0
const CAR_ASPECT := 0.75

var reduced_motion := false
var phase := "Preparing your race"
var frames := 0
var max_frame_gap_ms := 0.0
var max_gap_phase := ""
var phase_times: Array[Dictionary] = []
var _phase_label: Label
var _status_label: Label
var _started := 0
var _last_frame := 0
var _phase_started := 0
var _failed := false
var _cancelled := false
var _grid: Control
var _section := 0
var _pulse := 1.0


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started = Time.get_ticks_usec()
	_last_frame = _started
	_phase_started = _started
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(SKIN.workbench_backdrop())
	var brand := SKIN.style_tape(Label.new(), SKIN.YELLOW, 14)
	brand.text = "POCKET CIRCUIT"
	brand.position = Vector2(COLUMN_X + 4.0, 64.0)
	root.add_child(brand)
	var heading := SKIN.style_label(Label.new(), 84, SKIN.CREAM, true)
	heading.text = "TO THE\nGRID"
	heading.position = Vector2(COLUMN_X - 4.0, 100.0)
	heading.add_theme_constant_override("line_spacing", -18)
	root.add_child(heading)
	_phase_label = SKIN.style_label(Label.new(), 24, SKIN.YELLOW, true)
	_phase_label.position = Vector2(COLUMN_X, 348.0)
	_phase_label.size = Vector2(520.0, 36.0)
	root.add_child(_phase_label)
	_status_label = SKIN.style_label(Label.new(), 15, SKIN.ORANGE, true)
	_status_label.position = Vector2(COLUMN_X, 392.0)
	_status_label.size = Vector2(520.0, 26.0)
	root.add_child(_status_label)
	_grid = Control.new()
	_grid.name = "StartingGrid"
	_grid.position = GRID_RECT.position
	_grid.size = GRID_RECT.size
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_grid.draw.connect(_draw_grid)
	root.add_child(_grid)
	var cancel := BUTTON_SCRIPT.new() as Button
	SKIN.apply_button(cancel, false)
	cancel.set("reduced_motion", reduced_motion)
	cancel.text = "BACK · ESC / B"
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.position = Vector2(COLUMN_X, 590.0)
	cancel.size = Vector2(240.0, 56.0)
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func(): cancel_requested.emit())
	root.add_child(cancel)
	_update_copy()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		cancel_requested.emit()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not visible:
		return
	var now := Time.get_ticks_usec()
	var gap := (now - _last_frame) / 1000.0
	if gap > max_frame_gap_ms:
		max_frame_gap_ms = gap
		max_gap_phase = phase
	_last_frame = now
	frames += 1
	_pulse = 0.8 if reduced_motion else 0.65 + sin(Time.get_ticks_msec() * 0.006) * 0.35
	_grid.queue_redraw()
	_update_copy()


func set_section(section: int) -> void:
	_section = clampi(section, 0, STEPS.size() - 1)
	_grid.queue_redraw()


func set_phase(next_phase: String) -> void:
	if next_phase == phase:
		return
	var now := Time.get_ticks_usec()
	phase_times.append({"phase": phase, "ms": (now - _phase_started) / 1000.0})
	_phase_started = now
	phase = next_phase
	_update_copy()


func cancel() -> void:
	_cancelled = true
	_update_copy()


func fail(message: String) -> void:
	_failed = true
	phase = message
	_update_copy()


func metrics() -> Dictionary:
	return {"frames": frames, "max_frame_gap_ms": max_frame_gap_ms, "max_gap_phase": max_gap_phase, "elapsed_ms": (Time.get_ticks_usec() - _started) / 1000.0, "phases": phase_times.duplicate(true)}


func _update_copy() -> void:
	if _phase_label == null:
		return
	_phase_label.text = "Cancelling safely" if _cancelled else phase
	_status_label.text = "COULD NOT START · ESC / B  BACK" if _failed else ""


func _draw_grid() -> void:
	var lane := Rect2(Vector2.ZERO, _grid.size - Vector2.ONE * SKIN.SHADOW)
	SKIN.draw_plate(_grid, lane, SKIN.ASPHALT, 18)
	SKIN.draw_flag(_grid, Rect2(lane.position + Vector2(18.0, 20.0), Vector2(lane.size.x - 36.0, 16.0)), 8.0)
	var roster := CATALOG.championship_vehicle_ids()
	var rows := ceilf(float(STEPS.size()) / float(GRID_COLUMNS))
	var slot_size := Vector2((lane.size.x - 36.0) / float(GRID_COLUMNS), (lane.size.y - 60.0) / (rows + GRID_STAGGER))
	for index in STEPS.size():
		var column := index % GRID_COLUMNS
		var row := floori(float(index) / float(GRID_COLUMNS))
		var slot := Rect2(Vector2(18.0 + slot_size.x * column, 48.0 + slot_size.y * (row + GRID_STAGGER * column)), slot_size)
		_draw_slot(slot.grow(-12.0), index, roster[index % roster.size()])


func _draw_slot(box: Rect2, index: int, vehicle_id: String) -> void:
	var bracket := PackedVector2Array([Vector2(box.position.x, box.end.y), box.position, Vector2(box.end.x, box.position.y), box.end])
	_grid.draw_polyline(bracket, Color(SKIN.CREAM, 0.7), 3.0, true)
	var done := index < _section
	var current := index == _section
	var tag := Rect2(box.position + Vector2(10.0, box.size.y * 0.5 - 14.0), Vector2(84.0, 28.0))
	SKIN.draw_tag(_grid, tag, STEPS[index], SKIN.YELLOW if done else (SKIN.ORANGE if current else SKIN.CREAM), 13)
	var car_size := Vector2(CAR_LENGTH * CAR_ASPECT, CAR_LENGTH)
	var car_center := Vector2(box.end.x - car_size.x * 0.5 - 16.0, box.get_center().y)
	if current:
		_grid.draw_circle(car_center, CAR_LENGTH * 0.5, Color(SKIN.ORANGE, _pulse * 0.25))
	var texture := IDENTITIES.car_texture(vehicle_id)
	if texture == null or not (done or current):
		return
	_grid.draw_texture_rect(texture, Rect2(car_center - car_size * 0.5, car_size), false, Color.WHITE if done else Color(1.0, 1.0, 1.0, 0.55))
