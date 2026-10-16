extends Control

const TABLETOP := preload("res://scripts/ui/run_board_scene.gd")
const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const TOOLBOX := preload("res://assets/textures/workshop_hero/hero_workshop_toolbox.png")
const PAINT_CAN := preload("res://assets/textures/workshop_hero/hero_workshop_paint_can.png")
const REFERENCE_SIZE := Vector2(1280, 720)
const DOOR_RECT := Rect2(625, 143, 480, 290)
const SILL_RECT := Rect2(612, 437, 512, 22)
const PAINT_CAN_RECT := Rect2(365, 360, 130, 150)
const PAINT_CAN_SHADOW_RECT := Rect2(396, 473, 68, 14)
const CAR_SHADOW_OFFSET := Vector2(2, 3)
const LEGEND_SPACER := 6.0
const UI_COLUMN_HEIGHT := 572.0
const LOCK_CENTER := Vector2(865, 328)
const PARKED_CENTER := Vector2(865, 352)
const EXIT_CENTER := Vector2(865, 544)
const CAR_LENGTH := 202.0
const STAMP_TIME := 0.22
const UNLOCK_TIME := 0.14
const DOOR_TIME := 0.32
const ROLL_TIME := 0.30
const HOLD_TIME := 0.12
const FADE_TIME := 0.20

var act := 1
var reduced_motion := false
var already_open := false
var confirmation_state: StringName = &"idle"
var stamp_depth := 0.0
var door_progress := 0.0:
	set(value):
		door_progress = value
		if _shutter != null:
			_shutter.position.y = -_door.size.y * value
var lock_progress := 0.0:
	set(value):
		lock_progress = value
		if _padlock != null:
			_padlock.queue_redraw()
		if _chain != null:
			_chain.modulate.a = clampf(1.0 - value, 0.0, 1.0)

var _frame: Control
var _door: Control
var _shutter: Control
var _chain: Control
var _padlock: Control
var _car: TextureRect
var _car_shadow: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var table := TABLETOP.new()
	table.name = "LockupTabletop"
	table.act = act
	table.reduced_motion = reduced_motion
	table.ambient_motion = false
	table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(table)
	_frame = _painter("GarageFrame", _draw_frame)
	_car_shadow = TextureRect.new()
	_car_shadow.name = "LockupCarShadow"
	_car_shadow.texture = MATERIALS.SHADOW_CIRCLE
	_car_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_car_shadow.modulate = Color(MATERIALS.SHADOW_TINT, 0.28)
	_car_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_car_shadow.hide()
	add_child(_car_shadow)
	_car = TextureRect.new()
	_car.name = "LockupCar"
	_car.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_car.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_car.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_car.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_car.rotation = PI
	_car.hide()
	add_child(_car)
	_door = Control.new()
	_door.name = "LockupDoor"
	_door.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_door.clip_contents = true
	add_child(_door)
	_shutter = Control.new()
	_shutter.name = "ShutterPaint"
	_shutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shutter.draw.connect(_draw_shutter)
	_door.add_child(_shutter)
	_chain = _painter("LockupChain", _draw_chain)
	_padlock = _painter("LockupPadlock", _draw_padlock)
	resized.connect(_layout)
	_layout()
	if already_open:
		door_progress = 1.0
		lock_progress = 1.0
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, STAMP_TIME)


func _painter(node_name: String, paint: Callable) -> Control:
	var node := Control.new()
	node.name = node_name
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.draw.connect(paint)
	add_child(node)
	return node


func _layout() -> void:
	var ratio := size / REFERENCE_SIZE
	_door.position = DOOR_RECT.position * ratio
	_door.size = DOOR_RECT.size * ratio
	_shutter.size = _door.size
	_shutter.position.y = -_door.size.y * door_progress
	_car.size = Vector2(CAR_LENGTH * 0.75, CAR_LENGTH) * ratio
	_car.pivot_offset = _car.size * 0.5
	_car_shadow.size = Vector2(CAR_LENGTH * 0.56, CAR_LENGTH * 0.78) * ratio
	_park_car(PARKED_CENTER)
	_frame.queue_redraw()
	_shutter.queue_redraw()
	_chain.queue_redraw()
	_padlock.queue_redraw()


