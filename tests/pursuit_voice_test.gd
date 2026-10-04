extends SceneTree

const PURSUIT_GEN := preload("res://scripts/audio/sfx/pursuit_voice_generator.gd")
const ONE_SHOT := preload("res://scripts/audio/sfx/one_shot_voice.gd")

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var gen := PURSUIT_GEN.new()
	var voice := gen.generate("test-pursuit")
	if not voice is ONE_SHOT or voice.tiers.is_empty():
		push_error("PURSUIT_VOICE_TEST FAIL: generator produced no voice")
		quit(1)
		return
	var stinger := gen.generate_stinger("strip_captured")
	if stinger.tiers.is_empty():
		push_error("PURSUIT_VOICE_TEST FAIL: no stinger")
		quit(1)
		return
	# check samples non zero
	var s := voice.tiers[0]
	var has_energy := false
	for v in s:
		if absf(v) > 0.01:
			has_energy = true
			break
	if not has_energy:
		push_error("PURSUIT_VOICE_TEST FAIL: silent voice")
		quit(1)
		return
	print("PURSUIT_VOICE_TEST PASS")
	quit(0)
