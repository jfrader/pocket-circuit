extends Node

const BOOT_SCENE := "res://scenes/boot/boot.tscn"
const RACE_SCENE := "res://scenes/race/prototype_race.tscn"
const CATALOG := preload("res://data/championship/catalog.gd")
const SAVE_STORE_SCRIPT := preload("res://scripts/persistence/save_store.gd")
const CIRCUIT_IDENTITIES := preload("res://scripts/progression/championship_circuit_identity.gd")
const MASTERY := preload("res://scripts/progression/mastery_run.gd")
const PERSONAL_GHOST := preload("res://scripts/race/personal_ghost.gd")
const RACE_PREPARATION := preload("res://scripts/race/race_preparation.gd")
const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const GENERATED_CIRCUITS := preload("res://scripts/race/generated_circuit_identity.gd")
const GENERATED_RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const CIRCUIT_LIBRARY := preload("res://scripts/persistence/circuit_library.gd")
const CIRCUIT_PREVIEW_QUEUE := preload("res://scripts/race/circuit_preview_queue.gd")
const RACE_ASSET_PRELOADER := preload("res://scripts/race/race_asset_preloader.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const DRIVER_ROSTER := preload("res://scripts/progression/driver_roster.gd")
const DRIVER_DIRECTORY := preload("res://scripts/progression/driver_directory.gd")
const RUN_SESSION := preload("res://scripts/progression/run_session.gd")
## Every race fields the player plus three opponents.
const ROSTER_SIZE := 3
const RUN_ACT_RIVAL_DIFFICULTY := "clockwork"
const RUN_SEED_MAX := 0x7FFFFFFF
## A run race finished this far down the field (or not at all) costs wear.
const RUN_CRASH_FINISH_POSITION := 3
const RUN_CRASH_SEVERITY := 0.6
const LOADING_FRAME_BUDGET_USEC := 50_000

signal joypad_connection_changed(connected: bool)

var current_race_session: Dictionary = {}
## Active roguelike run, restored from the save on boot (null when there is none).
var _current_run_session: RunSession = null
var last_run_error: String = ""
## Why the run is not on disk yet ("" once a run save lands); the board shows it.
var run_save_error := ""
var _quick_roster: Dictionary = {}


## The championship's saved roster. An older save has none, so it falls back to a
## roster derived from that championship's own circuit seed: stable, never written
## from a read path, and different for every championship.
func _championship_roster() -> Dictionary:
	var vehicle_ids: Array = CATALOG.championship_vehicle_ids()
	var stored := DRIVER_ROSTER.normalize(_save_data.get("driver_roster"), vehicle_ids, ROSTER_SIZE)
	if not stored.is_empty():
		return stored
	var championship: Dictionary = _save_data.get("championship_circuit", {})
	var seed := int(championship.get("seed", 0))
	if seed <= 0:
		seed = DRIVER_ROSTER.MAX_SEED
	return DRIVER_ROSTER.create(seed, vehicle_ids, ROSTER_SIZE)


## A quick race rolls a fresh lineup each time it starts; a retry reuses the
## session's own event, so its lineup is kept.
func _roll_quick_roster() -> void:
	_quick_roster = DRIVER_ROSTER.create(
		_random_seed(DRIVER_ROSTER.MAX_SEED),
		CATALOG.quick_race_vehicle_ids(),
		ROSTER_SIZE
	)


## Generated opponents replace the shipped cast for the current race or campaign.
static func _roster_ids(roster: Dictionary) -> Array:
	var ids: Array = []
	for opponent: Variant in roster.get("opponents", []):
		if opponent is Dictionary:
			ids.append(String((opponent as Dictionary).get("id", "")))
	return ids


## Generated opponents replace the shipped cast for the current race or campaign.
## Race starts install explicitly, because the session is assigned after the
## event is built; screen syncs can use the session's own mode.
func _install_roster_for(mode: String) -> void:
	var roster := _quick_roster if mode == "quick" else _championship_roster()
	DRIVER_DIRECTORY.install_opponents(roster.get("opponents", []))


func _install_active_roster() -> void:
	var mode := String(current_race_session.get("mode", ""))
	_install_roster_for("quick" if mode == "strip" else mode)


## Points the event at its roster slots and names the rival in the story. Slots
## are derived from the roster and the event, so a retry faces the same drivers.
func _event_with_roster(event: Dictionary, roster: Dictionary) -> Dictionary:
	var opponents: Array = roster.get("opponents", [])
	if event.is_empty() or opponents.is_empty():
		return event
	var count := clampi(int(event.get("opponent_count", opponents.size())), 0, ROSTER_SIZE)
	var updated := event.duplicate(true)
	var ids: Array = []
	var lead := ""
	if count == 1:
		# A duel picks one rival per act, so acts do not all face the same driver.
		var slot := (maxi(1, int(event.get("act", 1))) - 1) % opponents.size()
		ids.append(String((opponents[slot] as Dictionary)["id"]))
		lead = String((opponents[slot] as Dictionary)["name"])
	else:
		for index in mini(count, opponents.size()):
			ids.append(String((opponents[index] as Dictionary)["id"]))
		lead = String((opponents[0] as Dictionary)["name"])
	updated["opponents"] = ids
	updated["opponent_count"] = ids.size()
	for key: String in ["story", "rival_line"]:
		var text := String(updated.get(key, ""))
		if text.contains(CATALOG.RIVAL_TOKEN):
			updated[key] = text.replace(CATALOG.RIVAL_TOKEN, lead)
	return updated
var reduced_camera_shake := false
var reduced_motion := false
var audio_director: Node

var _save_store: SaveStore
var _save_data: Dictionary
var _shell: CanvasLayer
var _shell_script: Script
var _loading_script: Script
var _last_scene: Node
var _destination := "title"
var _last_result_summary: Dictionary = {}
var _test_mode := false
var _last_save_error := ""
var _transitioning_to_race := false
var _loading_screen: CanvasLayer
var _loading_cancelled := false
var _loading_failed := false
var _last_loading_frame_yield := 0
var loading_metrics: Dictionary = {}
var _mastery_calibration_queue: Array[String] = []
var _mastery_calibration_active := false
var _mastery_calibration_worker: Node
var _mastery_calibration_failures: Dictionary = {}
var _circuit_preview_queue: Node
var _race_asset_preloader: Node


func _enter_tree() -> void:
	_ensure_joypad_button(&"ui_accept", JOY_BUTTON_A)
	_ensure_joypad_button(&"ui_cancel", JOY_BUTTON_B)
	_ensure_key(&"pause", KEY_ESCAPE)
	_ensure_joypad_button(&"pause", JOY_BUTTON_START)

	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# Emit initial state once at startup if a pad is already present (Godot does not
	# emit joy_connection_changed for pads that were connected before the game launched).
	if not Input.get_connected_joypads().is_empty():
		joypad_connection_changed.emit(true)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_test_mode = "--script" in OS.get_cmdline_args() or "--release-smoke" in OS.get_cmdline_user_args()
	# Autoload parsing also happens before a clean editor import has created
	# image/audio resources. Load presentation scripts only when the game runs.
	_shell_script = load("res://scripts/ui/app_shell.gd") as Script
	_loading_script = load("res://scripts/ui/race_loading_screen.gd") as Script
	var audio_script := load("res://scripts/audio/audio_director.gd") as Script
	audio_director = audio_script.new()
	audio_director.name = "AudioDirector"
	add_child(audio_director)
	_circuit_preview_queue = CIRCUIT_PREVIEW_QUEUE.new()
	_circuit_preview_queue.name = "CircuitPreviewQueue"
	add_child(_circuit_preview_queue)
	_race_asset_preloader = RACE_ASSET_PRELOADER.new()
	_race_asset_preloader.name = "RaceAssetPreloader"
	add_child(_race_asset_preloader)
	_race_asset_preloader.call("start", self)
	var active_save_path: String = "user://tests/pocket_circuit_app_autoload_test.json" if _test_mode else SaveStore.DEFAULT_PATH
	_save_store = SAVE_STORE_SCRIPT.new(active_save_path)
	if _test_mode:
		_save_store.remove_save()
	_save_data = _save_store.load_data()
	var stored_run: Variant = _save_data.get("current_run", {})
	if stored_run is Dictionary and not (stored_run as Dictionary).is_empty():
		_current_run_session = RUN_SESSION.deserialize(stored_run as Dictionary)
		if _current_run_session == null:
			_save_data["current_run"] = {}
	_install_held_vehicles()
	_settle_race_in_flight()
	reduced_camera_shake = bool(_save_data["reduced_camera_shake"])
	reduced_motion = bool(_save_data["reduced_motion"])
	_apply_settings()
	_install_player_avatar()
	_install_active_roster()
	if bool(_save_data["first_run"]):
		_save_data["first_run"] = false
		if not _test_mode:
			_save()
	call_deferred("_sync_current_scene")
	if "--release-smoke" in OS.get_cmdline_user_args():
		call_deferred("_run_release_smoke")


func _exit_tree() -> void:
	if Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_on_joy_connection_changed)
	# The prewarm builds the room off-tree; free it if the app is torn down mid-build.
	if _prewarm_room_root != null and is_instance_valid(_prewarm_room_root):
		_prewarm_room_root.free()
	_prewarm_room_root = null
	if _test_mode and _save_store:
		_save_store.remove_save()


