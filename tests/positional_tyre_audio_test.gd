extends SceneTree

const EMITTER := preload("res://scripts/audio/vehicle_loop_emitter.gd")
const LOOP_GENERATOR := preload("res://scripts/audio/sfx/tyre_loop_generator.gd")
const PROFILES := preload("res://scripts/audio/sfx/tyre_surface_profiles.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var errors := PackedStringArray()
	var source := Node2D.new()
	root.add_child(source)
	var emitter := EMITTER.new()
	root.add_child(emitter)
	emitter.configure(source, 500.0)
	var stream: AudioStreamWAV = LOOP_GENERATOR.generate(PROFILES.profile_for(&"workbench"))
	emitter.set_stream(stream)
	emitter.update_voice(Vector2.ZERO, 0.7, 1.1)
	var player := emitter.get_player() as AudioStreamPlayer2D
	if player == null:
		errors.append("emitter must own an AudioStreamPlayer2D")
	else:
		if not player.stream is AudioStreamWAV or player.stream is AudioStreamGenerator:
			errors.append("opponent voice must use a generated WAV, never real-time generator DSP")
		if stream.loop_mode != AudioStreamWAV.LOOP_FORWARD or stream.loop_end <= stream.loop_begin:
			errors.append("opponent WAV must be a real forward loop")
		if not is_equal_approx(player.pitch_scale, 1.1):
			errors.append("emitter must apply the state pitch")
	if emitter.is_distance_culled():
		errors.append("nearby vehicle should not be distance culled")
	source.position = Vector2(501.0, 0.0)
	emitter.update_voice(Vector2.ZERO, 1.0, 1.0)
	if not emitter.is_distance_culled():
		errors.append("distant vehicle should be culled before playback")

	emitter.queue_free()
	source.queue_free()
	await process_frame
	if errors.is_empty():
		print("POSITIONAL_TYRE_AUDIO_TEST PASS")
		quit(0)
		return
	for error in errors:
		push_error("POSITIONAL_TYRE_AUDIO_TEST FAIL: " + error)
	quit(1)
