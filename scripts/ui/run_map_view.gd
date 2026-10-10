extends Control

## The act map. Read-only beside a stop's screen; on the board every stop can
## be picked to read what it is, and a reachable one can then be gone to.
##
## Picking (a click, or keyboard focus) emits stop_selected. Going (a second
## click on the picked stop, ENTER on it, or the board's confirm) is the board's
## call through travel_to, which drives the car token along the route first.

signal stop_selected(stop_id: String)
signal stop_confirmed(stop_id: String)

const UI := preload("res://scripts/ui/run_ui.gd")
const PADDING := 36.0
const BOSS_Y := 72.0
const BOSS_LABEL_SIZE := Vector2(136, 20)
const BOSS_LABEL_GAP := 26.0
const ROW_TOP := 144.0
const BOTTOM := 30.0
const RING_RADIUS := 23.0
const SELECTED_SCALE := 1.25
const LOCKED_ALPHA := 0.42
const DONE_ALPHA := 0.6
const UNDER_TOKEN_ALPHA := 0.3
const TOKEN_SIZE := Vector2(30, 30)
## Seconds: the routes drawing in, a marker popping in (staggered by row), the
## token's drive to a stop, and the reachable stops' pulse period.
const REVEAL_TIME := 0.55
const POP_TIME := 0.22
const POP_STAGGER := 0.035
const TRAVEL_TIME := 0.45
const PULSE_PERIOD := 1.4
const DASH := 7.0
const DASH_SPEED := 22.0

var reduced_motion := false

var _map: RunMap
var _buttons: Dictionary = {}
var _centres: Dictionary = {}
var _current := ""
var _available: Array[String] = []
var _done: Dictionary = {}
var _selected := ""
var _interactive := false
var _picked_by_press := false
var _header: Label
var _boss_label: Label
var _reveal := 1.0
var _clock := 0.0
var _token: TextureRect
var _travelling := false


## Builds the markers for the session's act. `interactive` makes every stop
## pickable (the board); otherwise the map only shows (beside a stop's screen).
## `token` is the car drawn over the current stop on the board.
func configure(session: RunSession, interactive: bool, token: Texture2D = null) -> Array[Button]:
	_map = session.current_map
	_current = session.current_node_id
	_interactive = interactive
	_done = session.resolved_nodes.duplicate()
	custom_minimum_size = UI.CARD_SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS
	_header = UI.label("ACT %d · %s · SEED %d" % [_map.act, String(UI.ROOMS[_map.act]).to_upper(), _map.run_seed], 10, UI.MUTED, true)
	_header.position = Vector2(22, 18)
	add_child(_header)
	for entry: Dictionary in session.available_nodes():
		_available.append(String(entry["id"]))
	var result: Array[Button] = []
	for row: int in range(_map.num_rows):
		for node: Dictionary in _map.get_nodes_in_row(row):
			var id := String(node["id"])
			var kind := String(node["type"])
			var button := UI.marker(kind, id == _current, interactive)
			button.name = "Node_" + id.replace("_", "-")
			button.set_meta("stop_id", id)
			button.set_meta("reachable", id in _available)
			if not interactive:
				button.focus_mode = Control.FOCUS_NONE
				button.mouse_filter = Control.MOUSE_FILTER_IGNORE
			else:
				button.focus_entered.connect(_on_marker_focused.bind(id))
				button.pressed.connect(_on_marker_pressed.bind(id))
			add_child(button)
			_buttons[id] = button
			result.append(button)
			if kind == "act_rival":
				_boss_label = UI.label("ACT RIVAL", 10, UI.AMBER, true)
				_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				var plate := StyleBoxFlat.new()
				plate.bg_color = UI.PANEL
				_boss_label.add_theme_stylebox_override("normal", plate)
				add_child(_boss_label)
	if token != null and interactive:
		_token = TextureRect.new()
		_token.name = "CarToken"
		_token.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_token.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_token.texture = token
		_token.custom_minimum_size = TOKEN_SIZE
		_token.size = TOKEN_SIZE
		_token.pivot_offset = TOKEN_SIZE * 0.5
		_token.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_token.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_token)
	resized.connect(_layout)
	_layout()
	_rest_markers()
	if not reduced_motion:
		_play_reveal()
	return result


func is_reachable(stop_id: String) -> bool:
	return stop_id in _available


func selected_id() -> String:
	return _selected


## Picks a stop: it grows and gets the ring, and the route to it flows.
func select(stop_id: String) -> void:
	if not _buttons.has(stop_id) or stop_id == _selected:
		return
	_selected = stop_id
	# Keyboard focus follows the pick, so the map shows one ring.
	var button := _buttons[stop_id] as Button
	if _interactive and button.is_inside_tree() and not button.has_focus():
		button.grab_focus()
	_rest_markers()
	queue_redraw()
	stop_selected.emit(stop_id)


func marker(stop_id: String) -> Button:
	return _buttons.get(stop_id) as Button


## Drives the car token from the current stop to `stop_id`; returns when it
## arrives (at once with reduced motion).
func travel_to(stop_id: String) -> void:
	if not _centres.has(stop_id) or not _centres.has(_current):
		return
	var to: Vector2 = _centres[stop_id]
	if _token == null:
		return
	_token.rotation = (to - (_centres[_current] as Vector2)).angle() + PI * 0.5
	if reduced_motion:
		_token.position = to - TOKEN_SIZE * 0.5
		return
	_travelling = true
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_token, "position", to - TOKEN_SIZE * 0.5, TRAVEL_TIME)
	await tween.finished
	_travelling = false


