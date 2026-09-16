class_name EnvironmentalHazard
extends Area2D

signal state_changed(state_name: StringName)

const VISUAL_ROLE_CONTRACT := preload("res://scripts/race/generated_world_visual_role.gd")

enum HazardState { IDLE, WARNING, ACTIVE, EXIT, COOLDOWN }

const INK := Color("172033")
const CREAM := Color("fff8e8")
const HAZARD_SPRITES := {
	&"kitchen": preload("res://assets/textures/imagine/hazard_kitchen_apple.png"),
	&"workshop": preload("res://assets/textures/imagine/hazard_workshop_socket.png"),
	&"office": preload("res://assets/textures/imagine/hazard_office_cable.png"),
}

@export_range(0.0, 5.0, 0.1) var idle_duration := 0.8
@export_range(0.2, 5.0, 0.1) var warning_duration := 1.2
@export_range(0.2, 5.0, 0.1) var active_duration := 1.6
@export_range(0.2, 5.0, 0.1) var exit_duration := 0.6
@export_range(0.2, 8.0, 0.1) var cooldown_duration := 2.8
@export_range(0.0, 200.0, 1.0) var impact_impulse := 90.0
@export_range(0.4, 1.0, 0.01) var impact_slow_multiplier := 0.78

var theme: StringName = &"kitchen"
var state: HazardState = HazardState.IDLE
var motion: StringName = &"rolling"
var start_position := Vector2.ZERO
var end_position := Vector2.ZERO
var entry_position := Vector2.ZERO
var exit_position := Vector2.ZERO
var footprint_size := Vector2(60.0, 60.0)
var footprint_kind: StringName = &"circle"

var _state_elapsed := 0.0
var _moving_visual: Node2D
var _collision: CollisionShape2D
var _hazard_sprite: Sprite2D
var _hit_body_ids: Dictionary = {}


func configure(hazard_theme: StringName, travel_start: Vector2, travel_end: Vector2, plan: Dictionary = {}) -> void:
	theme = hazard_theme
	motion = StringName(plan.get("motion", &"static" if theme == &"office" else &"rolling"))
	start_position = travel_start
	end_position = travel_end if not is_static() else travel_start
	var travel_direction := start_position.direction_to(end_position)
	if travel_direction.is_zero_approx():
		travel_direction = Vector2.RIGHT
	if is_static():
		entry_position = start_position
		exit_position = start_position
	else:
		entry_position = start_position - travel_direction * float(plan.get("entry_distance", 72.0))
		exit_position = end_position + travel_direction * float(plan.get("exit_distance", 84.0))
	idle_duration = maxf(0.0, float(plan.get("idle_duration", idle_duration)))
	warning_duration = maxf(0.2, float(plan.get("warning_duration", warning_duration)))
	active_duration = maxf(0.2, float(plan.get("active_duration", active_duration)))
	exit_duration = maxf(0.2, float(plan.get("exit_duration", exit_duration)))
	cooldown_duration = maxf(0.2, float(plan.get("cooldown_duration", cooldown_duration)))
	footprint_size = plan.get("footprint_size", _default_footprint_size())
	footprint_kind = StringName(plan.get("footprint_kind", &"rect" if theme == &"office" else &"circle"))
	add_to_group("track_hazard")
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	process_mode = Node.PROCESS_MODE_INHERIT
	VISUAL_ROLE_CONTRACT.assign(self, VISUAL_ROLE_CONTRACT.MOVING_HAZARD)
	set_meta("hazard_id", StringName(plan.get("id", &"%s_crossing" % String(theme))))
	set_meta("seed", int(plan.get("seed", 0)))
	set_meta("role", StringName(plan.get("role", &"moving_hazard")))
	set_meta("footprint_kind", footprint_kind)
	set_meta("footprint_size", footprint_size)
	set_meta("visual_bounds", plan.get("visual_bounds", Rect2(-footprint_size * 0.5, footprint_size)))
	set_meta("warning_origin", entry_position)
	set_meta("warning_path", PackedVector2Array([entry_position, start_position]))
	set_meta("danger_path", PackedVector2Array([start_position, end_position]))
	set_meta("exit_path", PackedVector2Array([end_position, exit_position]))
	set_meta("motion_path", PackedVector2Array([entry_position, start_position, end_position, exit_position]))
	set_meta("motion", motion)
	set_meta("danger_states", PackedStringArray(["active"] if is_static() else ["active", "exit"]))
	_build_visuals()
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_set_state(HazardState.ACTIVE if is_static() else HazardState.IDLE)


func _physics_process(delta: float) -> void:
	advance(delta)


func is_static() -> bool:
	return motion == &"static"


func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	if is_static():
		_apply_overlapping_bodies()
		return
	var remaining := delta
	while remaining > 0.000001:
		var duration := _state_duration(state)
		var step := minf(remaining, maxf(duration - _state_elapsed, 0.0))
		_state_elapsed += step
		remaining -= step
		_update_positions()
		if _state_elapsed + 0.000001 < duration:
			break
		_state_elapsed = 0.0
		_set_state(_next_state(state))
	if is_collision_active():
		_apply_overlapping_bodies()