func _process(_delta: float) -> void:
	var scene := get_tree().current_scene
	if scene != _last_scene:
		_sync_current_scene()


func _unhandled_input(event: InputEvent) -> void:
	if _transitioning_to_race:
		return
	if _shell == null or not _shell.visible or get_tree().current_scene == null:
		return
	if event.is_action_pressed("ui_cancel"):
		_shell.call("go_back")
		get_viewport().set_input_as_handled()


func has_championship_progress() -> bool:
	return CATALOG.has_progress(_save_data)


func is_save_read_only() -> bool:
	return _save_store != null and _save_store.is_read_only


func get_save_recovery_message() -> String:
	return _save_store.recovery_message if _save_store != null else ""


func get_last_save_error() -> String:
	return _last_save_error


func get_save_data() -> Dictionary:
	return _save_data.duplicate(true)


func get_championship_event(event_id: String) -> Dictionary:
	return _event_with_roster(CATALOG.get_event(event_id), _championship_roster())


func has_joypad() -> bool:
	# Returns true if at least one joypad is currently connected.
	return not Input.get_connected_joypads().is_empty()


## The player drives one cast slot; only its portrait seed is customizable.
func get_player_avatar_seed() -> int:
	return int(_save_data.get("player_avatar_seed", SAVE_STORE_SCRIPT.PLAYER_AVATAR_DEFAULT_SEED))


## Shows a candidate portrait without writing it to the save.
func preview_player_avatar(seed: int) -> void:
	var player_id := CATALOG.player_driver_id()
	if player_id.is_empty():
		return
	IDENTITIES.set_avatar_seed_override(player_id, _bounded_avatar_seed(seed), _player_cast_avatar_seed(player_id))


func save_player_avatar(seed: int) -> bool:
	if is_save_read_only():
		return false
	var candidate := _save_data.duplicate(true)
	candidate["player_avatar_seed"] = _bounded_avatar_seed(seed)
	if candidate == _save_data:
		_install_player_avatar()
		return true
	if not _save_candidate(candidate):
		return false
	_save_data = candidate
	_install_player_avatar()
	return true


func random_player_avatar_seed() -> int:
	return _random_seed(SAVE_STORE_SCRIPT.PLAYER_AVATAR_MAX_SEED)


## Mirrors the save store's rule so an accepted seed always round-trips exactly.
func _bounded_avatar_seed(seed: int) -> int:
	if seed < 0 or seed > SAVE_STORE_SCRIPT.PLAYER_AVATAR_MAX_SEED:
		return get_player_avatar_seed()
	return seed


func _player_cast_avatar_seed(player_id: String) -> int:
	var art: Dictionary = CATALOG.get_driver(player_id).get("avatar_art", {})
	return int(art.get("seed", SAVE_STORE_SCRIPT.PLAYER_AVATAR_DEFAULT_SEED))


func _install_player_avatar() -> void:
	var player_id := CATALOG.player_driver_id()
	if player_id.is_empty():
		return
	IDENTITIES.set_avatar_seed_override(player_id, get_player_avatar_seed(), _player_cast_avatar_seed(player_id))


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
		"engine_volume": _save_data["engine_volume"],
		"tyre_volume": _save_data["tyre_volume"],
		"fullscreen": _save_data["fullscreen"],
		"reduced_camera_shake": _save_data["reduced_camera_shake"],
		"reduced_motion": _save_data["reduced_motion"],
		"player_avatar_seed": get_player_avatar_seed(),
		"first_run": false,
		"mastery_records": _save_data.get("mastery_records", []).duplicate(true),
		"personal_ghosts": _save_data.get("personal_ghosts", []).duplicate(true),
		"circuit_history": _save_data.get("circuit_history", []).duplicate(true),
		"favorite_circuits": _save_data.get("favorite_circuits", []).duplicate(true),
		"garage_cars": _save_data.get("garage_cars", []).duplicate(true),
		"current_run": _save_data.get("current_run", {}).duplicate(true),
	}
	var candidate := _save_store.default_data()
	for key: String in preserved_settings:
		candidate[key] = preserved_settings[key]
	candidate["championship_started"] = true
	candidate["championship_circuit"] = CIRCUIT_IDENTITIES.create_championship(_random_seed(CIRCUIT_IDENTITIES.MAX_SEED))
	candidate["driver_roster"] = DRIVER_ROSTER.create(
		_random_seed(DRIVER_ROSTER.MAX_SEED),
		CATALOG.championship_vehicle_ids(),
		ROSTER_SIZE
	)
	if not _save_candidate(candidate):
		_show_save_error(
			"Championship not started",
			Callable(self, "confirm_new_championship"),
			Callable(_shell, "show_title")
		)
		return false
	_save_data = candidate
	_install_active_roster()
	_shell.call("show_map")
	return true


func continue_championship() -> void:
	if CATALOG.is_ending_pending(_save_data):
		_shell.call("show_ending")
	else:
		_shell.call("show_map")


func finish_ending(destination: String = "map") -> bool:
	if not destination in ["map", "title"]:
		return false
	var candidate := _save_data.duplicate(true)
	if CATALOG.is_ending_pending(candidate):
		candidate["ending_seen"] = true
		if not _save_candidate(candidate):
			_show_save_error(
				"Championship ending not saved",
				Callable(self, "finish_ending").bind(destination),
				Callable(_shell, "show_ending")
			)
			return false
		_save_data = candidate
	if destination == "map":
		_shell.call("show_map")
	else:
		_shell.call("show_title")
	return true


func open_quick_race() -> void:
	_shell.call("show_quick_race")


func open_quick_strip() -> void:
	_shell.call("show_quick_strip")


func open_discovery() -> void:
	_shell.call("show_discovery")


func start_race(event_id: String, vehicle_id: String, quick_race: bool = false, mastery_run: bool = false) -> void:
	if _transitioning_to_race:
		return
	var event := CATALOG.get_event(event_id)
	if event.is_empty():
		return
	if not quick_race and not CATALOG.is_event_unlocked(event_id, _save_data):
		return
	if mastery_run and not event_id in _save_data.get("completed_events", []):
		return
	var event_theme := StringName(event.get("theme", "kitchen"))
	if event_theme in [&"kitchen", &"workshop", &"office"]:
		if quick_race:
			var circuit_draw := random_circuit_seed(event_theme)
			var generated_identity := GENERATED_CIRCUITS.create(
				event_theme,
				StringName(circuit_draw.get("room", "classic")),
				int(circuit_draw.get("seed", 0)),
				bool(event.get("reverse", false)),
				int(event.get("act", 0))
			)
			event = _event_with_generated_identity(event, generated_identity)
		else:
			var identity := get_championship_circuit_identity(event_id)
			if identity.is_empty():
				return
			event = CIRCUIT_IDENTITIES.apply_to_event(event, identity)
	if not quick_race and not vehicle_id in _save_data["unlocked_vehicles"]:
		vehicle_id = "rustbug"
	if quick_race:
		_roll_quick_roster()
	_install_roster_for("quick" if quick_race else "")
	if not mastery_run:
		event = _event_with_roster(event, _quick_roster if quick_race else _championship_roster())
	var mastery_context := {}
	if mastery_run:
		event = _mastery_solo_event(event)
		var mastery_metrics := MASTERY.metrics_for_event(_save_data.get("mastery_circuit_metrics"), event)
		if mastery_metrics.is_empty():
			_queue_mastery_calibration(event_id)
			return
		mastery_context = MASTERY.create_context(event, vehicle_id, mastery_metrics)
		if (mastery_context.get("identity", {}) as Dictionary).is_empty() or (mastery_context.get("targets", {}) as Dictionary).is_empty():
			return
	var candidate := _save_data.duplicate(true)
	candidate["selected_vehicle"] = vehicle_id
	if quick_race and event.has("generated_circuit_identity"):
		candidate["circuit_history"] = CIRCUIT_LIBRARY.add_recent(candidate.get("circuit_history"), event["generated_circuit_identity"])
	if candidate != _save_data:
		if _save_candidate(candidate):
			_save_data = candidate
		elif not quick_race:
			_show_save_error(
				"Vehicle choice not saved",
				Callable(self, "start_race").bind(event_id, vehicle_id, quick_race, mastery_run),
				Callable(_shell, "show_vehicle_select").bind(event_id, quick_race)
			)
			return
	current_race_session = {
		"mode": "quick" if quick_race else ("mastery" if mastery_run else "championship"),
		"event_id": event_id,
		"event": event,
		"vehicle_id": vehicle_id,
		"difficulty": CATALOG.race_difficulty(event, quick_race, mastery_run, String(_save_data["difficulty"])),
		"result_committed": false,
	}
	if mastery_run:
		var mastery_identity: Dictionary = mastery_context["identity"]
		current_race_session["mastery_identity"] = mastery_identity
		current_race_session["mastery_targets"] = (mastery_context["targets"] as Dictionary).duplicate(true)
		current_race_session["best_ghost"] = PERSONAL_GHOST.compatible_best(_save_data.get("personal_ghosts"), mastery_identity)
	_begin_race_transition(vehicle_id)


