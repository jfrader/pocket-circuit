extends RefCounted

const INK := Color("1a1f23")
const VOID := Color("111316")
const WOOD_DEEP := Color("3f2a22")
const WOOD := Color("5c4638")
const WOOD_EDGE := Color("8c6f55")
const ASPHALT := Color("2a2f33")
const ORANGE := Color("e85a2e")
const YELLOW := Color("f4c65a")
const LIME := Color("2e8b57")
const RED := Color("c81e2e")
const BLUE := Color("4a8fb8")
const CREAM := Color("f5f0e3")
const CREAM_DIM := Color(CREAM, 0.72)
const INK_SOFT := Color(INK, 0.62)
const SHADOW_TINT := Color(INK, 0.6)
const TAPE := Color(YELLOW, 0.86)

const SHADOW := 4.0
const PRESS := SHADOW - 1.0
const LINE := 3.0
const RADIUS := 10
const PLATE_SIZE := 48
const PLATE_MARGIN := 13.0
const PLANK_HEIGHT := 60.0
const BENCH_LIP := 30.0
const RULER_TICK := 16.0
const BUTTON_STATES: Array[String] = ["normal", "hover", "pressed", "hover_pressed", "disabled"]
const TOGGLE_ICONS := {
	"checked": [true, false],
	"checked_mirrored": [true, false],
	"checked_disabled": [true, true],
	"checked_disabled_mirrored": [true, true],
	"unchecked": [false, false],
	"unchecked_mirrored": [false, false],
	"unchecked_disabled": [false, true],
	"unchecked_disabled_mirrored": [false, true],
}

static var _svg_cache: Dictionary = {}
static var _flat_cache: Dictionary = {}
static var _display_font: FontVariation
static var _lamp_pool: GradientTexture2D
static var _column_shade: GradientTexture2D


static func display_font() -> Font:
	if _display_font == null:
		_display_font = FontVariation.new()
		_display_font.base_font = ThemeDB.fallback_font
		_display_font.variation_embolden = 0.9
		_display_font.spacing_glyph = 1
	return _display_font


static func plate_texture(pressed: bool) -> Texture2D:
	var inset := 1.5 + (PRESS if pressed else 0.0)
	var side := PLATE_SIZE - SHADOW - 3.0
	return _svg("plate_pressed" if pressed else "plate", (
		"<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d'>" % [PLATE_SIZE, PLATE_SIZE]
		+ "<rect x='%.1f' y='%.1f' width='%.1f' height='%.1f' rx='%d' fill='#%s'/>" % [1.5 + SHADOW, 1.5 + SHADOW, side, side, RADIUS, INK.to_html(false)]
		+ "<rect x='%.1f' y='%.1f' width='%.1f' height='%.1f' rx='%d' fill='#ffffff' stroke='#%s' stroke-width='%.1f'/>" % [inset, inset, side, side, RADIUS, INK.to_html(false), LINE]
		+ "</svg>"
	))


static func plate_color(primary: bool, state: String) -> Color:
	match state:
		"hover":
			return ORANGE if primary else CREAM.lerp(YELLOW, 0.55)
		"pressed", "hover_pressed":
			return ORANGE.darkened(0.12) if primary else YELLOW.darkened(0.08)
		"disabled":
			return WOOD_EDGE
	return YELLOW if primary else CREAM


static func panel(primary: bool, state: String = "normal") -> StyleBoxTexture:
	var push := PRESS if state in ["pressed", "hover_pressed"] else 0.0
	var style := StyleBoxTexture.new()
	style.texture = plate_texture(push > 0.0)
	_set_plate_margins(style)
	style.modulate_color = plate_color(primary, state)
	style.content_margin_left = (46.0 if primary else 18.0) + push
	style.content_margin_right = 18.0 + SHADOW - push
	style.content_margin_top = 6.0 + push
	style.content_margin_bottom = 6.0 + SHADOW - push
	return style


static func card_style(fill: Color, padding: float = 20.0) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = plate_texture(false)
	_set_plate_margins(style)
	style.modulate_color = fill
	style.content_margin_left = padding
	style.content_margin_top = padding
	style.content_margin_right = padding + SHADOW
	style.content_margin_bottom = padding + SHADOW
	return style


