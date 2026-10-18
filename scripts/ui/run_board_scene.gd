extends Control

const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const MATERIALS := preload("res://scripts/ui/run_scene_materials.gd")
const UI := preload("res://scripts/ui/run_ui.gd")
const SURFACES := {
	1: preload("res://assets/textures/world_materials/kitchen_counter.png"),
	2: preload("res://assets/textures/world_materials/workshop_bench.png"),
	3: preload("res://assets/textures/world_materials/office_walnut.png"),
}
const ROOM_NAMES := {1: "Kitchen Counter", 2: "Workshop Bench", 3: "Office Desk"}
const NIGHT := Color("101e35")
const LAMP := Color("ffd59a")
const DRESSING_SEED := 2426
const SURFACE_TINTS := {1: Color("dfcca6"), 2: Color("b78e64"), 3: Color("be986f")}
const SUNRISE := Color("ffd39a")
const MOONLIGHT := Color("344f80")
const HERO_LENGTH := {&"night_won": 280.0, &"night_lost": 228.0}
const CHALK_PADDING := 14
const MAP_SIZE := Vector2(896, 624)
const PAGE_INSET := Vector2(24, 16)
const DETAIL_WIDTH := 312.0
const COLUMN_GAP := 24
const MARKER_SCALE := 1.2
const DETAIL_OUTSET := 24
## The board's focus light: how many stops it can warm, the reach of the small
## pool on the player and on each choice (in scene widths), and how much of the
## night a pool lifts at its centre. Pools feather from their centre and stay
## apart, so the table between them keeps its own lamp light and texture.
const FOCUS_LIMIT := 8
const FOCUS_PLAYER_REACH := 0.075
const FOCUS_CHOICE_REACH := 0.055
const FOCUS_PEAK := 0.6
## Quieter caption tones on the chalkboard and on the paper slip.
const CHALK_CAPTION := Color(SKIN.CREAM, 0.66)
const PAPER_CAPTION := Color(SKIN.INK, 0.74)

var act := 1
var chalkboard := false
var refined_cards := false
var scene_mode: StringName = &"board"
var car_id := "rustbug"
var reduced_motion := false
var ambient_motion := true
var beam_origin := Vector2(0.17, 0.16)
var _lamp_pulse: Tween
var lighting_tint: Color:
	get:
		return SUNRISE if scene_mode == &"night_won" else MOONLIGHT if scene_mode == &"night_lost" else LAMP
var _hero: TextureRect
var _hero_shadow: TextureRect
var _tire_contacts: Control
var _light: ShaderMaterial
var _focus := PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	if chalkboard:
		get_parent().resized.connect(queue_redraw)
	else:
		MATERIALS.add_room_dressing(self, act, DRESSING_SEED, scene_mode != &"night_won")
		var shade := ColorRect.new()
		shade.name = "Lamplight"
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var shader := Shader.new()
		shader.code = "shader_type canvas_item;\n" + MATERIALS.sunlight_shader() + """
		uniform int ending = 0;
		uniform float lamp_warmth = 0.0;
		uniform vec2 focus_points[%d];
		uniform int focus_count = 0;
		uniform float aspect = 0.5625;
		void fragment() {
			float distance_to_lamp = length((UV - vec2(0.18, 0.12)) * vec2(1.0, 0.7));
			float night = smoothstep(0.13, 0.95, distance_to_lamp);
			if (ending == 0 && focus_count > 0) {
				// Small feathered warm pools on the player and their choices; the
				// rest of the table keeps the lamp's own falloff.
				float pool = 0.0;
				for (int i = 0; i < focus_count; i++) {
					float reach = i == 0 ? %.3f : %.3f;
					float d = length((UV - focus_points[i]) * vec2(1.0, aspect));
					pool = max(pool, 1.0 - smoothstep(0.0, reach, d));
				}
				night *= 1.0 - pool * %.3f;
			}
			COLOR = vec4(mix(vec3(1.0, 0.77, 0.43), vec3(0.025, 0.065, 0.16), smoothstep(0.0, 0.7, night)), mix(0.10, 0.88, night));""" % [FOCUS_LIMIT, FOCUS_PLAYER_REACH, FOCUS_CHOICE_REACH, FOCUS_PEAK] + """
			if (ending == 1) {
				float beam = sun_beam(UV);
				float intensity = beam * mix(0.28, 0.10, UV.y);
				COLOR = vec4(mix(vec3(0.91, 0.55, 0.29), vec3(1.0, 0.91, 0.64), beam), 0.16 + intensity);
			} else if (ending == 2) {
				float pool = 1.0 - smoothstep(0.05, 0.48, length((UV - vec2(0.27, 0.58)) * vec2(1.0, 0.7)));
				COLOR = vec4(mix(vec3(0.018, 0.035, 0.10), vec3(0.16, 0.25, 0.42), pool), mix(0.94, 0.72, pool));
			}
			if (ending == 0) { COLOR.rgb += vec3(0.9, 0.45, 0.1) * lamp_warmth; }
		}"""
		var light_material := ShaderMaterial.new()
		light_material.shader = shader
		light_material.set_shader_parameter("ending", 1 if scene_mode == &"night_won" else 2 if scene_mode == &"night_lost" else 0)
		shade.material = light_material
		_light = light_material
		resized.connect(_apply_focus)
		_apply_focus()
		add_child(shade)
		if ambient_motion:
			MATERIALS.add_beam_dust(self, size * beam_origin, reduced_motion, scene_mode == &"night_won")
			if not reduced_motion and scene_mode == &"board":
				_lamp_pulse = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
				var warmth := func(at: float) -> void: light_material.set_shader_parameter("lamp_warmth", at)
				_lamp_pulse.tween_method(warmth, 0.0, 0.015, 3.5)
				_lamp_pulse.tween_method(warmth, 0.015, 0.0, 3.5)
		if scene_mode != &"board":
			_add_hero()


