extends Control

const TABLETOP := preload("res://scripts/ui/run_board_scene.gd")
const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")
const BUTTON_STYLE := preload("res://scripts/ui/run_bench_scene.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const UI := preload("res://scripts/ui/run_ui.gd")
const NOTEPAD := preload("res://assets/textures/ground_dressing/office_notepad_page.png")
const ENVELOPES := preload("res://assets/textures/ground_dressing/office_envelope_stack.png")
const REFERENCE_SIZE := Vector2(1280, 720)
const UI_COLUMN_HEIGHT := 572.0
const STAMP_TIME := 0.32
const FADE_TIME := 0.18
const NOTE_ORIGIN := Vector2(255, 430)
const NOTE_ANGLE := -0.1
const DISABLED_INK := Color("807b68")
const TASKS: Array[String] = [
	"DELIVER A PART TO THE NEXT ROOM",
	"RECOVER A CAR FROM THE SILL",
	"TOW A STRANDED CAR TO THE VAN",
	"FETCH TOOLS FROM THE WORKSHOP",
]

var act := 1
var reduced_motion := false
var confirmation_state: StringName = &"idle"
var stamp_depth := 0.0
var _note: Control
var _clipboard: Control
var _cup: Control
var _paper_art: AtlasTexture
var _envelope_art: AtlasTexture
var _message: Label


static func request_for_node(session: RunSession, node_id: String) -> Dictionary:
	var request_seed := ("pocket-circuit|errand|%d|act%d|%s" % [session.run_seed, session.current_map.act, node_id]).hash() & 0x7FFFFFFF
	var rng := RandomNumberGenerator.new()
	rng.seed = request_seed
	var node_ids := session.current_map.nodes.keys()
	node_ids.sort()
	for race_id: String in node_ids:
		var opponents: Array = session.opponents_for_node(race_id).get("opponents", [])
		if not opponents.is_empty():
			var driver: Dictionary = opponents[rng.randi_range(0, opponents.size() - 1)]
			return {"requester": driver, "task": TASKS[rng.randi_range(0, TASKS.size() - 1)]}
	return {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var table := TABLETOP.new()
	table.name = "ErrandTabletop"
	table.act = act
	table.reduced_motion = reduced_motion
	table.ambient_motion = false
	table.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(table)
	_paper_art = _trimmed(NOTEPAD)
	_envelope_art = _trimmed(ENVELOPES)
	_note = _painter("ErrandNote", _draw_note)
	_message = UI.label(String(UI.TYPES["errand"]["copy"]), 16, SKIN.INK)
	_message.name = "ErrandMessage"
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.size = Vector2(205, 140)
	_note.add_child(_message)
	_layout_message()
	_clipboard = _painter("ErrandClipboard", _draw_clipboard)
	_cup = _painter("ErrandCoinCup", _draw_cup)
	resized.connect(func() -> void:
		_layout_message()
		_note.queue_redraw()
		_clipboard.queue_redraw()
		_cup.queue_redraw())
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, STAMP_TIME)


func _trimmed(texture: Texture2D) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(texture.get_image().get_used_rect())
	return atlas


func _painter(node_name: String, paint: Callable) -> Control:
	var node := Control.new()
	node.name = node_name
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.draw.connect(paint)
	add_child(node)
	return node


func _layout_message() -> void:
	var ratio := size / REFERENCE_SIZE
	_message.position = NOTE_ORIGIN * ratio + (Vector2(-110, -82) * ratio).rotated(NOTE_ANGLE)
	_message.rotation = NOTE_ANGLE
	_message.scale = ratio


func _draw_note() -> void:
	var ratio := size / REFERENCE_SIZE
	_note.draw_set_transform(NOTE_ORIGIN * ratio, NOTE_ANGLE, ratio)
	MATERIALS.shadow(_note, Rect2(-137, 77, 314, 16), false, 0.4)
	_note.draw_texture_rect(_envelope_art, Rect2(-135, 52, 300, 32), false, Color("d9cba7"))
	_note.draw_colored_polygon(PackedVector2Array([Vector2(-95, 70), Vector2(35, -45), Vector2(160, 70)]), Color("a89772"))
	_note.draw_line(Vector2(35, -45), Vector2(160, 70), Color("e5d7b1"), 2, true)
	_note.draw_texture_rect(_paper_art, Rect2(-125, -100, 235, 180), false, Color("f2e8cd"))
	MATERIALS.grain(_note, Rect2(-119, -94, 223, 168))
	_note.draw_line(Vector2(-117, -10), Vector2(103, -10), Color(0.43, 0.36, 0.24, 0.28), 2, true)
	_note.draw_line(Vector2(-117, -7), Vector2(103, -7), Color(1, 0.98, 0.85, 0.55), 1, true)
	_note.draw_colored_polygon(PackedVector2Array([Vector2(78, -100), Vector2(110, -100), Vector2(110, -72)]), Color("c8b88e"))
	_note.draw_line(Vector2(78, -100), Vector2(110, -72), Color("fff7de"), 2, true)


func _draw_clipboard() -> void:
	_clipboard.draw_set_transform(Vector2.ZERO, 0, size / REFERENCE_SIZE)
	MATERIALS.plate(_clipboard, Rect2(578, 95, 520, 450), Color("91754c"), 9)
	MATERIALS.grain(_clipboard, Rect2(583, 100, 510, 440))
	MATERIALS.paint_wear(_clipboard, Rect2(583, 108, 12, 422), 24281)
	_clipboard.draw_texture_rect(_paper_art, Rect2(594, 122, 488, 395), false, Color("f2e9cc"))
	MATERIALS.grain(_clipboard, Rect2(600, 128, 476, 383))
	MATERIALS.plate(_clipboard, Rect2(783, 83, 110, 46), Color("8b9c92"), 6)
	MATERIALS.plate(_clipboard, Rect2(805, 78, 66, 18), Color("bdc8b5"), 5)
	_clipboard.draw_rect(Rect2(795, 103, 86, 17), Color("526c66"))
	_clipboard.draw_line(Vector2(793, 89), Vector2(878, 89), Color("edf0d6"), 2, true)
	for x: float in [795.0, 881.0]:
		_clipboard.draw_circle(Vector2(x, 94), 3, SKIN.INK)


func _draw_cup() -> void:
	var ratio := size / REFERENCE_SIZE
	_cup.draw_set_transform(Vector2.ZERO, 0, ratio)
	MATERIALS.shadow(_cup, Rect2(1048, 574, 126, 24), true, 0.4)
	_cup.draw_set_transform(Vector2(1110, 533) * ratio, 0, ratio * Vector2(1, 0.55))
	_cup.draw_circle(Vector2(0, 50), 52, Color("435b55"))
	_cup.draw_rect(Rect2(-52, 0, 104, 50), Color("61796d"))
	MATERIALS.grain(_cup, Rect2(-47, 4, 94, 70))
	MATERIALS.paint_wear(_cup, Rect2(-45, 32, 90, 36), 24282)
	_cup.draw_line(Vector2(-46, 13), Vector2(-46, 52), Color(0.93, 0.95, 0.79, 0.38), 2, true)
	_cup.draw_circle(Vector2.ZERO, 55, SKIN.INK)
	_cup.draw_circle(Vector2.ZERO, 52, Color("b8c2a9"))
	_cup.draw_circle(Vector2.ZERO, 44, Color("293e3b"))
	_cup.draw_arc(Vector2(-1, -2), 52, PI, TAU, 40, Color("f2edcb"), 2, true)
	for coin: Vector2 in [Vector2(-22, 10), Vector2(2, -8), Vector2(22, 12), Vector2(-2, 24)]:
		_cup.draw_circle(coin + Vector2(2, 3), 12, SKIN.INK)
		_cup.draw_circle(coin, 11, Color("d1aa59"))
		_cup.draw_arc(coin - Vector2(1, 1), 8, PI, TAU, 20, Color("f6dda0"), 2, true)


func register_choice(button: Button, choice: int) -> void:
	BUTTON_STYLE.dress_button(button)
	button.modulate = Color.WHITE
	button.add_theme_color_override("font_disabled_color", DISABLED_INK)
	button.custom_minimum_size.y = 98
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		(button.get_theme_stylebox(state) as StyleBoxFlat).content_margin_left = 88
	button.draw.connect(func() -> void:
		if choice == 0:
			for at: Vector2 in [Vector2(36, 54), Vector2(50, 42), Vector2(31, 35)]:
				MATERIALS.shadow(button, Rect2(at - Vector2(16, 11), Vector2(34, 28)), true, 0.4)
				button.draw_circle(at, 13, SKIN.INK)
				button.draw_circle(at - Vector2(1, 1), 11, Color("c9a452"))
				button.draw_arc(at - Vector2(2, 2), 8, PI, TAU, 18, Color("f3d99a"), 2, true)
		else:
			button.draw_texture_rect(MATERIALS.WRENCH, Rect2(14, 15, 60, 64), false, choice_ink(button)))


static func choice_ink(button: Button) -> Color:
	return DISABLED_INK if button.disabled else SKIN.INK


func confirm(button: Button, choice: int) -> float:
	if confirmation_state != &"idle":
		return 0.0
	if reduced_motion:
		confirmation_state = &"crossfade"
		var fade := create_tween().set_parallel(true)
		fade.tween_property(self, "modulate:a", 0.0, FADE_TIME)
		fade.tween_property(button, "modulate:a", 0.0, FADE_TIME)
		return FADE_TIME
	confirmation_state = &"pay" if choice == 0 else &"tune_up"
	button.pivot_offset = button.size * 0.5
	var style := button.get_theme_stylebox("disabled") as StyleBoxFlat
	var press := func(depth: float) -> void:
		stamp_depth = depth
		button.scale = Vector2.ONE * lerpf(1.0, 0.97, depth)
		style.shadow_offset = Vector2(4, lerpf(5.0, 2.0, depth))
	var stamp := create_tween().set_trans(Tween.TRANS_SINE)
	stamp.tween_method(press, 0.0, 1.0, STAMP_TIME * 0.4)
	stamp.tween_method(press, 1.0, 0.0, STAMP_TIME * 0.6)
	return STAMP_TIME
