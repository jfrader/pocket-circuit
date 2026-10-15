extends Control

const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const STAGE := preload("res://scripts/ui/app_shell_stage.gd")
const SHADOW := Color(0.025, 0.035, 0.06, 0.65)
const ART_SCALE := 1.24
var kind := "race"
var selected := false
var reduced_motion := false
var lift := 0.0:
	set(value):
		lift = value
		queue_redraw()
var _lift_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_selected(value: bool) -> void:
	selected = value
	if _lift_tween != null:
		_lift_tween.kill()
	if reduced_motion:
		lift = 0.0
	else:
		_lift_tween = create_tween().set_trans(Tween.TRANS_SINE)
		_lift_tween.tween_property(self, "lift", 3.0 if value else 0.0, 0.16)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	draw_set_transform(center + Vector2(4, 7), 0, Vector2(1.0 - lift * 0.025, 0.48) * ART_SCALE)
	for blur in range(3, 0, -1):
		draw_circle(Vector2.ZERO, 15 + blur * 2, Color(SHADOW, 0.16))
	draw_set_transform(center - Vector2(0, lift), 0, Vector2.ONE * ART_SCALE)
	match kind:
		"race", "rival", "act_rival":
			STAGE.draw_car(self, center - Vector2(0, lift), 53, "rustbug" if kind == "race" else "pinbolt", -0.35)
		"bench":
			draw_set_transform(center - Vector2(0, lift), -0.6, Vector2.ONE * ART_SCALE)
			draw_rect(Rect2(-4, -25, 8, 37), Color("dce5de"))
			SKIN.draw_plate(self, Rect2(-9, 0, 18, 25), Color("e47741"), 4, 2)
			draw_line(Vector2(-2, 4), Vector2(-2, 19), Color("ffb471"), 2)
		"parts_van":
			for x: float in [-15.0, 15.0]:
				for y: float in [-10.0, 12.0]:
					draw_rect(Rect2(x - 3, y - 4, 6, 8), SKIN.INK)
			SKIN.draw_plate(self, Rect2(-16, -22, 32, 44), Color("d1ae62"), 5, 2)
			draw_rect(Rect2(-12, -16, 24, 11), Color("344e5d"))
			draw_rect(Rect2(-13, -2, 26, 18), Color("eee3bd"))
			draw_circle(Vector2(7, 6), 5, Color("537475"))
			draw_line(Vector2(0, 0), Vector2(0, 19), Color("8d713d"), 2)
		"lockup":
			draw_arc(Vector2(0, -9), 11, PI, TAU, 24, Color("c4c9c4"), 6, true)
			SKIN.draw_plate(self, Rect2(-17, -8, 34, 30), Color("d9ac53"), 4, 3)
			draw_circle(Vector2(0, 4), 4, SKIN.INK)
			draw_line(Vector2(0, 4), Vector2(0, 14), SKIN.INK, 3)
		"errand":
			SKIN.draw_plate(self, Rect2(-21, -15, 42, 32), SKIN.CREAM, 2, 3)
			draw_polyline(PackedVector2Array([Vector2(-21, -15), Vector2(0, 3), Vector2(21, -15)]), Color("ae9470"), 2, true)
			draw_circle(Vector2(0, 3), 4, SKIN.RED)
	draw_set_transform(Vector2.ZERO)
	if selected:
		draw_arc(center, 25, 0, TAU, 48, SKIN.YELLOW, 2, true)