func _on_marker_focused(stop_id: String) -> void:
	# A mouse press focuses before it presses: that press only picks the stop.
	_picked_by_press = stop_id != _selected and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	select(stop_id)


func _on_marker_pressed(stop_id: String) -> void:
	if _picked_by_press:
		_picked_by_press = false
		return
	if stop_id != _selected:
		select(stop_id)
		return
	stop_confirmed.emit(stop_id)


func _rest_markers() -> void:
	for id: String in _buttons:
		var button := _buttons[id] as Button
		button.pivot_offset = button.size * 0.5
		button.scale = Vector2.ONE * (SELECTED_SCALE if id == _selected else 1.0)
		var alpha := 1.0
		if id == _current and _token != null:
			alpha = UNDER_TOKEN_ALPHA
		elif id != _current and not id in _available:
			alpha = DONE_ALPHA if _done.has(id) else LOCKED_ALPHA
		button.self_modulate.a = alpha


func _play_reveal() -> void:
	_reveal = 0.0
	var routes := create_tween()
	routes.tween_method(func(at: float) -> void:
		_reveal = at
		queue_redraw(), 0.0, 1.0, REVEAL_TIME)
	for id: String in _buttons:
		var button := _buttons[id] as Button
		var rest := button.scale
		button.scale = rest * 0.4
		button.modulate.a = 0.0
		var pop := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		var delay := POP_STAGGER * float(_map.get_node(id)["row"])
		pop.tween_property(button, "scale", rest, POP_TIME).set_delay(delay)
		pop.tween_property(button, "modulate:a", 1.0, POP_TIME).set_delay(delay)


func _process(delta: float) -> void:
	if reduced_motion or not _interactive or _map == null:
		return
	_clock += delta
	queue_redraw()


func _layout() -> void:
	if _map == null:
		return
	var extent := size.max(custom_minimum_size)
	for id: String in _buttons:
		var node: Dictionary = _map.get_node(id)
		# The act rival row sits apart at the top; the walker rows fill the rest.
		var row := int(node["row"])
		var boss_row := _map.num_rows - 1
		var centre := Vector2(
			PADDING + float(node["col"]) * (extent.x - PADDING * 2.0) / float(RunMap.NUM_COLUMNS - 1),
			BOSS_Y if row == boss_row else lerpf(extent.y - BOTTOM, ROW_TOP, float(row) / float(maxi(1, boss_row - 1)))
		)
		if row == boss_row:
			_boss_label.size = BOSS_LABEL_SIZE
			_boss_label.position = Vector2(centre.x - BOSS_LABEL_SIZE.x * 0.5, centre.y + BOSS_LABEL_GAP)
		_centres[id] = centre
		var button := _buttons[id] as Button
		button.position = centre - button.size * 0.5
	if _token != null and not _travelling and _centres.has(_current):
		_token.position = (_centres[_current] as Vector2) - TOKEN_SIZE * 0.5
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UI.PANEL)
	draw_rect(Rect2(Vector2.ONE * 0.5, size - Vector2.ONE), UI.LINE, false, 1.0)
	if _map == null:
		return
	var rows := float(maxi(1, _map.num_rows - 1))
	for id: String in _centres:
		var row := float(_map.get_node(id)["row"])
		var shown := clampf(_reveal * (rows + 1.0) - row, 0.0, 1.0)
		if shown <= 0.0:
			continue
		for child: Dictionary in _map.get_children(id):
			var child_id := String(child["id"])
			var color := UI.LINE
			if String(child["type"]) == "act_rival":
				color = UI.BOSS_EDGE
			if id == _current and child_id in _available:
				color = UI.LIVE_EDGE
			var from: Vector2 = _centres[id]
			var to: Vector2 = from.lerp(_centres[child_id] as Vector2, shown)
			if id == _current and child_id == _selected and child_id in _available:
				_draw_flow(from, to)
			else:
				draw_line(from, to, color, 1.0, true)
	var pulse := 0.5 + 0.5 * sin(_clock * TAU / PULSE_PERIOD)
	if _interactive:
		for id: String in _available:
			if id != _selected and _centres.has(id):
				draw_circle(_centres[id] as Vector2, RING_RADIUS * (0.8 + 0.2 * pulse), Color(UI.AMBER, 0.06 + 0.1 * pulse))
	if _centres.has(_selected):
		var ring := UI.AMBER if _selected in _available else UI.MUTED
		draw_arc(_centres[_selected] as Vector2, RING_RADIUS * SELECTED_SCALE, 0.0, TAU, 40, ring, 2.0, true)
	if _centres.has(_current):
		var centre: Vector2 = _centres[_current]
		draw_texture_rect(UI.CURRENT_RING, Rect2(centre - Vector2.ONE * 22, Vector2.ONE * 44), false)
	for id: String in _done:
		if _centres.has(id) and id != _current:
			_draw_done(_centres[id] as Vector2)


## The route to the picked stop, as dashes running toward it.
func _draw_flow(from: Vector2, to: Vector2) -> void:
	var length := from.distance_to(to)
	if length <= 0.0:
		return
	var direction := (to - from) / length
	var at := fmod(_clock * DASH_SPEED, DASH * 2.0) - DASH * 2.0
	while at < length:
		var start := maxf(at, 0.0)
		var end := minf(at + DASH, length)
		if end > start:
			draw_line(from + direction * start, from + direction * end, UI.AMBER, 2.0, true)
		at += DASH * 2.0


## A raced or visited stop: a small tick under its marker.
func _draw_done(centre: Vector2) -> void:
	var tick := PackedVector2Array([centre + Vector2(9, 12), centre + Vector2(12, 15), centre + Vector2(18, 8)])
	draw_polyline(tick, UI.AMBER, 2.0, true)
