extends Control

const TABLETOP := preload("res://scripts/ui/run_board_scene.gd")
const PACK_STYLE := preload("res://scripts/ui/run_bench_scene.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")
const REFERENCE_SIZE := Vector2(1280, 720)
const STAMP_TIME := 0.24
const SWING_TIME := 0.25
const FADE_TIME := 0.18
const OFF_PEG_OFFSET := Vector2(18, 34)

var act := 1
var reduced_motion := false
var confirmation_state: StringName = &"idle"
var stamp_depth := 0.0
var blisters: Array[Control] = []
var _door: Control
var _lamp: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var table := TABLETOP.new()
	table.name = "VanTabletop"
	table.act = act
	table.reduced_motion = reduced_motion
	table.beam_origin = Vector2(0.35, 0.5)
	table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(table)
	_door = Control.new()
	_door.name = "VanDoor"
	_door.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_door.draw.connect(_draw_door)
	add_child(_door)
	_lamp = Control.new()
	_lamp.name = "WorkLamp"
	_lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lamp.draw.connect(_draw_lamp)
	add_child(_lamp)
	resized.connect(func() -> void:
		_door.queue_redraw()
		_lamp.queue_redraw())
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, STAMP_TIME)


func _draw_door() -> void:
	_door.draw_set_transform(Vector2.ZERO, 0, size / REFERENCE_SIZE)
	# Rear wheels and bumper anchor the shop to a die-cast vehicle.
	for x: float in [580.0, 1076.0]:
		MATERIALS.plate(_door, Rect2(x, 471, 56, 117), SKIN.INK, 14)
		_door.draw_line(Vector2(x + 13, 483), Vector2(x + 13, 573), Color("4f595a"), 5)
	MATERIALS.plate(_door, Rect2(544, 49, 606, 518), Color("b17443"), 28)
	MATERIALS.plate(_door, Rect2(566, 70, 562, 478), Color("354a48"), 14)
	MATERIALS.grain(_door, Rect2(550, 55, 594, 500))
	for slot in 16:
		var x := 584 + slot * 34
		_door.draw_line(Vector2(x, 83), Vector2(x, 531), Color("203533"), 2)
	for row in 8:
		for column in 13:
			_door.draw_circle(Vector2(590 + column * 40, 90 + row * 59), 2, Color("71867a"))
	# Doors are open outward, with deep window recesses and exposed hinges.
	var left := PackedVector2Array([Vector2(544, 86), Vector2(490, 121), Vector2(478, 523), Vector2(544, 552)])
	var right := PackedVector2Array([Vector2(1150, 86), Vector2(1221, 113), Vector2(1230, 521), Vector2(1150, 552)])
	_door.draw_colored_polygon(left, Color("e0b46a"))
	_door.draw_colored_polygon(right, Color("c89550"))
	MATERIALS.paint_wear(_door, Rect2(500, 270, 30, 225), 24261)
	MATERIALS.paint_wear(_door, Rect2(1172, 265, 32, 235), 24262)
	MATERIALS.paint_wear(_door, Rect2(585, 54, 500, 12), 24263)
	MATERIALS.paint_wear(_door, Rect2(590, 540, 500, 10), 24264)
	_door.draw_polyline(PackedVector2Array([left[0], left[1], left[2], left[3]]), SKIN.INK, 4, true)
	_door.draw_polyline(PackedVector2Array([right[0], right[1], right[2], right[3]]), SKIN.INK, 4, true)
	_door.draw_colored_polygon(PackedVector2Array([Vector2(534, 112), Vector2(502, 135), Vector2(498, 252), Vector2(532, 240)]), Color("29434d"))
	_door.draw_colored_polygon(PackedVector2Array([Vector2(1161, 112), Vector2(1207, 131), Vector2(1210, 249), Vector2(1163, 239)]), Color("29434d"))
	for x: float in [541.0, 1146.0]:
		for y: float in [166.0, 430.0]:
			MATERIALS.plate(_door, Rect2(x - 5, y, 14, 33), Color("bbc1ad"), 3)
	for x: float in [514.0, 1187.0]:
		MATERIALS.plate(_door, Rect2(x - 6, 330, 12, 47), Color("d0d2b9"), 4)
	MATERIALS.plate(_door, Rect2(546, 552, 606, 26), Color("abb4a7"), 8)
	for x: float in [560.0, 1104.0]:
		MATERIALS.plate(_door, Rect2(x, 510, 25, 30), Color("bc4934"), 4)
	_door.draw_line(Vector2(591, 65), Vector2(1100, 65), Color("f8d498"), 3, true)