func _park_car(center: Vector2) -> void:
	var scaled := center * size / REFERENCE_SIZE
	_car.position = scaled - _car.size * 0.5
	_car_shadow.position = scaled + CAR_SHADOW_OFFSET * size / REFERENCE_SIZE - _car_shadow.size * 0.5


func _draw_frame() -> void:
	_frame.draw_set_transform(Vector2.ZERO, 0, size / REFERENCE_SIZE)
	MATERIALS.shadow(_frame, Rect2(573, SILL_RECT.position.y - 35, 586, 103), false, 0.7)
	MATERIALS.plate(_frame, Rect2(599, 99, 535, SILL_RECT.end.y - 99), Color("41514f"), 8)
	MATERIALS.plate(_frame, Rect2(618, 133, 494, SILL_RECT.position.y - 129), Color("142b2e"), 3)
	_frame.draw_colored_polygon(PackedVector2Array([Vector2(599, 99), Vector2(633, 70), Vector2(1170, 70), Vector2(1134, 99)]), Color("8e9b8c"))
	_frame.draw_colored_polygon(PackedVector2Array([Vector2(1134, 99), Vector2(1170, 70), Vector2(1170, SILL_RECT.end.y - 36), Vector2(1134, SILL_RECT.end.y)]), Color("293b3b"))
	_frame.draw_line(Vector2(600, 99), Vector2(1134, 99), Color("e3d9b4"), 3, true)
	_frame.draw_line(Vector2(1135, 99), Vector2(1167, 73), Color("acb4a1"), 2, true)
	MATERIALS.grain(_frame, Rect2(603, 105, 527, SILL_RECT.end.y - 109))
	MATERIALS.paint_wear(_frame, Rect2(604, 113, 14, SILL_RECT.end.y - 143), 24271)
	MATERIALS.paint_wear(_frame, Rect2(1112, 113, 16, SILL_RECT.end.y - 143), 24272)
	MATERIALS.plate(_frame, SILL_RECT, Color("a7afa0"), 3)
	MATERIALS.shadow(_frame, Rect2(108, 446, 260, 84), false, 0.35)
	_frame.draw_texture_rect(TOOLBOX, Rect2(90, 332, 270, 205), false, Color("e4d5b5"))
	MATERIALS.shadow(_frame, PAINT_CAN_SHADOW_RECT, true, 0.35)
	_frame.draw_texture_rect(PAINT_CAN, PAINT_CAN_RECT, false, Color("dccfb0"))


func _draw_shutter() -> void:
	var rect := Rect2(Vector2.ZERO, _shutter.size)
	_shutter.draw_rect(rect, Color("61736d"))
	MATERIALS.grain(_shutter, rect.grow(-3))
	var pitch := _shutter.size.y / 13.0
	for slat in 13:
		var y := slat * pitch
		_shutter.draw_line(Vector2(0, y), Vector2(rect.end.x, y), Color("243b3b"), 3, true)
		_shutter.draw_line(Vector2(0, y + 4), Vector2(rect.end.x, y + 4), Color(0.85, 0.89, 0.75, 0.35), 2, true)
	MATERIALS.paint_wear(_shutter, rect.grow(-12), 24273)
	MATERIALS.plate(_shutter, Rect2(rect.size * Vector2(0.42, 0.86), rect.size * Vector2(0.16, 0.035)), Color("c4c7ad"), 3)


