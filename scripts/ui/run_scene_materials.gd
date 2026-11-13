extends RefCounted

const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const CAR_SPRITES := preload("res://scripts/vendor/procedural_2d/procedural_car_sprites.gd")
const GRAIN := preload("res://assets/textures/edge_dressing/wood_grain_faint.png")
const FIBER := preload("res://assets/textures/edge_dressing/fiber_strand.png")
const SHADOW_CIRCLE := preload("res://assets/textures/edge_dressing/shadow_soft_circle.png")
const SHADOW_RECT := preload("res://assets/textures/edge_dressing/shadow_soft_rect.png")
const SHADOW_STRIP := preload("res://assets/textures/edge_dressing/shadow_strip.png")
const WRENCH := preload("res://assets/textures/workshop_hero/hero_workshop_wrench.png")
const MAT_GRAIN := preload("res://assets/textures/world_materials/workshop_mat.png")
const CARDBOARD := preload("res://assets/textures/ground_dressing/workshop_cardboard_scrap.png")
const TAPE_CORNER := preload("res://assets/textures/track_boundary/workshop_tape_corner.png")
const STICKY_CORNER := preload("res://assets/textures/track_boundary/office_sticky_corner.png")
const ROOM_DRESSING := {
	1: [preload("res://assets/textures/kitchen/crumb_cluster_01.png"), preload("res://assets/textures/kitchen/crumb_cluster_02.png")],
	2: [preload("res://assets/textures/edge_dressing/screw_small.png"), preload("res://assets/textures/edge_dressing/workshop_bolt_micro.png"), preload("res://assets/textures/edge_dressing/workshop_washer_micro.png"), preload("res://assets/textures/edge_dressing/workshop_nail_micro.png"), preload("res://assets/textures/grip_patches/sawdust_patch.png"), preload("res://assets/textures/grip_patches/workshop_metal_filings.png")],
	3: [preload("res://assets/textures/grip_patches/office_eraser_dust.png"), preload("res://assets/textures/edge_dressing/pencil_shaving.png")],
}
const HERO_PIXEL_SCALE := 6
const HERO_CACHE_LIMIT := 12
const BRUSH_SEED := 2426
const SHADOW_TINT := Color(0.015, 0.025, 0.045, 0.65)
const SUN_FREQUENCY := 4.6
const SUN_SLOPE := 0.55
const SUN_PHASE := 0.2
const SUN_RISE := Vector2(0.02, 0.16)
const SUN_FALL := Vector2(0.51, 0.72)
const CHALK_TILE_SCALE := 1.5
const CHALK_CORE_ALPHA := 0.5
const TOKEN_CONTACT_SPREAD := 1.16
const TOKEN_HIGHLIGHT := Color("fff3d6")
static var _brush: ImageTexture
static var _hero_cache: Dictionary = {}
static var _mote_shader: Shader


static func hero_texture(car_id: String) -> Texture2D:
	if not _hero_cache.has(car_id):
		while _hero_cache.size() >= HERO_CACHE_LIMIT:
			_hero_cache.erase(_hero_cache.keys()[0])
		_hero_cache[car_id] = CAR_SPRITES.car_texture(IDENTITIES.car_payload(car_id), HERO_PIXEL_SCALE)
	return _hero_cache[car_id]


static func chalk_brush() -> ImageTexture:
	if _brush == null:
		var noise := FastNoiseLite.new()
		noise.seed = BRUSH_SEED
		noise.frequency = 0.18
		noise.fractal_octaves = 3
		var image := noise.get_seamless_image(64, 16)
		image.convert(Image.FORMAT_RGBA8)
		for y in image.get_height():
			for x in image.get_width():
				var strength := image.get_pixel(x, y).r
				var edge := sin(PI * float(y) / float(image.get_height() - 1))
				image.set_pixel(x, y, Color(1, 1, 1, (0.35 + strength * 0.65) * edge))
		_brush = ImageTexture.create_from_image(image)
	return _brush


static func shadow(item: CanvasItem, rect: Rect2, round_shape: bool = false, strength: float = 1.0) -> void:
	item.draw_texture_rect(SHADOW_CIRCLE if round_shape else SHADOW_RECT, rect, false, Color(SHADOW_TINT, SHADOW_TINT.a * strength))


static func plate(item: CanvasItem, rect: Rect2, fill: Color, radius: int = 4) -> void:
	var spread := clampf(rect.size.y * 0.12, 2.0, 12.0)
	shadow(item, Rect2(rect.position + Vector2(2, 4) - Vector2.ONE * spread, rect.size + Vector2.ONE * spread * 2.0), false, 0.65)
	SKIN.draw_plate(item, rect, fill, radius, 0)


