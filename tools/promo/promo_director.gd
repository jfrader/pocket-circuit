extends Node
## Promo capture director. Registered as an autoload only inside a throwaway
## capture worktree (tools/promo/setup_capture_worktree.sh); never committed to
## project.godot. Arguments come after "--" as --key=value. See tools/promo/README.md.

const BOSS_AI := preload("res://tools/promo/boss_ai.gd")
const ID_LIB := preload("res://scripts/presentation/procedural_identity_library.gd")
const CAR_GEN := preload("res://scripts/vendor/procedural_2d/procedural_car_generator.gd")

const MENU_WAIT_SECONDS := 1.5
const SAFETY_QUIT_SECONDS := 600.0
const COUNTDOWN_LEAD_SECONDS := 3.0
const GARAGE_IDS: Array[String] = ["rustbug", "pinbolt", "scrapjaw", "flicker", "thimble", "spindle", "anvil", "dustmite"]
const GARAGE_START_SECONDS := 2.0
const FLIP_THEMES: Array[String] = ["kitchen", "workshop", "office"]
const FLIP_TIERS: Array[String] = ["standard", "long", "compact", "endurance"]
const FLIP_SEED_STRIDE := 7919
# The style that pushes every AI personality axis to its upper bound.
const BOSS_STYLE := {"corner_pace": 1.04, "brake_timing": 1.1, "boost_eagerness": 1.18, "overtake_aggression": 1.13, "shortcut_preference": 1.16, "line_commitment": 1.06}

var _args := {}
var _elapsed := 0.0
var _started := false
var _race_started_at := -1.0
var _autopiloted: Array[VehicleController] = []
var _looks_applied := false
var _audio_streams: Dictionary = {}
var _garage_menu: Node = null
var _garage_step := -1
var _flip_panel: Node = null
var _flip_step := -1
var _drift_until := {}
var _drift_cooldown_until := {}
var _drift_steer := {}
var _was_braking := {}
var _metrics := {"last": 0.0, "hits": 0, "drift": 0.0, "boost": 0.0, "speed_sum": 0.0, "ticks": 0, "prev_speed": {}}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--") and "=" in arg:
			var pair := arg.substr(2).split("=", true, 1)
			_args[pair[0]] = pair[1]
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Run after the AI controllers so the boss driver can override their output.
	process_physics_priority = 1000
	set_process(_args.has("promo-shot"))
	set_physics_process(_args.has("promo-shot"))


func _arg(key: String, fallback: String) -> String:
	return String(_args.get(key, fallback))


func _num(key: String, fallback: float) -> float:
	return float(_args.get(key, fallback))


func _flag(key: String, fallback := false) -> bool:
	return _arg(key, "1" if fallback else "0") == "1"


func _process(delta: float) -> void:
	_elapsed += delta
	for bus in _arg("mute", "").split(",", false):
		var index := AudioServer.get_bus_index(bus)
		if index >= 0:
			AudioServer.set_bus_mute(index, true)
	_silence_sounds()
	var shot := _arg("promo-shot", "")
	if not _started and _elapsed > MENU_WAIT_SECONDS:
		_started = _start_shot(shot)
	match shot:
		"race", "strip":
			_take_over_player()
			_apply_looks()
			if _race_started_at >= 0.0 and _elapsed - _race_started_at > _num("seconds", 30.0):
				get_tree().quit()
		"flip":
			_flip()
		"garage":
			_garage()
	if shot not in ["race", "strip"] and _elapsed > _num("seconds", 8.0):
		get_tree().quit()
	if _elapsed > SAFETY_QUIT_SECONDS:
		get_tree().quit()


func _start_shot(shot: String) -> bool:
	var app := get_node_or_null("/root/App")
	if app == null:
		return false
	if shot != "race" and shot != "strip":
		return true
	var theme := StringName(_arg("theme", "kitchen"))
	var seed := int(_arg("seed", str(app.call("random_circuit_seed", theme).get("seed", 1))))
	var room: StringName = app.call("circuit_room_for_seed", seed)
	if _args.has("difficulty"):
		app.get("_save_data")["difficulty"] = _arg("difficulty", "club_circuit")
	print("PROMO start ", shot, " ", theme, " ", room, " ", seed)
	var vehicle := _arg("vehicle", "rustbug")
	var tier := _arg("tier", "standard")
	if shot == "race":
		app.call("start_circuit_race", theme, room, seed, vehicle, _flag("reverse"), tier)
	else:
		app.call("start_strip_race", theme, room, seed, vehicle, false, tier, StringName(_arg("theme-b", "")))
	return true


