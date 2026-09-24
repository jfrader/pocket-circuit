extends SceneTree

const RUSTBUG_STATS := preload("res://data/vehicles/rustbug.tres")
const RECIPE_LIBRARY := preload("res://scripts/audio/engine/engine_recipe_library.gd")
const STEP := 1.0 / 60.0
const MAX_SPEED := 692.0


func _initialize() -> void:
	var recipe := RECIPE_LIBRARY.resolve("rustbug", RUSTBUG_STATS)
	var errors := PackedStringArray()
	errors.append_array(_check_rest(recipe))
	errors.append_array(_check_pull(recipe))
	errors.append_array(_check_coast(recipe))
	errors.append_array(_check_determinism(recipe))
	if errors.is_empty():
		print("ENGINE_DRIVETRAIN_MODEL_TEST PASS")
		quit(0)
		return
	for error in errors:
		push_error("ENGINE_DRIVETRAIN_MODEL_TEST FAIL: " + error)
	quit(1)


func _check_rest(recipe: EngineRecipe) -> PackedStringArray:
	var errors := PackedStringArray()
	var model := EngineDrivetrainModel.new()
	model.configure(recipe)
	for index in 120:
		model.step(0.0, MAX_SPEED, 0.0, 0.0, STEP)
	errors.append_array(_expect(is_equal_approx(model.get_gear(), 0), "a parked car should sit in first gear"))
	errors.append_array(_expect(absf(model.get_rpm() - recipe.idle_rpm) < 5.0, "a parked car should idle; got %.1f" % model.get_rpm()))
	errors.append_array(_expect(model.get_shift_count() == 0, "idling should not shift"))
	return errors


func _check_pull(recipe: EngineRecipe) -> PackedStringArray:
	var errors := PackedStringArray()
	var model := EngineDrivetrainModel.new()
	model.configure(recipe)
	var previous_gear := 0
	var downshifts := 0
	var ceiling := recipe.redline_rpm * 1.05
	var floor_rpm := recipe.idle_rpm * 0.9
	var saw_shift_cut := false
	for index in 600:
		var speed := MAX_SPEED * clampf(float(index) / 420.0, 0.0, 1.0)
		model.step(speed, MAX_SPEED, 1.0, 1.0, STEP)
		if model.get_gear() < previous_gear:
			downshifts += 1
		previous_gear = model.get_gear()
		if model.is_shifting() and is_zero_approx(model.get_throttle()):
			saw_shift_cut = true
		if model.get_rpm() > ceiling or model.get_rpm() < floor_rpm:
			errors.append_array(_expect(false, "rpm escaped idle..redline at step %d: %.1f" % [index, model.get_rpm()]))
			break
	errors.append_array(_expect(model.get_shift_count() >= 2, "a full pull should shift up at least twice; got %d" % model.get_shift_count()))
	errors.append_array(_expect(model.get_gear() == model.get_gear_count() - 1, "a full pull should end in top gear; got %d" % model.get_gear()))
	errors.append_array(_expect(downshifts == 0, "a full-throttle pull should never downshift"))
	errors.append_array(_expect(saw_shift_cut, "shifting should cut throttle for the synth"))
	errors.append_array(_expect(model.get_rpm() > recipe.idle_rpm * 4.0, "a full pull should reach a high rev"))
	return errors


func _check_coast(recipe: EngineRecipe) -> PackedStringArray:
	var errors := PackedStringArray()
	var model := EngineDrivetrainModel.new()
	model.configure(recipe)
	for index in 600:
		model.step(MAX_SPEED, MAX_SPEED, 1.0, 1.0, STEP)
	var top_gear := model.get_gear()
	for index in 600:
		model.step(MAX_SPEED * (1.0 - float(index) / 600.0), MAX_SPEED, 0.0, 0.0, STEP)
	errors.append_array(_expect(top_gear == model.get_gear_count() - 1, "the pull should reach top gear before coasting"))
	errors.append_array(_expect(model.get_gear() == 0, "coasting to a stop should walk back down to first gear; got %d" % model.get_gear()))
	errors.append_array(_expect(absf(model.get_rpm() - recipe.idle_rpm) < 20.0, "a stopped car should settle back to idle; got %.1f" % model.get_rpm()))
	return errors


func _check_determinism(recipe: EngineRecipe) -> PackedStringArray:
	var errors := PackedStringArray()
	var first := EngineDrivetrainModel.new()
	var second := EngineDrivetrainModel.new()
	first.configure(recipe)
	second.configure(recipe)
	for index in 300:
		var speed := MAX_SPEED * float(index) / 300.0
		first.step(speed, MAX_SPEED, 0.7, 0.8, STEP)
		second.step(speed, MAX_SPEED, 0.7, 0.8, STEP)
	errors.append_array(_expect(is_equal_approx(first.get_rpm(), second.get_rpm()), "the drivetrain must be deterministic"))
	errors.append_array(_expect(first.get_gear() == second.get_gear(), "gear selection must be deterministic"))
	return errors


func _expect(condition: bool, message: String) -> PackedStringArray:
	if condition:
		return PackedStringArray()
	return PackedStringArray([message])
