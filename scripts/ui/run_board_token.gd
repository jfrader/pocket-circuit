extends Control

const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")
const SHADOW := Color(0.025, 0.035, 0.06, 0.65)
const ART_SCALE := 1.24
const CAR_PAD := Rect2(-25, -33, 50, 66)
const CAR_ANGLE := -0.35
const PAD_OPACITY := 0.18
var kind := "race"
var selected := false
var reduced_motion := false
var car_look: Dictionary = {}
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
	draw_set_transform(center + Vector2(2, 3), 0, Vector2(1.0 - lift * 0.025, 0.48) * ART_SCALE)
	draw_texture_rect(MATERIALS.SHADOW_CIRCLE, Rect2(-22, -22, 44, 44), false, Color(SHADOW, 0.4))
	draw_texture_rect(MATERIALS.SHADOW_STRIP, Rect2(-16, 5, 32, 9), false, Color(SHADOW, 0.4))
	draw_set_transform(center - Vector2(0, lift), 0, Vector2.ONE * ART_SCALE)
	match kind:
		"race", "rival", "act_rival":
			if not car_look.is_empty():
				draw_set_transform(center - Vector2(0, lift), CAR_ANGLE)
				draw_texture_rect(car_look["texture"], Rect2(-24, -32, 48, 64), false)
		"bench":
			draw_set_transform(center - Vector2(0, lift), -0.6, Vector2.ONE * ART_SCALE)
			draw_rect(Rect2(-4, -25, 8, 37), Color("dce5de"))
			SKIN.draw_plate(self, Rect2(-9, 0, 18, 25), Color("e47741"), 4, 0)
			draw_line(Vector2(-2, 4), Vector2(-2, 19), Color("ffb471"), 2)
		"parts_van":
			for x: float in [-15.0, 15.0]:
				for y: float in [-10.0, 12.0]:
					draw_rect(Rect2(x - 3, y - 4, 6, 8), SKIN.INK)
			SKIN.draw_plate(self, Rect2(-16, -22, 32, 44), Color("d1ae62"), 5, 0)
			draw_rect(Rect2(-12, -16, 24, 11), Color("344e5d"))
			draw_rect(Rect2(-13, -2, 26, 18), Color("eee3bd"))
			draw_circle(Vector2(7, 6), 5, Color("537475"))
			draw_line(Vector2(0, 0), Vector2(0, 19), Color("8d713d"), 2)
		"lockup":
			draw_arc(Vector2(0, -9), 11, PI, TAU, 24, Color("c4c9c4"), 6, true)
			SKIN.draw_plate(self, Rect2(-17, -8, 34, 30), Color("d9ac53"), 4, 0)
			draw_circle(Vector2(0, 4), 4, SKIN.INK)
			draw_line(Vector2(0, 4), Vector2(0, 14), SKIN.INK, 3)
		"errand":
			SKIN.draw_plate(self, Rect2(-21, -15, 42, 32), SKIN.CREAM, 2, 0)
			draw_polyline(PackedVector2Array([Vector2(-21, -15), Vector2(0, 3), Vector2(21, -15)]), Color("ae9470"), 2, true)
			draw_circle(Vector2(0, 3), 4, SKIN.RED)
	draw_set_transform(Vector2.ZERO)
	if selected:
		draw_arc(center, 25, 0, TAU, 48, SKIN.YELLOW, 2, true)


static func draw_place(item: CanvasItem, center: Vector2, stop_kind: String, scale_factor: float) -> void:
	var car_place := stop_kind in ["race", "rival", "act_rival"]
	item.draw_set_transform(center if car_place else center + Vector2(0, 5), CAR_ANGLE if car_place else 0.0, Vector2.ONE * scale_factor)
	var pad := CAR_PAD if car_place else Rect2(-29, -17, 58, 34)
	var fills := {"race": Color("64796a"), "rival": Color("8b6a50"), "act_rival": Color("a08756"), "bench": Color("526e68"), "parts_van": Color("8b8465"), "lockup": Color("67736c"), "errand": Color("a89c7b")}
	item.draw_texture_rect(MATERIALS.SHADOW_RECT, pad.grow(3), false, Color(fills.get(stop_kind, SKIN.CREAM), PAD_OPACITY))
	if stop_kind == "act_rival":
		item.draw_arc(Vector2.ZERO, 34, 0, TAU, 40, Color(SKIN.CREAM, 0.14), 1, true)
	MATERIALS.grain(item, pad)
	if stop_kind in ["race", "rival"]:
		for side: float in [-1, 1]:
			item.draw_line(Vector2(side * 23, 24), Vector2(side * 23, 31), Color(SKIN.CREAM, PAD_OPACITY), 1, true)
	elif stop_kind in ["bench", "parts_van", "lockup"]:
		for stripe in 3:
			item.draw_line(Vector2(-26 + stripe * 7, 15), Vector2(-20 + stripe * 7, 8), Color(SKIN.YELLOW, PAD_OPACITY), 1, true)
	else:
		item.draw_line(Vector2(-23, 11), Vector2(22, 11), Color(SKIN.INK, 0.1), 1, true)
	item.draw_set_transform(Vector2.ZERO)
