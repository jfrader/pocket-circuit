extends SceneTree

const APP_SHELL := preload("res://scripts/ui/app_shell.gd")
const DISCOVERY_PANEL := preload("res://scripts/ui/circuit_discovery_panel.gd")
const IDENTITIES := preload("res://scripts/race/generated_circuit_identity.gd")
const RULES := preload("res://scripts/race/generated_circuit_rules.gd")


class MockApp extends Node:
	var last_quick_tier := ""
	var last_discovery_identity: Dictionary = {}
	var favorites: Array = []
	var save_read_only := false

	func get_save_data() -> Dictionary:
		return {"selected_vehicle": "rustbug", "unlocked_vehicles": ["rustbug"], "reduced_motion": false}

	func is_save_read_only() -> bool:
		return save_read_only

	func get_last_save_error() -> String:
		return ""

	func random_circuit_seed(theme: StringName) -> Dictionary:
		return {"theme": String(theme), "room": String(IDENTITIES.room_for_route_seed(24680)), "seed": 24680}

	func circuit_room_for_seed(seed: int) -> StringName:
		return IDENTITIES.room_for_route_seed(seed)

	func generated_circuit_identity(theme: StringName, room: StringName, seed: int, reverse: bool = false, length_tier: String = "standard") -> Dictionary:
		return IDENTITIES.create(theme, room, seed, reverse, 0, "", "", {}, length_tier)

	func start_circuit_race(_theme: StringName, _room: StringName, _seed: int, _vehicle_id: String, _reverse: bool = false, length_tier: String = "standard") -> void:
		last_quick_tier = length_tier

	func get_circuit_library() -> Dictionary:
		return {"history": [], "favorites": favorites}

	func decode_circuit_share_code(code: String) -> Dictionary:
		return IDENTITIES.decode_share_code(code)

	func circuit_share_code(identity: Dictionary) -> Dictionary:
		return IDENTITIES.encode_share_code(identity)

	func set_circuit_favorite(identity: Dictionary, favorite: bool) -> bool:
		if favorite and identity.get("fingerprint", "") not in favorites:
			favorites.append(String(identity["fingerprint"]))
		elif not favorite:
			favorites.erase(String(identity.get("fingerprint", "")))
		return true

	func retier_circuit_identity(identity: Dictionary, length_tier: String) -> Dictionary:
		return get_node("/root/App").call("retier_circuit_identity", identity, length_tier)

	func prepare_circuit_preview(identity: Dictionary) -> Dictionary:
		await get_tree().process_frame
		await get_tree().process_frame
		return {
			"identity_fingerprint": String(identity.get("fingerprint", "")),
			"loaded_fingerprint": "0123456789abcdef",
			"points": PackedVector2Array([Vector2(20, 20), Vector2(390, 30), Vector2(380, 160), Vector2(30, 170)]),
		}

	func start_discovery_race(identity: Dictionary, _vehicle_id: String, _preview_fingerprint: String) -> bool:
		last_discovery_identity = identity.duplicate(true)
		return true

	func play_sfx(_sound: StringName, _volume: float = 1.0) -> bool:
		return true


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload should be available"):
		return

	# Default helper calls stay standard.
	var standard_identity: Dictionary = app.call("generated_circuit_identity", &"workshop", &"wide", 246810, false)
	if not _expect(not standard_identity.is_empty() and String(standard_identity["length_tier"]) == "standard", "default generated identities should stay standard"):
		return
	var long_identity: Dictionary = app.call("generated_circuit_identity", &"workshop", &"wide", 246810, false, "long")
	if not _expect(not long_identity.is_empty() and String(long_identity["length_tier"]) == "long" and String(IDENTITIES.generation_options(long_identity)["length_tier"]) == "long", "an explicit long identity should carry its tier into generation_options"):
		return
	if not _expect(String(long_identity["fingerprint"]) != String(standard_identity["fingerprint"]), "changing the length profile should change the fingerprint"):
		return
	if not _expect((app.call("generated_circuit_identity", &"workshop", &"wide", 246810, false, "bogus") as Dictionary).is_empty(), "an unknown length profile should be rejected"):
		return

	var endurance_identity: Dictionary = app.call("retier_circuit_identity", long_identity, "endurance")
	if not _expect(
			not endurance_identity.is_empty()
			and String(endurance_identity["length_tier"]) == "endurance"
			and String(endurance_identity["fingerprint"]) != String(long_identity["fingerprint"])
			and endurance_identity["sub_seeds"] == long_identity["sub_seeds"]
			and String(endurance_identity["room"]) == String(long_identity["room"])
			and String(endurance_identity["material_id"]) == String(long_identity["material_id"]),
			"retier should preserve seeds, room, and material while changing the fingerprint"
	):
		return
	if not _expect((app.call("retier_circuit_identity", long_identity, "bogus") as Dictionary).is_empty(), "retier should reject an unknown profile"):
		return

	# start_circuit_race forwards the explicit profile into the session identity.
	var room: StringName = app.call("circuit_room_for_seed", 24680)
	if not _expect(app.call("start_circuit_race", &"kitchen", room, 24680, "rustbug", false, "long"), "start_circuit_race should launch a long circuit"):
		return
	var session: Dictionary = app.call("get_current_race_session")
	var session_event: Dictionary = session.get("event", {})
	if not _expect(String(session_event.get("length_tier", "")) == "long" and String((session_event.get("generated_circuit_identity", {}) as Dictionary).get("length_tier", "")) == "long", "quick race should forward the long profile into the session identity"):
		return
	_reset_race_transition(app)

	# Existing default callers stay standard.
	if not _expect(app.call("start_circuit_race", &"kitchen", room, 24680, "rustbug", false), "a default quick race call should still launch"):
		return
	session = app.call("get_current_race_session")
	if not _expect(String((session.get("event", {}) as Dictionary).get("length_tier", "")) == "standard", "a default quick race call should remain standard"):
		return
	_reset_race_transition(app)

	# Nonexistent tiers reject instead of silently falling back.
	if not _expect(not app.call("start_circuit_race", &"kitchen", room, 24680, "rustbug", false, "bogus"), "start_circuit_race should reject an unknown profile"):
		return

	await _test_ui_selection()

	print("TRACK_LENGTH_SELECTION_TEST PASS")
	quit(0)