static func grain(item: CanvasItem, rect: Rect2, chalk: bool = false) -> void:
	item.draw_texture_rect(GRAIN, rect, false, Color(0.09, 0.15, 0.12, 0.045) if chalk else Color(1.0, 0.9, 0.75, 0.06))
	item.draw_texture_rect(FIBER, Rect2(rect.position + Vector2(8, rect.size.y * 0.6), Vector2(rect.size.x * 0.5, 12)), false, Color(0.8, 0.76, 0.58, 0.08))
	if chalk:
		for stroke in 3:
			var mark := Rect2(rect.position + Vector2(14 + stroke * 47, 23 + stroke * 42), Vector2(rect.size.x * 0.42, 13))
			item.draw_texture_rect(SHADOW_STRIP, mark, false, Color(0.9, 0.93, 0.79, 0.045))


static func finish_panel(panel: PanelContainer, chalk: bool = false) -> void:
	var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	style.shadow_size = 0
	panel.draw.connect(func() -> void:
		var rect := Rect2(Vector2.ZERO, panel.size)
		shadow(panel, rect.grow(15))
		panel.draw_style_box(style, rect)
		grain(panel, rect.grow(-7), chalk))


static func finish_button(button: Button) -> void:
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		(button.get_theme_stylebox(state) as StyleBoxFlat).shadow_size = 0
	button.draw.connect(func() -> void:
		var style := button.get_theme_stylebox("disabled" if button.disabled else "normal") as StyleBoxFlat
		button.draw_texture_rect(SHADOW_STRIP, Rect2(Vector2(-3, button.size.y - 3), Vector2(button.size.x + 14, style.shadow_offset.y * 3 + 5)), false, SHADOW_TINT)
		grain(button, Rect2(Vector2(4, 4), button.size - Vector2(8, 8))))


## A chalk/tape stroke. The brush is tiled at its own scale, so its alpha noise
## breaks the stroke up along its length, over a thin solid core that keeps the
## connection continuous.
static func chalk_line(item: CanvasItem, from: Vector2, to: Vector2, tint: Color, width: float = 6.0) -> void:
	var length := from.distance_to(to)
	if length <= 0.0:
		return
	var brush := chalk_brush()
	var span := float(brush.get_width()) * CHALK_TILE_SCALE
	item.draw_set_transform(from, (to - from).angle())
	item.draw_line(Vector2.ZERO, Vector2(length, 0), Color(tint, tint.a * CHALK_CORE_ALPHA), maxf(1.0, width * 0.25), true)
	var at := 0.0
	while at < length:
		var step := minf(span, length - at)
		var source := Rect2(0, 0, step / CHALK_TILE_SCALE, brush.get_height())
		item.draw_texture_rect_region(brush, Rect2(at, -width * 0.5, step, width), source, tint)
		at += span
	item.draw_set_transform(Vector2.ZERO)


## A round tabletop token lit from the upper left: a soft ambient shadow and a
## tight contact shadow, a narrow shaded side wall below the face, the rim in
## `rim` at `rim_width`, and a lamp highlight on its upper-left edge at
## `highlight` strength. Lifting raises the face and lets the contact shadow
## spread and fade. Returns the face centre.
static func token(item: CanvasItem, center: Vector2, radius: float, face: Color, edge: Color, rim: Color, depth: float, lift: float = 0.0, rim_width: float = 2.0, highlight: float = 1.0) -> Vector2:
	shadow(item, Rect2(center + Vector2(3, 5) - Vector2.ONE * radius * 1.35, Vector2.ONE * radius * 2.7), true, 0.4)
	var contact := radius * TOKEN_CONTACT_SPREAD + lift * 1.5
	item.draw_texture_rect(SHADOW_CIRCLE, Rect2(center + Vector2(1, depth + 1) - Vector2.ONE * contact, Vector2.ONE * contact * 2.0), false, Color(SHADOW_TINT, 0.95 - lift * 0.12))
	var top := center - Vector2(0, lift)
	# The side wall: dark where it meets the table, a step lighter under the face.
	item.draw_circle(top + Vector2(0, depth), radius, edge)
	item.draw_circle(top + Vector2(0, depth * 0.5), radius, edge.lerp(face, 0.45))
	item.draw_circle(top, radius, face)
	item.draw_arc(top, radius - 2.5, PI * 0.15, PI * 0.85, 32, Color(0, 0, 0, 0.3), 2.5, true)
	item.draw_arc(top, radius - 1.0, 0, TAU, 48, rim, rim_width, true)
	item.draw_arc(top, radius - 0.6, PI * 1.02, PI * 1.58, 24, Color(TOKEN_HIGHLIGHT, 0.75 * highlight), 1.4, true)
	item.draw_arc(top, radius - 3.2, PI * 1.08, PI * 1.5, 20, Color(TOKEN_HIGHLIGHT, 0.4 * highlight), 1.0, true)
	return top


