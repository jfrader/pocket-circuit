extends Control

signal dismissed

const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const UI := preload("res://scripts/ui/run_ui.gd")
const NOTE_RECT := Rect2(40, 568, 320, 70)
const COPY := "MOUSE CLICK / A / ENTER: PICK A STOP\nPRESS AGAIN OR GO TO DRIVE\nSURVIVE THE NIGHT"
const DRIVING_COPY := "W / UP / RT: ACCELERATE · S / DOWN / LT: BRAKE\nA / D / LEFT / RIGHT / LEFT STICK: STEER\nSPACE / A: DRIFT TO CHARGE BOOST\nSHIFT / B: BOOST ON THE STRAIGHT\nR / Y TO RECOVER\nESC / START TO PAUSE"
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
	_draw_slip(Rect2(Vector2.ZERO, size))


func _draw_slip(rect: Rect2) -> void:
	MATERIALS.shadow(self, Rect2(rect.position + Vector2(-5, 1), rect.size + Vector2(14, 12)), false, 0.4)
	draw_rect(Rect2(rect.position + Vector2(2, 3), rect.size), Color("bdae89"))
	draw_rect(rect, Color("eee1be"))
	draw_rect(rect.grow(-1), Color(SKIN.INK, 0.3), false, 1)
	MATERIALS.grain(self, rect.grow(-4))
	SKIN.draw_tape(self, rect.position + Vector2(rect.size.x - 30, 0), Vector2(42, 12), -0.08, Color("d9bd78"))


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


static func build_driving_screen(static_motion: bool) -> ControlsScreen:
	var screen := ControlsScreen.new()
	screen.reduced_motion = static_motion
	return screen


class ControlsScreen extends Control:
	signal ready_to_race
	signal back_requested

	const PAPER_SIZE := Vector2(832, 480)
	var reduced_motion := false
	var _paper := Rect2()
	var _finished := false
	var _copy: Label
	var _heading: Label
	var _ready_button: Button
	var _back_button: Button


	func _ready() -> void:
		name = "RunDrivingIntro"
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		_heading = UI.label("BEFORE YOU RACE", 32, SKIN.INK, true)
		add_child(_heading)
		_copy = UI.label(DRIVING_COPY, 18, SKIN.INK, true)
		_copy.name = "RunDrivingCopy"
		_copy.add_theme_constant_override("line_spacing", 12)
		add_child(_copy)
		_ready_button = Button.new()
		_ready_button.name = "DrivingReady"
		_ready_button.text = "READY"
		SKIN.apply_button(_ready_button, true)
		_ready_button.pressed.connect(_accept)
		add_child(_ready_button)
		_back_button = Button.new()
		_back_button.name = "DrivingBack"
		_back_button.text = "BACK"
		_back_button.focus_mode = Control.FOCUS_NONE
		SKIN.apply_button(_back_button, false)
		_back_button.pressed.connect(cancel)
		add_child(_back_button)
		resized.connect(_layout)
		_layout()
		_ready_button.grab_focus()
		if not reduced_motion:
			modulate.a = 0.0
			create_tween().tween_property(self, "modulate:a", 1.0, 0.18)


	func _layout() -> void:
		_paper = Rect2((size - PAPER_SIZE) * 0.5, PAPER_SIZE)
		_heading.position = _paper.position + Vector2(40, 32)
		_copy.position = _paper.position + Vector2(40, 108)
		_ready_button.position = _paper.end - Vector2(232, 84)
		_ready_button.size = Vector2(192, 52)
		_back_button.position = Vector2(_paper.position.x + 40, _paper.end.y - 84)
		_back_button.size = Vector2(160, 52)
		queue_redraw()


	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("213b33"))
		MATERIALS.grain(self, Rect2(Vector2.ZERO, size))
		MATERIALS.shadow(self, _paper.grow(10), false, 0.5)
		draw_rect(Rect2(_paper.position + Vector2(3, 4), _paper.size), Color("bdae89"))
		draw_rect(_paper, Color("eee1be"))
		draw_rect(_paper.grow(-2), Color(SKIN.INK, 0.3), false, 1)
		MATERIALS.grain(self, _paper.grow(-4))
		SKIN.draw_tape(self, _paper.position + Vector2(100, 0), Vector2(100, 24), -0.08, Color("d9bd78"))
		SKIN.draw_tape(self, Vector2(_paper.end.x - 100, _paper.position.y), Vector2(100, 24), 0.06, Color("d9bd78"))


	func _input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			cancel()
		elif event.is_action_pressed("ui_accept") and not event.is_echo():
			get_viewport().set_input_as_handled()
			_accept()


	func _accept() -> void:
		if _finished:
			return
		_finished = true
		ready_to_race.emit()


	func cancel() -> void:
		if _finished:
			return
		_finished = true
		back_requested.emit()
