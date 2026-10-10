extends RefCounted

const BG := Color("0a0c10")
const PANEL := Color("0e1218")
const LINE := Color("232d3a")
const INK := Color("e9ecf1")
const MUTED := Color("8b95a5")
const DIM := Color("5a6577")
const AMBER := Color("f2a53c")
const UPSIDE := Color("5fbf7f")
const DOWNSIDE := Color("e0605a")
const BOSS_EDGE := Color("674b29")
const LIVE_EDGE := Color("657587")
const CATALOG := preload("res://data/championship/catalog.gd")
const ROOMS := {1: "Kitchen Counter", 2: "Workshop Bench", 3: "Office Desk"}
const TYPES := {
	"race": {"name": "Race", "cost": "wear", "copy": "Four cars on a rolled circuit.", "icon": preload("res://assets/ui/run_map/node_race.svg")},
	"rival": {"name": "Rival", "cost": "points or wear", "copy": "One on one, with contact. Win and their car is yours.", "icon": preload("res://assets/ui/run_map/node_rival.svg")},
	"bench": {"name": "Bench", "cost": "the visit", "copy": "Repair the car, or fit one part. Not both.", "icon": preload("res://assets/ui/run_map/node_bench.svg")},
	"parts_van": {"name": "Parts van", "cost": "points", "copy": "Buy one part. Every part has a downside.", "icon": preload("res://assets/ui/run_map/node_parts_van.svg")},
	"lockup": {"name": "Lockup", "cost": "free", "copy": "A free car. No race.", "icon": preload("res://assets/ui/run_map/node_lockup.svg")},
	"errand": {"name": "Errand", "cost": "varies", "copy": "Someone wants a favour. Take the pay or a tune-up.", "icon": preload("res://assets/ui/run_map/node_errand.svg")},
	"act_rival": {"name": "Act rival", "cost": "the run", "copy": "The act's hardest drivers. Win to clear the act.", "icon": preload("res://assets/ui/run_map/node_boss.svg")},
}
## What the board's confirm button says for each kind of stop.
const GO_LABELS := {
	"race": "RACE", "rival": "DUEL", "act_rival": "RACE THE ACT RIVAL", "bench": "GO TO THE BENCH",
	"parts_van": "GO TO THE VAN", "lockup": "GO TO THE LOCKUP", "errand": "TAKE THE ERRAND",
}
const BOARD_CONTROLS := "CLICK OR MOVE TO A STOP TO SEE IT · CLICK IT AGAIN, ENTER OR A TO GO"
const NIGHT_WON := "You took the circuit before sunrise."
const NIGHT_LOST := "Cars won tonight are in Quick Race."
## Seconds a changed count ticks, holds its difference, and fades it.
const TICK_TIME := 0.6
const FLASH_HOLD := 0.9
const FLASH_FADE := 0.5
## Seconds between staggered entries, and each one's fade.
const STAGGER := 0.035
const STAGGER_TIME := 0.16
## Where a won car came from, as the garage and the run's car offer say it.
const ORIGIN_COPY := {"rival": "WON IN A DUEL · ACT %d", "lockup": "FOUND IN A LOCKUP · ACT %d"}
## The right-hand card of a run screen: the map, or a stop's parts.
const CARD_SIZE := Vector2(520, 516)
const PART_BUTTON_HEIGHT := 92.0
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


## What the run's stats showed, to animate what changed next time.
static func stats_snapshot(session: RunSession) -> Dictionary:
	return {
		"seed": session.run_seed,
		"POINTS": session.run_points,
		"OWNED": session.owned_cars.size(),
		"PARTS": session.parts_held.size(),
		"car": session.current_car_id,
		"wear": session.run_state.get_car_wear(session.current_car_id) if session.run_state != null else "",
	}


## The run's points, cars, parts and current car. Against `previous` (the last
## snapshot shown, same night), changed counts tick to their new value with
## the difference beside them, and a changed car or wear flashes.
static func stats(host: VBoxContainer, session: RunSession, previous: Dictionary = {}, reduced_motion: bool = true) -> void:
	var now := stats_snapshot(session)
	var animate := not reduced_motion and int(previous.get("seed", -1)) == session.run_seed
	var parent := VBoxContainer.new()
	parent.add_theme_constant_override("separation", 4)
	host.add_child(parent)
	divider(parent)
	spacer(parent, 4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 38)
	parent.add_child(row)
	for key: String in ["POINTS", "OWNED", "PARTS"]:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		row.add_child(column)
		column.add_child(label(key, 11, MUTED, true))
		var value_row := HBoxContainer.new()
		value_row.add_theme_constant_override("separation", 8)
		column.add_child(value_row)
		var value := label(str(now[key]), 28)
		value_row.add_child(value)
		if animate and int(previous.get(key, now[key])) != int(now[key]):
			_tick(value, value_row, int(previous[key]), int(now[key]))
	spacer(parent, 6)
	parent.add_child(label("CURRENT CAR", 11, MUTED, true))
	var wear := "?"
	if session.run_state != null:
		wear = session.run_state.get_car_wear(session.current_car_id)
	var car_line := label("%s · %s" % [car_name(session.current_car_id), wear], 18)
	parent.add_child(car_line)
	if animate and (previous.get("wear") != now["wear"] or previous.get("car") != now["car"]):
		car_line.add_theme_color_override("font_color", AMBER)
		var flash := car_line.create_tween()
		flash.tween_interval(FLASH_HOLD)
		flash.tween_method(func(at: float) -> void: car_line.add_theme_color_override("font_color", AMBER.lerp(INK, at)), 0.0, 1.0, FLASH_FADE)
	var fitted := session.fitted_parts(session.current_car_id).map(func(part: Dictionary) -> String: return RunParts.part_name(part))
	if not fitted.is_empty():
		var fitted_line := label("FITTED · %s" % ", ".join(PackedStringArray(fitted)).to_upper(), 11, MUTED, true)
		fitted_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(fitted_line)
	spacer(parent, 6)
	divider(parent)


