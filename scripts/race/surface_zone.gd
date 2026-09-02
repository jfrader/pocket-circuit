class_name SurfaceZone
extends Area2D

var surface_name: StringName = &"track"
var grip_multiplier: float = 1.0
var speed_multiplier: float = 1.0


func configure(
		zone_name: StringName,
		zone_polygon: PackedVector2Array,
		grip: float,
		speed: float,
		visual_color: Color = Color.TRANSPARENT,
		label_text: String = ""
) -> void:
	surface_name = zone_name
	grip_multiplier = clampf(grip, 0.2, 1.5)
	speed_multiplier = clampf(speed, 0.2, 1.5)
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	add_to_group("surface_zone")

	var collision := CollisionPolygon2D.new()
	collision.name = "SurfaceCollision"
	collision.polygon = zone_polygon
	add_child(collision)

	if visual_color.a > 0.0:
		var visual := Polygon2D.new()
		visual.name = "SurfaceVisual"
		visual.z_index = -5
		visual.color = visual_color
		visual.polygon = zone_polygon
		add_child(visual)

	if not label_text.is_empty():
		var label := Label.new()
		label.name = "SurfaceLabel"
		label.position = _polygon_center(zone_polygon) - Vector2(80.0, 12.0)
		label.size = Vector2(160.0, 28.0)
		label.text = label_text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color("fff8e8"))
		label.add_theme_color_override("font_outline_color", Color("172033"))
		label.add_theme_constant_override("outline_size", 4)
		add_child(label)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _exit_tree() -> void:
	for body: Node2D in get_overlapping_bodies():
		_clear_body(body)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("apply_surface_modifier"):
		body.call("apply_surface_modifier", get_instance_id(), surface_name, grip_multiplier, speed_multiplier)


func _on_body_exited(body: Node2D) -> void:
	_clear_body(body)


func _clear_body(body: Node2D) -> void:
	if body.has_method("clear_surface_modifier"):
		body.call("clear_surface_modifier", get_instance_id())


func contains_global_point(point: Vector2) -> bool:
	var collision := get_node_or_null("SurfaceCollision") as CollisionPolygon2D
	return collision != null and Geometry2D.is_point_in_polygon(to_local(point), collision.polygon)


func _polygon_center(points: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point: Vector2 in points:
		center += point
	return center / maxf(float(points.size()), 1.0)
