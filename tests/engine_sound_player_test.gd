extends SceneTree

const RUSTBUG_STATS := preload("res://data/vehicles/rustbug.tres")
const RECIPE_LIBRARY := preload("res://scripts/audio/engine/engine_recipe_library.gd")
const PLAYER_SCRIPT := preload("res://scripts/audio/engine/engine_sound_player.gd")
const STEP := 1.0 / 60.0


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var recipe := RECIPE_LIBRARY.resolve("rustbug", RUSTBUG_STATS)
	var player := PLAYER_SCRIPT.new()
	root.add_child(player)
	await process_frame
	var errors := PackedStringArray()
	errors.append_array(_check_prepare(player, recipe))
	errors.append_array(_check_state(player, recipe))
	errors.append_array(_check_pause(player))
	errors.append_array(_check_fallback())
	root.remove_child(player)
	player.free()
	await process_frame
	if errors.is_empty():
		print("ENGINE_SOUND_PLAYER_TEST PASS")
		quit(0)
		return
	for error in errors:
		push_error("ENGINE_SOUND_PLAYER_TEST FAIL: " + error)
	quit(1)


func _check_prepare(player: EngineSoundPlayer, recipe: EngineRecipe) -> PackedStringArray:
	var errors := PackedStringArray()
	# Lambdas capture by value, so collect through containers.
	var ready_signature := [""]
	var ready_count := [0]
	player.voice_ready.connect(func(signature: String) -> void:
		ready_signature[0] = signature
		ready_count[0] += 1
	)
	errors.append_array(_expect(player.is_using_fallback(), "a fresh player should start on the fallback path"))
	errors.append_array(_expect(player.prepare(recipe, "rustbug"), "preparing a valid recipe should succeed"))
	errors.append_array(_expect(not player.is_using_fallback(), "a prepared player should leave the fallback path"))
	errors.append_array(_expect(player.get_voice_signature() == String(ready_signature[0]) and not String(ready_signature[0]).is_empty(), "voice_ready should carry the generated signature"))
	errors.append_array(_expect(ready_count[0] == 1, "voice_ready should fire once per prepare"))
	errors.append_array(_expect(player.get_voice_bytes() > 0 and player.get_voice_bytes() <= 80 * 1024, "the prepared bank should stay inside budget; got %d" % player.get_voice_bytes()))
	errors.append_array(_expect(player.prepare(recipe, "rustbug"), "re-preparing the same recipe should stay valid"))
	errors.append_array(_expect(player.get_voice_signature() == String(ready_signature[0]), "re-preparing the same recipe should keep the same voice"))
	return errors


func _check_state(player: EngineSoundPlayer, recipe: EngineRecipe) -> PackedStringArray:
	var errors := PackedStringArray()
	for index in 120:
		player.set_vehicle_state(0.0, 692.0, 0.0, 0.0, STEP)
	errors.append_array(_expect(absf(player.get_rpm() - recipe.idle_rpm) < 5.0, "a parked car should idle on the generated voice; got %.1f" % player.get_rpm()))
	for index in 240:
		player.set_vehicle_state(692.0, 692.0, 1.0, 1.0, STEP)
	errors.append_array(_expect(player.get_rpm() > recipe.idle_rpm * 2.0, "a pull should raise rpm; got %.1f" % player.get_rpm()))
	errors.append_array(_expect(player.get_gear() > 0, "a pull should climb out of first gear"))
	return errors


func _check_pause(player: EngineSoundPlayer) -> PackedStringArray:
	var errors := PackedStringArray()
	var rpm_before := player.get_rpm()
	player.set_paused(true)
	for index in 60:
		player.set_vehicle_state(692.0, 692.0, 1.0, 1.0, STEP)
	errors.append_array(_expect(is_equal_approx(player.get_rpm(), rpm_before), "a paused voice must not advance the drivetrain"))
	player.set_paused(false)
	for index in 30:
		player.set_vehicle_state(692.0, 692.0, 1.0, 1.0, STEP)
	errors.append_array(_expect(player.get_rpm() >= rpm_before, "resuming should let the drivetrain advance again"))
	return errors


func _check_fallback() -> PackedStringArray:
	var errors := PackedStringArray()
	var broken := EngineRecipe.new()
	var player := PLAYER_SCRIPT.new()
	root.add_child(player)
	var reasons := []
	player.fallback_activated.connect(func(reason: String) -> void: reasons.append(reason))
	errors.append_array(_expect(not player.prepare(broken, "broken"), "an invalid recipe must not prepare"))
	errors.append_array(_expect(player.is_using_fallback(), "an invalid recipe must leave the fallback path active"))
	errors.append_array(_expect(reasons.size() == 1, "fallback_activated should fire once for an invalid recipe"))
	errors.append_array(_expect(not player.get_fallback_reason().is_empty(), "a fallback should explain itself"))
	root.remove_child(player)
	player.free()
	return errors


func _expect(condition: bool, message: String) -> PackedStringArray:
	if condition:
		return PackedStringArray()
	return PackedStringArray([message])