func _find_race_manager() -> RaceManager:
	for node in get_tree().root.find_children("*", "", true, false):
		if node.get("race_manager") is RaceManager:
			return node.get("race_manager")
	return null


## Hands the player's car to an AI driver once the race starts.
func _take_over_player() -> void:
	for node in get_tree().get_nodes_in_group("player_vehicle"):
		var car := node as VehicleController
		if car == null or car in _autopiloted:
			continue
		var manager := _find_race_manager()
		if manager == null or not manager.is_running:
			continue
		if _race_started_at < 0.0:
			_race_started_at = _elapsed - COUNTDOWN_LEAD_SECONDS
		_autopiloted.append(car)
		if not _flag("autopilot", true):
			continue
		car.set_player_controlled(false)
		var driver: AIVehicleController
		var style := {}
		if _flag("boss"):
			driver = BOSS_AI.new()
			style = BOSS_STYLE
			for key in BOSS_AI.TUNABLE_KEYS:
				if _args.has("ai-" + key):
					driver.boss_overrides[key] = _num("ai-" + key, 0.0)
		else:
			driver = AIVehicleController.new()
		car.add_child(driver)
		driver.configure(car, manager, 0.0, _arg("pilot", "clockwork"), "promo", style, null)
		car.set_controls_locked(false)
		print("PROMO autopilot on ", car.name, " boss=", _flag("boss"))


## Gives every car in the field its own palette, livery, wheels and spoiler.
func _apply_looks() -> void:
	if _looks_applied or not _flag("vary", true):
		return
	var cars := get_tree().get_nodes_in_group("race_vehicle")
	if cars.size() < int(_num("field", 4)):
		return
	_looks_applied = true
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_num("look-seed", 77))
	var palettes: Array = CAR_GEN.available_palette_ids().duplicate()
	for i in palettes.size():
		var j := rng.randi_range(i, palettes.size() - 1)
		var held = palettes[i]
		palettes[i] = palettes[j]
		palettes[j] = held
	var parts: Dictionary = CAR_GEN.available_parts()
	for i in cars.size():
		var car := cars[i] as VehicleController
		var vehicle_id := String(car.get_meta("audio_vehicle_id", _arg("vehicle", "rustbug")))
		var cosmetic := {"palette": palettes[i % palettes.size()]}
		for slot in ["livery", "wheels", "spoiler"]:
			cosmetic[slot] = parts[slot][rng.randi_range(0, parts[slot].size() - 1)]
		var key := ID_LIB._register_visual_key(vehicle_id, cosmetic)
		car.configure_visual_identity(key)
		print("PROMO look ", car.name, " ", key)


## Drops generated one-shots (e.g. boost, pursuit) from the audio director so
## play_sfx skips them. The director re-registers per-car voices on each race.
func _silence_sounds() -> void:
	var names := _arg("silence", "").split(",", false)
	if names.is_empty():
		return
	if _audio_streams.is_empty():
		for node in get_tree().root.find_children("*", "", true, false):
			if node.get("_generated_streams") is Dictionary:
				_audio_streams = node.get("_generated_streams")
				break
	for sound in names:
		_audio_streams.erase(StringName(sound))


func _garage() -> void:
	if _elapsed < GARAGE_START_SECONDS:
		return
	if _garage_menu == null:
		for node in get_tree().root.find_children("*", "", true, false):
			if node.has_method("show_garage") and node.has_method("_choose_vehicle"):
				_garage_menu = node
				break
		if _garage_menu == null:
			return
		_garage_menu.call("show_garage", GARAGE_IDS[0], GARAGE_IDS, "quick", "RACE")
	var step := int((_elapsed - GARAGE_START_SECONDS) / _num("dwell", 1.15))
	if step == _garage_step or step >= GARAGE_IDS.size():
		return
	_garage_step = step
	_garage_menu.call("_choose_vehicle", GARAGE_IDS[step])
	var button = _garage_menu.get("_vehicle_buttons").get(GARAGE_IDS[step])
	if button is Button:
		(button as Button).grab_focus()
	print("PROMO garage ", GARAGE_IDS[step])