func _draw_chain() -> void:
	_chain.draw_set_transform(Vector2.ZERO, 0, size / REFERENCE_SIZE)
	for side: float in [-1.0, 1.0]:
		var start := Vector2(LOCK_CENTER.x + side * 218, LOCK_CENTER.y - 85)
		var end := Vector2(LOCK_CENTER.x + side * 17, LOCK_CENTER.y - 18)
		for link in 12:
			var point := start.lerp(end, float(link) / 11.0)
			_chain.draw_set_transform(point * size / REFERENCE_SIZE, (end - start).angle(), size / REFERENCE_SIZE * Vector2(1, 0.5 if link % 2 == 0 else 0.75))
			MATERIALS.shadow(_chain, Rect2(-15, -9, 33, 24), true, 0.4)
			_chain.draw_arc(Vector2.ZERO, 12, 0, TAU, 24, SKIN.INK, 7, true)
			_chain.draw_arc(Vector2.ZERO, 12, 0, TAU, 24, Color("aebbb1"), 4, true)
			_chain.draw_arc(Vector2(-1, -1), 12, PI, TAU, 12, Color("e6e6c7"), 1, true)


func _draw_padlock() -> void:
	var center := LOCK_CENTER.lerp(Vector2(665, 470), lock_progress)
	_padlock.draw_set_transform(center * size / REFERENCE_SIZE, lock_progress * 0.12, size / REFERENCE_SIZE)
	MATERIALS.shadow(_padlock, Rect2(-50, -31, 108, 108), false, 0.5)
	_padlock.draw_set_transform((center + Vector2(0, -16 * lock_progress)) * size / REFERENCE_SIZE, -lock_progress * 0.55, size / REFERENCE_SIZE)
	_padlock.draw_arc(Vector2(0, -24), 28, PI, TAU, 32, SKIN.INK, 13, true)
	_padlock.draw_arc(Vector2(0, -24), 28, PI, TAU, 32, Color("b9c6bc"), 8, true)
	_padlock.draw_arc(Vector2(-2, -25), 28, PI + 0.1, TAU - 0.1, 32, Color("edf0d3"), 2, true)
	_padlock.draw_set_transform(center * size / REFERENCE_SIZE, lock_progress * 0.12, size / REFERENCE_SIZE)
	MATERIALS.plate(_padlock, Rect2(-43, -20, 86, 72), Color("b49750"), 8)
	MATERIALS.grain(_padlock, Rect2(-38, -15, 76, 62))
	MATERIALS.paint_wear(_padlock, Rect2(-35, -10, 70, 48), 24274)
	_padlock.draw_line(Vector2(-33, -13), Vector2(31, -13), Color("f1d99a"), 2, true)
	_padlock.draw_circle(Vector2(0, 11), 7, SKIN.INK)
	_padlock.draw_line(Vector2(0, 11), Vector2(0, 30), SKIN.INK, 5, true)


func confirm(button: Button, won_car_id: String) -> float:
	if confirmation_state != &"idle":
		return 0.0
	_car.texture = MATERIALS.hero_texture(won_car_id)
	_car.show()
	_car_shadow.show()
	if reduced_motion:
		confirmation_state = &"crossfade"
		_car.modulate.a = 0.0
		var fade := create_tween().set_parallel(true)
		for front: Control in [_door, _padlock, _chain]:
			fade.tween_property(front, "modulate:a", 0.0, FADE_TIME)
		fade.tween_property(_car, "modulate:a", 1.0, FADE_TIME)
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
	motion.tween_callback(func() -> void: confirmation_state = &"unlock")
	motion.tween_property(self, "lock_progress", 1.0, UNLOCK_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	motion.tween_callback(func() -> void: confirmation_state = &"open")
	motion.tween_property(self, "door_progress", 1.0, DOOR_TIME)
	motion.tween_callback(func() -> void: confirmation_state = &"roll")
	motion.tween_method(_park_car, PARKED_CENTER, EXIT_CENTER, ROLL_TIME)
	motion.tween_callback(func() -> void: confirmation_state = &"hold")
	motion.tween_interval(HOLD_TIME)
	return STAMP_TIME + UNLOCK_TIME + DOOR_TIME + ROLL_TIME + HOLD_TIME