## Warms the table around `points`, in map coordinates: the player's stop first,
## then the stops they can go to. The rest of the table keeps the lamp's light.
func set_focus(points: PackedVector2Array) -> void:
	_focus = points.slice(0, FOCUS_LIMIT)
	_apply_focus()


func focus_points() -> PackedVector2Array:
	return _focus


func _apply_focus() -> void:
	if _light == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var uvs := PackedVector2Array()
	uvs.resize(FOCUS_LIMIT)
	for index in _focus.size():
		uvs[index] = (PAGE_INSET + _focus[index]) / size
	_light.set_shader_parameter("focus_points", uvs)
	_light.set_shader_parameter("focus_count", _focus.size() if scene_mode == &"board" else 0)
	_light.set_shader_parameter("aspect", size.y / size.x)


func arrive() -> void:
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.32)


func _add_hero() -> void:
	_hero_shadow = TextureRect.new()
	_hero_shadow.name = "HeroShadow"
	_hero_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_shadow.rotation = -0.35
	_hero_shadow.texture = MATERIALS.SHADOW_CIRCLE
	_hero_shadow.modulate = MATERIALS.SHADOW_TINT
	_hero_shadow.modulate.a = 0.38
	add_child(_hero_shadow)
	_tire_contacts = Control.new()
	_tire_contacts.name = "HeroTireContacts"
	_tire_contacts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tire_contacts.rotation = -0.35
	_tire_contacts.draw.connect(func() -> void:
		var length: float = HERO_LENGTH[scene_mode]
		for x: float in [-0.22, 0.22]:
			for y: float in [-0.24, 0.24]:
				MATERIALS.shadow(_tire_contacts, Rect2(Vector2(x, y) * length - Vector2(18, 9), Vector2(36, 18)), true, 0.8))
	add_child(_tire_contacts)
	_hero = TextureRect.new()
	_hero.name = "WinnerCar" if scene_mode == &"night_won" else "SolitaryCar"
	_hero.texture = MATERIALS.hero_texture(car_id)
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hero.rotation = -0.35
	_hero.modulate = Color("fff0cd") if scene_mode == &"night_won" else Color("adcaed")
	add_child(_hero)
	resized.connect(_layout_hero)
	_layout_hero()


func _layout_hero() -> void:
	if _hero == null:
		return
	var length: float = HERO_LENGTH[scene_mode]
	_hero.size = Vector2(length * 0.75, length)
	_hero.pivot_offset = _hero.size * 0.5
	var center := size * Vector2(0.265, 0.565)
	_hero.position = center - _hero.size * 0.5
	_hero_shadow.size = Vector2(length * 0.72, length * 0.90)
	_hero_shadow.pivot_offset = _hero_shadow.size * 0.5
	_hero_shadow.position = center + Vector2(16, 22) - _hero_shadow.size * 0.5
	_tire_contacts.position = center