static func add_room_dressing(parent: Control, act: int, seed_value: int, enabled: bool = true) -> Control:
	var group := Control.new()
	group.name = "RoomDressing"
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(group)
	if not enabled:
		return group
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + act
	var textures: Array = ROOM_DRESSING[act]
	for index in 18:
		var prop := TextureRect.new()
		prop.name = "PaintedDressing%d" % index
		prop.texture = textures[index % textures.size()]
		prop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		prop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		prop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var extent := rng.randf_range(20, 37)
		prop.size = Vector2.ONE * extent
		prop.pivot_offset = prop.size * 0.5
		prop.rotation = rng.randf_range(-PI, PI)
		prop.position = Vector2(rng.randf_range(18, 1190), rng.randf_range(20, 650))
		prop.modulate.a = 0.7
		group.add_child(prop)
	return group


static func sunlight_shader() -> String:
	return """float sun_beam(vec2 uv) {
		float stripe = fract((uv.x - uv.y * %s + %s) * %s);
		return smoothstep(%s, %s, stripe) * (1.0 - smoothstep(%s, %s, stripe));
	}""" % [SUN_SLOPE, SUN_PHASE, SUN_FREQUENCY, SUN_RISE.x, SUN_RISE.y, SUN_FALL.x, SUN_FALL.y]


static func beam_strength(uv: Vector2, sunrise: bool, origin_uv: Vector2 = Vector2.ZERO) -> float:
	if sunrise:
		var stripe := fposmod((uv.x - uv.y * SUN_SLOPE + SUN_PHASE) * SUN_FREQUENCY, 1.0)
		return smoothstep(SUN_RISE.x, SUN_RISE.y, stripe) * (1.0 - smoothstep(SUN_FALL.x, SUN_FALL.y, stripe))
	return 1.0 - smoothstep(0.015, 0.11, uv.distance_to(origin_uv))


static func _dust_shader() -> Shader:
	if _mote_shader == null:
		_mote_shader = Shader.new()
		_mote_shader.code = "shader_type canvas_item;\n" + sunlight_shader() + """
		uniform vec2 scene_size;
		uniform vec2 beam_origin;
		uniform bool sunrise = false;
		varying vec2 canvas_position;
		void vertex() { canvas_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; }
		void fragment() {
			vec2 uv = canvas_position / scene_size;
			float mask = sunrise ? sun_beam(uv) : 1.0 - smoothstep(0.015, 0.11, length(uv - beam_origin));
			COLOR = texture(TEXTURE, UV) * COLOR;
			COLOR.a *= mask;
		}"""
	return _mote_shader


static func add_beam_dust(parent: Control, origin: Vector2, reduced: bool, sunrise: bool = false) -> Control:
	var group := Control.new()
	group.name = "BeamDust"
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(group)
	if reduced:
		return group
	var rng := RandomNumberGenerator.new()
	rng.seed = BRUSH_SEED
	for index in 3:
		var mote := TextureRect.new()
		mote.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mote.texture = SHADOW_CIRCLE
		mote.size = Vector2.ONE * rng.randf_range(2, 4)
		mote.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mote.modulate = Color(1, 0.91, 0.76, 0.14)
		var start := origin + Vector2(rng.randf_range(-32, 42), rng.randf_range(10, 50))
		if sunrise:
			for attempt in 64:
				var candidate := Vector2(rng.randf_range(0.08, 0.44), rng.randf_range(0.12, 0.65)) * parent.size
				if beam_strength(candidate / parent.size, true) > 0.9 and beam_strength((candidate + Vector2(4, -16)) / parent.size, true) > 0.9:
					start = candidate
					break
		var mask := ShaderMaterial.new()
		mask.shader = _dust_shader()
		mask.set_shader_parameter("scene_size", parent.size)
		mask.set_shader_parameter("beam_origin", origin / parent.size)
		mask.set_shader_parameter("sunrise", sunrise)
		mote.material = mask
		mote.set_meta("beam_start", start)
		mote.set_meta("beam_end", start + Vector2(4, -16))
		mote.position = start
		group.add_child(mote)
		var drift := mote.create_tween().set_loops()
		drift.tween_property(mote, "position", start + Vector2(4, -16), 5.0 + index)
		drift.tween_property(mote, "position", start, 0.0)
	return group


static func paint_wear(item: CanvasItem, rect: Rect2, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for patch in 3:
		var extent := rect.size * Vector2(rng.randf_range(0.3, 0.6), rng.randf_range(0.2, 0.4))
		var point := rect.position + (rect.size - extent) * Vector2(rng.randf(), rng.randf())
		item.draw_texture_rect(SHADOW_RECT, Rect2(point, extent), false, Color(0.98, 0.88, 0.66, 0.045))
	for nick in 4:
		var at := rect.position + Vector2(rect.size.x * float(nick + 1) / 5.0, 1)
		item.draw_line(at, at + Vector2(minf(7.0, rect.size.x * 0.1), 0), Color(0.95, 0.9, 0.74, 0.16), 1.0, true)
