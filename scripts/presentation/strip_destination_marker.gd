extends Control

const STRIP_CONTROLLER := preload("res://scripts/race/strip_controller.gd")
const EDGE_MARGIN := 48.0
const WARNING_SECONDS := 15.0

var finish: Vector2
var camera: Camera2D
var manager: RaceManager
var time_limit := STRIP_CONTROLLER.LIMIT_SECONDS


func configure(target: Vector2, view_camera: Camera2D, race_manager: RaceManager, limit_seconds: float = STRIP_CONTROLLER.LIMIT_SECONDS) -> void:
	finish = target
	camera = view_camera
	manager = race_manager
	time_limit = limit_seconds
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(camera) or not is_instance_valid(manager) or not manager.is_running:
		return
	var viewport_center := size * 0.5
	var screen_position := viewport_center + (finish - camera.get_screen_center_position()).rotated(-camera.global_rotation) * camera.zoom
	var point := Vector2(clampf(screen_position.x, EDGE_MARGIN, size.x - EDGE_MARGIN), clampf(screen_position.y, EDGE_MARGIN, size.y - EDGE_MARGIN))
	var angle := (screen_position - point).angle() if screen_position.distance_to(point) > 1.0 else -PI * 0.5
	var direction := Vector2.RIGHT.rotated(angle)
	var side := direction.rotated(PI * 0.5)
	draw_colored_polygon(PackedVector2Array([point + direction * 16.0, point - direction * 13.0 + side * 12.0, point - direction * 13.0 - side * 12.0]), Color(1.0, 0.84, 0.15))
	var remaining := maxf(0.0, time_limit - manager.race_time)
	if remaining < WARNING_SECONDS:
		draw_string(ThemeDB.fallback_font, point + Vector2(18.0, 5.0), "%d" % ceili(remaining), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