func get_state_name() -> StringName:
	return _state_name(state)


func get_travel_progress() -> float:
	match state:
		HazardState.WARNING:
			return clampf(_state_elapsed / maxf(warning_duration, 0.001), 0.0, 1.0)
		HazardState.ACTIVE:
			return clampf(_state_elapsed / maxf(active_duration, 0.001), 0.0, 1.0)
		HazardState.EXIT:
			return clampf(_state_elapsed / maxf(exit_duration, 0.001), 0.0, 1.0)
	return 0.0


func get_local_hazard_position() -> Vector2:
	return _position_for(state, _state_elapsed)


func is_collision_active() -> bool:
	return is_static() or state == HazardState.ACTIVE or state == HazardState.EXIT


func get_prediction(seconds_ahead: float) -> Dictionary:
	if is_static():
		return {
			"state": &"active",
			"position": start_position,
			"collision_active": true,
		}
	var predicted_state := state
	var predicted_elapsed := _state_elapsed
	var remaining := maxf(seconds_ahead, 0.0)
	while remaining > 0.000001:
		var duration := _state_duration(predicted_state)
		var available := maxf(duration - predicted_elapsed, 0.0)
		if remaining + 0.000001 < available:
			predicted_elapsed += remaining
			remaining = 0.0
		else:
			remaining -= available
			predicted_elapsed = 0.0
			predicted_state = _next_state(predicted_state)
	return {
		"state": _state_name(predicted_state),
		"position": _position_for(predicted_state, predicted_elapsed),
		"collision_active": is_static() or predicted_state == HazardState.ACTIVE or predicted_state == HazardState.EXIT,
	}


func get_time_until_danger() -> float:
	if is_collision_active():
		return 0.0
	var predicted_state := state
	var elapsed := _state_elapsed
	var total := 0.0
	for _transition in 5:
		total += maxf(_state_duration(predicted_state) - elapsed, 0.0)
		predicted_state = _next_state(predicted_state)
		elapsed = 0.0
		if predicted_state == HazardState.ACTIVE:
			return total
	return total


func get_motion_bounds() -> Rect2:
	var minimum := entry_position.min(exit_position).min(start_position).min(end_position)
	var maximum := entry_position.max(exit_position).max(start_position).max(end_position)
	return Rect2(minimum, maximum - minimum).grow(maxf(footprint_size.x, footprint_size.y) * 0.5)


func _state_duration(value: HazardState) -> float:
	match value:
		HazardState.IDLE:
			return idle_duration
		HazardState.WARNING:
			return warning_duration
		HazardState.ACTIVE:
			return active_duration
		HazardState.EXIT:
			return exit_duration
		_:
			return cooldown_duration


func _next_state(value: HazardState) -> HazardState:
	match value:
		HazardState.IDLE:
			return HazardState.WARNING
		HazardState.WARNING:
			return HazardState.ACTIVE
		HazardState.ACTIVE:
			return HazardState.EXIT
		HazardState.EXIT:
			return HazardState.COOLDOWN
		_:
			return HazardState.IDLE


func _state_name(value: HazardState) -> StringName:
	match value:
		HazardState.IDLE:
			return &"idle"
		HazardState.WARNING:
			return &"warning"
		HazardState.ACTIVE:
			return &"active"
		HazardState.EXIT:
			return &"exit"
		_:
			return &"cooldown"


func _position_for(value: HazardState, elapsed: float) -> Vector2:
	match value:
		HazardState.WARNING:
			return entry_position.lerp(start_position, clampf(elapsed / maxf(warning_duration, 0.001), 0.0, 1.0))
		HazardState.ACTIVE:
			return start_position.lerp(end_position, clampf(elapsed / maxf(active_duration, 0.001), 0.0, 1.0))
		HazardState.EXIT:
			return end_position.lerp(exit_position, clampf(elapsed / maxf(exit_duration, 0.001), 0.0, 1.0))
		HazardState.COOLDOWN:
			return exit_position
		_:
			return entry_position


func _default_footprint_size() -> Vector2:
	return Vector2(60.0, 36.0) if theme == &"office" else Vector2(60.0, 60.0)


func _set_state(next_state: HazardState) -> void:
	state = next_state
	if state == HazardState.ACTIVE:
		_hit_body_ids.clear()
	if is_instance_valid(_moving_visual):
		_moving_visual.visible = is_static() or state != HazardState.COOLDOWN
	if is_instance_valid(_collision):
		_collision.disabled = not is_collision_active()
	state_changed.emit(get_state_name())
	_update_positions()


