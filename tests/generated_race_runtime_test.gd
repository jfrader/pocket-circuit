extends SceneTree

const RACE_SCENE := "res://scenes/race/prototype_race.tscn"
const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const REQUESTED_SEED := 8


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload should be available"):
		return
	app.call("start_circuit_race", &"office", &"el", REQUESTED_SEED, "rustbug")
	var deadline := Time.get_ticks_msec() + 45000
	while app.call("is_race_loading") and not app.get("_loading_failed") and Time.get_ticks_msec() < deadline:
		await process_frame
	if not _expect(not app.call("is_race_loading") and not app.get("_loading_failed"), "Quick Race preparation should complete successfully before inspecting gameplay"):
		return
	if not _expect(current_scene != null and current_scene.scene_file_path == RACE_SCENE, "Quick Race should transition through App into the race scene"):
		return
	var session: Dictionary = app.call("get_current_race_session")
	if not _expect(String(session.get("mode", "")) == "quick" and String(session.get("event_id", "")) == "circuit_office_el_8", "App should retain the generated Quick Race session"):
		return
	var event: Dictionary = session.get("event", {})
	if not _expect(String(event.get("theme", "")) == "office" and String(event.get("room", "")) == "el" and int(event.get("seed", -1)) == REQUESTED_SEED, "App should preserve the requested generated circuit identity"):
		return
	var race := current_scene

	var track := race.get_node_or_null("Track") as Node2D
	if not _expect(track != null, "race should replace the embedded kitchen with a live generated track"):
		return
	if not _expect(bool(track.get_meta("generated_track", false)) and int(track.get_meta("requested_seed", -1)) == REQUESTED_SEED, "runtime track should retain the requested generated identity"):
		return
	if not _expect(StringName(track.get_meta("theme", &"")) == &"office" and StringName(track.get_meta("room_shape", &"")) == &"el", "runtime track should retain the requested theme and room"):
		return
	if not _expect(track.is_in_group("track"), "runtime generated track should retain its persistent track group"):
		return
	if not _expect(race.get_node_or_null("KitchenGraybox") == null, "runtime must not leave the stale embedded kitchen active"):
		return
	if not _expect(track.get_node_or_null("TrackSurface") is Line2D and track.get_node_or_null("TrackRibbon") == null, "generated runtime track should use the clean themed surface without the triangulating base ribbon"):
		return
	var track_surface: PackedVector2Array = (track.get_node_or_null("TrackSurface") as Line2D).points
	if not _expect(track_surface.size() >= 260, "generated track surface should be arc-length-uniform at >=260 samples (got %d)" % track_surface.size()):
		return
	var surface_max_gap := 0.0
	for index in track_surface.size():
		surface_max_gap = maxf(surface_max_gap, track_surface[index].distance_to(track_surface[(index + 1) % track_surface.size()]))
	if not _expect(surface_max_gap <= 35.0 + 1.0, "generated track surface should respect the shared sampler's 35u max spacing (got %.1f)" % surface_max_gap):
		return
	var boundary := track.get_node_or_null("InnerBarrier/BoundaryCollision") as CollisionShape2D
	if not _expect(boundary != null and boundary.shape is ConcavePolygonShape2D and track.get_node_or_null("InnerBarrier/SideFace") is Line2D and track.get_node_or_null("InnerBarrier/TexturedRim") is Line2D and track.get_node_or_null("InnerBarrier/TopLip") is Line2D, "generated island should use a physical concave boundary backed by a raised visible rim"):
		return
	if not _expect(track.get_node_or_null("OuterBarrier") == null and track.get_node_or_null("ContinuousBoundaryBacking") == null, "generated runtime track should leave its room apron open between real colliding assets"):
		return
	var reset_manager := race.get_node_or_null("ResetManager")
	var expected_bounds := (track.get_meta("room_bounds") as Rect2).grow(120.0)
	var room_polygon: PackedVector2Array = track.get_meta("room_polygon", PackedVector2Array())
	var island_polygon: PackedVector2Array = track.get_meta("island_invalid_polygon", PackedVector2Array())
	if not _expect(reset_manager != null and reset_manager.get("valid_bounds") == expected_bounds and reset_manager.get("valid_polygon") == room_polygon and reset_manager.get("invalid_polygon") == island_polygon, "generated room and raised-island geometry should propagate to runtime reset validation"):
		return
	var missing_quadrant := Vector2(1400.0, -800.0)
	if not _expect(expected_bounds.has_point(missing_quadrant) and not bool(reset_manager.call("is_position_valid", missing_quadrant)), "L-room recovery should reject its missing upper-right quadrant"):
		return
	var island_center := Vector2.ZERO
	for island_point: Vector2 in island_polygon:
		island_center += island_point
	island_center /= maxf(float(island_polygon.size()), 1.0)
	if not _expect(not island_polygon.is_empty() and not bool(reset_manager.call("is_position_valid", island_center)), "recovery should reject the raised island interior"):
		return
	var camera := race.get_node_or_null("FollowCamera2D") as Camera2D
	var room_bounds: Rect2 = track.get_meta("room_bounds")
	if not _expect(camera != null and camera.limit_left == floori(room_bounds.position.x) and camera.limit_top == floori(room_bounds.position.y) and camera.limit_right == ceili(room_bounds.end.x) and camera.limit_bottom == ceili(room_bounds.end.y), "generated room bounds should expand the runtime camera limits"):
		return
	var finish := track.get_node_or_null("Checkpoint0Finish") as Area2D
	if not _expect(finish != null and float(finish.get_meta("sensor_span", 0.0)) >= BUILDER.HALF_WIDTH * 2.0 - 0.5 and bool(finish.get_meta("sensor_asymmetric_span", false)), "runtime finish sensor should cover the corridor and available outer apron while stopping on the island side"):
		return
	if not await _probe_inner_rim(track):
		return
	if not await _probe_open_apron(track):
		return

	var grid := track.get_node_or_null("GridForward") as Node2D
	if not _expect(grid != null and grid.get_child_count() == 4, "generated forward grid should expose four markers"):
		return
	var marker_positions: Array[Vector2] = []
	for marker: Node2D in grid.get_children():
		marker_positions.append(marker.global_position)
	var vehicles := get_nodes_in_group("race_vehicle")
	if not _expect(vehicles.size() == 4, "runtime race should configure four racers"):
		return
	var ai_controller_count := 0
	var shortcut_controller_count := 0
	for vehicle: Node2D in vehicles:
		var nearest := INF
		for marker_position: Vector2 in marker_positions:
			nearest = minf(nearest, vehicle.global_position.distance_to(marker_position))
		if not _expect(nearest < 12.0, "%s should remain on the generated start grid after physics begins (distance %.1f)" % [vehicle.name, nearest]):
			return
		for child: Node in vehicle.get_children():
			if child is AIVehicleController:
				ai_controller_count += 1
				var racing_line: PackedVector2Array = child.get("_racing_line")
				if not _expect(racing_line.size() >= 260, "%s should cache the generated racing line at arc-length-uniform density (got %d)" % [vehicle.name, racing_line.size()]):
					return
				if child.uses_shortcut_line:
					shortcut_controller_count += 1
				var selected_line := track.get_node("ShortcutRacingLine" if child.uses_shortcut_line else "RacingLine") as Line2D
				for index in racing_line.size():
					if not _expect(racing_line[index].is_equal_approx(selected_line.to_global(selected_line.points[index])), "%s should cache its selected legal route rather than the embedded fixture" % vehicle.name):
						return
	if not _expect(ai_controller_count == 3, "runtime race should configure three generated-track AI controllers"):
		return
	if not _expect(shortcut_controller_count > 0 and shortcut_controller_count < ai_controller_count, "the mixed Club roster should retain both safe and shortcut routing choices"):
		return

	race.queue_free()
	app.current_race_session.clear()
	print("GENERATED_RACE_RUNTIME_TEST PASS seed=%d family=%s" % [REQUESTED_SEED, track.get_meta("family", "")])
	quit(0)


