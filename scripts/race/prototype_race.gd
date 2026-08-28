extends Node2D

signal return_requested

class RacePauseOverlay extends Control:
	signal cancel_pressed(requested_pause: bool)

	var enabled := true

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process_unhandled_input(true)

	func _unhandled_input(event: InputEvent) -> void:
		var requested_pause := InputMap.has_action("pause") and event.is_action_pressed("pause")
		var requested_resume := get_tree().paused and event.is_action_pressed("ui_cancel")
		if enabled and (requested_pause or requested_resume):
			cancel_pressed.emit(requested_pause)
			get_viewport().set_input_as_handled()


const RUSTBUG_SCENE := preload("res://scenes/vehicles/rustbug.tscn")
const AI_CONTROLLER_SCRIPT := preload("res://scripts/vehicle/ai_vehicle_controller.gd")
const TRACK_VARIANT_SCRIPT := preload("res://scripts/presentation/track_variant_presenter.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
const BOOST_FILL_SCALE := Vector2(0.52, 0.52)
const COUNTDOWN_STEP_SECONDS := 0.65
const FALLBACK_OPPONENTS: Array[String] = ["juniper", "milo", "tess"]
const GRID_TRANSFORMS: Array[Transform2D] = [
	Transform2D(PI * 0.5, Vector2(-600.0, 315.0)),
	Transform2D(PI * 0.5, Vector2(-630.0, 410.0)),
	Transform2D(PI * 0.5, Vector2(-660.0, 315.0)),
	Transform2D(PI * 0.5, Vector2(-690.0, 410.0)),
]
const REVERSE_GRID_TRANSFORMS: Array[Transform2D] = [
	Transform2D(0.0, Vector2(-680.0, 315.0)),
	Transform2D(0.0, Vector2(-785.0, 315.0)),
	Transform2D(0.0, Vector2(-680.0, 420.0)),
	Transform2D(0.0, Vector2(-785.0, 420.0)),
]
const RACER_MARKER_COLORS: Array[Color] = [
	Color("fff8e8"),
	Color("71b7ff"),
	Color("82d49b"),
	Color("ca78ff"),
]
const AI_LANE_OFFSETS: Array[float] = [-28.0, 26.0, 4.0]

@onready var race_manager: RaceManager = $RaceManager
@onready var hud_label: Label = $HUD/HUDLabel
@onready var boost_fill: Sprite2D = $HUD/RaceHUDArt/BoostBar/BoostFill
@onready var controls_label: Label = $HUD/ControlsLabel
@onready var camera: Camera2D = $FollowCamera2D
@onready var track_root: Node2D = $KitchenGraybox

var _player_vehicle: VehicleController
var _finished: bool = false
var _countdown_label: Label
var _race_flash_label: Label
var _position_label: Label
var _wrong_way_label: Label
var _results_panel: Panel
var _results_label: Label
var _retry_button: Button
var _continue_button: Button
var _pause_overlay: RacePauseOverlay
var _pause_menu_panel: PanelContainer
var _pause_settings_panel: PanelContainer
var _pause_resume_button: Button
var _pause_settings_first_control: Control
var _pause_settings_status: Label
var _session: Dictionary = {}
var _save_error := ""
var _results_finalized: bool = false
var _track_variant_presenter: TrackVariantPresenter
var _countdown_tween: Tween
var _race_flash_tween: Tween
var _countdown_active := false


func _ready() -> void:
	_create_phase_one_ui()
	_configure_session()
	_configure_track_variant()
	_create_pause_overlay()
	_configure_racers()
	race_manager.race_finished.connect(_on_race_finished)
	race_manager.position_changed.connect(_on_position_changed)
	race_manager.wrong_way_changed.connect(_on_wrong_way_changed)
	race_manager.lap_completed.connect(_on_lap_completed)
	race_manager.racer_finished.connect(_on_racer_finished)
	race_manager.results_ready.connect(_on_results_ready)
	boost_fill.z_index = 2
	controls_label.text += "   ·   ESC / START pause"
	if OS.is_debug_build():
		controls_label.text += "   ·   F3 telemetry"
		_ensure_debug_overlay()
	_countdown_active = true
	call_deferred("_run_countdown")


func _exit_tree() -> void:
	if get_tree():
		get_tree().paused = false
	var app := get_node_or_null("/root/App")
	if app and app.has_method("set_race_audio_paused"):
		app.call("set_race_audio_paused", false)


func _process(_delta: float) -> void:
	var elapsed: float = race_manager.race_time
	var minutes := int(elapsed / 60.0)
	var seconds := fmod(elapsed, 60.0)
	var shown_lap: int = mini(race_manager.lap_count + 1, race_manager.laps_to_finish)
	_update_boost_bar()
	_update_position_label()
	if _finished:
		hud_label.text = "RESULTS FINAL" if _results_finalized else "FINISH  ·  FINALIZING THE FIELD"
	elif race_manager.is_running:
		hud_label.text = "LAP %d/%d   ·   %02d:%04.1f" % [
			shown_lap,
			race_manager.laps_to_finish,
			minutes,
			seconds,
		]
	else:
		hud_label.text = "LAP 1/%d   ·   00:00.0" % race_manager.laps_to_finish


func _configure_racers() -> void:
	_player_vehicle = get_tree().get_first_node_in_group("player_vehicle") as VehicleController
	if _player_vehicle == null:
		push_error("Prototype race requires a player Rustbug")
		return
	var player_vehicle_id := String(_session.get("vehicle_id", "rustbug"))
	_configure_vehicle(_player_vehicle, 0, true, CATALOG.get_driver("rae"), player_vehicle_id)
	camera.call("set_target", _player_vehicle)
	var app := get_node_or_null("/root/App")
	if app and app.has_method("set_local_race_vehicle"):
		app.call("set_local_race_vehicle", _player_vehicle)

	var event: Dictionary = _session.get("event", {})
	var opponent_ids: Array = event.get("opponents", FALLBACK_OPPONENTS) if not event.is_empty() else FALLBACK_OPPONENTS
	var opponent_count := clampi(int(event.get("opponent_count", opponent_ids.size())), 0, 3)
	var difficulty := String(_session.get("difficulty", "club_circuit"))
	for ai_index in mini(opponent_ids.size(), opponent_count):
		var driver_id := String(opponent_ids[ai_index])
		var driver := CATALOG.get_driver(driver_id)
		var ai_vehicle_id := String(driver.get("vehicle_id", "rustbug"))
		var ai_vehicle := RUSTBUG_SCENE.instantiate() as VehicleController
		ai_vehicle.name = "%sAI" % String(driver.get("name", "Racer%d" % (ai_index + 1))).replace(" ", "")
		ai_vehicle.stats = CATALOG.create_vehicle_stats(ai_vehicle_id)
		ai_vehicle.remove_from_group("player_vehicle")
		ai_vehicle.add_to_group("race_vehicle")
		ai_vehicle.set_player_controlled(false)
		ai_vehicle.set_controls_locked(true)
		add_child(ai_vehicle)
		_configure_vehicle(ai_vehicle, ai_index + 1, false, driver, ai_vehicle_id)
		var ai_controller := AI_CONTROLLER_SCRIPT.new() as AIVehicleController
		ai_vehicle.add_child(ai_controller)
		ai_controller.configure(ai_vehicle, race_manager, AI_LANE_OFFSETS[ai_index], difficulty)


func _configure_vehicle(
		vehicle: VehicleController,
		racer_index: int,
		is_player: bool,
		driver: Dictionary,
		vehicle_id: String
) -> void:
	var grid := REVERSE_GRID_TRANSFORMS if race_manager.is_reverse_direction() else GRID_TRANSFORMS
	vehicle.global_transform = grid[racer_index]
	vehicle.collision_layer |= 1
	vehicle.collision_mask |= 1
	vehicle.add_to_group("race_vehicle")
	vehicle.set_player_controlled(is_player)
	vehicle.set_controls_locked(true)
	vehicle.apply_stats(CATALOG.create_vehicle_stats(vehicle_id))
	vehicle.configure_base_surface(_track_variant_presenter.base_surface_name)
	var driver_name := String(driver.get("name", "Racer"))
	var vehicle_data := CATALOG.get_vehicle(vehicle_id)
	var vehicle_name := String(vehicle_data.get("name", "Rustbug"))
	vehicle.configure_identity(driver_name, vehicle_name, vehicle_id)
	vehicle.configure_racer_marker(RACER_MARKER_COLORS[racer_index])
	race_manager.register_racer(vehicle, driver_name, vehicle_name, is_player)


func _configure_session() -> void:
	var app := get_node_or_null("/root/App")
	if app and app.has_method("get_current_race_session"):
		_session = app.call("get_current_race_session")
	var event: Dictionary = _session.get("event", {})
	if not event.is_empty():
		race_manager.laps_to_finish = clampi(int(event.get("laps", 3)), 1, 99)
		race_manager.set_reverse_direction(bool(event.get("reverse", false)))


func _configure_track_variant() -> void:
	var event: Dictionary = _session.get("event", {})
	var requested_theme := StringName(event.get("theme", "kitchen"))
	_track_variant_presenter = TRACK_VARIANT_SCRIPT.new() as TrackVariantPresenter
	track_root.add_child(_track_variant_presenter)
	_track_variant_presenter.configure(track_root, requested_theme)


func _run_countdown() -> void:
	race_manager.begin_countdown()
	for value in ["3", "2", "1"]:
		_present_countdown(value)
		_play_sfx(&"countdown", 0.82)
		race_manager.report_countdown_tick(value)
		await get_tree().create_timer(COUNTDOWN_STEP_SECONDS, false).timeout
	_present_countdown("GO!")
	_play_sfx(&"go", 0.92)
	race_manager.report_countdown_tick("GO!")
	race_manager.start_race()
	if "--media-capture" in OS.get_cmdline_user_args():
		print("MEDIA_RACE_READY %s %s" % [String(_session.get("event_id", "unknown")), String(_session.get("vehicle_id", "unknown"))])
	_countdown_active = false
	await get_tree().create_timer(COUNTDOWN_STEP_SECONDS, false).timeout
	_countdown_label.visible = false


func _update_boost_bar() -> void:
	var ratio: float = 0.0
	if is_instance_valid(_player_vehicle):
		ratio = clampf(_player_vehicle.boost_amount / maxf(_player_vehicle.stats.boost_capacity, 0.001), 0.0, 1.0)
	boost_fill.scale = Vector2(BOOST_FILL_SCALE.x * ratio, BOOST_FILL_SCALE.y)


func _update_position_label() -> void:
	if not is_instance_valid(_player_vehicle):
		return
	var race_position := race_manager.get_racer_position(_player_vehicle)
	var racer_count := race_manager.get_racer_count()
	_position_label.text = "%s  /  %d" % [_ordinal(race_position), racer_count]


func _on_race_finished(_total_time: float) -> void:
	_finished = true
	_results_panel.visible = true
	_retry_button.disabled = true
	_continue_button.disabled = true
	_update_results(race_manager.get_results())


func _on_position_changed(racer: Node2D, _position: int, _racer_count: int) -> void:
	if racer == _player_vehicle:
		_update_position_label()


func _on_wrong_way_changed(racer: Node2D, wrong_way: bool) -> void:
	if racer == _player_vehicle:
		_wrong_way_label.visible = wrong_way


func _on_lap_completed(lap: int) -> void:
	if lap >= race_manager.laps_to_finish:
		return
	_race_flash_label.text = "FINAL LAP" if lap == race_manager.laps_to_finish - 1 else "LAP %d" % (lap + 1)
	_race_flash_label.visible = true
	_race_flash_label.modulate.a = 1.0
	if _race_flash_tween and _race_flash_tween.is_valid():
		_race_flash_tween.kill()
	_race_flash_tween = create_tween()
	_race_flash_tween.tween_interval(1.0)
	_race_flash_tween.tween_property(_race_flash_label, "modulate:a", 0.0, 0.3)
	_race_flash_tween.tween_callback(Callable(_race_flash_label, "hide"))


func _on_racer_finished(_racer: Node2D, _position: int, _total_time: float) -> void:
	if _results_panel.visible:
		_update_results(race_manager.get_results())


func _on_results_ready(results: Array) -> void:
	_set_paused(false)
	if _results_finalized:
		return
	_finished = true
	_results_finalized = true
	_pause_overlay.enabled = false
	_results_panel.visible = true
	_attempt_result_commit(results)


func _update_results(results: Array) -> void:
	var lines: Array[String] = ["RACE RESULTS", ""]
	for result: Dictionary in results:
		var status := "DNF" if bool(result.get("dnf", false)) else (_format_time(float(result["time"])) if bool(result["finished"]) else "RACING")
		lines.append("%d. %s  ·  %s  ·  %s" % [
			int(result["position"]),
			String(result["driver_name"]),
			String(result["vehicle_name"]),
			status,
		])
	lines.append("")
	var final_prompt := "CONTINUE · RETRY TO RUN IT AGAIN" if String(_session.get("mode", "quick")) == "quick" else "RESULT SAVED · CONTINUE OR RETRY"
	if not _save_error.is_empty():
		final_prompt = "SAVE FAILED · RETRY SAVE BEFORE CONTINUING"
	lines.append("FINALIZING..." if not _results_finalized else final_prompt)
	_results_label.text = "\n".join(lines)


func restart_race() -> void:
	_set_paused(false)
	var app := get_node_or_null("/root/App")
	if app and not _session.is_empty() and app.has_method("retry_race"):
		app.call("retry_race")
	else:
		get_tree().reload_current_scene()


func request_return() -> void:
	_set_paused(false)
	return_requested.emit()
	var app := get_node_or_null("/root/App")
	if app and not _session.is_empty() and app.has_method("continue_after_race"):
		app.call("continue_after_race")
	else:
		get_tree().change_scene_to_file("res://scenes/boot/boot.tscn")


func request_abandon() -> void:
	if _finished or _results_finalized:
		return
	_set_paused(false)
	return_requested.emit()
	var app := get_node_or_null("/root/App")
	if app and not _session.is_empty() and app.has_method("abandon_race"):
		app.call("abandon_race")
	else:
		get_tree().change_scene_to_file("res://scenes/boot/boot.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if not _results_finalized:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		_on_retry_pressed()
	elif event.is_action_pressed("ui_cancel"):
		request_return()
	else:
		return
	get_viewport().set_input_as_handled()


func _on_pause_cancel(requested_pause: bool) -> void:
	if not requested_pause and is_instance_valid(_pause_settings_panel) and _pause_settings_panel.visible:
		_show_pause_menu()
	else:
		_toggle_pause()


func _toggle_pause() -> void:
	if _finished or _results_finalized:
		return
	if not _countdown_active and not race_manager.is_running:
		return
	if is_instance_valid(_player_vehicle) and race_manager.is_racer_finished(_player_vehicle):
		return
	_set_paused(not get_tree().paused)


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	var app := get_node_or_null("/root/App")
	if app and app.has_method("set_race_audio_paused"):
		app.call("set_race_audio_paused", paused)
	if is_instance_valid(_pause_overlay):
		_pause_overlay.visible = paused
	if paused:
		_show_pause_menu()


func _present_countdown(value: String) -> void:
	_countdown_label.text = value
	_countdown_label.visible = true
	if _countdown_tween and _countdown_tween.is_valid():
		_countdown_tween.kill()
	_countdown_label.pivot_offset = _countdown_label.size * 0.5
	if _reduced_motion_enabled():
		_countdown_label.scale = Vector2.ONE
		return
	_countdown_label.scale = Vector2(1.24, 1.24)
	_countdown_tween = create_tween()
	_countdown_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_countdown_tween.tween_property(_countdown_label, "scale", Vector2.ONE, 0.2)


func _reduced_motion_enabled() -> bool:
	var app := get_node_or_null("/root/App")
	return bool(app.get("reduced_motion")) if app else false


func _play_sfx(sound_name: StringName, volume_scale: float = 1.0) -> void:
	var app := get_node_or_null("/root/App")
	if app and app.has_method("play_sfx"):
		app.call("play_sfx", sound_name, volume_scale)


func _ensure_debug_overlay() -> void:
	if has_node("DebugOverlay"):
		return
	var debug_script := load("res://scripts/ui/" + "debug_overlay.gd") as Script
	if debug_script == null:
		return
	var overlay := debug_script.new() as CanvasLayer
	overlay.name = "DebugOverlay"
	add_child(overlay)


func _create_phase_one_ui() -> void:
	var hud := $HUD as CanvasLayer
	_countdown_label = Label.new()
	_countdown_label.name = "CountdownLabel"
	_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 88)
	_countdown_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.25))
	_countdown_label.add_theme_color_override("font_outline_color", Color(0.08, 0.09, 0.12))
	_countdown_label.add_theme_constant_override("outline_size", 10)
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_countdown_label)

	_race_flash_label = Label.new()
	_race_flash_label.name = "RaceFlashLabel"
	_race_flash_label.offset_left = 440.0
	_race_flash_label.offset_top = 62.0
	_race_flash_label.offset_right = 840.0
	_race_flash_label.offset_bottom = 112.0
	_race_flash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_race_flash_label.add_theme_font_size_override("font_size", 30)
	_race_flash_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.25))
	_race_flash_label.add_theme_color_override("font_outline_color", Color(0.08, 0.09, 0.12))
	_race_flash_label.add_theme_constant_override("outline_size", 6)
	_race_flash_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_race_flash_label.visible = false
	hud.add_child(_race_flash_label)

	_position_label = Label.new()
	_position_label.name = "PositionLabel"
	_position_label.offset_left = 1040.0
	_position_label.offset_top = 22.0
	_position_label.offset_right = 1250.0
	_position_label.offset_bottom = 72.0
	_position_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_position_label.add_theme_font_size_override("font_size", 30)
	_position_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.25))
	_position_label.add_theme_color_override("font_outline_color", Color(0.08, 0.09, 0.12))
	_position_label.add_theme_constant_override("outline_size", 6)
	hud.add_child(_position_label)

	_wrong_way_label = Label.new()
	_wrong_way_label.name = "WrongWayLabel"
	_wrong_way_label.offset_left = 440.0
	_wrong_way_label.offset_top = 118.0
	_wrong_way_label.offset_right = 840.0
	_wrong_way_label.offset_bottom = 170.0
	_wrong_way_label.text = "WRONG WAY"
	_wrong_way_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wrong_way_label.add_theme_font_size_override("font_size", 34)
	_wrong_way_label.add_theme_color_override("font_color", Color(1.0, 0.28, 0.18))
	_wrong_way_label.add_theme_color_override("font_outline_color", Color(0.08, 0.09, 0.12))
	_wrong_way_label.add_theme_constant_override("outline_size", 7)
	_wrong_way_label.visible = false
	hud.add_child(_wrong_way_label)

	_results_panel = Panel.new()
	_results_panel.name = "ResultsPanel"
	_results_panel.offset_left = 330.0
	_results_panel.offset_top = 150.0
	_results_panel.offset_right = 950.0
	_results_panel.offset_bottom = 565.0
	_results_panel.visible = false
	hud.add_child(_results_panel)
	_results_label = Label.new()
	_results_label.offset_left = 28.0
	_results_label.offset_top = 24.0
	_results_label.offset_right = 592.0
	_results_label.offset_bottom = 325.0
	_results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_label.add_theme_font_size_override("font_size", 22)
	_results_label.add_theme_color_override("font_color", Color(0.96, 0.94, 0.89))
	_results_panel.add_child(_results_label)

	_retry_button = Button.new()
	_retry_button.text = "Retry"
	_retry_button.position = Vector2(120.0, 340.0)
	_retry_button.size = Vector2(170.0, 48.0)
	_retry_button.disabled = true
	_retry_button.pressed.connect(_on_retry_pressed)
	_results_panel.add_child(_retry_button)
	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.position = Vector2(330.0, 340.0)
	_continue_button.size = Vector2(170.0, 48.0)
	_continue_button.disabled = true
	_continue_button.pressed.connect(request_return)
	_results_panel.add_child(_continue_button)


