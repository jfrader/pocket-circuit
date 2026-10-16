extends Control

signal dismissed

const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const UI := preload("res://scripts/ui/run_ui.gd")
const NOTE_RECT := Rect2(40, 568, 320, 70)
const COPY := "MOUSE CLICK / A / ENTER: PICK A STOP\nPRESS AGAIN OR GO TO DRIVE\nSURVIVE THE NIGHT"
const MOTION_THRESHOLD := 0.5
const EDGE_MARGIN := 8.0
var reduced_motion := false
var anchor_position := NOTE_RECT.position
var _dismissed := false
var _initial_focus: Control


func _ready() -> void:
	position = anchor_position
	size = NOTE_RECT.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	var copy := UI.label(COPY, 12, SKIN.INK, true)
	copy.name = "RunIntroCopy"
	copy.position = Vector2(12, 9)
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(copy)
	_initial_focus = get_viewport().gui_get_focus_owner()
	get_viewport().gui_focus_changed.connect(_focus_changed)
	if not reduced_motion:
		modulate.a = 0.0
		create_tween().tween_property(self, "modulate:a", 1.0, 0.18)


func _draw() -> void:
	MATERIALS.shadow(self, Rect2(Vector2(-5, 1), size + Vector2(14, 12)), false, 0.4)
	draw_rect(Rect2(Vector2(2, 3), size), Color("bdae89"))
	draw_rect(Rect2(Vector2.ZERO, size), Color("eee1be"))
	draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2), Color(SKIN.INK, 0.3), false, 1)
	MATERIALS.grain(self, Rect2(Vector2(4, 4), size - Vector2(8, 8)))
	SKIN.draw_tape(self, Vector2(size.x - 30, 0), Vector2(42, 12), -0.08, Color("d9bd78"))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		dismiss()
	elif event is InputEventKey and event.pressed and not event.echo:
		dismiss()
	elif event is InputEventJoypadButton and event.pressed:
		dismiss()
	elif event is InputEventJoypadMotion and absf(event.axis_value) > MOTION_THRESHOLD:
		dismiss()
	elif event is InputEventAction and event.pressed:
		dismiss()


func _focus_changed(control: Control) -> void:
	if control != _initial_focus:
		dismiss()


func dismiss() -> void:
	if _dismissed:
		return
	_dismissed = true
	hide()
	dismissed.emit()
	queue_free()
