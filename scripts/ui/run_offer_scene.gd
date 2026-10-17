extends Control

const TABLETOP := preload("res://scripts/ui/run_board_scene.gd")
const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const CONTROLS := preload("res://scripts/ui/run_bench_scene.gd")
const REFERENCE_SIZE := Vector2(1280, 720)
const HERO_RECT := Rect2(748, 47, 204, 272)
const RIVAL_RECT := Rect2(1045, 132, 108, 144)
const TURNTABLE_CENTER := Vector2(850, 252)
const SHAPE_SIZE := Vector2(420, 300)
const SHAPE_BOTTOM_PADDING := 16.0
const REVEAL_SCALE := 0.4
const REVEAL_TURN := -0.6
const REVEAL_TIME := 0.4
const STAMP_TIME := 0.1

var act := 1
var car_id := ""
var rival_car_id := ""
var reduced_motion := false
var reveal_state: StringName = &"idle"
var _table: Control
var _lamp: Control
var _hero: TextureRect
var _rival: TextureRect
var _stamp: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var surface := TABLETOP.new()
	surface.name = "OfferTabletop"
	surface.act = act
	surface.reduced_motion = reduced_motion
	surface.ambient_motion = false
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(surface)
	_table = _painter("OfferTurntable", _draw_turntable)
	_rival = _car("OfferRivalCar", IDENTITIES.car_texture(rival_car_id))
	_rival.modulate = Color("566369")
	_hero = _car("OfferedCar", MATERIALS.hero_texture(car_id))
	_lamp = _painter("OfferLamp", _draw_lamp)
	resized.connect(_layout)
	_layout()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, REVEAL_TIME)
	if reduced_motion:
		reveal_state = &"crossfade"
	else:
		reveal_state = &"turn_in"
		_hero.scale *= REVEAL_SCALE
		_hero.rotation = REVEAL_TURN
		var reveal := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		reveal.tween_property(_hero, "scale", size / REFERENCE_SIZE, REVEAL_TIME)
		reveal.tween_property(_hero, "rotation", 0.0, REVEAL_TIME)


func _car(node_name: String, texture: Texture2D) -> TextureRect:
	var car := TextureRect.new()
	car.name = node_name
	car.texture = texture
	car.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	car.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	car.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	car.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(car)
	return car


func _painter(node_name: String, paint: Callable) -> Control:
	var node := Control.new()
	node.name = node_name
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.draw.connect(paint)
	add_child(node)
	return node


func _layout() -> void:
	var ratio := size / REFERENCE_SIZE
	for pair: Array in [[_hero, HERO_RECT], [_rival, RIVAL_RECT]]:
		var car := pair[0] as TextureRect
		var rect: Rect2 = pair[1]
		car.size = rect.size
		car.pivot_offset = rect.size * 0.5
		car.scale = ratio
		car.position = rect.get_center() * ratio - rect.size * 0.5
	_table.queue_redraw()
	_lamp.queue_redraw()


func _draw_turntable() -> void:
	_table.draw_set_transform(Vector2.ZERO, 0, size / REFERENCE_SIZE)
	MATERIALS.shadow(_table, Rect2(TURNTABLE_CENTER + Vector2(-202, -75), Vector2(410, 194)), true, 0.6)
	MATERIALS.shadow(_table, Rect2(1053, 150, 88, 122), true, 0.4)
	_table.draw_set_transform(TURNTABLE_CENTER * size / REFERENCE_SIZE, 0, size / REFERENCE_SIZE * Vector2(1, 0.43))
	_table.draw_circle(Vector2(0, 22), 195, Color("273e40"))
	_table.draw_rect(Rect2(-195, 0, 390, 22), Color("364e4d"))
	_table.draw_circle(Vector2.ZERO, 195, SKIN.INK)
	_table.draw_circle(Vector2.ZERO, 190, Color("a9ad94"))
	_table.draw_circle(Vector2.ZERO, 182, Color("708579"))
	_table.draw_circle(Vector2.ZERO, 166, Color("435e56"))
	_table.draw_arc(Vector2(-2, -3), 187, PI, TAU, 80, Color("e9dfba"), 3, true)
	for angle in 12:
		var direction := Vector2.from_angle(TAU * float(angle) / 12.0)
		_table.draw_line(direction * 173, direction * 181, Color("d8d3ac"), 2, true)
	_table.draw_set_transform(Vector2.ZERO, 0, size / REFERENCE_SIZE)
	MATERIALS.shadow(_table, Rect2(HERO_RECT.position + Vector2(35, 55), Vector2(140, 187)), true, 0.35)