func start_mastery_run(event_id: String, vehicle_id: String) -> void:
	start_race(event_id, vehicle_id, false, true)


func get_mastery_state(event_id: String, vehicle_id: String = "") -> Dictionary:
	var event := CATALOG.get_event(event_id)
	var available: bool = not event.is_empty() and event_id in _save_data.get("completed_events", [])
	if event.is_empty():
		return {"available": false, "identity": {}, "record": {}, "targets": {}}
	var selected := vehicle_id if not vehicle_id.is_empty() else String(_save_data.get("selected_vehicle", "rustbug"))
	if not selected in _save_data.get("unlocked_vehicles", ["rustbug"]):
		selected = "rustbug"
	var identity := get_championship_circuit_identity(event_id)
	if identity.is_empty():
		return {"available": false, "identity": {}, "record": {}, "targets": {}}
	event = CIRCUIT_IDENTITIES.apply_to_event(event, identity)
	var metrics := MASTERY.metrics_for_event(_save_data.get("mastery_circuit_metrics"), event)
	if metrics.is_empty():
		var calibration_failed := available and _mastery_calibration_failures.has(event_id)
		if available and not calibration_failed:
			_queue_mastery_calibration(event_id)
		return {
			"available": false,
			"calibrating": available and not calibration_failed,
			"calibration_failed": calibration_failed,
			"identity": {},
			"record": {},
			"targets": {},
			"vehicle_id": selected,
			"ghost_available": false,
		}
	var context := MASTERY.create_context(event, selected, metrics)
	var mastery_identity: Dictionary = context["identity"]
	var state := MASTERY.state(_save_data.get("mastery_records"), mastery_identity, context["targets"])
	state["available"] = available and not mastery_identity.is_empty()
	state["calibrating"] = false
	state["calibration_failed"] = false
	state["vehicle_id"] = selected
	state["ghost_available"] = not PERSONAL_GHOST.compatible_best(_save_data.get("personal_ghosts"), mastery_identity).is_empty()
	return state


func record_prepared_mastery_metrics(event: Dictionary, prepared_metrics: Dictionary) -> bool:
	var metrics := MASTERY.circuit_metrics_from_prepared(event, prepared_metrics)
	if metrics.is_empty():
		return false
	current_race_session["mastery_circuit_metrics"] = metrics.duplicate(true)
	return true


func retry_mastery_calibration(event_id: String) -> void:
	_queue_mastery_calibration(event_id)


func _queue_mastery_calibration(event_id: String) -> void:
	if event_id.is_empty() or event_id in _mastery_calibration_queue:
		return
	if _mastery_calibration_active and String(get_meta("mastery_calibration_event", "")) == event_id:
		return
	_mastery_calibration_failures.erase(event_id)
	_mastery_calibration_queue.append(event_id)
	call_deferred("_run_next_mastery_calibration")


func _run_next_mastery_calibration() -> void:
	if _mastery_calibration_active or _mastery_calibration_queue.is_empty():
		return
	_mastery_calibration_active = true
	var event_id: String = _mastery_calibration_queue.pop_front()
	set_meta("mastery_calibration_event", event_id)
	var event := CATALOG.get_event(event_id)
	var circuit_identity := get_championship_circuit_identity(event_id)
	if event_id in _save_data.get("completed_events", []) and not event.is_empty() and not circuit_identity.is_empty():
		event = CIRCUIT_IDENTITIES.apply_to_event(event, circuit_identity)
		var worker := RACE_PREPARATION.new()
		_mastery_calibration_worker = worker
		add_child(worker)
		var metrics: Dictionary = await worker.run_data_job(MASTERY.prepare_circuit_metrics.bind(event))
		_mastery_calibration_worker.queue_free()
		_mastery_calibration_worker = null
		if _store_mastery_circuit_metrics(event, metrics):
			_mastery_calibration_failures.erase(event_id)
		else:
			_mastery_calibration_failures[event_id] = true
		if is_instance_valid(_shell) and _shell.has_method("refresh_mastery_calibration"):
			_shell.call("refresh_mastery_calibration", event_id)
	remove_meta("mastery_calibration_event")
	_mastery_calibration_active = false
	if not _mastery_calibration_queue.is_empty():
		call_deferred("_run_next_mastery_calibration")


func _store_mastery_circuit_metrics(event: Dictionary, metrics_value: Variant) -> bool:
	var metrics := MASTERY.normalize_circuit_metrics(metrics_value, event)
	if metrics.is_empty():
		return false
	var current_event := CATALOG.get_event(String(event.get("id", "")))
	var current_identity := get_championship_circuit_identity(String(event.get("id", "")))
	if current_event.is_empty() or current_identity.is_empty():
		return false
	current_event = CIRCUIT_IDENTITIES.apply_to_event(current_event, current_identity)
	if MASTERY.circuit_metrics_key_for_event(current_event) != MASTERY.circuit_metrics_key_for_event(event):
		return false
	var key := MASTERY.circuit_metrics_key_for_event(event)
	var metrics_map: Dictionary = _save_data.get("mastery_circuit_metrics", {}).duplicate(true)
	if metrics_map.get(key) == metrics:
		return true
	metrics_map[key] = metrics.duplicate(true)
	var candidate := _save_data.duplicate(true)
	candidate["mastery_circuit_metrics"] = metrics_map
	if not _save_candidate(candidate):
		return false
	_save_data = candidate
	return true


func random_circuit_seed(theme: StringName) -> Dictionary:
	var seed_value := _random_seed(999999)
	return {"theme": String(theme), "room": String(circuit_room_for_seed(seed_value)), "seed": seed_value}


func get_championship_circuit_identity(event_id: String) -> Dictionary:
	var championship: Variant = _save_data.get("championship_circuit")
	return CIRCUIT_IDENTITIES.event_identity(championship, event_id) if championship is Dictionary else {}


func circuit_room_for_seed(seed: int) -> StringName:
	return GENERATED_CIRCUITS.room_for_route_seed(seed)


func _random_seed(maximum: int) -> int:
	var random := RandomNumberGenerator.new()
	random.randomize()
	return random.randi_range(0, maximum)


func generated_circuit_identity(theme: StringName, room: StringName, seed: int, reverse: bool = false, length_tier: String = "standard", route_shape: String = "circuit") -> Dictionary:
	return GENERATED_CIRCUITS.create(theme, room, seed, reverse, 0, "", "", {}, length_tier, GENERATED_CIRCUITS.DEFAULT_ROAD_WIDTH, route_shape)



## Off-tree room being built by the prewarm; freed on app teardown if a quit
## happens mid-build.
var _prewarm_room_root: Node = null
## Circuits waiting to be prewarmed, one job at a time, and the keys queued or running.
var _prewarm_queue: Array[Dictionary] = []
var _prewarm_keys: Dictionary = {}
var _prewarm_running := false


## Fire-and-forget pre-generation for a generated circuit event while the player
## is on a preview or results screen that has idle time. The prepared layout
## is computed on a NORMAL data job; the continuation then also warms scenery
## outlines (on data jobs), the assembled room (off-tree via assemble_runtime
## + pack), and per-vehicle motion plans (where reproducible from the event).
## All steps yield cooperatively. Failures are ignored; the race path will
## still do any missing work on demand.
## Queues a generated circuit to be prepared ahead of its race. Jobs run one
## at a time (they share the off-tree room slot) and each circuit is queued at
## most once until it lands in the cache.
func prewarm_generated_circuit(event: Dictionary) -> void:
	if String(event.get("circuit", "")) != "generated":
		return
	var key := TRACK_BUILDER.generated_circuit_cache_key(event)
	if not key.is_empty() and (_prewarm_keys.has(key) or not TRACK_BUILDER.cached_prepared(key).is_empty()):
		return
	if not key.is_empty():
		_prewarm_keys[key] = true
	_prewarm_queue.append({
		"theme": StringName(event.get("theme", "kitchen")),
		"room": StringName(event.get("room", "classic")),
		"seed": int(event.get("seed", 0)),
		"options": TRACK_BUILDER.generated_circuit_options(event),
		"key": key,
	})
	if not _prewarm_running:
		_prewarm_running = true
		call_deferred("_run_prewarm_queue")


## Warms the circuits of the race-type stops the run board offers right now.
func prewarm_run_stops() -> void:
	if _current_run_session == null:
		return
	for stop: Dictionary in _current_run_session.available_nodes():
		if String(stop.get("type", "")) in RunSession.RACE_NODE_TYPES:
			var circuit := _run_circuit(String(stop["id"]))
			if not circuit.is_empty():
				prewarm_generated_circuit(GENERATED_CIRCUITS.apply_to_event(circuit))


func _run_prewarm_queue() -> void:
	while not _prewarm_queue.is_empty():
		var job: Dictionary = _prewarm_queue.pop_front()
		var key := String(job["key"])
		if key.is_empty() or TRACK_BUILDER.cached_prepared(key).is_empty():
			var preparation := RACE_PREPARATION.new()
			add_child(preparation)
			await _execute_prewarm_job(preparation, job["theme"], job["room"], int(job["seed"]), job["options"], key)
		_prewarm_keys.erase(key)
	_prewarm_running = false