static func tape_style(fill: Color = YELLOW) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(2)
	style.skew = Vector2(0.18, 0.0)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style


static func focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = ORANGE
	style.set_border_width_all(4)
	style.set_corner_radius_all(RADIUS + 5)
	style.set_expand_margin_all(5.0)
	style.expand_margin_right = 6.0 - SHADOW
	style.expand_margin_bottom = 6.0 - SHADOW
	return style


static func apply_button(button: Button, primary: bool) -> void:
	for state: String in BUTTON_STATES:
		button.add_theme_stylebox_override(state, panel(primary, state))
	button.add_theme_stylebox_override("focus", focus_style())
	button.add_theme_font_override("font", display_font())
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_hover_color", CREAM if primary else ORANGE.darkened(0.3))
	button.add_theme_color_override("font_hover_pressed_color", CREAM if primary else INK)
	button.add_theme_color_override("font_disabled_color", Color(INK, 0.55))
	button.add_theme_color_override("font_outline_color", INK)
	button.add_theme_constant_override("outline_size", 4 if primary else 0)
	button.add_theme_color_override("icon_disabled_color", Color(INK, 0.88))
	if button.has_method("set_art_role"):
		button.call("set_art_role", primary)


static func style_label(label: Label, font_size: int, color: Color = CREAM, display: bool = false) -> Label:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if display:
		label.add_theme_font_override("font", display_font())
	if color.get_luminance() > 0.45:
		label.add_theme_color_override("font_outline_color", INK)
		label.add_theme_constant_override("outline_size", _outline_for(font_size))
		if display:
			var drop := clampi(roundi(font_size / 14.0), 2, 6)
			label.add_theme_color_override("font_shadow_color", INK)
			label.add_theme_constant_override("shadow_offset_x", drop)
			label.add_theme_constant_override("shadow_offset_y", drop)
			label.add_theme_constant_override("shadow_outline_size", _outline_for(font_size))
	else:
		label.add_theme_constant_override("outline_size", 0)
	return label


static func style_tape(label: Label, fill: Color = YELLOW, font_size: int = 14) -> Label:
	style_label(label, font_size, INK, true)
	label.add_theme_stylebox_override("normal", tape_style(fill))
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.uppercase = true
	return label


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.set_color("font_color", "Label", CREAM)
	theme.set_color("font_outline_color", "Label", INK)
	theme.set_constant("outline_size", "Label", 3)
	for kind: String in ["Button", "OptionButton", "CheckButton"]:
		for state: String in BUTTON_STATES:
			var style := panel(false, state)
			if kind == "CheckButton":
				style.content_margin_right = 10.0 + SHADOW
			theme.set_stylebox(state, kind, style)
		theme.set_stylebox("focus", kind, focus_style())
		theme.set_font("font", kind, display_font())
		theme.set_font_size("font_size", kind, 18)
		theme.set_color("font_color", kind, INK)
		theme.set_color("font_focus_color", kind, INK)
		theme.set_color("font_pressed_color", kind, INK)
		theme.set_color("font_hover_color", kind, ORANGE.darkened(0.3))
		theme.set_color("font_hover_pressed_color", kind, INK)
		theme.set_color("font_disabled_color", kind, Color(INK, 0.55))
	theme.set_icon("arrow", "OptionButton", _chevron())
	theme.set_constant("arrow_margin", "OptionButton", 12)
	for icon: String in TOGGLE_ICONS:
		var toggle: Array = TOGGLE_ICONS[icon]
		theme.set_icon(icon, "CheckButton", _toggle(bool(toggle[0]), bool(toggle[1])))
	var groove := _flat(ASPHALT, INK, 7, 2).duplicate() as StyleBoxFlat
	groove.content_margin_top = 8.0
	groove.content_margin_bottom = 8.0
	theme.set_stylebox("slider", "HSlider", groove)
	theme.set_stylebox("grabber_area", "HSlider", _flat(ORANGE, INK, 7, 2))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _flat(YELLOW, INK, 7, 2))
	theme.set_icon("grabber", "HSlider", _knob(CREAM))
	theme.set_icon("grabber_highlight", "HSlider", _knob(YELLOW))
	theme.set_icon("grabber_disabled", "HSlider", _knob(WOOD_EDGE))
	theme.set_stylebox("focus", "HSlider", focus_style())
	theme.set_stylebox("normal", "LineEdit", card_style(CREAM, 8.0))
	theme.set_stylebox("read_only", "LineEdit", card_style(CREAM.darkened(0.08), 8.0))
	theme.set_stylebox("focus", "LineEdit", focus_style())
	theme.set_font("font", "LineEdit", display_font())
	theme.set_font_size("font_size", "LineEdit", 17)
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_uneditable_color", "LineEdit", Color(INK, 0.8))
	theme.set_color("font_placeholder_color", "LineEdit", Color(INK, 0.45))
	theme.set_color("font_selected_color", "LineEdit", INK)
	theme.set_color("selection_color", "LineEdit", Color(YELLOW, 0.7))
	theme.set_color("caret_color", "LineEdit", ORANGE)
	theme.set_stylebox("panel", "PopupMenu", card_style(CREAM, 8.0))
	theme.set_stylebox("hover", "PopupMenu", _flat(YELLOW, YELLOW, 6, 0))
	theme.set_font("font", "PopupMenu", display_font())
	theme.set_font_size("font_size", "PopupMenu", 17)
	theme.set_color("font_color", "PopupMenu", INK)
	theme.set_color("font_hover_color", "PopupMenu", INK)
	theme.set_icon("radio_checked", "PopupMenu", _dot(true))
	theme.set_icon("radio_unchecked", "PopupMenu", _dot(false))
	return theme