func _probe_open_apron(track: Node2D) -> bool:
	var centerline := (track.get_node("TrackSurface") as Line2D).points
	var visuals := track.get_node_or_null("GeneratedOuterBoundaryVisuals")
	var run_modes: Array = visuals.get_meta("run_modes", []) if visuals else []
	var open_run := run_modes.find(&"none")
	if not _expect(open_run >= 0 and not centerline.is_empty(), "open apron probe needs one intentionally empty rail sector"):
		return false
	var run_center := int(round((float(open_run) + 0.5) * float(centerline.size()) / 8.0)) % centerline.size()
	var room_polygon: PackedVector2Array = track.get_meta("room_polygon", PackedVector2Array())
	var island_polygon: PackedVector2Array = track.get_meta("island_invalid_polygon", PackedVector2Array())
	for center_offset in range(-12, 13, 3):
		var index := posmod(run_center + center_offset, centerline.size())
		var tangent := (centerline[(index + 1) % centerline.size()] - centerline[(index - 1 + centerline.size()) % centerline.size()]).normalized()
		var normal := tangent.rotated(PI * 0.5)
		for side: float in [-1.0, 1.0]:
			var motion := normal * 260.0 * side
			var target := centerline[index] + motion
			if not Geometry2D.is_point_in_polygon(target, room_polygon) or Geometry2D.is_point_in_polygon(target, island_polygon):
				continue
			var probe := CharacterBody2D.new()
			probe.name = "OpenApronProbe"
			probe.collision_layer = 1
			probe.collision_mask = 2 | 4 | 16
			probe.position = centerline[index]
			var probe_collision := CollisionShape2D.new()
			var probe_shape := CircleShape2D.new()
			probe_shape.radius = 14.0
			probe_collision.shape = probe_shape
			probe.add_child(probe_collision)
			track.add_child(probe)
			await physics_frame
			var hit := probe.move_and_collide(motion)
			probe.queue_free()
			if hit == null:
				return true
	return _expect(false, "a vehicle should be able to drive from the racing corridor into the open apron without hitting an invisible contour")