## A race that starts loading takes the CPU: circuits still waiting in the
## prewarm queue are dropped (the job already running finishes).
func _drop_queued_prewarms() -> void:
	for job: Dictionary in _prewarm_queue:
		_prewarm_keys.erase(String(job["key"]))
	_prewarm_queue.clear()


func _execute_prewarm_job(preparation: Node, theme: StringName, room: StringName, seed: int, options: Dictionary, key: String) -> void:
	var prepared: Dictionary = await preparation.run_data_job(
		TRACK_BUILDER.prepare_layout.bind(theme, room, seed, options),
		Thread.PRIORITY_NORMAL
	)
	if not prepared.is_empty() and not key.is_empty():
		TRACK_BUILDER.store_prepared(key, prepared)
		await _warm_scenery_outlines(preparation, prepared)
		await _warm_room_if_missing(key, prepared)
		# Motions warmed via separate RaceAssetPreloader pool + roster hooks (see prewarm_championship_event).
	if preparation:
		preparation.queue_free()


func prewarm_championship_event(event_id: String) -> void:
	if event_id.is_empty():
		return
	var identity := get_championship_circuit_identity(event_id)
	if identity.is_empty():
		return
	var event := get_championship_event(event_id)
	event = CIRCUIT_IDENTITIES.apply_to_event(event, identity)
	prewarm_generated_circuit(event)
	# Prewarm the exact roster's car motion looks too (opponents resolve to plain vehicle keys;
	# we also include the currently-selected vehicle + rae livery so the race the player
	# actually enters is warm). Uses the background preloader so work is low-pri data job,
	# yields in menu idle time, idempotent if already cached from the full pool.
	var roster := _championship_roster()
	var looks: Array = []
	for o: Variant in roster.get("opponents", []):
		if o is Dictionary:
			var did := String((o as Dictionary).get("id", ""))
			var vid := String((o as Dictionary).get("vehicle_id", "rustbug"))
			var k := IDENTITIES.resolve_visual_key(vid, did)
			looks.append(k)
	var sel := String(_save_data.get("selected_vehicle", "rustbug"))
	var pk := IDENTITIES.resolve_visual_key(sel, "rae")
	looks.append(pk)
	if is_instance_valid(_race_asset_preloader) and _race_asset_preloader.has_method("prewarm_additional"):
		_race_asset_preloader.call("prewarm_additional", looks)


## The field is only known once the player commits, so warm its looks now: the
## renders overlap the loading screen and land as cache hits in section 2.
## Mirrors PrototypeRace._build_field_racers_for_preparation so the keys (and
## any cosmetic collision shifts) match exactly.
func _prewarm_roster_motions(vehicle_id: String, event: Dictionary) -> void:
	if not is_instance_valid(_race_asset_preloader) or not _race_asset_preloader.has_method("prewarm_roster"):
		return
	var racers: Array[Dictionary] = [{"vehicle_id": vehicle_id, "driver_id": "rae", "slot": 0}]
	var opponents: Array = event.get("opponents", [])
	var count := clampi(int(event.get("opponent_count", opponents.size())), 0, 3)
	for i in mini(opponents.size(), count):
		var did := String(opponents[i])
		var record := CATALOG.get_driver(did)
		racers.append({"vehicle_id": String(record.get("vehicle_id", "rustbug")), "driver_id": did, "slot": i + 1})
	var looks: Array = []
	for k: Variant in IDENTITIES.resolve_field_visual_keys(racers).values():
		looks.append(String(k))
	_race_asset_preloader.call("prewarm_roster", looks)


## Safe, no-tree work: mirror the race path's outline prep exactly, on data jobs,
## with yields between textures.
func _warm_scenery_outlines(preparation: Node, prepared: Dictionary) -> void:
	if prepared.is_empty():
		return
	var spec: Dictionary = prepared.get("spec", {})
	for texture_path: String in TRACK_BUILDER.preparation_texture_paths(spec):
		if TRACK_BUILDER.has_prepared_outline_path(texture_path):
			continue
		if not ResourceLoader.exists(texture_path):
			continue
		var texture := load(texture_path) as Texture2D
		if texture != null and not TRACK_BUILDER.has_prepared_outline(texture):
			var outline: Dictionary = await preparation.run_data_job(
				TRACK_BUILDER.compute_alpha_outline.bind(texture.get_image(), texture.get_width(), texture.get_height())
			)
			if not outline.is_empty():
				TRACK_BUILDER.install_prepared_outline(texture, outline)
		if preparation.get_tree():
			await preparation.get_tree().process_frame


## Room prewarm: create_layout_root + assemble_runtime can run with root not
## added to any scene tree (confirmed by build_packed usage, absence of
## get_tree/get_viewport/ready assumptions in builders beyond _ready which
## is deferred until add in race, and pack after free in build_packed).
## We set name="Track" to match the race path's override, use a yielding stage
## to spread the work, then pack+store exactly as race does. Never force-add.
func _warm_room_if_missing(key: String, prepared: Dictionary) -> void:
	if key.is_empty() or prepared.is_empty() or TRACK_BUILDER.cached_room(key) != null:
		return
	if not is_inside_tree():
		return
	var root := TRACK_BUILDER.create_layout_root(prepared)
	root.name = "Track"
	_prewarm_room_root = root
	# Yielding stage spreads the assembly (~0.3s) across frames; Callable()
	# would block one frame.
	await TRACK_BUILDER.assemble_runtime(root, prepared, _prewarm_yield_stage)
	if not is_instance_valid(root):
		_prewarm_room_root = null
		return
	if is_inside_tree():
		TRACK_BUILDER.mark_packed_scene_owners(root)
		var pscene := PackedScene.new()
		if pscene.pack(root) == OK:
			TRACK_BUILDER.store_room(key, pscene)
	root.free()
	_prewarm_room_root = null
	if get_tree():
		await get_tree().process_frame


func _prewarm_yield_stage(_phase: String) -> void:
	await get_tree().process_frame


## Motions are now prewarmed by the full-pool background warmer in RaceAssetPreloader
## (using possible_field_visual_keys) plus explicit roster looks from prewarm_championship_event.
## This covers both the late _roll_quick_roster() case and exact championship rosters.
## The race path still renders anything missing (no change to loading logic).
func _warm_motions_if_reproducible(_preparation: Node, _event: Dictionary) -> void:
	pass


func circuit_share_code(identity: Dictionary) -> Dictionary:
	return GENERATED_CIRCUITS.encode_share_code(identity)


func decode_circuit_share_code(code: String) -> Dictionary:
	return GENERATED_CIRCUITS.decode_share_code(code)


func retier_circuit_identity(identity_value: Dictionary, length_tier: String) -> Dictionary:
	if not GENERATED_RULES.LENGTH_TIERS.has(length_tier):
		return {}
	var identity := GENERATED_CIRCUITS.normalize(identity_value)
	if identity.is_empty():
		return {}
	var sub_seeds: Dictionary = identity["sub_seeds"]
	var overrides := {}
	for domain: String in ["room_composition", "material", "dressing", "obstacle", "hazard"]:
		overrides[domain] = sub_seeds[domain]
	return GENERATED_CIRCUITS.create(
		StringName(identity["theme"]),
		StringName(identity["room"]),
		int(sub_seeds["route"]),
		bool(identity["reverse"]),
		int(identity["danger_level"]),
		String(identity["material_id"]),
		String(identity["palette_id"]),
		overrides,
		length_tier,
		StringName(identity.get("road_width", GENERATED_CIRCUITS.DEFAULT_ROAD_WIDTH)),
		String(identity.get("route_shape", "circuit")),
		String(identity.get("theme_b", ""))
	)


func get_circuit_library() -> Dictionary:
	return {
		"history": CIRCUIT_LIBRARY.normalize_history(_save_data.get("circuit_history")).duplicate(true),
		"favorites": CIRCUIT_LIBRARY.normalize_favorites(_save_data.get("favorite_circuits")).duplicate(true),
	}


func set_circuit_favorite(identity_value: Dictionary, favorite: bool) -> bool:
	var identity := GENERATED_CIRCUITS.normalize(identity_value)
	if identity.is_empty():
		return false
	var candidate := _save_data.duplicate(true)
	var favorites: Variant = candidate.get("favorite_circuits")
	candidate["favorite_circuits"] = CIRCUIT_LIBRARY.add_favorite(favorites, identity) if favorite else CIRCUIT_LIBRARY.remove_favorite(favorites, String(identity["fingerprint"]))
	if candidate == _save_data:
		return true
	if not _save_candidate(candidate):
		return false
	_save_data = candidate
	return true


func prepare_circuit_preview(identity_value: Dictionary) -> Dictionary:
	var identity := GENERATED_CIRCUITS.normalize(identity_value)
	if identity.is_empty():
		return {}
	return await _circuit_preview_queue.request(identity)


