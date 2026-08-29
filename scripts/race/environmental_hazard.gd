class_name EnvironmentalHazard
extends Area2D

signal state_changed(state_name: StringName)

enum HazardState { WARNING, ACTIVE, COOLDOWN }

const INK := Color("172033")
const CREAM := Color("fff8e8")
const AMBER := Color("f4bf3a")
const HAZARD_SPRITES := {
	&"kitchen": preload("res://assets/textures/imagine/hazard_kitchen_apple.png"),
	&"workshop": preload("res://assets/textures/imagine/hazard_workshop_socket.png"),
	&"office": preload("res://assets/textures/imagine/hazard_office_cable.png"),
}

@export_range(0.2, 5.0, 0.1) var warning_duration := 1.2
@export_range(0.2, 5.0, 0.1) var active_duration := 1.6
@export_range(0.2, 8.0, 0.1) var cooldown_duration := 2.8
@export_range(0.0, 200.0, 1.0) var impact_impulse := 90.0
@export_range(0.4, 1.0, 0.01) var impact_slow_multiplier := 0.78

var theme: StringName = &"kitchen"
var hazard_name := "ROLLING FRUIT"
var state: HazardState = HazardState.WARNING
var start_position := Vector2.ZERO
var end_position := Vector2.ZERO

var _state_elapsed := 0.0
var _moving_visual: Node2D
var _collision: CollisionShape2D
var _warning_visual: Node2D
var _hit_body_ids: Dictionary = {}


func configure(hazard_theme: StringName, travel_start: Vector2, travel_end: Vector2) -> void:
	theme = hazard_theme
	start_position = travel_start
	end_position = travel_end
	add_to_group("track_hazard")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	process_mode = Node.PROCESS_MODE_INHERIT
	_build_visuals()
	body_entered.connect(_on_body_entered)
	_set_state(HazardState.WARNING)


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	_state_elapsed += delta
	match state:
		HazardState.WARNING:
			if _state_elapsed >= warning_duration:
				_state_elapsed -= warning_duration
				_set_state(HazardState.ACTIVE)
		HazardState.ACTIVE:
			if _state_elapsed >= active_duration:
				_state_elapsed -= active_duration
				_set_state(HazardState.COOLDOWN)
		HazardState.COOLDOWN:
			if _state_elapsed >= cooldown_duration:
				_state_elapsed -= cooldown_duration
				_set_state(HazardState.WARNING)
	_update_positions()


func get_state_name() -> StringName:
	match state:
		HazardState.WARNING:
			return &"warning"
		HazardState.ACTIVE:
			return &"active"
		_:
			return &"cooldown"


func get_travel_progress() -> float:
	return clampf(_state_elapsed / maxf(active_duration, 0.001), 0.0, 1.0) if state == HazardState.ACTIVE else 0.0


func get_motion_bounds() -> Rect2:
	var minimum := Vector2(minf(start_position.x, end_position.x), minf(start_position.y, end_position.y))
	var maximum := Vector2(maxf(start_position.x, end_position.x), maxf(start_position.y, end_position.y))
	return Rect2(minimum, maximum - minimum).grow(34.0)


func _set_state(next_state: HazardState) -> void:
	state = next_state
	_hit_body_ids.clear()
	if is_instance_valid(_warning_visual):
		_warning_visual.visible = state == HazardState.WARNING
	if is_instance_valid(_moving_visual):
		_moving_visual.visible = state != HazardState.COOLDOWN
	state_changed.emit(get_state_name())
	if state == HazardState.WARNING:
		_play_sfx(&"hazard_warning", 0.78)
	_update_positions()


func _update_positions() -> void:
	if not is_instance_valid(_moving_visual) or not is_instance_valid(_collision):
		return
	var progress := get_travel_progress()
	var moving_position := start_position.lerp(end_position, progress)
	_moving_visual.position = moving_position
	_collision.position = moving_position
	if theme == &"office":
		var cable := _moving_visual.get_node_or_null("Cable") as Line2D
		if cable:
			cable.points = PackedVector2Array([start_position - moving_position, Vector2.ZERO])


func _on_body_entered(body: Node2D) -> void:
	if state != HazardState.ACTIVE or body is not RigidBody2D:
		return
	if not body.is_in_group("race_vehicle") and not body.is_in_group("player_vehicle"):
		return
	var body_id := body.get_instance_id()
	if _hit_body_ids.has(body_id):
		return
	_hit_body_ids[body_id] = true
	var vehicle := body as RigidBody2D
	vehicle.linear_velocity *= impact_slow_multiplier
	var travel_direction := start_position.direction_to(end_position)
	vehicle.apply_central_impulse(travel_direction * impact_impulse)
	if body.is_in_group("player_vehicle"):
		_play_sfx(&"impact", 0.68)


