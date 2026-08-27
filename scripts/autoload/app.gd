extends Node

const BOOT_SCENE := "res://scenes/boot/boot.tscn"
const RACE_SCENE := "res://scenes/race/prototype_race.tscn"
const CATALOG := preload("res://data/championship/catalog.gd")
const SAVE_STORE_SCRIPT := preload("res://scripts/persistence/save_store.gd")
const SHELL_SCRIPT := preload("res://scripts/ui/app_shell.gd")
const AUDIO_DIRECTOR_SCRIPT := preload("res://scripts/audio/audio_director.gd")

var current_race_session: Dictionary = {}
var reduced_camera_shake := false
var reduced_motion := false
var audio_director: Node

var _save_store: SaveStore
var _save_data: Dictionary
var _shell: CanvasLayer
var _last_scene: Node
var _destination := "title"
var _last_result_summary: Dictionary = {}
var _test_mode := false
var _last_save_error := ""


func _enter_tree() -> void:
	_ensure_joypad_button(&"ui_accept", JOY_BUTTON_A)
	_ensure_joypad_button(&"ui_cancel", JOY_BUTTON_B)
	_ensure_key(&"pause", KEY_ESCAPE)
	_ensure_joypad_button(&"pause", JOY_BUTTON_START)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_test_mode = "--script" in OS.get_cmdline_args() or "--release-smoke" in OS.get_cmdline_user_args()
	audio_director = AUDIO_DIRECTOR_SCRIPT.new()
	audio_director.name = "AudioDirector"
	add_child(audio_director)
	var active_save_path: String = "user://tests/pocket_circuit_app_autoload_test.json" if _test_mode else SaveStore.DEFAULT_PATH
	_save_store = SAVE_STORE_SCRIPT.new(active_save_path)
	if _test_mode:
		_save_store.remove_save()
	_save_data = _save_store.load_data()
	reduced_camera_shake = bool(_save_data["reduced_camera_shake"])
	reduced_motion = bool(_save_data["reduced_motion"])
	_apply_settings()
	if bool(_save_data["first_run"]):
		_save_data["first_run"] = false
		if not _test_mode:
			_save()
	call_deferred("_sync_current_scene")
	if "--release-smoke" in OS.get_cmdline_user_args():
		call_deferred("_run_release_smoke")


func _exit_tree() -> void:
	if _test_mode and _save_store:
		_save_store.remove_save()


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene != _last_scene:
		_sync_current_scene()


func _unhandled_input(event: InputEvent) -> void:
	if _shell == null or not _shell.visible or get_tree().current_scene == null:
		return
	if event.is_action_pressed("ui_cancel"):
		_shell.call("go_back")
		get_viewport().set_input_as_handled()


func has_championship_progress() -> bool:
	return CATALOG.has_progress(_save_data)


func is_save_read_only() -> bool:
	return _save_store != null and _save_store.is_read_only


func get_last_save_error() -> String:
	return _last_save_error


func get_save_data() -> Dictionary:
	return _save_data.duplicate(true)


func get_current_race_session() -> Dictionary:
	return current_race_session.duplicate(true)


func request_new_championship() -> void:
	if has_championship_progress():
		_shell.call("show_reset_confirmation")
	else:
		confirm_new_championship()


func confirm_new_championship() -> bool:
	var preserved_settings := {
		"difficulty": _save_data["difficulty"],
		"master_volume": _save_data["master_volume"],
		"music_volume": _save_data["music_volume"],
		"sfx_volume": _save_data["sfx_volume"],
		"fullscreen": _save_data["fullscreen"],
		"reduced_camera_shake": _save_data["reduced_camera_shake"],
		"reduced_motion": _save_data["reduced_motion"],
		"first_run": false,
	}
	var candidate := _save_store.default_data()
	for key: String in preserved_settings:
		candidate[key] = preserved_settings[key]
	candidate["championship_started"] = true
	if not _save_candidate(candidate):
		_show_save_error(
			"Championship not started",
			Callable(self, "confirm_new_championship"),
			Callable(_shell, "show_title")
		)
		return false
	_save_data = candidate
	_shell.call("show_map")
	return true


func continue_championship() -> void:
	_shell.call("show_map")


func open_quick_race() -> void:
	_shell.call("show_vehicle_select", "kitchen_crumb_rush", true)


func start_race(event_id: String, vehicle_id: String, quick_race: bool = false) -> void:
	var event := CATALOG.get_event(event_id)
	if event.is_empty():
		return
	if not quick_race and not CATALOG.is_event_unlocked(event_id, _save_data):
		return
	if not vehicle_id in _save_data["unlocked_vehicles"]:
		vehicle_id = "rustbug"
	var candidate := _save_data.duplicate(true)
	candidate["selected_vehicle"] = vehicle_id
	if candidate != _save_data:
		if _save_candidate(candidate):
			_save_data = candidate
		elif not quick_race:
			_show_save_error(
				"Vehicle choice not saved",
				Callable(self, "start_race").bind(event_id, vehicle_id, quick_race),
				Callable(_shell, "show_vehicle_select").bind(event_id, quick_race)
			)
			return
	current_race_session = {
		"mode": "quick" if quick_race else "championship",
		"event_id": event_id,
		"event": event,
		"vehicle_id": vehicle_id,
		"difficulty": String(_save_data["difficulty"]),
		"result_committed": false,
	}
	if _shell:
		_shell.visible = false
	get_tree().change_scene_to_file(RACE_SCENE)