static func workbench_backdrop() -> Control:
	var backdrop := Control.new()
	backdrop.name = "Workbench"
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.draw.connect(func() -> void: draw_workbench(backdrop, Rect2(Vector2.ZERO, backdrop.size)))
	backdrop.resized.connect(backdrop.queue_redraw)
	return backdrop


static func draw_workbench(item: CanvasItem, rect: Rect2) -> void:
	item.draw_rect(rect, VOID)
	var plank_index := 0
	var top := rect.position.y
	while top < rect.end.y:
		_draw_plank(item, Rect2(rect.position.x, top, rect.size.x, PLANK_HEIGHT), plank_index)
		top += PLANK_HEIGHT
		plank_index += 1
	var pool_center := rect.position + rect.size * Vector2(0.72, 0.42)
	var pool_size := Vector2(rect.size.x * 0.78, rect.size.y * 1.15)
	item.draw_texture_rect(_lamp_pool_texture(), Rect2(pool_center - pool_size * 0.5, pool_size), false)
	item.draw_texture_rect(_column_shade_texture(), Rect2(rect.position, Vector2(rect.size.x * 0.55, rect.size.y)), false)
	_draw_bench_lip(item, Rect2(rect.position.x, rect.end.y - BENCH_LIP, rect.size.x, BENCH_LIP))
	_draw_lamp(item, Vector2(rect.end.x - 70.0, rect.position.y - 6.0))


static func draw_plate(item: CanvasItem, rect: Rect2, fill: Color = CREAM, radius: int = RADIUS, shadow: float = SHADOW) -> void:
	if shadow > 0.0:
		item.draw_style_box(_flat(INK, INK, radius, 0), Rect2(rect.position + Vector2(shadow, shadow), rect.size))
	item.draw_style_box(_flat(fill, INK, radius, int(LINE)), rect)


static func draw_disc(item: CanvasItem, center: Vector2, radius: float, fill: Color, shadow: float = SHADOW) -> void:
	if shadow > 0.0:
		item.draw_circle(center + Vector2(shadow, shadow), radius + LINE, SHADOW_TINT)
	item.draw_circle(center, radius + LINE, INK)
	item.draw_circle(center, radius, fill)


static func draw_checker(item: CanvasItem, rect: Rect2, cell: float, dark: Color = INK, light: Color = CREAM) -> void:
	item.draw_rect(rect, light)
	var columns := ceili(rect.size.x / cell)
	var rows := ceili(rect.size.y / cell)
	for row in rows:
		for column in columns:
			if (row + column) % 2 == 0:
				var square := Rect2(rect.position + Vector2(column, row) * cell, Vector2.ONE * cell).intersection(rect)
				item.draw_rect(square, dark)