func _update_positions() -> void:
	if not is_instance_valid(_moving_visual) or not is_instance_valid(_collision):
		return
	var moving_position := get_local_hazard_position()
	_moving_visual.position = moving_position
	_collision.position = moving_position
	if is_instance_valid(_hazard_sprite) and not is_static() and footprint_kind == &"circle":
		var radius := maxf(footprint_size.x, footprint_size.y) * 0.5
		_hazard_sprite.rotation = _traveled_distance() / maxf(radius, 1.0)


func _on_body_entered(body: Node2D) -> void:
	_apply_hit(body)


func _apply_overlapping_bodies() -> void:
	if not is_inside_tree():
		return
	for body: Node2D in get_overlapping_bodies():
		_apply_hit(body)


func _apply_hit(body: Node2D) -> void:
	if not is_collision_active() or body is not RigidBody2D:
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


func _traveled_distance() -> float:
	var warning_length := entry_position.distance_to(start_position)
	var active_length := start_position.distance_to(end_position)
	var exit_length := end_position.distance_to(exit_position)
	var progress := get_travel_progress()
	match state:
		HazardState.WARNING:
			return warning_length * progress
		HazardState.ACTIVE:
			return warning_length + active_length * progress
		HazardState.EXIT:
			return warning_length + active_length + exit_length * progress
		HazardState.COOLDOWN:
			return warning_length + active_length + exit_length
		_:
			return 0.0


func _build_visuals() -> void:
	_moving_visual = Node2D.new()
	_moving_visual.name = "MovingHazard"
	_moving_visual.z_index = 3
	VISUAL_ROLE_CONTRACT.assign(_moving_visual, VISUAL_ROLE_CONTRACT.MOVING_HAZARD)
	add_child(_moving_visual)
	var shape: Shape2D
	var polygon := Polygon2D.new()
	polygon.name = "HazardBody"
	VISUAL_ROLE_CONTRACT.assign(polygon, VISUAL_ROLE_CONTRACT.MOVING_HAZARD)
	match theme:
		&"workshop":
			polygon.color = Color("bcc4c9")
			polygon.polygon = _regular_polygon(maxf(footprint_size.x, footprint_size.y) * 0.5, 6)
			shape = CircleShape2D.new()
			(shape as CircleShape2D).radius = maxf(footprint_size.x, footprint_size.y) * 0.5
		&"office":
			polygon.color = Color("6f91b8")
			polygon.polygon = PackedVector2Array([
				Vector2(-footprint_size.x, -footprint_size.y) * 0.5, Vector2(footprint_size.x, -footprint_size.y) * 0.5,
				Vector2(footprint_size.x, footprint_size.y) * 0.5, Vector2(-footprint_size.x, footprint_size.y) * 0.5,
			])
			shape = RectangleShape2D.new()
			(shape as RectangleShape2D).size = footprint_size
			var cable := Line2D.new()
			cable.name = "Cable"
			cable.width = 9.0
			cable.default_color = INK
			cable.antialiased = true
			VISUAL_ROLE_CONTRACT.assign(cable, VISUAL_ROLE_CONTRACT.MOVING_HAZARD)
			_moving_visual.add_child(cable)
		_:
			polygon.color = Color("e96b4c")
			polygon.polygon = _regular_polygon(maxf(footprint_size.x, footprint_size.y) * 0.5, 12)
			shape = CircleShape2D.new()
			(shape as CircleShape2D).radius = maxf(footprint_size.x, footprint_size.y) * 0.5
	_moving_visual.add_child(polygon)
	var shine := Line2D.new()
	shine.width = 5.0
	shine.default_color = Color(CREAM, 0.7)
	shine.points = PackedVector2Array([Vector2(-11.0, -10.0), Vector2(8.0, -16.0)])
	shine.antialiased = true
	VISUAL_ROLE_CONTRACT.assign(shine, VISUAL_ROLE_CONTRACT.MOVING_HAZARD)
	_moving_visual.add_child(shine)
	var sprite_texture := HAZARD_SPRITES.get(theme, HAZARD_SPRITES[&"kitchen"]) as Texture2D
	if sprite_texture:
		var sprite := Sprite2D.new()
		sprite.name = "HazardSprite"
		sprite.texture = sprite_texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.set_meta("asset_path", sprite_texture.resource_path)
		VISUAL_ROLE_CONTRACT.assign(sprite, VISUAL_ROLE_CONTRACT.MOVING_HAZARD)
		var longest := maxf(sprite_texture.get_width(), sprite_texture.get_height())
		sprite.scale = Vector2.ONE * ((maxf(footprint_size.x, footprint_size.y) + 8.0) / maxf(longest, 1.0))
		_moving_visual.add_child(sprite)
		_hazard_sprite = sprite
		polygon.visible = false
		shine.visible = false
		var cable := _moving_visual.get_node_or_null("Cable") as CanvasItem
		if cable:
			cable.visible = false

	_collision = CollisionShape2D.new()
	_collision.name = "HazardCollision"
	_collision.shape = shape
	_collision.set_meta("footprint_kind", footprint_kind)
	_collision.set_meta("footprint_size", footprint_size)
	add_child(_collision)


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