func start_circuit_race(theme: StringName, room: StringName, seed: int, vehicle_id: String, reverse: bool = false, length_tier: String = "standard") -> bool:
	if _transitioning_to_race:
		return false
	if not GENERATED_RULES.LENGTH_TIERS.has(length_tier):
		return false
	var identity := GENERATED_CIRCUITS.create(theme, room, seed, reverse, 0, "", "", {}, length_tier)
	if identity.is_empty():
		_roll_quick_roster()
		_install_roster_for("quick")
		current_race_session = {
			"mode": "quick",
			"event_id": "circuit_%s_%s_%d" % [String(theme), String(room), seed],
			"event": {
				"id": "circuit_%s_%s_%d" % [String(theme), String(room), seed],
				"name": "Invalid Circuit",
				"theme": String(theme),
				"room": String(room),
				"seed": seed,
				"circuit": "generated",
				"race_format": "circuit",
				"reverse": reverse,
				"opponent_count": ROSTER_SIZE,
				"opponents": _roster_ids(_quick_roster),
			},
			"vehicle_id": vehicle_id,
			"difficulty": String(_save_data["difficulty"]),
			"result_committed": false,
		}
		_begin_race_transition(vehicle_id)
		return true
	return _start_generated_identity_race(identity, vehicle_id, "quick")


func start_strip_race(theme: StringName, room: StringName, seed: int, vehicle_id: String, reverse: bool = false, length_tier: String = "standard", theme_b: StringName = &"") -> bool:
	if _transitioning_to_race or not GENERATED_RULES.LENGTH_TIERS.has(length_tier):
		return false
	var identity := GENERATED_CIRCUITS.create(theme, room, seed, reverse, 0, "", "", {}, length_tier, GENERATED_CIRCUITS.DEFAULT_ROAD_WIDTH, "strip", theme_b)
	if identity.is_empty():
		return false
	return _start_generated_identity_race(identity, vehicle_id, "strip")


func start_discovery_race(identity_value: Dictionary, vehicle_id: String, preview_fingerprint: String = "") -> bool:
	if _transitioning_to_race or preview_fingerprint.length() != 16:
		return false
	return _start_generated_identity_race(identity_value, vehicle_id, "discovery", preview_fingerprint)


func _start_generated_identity_race(identity_value: Dictionary, vehicle_id: String, mode: String, preview_fingerprint: String = "") -> bool:
	var identity := GENERATED_CIRCUITS.normalize(identity_value)
	if identity.is_empty() or not mode in ["quick", "discovery", "strip"]:
		return false
	if mode in ["quick", "strip"]:
		_roll_quick_roster()
	_install_roster_for("quick" if mode == "strip" else mode)
	var event := _event_with_roster(
		GENERATED_CIRCUITS.apply_to_event(identity, _roster_ids(_quick_roster if mode in ["quick", "strip"] else _championship_roster())),
		_quick_roster if mode in ["quick", "strip"] else _championship_roster()
	)
	if event.is_empty():
		return false
	if mode in ["quick", "strip"]:
		event["id"] = "circuit_%s_%s_%d" % [String(identity["theme"]), String(identity["room"]), int(identity["sub_seeds"]["route"])]
	if mode == "strip":
		event["race_format"] = "strip"
		event["opponent_count"] = 1
		for rival: Dictionary in _quick_roster.get("opponents", []):
			if String(rival.get("vehicle_id", "")) != vehicle_id:
				event["opponents"] = [String(rival["id"])]
				break
		if (event.get("opponents", []) as Array).size() != 1:
			event["opponents"] = [_roster_ids(_quick_roster)[0]]
	var candidate := _save_data.duplicate(true)
	candidate["circuit_history"] = CIRCUIT_LIBRARY.add_recent(candidate.get("circuit_history"), identity)
	if mode == "strip":
		candidate["selected_vehicle"] = vehicle_id
	if candidate != _save_data:
		if is_save_read_only():
			candidate = _save_data
		elif not _save_candidate(candidate):
			if mode == "discovery":
				_show_save_error(
					"Circuit history not saved",
					Callable(self, "_start_generated_identity_race").bind(identity, vehicle_id, mode, preview_fingerprint),
					Callable(_shell, "show_discovery")
				)
				return false
			candidate = _save_data
		else:
			_save_data = candidate
	if not preview_fingerprint.is_empty():
		event["preview_fingerprint"] = preview_fingerprint
	_prewarm_roster_motions(vehicle_id, event)
	current_race_session = {
		"mode": mode,
		"event_id": event["id"],
		"event": event,
		"vehicle_id": vehicle_id,
		"difficulty": String(_save_data["difficulty"]),
		"result_committed": false,
	}
	_begin_race_transition(vehicle_id)
	return true


## The event's own opponents are replaced by roster slots afterwards, so this
## only needs a legal fallback when a caller supplies none.
func _event_with_generated_identity(base_event: Dictionary, identity_value: Dictionary) -> Dictionary:
	var fallback: Array = base_event.get("opponents", _roster_ids(_championship_roster()))
	var generated := GENERATED_CIRCUITS.apply_to_event(identity_value, fallback)
	if generated.is_empty():
		return {}
	var event := base_event.duplicate(true)
	for key: Variant in generated:
		event[key] = generated[key]
	event["id"] = "circuit_%s_%s_%d" % [String(generated["theme"]), String(generated["room"]), int(generated["seed"])]
	event["generated_circuit_identity"] = (generated["circuit_identity"] as Dictionary).duplicate(true)
	return event


func is_race_loading() -> bool:
	return _transitioning_to_race


func is_menu_visible() -> bool:
	return is_instance_valid(_shell) and _shell.visible


func race_asset_precompute_finished() -> bool:
	return is_instance_valid(_race_asset_preloader) and bool(_race_asset_preloader.call("is_finished"))


func race_asset_precompute_metrics() -> Dictionary:
	if not is_instance_valid(_race_asset_preloader):
		return {}
	return _race_asset_preloader.call("debug_metrics")


func is_race_loading_cancelled() -> bool:
	return _loading_cancelled


func set_loading_section(section: int) -> void:
	if is_instance_valid(_loading_screen):
		_loading_screen.call("set_section", section)


func loading_step(phase: String) -> void:
	if is_instance_valid(_loading_screen):
		_loading_screen.call("set_phase", phase)
	await _yield_loading_frame()


func _throttled_loading_step(phase: String) -> void:
	# Dense per-resource loops update the phase text every iteration but only
	# yield a rendered frame once the time budget is spent. This keeps the
	# loading screen responsive and cancellable without paying a full frame
	# (plus GPU sync) for every dependency or generated image.
	if is_instance_valid(_loading_screen):
		_loading_screen.call("set_phase", phase)
	if Time.get_ticks_usec() - _last_loading_frame_yield < LOADING_FRAME_BUDGET_USEC:
		return
	await _yield_loading_frame()


func _yield_loading_frame() -> void:
	_last_loading_frame_yield = Time.get_ticks_usec()
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw


func _begin_race_transition(vehicle_id: String = "") -> void:
	_transitioning_to_race = true
	_drop_queued_prewarms()
	_loading_cancelled = false
	_loading_failed = false
	get_tree().paused = false
	if is_instance_valid(_loading_screen):
		_loading_screen.queue_free()
	_loading_screen = _loading_script.new()
	_loading_screen.name = "RaceLoading"
	_loading_screen.set("reduced_motion", reduced_motion)
	_loading_screen.connect("cancel_requested", _cancel_race_loading)
	add_child(_loading_screen)
	if _shell:
		_shell.visible = false
	var previous := get_tree().current_scene
	if previous != null:
		previous.process_mode = Node.PROCESS_MODE_DISABLED
	await loading_step("Loading race resources")
	if _loading_cancelled:
		_leave_race_loading()
		return
	var resources: Dictionary = {}
	var loaded := await _load_scene_resources(RACE_SCENE, resources)
	if _loading_cancelled:
		_leave_race_loading()
		return
	if not loaded:
		fail_race_loading("Race resources could not be loaded")
		return
	var packed := resources.get(RACE_SCENE) as PackedScene
	# Synthesize this car's engine voice and crash/boost one-shots behind the
	# loading screen; the race scene would otherwise pay for them on its first
	# live frame.
	await loading_step("Tuning the engine")
	if _loading_cancelled:
		_leave_race_loading()
		return
	if is_instance_valid(audio_director):
		await audio_director.call("warm_vehicle_audio", vehicle_id, loading_step.bind("Tuning the engine"))
		for opponent_id in _opponent_audio_vehicle_ids():
			if _loading_cancelled:
				_leave_race_loading()
				return
			await loading_step("Tuning the engine")
			await audio_director.call("warm_vehicle_audio", opponent_id, loading_step.bind("Tuning the engine"))
	await loading_step("Opening the circuit")
	if _loading_cancelled:
		_leave_race_loading()
		return
	if packed == null or get_tree().change_scene_to_packed(packed) != OK:
		fail_race_loading("The race scene could not be opened")


func _opponent_audio_vehicle_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	if String(current_race_session.get("mode", "")) == "mastery":
		return ids
	var event: Dictionary = current_race_session.get("event", {})
	var opponent_ids: Array = event.get("opponents", [])
	var count := clampi(int(event.get("opponent_count", opponent_ids.size())), 0, 3)
	for index in mini(opponent_ids.size(), count):
		var driver: Dictionary = CATALOG.get_driver(String(opponent_ids[index]))
		var vehicle_id := String(driver.get("vehicle_id", ""))
		if vehicle_id.is_empty() or vehicle_id in ids:
			continue
		ids.append(vehicle_id)
	return ids


