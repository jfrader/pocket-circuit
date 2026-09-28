extends Button

const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const FLAG_CELL := 5.0
const FLAG_CELLS := 4
const FEEDBACK_WIDTH := 112.0

var reduced_motion := false
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var feedback := 0.0:
	set(value):
		feedback = value
		queue_redraw()
var _primary := false
var _hovered := false
var _feedback_tween: Tween


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	focus_entered.connect(_update_feedback)
	focus_exited.connect(_update_feedback)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)


func set_art_role(primary: bool) -> void:
	_primary = primary
	queue_redraw()


func _on_hover(hovered: bool) -> void:
	_hovered = hovered
	_update_feedback()


func _update_feedback() -> void:
	if _feedback_tween and _feedback_tween.is_valid():
		_feedback_tween.kill()
	var target := 0.0 if disabled else (1.0 if _hovered else (0.35 if has_focus() else 0.0))
	var app := get_node_or_null("/root/App")
	if reduced_motion or (app != null and bool(app.get("reduced_motion"))):
		feedback = target
		return
	_feedback_tween = create_tween()
	_feedback_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_feedback_tween.tween_property(self, "feedback", target, 0.12)


func _draw() -> void:
	var push := Vector2.ONE * (SKIN.PRESS if is_pressed() else 0.0)
	var plate := Rect2(push, size - Vector2.ONE * SKIN.SHADOW)
	if _primary and icon == null and size.x >= 180:
		var flag_size := FLAG_CELL * FLAG_CELLS
		var flag_origin := plate.position + Vector2(17.0, floorf((plate.size.y - flag_size) * 0.5))
		SKIN.draw_flag(self, Rect2(flag_origin, Vector2.ONE * flag_size), FLAG_CELL, Color(SKIN.INK, 0.4 if disabled else 1.0))
	if selected and not disabled:
		SKIN.draw_checker(self, Rect2(plate.position + Vector2(10.0, 6.0), Vector2(plate.size.x - 20.0, FLAG_CELL)), FLAG_CELL, SKIN.INK, SKIN.YELLOW)
		SKIN.draw_disc(self, plate.position + Vector2(plate.size.x - 4.0, 4.0), 9.0, SKIN.ORANGE, 2.0)
		var tick := plate.position + Vector2(plate.size.x - 4.0, 4.0)
		draw_polyline(PackedVector2Array([tick + Vector2(-4.5, 0.0), tick + Vector2(-1.0, 3.5), tick + Vector2(4.5, -3.5)]), SKIN.CREAM, 2.5, true)
	if disabled and icon != null:
		SKIN.draw_padlock(self, plate.position + Vector2(plate.size.x - 16.0, 18.0))
	if not disabled and feedback > 0.01:
		var length := maxf(0.0, minf(FEEDBACK_WIDTH, plate.size.x - 32.0)) * feedback
		var baseline := plate.position + Vector2(16.0, plate.size.y - 7.0)
		draw_line(baseline, baseline + Vector2(length, 0.0), SKIN.INK if _primary else SKIN.ORANGE, 3.0, true)


func _exit_tree() -> void:
	if _feedback_tween and _feedback_tween.is_valid():
		_feedback_tween.kill()