func _draw_lamp() -> void:
	_lamp.draw_set_transform(Vector2.ZERO, 0, size / REFERENCE_SIZE)
	MATERIALS.plate(_lamp, Rect2(102, 503, 175, 32), Color("334542"), 16)
	_lamp.draw_line(Vector2(197, 510), Vector2(304, 407), Color("1a292d"), 16, true)
	_lamp.draw_line(Vector2(304, 407), Vector2(377, 325), Color("586a61"), 14, true)
	_lamp.draw_line(Vector2(202, 503), Vector2(300, 410), Color(0.9, 0.93, 0.77, 0.12), 2, true)
	for joint: Vector2 in [Vector2(197, 510), Vector2(304, 407), Vector2(377, 325)]:
		_lamp.draw_circle(joint, 13, Color("263a39"))
		_lamp.draw_circle(joint - Vector2(2, 2), 5, Color("bdc8b5"))
	_lamp.draw_set_transform(Vector2(397, 330), 0.55, size / REFERENCE_SIZE)
	_lamp.draw_colored_polygon(PackedVector2Array([Vector2(-30, -37), Vector2(26, -37), Vector2(55, 18), Vector2(-55, 18)]), Color("d99d49"))
	MATERIALS.paint_wear(_lamp, Rect2(-22, -32, 44, 42), 24265)
	_lamp.draw_line(Vector2(-53, 20), Vector2(53, 20), SKIN.INK, 8, true)
	_lamp.draw_line(Vector2(-41, 17), Vector2(41, 17), Color("fff0b6"), 9, true)


func register_pack(button: Button, part: Dictionary) -> void:
	PACK_STYLE.dress_part(button, part)
	var blister := button.get_child(1) as Control
	blister.name = "VanBlister"
	blisters.append(blister)
	button.draw.connect(func() -> void:
		var peg := Vector2(button.size.x * 0.5, 1)
		button.draw_circle(peg + Vector2(2, 2), 6, Color("293c38"))
		button.draw_arc(peg - Vector2(0, 4), 6, PI, TAU + 0.6, 20, Color("c3d1bf"), 3, true))


func confirm(button: Button) -> float:
	if confirmation_state != &"idle":
		return 0.0
	if reduced_motion:
		confirmation_state = &"crossfade"
		var fade := create_tween().set_parallel(true)
		fade.tween_property(self, "modulate:a", 0.0, FADE_TIME)
		fade.tween_property(button, "modulate:a", 0.0, FADE_TIME)
		return FADE_TIME
	confirmation_state = &"stamp"
	button.pivot_offset = button.size * 0.5
	var style := button.get_theme_stylebox("disabled") as StyleBoxFlat
	var press := func(depth: float) -> void:
		stamp_depth = depth
		button.scale = Vector2.ONE * lerpf(1.0, 0.97, depth)
		style.shadow_offset = Vector2(4, lerpf(5.0, 2.0, depth))
	var motion := create_tween().set_trans(Tween.TRANS_SINE)
	motion.tween_method(press, 0.0, 1.0, STAMP_TIME * 0.4)
	motion.tween_method(press, 1.0, 0.0, STAMP_TIME * 0.6)
	motion.tween_callback(func() -> void:
		confirmation_state = &"swing"
		button.pivot_offset = Vector2(button.size.x * 0.5, 0))
	motion.tween_property(button, "rotation", -0.10, SWING_TIME * 0.4)
	motion.tween_property(button, "rotation", 0.17, SWING_TIME * 0.6)
	motion.parallel().tween_property(button, "position", button.position + OFF_PEG_OFFSET, SWING_TIME * 0.6)
	motion.parallel().tween_property(button, "modulate:a", 0.0, SWING_TIME * 0.6)
	return STAMP_TIME + SWING_TIME


static func header_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("26362f")
	style.border_color = Color("806446")
	style.set_border_width_all(5)
	style.set_content_margin_all(14)
	style.shadow_color = Color(0.01, 0.02, 0.04, 0.55)
	style.shadow_size = 4
	style.shadow_offset = Vector2(5, 7)
	return style
