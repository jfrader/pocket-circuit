extends Button

const SKIN := preload("res://scripts/ui/motorsport_skin.gd")

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
	if selected and not disabled:
		draw_line(Vector2(14, 5), Vector2(size.x - 14, 5), SKIN.AMBER, 2)
	if _primary and icon == null and size.x >= 180:
		var origin := Vector2(17, floorf((size.y - 20) * 0.5))
		if is_pressed():
			origin.y += 2
		for row in 4:
			for column in 4:
				if (row + column) % 2 == 0:
					draw_rect(Rect2(origin + Vector2(column * 5, row * 5), Vector2(5, 5)), Color(SKIN.INK, 0.4 if disabled else 0.85))
	if not disabled and feedback > 0.01:
		var length := maxf(0, minf(112, size.x - 32)) * feedback
		draw_line(Vector2(16, size.y - 5), Vector2(16 + length, size.y - 5), SKIN.TEAL, 2)


func _exit_tree() -> void:
	if _feedback_tween and _feedback_tween.is_valid():
		_feedback_tween.kill()
