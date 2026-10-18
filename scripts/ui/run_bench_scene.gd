extends Control

const TABLETOP := preload("res://scripts/ui/run_board_scene.gd")
const PART_PROP := preload("res://scripts/ui/run_bench_part.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const REFERENCE_SIZE := Vector2(1280, 720)
const CAR_CENTER := Vector2(318, 421)
const CAR_LENGTH := 240.0
const CONFIRM_TIME := 0.32
const FADE_TIME := 0.18

var act := 1
var car_id := "rustbug"
var car_wear := "clean"
var held_parts: Array[Dictionary] = []
var reduced_motion := false
var confirmation_state: StringName = &"idle"
var stamp_depth := 0.0
var _car: TextureRect
var _moving_part: Control
var _mat: Control
var _car_shadow: TextureRect
var _wrench: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var table := TABLETOP.new()
	table.name = "BenchTabletop"
	table.act = act
	table.reduced_motion = reduced_motion
	table.ambient_motion = false
	table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(table)
	_mat = Control.new()
	_mat.name = "RepairMat"
	_mat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat.draw.connect(_draw_mat)
	add_child(_mat)
	_car_shadow = TextureRect.new()
	_car_shadow.name = "BenchCarShadow"
	_car_shadow.texture = MATERIALS.SHADOW_CIRCLE
	_car_shadow.modulate = MATERIALS.SHADOW_TINT
	_car_shadow.modulate.a = 0.4
	_car_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_car_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_car_shadow.rotation = -0.2
	add_child(_car_shadow)
	_car = TextureRect.new()
	_car.name = "BenchCar"
	_car.texture = IDENTITIES.car_texture_with_wear(car_id, car_wear, MATERIALS.HERO_PIXEL_SCALE, int(CAR_LENGTH))
	_car.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_car.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_car.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_car.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_car.rotation = -0.2
	add_child(_car)
	_wrench = TextureRect.new()
	_wrench.name = "PaintedWrench"
	_wrench.texture = MATERIALS.WRENCH
	_wrench.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wrench.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wrench.rotation = -1.05
	_wrench.modulate = Color("d4c7a5")
	add_child(_wrench)
	for index in mini(held_parts.size(), 3):
		var pack := PART_PROP.new()
		pack.name = "HeldBlister%d" % index
		pack.part_id = String(held_parts[index]["part"])
		pack.position = Vector2(101 + index * 60, 478)
		pack.size = Vector2(43, 56)
		pack.rotation = -0.12 + index * 0.13
		add_child(pack)
	_moving_part = PART_PROP.new()
	_moving_part.name = "FittingPart"
	_moving_part.size = Vector2(58, 76)
	_moving_part.hide()
	# The fitting pack passes under the car, not over its roof.
	add_child(_moving_part)
	move_child(_moving_part, _car.get_index())
	resized.connect(_layout)
	_layout()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, CONFIRM_TIME)


func _layout() -> void:
	var ratio := size / REFERENCE_SIZE
	_car.size = Vector2(CAR_LENGTH * 0.75, CAR_LENGTH) * ratio
	_car.pivot_offset = _car.size * 0.5
	_car.position = CAR_CENTER * ratio - _car.size * 0.5
	_car_shadow.size = _car.size * Vector2(1.25, 1.05)
	_car_shadow.pivot_offset = _car_shadow.size * 0.5
	_car_shadow.position = CAR_CENTER * ratio + Vector2(9, 14) - _car_shadow.size * 0.5
	_wrench.size = Vector2(250, 250) * ratio
	_wrench.pivot_offset = _wrench.size * 0.5
	_wrench.position = Vector2(475, 421) * ratio - _wrench.size * 0.5
	_mat.queue_redraw()


func _draw_mat() -> void:
	_mat.draw_set_transform(Vector2.ZERO, 0, size / REFERENCE_SIZE)
	var mat := Rect2(72, 302, 492, 246)
	MATERIALS.plate(_mat, mat, Color("294343"), 18)
	_mat.draw_texture_rect(MATERIALS.MAT_GRAIN, mat.grow(-8), false, Color(0.65, 0.75, 0.68, 0.16))
	MATERIALS.grain(_mat, mat.grow(-10))
	_mat.draw_rect(mat.grow(-12), Color("7c9990"), false, 2)
	for rib in 22:
		var x := mat.position.x + 25 + rib * 21
		_mat.draw_line(Vector2(x, mat.position.y + 20), Vector2(x, mat.end.y - 20), Color(0.02, 0.09, 0.1, 0.24), 2)
	_mat.draw_set_transform(CAR_CENTER + Vector2(9, 14), -0.2, Vector2(0.65, 1))
	for x: float in [-42.0, 42.0]:
		for y: float in [-54.0, 54.0]:
			MATERIALS.shadow(_mat, Rect2(Vector2(x, y) - Vector2(18, 10), Vector2(36, 20)), true, 0.75)
	_mat.draw_set_transform(Vector2.ZERO)
	_mat.draw_set_transform(Vector2(477, 424) * size / REFERENCE_SIZE, -1.05, size / REFERENCE_SIZE)
	MATERIALS.shadow(_mat, Rect2(-120, -40, 240, 80), false, 0.3)


