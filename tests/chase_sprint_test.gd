extends SceneTree

const FIXED_FPS := 60
const RACE := preload("res://scripts/race/prototype_race.gd")
const SPRITES := preload("res://scripts/vendor/procedural_2d/procedural_car_sprites.gd")
const SCENE := preload("res://scenes/race/prototype_race.tscn")
const VEHICLE := preload("res://scenes/vehicles/rustbug.tscn")
const TRAFFIC_CAR := preload("res://scripts/race/strip/traffic_car.gd")
const SAMPLER := preload("res://scripts/race/strip/strip_route_sampler.gd")

var reports: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var script := load("res://scripts/race/chase_sprint_controller.gd") as Script
	if script == null:
		_fail("Missing sprint controller")
		return
	var manager := RaceManager.new()
	var player := VehicleController.new()
	var chaser := VehicleController.new()
	root.add_child(manager)
	root.add_child(player)
	root.add_child(chaser)
	var controller: Node2D = script.new()
	root.add_child(controller)
	controller.configure(manager, player, chaser)
	controller.set_physics_process(false)
	controller.sprint_resolved.connect(func(outcome: String, data: Dictionary) -> void: reports.append({"outcome": outcome, "data": data}))
	await process_frame
	manager.is_running = true
	player.freeze = false
	chaser.freeze = false
	chaser.position = Vector2.RIGHT * SPRITES.IMAGE_WIDTH * 2.0
	controller.advance_pursuit(0.1)
	if not _check(reports.is_empty() and controller.capture_fraction() > 0.0, "Tap captures or arc does not fill"):
		return
	var wall := StaticBody2D.new()
	wall.collision_layer = 2
	wall.collision_mask = 0
	wall.position = chaser.position * 0.5
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12, 200)
	collision.shape = shape
	wall.add_child(collision)
	root.add_child(wall)
	await physics_frame
	await physics_frame
	controller.advance_pursuit(1.5)
	if not _check(reports.is_empty() and controller.capture_fraction() == 0.0, "A wall between nearby cars must prevent capture and reset exposure"):
		return
	wall.free()
	await physics_frame
	var first_gate := preload("res://scripts/race/checkpoint.gd").new()
	first_gate.checkpoint_index = 1
	var finish_gate := preload("res://scripts/race/checkpoint.gd").new()
	finish_gate.checkpoint_index = 2
	finish_gate.position.y = -1000.0
	root.add_child(first_gate)
	root.add_child(finish_gate)
	manager.configure_strip_route(1, 2)
	manager.configure_checkpoints([first_gate, finish_gate])
	manager.register_racer(player, "Player", "Rustbug", true)
	manager.register_racer(chaser, "Chaser", "Pinbolt")
	controller.advance_pursuit(0.1)
	if not _check(manager.report_checkpoint(first_gate, player), "Player should enter the next strip section"):
		return
	controller.advance_pursuit(1.5)
	if not _check(reports.is_empty() and controller.capture_fraction() == 0.0, "Nearby cars on different strip sections must not capture"):
		return
	if not _check(manager.report_checkpoint(first_gate, chaser), "Chaser should rejoin the player's strip section"):
		return
	controller.advance_pursuit(0.1)
	controller.advance_pursuit(1.39)
	chaser.position.x += 0.1
	controller.advance_pursuit(0.01)
	if not _check(controller.capture_fraction() == 0.0, "Leaving two-width range must reset continuous exposure"):
		return
	chaser.position.x -= 0.1
	controller.advance_pursuit(1.49)
	if not _check(reports.is_empty(), "Capture fired before 1.5 seconds"):
		return
	controller.advance_pursuit(0.01)
	controller.win(2.0)
	if not _check(reports.size() == 1 and reports[0].outcome == "CAUGHT" and reports[0].data.terminal and not manager.is_running, "Caught result must be terminal and one-shot"):
		return
	controller.free()
	controller = script.new()
	root.add_child(controller)
	controller.configure(manager, player, chaser, true)
	controller.set_physics_process(false)
	controller.sprint_resolved.connect(func(outcome: String, data: Dictionary) -> void: reports.append({"outcome": outcome, "data": data}))
	reports.clear()
	manager.is_running = true
	manager.race_time = 179.9
	chaser.position = Vector2.ONE * 1000.0
	controller.advance_pursuit(0.09)
	if not _check(reports.is_empty(), "Rescue fired before 180 seconds"):
		return
	controller.advance_pursuit(0.1)
	if not _check(reports.size() == 1 and reports[0].outcome == "RESCUED" and not reports[0].data.terminal and manager.is_running and chaser.freeze, "Rescue must break pursuit without ending the drive"):
		return
	controller.advance_pursuit(10.0)
	controller.win(195.0)
	controller.win(196.0)
	if not _check(reports.size() == 2 and reports[1].outcome == "ARRIVED" and reports[1].data.rescued and reports[1].data.elapsed == 195.0, "Arrival after rescue must resolve once"):
		return
	controller.free()
	controller = script.new()
	root.add_child(controller)
	controller.configure(manager, player, chaser)
	controller.win(70.0)
	if not _check(controller.result().outcome == "ARRIVED" and not controller.result().rescued, "Clean arrival contract"):
		return
	var race := RACE.new()
	race.set("_session", {"mode": "chase_sprint", "vehicle_id": "rustbug", "chaser": {"id": "robbed-42", "name": "Robbed Driver", "vehicle_id": "pinbolt"}})
	var field: Array[Dictionary] = race.call("_build_field_racers_for_preparation")
	var driver: Dictionary = race.call("_chase_driver")
	if not _check(field.size() == 2 and field[1].driver_id == "robbed-42" and field[1].vehicle_id == "pinbolt" and driver.name == "Robbed Driver", "Sprint must use session chaser identity and vehicle"):
		return
	if not _check(race.call("_is_strip_route"), "Sprint must reuse strip route"):
		return
	race.free()
	controller.free()
	player.free()
	chaser.free()
	manager.free()
	first_gate.free()
	finish_gate.free()
	if not _scene_contract():
		return
	if not await _traffic_clip():
		return
	print("CHASE_SPRINT_TEST PASS continuous_two_width_capture arc identity arrived caught nonterminal_180s_rescue scene_seam traffic_speed_cost")
	quit(0)


