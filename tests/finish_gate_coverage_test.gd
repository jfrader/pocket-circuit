extends SceneTree

const CHECKPOINT_SCENE := preload("res://scenes/race/checkpoint.tscn")
const THEME_SCENES: Dictionary = {
	&"kitchen": "res://scenes/tracks/kitchen_circuit.tscn",
	&"workshop": "res://scenes/tracks/workshop_workbench.tscn",
	&"office": "res://scenes/tracks/office_desk.tscn",
}

func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var checkpoint_scene := CHECKPOINT_SCENE.instantiate()
	var gate_shape := (checkpoint_scene.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	if not _expect(gate_shape.size.is_equal_approx(Vector2(34.0, 280.0)), "checkpoint gates should span the full drivable corridor"):
		return
	checkpoint_scene.free()

	for theme: StringName in [&"kitchen", &"workshop", &"office"]:
		if not await _test_theme_gate(theme):
			return
	print("FINISH_GATE_COVERAGE_TEST PASS")
	quit(0)


func _test_theme_gate(theme: StringName) -> bool:
	var packed := load(String(THEME_SCENES[theme])) as PackedScene
	if not _expect(packed != null, "%s track scene should exist" % theme):
		return false
	var track := packed.instantiate()
	root.add_child(track)
	var finish: Area2D
	for child: Node in track.get_children():
		if child is Area2D and bool(child.get("is_finish_line")):
			finish = child as Area2D
			break
	if not _expect(finish != null, "%s should define a finish-line checkpoint" % theme):
		return false
	var corners := _gate_corners(finish)
	var sensor := finish.get_node("CollisionShape2D") as CollisionShape2D
	var size := (sensor.shape as RectangleShape2D).size * sensor.global_scale.abs()
	var width := size.x
	var height := size.y
	var long_axis := maxf(width, height)
	var short_axis := minf(width, height)
	if not _expect(
		long_axis >= 272.0 and short_axis <= 60.0,
		"%s finish gate should be a full-corridor line (%.0f x %.0f)" % [theme, width, height]
	):
		return false
	var white := track.get_node_or_null("StartFinishWhite") as Polygon2D
	var black := track.get_node_or_null("StartFinishBlack") as Polygon2D
	if not _expect(white != null and black != null and white.visible and black.visible, "%s should show its checker strip at the finish line" % theme):
		return false
	for container_name: String in ["GridForward", "GridReverse"]:
		var container := track.get_node_or_null(container_name) as Node2D
		if not _expect(container != null and container.get_child_count() == 4, "%s should place four %s spawn markers" % [theme, container_name]):
			return false
		for child: Node in container.get_children():
			var marker := child as Node2D
			if marker == null:
				continue
			var marker_position := marker.global_position
			var inside_gate := Rect2(-size * 0.5, size).grow(24.0).has_point(sensor.to_local(marker_position))
			if not _expect(not inside_gate, "%s %s marker %s overlaps the finish gate" % [theme, container_name, child.name]):
				return false
			if not _expect(
				absf(marker_position.x) <= 900.0 and absf(marker_position.y) <= 600.0,
				"%s %s marker %s should stay inside the drivable world bounds" % [theme, container_name, child.name]
			):
				return false
	track.queue_free()
	await process_frame
	await physics_frame
	return true


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
