extends Control

const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")
var part_id := "short_gears"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0, size / Vector2(58, 76))
	MATERIALS.plate(self, Rect2(0, 0, 58, 76), Color("cfb985"), 3)
	draw_texture_rect(MATERIALS.CARDBOARD, Rect2(-6, -6, 70, 88), false, Color(0.9, 0.83, 0.62, 0.22))
	draw_rect(Rect2(5, 4, 48, 12), Color("486f6c"))
	draw_line(Vector2(22, 9), Vector2(36, 9), SKIN.INK, 3, true)
	var bubble := Rect2(6, 21, 46, 49)
	MATERIALS.shadow(self, bubble.grow(5), false, 0.5)
	SKIN.draw_plate(self, bubble, Color("d9ddd0"), 10, 0)
	var center := Vector2(29, 45)
	if part_id == "slick_tyres":
		for x: float in [-10.0, 10.0]:
			draw_circle(center + Vector2(x, 0), 10, SKIN.INK)
			draw_circle(center + Vector2(x, 0), 4, Color("a5b5b1"))
	elif part_id in ["short_gears", "long_gears", "drift_diff", "quick_rack"]:
		for tooth in 8:
			var direction := Vector2.from_angle(float(tooth) * TAU / 8)
			draw_line(center + direction * 8, center + direction * 15, Color("586f73"), 6, true)
		draw_circle(center, 11, Color("8d9e99"))
		draw_circle(center, 4, SKIN.INK)
	elif part_id in ["big_tank", "nitro_jets", "power_scoop"]:
		MATERIALS.plate(self, Rect2(center - Vector2(12, 15), Vector2(24, 30)), Color("b46c40"), 5)
		draw_rect(Rect2(center - Vector2(6, 18), Vector2(12, 6)), Color("667975"))
		draw_line(center - Vector2(7, 9), center + Vector2(-7, 9), Color("f5c18c"), 2)
	else:
		MATERIALS.plate(self, Rect2(center - Vector2(16, 11), Vector2(32, 22)), Color("657c79"), 3)
		for rib in 4:
			draw_line(center + Vector2(-11 + rib * 7, -8), center + Vector2(-11 + rib * 7, 8), Color("c9d3c9"), 2)
	draw_arc(center, 20, PI, PI * 1.55, 20, Color(1, 1, 0.9, 0.8), 2, true)
	draw_line(Vector2(13, 24), Vector2(43, 24), Color(1, 1, 0.94, 0.55), 1, true)
	draw_set_transform(center * size / Vector2(58, 76), -0.55, size / Vector2(58, 76))
	draw_texture_rect(MATERIALS.SHADOW_STRIP, Rect2(-20, -4, 40, 8), false, Color(1, 1, 0.96, 0.26))