func _scene_contract() -> bool:
	var app := root.get_node("App")
	app.set("current_race_session", {
		"mode": "chase_sprint", "vehicle_id": "rustbug",
		"chaser": {"id": "robbed-42", "name": "Robbed Driver", "vehicle_id": "pinbolt"},
		"event": {"id": "chase-test", "name": "Carry it home", "circuit": "generated", "race_format": "strip", "theme": "kitchen", "room": "classic", "seed": 42, "length_tier": "standard"},
	})
	var scene := SCENE.instantiate()
	root.add_child(scene)
	var controller := scene.get("_strip_controller") as Node2D
	if not _check(controller != null and controller.get_script().resource_path.ends_with("chase_sprint_controller.gd"), "Scene did not select sprint controller"):
		return false
	var manager := scene.get_node("RaceManager") as RaceManager
	var chaser := controller.get("chaser") as VehicleController
	var state := manager.get_racer_state(chaser)
	if not _check(manager.get_racer_count() == 2 and state.driver_name == "Robbed Driver" and chaser.get_meta("audio_vehicle_id") == "pinbolt", "Scene lost session identity or spawned exhibition rivals"):
		return false
	if not _check(scene.get_node_or_null("StripTraffic") != null and is_zero_approx((scene.get("camera") as Camera2D).rotation), "Scene lost traffic or north camera"):
		return false
	reports.clear()
	scene.sprint_resolved.connect(func(value: String, data: Dictionary) -> void: reports.append({"outcome": value, "data": data}))
	manager.is_running = true
	var player := controller.get("player") as VehicleController
	manager.prepare_race()
	manager.is_running = true
	manager.race_time = 72.0
	for checkpoint in manager.checkpoints:
		if int(checkpoint.get("checkpoint_index")) > 0:
			manager.report_checkpoint(checkpoint, player)
	if not _check(reports.size() == 1 and reports[0].outcome == "ARRIVED" and scene.call("get_sprint_result").outcome == "ARRIVED", "Scene must forward terminal result and expose getter"):
		return false
	if not _check(not (scene.get("_retry_button") as Button).visible and (scene.get("_continue_button") as Button).visible, "Sprint results must offer continue, not replay a won haul"):
		return false
	scene.free()
	app.set("current_race_session", {})
	return true


func _traffic_clip() -> bool:
	var player := VEHICLE.instantiate() as VehicleController
	var clear_lane := VEHICLE.instantiate() as VehicleController
	clear_lane.position.x = 600.0
	var chaser := VehicleController.new()
	chaser.freeze = true
	chaser.position = Vector2.ONE * 2000.0
	root.add_child(player)
	root.add_child(clear_lane)
	root.add_child(chaser)
	for car in [player, clear_lane]:
		car.collision_mask |= 1
		car.set_player_controlled(false)
		car.set_external_controls(0.0, 0.0, 0.0)
	var sampler := SAMPLER.new()
	sampler.configure(PackedVector2Array([Vector2(14.0, -1000.0), Vector2(14.0, 1000.0)]))
	var traffic := TRAFFIC_CAR.new()
	traffic.configure(915.0, 1.0, 100.0, &"cruiser", "rustbug", sampler, 1.0)
	root.add_child(traffic)
	var manager := RaceManager.new()
	root.add_child(manager)
	var controller: Node2D = load("res://scripts/race/chase_sprint_controller.gd").new()
	root.add_child(controller)
	controller.configure(manager, player, chaser)
	for frame in 3:
		await physics_frame
	manager.is_running = true
	player.linear_velocity = Vector2.UP * 600.0
	clear_lane.linear_velocity = Vector2.UP * 600.0
	var touched := false
	var speed_cost := 0.0
	for frame in 30:
		await physics_frame
		touched = touched or player.has_static_contact
		speed_cost = maxf(speed_cost, clear_lane.linear_velocity.dot(Vector2.UP) - player.linear_velocity.dot(Vector2.UP))
	var valid := _check(touched and speed_cost > 25.0 and manager.is_running and controller.result().is_empty(), "Actual traffic clipping must cost speed, not resolve the run: touched=%s speed_cost=%.1f running=%s" % [touched, speed_cost, manager.is_running])
	controller.free()
	manager.free()
	traffic.free()
	player.free()
	clear_lane.free()
	chaser.free()
	return valid


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_fail(message)
	return condition


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