func _load_scene_resources(path: String, resources: Dictionary) -> bool:
	if _loading_cancelled:
		return false
	if resources.has(path):
		return true
	# Yield to the loading screen on a time budget (rather than once per
	# dependency) so it stays responsive and can cancel without paying a
	# rendered frame + GPU sync for every resource.
	await _throttled_loading_step("Loading race resources")
	if _loading_cancelled:
		return false
	resources[path] = null
	var scripts: Array[String] = []
	var assets: Array[String] = []
	for dependency in ResourceLoader.get_dependencies(path):
		var resource_path := String(dependency).split("::")[-1]
		if resource_path.get_extension() == "gd":
			scripts.append(resource_path)
		else:
			assets.append(resource_path)
	assets.append_array(scripts)
	for dependency: String in assets:
		if not await _load_scene_resources(dependency, resources):
			return false
	# Scene scripts can preload textures. Keep their compilation and GPU resource
	# creation on the main thread; the throttled yield above covers responsiveness
	# while `change_scene_to_packed`'s own frame yield handles the final GPU sync.
	resources[path] = load(path)
	return resources[path] != null


func complete_race_loading() -> bool:
	if _loading_cancelled:
		_leave_race_loading()
		return false
	if is_instance_valid(_loading_screen):
		loading_metrics = _loading_screen.call("metrics")
		_loading_screen.queue_free()
	_loading_screen = null
	_transitioning_to_race = false
	return true


func fail_race_loading(message: String) -> void:
	if _loading_cancelled:
		_leave_race_loading()
		return
	_loading_failed = true
	if is_instance_valid(_loading_screen):
		_loading_screen.call("fail", message)


func _cancel_race_loading() -> void:
	if not _transitioning_to_race:
		return
	_loading_cancelled = true
	if _loading_failed:
		_leave_race_loading()
	elif is_instance_valid(_loading_screen):
		_loading_screen.call("cancel")


func _leave_race_loading() -> void:
	if is_instance_valid(_loading_screen):
		_loading_screen.queue_free()
	_loading_screen = null
	_transitioning_to_race = false
	_loading_failed = false
	var mode := String(current_race_session.get("mode", "quick"))
	_destination = "run_board" if mode == "run" else ("discovery" if mode == "discovery" else ("title" if mode == "quick" else "map"))
	current_race_session.clear()
	get_tree().change_scene_to_file(BOOT_SCENE)


func report_race_result(player_position: int, total_time: float, results: Array, player_dnf: bool = false, performance: Dictionary = {}) -> bool:
	if current_race_session.is_empty():
		return false
	if bool(current_race_session.get("result_committed", false)):
		return true
	var event: Dictionary = current_race_session.get("event", {})
	var racer_count := _field_size(event)
	current_race_session["result"] = {
		"position": clampi(player_position, 1, racer_count),
		"time": maxf(0.0, total_time),
		"results": results,
		"dnf": player_dnf,
	}
	var mode := String(current_race_session["mode"])
	if mode in ["quick", "discovery"]:
		current_race_session["result_committed"] = true
		current_race_session.erase("save_error")
		return true

	if mode == "run":
		var res: Dictionary = current_race_session.get("result", {}) as Dictionary
		var pos: int = int(res.get("position", 4))
		var dnf_flag: bool = bool(res.get("dnf", false))
		var node_id: String = String(current_race_session.get("run_node_id", ""))
		_commit_run_result(node_id, pos, dnf_flag, racer_count)
		current_race_session["result_summary"] = {
			"run": true,
			"position": pos,
			"node_id": node_id,
		}
		current_race_session["post_race_destination"] = "run_board"
		current_race_session["result_committed"] = true
		current_race_session.erase("save_error")
		return true

	var result_save := _result_save_candidate_with_session_metrics(event) if not player_dnf else _save_data.duplicate(true)
	var summary := {
		"save": result_save,
		"event_id": String(current_race_session["event_id"]),
		"new_best": false,
		"points_gained": 0,
		"act_completed": false,
		"ending_unlocked": false,
		"unlocked_vehicles": [],
		"mastery": mode == "mastery",
	}
	if mode == "mastery":
		summary["mastery_targets"] = (current_race_session.get("mastery_targets", {}) as Dictionary).duplicate(true)
		summary["mastery_dnf"] = player_dnf
	if mode == "mastery" and not player_dnf:
		var identity: Dictionary = current_race_session.get("mastery_identity", {})
		var targets: Dictionary = current_race_session.get("mastery_targets", {})
		var laps := maxi(1, int(event.get("laps", 1)))
		var best_lap := float(performance.get("best_lap", total_time / float(laps)))
		var mastery_result := MASTERY.apply_result(result_save.get("mastery_records"), identity, targets, best_lap, total_time)
		var candidate: Dictionary = summary["save"]
		candidate["mastery_records"] = mastery_result["records"]
		var ghost_result := PERSONAL_GHOST.store_best(
			candidate.get("personal_ghosts"),
			identity,
			total_time,
			performance.get("ghost_samples", [])
		)
		candidate["personal_ghosts"] = ghost_result["ghosts"]
		summary["save"] = candidate
		summary["mastery_record"] = mastery_result["record"]
		summary["mastery_targets"] = (current_race_session.get("mastery_targets", {}) as Dictionary).duplicate(true)
		summary["new_best_lap"] = mastery_result["new_best_lap"]
		summary["new_best_race"] = mastery_result["new_best_race"]
		summary["medal_improved"] = mastery_result["medal_improved"]
		summary["ghost_saved"] = ghost_result["saved"]
	elif mode == "championship" and not player_dnf:
		summary = CATALOG.apply_event_result(
			result_save,
			String(current_race_session["event_id"]),
			int(current_race_session["result"]["position"])
		)
	var candidate: Dictionary = summary["save"]
	if candidate != _save_data and not _save_candidate(candidate):
		if mode == "mastery":
			var records_only: Dictionary = candidate.duplicate(true)
			records_only["personal_ghosts"] = (_save_data.get("personal_ghosts", []) as Array).duplicate(true)
			summary["ghost_saved"] = false
			if records_only != _save_data and _save_candidate(records_only):
				candidate = records_only
			else:
				current_race_session["save_error"] = _last_save_error
				current_race_session["result_summary"] = summary
				current_race_session["post_race_destination"] = "map"
				return false
		else:
			current_race_session["save_error"] = _last_save_error
			return false
	_save_data = candidate
	current_race_session["result_summary"] = summary
	current_race_session["post_race_destination"] = "ending" if mode == "championship" and CATALOG.is_ending_pending(candidate) else "map"
	current_race_session["result_committed"] = true
	current_race_session.erase("save_error")
	return true


func _result_save_candidate_with_session_metrics(event: Dictionary) -> Dictionary:
	var candidate := _save_data.duplicate(true)
	var metrics := MASTERY.normalize_circuit_metrics(current_race_session.get("mastery_circuit_metrics"), event)
	if metrics.is_empty():
		return candidate
	var key := MASTERY.circuit_metrics_key_for_event(event)
	var metrics_map: Dictionary = candidate.get("mastery_circuit_metrics", {}).duplicate(true)
	metrics_map[key] = metrics.duplicate(true)
	candidate["mastery_circuit_metrics"] = metrics_map
	return candidate


func continue_after_race(transition_scene: bool = true) -> void:
	if String(current_race_session.get("mode", "")) == "strip":
		current_race_session.clear()
		_destination = "title"
		if transition_scene:
			get_tree().change_scene_to_file(BOOT_SCENE)
		return
	if current_race_session.is_empty() or not current_race_session.has("result"):
		return
	if String(current_race_session["mode"]) in ["quick", "discovery"]:
		var return_mode := String(current_race_session["mode"])
		current_race_session.clear()
		_destination = "discovery" if return_mode == "discovery" else "title"
		get_tree().change_scene_to_file(BOOT_SCENE)
		return
	if String(current_race_session.get("mode", "")) == "mastery" and not bool(current_race_session.get("result_committed", false)):
		current_race_session.clear()
		_destination = "map"
		if transition_scene:
			get_tree().change_scene_to_file(BOOT_SCENE)
		return
	if not bool(current_race_session.get("result_committed", false)):
		return
	_last_result_summary = current_race_session.get("result_summary", {}).duplicate(true)
	_destination = String(current_race_session.get("post_race_destination", "map"))
	if transition_scene:
		get_tree().change_scene_to_file(BOOT_SCENE)


## The declared field size is authoritative: a session may carry its opponents
## from a saved roster, but the event always states how many cars it fields.
static func _field_size(event: Dictionary) -> int:
	var declared := maxi((event.get("opponents", []) as Array).size(), int(event.get("opponent_count", 0)))
	return clampi(declared + 1, 1, 4)


## A run race is raced once: no restart mid-race and no retry after it.
func can_retry_race() -> bool:
	return String(current_race_session.get("mode", "")) != "run"


