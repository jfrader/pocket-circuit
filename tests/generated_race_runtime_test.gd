extends SceneTree

const RACE_SCENE := "res://scenes/race/prototype_race.tscn"
const REQUESTED_SEED := 5


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload should be available"):
		return
	app.call("start_circuit_race", &"workshop", &"square", REQUESTED_SEED, "rustbug")
	var transition_frames := 300
	while transition_frames > 0 and (current_scene == null or current_scene.scene_file_path != RACE_SCENE):
		await process_frame
		transition_frames -= 1
	if not _expect(current_scene != null and current_scene.scene_file_path == RACE_SCENE, "Quick Race should transition through App into the race scene"):
		return
	var session: Dictionary = app.call("get_current_race_session")
	if not _expect(String(session.get("mode", "")) == "quick" and String(session.get("event_id", "")) == "circuit_workshop_square_5", "App should retain the generated Quick Race session"):
		return
	var event: Dictionary = session.get("event", {})
	if not _expect(String(event.get("theme", "")) == "workshop" and String(event.get("room", "")) == "square" and int(event.get("seed", -1)) == REQUESTED_SEED, "App should preserve the requested generated circuit identity"):
		return
	var race := current_scene
	await process_frame

	var track := race.get_node_or_null("Track") as Node2D
	if not _expect(track != null, "race should replace the embedded kitchen with a live generated track"):
		return
	if not _expect(bool(track.get_meta("generated_track", false)) and int(track.get_meta("requested_seed", -1)) == REQUESTED_SEED, "runtime track should retain the requested generated identity"):
		return
	if not _expect(StringName(track.get_meta("theme", &"")) == &"workshop" and StringName(track.get_meta("room_shape", &"")) == &"square", "runtime track should retain the requested theme and room"):
		return
	if not _expect(track.is_in_group("track"), "runtime generated track should retain its persistent track group"):
		return
	if not _expect(race.get_node_or_null("KitchenGraybox") == null, "runtime must not leave the stale embedded kitchen active"):
		return
	if not _expect(track.get_node_or_null("TrackSurface") is Line2D and track.get_node_or_null("TrackRibbon") == null, "generated runtime track should use the clean themed surface without the triangulating base ribbon"):
		return
	var boundary := track.get_node_or_null("InnerBarrier/BoundaryCollision") as CollisionShape2D
	if not _expect(boundary != null and boundary.shape is ConcavePolygonShape2D, "generated island should use a physical concave boundary"):
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
				if not _expect(racing_line.size() == 260, "%s should cache the generated racing line" % vehicle.name):
					return
	if not _expect(ai_controller_count == 3, "runtime race should configure three generated-track AI controllers"):
		return

	race.queue_free()
	app.current_race_session.clear()
	print("GENERATED_RACE_RUNTIME_TEST PASS seed=%d family=%s" % [REQUESTED_SEED, track.get_meta("family", "")])
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("GENERATED_RACE_RUNTIME_TEST FAIL: " + message)
	quit(1)
	return false