func _draw() -> void:
	if chalkboard:
		_draw_chalkboard()
		return
	var surface: Texture2D = SURFACES.get(act, SURFACES[1])
	draw_texture_rect(surface, Rect2(Vector2.ZERO, size), true, SURFACE_TINTS.get(act, Color.WHITE))
	_draw_room_material()
	MATERIALS.grain(self, Rect2(Vector2.ZERO, size))
	# Broad translucent bands make one warm pool, with cool night at the rim.
	draw_rect(Rect2(Vector2.ZERO, size), Color(NIGHT, 0.25))
	for ring in range(24, 0, -1):
		var radius := float(ring) * size.x / 24.0
		draw_circle(size * Vector2(0.17, 0.08), radius, Color(LAMP, 0.008))
	for edge in 24:
		var inset := float(edge) * 4.0
		draw_rect(Rect2(Vector2.ONE * inset, size - Vector2.ONE * inset * 2.0), Color(NIGHT, 0.022), false, 8.0)
	if act == 1:
		# A saucer, cropped by the table edge, and its coffee ring.
		_draw_saucer(Vector2(size.x + 22, size.y * 0.67))
	elif act == 2:
		for screw in 5:
			var point := Vector2(size.x - 22 - screw * 15, size.y - 34 + (screw % 2) * 9)
			MATERIALS.shadow(self, Rect2(point - Vector2(14, 14), Vector2(30, 30)), true)
			draw_texture_rect(MATERIALS.ROOM_DRESSING[2][0], Rect2(point - Vector2(14, 14), Vector2(28, 28)), false)
	elif scene_mode != &"night_won":
		SKIN.draw_tape(self, Vector2(size.x - 20, size.y * 0.4), Vector2(125, 28), -0.7, SKIN.CREAM)
		for line in 7:
			draw_line(Vector2(size.x - 46, size.y * 0.55 + line * 9), Vector2(size.x, size.y * 0.55 + line * 9), Color(SKIN.CREAM, 0.22), 1)
	_draw_tape_roll(Rect2(size.x - 112, 6, 88, 88))


## A rolled masking tape with its core, standing on the table edge. Drawn
## procedurally: the painted roll source lives under assets/textures/
## environment_pilot/, which export presets exclude.
func _draw_tape_roll(rect: Rect2) -> void:
	MATERIALS.shadow(self, Rect2(rect.position + Vector2(6, 16), rect.size), true)
	var center := rect.get_center()
	var radius := rect.size.x * 0.5
	# A slight top-down tilt so the roll reads as a cylinder, not a disc.
	draw_set_transform(center, 0.0, Vector2(1.0, 0.82))
	# Outer paper with a visible thickness edge.
	draw_circle(Vector2.ZERO, radius, Color("e2d4ae"))
	draw_arc(Vector2.ZERO, radius * 0.96, 0, TAU, 96, Color("c3b183"), 2.5, true)
	draw_arc(Vector2.ZERO, radius * 0.99, 0.6, 2.6, 48, Color("f2e6c4"), 2.0, true)
	# Wound paper: fine, low-contrast layers.
	for ring in 4:
		var r := radius * (0.38 + 0.09 * ring)
		draw_arc(Vector2.ZERO, r, 0, TAU, 96, Color("b3a377", 0.5), 1.2, true)
	# Hollow core: cardboard wall around a dark opening.
	draw_circle(Vector2.ZERO, radius * 0.30, Color("c9a56c"))
	draw_circle(Vector2.ZERO, radius * 0.24, Color("5b4a30"))
	draw_circle(Vector2.ZERO, radius * 0.20, Color("3a2f1f"))
	draw_arc(Vector2.ZERO, radius * 0.26, PI * 0.7, PI * 1.6, 24, Color("e8cf9c"), 2.0, true)
	# Contact shading on the lower rim.
	draw_arc(Vector2.ZERO, radius * 0.96, PI * 0.15, PI * 0.85, 48, Color(0.01, 0.02, 0.04, 0.12), 2.5, true)
	draw_set_transform(Vector2.ZERO)