func retry_race(reload_scene: bool = true) -> void:
	if current_race_session.is_empty() or _transitioning_to_race or not can_retry_race():
		return
	if String(current_race_session.get("mode", "")) == "mastery":
		var identity: Dictionary = current_race_session.get("mastery_identity", {})
		current_race_session["best_ghost"] = PERSONAL_GHOST.compatible_best(_save_data.get("personal_ghosts"), identity)
	_reset_race_attempt()
	if reload_scene:
		_begin_race_transition(String(current_race_session.get("vehicle_id", "")))


func can_start_mastery_rematch() -> bool:
	if current_race_session.is_empty() or not bool(current_race_session.get("result_committed", false)):
		return false
	if String(current_race_session.get("mode", "")) != "championship" or CATALOG.is_ending_pending(_save_data):
		return false
	return String(current_race_session.get("event_id", "")) in _save_data.get("completed_events", [])


func start_mastery_rematch(reload_scene: bool = true) -> bool:
	if not can_start_mastery_rematch() or _transitioning_to_race:
		return false
	var event := _mastery_solo_event(current_race_session.get("event", {}))
	var vehicle_id := String(current_race_session.get("vehicle_id", "rustbug"))
	var metrics: Dictionary = current_race_session.get("mastery_circuit_metrics", {})
	if metrics.is_empty():
		metrics = MASTERY.metrics_for_event(_save_data.get("mastery_circuit_metrics"), event)
	var context := MASTERY.create_context(event, vehicle_id, metrics)
	var identity: Dictionary = context["identity"]
	if identity.is_empty():
		return false
	current_race_session["mode"] = "mastery"
	current_race_session["event"] = event
	current_race_session["difficulty"] = "club_circuit"
	current_race_session["mastery_identity"] = identity
	current_race_session["mastery_targets"] = (context["targets"] as Dictionary).duplicate(true)
	current_race_session["best_ghost"] = PERSONAL_GHOST.compatible_best(_save_data.get("personal_ghosts"), identity)
	_reset_race_attempt()
	if reload_scene:
		_begin_race_transition(vehicle_id)
	return true


func _reset_race_attempt() -> void:
	current_race_session.erase("result")
	current_race_session.erase("result_summary")
	current_race_session.erase("post_race_destination")
	current_race_session.erase("save_error")
	current_race_session["result_committed"] = false


func _mastery_solo_event(event: Dictionary) -> Dictionary:
	var solo := event.duplicate(true)
	solo["opponent_count"] = 0
	solo["opponents"] = []
	return solo


func abandon_race() -> void:
	if current_race_session.is_empty() or current_race_session.has("result"):
		return
	var mode := String(current_race_session.get("mode", "quick"))
	if mode == "run":
		_settle_race_in_flight()
	_destination = "run_board" if mode == "run" else ("discovery" if mode == "discovery" else ("title" if mode in ["quick", "strip"] else "map"))
	current_race_session.clear()
	get_tree().change_scene_to_file(BOOT_SCENE)


## The active roguelike run, or null. Only this path writes the run; Quick Race
## never writes back to it.
func current_run_session() -> RunSession:
	return _current_run_session


## Starts a fresh run for the seed and persists its opening state.
func start_run(run_seed: int) -> RunSession:
	if _current_run_session != null:
		abandon_run()
		if _current_run_session != null and not is_save_read_only():
			# The old night could not be saved; it stays until it can. A read-only
			# save never will, so there the new night simply replaces it.
			return null
	_current_run_session = RUN_SESSION.create(run_seed)
	persist_current_run()
	return _current_run_session


## Persists the active run. A run that has ended (won or lost) is written out
## in the same save as the cars it won joining the garage (one-way); the run is
## only dropped once that save lands, so a failed write loses nothing.
func persist_current_run() -> void:
	last_run_error = ""
	var ended := _current_run_session != null and (_current_run_session.is_complete() or _current_run_session.is_failed())
	var candidate := _save_data.duplicate(true)
	if ended:
		candidate["garage_cars"] = _garage_with(_current_run_session.won_cars())
		candidate["current_run"] = {}
	else:
		candidate["current_run"] = RUN_SESSION.serialize(_current_run_session) if _current_run_session != null else {}
	if candidate != _save_data:
		if is_save_read_only():
			last_run_error = "save is read-only"
		elif not _save_candidate(candidate):
			last_run_error = "save failed"
		else:
			_save_data = candidate
	run_save_error = last_run_error
	if ended and last_run_error.is_empty():
		_current_run_session = null
	_install_held_vehicles()


## Abandoning is losing the night: the run ends like any failed run, so the
## cars it won still join the garage and the saved run is cleared.
func abandon_run() -> void:
	if _current_run_session != null:
		_current_run_session.failed = true
	persist_current_run()


## Every car in the garage plus the ones this night won (append only, no duplicates).
func _garage_with(won: Array[Dictionary]) -> Array:
	var garage: Array = (_save_data.get("garage_cars", []) as Array).duplicate(true)
	var held := {}
	for car: Dictionary in garage:
		held[String(car["id"])] = true
	for car: Dictionary in won:
		if not held.has(String(car["id"])):
			garage.append(car)
	return garage


## Installs every generated car the player holds (the garage and the active run)
## so they resolve by id like shipped cars.
func _install_held_vehicles() -> void:
	var cars: Array = (_save_data.get("garage_cars", []) as Array).duplicate(true)
	if _current_run_session != null:
		cars.append_array(_current_run_session.won_cars())
	VehicleDirectory.install(cars.map(func(car: Dictionary) -> Dictionary: return CATALOG.generated_vehicle(car)))


## Quick Race is the garage: the shipped cars plus every car won, in garage order.
func quick_race_roster() -> Array[String]:
	var ids := CATALOG.quick_race_vehicle_ids()
	ids.append_array(garage_car_ids())
	return CATALOG.garage_order(ids)


## The garage's won cars, newest last.
func garage_car_ids() -> Array[String]:
	var ids: Array[String] = []
	for car: Dictionary in _save_data.get("garage_cars", []):
		ids.append(String(car["id"]))
	return ids


## Starts a new run on a random seed (every NEW RUN is a different night).
## Tests and reproducible cases use start_run(fixed_seed) directly.
func start_new_run() -> RunSession:
	return start_run(_random_seed(RUN_SEED_MAX))


## Delegates to the session to move to a child node (if allowed), then persists
## the run. Returns true on success. Real per-node outcomes (races, benches,
## rivals, etc) are resolved in later slices; this slice only advances position.
func enter_run_node(node_id: String) -> bool:
	if _current_run_session == null:
		return false
	var ok: bool = _current_run_session.enter_node(node_id)
	if ok:
		persist_current_run()
	else:
		last_run_error = "refused"
	return ok

func _advance_or_check_node(node_id: String, allowed_types: Array) -> bool:
	if _current_run_session == null:
		last_run_error = "no active run"
		return false
	var target_id := node_id
	if target_id.is_empty():
		target_id = String(_current_run_session.current_node().get("id", ""))
	if target_id == String(_current_run_session.current_node().get("id", "")):
		var ntype := String(_current_run_session.current_node().get("type", ""))
		if not allowed_types.has(ntype):
			last_run_error = "wrong node type"
			return false
		return true
	var allowed := false
	for entry: Dictionary in _current_run_session.available_nodes():
		if String(entry.get("id", "")) == target_id:
			allowed = true
			break
	if not allowed:
		last_run_error = "node not an available child"
		return false
	var node: Dictionary = _current_run_session.current_map.get_node(target_id) if _current_run_session.current_map != null else {}
	var ntype: String = String(node.get("type", ""))
	if not allowed_types.has(ntype):
		last_run_error = "wrong node type"
		return false
	if not _current_run_session.enter_node(target_id):
		last_run_error = "failed to enter node"
		return false
	persist_current_run()
	return true

func start_run_race(node_id: String = "") -> bool:
	return _start_run_event(node_id, ["race", "act_rival"])


func start_run_rival(node_id: String = "") -> bool:
	return _start_run_event(node_id, ["rival"])


## Enters (or re-checks) a race-type run node and builds its race session: a
## full field for races, the hardest difficulty for the act rival, a one-on-one
## duel for rivals.
func _start_run_event(node_id: String, allowed_types: Array) -> bool:
	if _transitioning_to_race:
		last_run_error = "transitioning to race"
		return false
	if _current_run_session == null:
		last_run_error = "no active run"
		return false
	# Draw the circuit before entering the stop, so a failed draw never leaves
	# the run standing on a stop it cannot race.
	var target_id := node_id if not node_id.is_empty() else _current_run_session.current_node_id
	var circuit := _run_circuit(target_id)
	if circuit.is_empty():
		last_run_error = "circuit could not be drawn"
		return false
	if not _advance_or_check_node(node_id, allowed_types):
		return false
	if not _current_run_session.is_race_pending():
		last_run_error = "already raced"
		return false
	var node: Dictionary = _current_run_session.current_node()
	var node_type := String(node.get("type", ""))
	var duel := node_type == "rival"
	var vehicle_id: String = _current_run_session.current_car_id
	_roll_quick_roster()
	_install_roster_for("quick")
	var opponents: Array = _roster_ids(_quick_roster)
	if duel:
		opponents = opponents.slice(0, 1)
	var event_id: String = "run_%s" % target_id
	var event := _event_with_generated_identity({"opponents": opponents}, circuit)
	if event.is_empty():
		last_run_error = "circuit could not be drawn"
		return false
	# The circuit decides the track; the stop decides who races on it.
	event["id"] = event_id
	event["race_format"] = "rival_duel" if duel else "circuit"
	event["opponents"] = opponents
	event["opponent_count"] = opponents.size()
	current_race_session = {
		"mode": "run",
		"event_id": event_id,
		"event": event,
		"vehicle_id": vehicle_id,
		"difficulty": RUN_ACT_RIVAL_DIFFICULTY if node_type == "act_rival" else String(_save_data.get("difficulty", "club_circuit")),
		"result_committed": false,
		"run_node_id": target_id,
	}
	if not _test_mode:
		_begin_race_transition(vehicle_id)
	return true