func _create_pause_overlay() -> void:
	var hud := $HUD as CanvasLayer
	_pause_overlay = RacePauseOverlay.new()
	_pause_overlay.name = "PauseOverlay"
	_pause_overlay.z_index = 100
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.visible = false
	_pause_overlay.cancel_pressed.connect(_on_pause_cancel)
	hud.add_child(_pause_overlay)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.04, 0.07, 0.82)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_overlay.add_child(shade)

	_pause_menu_panel = PanelContainer.new()
	_pause_menu_panel.name = "PauseMenuPanel"
	_pause_menu_panel.add_theme_stylebox_override("panel", _pause_style(Color("121925"), Color("f4bf3a"), 12, 2))
	_pause_menu_panel.position = Vector2(370.0, 105.0)
	_pause_menu_panel.size = Vector2(540.0, 510.0)
	_pause_overlay.add_child(_pause_menu_panel)
	var menu_margin := MarginContainer.new()
	menu_margin.add_theme_constant_override("margin_left", 48)
	menu_margin.add_theme_constant_override("margin_top", 38)
	menu_margin.add_theme_constant_override("margin_right", 48)
	menu_margin.add_theme_constant_override("margin_bottom", 38)
	_pause_menu_panel.add_child(menu_margin)
	var menu_column := VBoxContainer.new()
	menu_column.add_theme_constant_override("separation", 18)
	menu_margin.add_child(menu_column)
	var menu_heading := Label.new()
	menu_heading.text = "RACE PAUSED"
	menu_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_heading.add_theme_font_size_override("font_size", 34)
	menu_column.add_child(menu_heading)
	_pause_resume_button = _add_pause_button(menu_column, "Resume", _toggle_pause)
	_add_pause_button(menu_column, "Settings", _show_pause_settings)
	_add_pause_button(menu_column, "Restart", restart_race)
	var return_label := "Return to Title" if String(_session.get("mode", "quick")) == "quick" else "Return to Championship"
	_add_pause_button(menu_column, return_label, request_abandon)

	_pause_settings_panel = PanelContainer.new()
	_pause_settings_panel.name = "PauseSettingsPanel"
	_pause_settings_panel.add_theme_stylebox_override("panel", _pause_style(Color("121925"), Color("55a8c9"), 12, 2))
	_pause_settings_panel.position = Vector2(320.0, 50.0)
	_pause_settings_panel.size = Vector2(640.0, 620.0)
	_pause_settings_panel.visible = false
	_pause_overlay.add_child(_pause_settings_panel)
	var settings_margin := MarginContainer.new()
	settings_margin.add_theme_constant_override("margin_left", 44)
	settings_margin.add_theme_constant_override("margin_top", 30)
	settings_margin.add_theme_constant_override("margin_right", 44)
	settings_margin.add_theme_constant_override("margin_bottom", 30)
	_pause_settings_panel.add_child(settings_margin)
	var settings_column := VBoxContainer.new()
	settings_column.add_theme_constant_override("separation", 12)
	settings_margin.add_child(settings_column)
	var settings_heading := Label.new()
	settings_heading.text = "RACE SETTINGS"
	settings_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_heading.add_theme_font_size_override("font_size", 30)
	settings_column.add_child(settings_heading)
	var settings_copy := Label.new()
	settings_copy.text = "Audio and comfort apply immediately. Difficulty and display stay in the main Settings screen."
	settings_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_copy.custom_minimum_size = Vector2(0.0, 44.0)
	settings_column.add_child(settings_copy)
	var app := get_node_or_null("/root/App")
	var settings: Dictionary = app.call("get_save_data") if app and app.has_method("get_save_data") else {}
	_pause_settings_first_control = _add_pause_setting_slider(settings_column, "Master", "master_volume", float(settings.get("master_volume", 1.0)))
	_add_pause_setting_slider(settings_column, "Music", "music_volume", float(settings.get("music_volume", 0.8)))
	_add_pause_setting_slider(settings_column, "SFX", "sfx_volume", float(settings.get("sfx_volume", 0.9)))
	var comfort_heading := Label.new()
	comfort_heading.text = "COMFORT"
	comfort_heading.add_theme_font_size_override("font_size", 18)
	settings_column.add_child(comfort_heading)
	var shake := CheckButton.new()
	shake.name = "PauseReducedCameraShake"
	shake.text = "Reduced camera shake"
	shake.custom_minimum_size = Vector2(0.0, 42.0)
	shake.button_pressed = bool(settings.get("reduced_camera_shake", false))
	shake.toggled.connect(func(enabled: bool) -> void: _update_pause_setting("reduced_camera_shake", enabled))
	settings_column.add_child(shake)
	var motion := CheckButton.new()
	motion.name = "PauseReducedMotion"
	motion.text = "Reduced motion"
	motion.custom_minimum_size = Vector2(0.0, 42.0)
	motion.button_pressed = bool(settings.get("reduced_motion", false))
	motion.toggled.connect(func(enabled: bool) -> void: _update_pause_setting("reduced_motion", enabled))
	settings_column.add_child(motion)
	_pause_settings_status = Label.new()
	_pause_settings_status.custom_minimum_size = Vector2(0.0, 42.0)
	_pause_settings_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_column.add_child(_pause_settings_status)
	_add_pause_button(settings_column, "Back", _show_pause_menu)


