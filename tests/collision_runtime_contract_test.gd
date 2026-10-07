extends SceneTree

const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const GENERATED_CIRCUITS := preload("res://scripts/race/generated_circuit_identity.gd")
const VEHICLE_SCENE := preload("res://scenes/vehicles/rustbug.tscn")
const RACE_MANAGER_SCRIPT := preload("res://scripts/race/race_manager.gd")


func _initialize() -> void:
	Engine.physics_ticks_per_second = 120
	call_deferred("_run_test")


func _run_test() -> void:
	var world := Node2D.new()
	root.add_child(world)
	current_scene = world

	var theme: StringName = &"kitchen"
	var room: StringName = &"classic"
	var seed: int = 424242
	var identity: Dictionary = GENERATED_CIRCUITS.create(theme, room, seed)
	if not _expect(not identity.is_empty(), "must generate a kitchen/classic identity"):
		return
	var prepared: Dictionary = TRACK_BUILDER.prepare_layout(theme, room, seed)
	if not _expect(not prepared.is_empty(), "must prepare the layout"):
		return

	var track: Node2D = TRACK_BUILDER.create_layout_root(prepared)
	world.add_child(track)
	await TRACK_BUILDER.assemble_runtime(track, prepared, Callable())

	# Locate a solid boundary or prop section on the generated track
	var solids: Array[StaticBody2D] = []
	for n: Node in track.find_children("*Section*", "StaticBody2D", true, false):
		solids.append(n as StaticBody2D)
	if solids.is_empty():
		for n: Node in track.find_children("*Boundary*", "StaticBody2D", true, false):
			solids.append(n as StaticBody2D)
	if solids.is_empty():
		for n: Node in track.find_children("*", "StaticBody2D", true, false):
			if (n as StaticBody2D).collision_layer != 0:
				solids.append(n as StaticBody2D)
	if not _expect(not solids.is_empty(), "generated track must contain at least one solid StaticBody2D for boundary/prop"):
		return
	var target_solid: StaticBody2D = solids[0]

	# Spawn real rustbug RigidBody2D against the solid at speed
	var vehicle: RigidBody2D = VEHICLE_SCENE.instantiate() as RigidBody2D
	vehicle.name = "ContractVehicle"
	vehicle.position = target_solid.global_position + Vector2(0, 80)
	vehicle.rotation = 0.0
	vehicle.linear_velocity = Vector2(0, -420.0)  # drive straight into solid at speed
	vehicle.angular_velocity = 0.0
	vehicle.set("control_mode", 1)
	vehicle.set("controls_locked", true)
	vehicle.collision_layer = 1
	vehicle.collision_mask = 16 | 2
	vehicle.add_to_group("race_vehicle")
	world.add_child(vehicle)

	var start_dist := vehicle.position.distance_to(target_solid.global_position)
	for _f in 30:
		await physics_frame

	# No tunnelling: must not have passed through the solid (dist should not invert or go tiny negative side)
	var after_dist := vehicle.position.distance_to(target_solid.global_position)
	if not _expect(after_dist > 5.0 and after_dist < start_dist + 30.0, "vehicle must not tunnel through solid at speed (pre=%f post=%f)" % [start_dist, after_dist]):
		return

	# Recovery contract on the generated track: the checkpoint recovery transform
	# the race manager hands out must place the car back inside the corridor.
	# (Wrong-way state itself is covered by wrong_way_route_test with a configured
	# route reference; this guard is about runtime collision + recovery placement
	# on generated geometry.)
	var cp_nodes: Array = track.find_children("*", "", true, false).filter(func(n: Node) -> bool: return n.is_in_group("track_checkpoints"))
	if not _expect(cp_nodes.size() > 0, "generated track must expose checkpoints for recovery"):
		return
	var nearest_cp: Node2D = null
	var nearest_cp_dist := INF
	for cp: Node in cp_nodes:
		var d := vehicle.global_position.distance_to((cp as Node2D).global_position)
		if d < nearest_cp_dist:
			nearest_cp_dist = d
			nearest_cp = cp as Node2D
	var manager: RaceManager = RACE_MANAGER_SCRIPT.new() as RaceManager
	manager.configure_checkpoints(cp_nodes)
	manager.register_racer(vehicle, "Contract", "Rustbug", true)
	manager.prepare_race()
	manager.start_race()
	var recovery: Transform2D = nearest_cp.call("get_recovery_transform") as Transform2D
	vehicle.global_position = recovery.origin
	vehicle.linear_velocity = Vector2.ZERO
	vehicle.angular_velocity = 0.0
	for _f in 4:
		await physics_frame
	var route_distance := INF
	for point: Vector2 in (prepared["centerline"] as PackedVector2Array):
		route_distance = minf(route_distance, vehicle.global_position.distance_to(point))
	if not _expect(route_distance < TRACK_BUILDER.HALF_WIDTH + 200.0, "recovery must place the car back inside the corridor (nearest centerline point %f)" % route_distance):
		return

	manager.free()
	track.free()
	vehicle.free()
	current_scene = null
	world.free()
	print("COLLISION_RUNTIME_CONTRACT_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("COLLISION_RUNTIME_CONTRACT_TEST FAIL: " + message)
	quit(1)
	return false