func _test_ui_selection() -> void:
	var mock := MockApp.new()
	root.add_child(mock)
	var shell := APP_SHELL.new() as CanvasLayer
	root.add_child(shell)
	shell.call("configure", mock)
	shell.call("show_quick_race")
	await _wait_frames(2)
	if not _expect(String(shell.get("_quick_race_length_tier")) == "standard", "Quick Race should pin the standard length profile"):
		return
	if not _expect(
			String(shell.get("_quick_race_theme")) == "kitchen"
			and String(shell.get("_quick_race_room")) == "classic"
			and int(shell.get("_quick_race_seed")) == 875
			and not bool(shell.get("_quick_race_reverse")),
			"Quick Race should pin the fixed kitchen/classic seed 875 identity"
	):
		return
	if not _expect(shell.find_child("QuickRaceSize", true, false) == null, "Quick Race should not expose a size selector"):
		return
	shell.call("_start_quick_race")
	if not _expect(mock.last_quick_tier == "standard", "starting a quick race should forward the pinned standard profile"):
		return
	root.remove_child(shell)
	shell.free()

	var long_identity := IDENTITIES.create(&"kitchen", IDENTITIES.room_for_route_seed(13579), 13579, false, 1, "", "", {}, "long")
	var panel := DISCOVERY_PANEL.new() as CircuitDiscoveryPanel
	panel.name = "CircuitDiscoveryPanel"
	root.add_child(panel)
	panel.call("configure", mock)
	panel.call("show_confirmation", long_identity)
	await _wait_frames(4)
	if not _expect(String((panel.get("_identity") as Dictionary).get("length_tier", "")) == "long", "an imported or favorited long profile should survive into the confirmation preview"):
		return
	var launch := panel.find_child("DiscoveryLaunch", true, false) as Button
	var discovery_size := panel.find_child("DiscoverySize", true, false) as OptionButton
	if not _expect(launch != null and discovery_size != null and not launch.disabled and discovery_size.selected == RULES.LENGTH_TIERS.find("long"), "discovery confirmation should complete its preview and reflect the imported profile in its size selector"):
		return
	var original_fingerprint := String((panel.get("_identity") as Dictionary)["fingerprint"])
	discovery_size.select(RULES.LENGTH_TIERS.find("endurance"))
	discovery_size.item_selected.emit(discovery_size.selected)
	await _wait_frames(1)
	if not _expect(String((panel.get("_identity") as Dictionary).get("length_tier", "")) == "endurance" and String((panel.get("_identity") as Dictionary)["fingerprint"]) != original_fingerprint, "changing the profile should regenerate the identity with a new fingerprint"):
		return
	await _wait_frames(4)
	launch = panel.find_child("DiscoveryLaunch", true, false) as Button
	if not _expect(not launch.disabled and String((panel.get("_preview") as Dictionary).get("identity_fingerprint", "")) == String((panel.get("_identity") as Dictionary)["fingerprint"]), "the regenerated profile should re-prepare its preview and re-enable launch"):
		return
	root.remove_child(panel)
	panel.free()
	root.remove_child(mock)
	mock.free()


func _reset_race_transition(app: Node) -> void:
	app.set("_loading_cancelled", true)
	if is_instance_valid(app.get("_loading_screen")):
		(app.get("_loading_screen") as Node).queue_free()
	app.set("_loading_screen", null)
	app.set("_transitioning_to_race", false)
	app.current_race_session.clear()


func _wait_frames(count: int) -> void:
	for _frame in count:
		await process_frame


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_LENGTH_SELECTION_TEST FAIL: " + message)
	quit(1)
	return false
