extends RefCounted

const VISUALS := preload("res://scripts/race/strip/traffic_visuals.gd")
const ROOM_DRAW_MARGIN := 800.0


static func draw_runner(camera: Camera2D, room: PackedVector2Array, traffic: StripTraffic, draw_frame: Callable, cancelled: Callable) -> Dictionary:
	var bounds := Rect2(room[0], Vector2.ZERO)
	for point in room:
		bounds = bounds.expand(point)
	bounds = bounds.grow(ROOM_DRAW_MARGIN)
	var viewport_size := camera.get_viewport_rect().size
	var fit := minf(viewport_size.x / bounds.size.x, viewport_size.y / bounds.size.y)
	var original_transform := camera.global_transform
	var original_zoom := camera.zoom
	var original_offset := camera.offset
	var original_smoothing := camera.position_smoothing_enabled
	var original_interpolation := camera.physics_interpolation_mode
	var original_process := camera.process_mode
	camera.process_mode = Node.PROCESS_MODE_DISABLED
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.position_smoothing_enabled = false
	camera.offset = Vector2.ZERO
	camera.zoom = Vector2.ONE * fit
	camera.global_position = bounds.get_center()
	camera.reset_smoothing()
	camera.force_update_scroll()
	var drawn := 0
	# The loading callback waits for frame_post_draw on rendered runs. A wide
	# view includes both rooms; cycling prepared poses also draws every traffic
	# texture without advancing its rolling distance or the simulation.
	for pose in VISUALS.MOTION_POSE_COUNT:
		if cancelled.call():
			break
		traffic.show_warmup_pose(pose)
		await draw_frame.call()
		drawn += 1
	traffic.restore_warmup_pose()
	camera.global_transform = original_transform
	camera.zoom = original_zoom
	camera.offset = original_offset
	camera.position_smoothing_enabled = original_smoothing
	camera.physics_interpolation_mode = original_interpolation
	camera.process_mode = original_process
	camera.reset_physics_interpolation()
	camera.reset_smoothing()
	camera.force_update_scroll()
	return {"bounds": bounds, "zoom": fit, "frames": drawn, "complete": drawn == VISUALS.MOTION_POSE_COUNT}