func _draw_lamp() -> void:
	_lamp.draw_set_transform(Vector2.ZERO, 0, size / REFERENCE_SIZE)
	_lamp.draw_colored_polygon(PackedVector2Array([Vector2(675, 133), Vector2(767, 149), Vector2(1034, 461), Vector2(643, 459)]), Color(1, 0.88, 0.57, 0.035))
	MATERIALS.shadow(_lamp, Rect2(580, 281, 123, 30), true, 0.5)
	_lamp.draw_set_transform(Vector2(634, 285) * size / REFERENCE_SIZE, 0, size / REFERENCE_SIZE * Vector2(1, 0.36))
	_lamp.draw_circle(Vector2.ZERO, 49, SKIN.INK)
	_lamp.draw_circle(Vector2(-2, -5), 45, Color("4e685f"))
	_lamp.draw_set_transform(Vector2.ZERO, 0, size / REFERENCE_SIZE)
	_lamp.draw_polyline(PackedVector2Array([Vector2(632, 280), Vector2(605, 179), Vector2(708, 108)]), SKIN.INK, 15, true)
	_lamp.draw_polyline(PackedVector2Array([Vector2(632, 277), Vector2(607, 180), Vector2(708, 111)]), Color("8d9c83"), 8, true)
	_lamp.draw_line(Vector2(606, 177), Vector2(700, 112), Color("d9d6b2"), 2, true)
	_lamp.draw_circle(Vector2(607, 180), 12, Color("384f4b"))
	_lamp.draw_set_transform(Vector2(721, 120) * size / REFERENCE_SIZE, 0.25, size / REFERENCE_SIZE)
	MATERIALS.shadow(_lamp, Rect2(-46, -29, 98, 60), true, 0.35)
	_lamp.draw_colored_polygon(PackedVector2Array([Vector2(-27, -27), Vector2(25, -27), Vector2(53, 24), Vector2(-48, 24)]), Color("b99653"))
	MATERIALS.paint_wear(_lamp, Rect2(-20, -22, 40, 40), 24291)
	_lamp.draw_line(Vector2(-24, -25), Vector2(23, -25), Color("f0d797"), 2, true)
	_lamp.draw_line(Vector2(-47, 24), Vector2(52, 24), SKIN.INK, 8, true)
	_lamp.draw_line(Vector2(-43, 23), Vector2(49, 23), Color("ffe2a1"), 4, true)


func register_control(button: Button, primary: bool = false) -> void:
	CONTROLS.dress_button(button, primary)
	button.button_down.connect(_press_control.bind(button, true))
	button.button_up.connect(_press_control.bind(button, false))


func _press_control(button: Button, down: bool) -> void:
	if is_instance_valid(_stamp):
		_stamp.kill()
	_stamp = create_tween().set_trans(Tween.TRANS_SINE)
	if reduced_motion:
		_stamp.tween_property(button, "modulate:a", 0.75 if down else 1.0, STAMP_TIME)
		return
	button.pivot_offset = button.size * 0.5
	var style := button.get_theme_stylebox("normal") as StyleBoxFlat
	var depth := func(at: float) -> void:
		button.scale = Vector2.ONE * at
		style.shadow_offset.y = remap(at, 0.97, 1.0, 2.0, 5.0)
	_stamp.tween_method(depth, button.scale.x, 0.97 if down else 1.0, STAMP_TIME)