func report_race_result(player_position: int, total_time: float, results: Array, player_dnf: bool = false) -> bool:
	if current_race_session.is_empty():
		return false
	if bool(current_race_session.get("result_committed", false)):
		return true
	var event: Dictionary = current_race_session.get("event", {})
	var racer_count := clampi((event.get("opponents", []) as Array).size() + 1, 1, 4)
	current_race_session["result"] = {
		"position": clampi(player_position, 1, racer_count),
		"time": maxf(0.0, total_time),
		"results": results,
		"dnf": player_dnf,
	}
	if String(current_race_session["mode"]) == "quick":
		current_race_session["result_committed"] = true
		current_race_session.erase("save_error")
		return true

	var ending_was_seen := bool(_save_data["ending_seen"])
	var summary := {
		"save": _save_data.duplicate(true),
		"event_id": String(current_race_session["event_id"]),
		"new_best": false,
		"points_gained": 0,
		"act_completed": false,
		"ending_unlocked": false,
		"unlocked_vehicles": [],
	}
	if not player_dnf:
		summary = CATALOG.apply_event_result(
			_save_data,
			String(current_race_session["event_id"]),
			int(current_race_session["result"]["position"])
		)
	var candidate: Dictionary = summary["save"]
	if candidate != _save_data and not _save_candidate(candidate):
		current_race_session["save_error"] = _last_save_error
		return false
	_save_data = candidate
	current_race_session["result_summary"] = summary
	current_race_session["post_race_destination"] = "ending" if bool(summary["ending_unlocked"]) and not ending_was_seen else "map"
	current_race_session["result_committed"] = true
	current_race_session.erase("save_error")
	return true


func continue_after_race(transition_scene: bool = true) -> void:
	if current_race_session.is_empty() or not current_race_session.has("result"):
		return
	if String(current_race_session["mode"]) == "quick":
		current_race_session.clear()
		_destination = "title"
		get_tree().change_scene_to_file(BOOT_SCENE)
		return
	if not bool(current_race_session.get("result_committed", false)):
		return
	_last_result_summary = current_race_session.get("result_summary", {}).duplicate(true)
	_destination = String(current_race_session.get("post_race_destination", "map"))
	if transition_scene:
		get_tree().change_scene_to_file(BOOT_SCENE)


func retry_race(reload_scene: bool = true) -> void:
	if current_race_session.is_empty():
		return
	current_race_session.erase("result")
	current_race_session.erase("result_summary")
	current_race_session.erase("post_race_destination")
	current_race_session.erase("save_error")
	current_race_session["result_committed"] = false
	if reload_scene:
		get_tree().reload_current_scene()


func abandon_race() -> void:
	if current_race_session.is_empty() or current_race_session.has("result"):
		return
	_destination = "title" if String(current_race_session.get("mode", "quick")) == "quick" else "map"
	current_race_session.clear()
	get_tree().change_scene_to_file(BOOT_SCENE)


func update_setting(key: String, value: Variant) -> bool:
	var candidate := _save_data.duplicate(true)
	match key:
		"difficulty":
			if value is String and value in SaveStore.VALID_DIFFICULTIES:
				candidate[key] = value
			else:
				return false
		"master_volume", "music_volume", "sfx_volume":
			if value is float or value is int:
				candidate[key] = clampf(float(value), 0.0, 1.0)
			else:
				return false
		"fullscreen", "reduced_camera_shake", "reduced_motion":
			if value is bool:
				candidate[key] = value
			else:
				return false
		_:
			return false
	if not is_save_read_only() and candidate != _save_data and not _save_candidate(candidate):
		_show_save_error(
			"Settings not saved",
			Callable(self, "_retry_setting").bind(key, value),
			Callable(_shell, "show_settings")
		)
		return false
	_save_data = candidate
	reduced_camera_shake = bool(_save_data["reduced_camera_shake"])
	reduced_motion = bool(_save_data["reduced_motion"])
	_apply_settings()
	return true


func _retry_setting(key: String, value: Variant) -> void:
	if update_setting(key, value):
		_shell.call("show_settings")


func play_sfx(sound_name: StringName, volume_scale: float = 1.0, pitch_scale: float = 1.0) -> bool:
	return audio_director.play_sfx(sound_name, volume_scale, pitch_scale) if is_instance_valid(audio_director) else false


func set_local_race_vehicle(vehicle: Node) -> void:
	if is_instance_valid(audio_director):
		audio_director.set_local_vehicle(vehicle)


func set_race_audio_paused(paused: bool) -> void:
	if is_instance_valid(audio_director):
		audio_director.set_race_paused(paused)