func _show_pause_menu() -> void:
	if not is_instance_valid(_pause_menu_panel) or not is_instance_valid(_pause_settings_panel):
		return
	_pause_menu_panel.visible = true
	_pause_settings_panel.visible = false
	if is_instance_valid(_pause_resume_button):
		_pause_resume_button.grab_focus()


func _show_pause_settings() -> void:
	if not is_instance_valid(_pause_menu_panel) or not is_instance_valid(_pause_settings_panel):
		return
	_pause_menu_panel.visible = false
	_pause_settings_panel.visible = true
	_pause_settings_status.text = ""
	if is_instance_valid(_pause_settings_first_control):
		_pause_settings_first_control.grab_focus()


func _add_pause_setting_slider(parent: Control, label_text: String, setting_key: String, value: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(120.0, 0.0)
	label.add_theme_font_size_override("font_size", 18)
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "PauseSetting_%s" % setting_key
	slider.custom_minimum_size = Vector2(360.0, 38.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = value * 100.0
	slider.value_changed.connect(func(new_value: float) -> void: _update_pause_setting(setting_key, new_value / 100.0))
	row.add_child(slider)
	parent.add_child(row)
	return slider


func _update_pause_setting(setting_key: String, value: Variant) -> void:
	var app := get_node_or_null("/root/App")
	var applied := app and app.has_method("update_setting") and bool(app.call("update_setting", setting_key, value))
	if not is_instance_valid(_pause_settings_status):
		return
	if not applied:
		_pause_settings_status.text = "Could not save this change. The previous value is still active."
	elif app.has_method("is_save_read_only") and bool(app.call("is_save_read_only")):
		_pause_settings_status.text = "Applied for this session; the newer save remains untouched."
	else:
		_pause_settings_status.text = "Saved."


func _pause_style(fill: Color, border: Color, radius: int, width: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	return box


func _add_pause_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(400.0, 58.0)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_hover_color", Color("fff8e8"))
	button.add_theme_color_override("font_focus_color", Color("f4bf3a"))
	button.add_theme_stylebox_override("normal", _pause_style(Color("1b2638"), Color("36455d"), 8))
	button.add_theme_stylebox_override("hover", _pause_style(Color("263650"), Color("f4bf3a"), 8, 2))
	button.add_theme_stylebox_override("pressed", _pause_style(Color("111a29"), Color("f4bf3a"), 8, 2))
	button.add_theme_stylebox_override("focus", _pause_style(Color("263650"), Color("f4bf3a"), 8, 3))
	button.focus_entered.connect(_play_sfx.bind(&"ui_move", 0.62))
	button.pressed.connect(callback)
	button.pressed.connect(_play_sfx.bind(&"ui_confirm", 0.78))
	parent.add_child(button)
	return button


func _on_retry_pressed() -> void:
	if _save_error.is_empty():
		restart_race()
	else:
		_attempt_result_commit(race_manager.get_results())


func _attempt_result_commit(results: Array) -> void:
	var committed := _report_result_to_app(results)
	_retry_button.disabled = false
	_continue_button.disabled = not committed
	_retry_button.text = "Retry" if committed else "Retry Save"
	_update_results(results)
	if committed:
		_continue_button.grab_focus()
	else:
		_retry_button.grab_focus()


func _report_result_to_app(results: Array) -> bool:
	_save_error = ""
	var app := get_node_or_null("/root/App")
	if app == null or _session.is_empty() or not app.has_method("report_race_result"):
		return true
	for result: Dictionary in results:
		if result.get("vehicle") == _player_vehicle:
			var committed := bool(app.call("report_race_result", int(result["position"]), float(result["time"]), results, bool(result.get("dnf", false))))
			if not committed and app.has_method("get_last_save_error"):
				_save_error = String(app.call("get_last_save_error"))
			return committed
	return true


func _format_time(total_seconds: float) -> String:
	return "%02d:%04.1f" % [int(total_seconds / 60.0), fmod(total_seconds, 60.0)]


func _ordinal(value: int) -> String:
	match value:
		1:
			return "1ST"
		2:
			return "2ND"
		3:
			return "3RD"
		_:
			return "%dTH" % value