## Opens Circuit Discovery and shows a new generated circuit every dwell.
func _flip() -> void:
	var start := _num("flip-start", 2.0)
	if _elapsed < start:
		return
	var app := get_node_or_null("/root/App")
	if _flip_panel == null:
		for node in get_tree().root.find_children("*", "", true, false):
			if node.has_method("show_discovery") and node.has_method("show_quick_race"):
				node.call("show_discovery")
				break
		_flip_panel = get_tree().root.find_child("CircuitDiscoveryPanel", true, false)
		if _flip_panel == null:
			return
	var step := int((_elapsed - start) / _num("dwell", 2.5))
	if step == _flip_step:
		return
	_flip_step = step
	var theme := StringName(FLIP_THEMES[step % FLIP_THEMES.size()])
	var seed := int(_num("seed-base", 4242)) + step * FLIP_SEED_STRIDE
	var room: StringName = app.call("circuit_room_for_seed", seed)
	var tier: String = FLIP_TIERS[(step / FLIP_THEMES.size()) % FLIP_TIERS.size()]
	var identity: Dictionary = app.call("generated_circuit_identity", theme, room, seed, step % 2 == 1, tier)
	if identity.is_empty():
		return
	_flip_panel.call("show_confirmation", identity)
	print("PROMO flip ", step, " ", theme, " ", seed, " ", identity.get("display_name", ""))


func _physics_process(delta: float) -> void:
	for car in _autopiloted:
		if not is_instance_valid(car):
			continue
		if _flag("boss"):
			_drive_like_a_boss(car)
		if _flag("metrics"):
			_record_metrics(car, delta)


## Flat out, a short handbrake flick at the start of every braking zone, and
## boost on the straights. Overrides the AI's output for this physics tick.
func _drive_like_a_boss(car: VehicleController) -> void:
	var steer := float(car.get("_external_steer"))
	var speed_ratio := car.speed / maxf(car.get_effective_max_speed(), 0.001)
	var braking := float(car.get("_external_brake")) > _num("b-brake", 0.2)
	var brake_onset := braking and not bool(_was_braking.get(car, false))
	_was_braking[car] = braking
	if brake_onset and speed_ratio > _num("b-speed", 0.5) and absf(steer) > _num("b-steer", 0.2) and _elapsed > float(_drift_cooldown_until.get(car, -INF)):
		_drift_until[car] = _elapsed + _num("b-hold", 0.15)
		_drift_cooldown_until[car] = _elapsed + _num("b-cool", 0.8)
		_drift_steer[car] = signf(steer)
	if _elapsed < float(_drift_until.get(car, -INF)):
		car.set_external_controls(1.0, 0.0, float(_drift_steer[car]), true, false)
	elif absf(steer) < _num("b-boost-steer", 0.15) and not car.is_drifting:
		car.set("_external_boost", true)


func _record_metrics(car: VehicleController, delta: float) -> void:
	var speed_ratio := car.speed / maxf(car.get_effective_max_speed(), 0.001)
	var previous: Dictionary = _metrics["prev_speed"]
	if float(previous.get(car, car.speed)) - car.speed > _num("hit-drop", 60.0):
		_metrics["hits"] += 1
	previous[car] = car.speed
	if car.is_drifting:
		_metrics["drift"] += delta
	if car.is_boost_active():
		_metrics["boost"] += delta
	_metrics["speed_sum"] += speed_ratio
	_metrics["ticks"] += 1
	if _elapsed - float(_metrics["last"]) < _num("m-every", 5.0):
		return
	_metrics["last"] = _elapsed
	var manager := _find_race_manager()
	print("PROMO m t=%.0f lap=%d prog=%.1f pos=%d avgspd=%.2f drift=%.1f boost=%.1f hits=%d" % [
		_elapsed - _race_started_at, manager.lap_count, manager.get_racer_progress(car), manager.get_racer_position(car),
		float(_metrics["speed_sum"]) / maxf(1.0, float(_metrics["ticks"])), _metrics["drift"], _metrics["boost"], _metrics["hits"]])