static func draw_grid(item: CanvasItem, rect: Rect2, cell: float, color: Color = Color(BLUE, 0.15)) -> void:
	var x := rect.position.x + cell
	while x < rect.end.x:
		item.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), color, 1.0)
		x += cell
	var y := rect.position.y + cell
	while y < rect.end.y:
		item.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), color, 1.0)
		y += cell


static func draw_flag(item: CanvasItem, rect: Rect2, cell: float, dark: Color = INK) -> void:
	draw_checker(item, rect, cell, dark)
	item.draw_rect(rect, INK, false, 2.0)


static func draw_tube(item: CanvasItem, rect: Rect2, ratio: float, fill: Color = ORANGE, highlight: Color = YELLOW) -> void:
	var radius := roundi(rect.size.y * 0.5)
	draw_plate(item, rect, ASPHALT, radius, 2.0)
	var inner := rect.grow(-LINE - 1.0)
	var filled := Rect2(inner.position, Vector2(inner.size.x * clampf(ratio, 0.0, 1.0), inner.size.y))
	if filled.size.x < 2.0:
		return
	item.draw_style_box(_flat(fill, fill, roundi(inner.size.y * 0.5), 0), filled)
	var glint := maxf(2.0, inner.size.y * 0.18)
	var glint_y := filled.position.y + inner.size.y * 0.32
	var glint_inset := inner.size.y * 0.4
	if filled.size.x > glint_inset * 2.0:
		item.draw_line(Vector2(filled.position.x + glint_inset, glint_y), Vector2(filled.end.x - glint_inset, glint_y), highlight, glint, true)
	var ticks := 4
	for tick in ticks:
		var x := inner.position.x + inner.size.x * float(tick + 1) / float(ticks + 1)
		item.draw_line(Vector2(x, inner.position.y + 2.0), Vector2(x, inner.position.y + inner.size.y * 0.28), Color(CREAM, 0.7), 2.0)
	if ratio > 0.08:
		item.draw_circle(Vector2(filled.end.x - inner.size.y * 0.35, inner.get_center().y), inner.size.y * 0.22, highlight)


static func draw_tape(item: CanvasItem, center: Vector2, tape_size: Vector2, angle: float = 0.0, fill: Color = TAPE) -> void:
	var half := tape_size * 0.5
	var teeth := 4
	var points := PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y)])
	for tooth in range(1, teeth):
		points.append(Vector2(half.x + (3.0 if tooth % 2 == 1 else -2.0), -half.y + tape_size.y * float(tooth) / float(teeth)))
	points.append(Vector2(half.x, half.y))
	points.append(Vector2(-half.x, half.y))
	for tooth in range(teeth - 1, 0, -1):
		points.append(Vector2(-half.x + (-3.0 if tooth % 2 == 1 else 2.0), -half.y + tape_size.y * float(tooth) / float(teeth)))
	for index in points.size():
		points[index] = center + points[index].rotated(angle)
	item.draw_colored_polygon(points, fill)


static func draw_padlock(item: CanvasItem, center: Vector2, lock_size: float = 14.0) -> void:
	var shackle := center + Vector2(0.0, -lock_size * 0.12)
	item.draw_arc(shackle, lock_size * 0.3, PI, TAU, 12, INK, lock_size * 0.22 + LINE, true)
	item.draw_arc(shackle, lock_size * 0.3, PI, TAU, 12, CREAM, lock_size * 0.14, true)
	var body := Rect2(center + Vector2(-lock_size * 0.5, -lock_size * 0.14), Vector2(lock_size, lock_size * 0.72))
	draw_plate(item, body, YELLOW, 3, 2.0)
	item.draw_circle(body.get_center(), lock_size * 0.1, INK)


static func draw_text(
		item: CanvasItem,
		text_position: Vector2,
		text: String,
		font_size: int,
		color: Color,
		width: float = -1.0,
		alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
		display: bool = true
) -> void:
	var font := display_font() if display else ThemeDB.fallback_font
	if color.get_luminance() > 0.45:
		var outline := _outline_for(font_size)
		if display and font_size >= 24:
			var drop := Vector2.ONE * clampi(roundi(font_size / 14.0), 2, 6)
			item.draw_string_outline(font, text_position + drop, text, alignment, width, font_size, outline, INK)
		item.draw_string_outline(font, text_position, text, alignment, width, font_size, outline, INK)
	item.draw_string(font, text_position, text, alignment, width, font_size, color)


