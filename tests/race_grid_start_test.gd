extends SceneTree

const PROTOTYPE := preload("res://scenes/race/prototype_race.tscn")
const CASES := [[&"kitchen", &"long", 24469], [&"workshop", &"square", 51940]]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for case: Array in CASES:
		for reverse in [false, true]:
			if not await _check_start(case, reverse):
				return
	print("RACE_GRID_START_TEST PASS four_fields")
	quit(0)


func _check_start(case: Array, reverse: bool) -> bool:
	var race := PROTOTYPE.instantiate()
	race.set("_session", {"event": {"theme": case[0], "circuit": "generated", "room": case[1], "seed": case[2], "reverse": reverse}, "difficulty": "club_circuit"})
	root.add_child(race)
	current_scene = race
	var manager := race.get_node("RaceManager") as RaceManager
	var expected: Array = race.call("_grid_transforms", reverse)
	for settle in 6:
		await create_timer(0.1).timeout
	paused = false
	var racers := manager.get_rankings()
	var starts: Dictionary = {}
	var valid := _expect(racers.size() == 4, "the full four-car field must exist")
	for racer: Node2D in racers:
		var state := manager.get_racer_state(racer)
		var slot := int(state["registration_index"])
		var pose := expected[slot] as Transform2D
		valid = _expect(racer.global_position.distance_to(pose.origin) < 2.0, "%s must remain in grid slot %d during countdown" % [racer.name, slot]) and valid
		starts[racer] = pose
		var collision := racer.get_node("CollisionShape2D") as CollisionShape2D
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = collision.shape
		query.transform = collision.global_transform
		query.collision_mask = 2 | 4 | 16
		query.exclude = [(racer as RigidBody2D).get_rid()]
		valid = _expect(racer.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(), "%s grid footprint must not touch solid scenery" % racer.name) and valid
	for wait in 30:
		if manager.is_running:
			break
		await create_timer(0.1).timeout
	valid = _expect(manager.is_running, "countdown must start the race") and valid
	for frame in 6:
		await physics_frame
	for racer: Node2D in racers:
		var body := racer as RigidBody2D
		var pose := starts[racer] as Transform2D
		valid = _expect(body.global_position.distance_to(pose.origin) < 35.0, "%s must launch from the grid, not jump to stale physics coordinates" % racer.name) and valid
		valid = _expect(not body.freeze and body.collision_layer != 0 and body.collision_mask != 0, "%s must have normal collision restored after launch synchronization" % racer.name) and valid
	current_scene = null
	root.remove_child(race)
	race.free()
	await process_frame
	await physics_frame
	return valid


func _expect(ok: bool, message: String) -> bool:
	if not ok:
		push_error("RACE_GRID_START_TEST FAIL: " + message)
		quit(1)
	return ok
