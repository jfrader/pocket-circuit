extends SceneTree

const TRACK_SCENE := preload("res://scenes/tracks/kitchen_graybox.tscn")
const CHECKPOINT_SCENE := preload("res://scenes/race/checkpoint.tscn")

const FINISH_CENTER := Vector2(-735.0, 240.0)
const GRID_TRANSFORMS: Array[Transform2D] = [
	Transform2D(PI * 0.5, Vector2(-600.0, 315.0)),
	Transform2D(PI * 0.5, Vector2(-630.0, 410.0)),
	Transform2D(PI * 0.5, Vector2(-660.0, 315.0)),
	Transform2D(PI * 0.5, Vector2(-690.0, 410.0)),
]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var checkpoint_scene := CHECKPOINT_SCENE.instantiate()
	var gate_shape := (checkpoint_scene.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	if not _expect(gate_shape.size.is_equal_approx(Vector2(34.0, 280.0)), "checkpoint gates should span the full drivable corridor"):
		return

	var track := TRACK_SCENE.instantiate()
	root.add_child(track)
	var finish := track.get_node("Checkpoint0Finish") as Area2D
	var corners := _gate_corners(finish)
	if not _expect(
		finish.position.is_equal_approx(FINISH_CENTER),
		"the finish gate should sit on the left straight behind the start grid"
	):
		return
	if not _expect(
		corners["min_x"] <= -874.0
		and corners["max_x"] >= -596.0
		and corners["min_y"] <= 224.0
		and corners["max_y"] >= 256.0,
		"the finish gate should reach edge to edge of the drivable corridor (%.0f..%.0f x %.0f..%.0f)" % [corners["min_x"], corners["max_x"], corners["min_y"], corners["max_y"]]
	):
		return
	for grid_transform: Transform2D in GRID_TRANSFORMS:
		var grid_origin := grid_transform.origin
		if not _expect(grid_origin.y >= corners["max_y"] + 20.0, "the start grid should sit past the finish gate in driving order (grid=%s gate_bottom=%.0f)" % [str(grid_origin), corners["max_y"]]):
			return
	if not _expect(track.get_node_or_null("Labels") == null, "debug track labels should be removed"):
		return
	if not _expect(track.get_node_or_null("ArtSurfaces/StartFinish") == null, "the misplaced illustrated start/finish sprite should be removed"):
		return
	print("FINISH_GATE_COVERAGE_TEST PASS")
	quit(0)


func _gate_corners(gate: Area2D) -> Dictionary:
	var shape := (gate.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	var half := shape.size * 0.5
	var corners := [
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	]
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for corner: Vector2 in corners:
		var world := gate.position + corner.rotated(gate.rotation)
		min_x = minf(min_x, world.x)
		max_x = maxf(max_x, world.x)
		min_y = minf(min_y, world.y)
		max_y = maxf(max_y, world.y)
	return {"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y}


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("FINISH_GATE_COVERAGE_TEST FAIL: " + message)
	quit(1)
	return false