static func draw_tag(item: CanvasItem, rect: Rect2, text: String, fill: Color = CREAM, font_size: int = 14) -> void:
	draw_plate(item, rect, fill, 6, 3.0)
	item.draw_circle(rect.position + Vector2(12.0, rect.size.y * 0.5), 3.5, INK)
	draw_text(item, rect.position + Vector2(22.0, rect.size.y * 0.5 + font_size * 0.36), text, font_size, INK, rect.size.x - 30.0)


static func _outline_for(font_size: int) -> int:
	return clampi(roundi(font_size / 5.0), 3, 12)


static func _draw_plank(item: CanvasItem, plank: Rect2, plank_index: int) -> void:
	item.draw_rect(plank, WOOD_DEEP.lerp(WOOD, 0.08 + 0.07 * float(plank_index % 3)).darkened(0.32))
	for grain in 3:
		var points := PackedVector2Array()
		var phase := float(plank_index * 3 + grain) * 1.37
		var base_y := plank.position.y + plank.size.y * (0.22 + 0.28 * float(grain))
		for step in 25:
			var x := plank.position.x + plank.size.x * float(step) / 24.0
			points.append(Vector2(x, base_y + sin(x * 0.011 + phase) * 3.0 + sin(x * 0.037 + phase * 2.0) * 1.2))
		item.draw_polyline(points, Color(WOOD_EDGE, 0.1), 1.5, true)
	var joint := plank.position.x + fposmod(float(plank_index) * 467.0 + 180.0, plank.size.x)
	item.draw_line(Vector2(joint, plank.position.y), Vector2(joint, plank.end.y), Color(INK, 0.55), 2.0)
	item.draw_line(plank.position, Vector2(plank.end.x, plank.position.y), Color(INK, 0.7), 2.0)
	item.draw_line(plank.position + Vector2(0.0, 2.0), Vector2(plank.end.x, plank.position.y + 2.0), Color(WOOD_EDGE, 0.12), 1.0)


static func _draw_bench_lip(item: CanvasItem, lip: Rect2) -> void:
	item.draw_rect(Rect2(lip.position + Vector2(0.0, -SHADOW * 2.0), Vector2(lip.size.x, SHADOW * 2.0)), Color(INK, 0.35))
	item.draw_rect(lip, WOOD.darkened(0.12))
	item.draw_rect(Rect2(lip.position, Vector2(lip.size.x, 4.0)), WOOD_EDGE)
	item.draw_line(lip.position, Vector2(lip.end.x, lip.position.y), INK, LINE)
	var tick := 0
	var x := lip.position.x + RULER_TICK
	while x < lip.end.x:
		var length := 11.0 if tick % 4 == 3 else 5.0
		item.draw_line(Vector2(x, lip.position.y + 4.0), Vector2(x, lip.position.y + 4.0 + length), Color(INK, 0.5), 2.0)
		x += RULER_TICK
		tick += 1
	item.draw_rect(Rect2(lip.position.x, lip.end.y - 6.0, lip.size.x, 6.0), Color(INK, 0.45))


static func _draw_lamp(item: CanvasItem, head: Vector2) -> void:
	var offset := Vector2.ONE * SHADOW * 3.0
	var arm_end := head + Vector2(150.0, -120.0)
	item.draw_line(head + offset, arm_end + offset, SHADOW_TINT, 16.0)
	item.draw_line(head, arm_end, INK, 16.0)
	item.draw_line(head, arm_end, BLUE.darkened(0.45), 10.0)
	item.draw_circle(head + offset, 74.0, SHADOW_TINT)
	item.draw_circle(head, 74.0, INK)
	item.draw_circle(head, 70.0, BLUE.darkened(0.35))
	item.draw_arc(head, 58.0, PI * 0.55, PI * 1.25, 18, Color(CREAM, 0.35), 6.0, true)
	item.draw_circle(head, 30.0, INK)
	item.draw_circle(head, 26.0, BLUE.darkened(0.55))


