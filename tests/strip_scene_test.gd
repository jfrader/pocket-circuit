extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var prepared := BUILDER.prepare_layout(&"kitchen", &"classic", 42, {"route_shape": "strip"})
	if prepared.is_empty():
		_fail("Strip layout unavailable")
		return
	var root := BUILDER.create_layout_root(prepared)
	get_root().add_child(root)
	await BUILDER.assemble_runtime(root, prepared, Callable())
	var line := root.get_node_or_null("RacingLine") as Line2D
	var road := root.get_node_or_null("TrackSurface") as Line2D
	var start_cap := root.get_node_or_null("StartCap") as StaticBody2D
	var finish_cap := root.get_node_or_null("FinishCap") as StaticBody2D
	var caps := start_cap != null and finish_cap != null and start_cap.get_children().any(func(child: Node) -> bool: return child is CollisionShape2D) and finish_cap.get_children().any(func(child: Node) -> bool: return child is CollisionShape2D)
	var gates := get_nodes_in_group("track_checkpoints")
	var okay := line != null and not line.closed and road != null and not road.closed and caps and gates.size() == (prepared["strip_gates"] as Array).size() and root.get_node_or_null("GridForward") != null
	root.free()
	if not okay:
		_fail("Open road assembly missing caps, gates, grid, or open lines")
		return
	var packed_result := BUILDER.build_packed(&"kitchen", &"classic", 42, {"route_shape": "strip"})
	var packed := packed_result.get("scene") as PackedScene
	if packed == null:
		_fail("Strip could not be packed")
		return
	var instance := packed.instantiate()
	if instance.get_node_or_null("StartCap") == null or instance.get_node_or_null("FinishCap") == null or instance.get_node_or_null("RacingLine") == null:
		instance.free()
		_fail("Packed strip lost open-road nodes")
		return
	instance.free()
	print("STRIP_SCENE_TEST PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
