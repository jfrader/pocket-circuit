extends Control

const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
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

var act := 1
var chalkboard := false
var scene_mode: StringName = &"board"
var car_id := "rustbug"
var reduced_motion := false
var lighting_tint: Color:
	get:
		return SUNRISE if scene_mode == &"night_won" else MOONLIGHT if scene_mode == &"night_lost" else LAMP
var _hero: TextureRect
var _hero_shadow: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	if chalkboard:
		get_parent().resized.connect(queue_redraw)
	else:
		var shade := ColorRect.new()
		shade.name = "Lamplight"
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var shader := Shader.new()
		shader.code = """shader_type canvas_item;
		uniform int ending = 0;
		void fragment() {
			float distance_to_lamp = length((UV - vec2(0.18, 0.12)) * vec2(1.0, 0.7));
			float night = smoothstep(0.13, 0.95, distance_to_lamp);
			COLOR = vec4(mix(vec3(1.0, 0.77, 0.43), vec3(0.025, 0.065, 0.16), night), mix(0.10, 0.88, night));
			if (ending == 1) {
				COLOR = vec4(mix(vec3(1.0, 0.86, 0.58), vec3(0.74, 0.35, 0.18), UV.y), 0.28);
			} else if (ending == 2) {
				float pool = 1.0 - smoothstep(0.05, 0.48, length((UV - vec2(0.27, 0.58)) * vec2(1.0, 0.7)));
				COLOR = vec4(mix(vec3(0.018, 0.035, 0.10), vec3(0.16, 0.25, 0.42), pool), mix(0.94, 0.72, pool));
			}
		}"""
		var light_material := ShaderMaterial.new()
		light_material.shader = shader
		light_material.set_shader_parameter("ending", 1 if scene_mode == &"night_won" else 2 if scene_mode == &"night_lost" else 0)
		shade.material = light_material
		add_child(shade)
		if scene_mode != &"board":
			_add_hero()


func arrive() -> void:
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.32)


func _add_hero() -> void:
	_hero_shadow = TextureRect.new()
	_hero_shadow.name = "HeroShadow"
	_hero_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero_shadow.rotation = -0.35
	var falloff := Gradient.new()
	falloff.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	falloff.colors = PackedColorArray([Color(0.01, 0.02, 0.04, 0.5), Color(0.01, 0.02, 0.04, 0.22), Color(0.01, 0.02, 0.04, 0)])
	var ellipse := GradientTexture2D.new()
	ellipse.width = 256
	ellipse.height = 256
	ellipse.gradient = falloff
	ellipse.fill = GradientTexture2D.FILL_RADIAL
	ellipse.fill_from = Vector2(0.5, 0.5)
	ellipse.fill_to = Vector2(0.5, 1.0)
	_hero_shadow.texture = ellipse
	add_child(_hero_shadow)
	_hero = TextureRect.new()
	_hero.name = "WinnerCar" if scene_mode == &"night_won" else "SolitaryCar"
	_hero.texture = IDENTITIES.car_texture(car_id)
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
	_hero_shadow.size = Vector2(length * 0.82, length * 1.04)
	_hero_shadow.pivot_offset = _hero_shadow.size * 0.5
	_hero_shadow.position = center + Vector2(16, 22) - _hero_shadow.size * 0.5


func _draw() -> void:
	if chalkboard:
		_draw_chalkboard()
		return
	var surface: Texture2D = SURFACES.get(act, SURFACES[1])
	draw_texture_rect(surface, Rect2(Vector2.ZERO, size), true, SURFACE_TINTS.get(act, Color.WHITE))
	_draw_room_material()
	if scene_mode == &"night_won":
		for ray in 4:
			var x := float(ray) * 210.0 - 400.0
			draw_colored_polygon(PackedVector2Array([Vector2(x, 0), Vector2(x + 120, 0), Vector2(x + 650, size.y), Vector2(x + 450, size.y)]), Color(SUNRISE, 0.18))
	# Broad translucent bands make one warm pool, with cool night at the rim.
	draw_rect(Rect2(Vector2.ZERO, size), Color(NIGHT, 0.25))
	for ring in range(24, 0, -1):
		var radius := float(ring) * size.x / 24.0
		draw_circle(size * Vector2(0.17, 0.08), radius, Color(LAMP, 0.008))
	for edge in 24:
		var inset := float(edge) * 4.0
		draw_rect(Rect2(Vector2.ONE * inset, size - Vector2.ONE * inset * 2.0), Color(NIGHT, 0.022), false, 8.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = DRESSING_SEED + act
	for crumb in 65:
		var point := Vector2(rng.randf_range(16.0, size.x - 16.0), rng.randf_range(16.0, size.y - 16.0))
		var radius := rng.randf_range(0.7, 2.4)
		draw_circle(point + Vector2(2, 3), radius + 1.0, Color(NIGHT, 0.5))
		draw_circle(point, radius, Color(LAMP, rng.randf_range(0.12, 0.4)))
	if act == 1:
		# A saucer, cropped by the table edge, and its coffee ring.
		_draw_saucer(Vector2(size.x + 22, size.y * 0.67))
	elif act == 2:
		for screw in 5:
			var point := Vector2(size.x - 22 - screw * 15, size.y - 34 + (screw % 2) * 9)
			draw_circle(point + Vector2(3, 4), 6, Color(NIGHT, 0.7))
			draw_circle(point, 5, Color("a8a6a0"))
			draw_line(point - Vector2(3, 0), point + Vector2(3, 0), SKIN.INK, 2)
	else:
		SKIN.draw_tape(self, Vector2(size.x - 20, size.y * 0.4), Vector2(125, 28), -0.7, SKIN.CREAM)
		for line in 7:
			draw_line(Vector2(size.x - 46, size.y * 0.55 + line * 9), Vector2(size.x, size.y * 0.55 + line * 9), Color(SKIN.CREAM, 0.22), 1)


func _draw_saucer(center: Vector2) -> void:
	draw_circle(center + Vector2(8, 12), 104, Color(NIGHT, 0.6))
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
			SKIN.draw_plate(self, pad, Color("405752"), 18, 9)
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
	SKIN.draw_plate(self, rect, Color("71563c"), 5, 10)
	var face := rect.grow(-7)
	draw_rect(face, Color("26362f"))
	draw_rect(face.grow(-3), Color("83927d"), false, 1)
	for line in 4:
		var y := face.position.y + 15 + line * 39
		draw_line(Vector2(face.position.x + 12, y), Vector2(face.end.x - 12, y + 3), Color(SKIN.CREAM, 0.025), 3, true)
	SKIN.draw_tape(self, Vector2(20, -12), Vector2(68, 22), -0.13)
	SKIN.draw_tape(self, Vector2(extent.x - 18, -12), Vector2(68, 22), 0.15)
	var paper := Rect2(Vector2(-8, paper_y), Vector2(extent.x + 16, maxf(92.0, extent.y - paper_y + 10.0)))
	SKIN.draw_plate(self, paper, Color("e6dcc0"), 2, 7)
	for line in 9:
		var y := paper.position.y + 28 + line * 27
		if y > paper.end.y - 12.0:
			break
		draw_line(Vector2(paper.position.x + 14, y), Vector2(paper.end.x - 14, y), Color(SKIN.INK, 0.08), 1)
	SKIN.draw_tape(self, Vector2(extent.x * 0.76, paper_y), Vector2(84, 24), -0.09)


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


static func label_tape() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("27332f")
	style.set_content_margin_all(4)
	return style
