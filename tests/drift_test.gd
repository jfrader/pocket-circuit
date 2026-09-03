extends SceneTree

const PROTOTYPE_SCENE := preload("res://scenes/race/prototype_race.tscn")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var prototype := PROTOTYPE_SCENE.instantiate()
	root.add_child(prototype)
	current_scene = prototype

	for settle in 6:
		await create_timer(0.1).timeout
	paused = false

	for _frame in 5:
		await physics_frame

	var vehicle := get_first_node_in_group("player_vehicle") as RigidBody2D
	if vehicle == null:
		_fail("player_vehicle was not found")
		return
	var race_manager := get_first_node_in_group("race_manager") as RaceManager
	if race_manager == null:
		_fail("race_manager was not found")
		return
	var started := [race_manager.is_running]
	if not started[0]:
		race_manager.race_started.connect(func() -> void: started[0] = true, CONNECT_ONE_SHOT)
	var timeout_frames := 300
	while not bool(started[0]) and timeout_frames > 0:
		await physics_frame
		timeout_frames -= 1
	if not bool(started[0]):
		_fail("race_started was not emitted before the timeout")
		return

	Input.action_press("accelerate")
	var peak_speed := 0.0
	for _frame in 90:
		await physics_frame
		peak_speed = maxf(peak_speed, float(vehicle.get("speed")))

	Input.action_press("handbrake")
	Input.action_press("steer_right")
	var drift_seen := false
	var drift_speed := 0.0
	var max_slip := 0.0
	for _frame in 60:
		await physics_frame
		var current_speed := float(vehicle.get("speed"))
		var current_slip := absf(float(vehicle.get("slip_angle")))
		max_slip = maxf(max_slip, current_slip)
		if bool(vehicle.get("is_drifting")):
			drift_seen = true
			drift_speed = maxf(drift_speed, current_speed)

	Input.action_release("accelerate")
	Input.action_release("handbrake")
	Input.action_release("steer_right")

	print("DRIFT_TEST observed peak_speed=%.2f drift_speed=%.2f is_drifting=%s max_slip=%.2f" % [
		peak_speed,
		drift_speed,
		str(drift_seen),
		max_slip,
	])
	if drift_seen and max_slip > 12.0:
		print("DRIFT_TEST PASS")
		quit(0)
	else:
		_fail("drift state or slip angle did not reach the expected range")


func _fail(message: String) -> void:
	Input.action_release("accelerate")
	Input.action_release("handbrake")
	Input.action_release("steer_right")
	push_error("DRIFT_TEST FAIL: " + message)
	quit(1)