func _draw_saucer(center: Vector2) -> void:
	MATERIALS.shadow(self, Rect2(center - Vector2(118, 104), Vector2(256, 240)), true)
	draw_circle(center, 100, Color("aaa99b"))
	draw_circle(center, 84, Color("d8ccad"))
	draw_arc(center, 65, 0, TAU, 64, Color("7c6149"), 4, true)
	draw_circle(center, 55, Color("44342c"))
	draw_arc(center - Vector2(8, 8), 40, PI, TAU * 0.8, 32, Color("bd9971"), 2, true)


func _draw_room_material() -> void:
	match act:
		1:
			# Oversized ceramic slabs give the counter a household scale.
			for column in range(1, 7):
				var x := float(column) * 236.0
				draw_line(Vector2(x, 0), Vector2(x - 22, size.y), Color("887a63"), 5, true)
				draw_line(Vector2(x + 3, 0), Vector2(x - 19, size.y), Color("f5e4bc"), 2, true)
			for row in range(1, 4):
				var y := float(row) * 260.0
				draw_line(Vector2(0, y), Vector2(size.x, y - 10), Color("887a63"), 5, true)
				draw_line(Vector2(0, y + 3), Vector2(size.x, y - 7), Color("f5e4bc"), 2, true)
		2:
			for plank in range(1, 6):
				var y := float(plank) * 155.0
				draw_line(Vector2(0, y), Vector2(size.x, y - 7), Color("533b2b"), 4, true)
				draw_line(Vector2(0, y + 4), Vector2(size.x, y - 3), Color("dec399"), 1, true)
				for x: float in [24.0, size.x - 24.0]:
					draw_circle(Vector2(x, y - 16), 5, Color("716b59"))
					draw_line(Vector2(x - 3, y - 16), Vector2(x + 3, y - 16), SKIN.INK, 2)
		3:
			var pad := Rect2(34, 82, 548, 490)
			MATERIALS.plate(self, pad, Color("405752"), 18)
			MATERIALS.grain(self, pad.grow(-5))
			draw_style_box(_stitch_border(), pad.grow(-9))


func _stitch_border() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = Color("a29472")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	return style


func _draw_chalkboard() -> void:
	var extent: Vector2 = get_parent().size
	var inset := get_parent().get_node("ChalkboardInset") as Control
	var paper_y := inset.position.y + inset.size.y + 4.0
	var rect := Rect2(Vector2(-8, -8), Vector2(extent.x + 16, paper_y - 4.0))
	if refined_cards:
		_draw_refined_cards(rect, Rect2(Vector2(-8, paper_y), Vector2(extent.x + 16, maxf(92.0, extent.y - paper_y + 10.0))))
		return
	MATERIALS.plate(self, rect, Color("71563c"), 5)
	var face := rect.grow(-7)
	draw_rect(face, Color("26362f"))
	draw_rect(face.grow(-3), Color("83927d"), false, 1)
	MATERIALS.grain(self, face.grow(-3), true)
	for line in 4:
		var y := face.position.y + 15 + line * 39
		draw_line(Vector2(face.position.x + 12, y), Vector2(face.end.x - 12, y + 3), Color(SKIN.CREAM, 0.025), 3, true)
	SKIN.draw_tape(self, Vector2(20, -12), Vector2(68, 22), -0.13)
	SKIN.draw_tape(self, Vector2(extent.x - 18, -12), Vector2(68, 22), 0.15)
	var paper := Rect2(Vector2(-8, paper_y), Vector2(extent.x + 16, maxf(92.0, extent.y - paper_y + 10.0)))
	MATERIALS.plate(self, paper, Color("e6dcc0"), 2)
	MATERIALS.grain(self, paper.grow(-3))
	for line in 9:
		var y := paper.position.y + 28 + line * 27
		if y > paper.end.y - 12.0:
			break
		draw_line(Vector2(paper.position.x + 14, y), Vector2(paper.end.x - 14, y), Color(SKIN.INK, 0.08), 1)
	SKIN.draw_tape(self, Vector2(extent.x * 0.76, paper_y), Vector2(84, 24), -0.09)