## A card of parts under a header: returns the card and the list to fill. The
## list scrolls to the focused part when the pile outgrows the card.
static func parts_card(header: String) -> Array[Control]:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = LINE
	style.set_border_width_all(1)
	style.set_content_margin_all(22)
	card.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	card.add_child(column)
	column.add_child(label(header, 10, MUTED, true))
	var scroll := ScrollContainer.new()
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return [card, list]


## A part as one button: its title, then what it gives and what it takes.
static func part_button(part: Dictionary, title: String, disabled: bool) -> Button:
	var button := action("", false, disabled)
	button.custom_minimum_size.y = PART_BUTTON_HEIGHT
	var lines := VBoxContainer.new()
	lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lines.offset_left = 18
	lines.offset_right = -18
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.add_theme_constant_override("separation", 4)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.modulate.a = 0.45 if disabled else 1.0
	button.add_child(lines)
	for line: Label in [label(title, 13, INK, true), label("+ " + RunParts.upside_copy(part), 13, UPSIDE, true), label("− " + RunParts.downside_copy(part), 13, DOWNSIDE, true)]:
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lines.add_child(line)
	return button


## Counts a value from `from` to `to`, with the difference floating beside it.
static func _tick(value: Label, row: HBoxContainer, from: int, to: int) -> void:
	var delta := label(("+%d" if to > from else "%d") % (to - from), 16, AMBER if to > from else DOWNSIDE, true)
	row.add_child(delta)
	var tween := value.create_tween()
	tween.tween_method(func(at: float) -> void: value.text = str(roundi(lerpf(from, to, at))), 0.0, 1.0, TICK_TIME)
	tween.tween_interval(FLASH_HOLD)
	tween.tween_property(delta, "modulate:a", 0.0, FLASH_FADE)


## What a stop pays and costs, as label/value rows; race-type stops name their
## circuit.
static func stop_facts(kind: String, session: RunSession, circuit: Dictionary) -> Array:
	var rows: Array = []
	if not circuit.is_empty():
		rows.append(["CIRCUIT", "%s · %s" % [String(circuit.get("display_name", "")), "reverse" if bool(circuit.get("reverse", false)) else "forward"]])
	var pays := PackedStringArray()
	for place: int in RunSession.RUN_POINTS_BY_FINISH:
		pays.append(str(RunSession.RUN_POINTS_BY_FINISH[place]))
	match kind:
		"race":
			rows.append(["FIELD", "%d cars" % RunSession.RUN_POINTS_BY_FINISH.size()])
			rows.append(["PAYS", "%s points, 1st to last" % " · ".join(pays)])
			rows.append(["COSTS", "wear when you crash"])
		"rival":
			rows.append(["FIELD", "one on one, contact"])
			rows.append(["WIN", "their car"])
			rows.append(["LOSE", "%d points, or wear without them" % RunSession.RIVAL_LOSS_POINTS_COST])
		"act_rival":
			rows.append(["FIELD", "%d cars, hardest drivers" % RunSession.RUN_POINTS_BY_FINISH.size()])
			rows.append(["WIN", "act %d" % (session.current_map.act + 1) if session.current_map.act < RunSession.FINAL_ACT else "the night"])
			rows.append(["LOSE", "the run"])
		"bench":
			rows.append(["REPAIR", "one wear level"])
			rows.append(["OR FIT", "one of your %d parts" % session.parts_held.size() if not session.parts_held.is_empty() else "no parts held"])
		"parts_van":
			rows.append(["STOCK", "%d parts, one sale" % RunParts.VAN_STOCK])
			rows.append(["YOU HAVE", "%d points" % session.run_points])
		"lockup":
			rows.append(["GIVES", "a free car"])
		"errand":
			rows.append(["CHOICE", "%d points or a tune-up" % RunSession.ERRAND_PAY_POINTS])
	return rows


static func facts(rows: Array) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = "StopFacts"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	for row: Array in rows:
		grid.add_child(label(String(row[0]), 11, MUTED, true))
		var value := label(String(row[1]), 15)
		value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(value)
	return grid


## Fades and lifts controls in one after another; nothing moves with reduced motion.
static func stagger_in(controls: Array, reduced_motion: bool) -> void:
	if reduced_motion:
		return
	var index := 0
	for node: Variant in controls:
		var control := node as Control
		if control == null or not control.is_inside_tree():
			continue
		control.modulate.a = 0.0
		var tween := control.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(control, "modulate:a", 1.0, STAGGER_TIME).set_delay(STAGGER * index)
		index += 1


## A car's display name (generated cars have their own), never its id.
static func car_name(vehicle_id: String) -> String:
	return String(CATALOG.get_vehicle(vehicle_id).get("name", vehicle_id))


static func action(text: String, primary: bool = false, disabled: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	if disabled:
		button.focus_mode = Control.FOCUS_NONE
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


static func marker(kind: String, current: bool, interactive: bool) -> Button:
	var button := Button.new()
	button.icon = TYPES[kind]["icon"] as Texture2D
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 28)
	button.custom_minimum_size = Vector2(38, 38)
	button.size = button.custom_minimum_size
	button.flat = true
	button.disabled = not interactive
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
			# The map draws the picked stop's ring; focus adds none of its own.
			style.border_color = MUTED
			style.set_border_width_all(0 if state == "focus" else 1)
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
