extends SceneTree

const AUDIO_DIRECTOR_SCRIPT := preload("res://scripts/audio/audio_director.gd")


class RemoteCar extends Node2D:
	var speed := 400.0
	var stats: VehicleStats = preload("res://data/vehicles/rustbug.tres")

	func get_engine_load() -> float:
		return 0.8

	func get_throttle_input() -> float:
		return 0.8


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var errors := PackedStringArray()
	var director := AUDIO_DIRECTOR_SCRIPT.new()
	root.add_child(director)
	await process_frame
	var cars: Array[Node] = []
	for index in 4:
		var car := RemoteCar.new()
		car.position = Vector2(40.0 * float(index + 1), 0.0)
		car.set_meta("audio_vehicle_id", "rustbug")
		root.add_child(car)
		cars.append(car)
	director.set_positional_vehicles(cars)
	var emitters: Array[Node] = director.call("get_positional_engine_emitters")
	if emitters.size() != 4:
		errors.append("each rival should get an engine emitter, got %d" % emitters.size())
	else:
		var stream := AudioStreamWAV.new()
		stream.set_meta("base_rpm", 3000.0)
		for emitter: Node in emitters:
			emitter.call("set_stream", stream)
			if (emitter.call("get_player") as AudioStreamPlayer2D).bus != &"Engine":
				errors.append("rival engines must use the Engine bus")
		director.call("_update_positional_engines", 0.05)
		var voiced := 0
		var farthest_voiced := false
		for index in emitters.size():
			var emitter: Node = emitters[index]
			if bool(emitter.call("is_voiced")):
				voiced += 1
			if index == emitters.size() - 1 and bool(emitter.call("is_voiced")):
				farthest_voiced = true
			var player := emitter.call("get_player") as AudioStreamPlayer2D
			if player.pitch_scale < 0.5 or player.pitch_scale > 1.7:
				errors.append("rival engine pitch left the allowed range")
		if voiced > 3:
			errors.append("only the nearest 3 rivals should be voiced, got %d" % voiced)
		if farthest_voiced:
			errors.append("the farthest rival should be culled")
	if director.call("warm_vehicle_audio", "rustbug"):
		errors.append("headless runs must not generate opponent engine audio")
	for car: Node in cars:
		car.queue_free()
	director.queue_free()
	await process_frame
	if errors.is_empty():
		print("POSITIONAL_ENGINE_AUDIO_TEST PASS")
		quit(0)
		return
	for error in errors:
		push_error("POSITIONAL_ENGINE_AUDIO_TEST FAIL: " + error)
	quit(1)
