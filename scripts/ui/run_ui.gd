extends RefCounted

const BG := Color("0a0c10")
const PANEL := Color("0e1218")
const LINE := Color("232d3a")
const INK := Color("e9ecf1")
const MUTED := Color("8b95a5")
const DIM := Color("5a6577")
const AMBER := Color("f2a53c")
const BOSS_EDGE := Color("674b29")
const LIVE_EDGE := Color("657587")
const ROOMS := {1: "Kitchen Counter", 2: "Workshop Bench", 3: "Office Desk"}
const TYPES := {
	"race": {"name": "Race", "cost": "wear", "copy": "Four cars, a rolled circuit. The filler, and the place you test a build.", "icon": preload("res://assets/ui/run_map/node_race.svg")},
	"rival": {"name": "Rival", "cost": "points or wear", "copy": "One-on-one, contact. The reliable source of a car.", "icon": preload("res://assets/ui/run_map/node_rival.svg")},
	"bench": {"name": "Bench", "cost": "the visit", "copy": "No race. Repair the car, or fit one part. Never both.", "icon": preload("res://assets/ui/run_map/node_bench.svg")},
	"parts_van": {"name": "Parts van", "cost": "points", "copy": "No race. Spend points on parts.", "icon": preload("res://assets/ui/run_map/node_parts_van.svg")},
	"lockup": {"name": "Lockup", "cost": "free", "copy": "No race. A free car, no fight. Rare, and fought over.", "icon": preload("res://assets/ui/run_map/node_lockup.svg")},
	"errand": {"name": "Errand", "cost": "varies", "copy": "A choice, no race. The cast wants something; it has a price.", "icon": preload("res://assets/ui/run_map/node_errand.svg")},
	"act_rival": {"name": "Act rival", "cost": "the run", "copy": "A generated driver carrying the act's hardest AI profile. One race decides the act.", "icon": preload("res://assets/ui/run_map/node_boss.svg")},
}
const VAN_PARTS := [["TOOL KIT", 8], ["TYRE SET", 15], ["SPARE SHELL", 25]]
const CURRENT_RING := preload("res://assets/ui/run_map/ring_current.svg")

static var _mono: FontVariation


static func label(text: String, font_size: int = 16, color: Color = INK, mono: bool = false) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_override("font", mono_font() if mono else ThemeDB.fallback_font)
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	result.add_theme_constant_override("outline_size", 0)
	result.add_theme_constant_override("shadow_outline_size", 0)
	result.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	return result


static func mono_font() -> Font:
	if _mono == null:
		var base := SystemFont.new()
		base.font_names = PackedStringArray(["DejaVu Sans Mono", "Consolas", "Menlo", "monospace"])
		_mono = FontVariation.new()
		_mono.base_font = base
		_mono.spacing_glyph = 1
	return _mono


static func spacer(parent: Node, height: float) -> void:
	var space := Control.new()
	space.custom_minimum_size.y = height
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(space)


static func divider(parent: Node) -> void:
	var line := ColorRect.new()
	line.color = LINE
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)


static func icon(kind: String, extent: float = 28.0) -> TextureRect:
	var image := TextureRect.new()
	image.texture = TYPES[kind]["icon"] as Texture2D
	image.custom_minimum_size = Vector2.ONE * extent
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image


static func stats(host: VBoxContainer, session: RunSession) -> void:
	var parent := VBoxContainer.new()
	parent.add_theme_constant_override("separation", 4)
	host.add_child(parent)
	divider(parent)
	spacer(parent, 4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 38)
	parent.add_child(row)
	for entry: Array in [["POINTS", str(session.run_points)], ["OWNED", str(session.owned_cars.size())]]:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		row.add_child(column)
		column.add_child(label(String(entry[0]), 11, MUTED, true))
		column.add_child(label(String(entry[1]), 28))
	spacer(parent, 6)
	parent.add_child(label("CURRENT CAR", 11, MUTED, true))
	var wear := "?"
	if session.run_state != null:
		wear = session.run_state.get_car_wear(session.current_car_id)
	parent.add_child(label("%s · %s" % [session.current_car_id, wear], 18))
	spacer(parent, 6)
	divider(parent)


static func action(text: String, primary: bool = false, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	button.custom_minimum_size.y = 44
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_override("font", mono_font())
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_constant_override("outline_size", 0)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = AMBER if primary else PANEL
		style.border_color = LINE
		style.set_border_width_all(1)
		style.set_corner_radius_all(3)
		style.content_margin_left = 18
		style.content_margin_right = 18
		if state == "hover" or state == "pressed":
			style.bg_color = AMBER.lightened(0.12) if primary else Color("1a222d")
			style.border_color = AMBER
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = INK
			style.set_border_width_all(2)
		if state == "disabled":
			style.bg_color = PANEL
		button.add_theme_stylebox_override(state, style)
		button.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), BG if primary and state != "disabled" else INK)
	button.add_theme_color_override("font_disabled_color", DIM)
	button.add_theme_color_override("font_hover_pressed_color", BG if primary else INK)
	return button


static func marker(kind: String, current: bool, available: bool) -> Button:
	var button := Button.new()
	button.icon = TYPES[kind]["icon"] as Texture2D
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 28)
	button.custom_minimum_size = Vector2(38, 38)
	button.size = button.custom_minimum_size
	button.flat = true
	button.disabled = not available
	button.tooltip_text = "%s · %s\n%s" % [TYPES[kind]["name"], TYPES[kind]["cost"], TYPES[kind]["copy"]]
	button.add_theme_color_override("icon_normal_color", Color.WHITE)
	button.add_theme_color_override("icon_disabled_color", Color.WHITE if current else Color(0.85, 0.85, 0.85, 0.75))
	button.add_theme_color_override("icon_hover_color", Color.WHITE)
	button.add_theme_color_override("icon_focus_color", Color.WHITE)
	button.add_theme_color_override("icon_pressed_color", Color.WHITE)
	for state: String in ["normal", "disabled", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color.TRANSPARENT
		style.set_corner_radius_all(19)
		style.set_content_margin_all(5)
		if state in ["hover", "pressed", "focus"]:
			style.bg_color = Color(AMBER, 0.08)
			style.border_color = AMBER if state == "focus" else MUTED
			style.set_border_width_all(1)
		button.add_theme_stylebox_override(state, style)
	return button


static func legend(map: RunMap) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "RunLegend"
	row.add_theme_constant_override("separation", 18)
	var present: Dictionary = {}
	for node: Dictionary in map.nodes.values():
		present[String(node["type"])] = true
	for kind: String in TYPES:
		if not present.has(kind):
			continue
		var item := HBoxContainer.new()
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.add_theme_constant_override("separation", 8)
		item.tooltip_text = String(TYPES[kind]["copy"])
		row.add_child(item)
		item.add_child(icon(kind, 24))
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 1)
		item.add_child(text)
		text.add_child(label(String(TYPES[kind]["name"]), 14))
		text.add_child(label(String(TYPES[kind]["cost"]), 11, MUTED))
	return row