func confirm(button: Button, kind: StringName, part_id: String = "") -> float:
	if confirmation_state != &"idle":
		return 0.0
	if reduced_motion:
		confirmation_state = &"crossfade"
		create_tween().tween_property(self, "modulate:a", 0.0, FADE_TIME)
		return FADE_TIME
	confirmation_state = kind
	button.pivot_offset = button.size * 0.5
	var style := button.get_theme_stylebox("disabled" if button.disabled else "normal") as StyleBoxFlat
	var stamp := create_tween().set_trans(Tween.TRANS_SINE)
	var press := func(depth: float) -> void:
		stamp_depth = depth
		button.scale = Vector2.ONE * lerpf(1.0, 0.97, depth)
		if style != null:
			style.shadow_offset = Vector2(4, lerpf(5.0, 2.0, depth))
	stamp.tween_method(press, 0.0, 1.0, CONFIRM_TIME * 0.4)
	stamp.tween_method(press, 1.0, 0.0, CONFIRM_TIME * 0.6)
	if kind == &"fit":
		_moving_part.set("part_id", part_id)
		var start := Vector2(130, 457)
		for index in mini(held_parts.size(), 3):
			if String(held_parts[index]["part"]) == part_id:
				var pack := get_node("HeldBlister%d" % index) as Control
				start = pack.position
				pack.hide()
				break
		_moving_part.position = start * size / REFERENCE_SIZE
		_moving_part.show()
		var slide := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		slide.tween_property(_moving_part, "position", CAR_CENTER * size / REFERENCE_SIZE - _moving_part.size * 0.5, CONFIRM_TIME)
	return CONFIRM_TIME


static func dress_button(button: Button, primary: bool = false) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = SKIN.YELLOW if primary else Color("eee3c6")
		style.border_color = SKIN.INK
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		style.set_content_margin_all(12)
		style.shadow_color = Color(0.01, 0.02, 0.04, 0.5)
		style.shadow_size = 3
		style.shadow_offset = Vector2(4, 5)
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = Color("fff8dc")
			style.set_border_width_all(3)
			style.shadow_size = 0
		if state == "hover" or state == "pressed":
			style.bg_color = style.bg_color.lightened(0.1)
		button.add_theme_stylebox_override(state, style)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		button.add_theme_color_override(state, SKIN.INK)
	if button.disabled:
		button.modulate.a = 0.6
	MATERIALS.finish_button(button)


static func dress_part(button: Button, part: Dictionary) -> void:
	dress_button(button)
	button.custom_minimum_size.y = 124
	var lines := button.get_child(0) as VBoxContainer
	lines.offset_left = 82
	lines.offset_right = -12
	for index in lines.get_child_count():
		var label := lines.get_child(index) as Label
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_override("font", ThemeDB.fallback_font)
		label.add_theme_font_size_override("font_size", 15 if index == 0 else 14)
		label.add_theme_color_override("font_color", SKIN.INK if index == 0 else Color("245342") if index == 1 else Color("8d322a"))
	var title := lines.get_child(0) as Label
	var price_at := title.text.find(" · ")
	if price_at >= 0:
		var printed := RichTextLabel.new()
		printed.name = "PrintedPrice"
		printed.fit_content = true
		printed.scroll_active = false
		printed.mouse_filter = Control.MOUSE_FILTER_IGNORE
		printed.add_theme_font_size_override("normal_font_size", 15)
		printed.add_theme_color_override("default_color", SKIN.INK)
		printed.push_font(ThemeDB.fallback_font)
		printed.add_text(title.text.substr(0, price_at))
		printed.pop()
		printed.push_font(preload("res://scripts/ui/run_ui.gd").mono_font())
		printed.add_text(title.text.substr(price_at))
		printed.pop()
		title.hide()
		lines.add_child(printed)
		lines.move_child(printed, 1)
	var blister := PART_PROP.new()
	blister.part_id = String(part["part"])
	blister.size = Vector2(54, 72)
	blister.position = Vector2(13, 24)
	button.add_child(blister)
