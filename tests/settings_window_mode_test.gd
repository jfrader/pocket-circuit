extends SceneTree

const SAVE_STORE := preload("res://scripts/persistence/save_store.gd")
const TEST_PATH := "user://tests/settings_window_mode_test.json"
const VOLUME_BUSES := {
	"master_volume": "Master",
	"music_volume": "Music",
	"sfx_volume": "SFX",
	"engine_volume": "Engine",
	"tyre_volume": "Tyre",
}
const NATIVE_SETTLE_SECONDS := 0.25

class TestSaveStore extends SaveStore:
	var attempts := 0
	var fail_writes := false

	func _init() -> void:
		super(TEST_PATH)

	func save_data(data: Dictionary) -> bool:
		attempts += 1
		if fail_writes:
			last_save_error = "Injected settings write failure"
			return false
		return super.save_data(data)


var _app: Node
var _shell: CanvasLayer
var _store: TestSaveStore
var _focus_losses := 0


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	_app = root.get_node("App")
	_store = TestSaveStore.new()
	_store.remove_save()
	_app.set("_save_store", _store)
	_app.set("_save_data", _store.default_data())
	_app.call("_ensure_shell")
	_shell = _app.get("_shell")
	root.focus_exited.connect(func() -> void: _focus_losses += 1)
	if not await _test_volume_sliders():
		return
	if not await _test_other_settings():
		return
	if not await _test_save_failures():
		return
	if not await _test_fullscreen_application():
		return
	_store.remove_save()
	_shell.free()
	_app.set("_shell", null)
	await process_frame
	print("SETTINGS_WINDOW_MODE_TEST PASS")
	quit(0)


func _test_volume_sliders() -> bool:
	var live_modes := [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_MAXIMIZED, DisplayServer.WINDOW_MODE_WINDOWED] if _native_display() else [DisplayServer.WINDOW_MODE_WINDOWED]
	for saved_fullscreen: bool in [false, true]:
		for live_mode: int in live_modes:
			var settings: Dictionary = _app.call("get_save_data")
			settings["fullscreen"] = saved_fullscreen
			_app.set("_save_data", settings)
			if not _expect(_store.save_data(settings), "fixture settings should persist"):
				return false
			_shell.call("show_settings")
			await _settle()
			if _native_display():
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				await _settle()
				DisplayServer.window_set_mode(live_mode)
				await _settle()
				if not _expect(DisplayServer.window_get_mode() == live_mode, "native window mode fixture must be active"):
					return false
			var sliders := _shell.find_children("*", "HSlider", true, false)
			if not _expect(sliders.size() == VOLUME_BUSES.size(), "Options should expose all five volume sliders"):
				return false
			var index := 0
			for key: String in VOLUME_BUSES:
				var slider := sliders[index] as HSlider
				for percent: float in [37.0 + index, 0.0]:
					var before := _window_state()
					slider.value = percent
					await _settle()
					if not _expect(_window_state() == before, "%s slider must preserve live mode, size and focus (saved fullscreen=%s, live mode=%d): %s -> %s" % [key, saved_fullscreen, live_mode, before, _window_state()]):
						return false
					var volume := percent / 100.0
					if not _expect(is_equal_approx(float(_app.call("get_save_data")[key]), volume) and is_equal_approx(float(_store.load_data()[key]), volume), key + " slider should update and persist its volume immediately"):
						return false
					if not _expect_bus(key, volume):
						return false
				index += 1
			if _native_display():
				print("SETTINGS_WINDOW_MODE_NATIVE sliders PASS saved_fullscreen=%s live_mode=%d" % [saved_fullscreen, live_mode])
	return true


func _test_other_settings() -> bool:
	for entry: Array in [["difficulty", "clockwork"], ["reduced_camera_shake", true], ["reduced_motion", true], ["engine_volume", 2.0], ["tyre_volume", -1.0]]:
		var before := _window_state()
		if not _expect(bool(_app.call("update_setting", entry[0], entry[1])), "valid settings update should succeed"):
			return false
		await _settle()
		if not _expect(_window_state() == before, String(entry[0]) + " must not change the window"):
			return false
	var loaded := _store.load_data()
	if not _expect(loaded["difficulty"] == "clockwork" and loaded["reduced_camera_shake"] and loaded["reduced_motion"] and bool(_app.get("reduced_camera_shake")) and bool(_app.get("reduced_motion")), "difficulty and comfort settings should persist and apply"):
		return false
	if not _expect_bus("engine_volume", 1.0) or not _expect_bus("tyre_volume", 0.0):
		return false
	if not _expect(loaded["engine_volume"] == 1.0 and loaded["tyre_volume"] == 0.0, "volume settings should clamp before persistence"):
		return false
	var attempts := _store.attempts
	var before := _window_state()
	if not _expect(bool(_app.call("update_setting", "master_volume", loaded["master_volume"])), "an unchanged setting should succeed"):
		return false
	for entry: Array in [["master_volume", "loud"], ["fullscreen", 1], ["difficulty", "unknown"], ["unknown", true]]:
		if not _expect(not bool(_app.call("update_setting", entry[0], entry[1])), "invalid settings should be rejected"):
			return false
	await _settle()
	return _expect(_store.attempts == attempts and _app.call("get_save_data") == loaded and _window_state() == before, "unchanged or invalid settings must not write saves or change the window")


