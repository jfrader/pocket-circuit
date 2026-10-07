extends Control

const UI := preload("res://scripts/ui/run_ui.gd")
const PADDING := 36.0
const BOSS_Y := 72.0
const ROW_TOP := 144.0
const BOTTOM := 30.0

var _map: RunMap
var _buttons: Dictionary = {}
var _centres: Dictionary = {}
var _current := ""
var _available: Array[String] = []
var _header: Label
var _boss_label: Label


func configure(session: RunSession, on_pressed: Callable) -> Array[Button]:
	_map = session.current_map
	_current = session.current_node_id
	custom_minimum_size = Vector2(520, 516)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_header = UI.label("RUN · ACT %d · %s · SEED %d" % [_map.act, String(UI.ROOMS[_map.act]).to_upper(), _map.run_seed], 10, UI.MUTED, true)
	_header.position = Vector2(22, 18)
	add_child(_header)
	for entry: Dictionary in session.available_nodes():
		_available.append(String(entry["id"]))
	var result: Array[Button] = []
	for row: int in range(_map.num_rows):
		for node: Dictionary in _map.get_nodes_in_row(row):
			var id := String(node["id"])
			var kind := String(node["type"])
			var button := UI.marker(kind, id == _current, id in _available)
			button.name = "Node_" + id.replace("_", "-")
			if id in _available and on_pressed.is_valid():
				button.pressed.connect(on_pressed.bind(id))
			add_child(button)
			_buttons[id] = button
			result.append(button)
			if kind == "act_rival":
				_boss_label = UI.label("ACT RIVAL", 10, UI.AMBER, true)
				_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				add_child(_boss_label)
	resized.connect(_layout)
	_layout()
	return result


func _layout() -> void:
	if _map == null:
		return
	var extent := size.max(custom_minimum_size)
	for id: String in _buttons:
		var node: Dictionary = _map.get_node(id)
		var centre := Vector2(
			PADDING + float(node["col"]) * (extent.x - PADDING * 2.0) / float(RunMap.NUM_COLUMNS - 1),
			lerpf(extent.y - BOTTOM, ROW_TOP, float(node["row"]) / float(maxi(1, _map.num_rows - 1)))
		)
		if String(node["type"]) == "act_rival":
			centre = Vector2(extent.x * 0.5, BOSS_Y)
			_boss_label.position = Vector2(centre.x - 68, BOSS_Y + 26)
			_boss_label.size = Vector2(136, 20)
		_centres[id] = centre
		var button := _buttons[id] as Button
		button.position = centre - button.size * 0.5
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UI.PANEL)
	draw_rect(Rect2(Vector2.ZERO, size), UI.LINE, false, 1.0)
	if _map == null:
		return
	for id: String in _centres:
		for child: Dictionary in _map.get_children(id):
			var child_id := String(child["id"])
			var color := UI.LINE
			if String(child["type"]) == "act_rival":
				color = Color("674b29")
			if id == _current and child_id in _available:
				color = Color("657587")
			draw_line(_centres[id] as Vector2, _centres[child_id] as Vector2, color, 1.0, true)
	if _centres.has(_current):
		var centre: Vector2 = _centres[_current]
		draw_texture_rect(UI.CURRENT_RING, Rect2(centre - Vector2.ONE * 22, Vector2.ONE * 44), false)