func _draw_refined_cards(chalk: Rect2, paper: Rect2) -> void:
	MATERIALS.shadow(self, Rect2(chalk.position + Vector2(-5, -2), chalk.size + Vector2(12, 12)), false, 0.5)
	draw_rect(chalk, Color("80694c"))
	draw_rect(chalk.grow(-2), Color("213b33"))
	draw_rect(chalk.grow(-4), Color("849383"), false, 1)
	draw_line(chalk.position + Vector2(2, 1), Vector2(chalk.end.x - 2, chalk.position.y + 1), Color("cab68d"), 1, true)
	MATERIALS.grain(self, chalk.grow(-5), true)
	MATERIALS.paint_wear(self, Rect2(chalk.position + Vector2(2, 5), Vector2(5, chalk.size.y - 10)), 24411)
	MATERIALS.shadow(self, Rect2(paper.position + Vector2(-4, 0), paper.size + Vector2(12, 12)), false, 0.55)
	draw_rect(Rect2(paper.position + Vector2(3, 4), paper.size), Color("b9ac8f"))
	draw_rect(Rect2(paper.position + Vector2(1, 2), paper.size), Color("f4e7ca"))
	draw_rect(paper, Color("e9dfc4"))
	draw_rect(paper, Color(SKIN.INK, 0.6), false, 1)
	draw_line(paper.position + Vector2(3, 2), Vector2(paper.end.x - 3, paper.position.y + 2), Color("fff5dc"), 1, true)
	MATERIALS.grain(self, paper.grow(-4))
	for line in 10:
		var y := paper.position.y + 28 + line * 27
		if y < paper.end.y - 12:
			draw_line(Vector2(paper.position.x + 12, y), Vector2(paper.end.x - 12, y), Color(SKIN.INK, 0.045), 1)
	for at: Vector2 in [chalk.position + Vector2(9, -4), Vector2(paper.end.x - 38, paper.position.y - 7)]:
		SKIN.draw_tape(self, at + Vector2(17, 8), Vector2(35, 17), -0.09, Color("d9bf81"))
		draw_texture_rect_region(MATERIALS.TAPE_CORNER, Rect2(at, Vector2(35, 17)), Rect2(180, 110, 80, 50), Color(1, 0.9, 0.7, 0.16))
	draw_colored_polygon(PackedVector2Array([paper.end - Vector2(19, 0), paper.end - Vector2(0, 19), paper.end]), Color("cbbd9c"))
	draw_line(paper.end - Vector2(19, 0), paper.end - Vector2(0, 19), Color("fff0d2"), 1, true)


static func compact_labels(host: Node) -> void:
	for child: Node in host.get_children():
		if child is Label:
			var label := child as Label
			var font_size := label.get_theme_font_size("font_size")
			label.add_theme_font_size_override("font_size", 28 if font_size >= 30 else 24 if font_size >= 24 else 16 if font_size >= 16 else font_size)
			if label.get_parent() is VBoxContainer and not label.get_parent().get_parent() is HBoxContainer:
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if child is GridContainer:
			(child as GridContainer).add_theme_constant_override("h_separation", 10)
		compact_labels(child)


static func facts(rows: Array) -> VBoxContainer:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 2)
	var short_rows: Array = []
	for row: Array in rows:
		if String(row[0]) == "CIRCUIT":
			var stacked := VBoxContainer.new()
			stacked.name = "CircuitFact"
			stacked.add_theme_constant_override("separation", 3)
			stacked.add_child(UI.label(String(row[0]), 11, UI.MUTED, true))
			var value := UI.label(String(row[1]), 15)
			value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			stacked.add_child(value)
			list.add_child(stacked)
		else:
			short_rows.append(row)
	list.add_child(UI.facts(short_rows))
	return list


static func ink_labels(host: Node) -> void:
	for child: Node in host.get_children():
		if child is Label:
			(child as Label).add_theme_color_override("font_color", SKIN.INK)
		ink_labels(child)


static func chalk_labels(host: Node) -> void:
	for child: Node in host.get_children():
		if child is Label:
			(child as Label).add_theme_color_override("font_color", SKIN.CREAM)
		chalk_labels(child)


## Mono captions (keys, states, metadata) step back behind the values they
## label: same words, a quieter tone of the surface's ink.
static func quiet_captions(host: Node, ink: Color) -> void:
	for child: Node in host.get_children():
		if child is Label and (child as Label).get_theme_font("font") == UI.mono_font():
			(child as Label).add_theme_color_override("font_color", ink)
		quiet_captions(child, ink)


static func label_tape() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("27332f")
	style.set_content_margin_all(4)
	return style
