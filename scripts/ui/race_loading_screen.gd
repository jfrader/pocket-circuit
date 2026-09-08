extends CanvasLayer

signal cancel_requested

const BACKDROP := preload("res://assets/ui/imagine/motorsport_loading.jpg")
const BUTTON_SCRIPT := preload("res://scripts/ui/motorsport_button.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")

class PreparationStrip extends Control:
	var section := 0
	var pulse := 1.0

	func _draw() -> void:
		var labels := ["LOAD", "TRACK", "CARS", "GRID"]
		for index in 4:
			var point := Vector2(26 + index * 110, 12)
			if index < 3:
				draw_line(point, point + Vector2(110, 0), Color("546560"), 2)
			var color := Color("f4bf52") if index < section else Color("546560")
			if index == section:
				color = Color("71c9bc")
				draw_circle(point, 11, Color(color, pulse * 0.3))
			draw_circle(point, 5, color)
			draw_string(ThemeDB.fallback_font, point + Vector2(-23, 29), labels[index], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("fff2ce"))

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
var _strip: PreparationStrip


func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_started = Time.get_ticks_usec()
	_last_frame = _started
	_phase_started = _started
	var background := ColorRect.new()
	background.color = Color("101b21")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var artwork := TextureRect.new()
	artwork.texture = BACKDROP
	artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	artwork.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(artwork)
	var heading := Label.new()
	heading.text = "TO THE\nGRID"
	heading.position = Vector2(60, 86)
	heading.add_theme_font_size_override("font_size", 64)
	heading.add_theme_color_override("font_color", Color("f4bf52"))
	heading.add_theme_color_override("font_outline_color", Color("101b21"))
	heading.add_theme_constant_override("outline_size", 7)
	background.add_child(heading)
	var brand := Label.new()
	brand.text = "POCKET CIRCUIT / PIT LANE"
	brand.position = Vector2(64, 58)
	brand.add_theme_color_override("font_color", Color("71c9bc"))
	background.add_child(brand)
	var rail := ColorRect.new()
	rail.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	rail.offset_top = -122
	rail.color = Color(0.04, 0.075, 0.085, 0.94)
	background.add_child(rail)
	_strip = PreparationStrip.new()
	_strip.position = Vector2(60, 28)
	_strip.size = Vector2(400, 60)
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_child(_strip)
	_phase_label = Label.new()
	_phase_label.position = Vector2(490, 24)
	_phase_label.add_theme_font_size_override("font_size", 20)
	rail.add_child(_phase_label)
	_status_label = Label.new()
	_status_label.position = Vector2(490, 59)
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color("71c9bc"))
	rail.add_child(_status_label)
	var cancel := BUTTON_SCRIPT.new() as Button
	SKIN.apply_button(cancel, false)
	cancel.set("reduced_motion", reduced_motion)
	cancel.text = "BACK · ESC / B"
	cancel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	cancel.offset_left = -225
	cancel.offset_right = -32
	cancel.offset_top = -26
	cancel.offset_bottom = 26
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func(): cancel_requested.emit())
	rail.add_child(cancel)
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
	_strip.pulse = 0.8 if reduced_motion else 0.65 + sin(Time.get_ticks_msec() * 0.006) * 0.35
	_strip.queue_redraw()
	_update_copy()


func set_section(section: int) -> void:
	_strip.section = clampi(section, 0, 3)
	_strip.queue_redraw()


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
	_status_label.text = "Could not start. Use Back to return." if _failed else "THE COUNTDOWN STARTS WHEN EVERYTHING IS READY"