func _test_save_failures() -> bool:
	_store.is_read_only = true
	var attempts := _store.attempts
	var persisted_volume := float(_app.call("get_save_data")["music_volume"])
	var before := _window_state()
	if not _expect(bool(_app.call("update_setting", "music_volume", 0.42)), "read-only saves should still allow session audio changes"):
		return false
	await _settle()
	if not _expect(_store.attempts == attempts and _window_state() == before and is_equal_approx(float(_app.call("get_save_data")["music_volume"]), 0.42), "read-only audio must apply without save attempts or window changes") or not _expect_bus("music_volume", 0.42):
		return false
	if not _expect(is_equal_approx(float(SAVE_STORE.new(TEST_PATH).load_data()["music_volume"]), persisted_volume), "read-only updates must leave the saved volume untouched"):
		return false
	_store.is_read_only = false
	_store.fail_writes = true
	for entry: Array in [["sfx_volume", 0.62], ["fullscreen", not bool(_app.call("get_save_data")["fullscreen"])]]:
		var settings: Dictionary = _app.call("get_save_data")
		before = _window_state()
		if not _expect(not bool(_app.call("update_setting", entry[0], entry[1])), "failed settings saves should reject the update"):
			return false
		await _settle()
		if not _expect(_app.call("get_save_data") == settings and _window_state() == before and String(_shell.get("_screen")) == "save_error", "failed settings saves must retain values and window state and show the retry screen"):
			return false
		if not _expect_bus("sfx_volume", float(settings["sfx_volume"])):
			return false
	_store.fail_writes = false
	before = _window_state()
	_app.call("_retry_setting", "sfx_volume", 0.62)
	await _settle()
	return _expect(_window_state() == before and String(_shell.get("_screen")) == "settings" and is_equal_approx(float(_store.load_data()["sfx_volume"]), 0.62), "retry should persist audio and return to Settings without changing the window") and _expect_bus("sfx_volume", 0.62)


func _test_fullscreen_application() -> bool:
	for fullscreen: bool in [true, false]:
		if not _expect(bool(_app.call("update_setting", "fullscreen", fullscreen)) and bool(_store.load_data()["fullscreen"]) == fullscreen, "explicit fullscreen choices should persist"):
			return false
		await _settle()
		if not _native_display():
			continue
		var expected_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if not _expect(DisplayServer.window_get_mode() == expected_mode, "explicit fullscreen changes should apply the requested mode"):
			return false
		var before := _window_state()
		_app.call("update_setting", "fullscreen", fullscreen)
		await _settle()
		if not _expect(_window_state() == before, "an already-applied fullscreen choice must not resize or refocus the window"):
			return false
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN)
		await _settle()
		_app.call("_apply_settings")
		await _settle()
		if not _expect(DisplayServer.window_get_mode() == expected_mode, "startup settings application should restore the saved display choice"):
			return false
	return true


func _native_display() -> bool:
	return DisplayServer.get_name().to_lower() != "headless"


func _settle() -> void:
	if _native_display():
		await create_timer(NATIVE_SETTLE_SECONDS).timeout
	else:
		await process_frame


func _window_state() -> Dictionary:
	if not _native_display():
		return {}
	return {"mode": DisplayServer.window_get_mode(), "size": DisplayServer.window_get_size(), "focused": DisplayServer.window_is_focused(), "focus_losses": _focus_losses}


func _expect_bus(key: String, volume: float) -> bool:
	var bus_index := AudioServer.get_bus_index(String(VOLUME_BUSES[key]))
	var expected_db := -80.0 if is_zero_approx(volume) else linear_to_db(volume)
	return _expect(bus_index >= 0 and is_equal_approx(AudioServer.get_bus_volume_db(bus_index), expected_db), key + " should immediately control its audio bus")


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("SETTINGS_WINDOW_MODE_TEST FAIL: " + message)
	quit(1)
	return false