static func _flat(fill: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var key := "%s|%s|%d|%d" % [fill.to_html(), border.to_html(), radius, border_width]
	if not _flat_cache.has(key):
		var style := StyleBoxFlat.new()
		style.bg_color = fill
		style.border_color = border
		style.set_border_width_all(border_width)
		style.set_corner_radius_all(radius)
		style.anti_aliasing = true
		_flat_cache[key] = style
	return _flat_cache[key]


static func _set_plate_margins(style: StyleBoxTexture) -> void:
	style.texture_margin_left = PLATE_MARGIN
	style.texture_margin_top = PLATE_MARGIN
	style.texture_margin_right = PLATE_MARGIN + SHADOW
	style.texture_margin_bottom = PLATE_MARGIN + SHADOW


static func _svg(key: String, svg: String) -> Texture2D:
	if not _svg_cache.has(key):
		var image := Image.new()
		if image.load_svg_from_buffer(svg.to_utf8_buffer(), 1.0) != OK:
			push_error("Workbench skin could not render '%s'." % key)
			return null
		_svg_cache[key] = ImageTexture.create_from_image(image)
	return _svg_cache[key]


static func _toggle(on: bool, disabled: bool) -> Texture2D:
	var track := (ORANGE if on else ASPHALT) if not disabled else WOOD_EDGE
	var knob_x := 32.0 if on else 14.0
	return _svg("toggle_%s_%s" % [on, disabled], (
		"<svg xmlns='http://www.w3.org/2000/svg' width='48' height='30'>"
		+ "<rect x='3' y='5' width='42' height='22' rx='11' fill='#%s' stroke='#%s' stroke-width='3'/>" % [track.to_html(false), INK.to_html(false)]
		+ "<circle cx='%.1f' cy='16' r='9' fill='#%s' stroke='#%s' stroke-width='3'/>" % [knob_x, CREAM.to_html(false), INK.to_html(false)]
		+ "</svg>"
	))


static func _knob(fill: Color) -> Texture2D:
	return _svg("knob_%s" % fill.to_html(false), (
		"<svg xmlns='http://www.w3.org/2000/svg' width='28' height='28'>"
		+ "<circle cx='15' cy='15' r='11' fill='#%s'/>" % INK.to_html(false)
		+ "<circle cx='13' cy='13' r='10.5' fill='#%s' stroke='#%s' stroke-width='3'/>" % [fill.to_html(false), INK.to_html(false)]
		+ "</svg>"
	))


static func _chevron() -> Texture2D:
	return _svg("chevron", (
		"<svg xmlns='http://www.w3.org/2000/svg' width='20' height='14'>"
		+ "<path d='M3 3 L10 10 L17 3' fill='none' stroke='#%s' stroke-width='3.5' stroke-linecap='round' stroke-linejoin='round'/>" % INK.to_html(false)
		+ "</svg>"
	))


static func _dot(on: bool) -> Texture2D:
	return _svg("dot_%s" % on, (
		"<svg xmlns='http://www.w3.org/2000/svg' width='18' height='18'>"
		+ "<circle cx='9' cy='9' r='6.5' fill='#%s' stroke='#%s' stroke-width='2.5'/>" % [(ORANGE if on else CREAM).to_html(false), INK.to_html(false)]
		+ "</svg>"
	))


static func _lamp_pool_texture() -> GradientTexture2D:
	if _lamp_pool == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		gradient.colors = PackedColorArray([Color(YELLOW, 0.3), Color(ORANGE, 0.1), Color(ORANGE, 0.0)])
		_lamp_pool = GradientTexture2D.new()
		_lamp_pool.gradient = gradient
		_lamp_pool.fill = GradientTexture2D.FILL_RADIAL
		_lamp_pool.fill_from = Vector2(0.5, 0.5)
		_lamp_pool.fill_to = Vector2(1.0, 0.5)
		_lamp_pool.width = 256
		_lamp_pool.height = 256
	return _lamp_pool


static func _column_shade_texture() -> GradientTexture2D:
	if _column_shade == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
		gradient.colors = PackedColorArray([Color(VOID, 0.6), Color(VOID, 0.35), Color(VOID, 0.0)])
		_column_shade = GradientTexture2D.new()
		_column_shade.gradient = gradient
		_column_shade.width = 256
		_column_shade.height = 4
	return _column_shade