func _build_visuals() -> void:
	_warning_visual = Node2D.new()
	_warning_visual.name = "WarningTelegraph"
	add_child(_warning_visual)
	var warning_line := Line2D.new()
	warning_line.width = 12.0
	warning_line.default_color = Color(AMBER, 0.78)
	warning_line.points = PackedVector2Array([start_position, end_position])
	warning_line.antialiased = true
	_warning_visual.add_child(warning_line)
	var warning_label := Label.new()
	warning_label.position = start_position.lerp(end_position, 0.5) - Vector2(105.0, 48.0)
	warning_label.size = Vector2(210.0, 32.0)
	warning_label.text = "!  %s  !" % _theme_hazard_name()
	warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning_label.add_theme_font_size_override("font_size", 16)
	warning_label.add_theme_color_override("font_color", AMBER)
	warning_label.add_theme_color_override("font_outline_color", INK)
	warning_label.add_theme_constant_override("outline_size", 5)
	_warning_visual.add_child(warning_label)

	_moving_visual = Node2D.new()
	_moving_visual.name = "MovingHazard"
	_moving_visual.z_index = 3
	add_child(_moving_visual)
	var shape: Shape2D
	var polygon := Polygon2D.new()
	polygon.name = "HazardBody"
	match theme:
		&"workshop":
			hazard_name = "SLIDING SOCKET"
			polygon.color = Color("bcc4c9")
			polygon.polygon = _regular_polygon(30.0, 6)
			shape = CircleShape2D.new()
			(shape as CircleShape2D).radius = 29.0
		&"office":
			hazard_name = "SWINGING CABLE"
			polygon.color = Color("6f91b8")
			polygon.polygon = PackedVector2Array([
				Vector2(-30.0, -18.0), Vector2(30.0, -18.0),
				Vector2(30.0, 18.0), Vector2(-30.0, 18.0),
			])
			shape = RectangleShape2D.new()
			(shape as RectangleShape2D).size = Vector2(60.0, 36.0)
			var cable := Line2D.new()
			cable.name = "Cable"
			cable.width = 9.0
			cable.default_color = INK
			cable.antialiased = true
			_moving_visual.add_child(cable)
		_:
			hazard_name = "ROLLING FRUIT"
			polygon.color = Color("e96b4c")
			polygon.polygon = _regular_polygon(31.0, 12)
			shape = CircleShape2D.new()
			(shape as CircleShape2D).radius = 30.0
	_moving_visual.add_child(polygon)
	var shine := Line2D.new()
	shine.width = 5.0
	shine.default_color = Color(CREAM, 0.7)
	shine.points = PackedVector2Array([Vector2(-11.0, -10.0), Vector2(8.0, -16.0)])
	shine.antialiased = true
	_moving_visual.add_child(shine)
	var sprite_texture := HAZARD_SPRITES.get(theme, HAZARD_SPRITES[&"kitchen"]) as Texture2D
	if sprite_texture:
		var sprite := Sprite2D.new()
		sprite.name = "HazardSprite"
		sprite.texture = sprite_texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(sprite_texture.get_width(), sprite_texture.get_height())
		sprite.scale = Vector2.ONE * (68.0 / maxf(longest, 1.0))
		_moving_visual.add_child(sprite)
		polygon.visible = false
		shine.visible = false
		var cable := _moving_visual.get_node_or_null("Cable") as CanvasItem
		if cable:
			cable.visible = false

	_collision = CollisionShape2D.new()
	_collision.name = "HazardCollision"
	_collision.shape = shape
	add_child(_collision)


func _theme_hazard_name() -> String:
	match theme:
		&"workshop":
			return "SOCKET CROSSING"
		&"office":
			return "CABLE SWING"
		_:
			return "FRUIT CROSSING"


func _regular_polygon(radius: float, sides: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in sides:
		points.append(Vector2.RIGHT.rotated(TAU * float(index) / float(sides)) * radius)
	return points


func _play_sfx(sound_name: StringName, volume_scale: float) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	var app := tree.root.get_node_or_null("App")
	if app and app.has_method("play_sfx"):
		app.call("play_sfx", sound_name, volume_scale)