## The circuit a run stop races on: drawn from the run seed, the act and the
## stop like a Quick Race draw, in the act's room. The same stop always gets the
## same circuit; different stops and acts get different ones.
func _run_circuit(stop_id: String) -> Dictionary:
	var act := _current_run_session.current_map.act
	var seed := _current_run_session.circuit_seed(stop_id)
	return GENERATED_CIRCUITS.create(
		StringName(CATALOG.get_act(act)["id"]),
		GENERATED_CIRCUITS.room_for_route_seed(seed),
		seed,
		_current_run_session.circuit_reversed(stop_id),
		act
	)


## The race scene calls this when its countdown begins: from here a run race
## counts, so it is marked (and saved) as running until its result lands.
## A race that never got this far (cancelled or failed loading) costs nothing.
func race_started() -> void:
	if String(current_race_session.get("mode", "")) != "run" or _current_run_session == null:
		return
	if _current_run_session.start_race(String(current_race_session.get("run_node_id", "")), _field_size(current_race_session.get("event", {}))):
		persist_current_run()


## A run race that started and was never reported (quit, abandoned, or the game
## closed mid-race) ends as a did-not-finish in last place. A mark that no longer
## matches the run is dropped rather than retried on every boot.
func _settle_race_in_flight() -> void:
	if _current_run_session == null or _current_run_session.race_in_flight.is_empty():
		return
	var flight: Dictionary = _current_run_session.race_in_flight
	var field := int(flight.get("field", 1))
	_commit_run_result(String(flight.get("node", "")), field, true, field)
	if _current_run_session != null and not _current_run_session.race_in_flight.is_empty():
		_current_run_session.race_in_flight = {}
		persist_current_run()


## Applies a run race outcome exactly once: rivals through resolve_rival (which
## owns its own loss penalty), races and the act rival through resolve_race plus
## the crash wear of a poor finish. A refused resolution applies nothing.
func _commit_run_result(node_id: String, position: int, dnf: bool, field_size: int) -> void:
	if _current_run_session == null or node_id.is_empty():
		return
	if String(_current_run_session.current_node().get("type", "")) == "rival":
		_current_run_session.resolve_rival(node_id, position == 1 and not dnf)
	else:
		var outcome: Dictionary = _current_run_session.resolve_race(node_id, position, field_size)
		if outcome.has("error"):
			last_run_error = String(outcome["error"])
			return
		if dnf or position >= RUN_CRASH_FINISH_POSITION:
			_current_run_session.register_crash(RUN_CRASH_SEVERITY)
	persist_current_run()


## Run node outcome seams (non-race). Each validates the node, applies the
## session action and persists it. The return value is the logical outcome; a
## failed save is reported through last_run_error, never by undoing the move.
func run_bench_repair(car_key: String, node_id: String = "") -> bool:
	return _run_seam(node_id, "bench", func() -> bool: return _current_run_session.bench_repair(car_key))


func run_bench_fit(part: String, node_id: String = "") -> bool:
	return _run_seam(node_id, "bench", func() -> bool: return _current_run_session.bench_fit(_current_run_session.current_car_id, part))


func run_buy_part(part_id: String, node_id: String = "") -> bool:
	return _run_seam(node_id, "parts_van", func() -> bool: return _current_run_session.buy_part(part_id))


func run_open_lockup(node_id: String = "") -> bool:
	return _run_seam(node_id, "lockup", func() -> bool: return not _current_run_session.open_lockup().is_empty())


func run_resolve_errand(choice: int, node_id: String = "") -> bool:
	return _run_seam(node_id, "errand", func() -> bool: return not _current_run_session.resolve_errand(choice).has("error"))


func _run_seam(node_id: String, node_type: String, action: Callable) -> bool:
	if not _advance_or_check_node(node_id, [node_type]):
		return false
	if not bool(action.call()):
		last_run_error = "refused"
		return false
	persist_current_run()
	return true


func update_setting(key: String, value: Variant) -> bool:
	var candidate := _save_data.duplicate(true)
	match key:
		"difficulty":
			if value is String and value in SaveStore.VALID_DIFFICULTIES:
				candidate[key] = value
			else:
				return false
		"master_volume", "music_volume", "sfx_volume", "engine_volume", "tyre_volume":
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
	_apply_audio_settings()
	if key == "fullscreen":
		_apply_window_mode()
	return true


func _retry_setting(key: String, value: Variant) -> void:
	if update_setting(key, value):
		_shell.call("show_settings")


func play_sfx(sound_name: StringName, volume_scale: float = 1.0, pitch_scale: float = 1.0) -> bool:
	return audio_director.play_sfx(sound_name, volume_scale, pitch_scale) if is_instance_valid(audio_director) else false


func set_local_race_vehicle(vehicle: Node, vehicle_id: String = "") -> void:
	if is_instance_valid(audio_director):
		audio_director.set_local_vehicle(vehicle, vehicle_id)


func set_race_audio_paused(paused: bool) -> void:
	if is_instance_valid(audio_director):
		audio_director.set_race_paused(paused)


func quit_game() -> void:
	get_tree().quit()


func _sync_current_scene() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	if _transitioning_to_race and scene.scene_file_path == BOOT_SCENE:
		return
	_last_scene = scene
	if scene.scene_file_path == BOOT_SCENE:
		if is_instance_valid(audio_director):
			audio_director.play_menu_music()
		_hide_boot_placeholder(scene)
		_ensure_shell()
		current_race_session.clear()
		_quick_roster = {}
		_install_active_roster()
		_shell.visible = true
		match _destination:
			"map":
				_shell.call("show_map", _last_result_summary)
			"discovery":
				_shell.call("show_discovery")
			"run_board":
				_shell.call("show_run_board")
			"ending":
				_shell.call("show_ending")
			_:
				if CATALOG.is_ending_pending(_save_data):
					_shell.call("show_ending")
				else:
					_shell.call("show_title")
		_last_result_summary = {}
		_destination = "title"
	else:
		if scene.scene_file_path == RACE_SCENE and is_instance_valid(audio_director) and not _transitioning_to_race:
			audio_director.play_race_music()
		if _shell:
			_shell.visible = false


func _ensure_shell() -> void:
	if is_instance_valid(_shell):
		return
	_shell = _shell_script.new() as CanvasLayer
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
	_apply_audio_settings()
	_apply_window_mode()


func _apply_audio_settings() -> void:
	_apply_bus_volume("Master", float(_save_data["master_volume"]))
	_apply_bus_volume("Music", float(_save_data["music_volume"]))
	_apply_bus_volume("SFX", float(_save_data["sfx_volume"]))
	_apply_bus_volume("Engine", float(_save_data["engine_volume"]))
	_apply_bus_volume("Tyre", float(_save_data["tyre_volume"]))


func _apply_window_mode() -> void:
	if DisplayServer.get_name().to_lower() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(_save_data["fullscreen"]) else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
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


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected:
		_release_joypad_actions()
	# Emit live state on every change (connect or disconnect). Callers can react to
	# presence without polling.
	joypad_connection_changed.emit(not Input.get_connected_joypads().is_empty())


func _release_joypad_actions() -> void:
	# Release every action that has a joypad event bound and is currently held.
	# This prevents a disconnected pad from leaving throttle/steer/pause/ui_* stuck.
	for action: StringName in InputMap.get_actions():
		if not Input.is_action_pressed(action):
			continue
		var has_joypad_event := false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				has_joypad_event = true
				break
		if has_joypad_event:
			Input.action_release(action)


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
	var startup_deadline := Time.get_ticks_msec() + 45000
	while is_race_loading() and not _loading_failed and Time.get_ticks_msec() < startup_deadline:
		await get_tree().process_frame
	if is_race_loading() or get_tree().current_scene == null or get_tree().current_scene.scene_file_path != RACE_SCENE:
		_release_smoke_fail("race scene did not load")
		return
	var race := get_tree().current_scene
	var race_manager := race.get_node_or_null("RaceManager") as RaceManager
	if race_manager == null:
		_release_smoke_fail("race manager is missing")
		return
	# Keep automated release verification independent from stale host input state.
	if get_tree().paused:
		race.call("_set_paused", false)
	while Time.get_ticks_msec() < startup_deadline and not race_manager.is_running:
		await get_tree().physics_frame
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