func _probe_inner_rim(track: Node2D) -> bool:
	var centerline := (track.get_node("TrackSurface") as Line2D).points
	var island_polygon: PackedVector2Array = track.get_meta("island_invalid_polygon", PackedVector2Array())
	for index in range(0, centerline.size(), 26):
		var inner_direction := centerline[index].direction_to(_closest_point_on_loop(centerline[index], island_polygon))
		var probe := CharacterBody2D.new()
		probe.name = "InnerRimProbe"
		probe.collision_layer = 1
		probe.collision_mask = 2 | 4 | 16
		probe.position = centerline[index]
		var probe_collision := CollisionShape2D.new()
		var probe_shape := CircleShape2D.new()
		probe_shape.radius = 14.0
		probe_collision.shape = probe_shape
		probe.add_child(probe_collision)
		track.add_child(probe)
		await physics_frame
		var hit := probe.move_and_collide(inner_direction * 260.0)
		probe.queue_free()
		if not _expect(hit != null, "the visible raised island should physically stop an inside cut at sample %d" % index):
			return false
	return true


func _closest_point_on_loop(point: Vector2, loop: PackedVector2Array) -> Vector2:
	var result := loop[0]
	var nearest_distance := INF
	for index in loop.size():
		var from := loop[index]
		var to := loop[(index + 1) % loop.size()]
		var segment := to - from
		var fraction := clampf((point - from).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
		var candidate := from + segment * fraction
		var distance := point.distance_squared_to(candidate)
		if distance < nearest_distance:
			nearest_distance = distance
			result = candidate
	return result


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("GENERATED_RACE_RUNTIME_TEST FAIL: " + message)
	quit(1)
	return false