func quit_game() -> void:
	get_tree().quit()


func _sync_current_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_last_scene = scene
	if scene.scene_file_path == BOOT_SCENE:
		if is_instance_valid(audio_director):
			audio_director.play_menu_music()
		_hide_boot_placeholder(scene)
		_ensure_shell()
		_shell.visible = true
		match _destination:
			"map":
				_shell.call("show_map", _last_result_summary)
			"ending":
				_shell.call("show_ending")
			_:
				_shell.call("show_title")
		_last_result_summary = {}
		_destination = "title"
		current_race_session.clear()
	else:
		if scene.scene_file_path == RACE_SCENE and is_instance_valid(audio_director):
			audio_director.play_race_music()
		if _shell:
			_shell.visible = false


func _ensure_shell() -> void:
	if is_instance_valid(_shell):
		return
	_shell = SHELL_SCRIPT.new() as CanvasLayer
	_shell.name = "AppShell"
	add_child(_shell)
	_shell.call("configure", self)


func _hide_boot_placeholder(scene: Node) -> void:
	for child: Node in scene.get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = false
		elif child is CanvasLayer:
			(child as CanvasLayer).visible = false


func _apply_settings() -> void:
	_apply_bus_volume("Master", float(_save_data["master_volume"]))
	_apply_bus_volume("Music", float(_save_data["music_volume"]))
	_apply_bus_volume("SFX", float(_save_data["sfx_volume"]))
	if DisplayServer.get_name().to_lower() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(_save_data["fullscreen"]) else DisplayServer.WINDOW_MODE_WINDOWED
		DisplayServer.window_set_mode(mode)


func _apply_bus_volume(bus_name: String, linear_volume: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	var decibels := -80.0 if linear_volume <= 0.0001 else linear_to_db(linear_volume)
	AudioServer.set_bus_volume_db(bus_index, decibels)


func _ensure_joypad_button(action: StringName, button_index: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button_index:
			return
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	InputMap.action_add_event(action, event)


func _ensure_key(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).keycode == keycode:
			return
	var event := InputEventKey.new()
	event.keycode = keycode
	InputMap.action_add_event(action, event)


func _save() -> bool:
	return _save_candidate(_save_data)


func _save_candidate(candidate: Dictionary) -> bool:
	_last_save_error = ""
	if not _save_store.save_data(candidate):
		_last_save_error = _save_store.last_save_error
		push_warning(_last_save_error)
		return false
	return true


func _show_save_error(title: String, retry_action: Callable, back_action: Callable) -> void:
	if is_instance_valid(_shell) and _shell.has_method("show_save_error"):
		_shell.call("show_save_error", title, _last_save_error, retry_action, back_action)


func _run_release_smoke() -> void:
	await get_tree().process_frame
	if not confirm_new_championship():
		_release_smoke_fail("new championship did not persist")
		return
	start_race("kitchen_crumb_rush", "rustbug", false)
	var scene_frames_remaining := 300
	while scene_frames_remaining > 0 and (get_tree().current_scene == null or get_tree().current_scene.scene_file_path != RACE_SCENE):
		await get_tree().process_frame
		scene_frames_remaining -= 1
	if get_tree().current_scene == null or get_tree().current_scene.scene_file_path != RACE_SCENE:
		_release_smoke_fail("race scene did not load")
		return
	var race := get_tree().current_scene
	var race_manager := race.get_node_or_null("RaceManager") as RaceManager
	if race_manager == null:
		_release_smoke_fail("race manager is missing")
		return
	var race_frames_remaining := 900
	while race_frames_remaining > 0 and not race_manager.is_running:
		await get_tree().physics_frame
		race_frames_remaining -= 1
	if not race_manager.is_running:
		_release_smoke_fail("race did not start")
		return
	var player_vehicle := race.get("_player_vehicle") as Node2D
	var player_state := race_manager.get_racer_state(player_vehicle)
	if player_vehicle == null or player_state.is_empty():
		_release_smoke_fail("player racer state is missing")
		return
	race_manager.call("_finish_racer", player_vehicle, player_state)
	race_manager.finalize_remaining_racers_as_dnf()
	await get_tree().process_frame
	if not bool(race.get("_results_finalized")):
		_release_smoke_fail("results screen did not finalize")
		return
	var continue_button := race.get("_continue_button") as Button
	if continue_button == null or continue_button.disabled:
		_release_smoke_fail("committed results did not enable Continue")
		return
	var verification_store := SAVE_STORE_SCRIPT.new(_save_store.save_path)
	var persisted: Dictionary = verification_store.load_data()
	if not bool(persisted["championship_started"]) or int(persisted["best_event_finishes"].get("kitchen_crumb_rush", 0)) != 1:
		_release_smoke_fail("persisted race result could not be reloaded")
		return
	print("RELEASE_RACE_SMOKE PASS")
	get_tree().quit(0)


func _release_smoke_fail(message: String) -> void:
	push_error("RELEASE_RACE_SMOKE FAIL: " + message)
	get_tree().quit(1)
