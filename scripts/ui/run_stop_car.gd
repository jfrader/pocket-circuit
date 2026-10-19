extends Control

## A small paper card in the stop slip holding the car a race-type stop puts
## against you: the field leader, the rival, or your own car when the stop has
## no field assigned.

const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")
## Narrow enough to sit beside "Act rival" inside the 264px slip.
const CARD_SIZE := Vector2(84, 60)
## Sized so the widest generated body, wheels included, stays on the card.
const CAR_LENGTH := 72.0
const CAR_ANGLE := PI * 0.5 - 0.18
var look: Dictionary = {}


func _init(car_look: Dictionary = {}) -> void:
	look = car_look
	name = "StopCar"
	custom_minimum_size = CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	set_meta("vehicle_id", String(look.get("key", "")))
	set_meta("source", String(look.get("source", "")))


func texture() -> Texture2D:
	return look.get("texture") as Texture2D


func _draw() -> void:
	var card := Rect2(Vector2.ZERO, size)
	MATERIALS.shadow(self, Rect2(card.position + Vector2(-2, 1), card.size + Vector2(7, 8)), false, 0.55)
	draw_rect(card, Color("ded3b6"))
	draw_rect(card, Color(SKIN.INK, 0.45), false, 1)
	MATERIALS.grain(self, card.grow(-3))
	if texture() == null:
		return
	var center := card.get_center()
	var car := Vector2(CAR_LENGTH * 0.75, CAR_LENGTH)
	draw_set_transform(center + Vector2(2, 3), CAR_ANGLE, Vector2(0.92, 0.8))
	draw_texture_rect(MATERIALS.SHADOW_CIRCLE, Rect2(-car * 0.36, car * 0.72), false, Color(MATERIALS.SHADOW_TINT, 0.45))
	draw_set_transform(center, CAR_ANGLE)
	draw_texture_rect(texture(), Rect2(-car * 0.5, car), false)
	draw_set_transform(Vector2.ZERO)
