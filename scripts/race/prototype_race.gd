extends Node2D

signal return_requested

class RacePauseOverlay extends Control:
	signal cancel_pressed(requested_pause: bool)

	var enabled := true
	var settings_open := false

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process_input(true)

	func _input(event: InputEvent) -> void:
		var app := get_node_or_null("/root/App")
		if app and app.has_method("is_race_loading") and app.call("is_race_loading"):
			return
		var requested_pause := InputMap.has_action("pause") and event.is_action_pressed("pause")
		if event is InputEventKey:
			requested_pause = requested_pause or (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE
		elif event is InputEventJoypadButton:
			requested_pause = requested_pause or (event as InputEventJoypadButton).pressed and (event as InputEventJoypadButton).button_index == 6
		var requested_resume := get_tree().paused and event.is_action_pressed("ui_cancel")
		if enabled and (requested_pause or requested_resume):
			if get_tree().paused and not settings_open:
				get_tree().paused = false
				visible = false
				cancel_pressed.emit(false)
			else:
				cancel_pressed.emit(requested_pause)
			get_viewport().set_input_as_handled()


const RUSTBUG_SCENE := preload("res://scenes/vehicles/rustbug.tscn")
const AI_CONTROLLER_SCRIPT := preload("res://scripts/vehicle/ai_vehicle_controller.gd")
const TRACK_VARIANT_SCRIPT := preload("res://scripts/presentation/track_variant_presenter.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const RACE_HUD_SCRIPT := preload("res://scripts/ui/race_hud.gd")
const MENU_BUTTON_SCRIPT := preload("res://scripts/ui/motorsport_button.gd")
const MENU_SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const PREPARATION_SCRIPT := preload("res://scripts/race/race_preparation.gd")
const GENERATED_CIRCUITS := preload("res://scripts/race/generated_circuit_identity.gd")
const CIRCUIT_PREVIEW := preload("res://scripts/race/circuit_route_preview.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const PERSONAL_GHOST_SCRIPT := preload("res://scripts/race/personal_ghost.gd")
const RACE_MUSIC_PLAN := preload("res://scripts/audio/race_music_plan.gd")
const STARTING_GRID_SYNC_FRAMES := 2
const COUNTDOWN_STEP_SECONDS := 0.65
const PAUSE_STRIP_HEIGHT := 12.0
## The victory/defeat outro is a four-bar phrase. Hold the menu phase off it for
## roughly that long so the finish reads as an outro rather than a cut.
const RESULTS_OUTRO_SECONDS := 7.0
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
const AI_LANE_OFFSETS: Array[float] = [-42.0, 38.0, 6.0]
const TRACK_SCENES: Dictionary = {
	&"workshop": "res://scenes/tracks/workshop_workbench.tscn",
	&"office": "res://scenes/tracks/office_desk.tscn",
	&"kitchen": "res://scenes/tracks/kitchen_circuit.tscn",
}

@onready var race_manager: RaceManager = $RaceManager
@onready var hud_label: Label = $HUD/HUDLabel
@onready var controls_label: Label = $HUD/ControlsLabel
@onready var camera: Camera2D = $FollowCamera2D
@onready var track_root: Node2D = $KitchenGraybox

var _player_vehicle: VehicleController
var _finished: bool = false
## Set when the player leaves the results screen (continue/retry/abandon) so the
## queued menu phase cannot fire after the scene has moved on.
var _left_results := false
var _countdown_label: Label
var _race_flash_label: Label
var _race_hud: RaceHUD
var _position_label: Label
var _results_panel: Panel
var _results_label: Label
var _retry_button: Button
var _mastery_button: Button
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
var _player_took_lead := false
var _race_won := false
var _track_variant_presenter: TrackVariantPresenter
var _countdown_tween: Tween
var _race_flash_tween: Tween
var _countdown_active := false
var _starting_collision_states: Array[Dictionary] = []
var is_preparing := false
var _personal_ghost: PersonalGhost
var _ghost_samples: Array = []
var _next_ghost_sample_time := 0.0
var _previous_ghost_capture_time := 0.0
var _previous_ghost_capture_transform := Transform2D.IDENTITY
var _mastery_capture_finished := false
var _last_lap_elapsed := 0.0
var _best_lap := INF


func _ready() -> void:
	_create_phase_one_ui()
	_configure_session()
	var app := get_node_or_null("/root/App")
	if app and app.has_method("is_race_loading") and app.call("is_race_loading"):
		is_preparing = true
		process_mode = Node.PROCESS_MODE_DISABLED
		var player := get_tree().get_first_node_in_group("player_vehicle") as RigidBody2D
		if player:
			player.freeze = true
		call_deferred("_prepare_race_async")
		return
	if not _configure_track_variant():
		call_deferred("_abort_failed_race")
		return
	_complete_race_setup()


func _complete_race_setup(start_countdown: bool = true) -> void:
	_create_pause_overlay()
	_pause_overlay.enabled = start_countdown
	_configure_racers()
	_configure_personal_ghost()
	for racer: Node2D in race_manager.get_rankings():
		if racer is RigidBody2D:
			var body := racer as RigidBody2D
			_starting_collision_states.append({"body": body, "layer": body.collision_layer, "mask": body.collision_mask})
			body.collision_layer = 0
			body.collision_mask = 0
	race_manager.race_started.connect(_release_starting_grid)
	race_manager.race_started.connect(_begin_mastery_capture)
	race_manager.race_finished.connect(_on_race_finished)
	race_manager.position_changed.connect(_on_position_changed)
	race_manager.wrong_way_changed.connect(_on_wrong_way_changed)
	race_manager.lap_completed.connect(_on_lap_completed)
	race_manager.racer_finished.connect(_on_racer_finished)
	race_manager.racer_recovered.connect(_on_racer_recovered)
	race_manager.results_ready.connect(_on_results_ready)
	if OS.is_debug_build():
		_ensure_debug_overlay()
	if start_countdown:
		_countdown_active = true
		call_deferred("_run_countdown")


func _loading_step(phase: String) -> void:
	var app := get_node_or_null("/root/App")
	if app:
		await app.call("loading_step", phase)


func _prepare_race_async() -> void:
	var app := get_node("/root/App")
	var event: Dictionary = _session.get("event", {})
	var preparation := PREPARATION_SCRIPT.new()
	add_child(preparation)
	app.call("set_loading_section", 1)
	await _loading_step("Generating a legal circuit")
	if String(event.get("circuit", "")) == "generated":
		var key := _circuit_cache_key(event)
		var prepared: Dictionary = {}
		var used_cached_prepared := false
		if not key.is_empty():
			prepared = TRACK_BUILDER.cached_prepared(key)
			if not prepared.is_empty():
				used_cached_prepared = true
		if prepared.is_empty():
			prepared = await preparation.run_data_job(TRACK_BUILDER.prepare_layout.bind(StringName(event.get("theme", "kitchen")), StringName(event.get("room", "classic")), int(event.get("seed", 0)), _track_generation_options(event)), Thread.PRIORITY_NORMAL)
			if not prepared.is_empty() and not key.is_empty():
				TRACK_BUILDER.store_prepared(key, prepared)
		if app.call("is_race_loading_cancelled"):
			app.call("complete_race_loading")
			return
		if prepared.is_empty():
			app.call("fail_race_loading", "Circuit generation failed")
			return
		if app.has_method("record_prepared_mastery_metrics"):
			app.call("record_prepared_mastery_metrics", event, prepared.get("racing_line_metrics", {}))
		var expected_preview_fingerprint := String(event.get("preview_fingerprint", ""))
		if not expected_preview_fingerprint.is_empty():
			var preview_identity: Variant = event.get("generated_circuit_identity", event.get("circuit_identity"))
			var loaded_preview_fingerprint := CIRCUIT_PREVIEW.fingerprint_for_prepared(preview_identity, prepared)
			if loaded_preview_fingerprint != expected_preview_fingerprint:
				if used_cached_prepared:
					# Cache hit produced a fingerprint mismatch (stale or wrong
					# identity). Fall back to full generation instead of failing.
					prepared = await preparation.run_data_job(TRACK_BUILDER.prepare_layout.bind(StringName(event.get("theme", "kitchen")), StringName(event.get("room", "classic")), int(event.get("seed", 0)), _track_generation_options(event)), Thread.PRIORITY_NORMAL)
					if app.call("is_race_loading_cancelled"):
						app.call("complete_race_loading")
						return
					if prepared.is_empty():
						app.call("fail_race_loading", "Circuit generation failed")
						return
					if not key.is_empty():
						TRACK_BUILDER.store_prepared(key, prepared)
					loaded_preview_fingerprint = CIRCUIT_PREVIEW.fingerprint_for_prepared(preview_identity, prepared)
				else:
					app.call("fail_race_loading", "The loaded circuit did not match the confirmed preview")
					return
			prepared["loaded_preview_fingerprint"] = loaded_preview_fingerprint
		if app.has_method("record_prepared_mastery_metrics"):
			app.call("record_prepared_mastery_metrics", event, prepared.get("racing_line_metrics", {}))
		for texture_path in TRACK_BUILDER.preparation_texture_paths(prepared["spec"]):
			if TRACK_BUILDER.has_prepared_outline_path(texture_path):
				continue
			if not ResourceLoader.exists(texture_path):
				continue
			await _loading_step("Preparing scenery footprints")
			var texture := load(texture_path) as Texture2D
			if texture != null and not TRACK_BUILDER.has_prepared_outline(texture):
				var outline: Dictionary = await preparation.run_data_job(TRACK_BUILDER.compute_alpha_outline.bind(texture.get_image(), texture.get_width(), texture.get_height()))
				if outline.is_empty():
					app.call("fail_race_loading", "Scenery footprints could not be prepared")
					return
				TRACK_BUILDER.install_prepared_outline(texture, outline)
			if app.call("is_race_loading_cancelled"):
				app.call("complete_race_loading")
				return
		await _loading_step("Building the room")
		var embedded := track_root
		remove_child(embedded)
		embedded.free()
		var used_cached_room := false
		if not key.is_empty():
			var packed: PackedScene = TRACK_BUILDER.cached_room(key)
			if packed != null:
				var candidate := packed.instantiate()
				if candidate is Node2D and candidate.get_child_count() > 0:
					track_root = candidate
					used_cached_room = true
		if not used_cached_room:
			track_root = TRACK_BUILDER.create_layout_root(prepared)
		track_root.name = "Track"
		add_child(track_root)
		if prepared.has("loaded_preview_fingerprint"):
			track_root.set_meta("preview_fingerprint", prepared["loaded_preview_fingerprint"])
		if not used_cached_room:
			await TRACK_BUILDER.assemble_runtime(track_root, prepared, _loading_step)
			if not key.is_empty():
				var pscene := PackedScene.new()
				if pscene.pack(track_root) == OK:
					TRACK_BUILDER.store_room(key, pscene)
		_apply_circuit_identity_metadata(event)
		_apply_track_variant(StringName(event.get("theme", "kitchen")))
	else:
		if not _configure_track_variant():
			app.call("fail_race_loading", "The circuit could not be opened")
			return
	if app.call("is_race_loading_cancelled"):
		app.call("complete_race_loading")
		return
	app.call("set_loading_section", 2)
	var field_racers: Array[Dictionary] = _build_field_racers_for_preparation()
	var resolved_keys: Dictionary = IDENTITIES.resolve_field_visual_keys(field_racers)
	var keys_to_prepare: Array[String] = []
	for k in resolved_keys.values():
		var sk := String(k)
		if not keys_to_prepare.has(sk):
			keys_to_prepare.append(sk)
	for visual_key: String in keys_to_prepare:
		var display := visual_key.split("|", true, 1)[0] if visual_key.find("|") != -1 else visual_key
		await _loading_step("Preparing %s animation" % display.capitalize())
		var plan := IDENTITIES.motion_preparation_plan_for_key(visual_key)
		if not (plan["jobs"] as Array).is_empty():
			var rendered: Dictionary = await preparation.run_data_job(IDENTITIES.render_motion_plan.bind(plan))
			if rendered.is_empty():
				app.call("fail_race_loading", "Vehicle graphics could not be prepared")
				return
			for index in rendered["jobs"].size():
				if not IDENTITIES.install_motion_image_for_key(visual_key, rendered["jobs"][index], rendered["images"][index]):
					app.call("fail_race_loading", "Vehicle graphics could not be prepared")
					return
		if app.call("is_race_loading_cancelled"):
			app.call("complete_race_loading")
			return
	preparation.queue_free()
	app.call("set_loading_section", 3)
	await _loading_step("Setting the starting grid")
	_complete_race_setup(false)
	camera.global_position = _player_vehicle.global_position
	camera.reset_smoothing()
	camera.force_update_scroll()
	await _loading_step("Preparing race audio")
	var director := app.get("audio_director") as Node
	if director:
		# The director swaps in this circuit's score directly on Starting Grid.
		director.call("play_race_music")
		for entry: Dictionary in _build_field_racers_for_preparation():
			await director.call("warm_vehicle_audio", String(entry.get("vehicle_id", "")), _loading_step.bind("Preparing race audio"))
			await _loading_step("Preparing race audio")
	for frame in 3:
		await _loading_step("Warming graphics for the starting grid")
	if not app.call("complete_race_loading"):
		return
	is_preparing = false
	process_mode = Node.PROCESS_MODE_INHERIT
	_pause_overlay.enabled = true
	_countdown_active = true
	call_deferred("_run_countdown")


func _exit_tree() -> void:
	if get_tree():
		get_tree().paused = false
	var app := get_node_or_null("/root/App")
	if app and app.has_method("set_race_audio_paused"):
		app.call("set_race_audio_paused", false)
	var director := _audio_director()
	if director and director.has_method("set_positional_vehicles"):
		var no_vehicles: Array[Node] = []
		director.call("set_positional_vehicles", no_vehicles)


func _process(_delta: float) -> void:
	_update_race_hud()
	_update_personal_ghost()


func _begin_mastery_capture() -> void:
	_ghost_samples.clear()
	_next_ghost_sample_time = 0.0
	_last_lap_elapsed = 0.0
	_best_lap = INF
	_mastery_capture_finished = false
	if String(_session.get("mode", "")) == "mastery" and is_instance_valid(_player_vehicle):
		_previous_ghost_capture_time = 0.0
		_previous_ghost_capture_transform = _player_vehicle.global_transform
		_capture_ghost_sample(0.0, _previous_ghost_capture_transform)
		_next_ghost_sample_time = PersonalGhost.SAMPLE_INTERVAL


func _update_personal_ghost() -> void:
	if is_instance_valid(_personal_ghost):
		_personal_ghost.set_playback_time(race_manager.race_time)
	if String(_session.get("mode", "")) != "mastery" or _mastery_capture_finished or not race_manager.is_running or not is_instance_valid(_player_vehicle):
		return
	_capture_mastery_through(race_manager.race_time, _player_vehicle.global_transform)


func _capture_mastery_through(current_time: float, current_transform: Transform2D) -> void:
	while _next_ghost_sample_time <= current_time + 0.0001 and _ghost_samples.size() < PersonalGhost.MAX_SAMPLES:
		var duration := current_time - _previous_ghost_capture_time
		var weight := clampf((_next_ghost_sample_time - _previous_ghost_capture_time) / duration, 0.0, 1.0) if duration > 0.000001 else 1.0
		var sample_transform := Transform2D(
			lerp_angle(_previous_ghost_capture_transform.get_rotation(), current_transform.get_rotation(), weight),
			_previous_ghost_capture_transform.origin.lerp(current_transform.origin, weight)
		)
		_capture_ghost_sample(_next_ghost_sample_time, sample_transform)
		_next_ghost_sample_time += PersonalGhost.SAMPLE_INTERVAL
	_previous_ghost_capture_time = current_time
	_previous_ghost_capture_transform = current_transform


func _capture_ghost_sample(sample_time: float, sample_transform: Transform2D) -> void:
	_ghost_samples.append(PERSONAL_GHOST_SCRIPT.sample(sample_time, sample_transform))


func _configure_personal_ghost() -> void:
	if String(_session.get("mode", "")) != "mastery":
		return
	var ghost: Dictionary = _session.get("best_ghost", {})
	if ghost.is_empty():
		return
	_personal_ghost = PERSONAL_GHOST_SCRIPT.new() as PersonalGhost
	_personal_ghost.name = "PersonalBestGhost"
	add_child(_personal_ghost)
	var pvid := String(_session.get("vehicle_id", "rustbug"))
	var pkey := IDENTITIES.resolve_visual_key(pvid, "rae")
	var ptex := IDENTITIES.car_texture_for_key(pkey)
	if not _personal_ghost.configure(ghost, ptex):
		_personal_ghost.queue_free()
		_personal_ghost = null


func _build_field_racers_for_preparation() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var pvid := String(_session.get("vehicle_id", "rustbug"))
	entries.append({"vehicle_id": pvid, "driver_id": "rae", "slot": 0})
	var ev: Dictionary = _session.get("event", {})
	var oids: Array = ev.get("opponents", FALLBACK_OPPONENTS) if not ev.is_empty() else FALLBACK_OPPONENTS
	var ocnt := 0 if String(_session.get("mode", "")) == "mastery" else clampi(int(ev.get("opponent_count", oids.size())), 0, 3)
	for i in mini(oids.size(), ocnt):
		var did := String(oids[i])
		var d := CATALOG.get_driver(did)
		var vid := String(d.get("vehicle_id", "rustbug"))
		entries.append({"vehicle_id": vid, "driver_id": did, "slot": i + 1})
	return entries


func _resolve_field_visual_keys() -> Dictionary:
	var racers := _build_field_racers_for_preparation()
	return IDENTITIES.resolve_field_visual_keys(racers)


func _configure_racers() -> void:
	_player_vehicle = get_tree().get_first_node_in_group("player_vehicle") as VehicleController
	if _player_vehicle == null:
		push_error("Prototype race requires a player Rustbug")
		return
	var player_vehicle_id := String(_session.get("vehicle_id", "rustbug"))
	var field_visuals := _resolve_field_visual_keys()
	var player_key := String(field_visuals.get(0, player_vehicle_id))
	_configure_vehicle(_player_vehicle, 0, true, CATALOG.get_driver("rae"), player_vehicle_id, player_key)
	camera.call("set_target", _player_vehicle)
	var app := get_node_or_null("/root/App")
	if app and app.has_method("set_local_race_vehicle"):
		app.call("set_local_race_vehicle", _player_vehicle, player_vehicle_id)

	var event: Dictionary = _session.get("event", {})
	var opponent_ids: Array = event.get("opponents", FALLBACK_OPPONENTS) if not event.is_empty() else FALLBACK_OPPONENTS
	var opponent_count := 0 if String(_session.get("mode", "")) == "mastery" else clampi(int(event.get("opponent_count", opponent_ids.size())), 0, 3)
	var difficulty := String(_session.get("difficulty", "club_circuit"))
	var grid := _grid_transforms(race_manager.is_reverse_direction())
	var positional_vehicles: Array[Node] = []
	for ai_index in mini(opponent_ids.size(), opponent_count):
		var driver_id := String(opponent_ids[ai_index])
		var driver := CATALOG.get_driver(driver_id)
		var ai_vehicle_id := String(driver.get("vehicle_id", "rustbug"))
		var ai_visual_key := String(field_visuals.get(ai_index + 1, ai_vehicle_id))
		var ai_vehicle := RUSTBUG_SCENE.instantiate() as VehicleController
		ai_vehicle.name = "%sAI" % String(driver.get("name", "Racer%d" % (ai_index + 1))).replace(" ", "")
		ai_vehicle.stats = CATALOG.create_vehicle_stats(ai_vehicle_id)
		ai_vehicle.remove_from_group("player_vehicle")
		ai_vehicle.add_to_group("race_vehicle")
		ai_vehicle.set_meta("audio_vehicle_id", ai_vehicle_id)
		ai_vehicle.set_player_controlled(false)
		ai_vehicle.set_controls_locked(true)
		# Register the rigid body at its actual spawn, not at the scene's
		# default origin inside the island followed by a live teleport.
		ai_vehicle.transform = global_transform.affine_inverse() * grid[ai_index + 1]
		add_child(ai_vehicle)
		_configure_vehicle(ai_vehicle, ai_index + 1, false, driver, ai_vehicle_id, ai_visual_key)
		var ai_controller := AI_CONTROLLER_SCRIPT.new() as AIVehicleController
		ai_vehicle.add_child(ai_controller)
		ai_controller.configure(
			ai_vehicle,
			race_manager,
			AI_LANE_OFFSETS[ai_index],
			difficulty,
			driver_id,
			driver.get("ai_style", {}) as Dictionary
		)
		positional_vehicles.append(ai_vehicle)
	var director := _audio_director()
	if director and director.has_method("set_positional_vehicles"):
		director.call("set_positional_vehicles", positional_vehicles)


func _configure_vehicle(
		vehicle: VehicleController,
		racer_index: int,
		is_player: bool,
		driver: Dictionary,
		vehicle_id: String,
		visual_key: String = ""
) -> void:
	var grid := _grid_transforms(race_manager.is_reverse_direction())
	vehicle.freeze = true
	vehicle.place_on_grid(grid[racer_index])
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
	var use_visual := visual_key if not visual_key.is_empty() else vehicle_id
	vehicle.configure_identity(driver_name, vehicle_name, use_visual)
	vehicle.configure_racer_marker(RACER_MARKER_COLORS[racer_index], racer_index)
	race_manager.register_racer(vehicle, driver_name, vehicle_name, is_player)


func _release_starting_grid() -> void:
	if not is_inside_tree():
		return
	# Clear stale contacts while the body accepts its queued spawn transform.
	# Restore normal collision immediately after the physics server syncs it.
	for entry: Dictionary in _starting_collision_states:
		var body := entry["body"] as RigidBody2D
		body.collision_layer = 0
		body.collision_mask = 0
		body.freeze = false
	for _frame in STARTING_GRID_SYNC_FRAMES:
		await get_tree().physics_frame
		if not is_inside_tree():
			return
	for entry: Dictionary in _starting_collision_states:
		var body := entry["body"] as RigidBody2D
		if is_instance_valid(body):
			body.collision_layer = int(entry["layer"])
			body.collision_mask = int(entry["mask"])
	_starting_collision_states.clear()


func _configure_session() -> void:
	var app := get_node_or_null("/root/App")
	if app and app.has_method("get_current_race_session"):
		var session: Variant = app.call("get_current_race_session")
		if session is Dictionary and not (session as Dictionary).is_empty():
			_session = session
	var event: Dictionary = _session.get("event", {})
	if not event.is_empty():
		race_manager.laps_to_finish = clampi(int(event.get("laps", 3)), 1, 99)
		race_manager.set_reverse_direction(bool(event.get("reverse", false)))
		if is_instance_valid(_race_hud):
			var vehicle := CATALOG.get_vehicle(String(_session.get("vehicle_id", "rustbug")))
			_race_hud.set_context(String(event.get("name", "Household Circuit")), String(vehicle.get("name", "Rustbug")))


func _configure_track_variant() -> bool:
	var event: Dictionary = _session.get("event", {})
	var requested_theme := StringName(event.get("theme", "kitchen"))
	var scene_path := ""
	var packed: PackedScene = null
	if String(event.get("circuit", "")) == "generated":
		var circuit_room := StringName(event.get("room", "classic"))
		var circuit_seed := int(event.get("seed", 0))
		var built := TRACK_BUILDER.build_packed(requested_theme, circuit_room, circuit_seed, _track_generation_options(event))
		packed = built.get("scene") as PackedScene
		var app := get_node_or_null("/root/App")
		if app and app.has_method("record_prepared_mastery_metrics"):
			app.call("record_prepared_mastery_metrics", event, built.get("racing_line_metrics", {}))
		if packed == null:
			push_error("Could not generate circuit %s/%s/%d" % [requested_theme, circuit_room, circuit_seed])
			return false
	else:
		scene_path = String(TRACK_SCENES.get(requested_theme, ""))
		var track_override := OS.get_environment("PC_TRACK_SCENE")
		if not track_override.is_empty():
			scene_path = track_override
		packed = load(scene_path) as PackedScene
	if packed == null:
		push_error("Could not load circuit scene %s" % scene_path)
		return false
	var embedded := track_root
	embedded.get_parent().remove_child(embedded)
	embedded.free()
	track_root = packed.instantiate() as Node2D
	track_root.name = "Track"
	add_child(track_root)
	_apply_circuit_identity_metadata(event)
	_apply_track_variant(requested_theme)
	return true


func _track_generation_options(event: Dictionary) -> Dictionary:
	return TRACK_BUILDER.generated_circuit_options(event)


func _circuit_cache_key(event: Dictionary) -> String:
	return TRACK_BUILDER.generated_circuit_cache_key(event)


func _apply_circuit_identity_metadata(event: Dictionary) -> void:
	var identity: Variant = event.get("circuit_identity")
	if identity is Dictionary:
		var identity_record := identity as Dictionary
		track_root.set_meta("circuit_identity", identity_record.duplicate(true))
		track_root.set_meta("circuit_fingerprint", String(event.get("circuit_fingerprint", "")))
		track_root.set_meta("circuit_schema_version", int(event.get("circuit_schema_version", 0)))
		track_root.set_meta("circuit_generator_version", int(event.get("circuit_generator_version", 0)))
		track_root.set_meta("championship_seed", int(identity_record.get("championship_seed", 0)))
		track_root.set_meta("circuit_sub_seeds", (identity_record.get("sub_seeds", {}) as Dictionary).duplicate(true))
	var generated_identity: Variant = event.get("generated_circuit_identity")
	if generated_identity is Dictionary:
		track_root.set_meta("generated_circuit_identity", (generated_identity as Dictionary).duplicate(true))
		track_root.set_meta("generated_circuit_fingerprint", String((generated_identity as Dictionary).get("fingerprint", "")))
		track_root.set_meta("circuit_display_name", String((generated_identity as Dictionary).get("display_name", event.get("name", ""))))
		track_root.set_meta("circuit_summary", String((generated_identity as Dictionary).get("summary", "")))


func _apply_track_variant(requested_theme: StringName) -> void:
	if track_root.has_meta("room_bounds"):
		var room_bounds: Rect2 = track_root.get_meta("room_bounds")
		camera.limit_left = floori(room_bounds.position.x)
		camera.limit_top = floori(room_bounds.position.y)
		camera.limit_right = ceili(room_bounds.end.x)
		camera.limit_bottom = ceili(room_bounds.end.y)
		var reset_manager := get_node_or_null("ResetManager")
		if reset_manager != null:
			reset_manager.set("valid_bounds", room_bounds.grow(120.0))
			reset_manager.set("valid_polygon", track_root.get_meta("room_polygon", PackedVector2Array()))
			reset_manager.set("valid_polygon_margin", 120.0)
			reset_manager.set("invalid_polygon", track_root.get_meta("island_invalid_polygon", PackedVector2Array()))
	_track_variant_presenter = TRACK_VARIANT_SCRIPT.new() as TrackVariantPresenter
	track_root.add_child(_track_variant_presenter)
	_track_variant_presenter.configure(track_root, requested_theme)
	var discovered_checkpoints: Array[Node] = []
	for child: Node in track_root.get_children():
		if child.is_in_group("track_checkpoints"):
			discovered_checkpoints.append(child)
	race_manager.configure_checkpoints(discovered_checkpoints)
	_configure_route_reference()


func _configure_route_reference() -> void:
	# Route-reference seam: hand the race manager the actual drivable route once,
	# so wrong-way detection follows the real route tangent instead of the
	# checkpoint chord. Generated tracks expose a hidden RacingLine; older
	# authored fixtures store ordered centerline samples as surface tiles.
	# Without either, the manager falls back to the direct checkpoint chord.
	var route := PackedVector2Array()
	var racing_line := track_root.get_node_or_null("RacingLine") as Line2D
	if racing_line != null:
		for point: Vector2 in racing_line.points:
			route.append(racing_line.to_global(point))
	else:
		var tiles := track_root.get_node_or_null("TrackSurfaceTiles") as Node2D
		if tiles != null:
			for tile: Node in tiles.get_children():
				if tile is Node2D:
					route.append((tile as Node2D).global_position)
	race_manager.configure_route_reference(route, float(track_root.get_meta("corridor_max_half_width", TrackBuilderCore.HALF_WIDTH)))


func _abort_failed_race() -> void:
	set_process(false)
	set_physics_process(false)
	var app := get_node_or_null("/root/App")
	if app and app.has_method("abandon_race"):
		app.call("abandon_race")


func _grid_transforms(reverse: bool) -> Array[Transform2D]:
	var container := track_root.get_node_or_null("GridReverse" if reverse else "GridForward") as Node2D
	var transforms: Array[Transform2D] = []
	if container:
		for child: Node in container.get_children():
			var marker := child as Node2D
			if marker:
				var heading := marker.rotation
				var tiles := track_root.get_node_or_null("TrackSurfaceTiles")
				if track_root.get_node_or_null("RacingLine") == null and tiles != null and tiles.get_child_count() >= 3:
					# Old snapshots reused the finish-line heading for every slot,
					# including slots already on a bend. Face the local road tangent.
					var nearest_distance := INF
					for i in tiles.get_child_count():
						var start := (tiles.get_child(i) as Node2D).position
						var end := (tiles.get_child((i + 1) % tiles.get_child_count()) as Node2D).position
						var closest := Geometry2D.get_closest_point_to_segment(marker.position, start, end)
						var distance := marker.position.distance_squared_to(closest)
						if distance < nearest_distance and start.distance_squared_to(end) > 0.001:
							nearest_distance = distance
							var tangent := (end - start) * (-1.0 if reverse else 1.0)
							heading = tangent.angle() + PI * 0.5
				transforms.append(Transform2D(heading, marker.position))
	if transforms.size() == 4:
		return transforms
	return REVERSE_GRID_TRANSFORMS if reverse else GRID_TRANSFORMS


func _run_countdown() -> void:
	var director := _audio_director()
	if director != null and director.has_method("stop_live_rotation"):
		director.call("stop_live_rotation")
	_cue_live_section("grid")
	race_manager.begin_countdown()
	for value in ["3", "2", "1"]:
		_present_countdown(value)
		_play_sfx(&"countdown", 0.82)
		race_manager.report_countdown_tick(value)
		# process_in_physics keeps the countdown on the fixed physics step so the
		# race start is deterministic instead of drifting with rendered frame rate.
		await get_tree().create_timer(COUNTDOWN_STEP_SECONDS, false, true).timeout
	_present_countdown("GO!")
	_play_sfx(&"go", 0.92)
	race_manager.report_countdown_tick("GO!")
	race_manager.start_race()
	if "--media-capture" in OS.get_cmdline_user_args():
		print("MEDIA_RACE_READY %s %s" % [String(_session.get("event_id", "unknown")), String(_session.get("vehicle_id", "unknown"))])
	_countdown_active = false
	await get_tree().create_timer(COUNTDOWN_STEP_SECONDS, false, true).timeout
	_countdown_label.visible = false


func _update_race_hud() -> void:
	if not is_instance_valid(_race_hud) or not is_instance_valid(_player_vehicle):
		return
	var shown_lap := mini(race_manager.lap_count + 1, race_manager.laps_to_finish)
	var boost_ratio := clampf(_player_vehicle.boost_amount / maxf(_player_vehicle.get_boost_capacity(), 0.001), 0.0, 1.0)
	var speed_ratio := clampf(_player_vehicle.speed / maxf(_player_vehicle.get_effective_max_speed(), 0.001), 0.0, 1.2)
	_race_hud.set_telemetry(
		race_manager.get_racer_position(_player_vehicle),
		race_manager.get_racer_count(),
		shown_lap,
		race_manager.laps_to_finish,
		race_manager.race_time,
		speed_ratio,
		boost_ratio
	)
	var racers := race_manager.get_rankings()
	var progress := PackedFloat32Array()
	var total_gates := maxf(1.0, race_manager.laps_to_finish * race_manager.get_checkpoint_count())
	for racer: Node2D in racers:
		progress.append(race_manager.get_racer_progress(racer) / total_gates)
	_race_hud.set_route_progress(progress, racers.find(_player_vehicle), race_manager.get_expected_checkpoint(_player_vehicle))


func _on_race_finished(_total_time: float) -> void:
	_finished = true
	_race_hud.visible = false
	_race_won = is_instance_valid(_player_vehicle) and race_manager.get_racer_position(_player_vehicle) == 1
	var director := _audio_director()
	if director != null and director.has_method("stop_live_rotation"):
		director.call("stop_live_rotation")
	# Cue victory/defeat outro first. _queue_menu_phase waits a beat so the
	# outro gets its musical time before we cue grid (get_live_section reports
	# the incoming target immediately during transition, which used to cut it).
	# Grid arrives during results if the player lingers.
	_cue_live_section("victory" if _race_won else "defeat")
	_results_panel.visible = true
	_retry_button.disabled = true
	_continue_button.disabled = true
	_update_results(race_manager.get_results())
	_queue_menu_phase()


func _queue_menu_phase() -> void:
	# The binding reports the incoming section the moment a transition starts, so
	# polling `get_live_section` would cue grid the instant the victory blend
	# began. Wait out the outro phrase, then hand over to the menu phase.
	await get_tree().create_timer(RESULTS_OUTRO_SECONDS).timeout
	if _left_results or not _finished or not is_inside_tree():
		return
	_cue_live_section("grid")


func _on_position_changed(racer: Node2D, _position: int, _racer_count: int) -> void:
	if racer != _player_vehicle:
		return
	_update_race_hud()
	if _countdown_active or _finished:
		return
	if RACE_MUSIC_PLAN.opening_phase_is_locked(race_manager.lap_count):
		if _position == 1:
			_player_took_lead = true
		return
	if _position == 1 and not _player_took_lead:
		_player_took_lead = true
		_cue_live_section_timed("grid", 8.0)
	else:
		_advance_live_rotation()

func _on_racer_recovered(racer: Node2D) -> void:
	if racer == _player_vehicle and not RACE_MUSIC_PLAN.opening_phase_is_locked(race_manager.lap_count):
		# A spin that gets saved gets a reset sting, then the rotation resumes.
		_cue_live_section_timed("recovery", 8.0)


func _on_wrong_way_changed(racer: Node2D, wrong_way: bool) -> void:
	if racer != _player_vehicle:
		return
	if is_instance_valid(_race_hud):
		_race_hud.set_wrong_way(wrong_way)
	if wrong_way and not _countdown_active and not _finished and not RACE_MUSIC_PLAN.opening_phase_is_locked(race_manager.lap_count):
		_cue_live_section_timed("wrong-way", 6.0)


func _on_lap_completed(lap: int) -> void:
	if String(_session.get("mode", "")) == "mastery" and is_instance_valid(_player_vehicle):
		var elapsed := float(race_manager.get_racer_state(_player_vehicle).get("elapsed", race_manager.race_time))
		var lap_time := elapsed - _last_lap_elapsed
		if lap_time > 0.0:
			_best_lap = minf(_best_lap, lap_time)
		_last_lap_elapsed = elapsed
	if lap >= race_manager.laps_to_finish:
		return
	_race_flash_label.text = "FINAL LAP" if lap == race_manager.laps_to_finish - 1 else "LAP %d" % (lap + 1)
	if lap == race_manager.laps_to_finish - 1:
		var director := _audio_director()
		if director != null and director.has_method("stop_live_rotation"):
			director.call("stop_live_rotation")
		_cue_live_section("final-lap")
	elif RACE_MUSIC_PLAN.opening_phase_is_locked(lap - 1):
		_begin_race_music()
	else:
		# Re-evaluate the running order at each lap boundary instead of holding
		# one section through the whole race.
		_advance_live_rotation()
	_race_flash_label.visible = true
	_race_flash_label.modulate.a = 1.0
	if _race_flash_tween and _race_flash_tween.is_valid():
		_race_flash_tween.kill()
	_race_flash_tween = create_tween()
	_race_flash_tween.tween_interval(1.0)
	_race_flash_tween.tween_property(_race_flash_label, "modulate:a", 0.0, 0.3)
	_race_flash_tween.tween_callback(Callable(_race_flash_label, "hide"))


func _on_racer_finished(racer: Node2D, _position: int, total_time: float) -> void:
	if racer == _player_vehicle and String(_session.get("mode", "")) == "mastery" and not _mastery_capture_finished:
		_capture_mastery_through(total_time, _player_vehicle.global_transform)
		_mastery_capture_finished = true
		var final_sample_time := snappedf(total_time, 0.001)
		while not _ghost_samples.is_empty() and float(_ghost_samples.back()[0]) >= final_sample_time - 0.0005:
			_ghost_samples.pop_back()
		if _ghost_samples.size() >= PersonalGhost.MAX_SAMPLES:
			_ghost_samples.pop_back()
		_capture_ghost_sample(final_sample_time, _player_vehicle.global_transform)
	if _results_panel.visible:
		_update_results(race_manager.get_results())


func _on_results_ready(results: Array) -> void:
	_set_paused(false)
	if _results_finalized:
		return
	_finished = true
	_results_finalized = true
	_pause_overlay.enabled = false
	_race_hud.visible = false
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
	var final_prompt := "CONTINUE · RETRY TO RUN IT AGAIN" if String(_session.get("mode", "quick")) in ["quick", "discovery"] else "RESULT SAVED · CONTINUE OR RETRY"
	var app := get_node_or_null("/root/App")
	var live_session: Dictionary = app.call("get_current_race_session") if app and app.has_method("get_current_race_session") else {}
	var summary: Dictionary = live_session.get("result_summary", {})
	if bool(summary.get("mastery", false)):
		var record: Dictionary = summary.get("mastery_record", {})
		var targets: Dictionary = summary.get("mastery_targets", {})
		if not record.is_empty():
			lines.append("MASTERY · %s MEDAL" % String(record.get("medal", "none")).to_upper())
			lines.append("BEST LAP %s · RACE %s" % [_format_time(float(record["best_lap"])), _format_time(float(record["best_race"]))])
		if not targets.is_empty():
			lines.append("TARGETS  G %s · S %s · B %s" % [_format_time(float(targets["gold"])), _format_time(float(targets["silver"])), _format_time(float(targets["bronze"]))])
		if bool(summary.get("ghost_saved", false)):
			lines.append("PERSONAL BEST GHOST SAVED")
		final_prompt = "NO TIME SAVED · CONTINUE OR RETRY" if bool(summary.get("mastery_dnf", false)) else "TIME TRIAL SAVED · CONTINUE OR RETRY"
	if not _save_error.is_empty():
		final_prompt = "Couldn't save this time trial. Championship is unchanged — continue anytime." if String(_session.get("mode", "")) == "mastery" else "Couldn't save. Retry save, or continue without it."
	lines.append("FINALIZING..." if not _results_finalized else final_prompt)
	_results_label.text = "\n".join(lines)


func restart_race() -> void:
	_left_results = true
	_set_paused(false)
	var app := get_node_or_null("/root/App")
	if app and not _session.is_empty() and app.has_method("retry_race"):
		app.call("retry_race")
	else:
		get_tree().reload_current_scene()


func request_return() -> void:
	_left_results = true
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
	_left_results = true
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
	if not get_tree().paused:
		if requested_pause:
			_toggle_pause()
		else:
			_set_paused(false)
		return
	if is_instance_valid(_pause_settings_panel) and _pause_settings_panel.visible:
		_show_pause_menu()
	elif requested_pause or get_tree().paused:
		_toggle_pause()


func _toggle_pause() -> void:
	if _finished or _results_finalized:
		return
	if not get_tree().paused and not _countdown_active and not race_manager.is_running:
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


func _audio_director() -> Node:
	if not ClassDB.class_exists("GamestrumentsPlayer"):
		return null
	var app := get_node_or_null("/root/App")
	if app == null:
		return null
	var director: Variant = app.get("audio_director")
	if is_instance_valid(director) and director is Node:
		return director as Node
	return null


func _cue_live_section(section: String) -> void:
	var director := _audio_director()
	if director != null and director.has_method("cue_live_section"):
		director.call("cue_live_section", section)


func _cue_live_section_timed(section: String, hold_seconds: float) -> void:
	var director := _audio_director()
	if director != null and director.has_method("cue_live_section_timed"):
		director.call("cue_live_section_timed", section, hold_seconds)


func _advance_live_rotation() -> void:
	var director := _audio_director()
	if director != null and director.has_method("advance_live_rotation"):
		director.call("advance_live_rotation")


func _begin_race_music() -> void:
	# After lap one, rotate through grooves, builds, and peaks. Events (lead,
	# incident, final lap, finish) override that deck.
	var director := _audio_director()
	if director == null or not director.has_method("begin_live_rotation"):
		return
	var event := _music_event()
	var tier := String(event.get("length_tier", "standard"))
	director.call("begin_live_rotation", RACE_MUSIC_PLAN.flow_deck(event), RACE_MUSIC_PLAN.tier_dwell(tier))


func _music_event() -> Dictionary:
	var event: Variant = _session.get("event", {})
	return event as Dictionary if event is Dictionary else {}


func _ensure_debug_overlay() -> void:
	if has_node("DebugOverlay"):
		return
	if not ResourceLoader.exists("res://scripts/ui/" + "debug_overlay.gd"):
		return
	var debug_script := load("res://scripts/ui/" + "debug_overlay.gd") as Script
	if debug_script == null:
		return
	var overlay := debug_script.new() as CanvasLayer
	overlay.name = "DebugOverlay"
	add_child(overlay)


func _create_phase_one_ui() -> void:
	var hud := $HUD as CanvasLayer
	hud_label.visible = false
	controls_label.visible = false
	_race_hud = RACE_HUD_SCRIPT.new() as RaceHUD
	_race_hud.name = "RaceHUD"
	hud.add_child(_race_hud)

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
	_race_flash_label.offset_top = 92.0
	_race_flash_label.offset_right = 840.0
	_race_flash_label.offset_bottom = 144.0
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
	_position_label.visible = false
	hud.add_child(_position_label)

	_results_panel = Panel.new()
	_results_panel.name = "ResultsPanel"
	_results_panel.offset_left = 330.0
	_results_panel.offset_top = 150.0
	_results_panel.offset_right = 950.0
	_results_panel.offset_bottom = 565.0
	_results_panel.visible = false
	_results_panel.add_theme_stylebox_override("panel", _pause_panel_style(Color("0c121c", 0.96), Color("f4c65a")))
	hud.add_child(_results_panel)
	_results_label = Label.new()
	_results_label.offset_left = 28.0
	_results_label.offset_top = 24.0
	_results_label.offset_right = 592.0
	_results_label.offset_bottom = 325.0
	_results_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_label.add_theme_font_size_override("font_size", 20)
	_results_label.add_theme_color_override("font_color", Color(0.96, 0.94, 0.89))
	_results_panel.add_child(_results_label)

	_retry_button = MENU_BUTTON_SCRIPT.new() as Button
	_retry_button.text = "RETRY"
	_retry_button.position = Vector2(126.0, 340.0)
	_retry_button.size = Vector2(170.0, 48.0)
	_retry_button.disabled = true
	_apply_menu_button_art(_retry_button)
	_retry_button.add_theme_font_size_override("font_size", 16)
	_retry_button.pressed.connect(_on_retry_pressed)
	_results_panel.add_child(_retry_button)
	_mastery_button = MENU_BUTTON_SCRIPT.new() as Button
	_mastery_button.text = "SOLO TIME TRIAL"
	_mastery_button.position = Vector2(225.0, 340.0)
	_mastery_button.size = Vector2(170.0, 48.0)
	_mastery_button.disabled = true
	_mastery_button.visible = false
	_apply_menu_button_art(_mastery_button)
	_mastery_button.add_theme_font_size_override("font_size", 16)
	_mastery_button.pressed.connect(_on_mastery_pressed)
	_results_panel.add_child(_mastery_button)
	_continue_button = MENU_BUTTON_SCRIPT.new() as Button
	_continue_button.text = "CONTINUE"
	_continue_button.position = Vector2(324.0, 340.0)
	_continue_button.size = Vector2(170.0, 48.0)
	_continue_button.disabled = true
	_apply_menu_button_art(_continue_button, true)
	_continue_button.add_theme_font_size_override("font_size", 16)
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
	_pause_overlay.theme = MENU_SKIN.make_theme()
	hud.add_child(_pause_overlay)

	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(MENU_SKIN.VOID, 0.8)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_overlay.add_child(shade)

	_pause_menu_panel = PanelContainer.new()
	_pause_menu_panel.name = "PauseMenuPanel"
	_pause_menu_panel.add_theme_stylebox_override("panel", MENU_SKIN.card_style(MENU_SKIN.CREAM, 0.0))
	_pause_menu_panel.position = Vector2(370.0, 105.0)
	_pause_menu_panel.size = Vector2(540.0, 510.0)
	_pause_overlay.add_child(_pause_menu_panel)
	var menu_margin := MarginContainer.new()
	menu_margin.add_theme_constant_override("margin_left", 48)
	menu_margin.add_theme_constant_override("margin_top", 34)
	menu_margin.add_theme_constant_override("margin_right", 48)
	menu_margin.add_theme_constant_override("margin_bottom", 38)
	_pause_menu_panel.add_child(menu_margin)
	var menu_column := VBoxContainer.new()
	menu_column.add_theme_constant_override("separation", 18)
	menu_margin.add_child(menu_column)
	menu_column.add_child(_pause_checker_strip())
	var menu_heading := MENU_SKIN.style_label(Label.new(), 34, MENU_SKIN.INK, true)
	menu_heading.text = "RACE PAUSED"
	menu_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_column.add_child(menu_heading)
	_pause_resume_button = _add_pause_button(menu_column, "Resume", _toggle_pause, true)
	_add_pause_button(menu_column, "Settings", _show_pause_settings)
	_add_pause_button(menu_column, "Restart", restart_race)
	var mode := String(_session.get("mode", "quick"))
	var return_label := "Return to Discovery" if mode == "discovery" else ("Return to Title" if mode == "quick" else "Return to Championship")
	_add_pause_button(menu_column, return_label, request_abandon)

	_pause_settings_panel = PanelContainer.new()
	_pause_settings_panel.name = "PauseSettingsPanel"
	_pause_settings_panel.add_theme_stylebox_override("panel", MENU_SKIN.card_style(MENU_SKIN.CREAM, 0.0))
	_pause_settings_panel.position = Vector2(320.0, 16.0)
	_pause_settings_panel.size = Vector2(640.0, 688.0)
	_pause_settings_panel.visible = false
	_pause_overlay.add_child(_pause_settings_panel)
	var settings_margin := MarginContainer.new()
	settings_margin.add_theme_constant_override("margin_left", 44)
	settings_margin.add_theme_constant_override("margin_top", 26)
	settings_margin.add_theme_constant_override("margin_right", 44)
	settings_margin.add_theme_constant_override("margin_bottom", 30)
	_pause_settings_panel.add_child(settings_margin)
	var settings_column := VBoxContainer.new()
	settings_column.add_theme_constant_override("separation", 12)
	settings_margin.add_child(settings_column)
	settings_column.add_child(_pause_checker_strip())
	var settings_heading := MENU_SKIN.style_label(Label.new(), 30, MENU_SKIN.INK, true)
	settings_heading.text = "RACE SETTINGS"
	settings_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_column.add_child(settings_heading)
	var app := get_node_or_null("/root/App")
	var settings: Dictionary = app.call("get_save_data") if app and app.has_method("get_save_data") else {}
	_pause_settings_first_control = _add_pause_setting_slider(settings_column, "Master", "master_volume", float(settings.get("master_volume", 1.0)))
	_add_pause_setting_slider(settings_column, "Music", "music_volume", float(settings.get("music_volume", 0.8)))
	_add_pause_setting_slider(settings_column, "SFX", "sfx_volume", float(settings.get("sfx_volume", 0.9)))
	_add_pause_setting_slider(settings_column, "Engine", "engine_volume", float(settings.get("engine_volume", settings.get("sfx_volume", 0.9))))
	_add_pause_setting_slider(settings_column, "Tyres", "tyre_volume", float(settings.get("tyre_volume", settings.get("sfx_volume", 0.9))))
	var comfort_heading := MENU_SKIN.style_label(Label.new(), 18, MENU_SKIN.INK, true)
	comfort_heading.text = "COMFORT"
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
	_pause_settings_status = MENU_SKIN.style_label(Label.new(), 15, MENU_SKIN.INK_SOFT)
	_pause_settings_status.custom_minimum_size = Vector2(0.0, 42.0)
	_pause_settings_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	settings_column.add_child(_pause_settings_status)
	_add_pause_button(settings_column, "Back", _show_pause_menu)


func _show_pause_menu() -> void:
	if not is_instance_valid(_pause_menu_panel) or not is_instance_valid(_pause_settings_panel):
		return
	_pause_menu_panel.visible = true
	_pause_settings_panel.visible = false
	_pause_overlay.settings_open = false
	if is_instance_valid(_pause_resume_button):
		_pause_resume_button.grab_focus()


func _show_pause_settings() -> void:
	if not is_instance_valid(_pause_menu_panel) or not is_instance_valid(_pause_settings_panel):
		return
	_pause_menu_panel.visible = false
	_pause_settings_panel.visible = true
	_pause_overlay.settings_open = true
	_pause_settings_status.text = ""
	if is_instance_valid(_pause_settings_first_control):
		_pause_settings_first_control.grab_focus()


func _add_pause_setting_slider(parent: Control, label_text: String, setting_key: String, value: float) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := MENU_SKIN.style_label(Label.new(), 18, MENU_SKIN.INK, true)
	label.text = label_text
	label.custom_minimum_size = Vector2(120.0, 0.0)
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


func _pause_panel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(3)
	box.set_corner_radius_all(10)
	return box


func _apply_menu_button_art(button: Button, primary: bool = false) -> void:
	MENU_SKIN.apply_button(button, primary)


func _pause_checker_strip() -> Control:
	var strip := Control.new()
	strip.custom_minimum_size = Vector2(0.0, PAUSE_STRIP_HEIGHT)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.draw.connect(func() -> void: MENU_SKIN.draw_flag(strip, Rect2(Vector2.ZERO, strip.size), PAUSE_STRIP_HEIGHT * 0.5))
	return strip


func _add_pause_button(parent: Control, text: String, callback: Callable, primary: bool = false) -> Button:
	var button := MENU_BUTTON_SCRIPT.new() as Button
	button.text = text.to_upper()
	button.custom_minimum_size = Vector2(400.0, 58.0)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 18)
	_apply_menu_button_art(button, primary)
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


func _on_mastery_pressed() -> void:
	_left_results = true
	_set_paused(false)
	var app := get_node_or_null("/root/App")
	if app and app.has_method("start_mastery_rematch"):
		app.call("start_mastery_rematch")


func _attempt_result_commit(results: Array) -> void:
	var committed := _report_result_to_app(results)
	var mastery_mode := String(_session.get("mode", "")) == "mastery"
	_retry_button.disabled = false
	_continue_button.disabled = not committed and not mastery_mode
	_retry_button.text = "RETRY" if committed else "RETRY SAVE"
	var app := get_node_or_null("/root/App")
	var mastery_available := committed and app and app.has_method("can_start_mastery_rematch") and bool(app.call("can_start_mastery_rematch"))
	_mastery_button.visible = mastery_available
	_mastery_button.disabled = not mastery_available
	_layout_result_actions(mastery_available)
	_retry_button.focus_neighbor_right = _retry_button.get_path_to(_mastery_button if mastery_available else _continue_button)
	_continue_button.focus_neighbor_left = _continue_button.get_path_to(_mastery_button if mastery_available else _retry_button)
	if mastery_available:
		_mastery_button.focus_neighbor_left = _mastery_button.get_path_to(_retry_button)
		_mastery_button.focus_neighbor_right = _mastery_button.get_path_to(_continue_button)
	_update_results(results)
	if committed:
		_continue_button.grab_focus()
	else:
		_retry_button.grab_focus()


func _layout_result_actions(mastery_available: bool) -> void:
	if mastery_available:
		_retry_button.position.x = 26.0
		_mastery_button.position.x = 225.0
		_continue_button.position.x = 424.0
	else:
		_retry_button.position.x = 126.0
		_continue_button.position.x = 324.0


func _report_result_to_app(results: Array) -> bool:
	_save_error = ""
	var app := get_node_or_null("/root/App")
	if app == null or _session.is_empty() or not app.has_method("report_race_result"):
		return true
	for result: Dictionary in results:
		if result.get("vehicle") == _player_vehicle:
			var finish_time := float(result["time"])
			var performance := {
				"best_lap": 0.0 if is_inf(_best_lap) else _best_lap,
				"ghost_samples": PERSONAL_GHOST_SCRIPT.finalize_samples(_ghost_samples, finish_time),
			}
			var committed := bool(app.call("report_race_result", int(result["position"]), finish_time, results, bool(result.get("dnf", false)), performance))
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
