extends SceneTree

const APP_SHELL := preload("res://scripts/ui/app_shell.gd")
const IDENTITIES := preload("res://scripts/race/generated_circuit_identity.gd")

class TestApp extends Node:
	var identity := IDENTITIES.create(&"kitchen", IDENTITIES.room_for_route_seed(13579), 13579, true, 1)
	var favorite := false
	var favorite_save_succeeds := true
	var save_read_only := false
	var discovery_opened := false
	var launched: Dictionary = {}
	var prewarm_events: Array = []

	func is_save_read_only() -> bool:
		return save_read_only

	func get_save_recovery_message() -> String:
		return ""

	func get_last_save_error() -> String:
		return "Disk is unavailable"

	func has_championship_progress() -> bool:
		return true

	func open_discovery() -> void:
		discovery_opened = true

	func get_save_data() -> Dictionary:
		return {"selected_vehicle": "rustbug", "unlocked_vehicles": ["rustbug"], "reduced_motion": true}

	func get_circuit_library() -> Dictionary:
		return {"history": [identity.duplicate(true)], "favorites": [identity.duplicate(true)] if favorite else []}

	func generated_circuit_identity(theme: StringName, room: StringName, seed: int, reverse: bool = false, length_tier: String = "standard") -> Dictionary:
		return IDENTITIES.create(theme, room, seed, reverse, 0, "", "", {}, length_tier)

	func decode_circuit_share_code(code: String) -> Dictionary:
		return IDENTITIES.decode_share_code(code)

	func circuit_share_code(value: Dictionary) -> Dictionary:
		return IDENTITIES.encode_share_code(value)

	func set_circuit_favorite(_value: Dictionary, value: bool) -> bool:
		if not favorite_save_succeeds:
			return false
		favorite = value
		return true

	func prepare_circuit_preview(value: Dictionary) -> Dictionary:
		var identity_fingerprint := String(value.get("fingerprint", ""))
		for _frame in 3:
			await get_tree().process_frame
		return {
			"identity_fingerprint": identity_fingerprint,
			"loaded_fingerprint": "0123456789abcdef",
			"points": PackedVector2Array([Vector2(20, 20), Vector2(390, 30), Vector2(380, 160), Vector2(30, 170)]),
		}

	func start_discovery_race(value: Dictionary, vehicle_id: String, preview_fingerprint: String) -> bool:
		launched = {"identity": value.duplicate(true), "vehicle_id": vehicle_id, "preview_fingerprint": preview_fingerprint}
		return true

	func prewarm_generated_circuit(event: Dictionary) -> void:
		prewarm_events.append(event.duplicate(true))

	func play_sfx(_sound: StringName, _volume: float = 1.0) -> bool:
		return true


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := TestApp.new()
	var shell := APP_SHELL.new() as CanvasLayer
	root.add_child(app)
	root.add_child(shell)
	shell.call("configure", app)
	shell.call("show_title")
	await _wait_frames(2)
	shell.call("_on_art_action", &"discovery")
	if not _expect(app.discovery_opened, "the title Discovery action should dispatch through the controller-safe menu"):
		return

	shell.call("show_discovery")
	await _wait_frames(2)
	var code_edit := shell.find_child("DiscoveryCode", true, false) as LineEdit
	if not _expect(code_edit != null and root.get_viewport().gui_get_focus_owner() == code_edit, "Discovery should open with stable keyboard/controller focus on its code field"):
		return
	code_edit.text = "PC1-BROKEN*"
	code_edit.text_submitted.emit(code_edit.text)
	await process_frame
	var panel := shell.find_child("CircuitDiscoveryPanel", true, false) as CircuitDiscoveryPanel
	if not _expect(panel != null and String(panel.get("_mode")) == "browser" and root.get_viewport().gui_get_focus_owner() == code_edit, "corrupt input should remain on the import screen and keep focus for correction"):
		return

	code_edit.text = String(IDENTITIES.encode_share_code(app.identity)["code"])
	code_edit.text_submitted.emit(code_edit.text)
	await _wait_frames(2)
	var favorite := shell.find_child("DiscoveryFavorite", true, false) as Button
	if not _expect(String(panel.get("_mode")) == "confirmation" and favorite != null and root.get_viewport().gui_get_focus_owner() == favorite, "a valid import should open confirmation without moving focus while its preview prepares"):
		return
	if not _expect(app.prewarm_events.size() == 1 and String((app.prewarm_events[0] as Dictionary).get("circuit_fingerprint", "")) == String(app.identity["fingerprint"]), "the confirmation screen must prewarm exactly the circuit it shows"):
		return
	await _wait_frames(5)
	var launch := shell.find_child("DiscoveryLaunch", true, false) as Button
	if not _expect(launch != null and not launch.disabled and root.get_viewport().gui_get_focus_owner() == favorite and String(app.identity["summary"]).contains("Reverse"), "preview completion should enable launch without stealing focus and should preserve reverse identity"):
		return
	favorite.text = "REMOVE FAVORITE"
	favorite.pressed.emit()
	if not _expect(app.favorite and bool(panel.get("_is_favorite")) and favorite.text == "REMOVE FAVORITE", "favorite behavior should use explicit boolean state rather than presentation text"):
		return
	app.favorite_save_succeeds = false
	favorite.pressed.emit()
	var favorite_status := shell.find_child("DiscoveryFavoriteStatus", true, false) as Label
	if not _expect(app.favorite and bool(panel.get("_is_favorite")) and favorite_status != null and favorite_status.text.contains("Disk is unavailable"), "a favorite persistence failure should keep state and show actionable inline detail"):
		return
	app.favorite_save_succeeds = true
	await _tap_action(&"ui_down")
	if not _expect(root.get_viewport().gui_get_focus_owner() == launch, "controller navigation should move predictably from Favorite to Race"):
		return
	launch.pressed.emit()
	if not _expect(app.launched.get("identity", {}) == app.identity and String(app.launched.get("preview_fingerprint", "")) == "0123456789abcdef", "confirmation should launch exactly the identity and preview fingerprint that were shown"):
		return

	shell.call("go_back")
	await _wait_frames(2)
	if not _expect(String(panel.get("_mode")) == "browser" and String(shell.get("_screen")) == "discovery", "Back from confirmation should return to the Discovery browser, not leave the menu"):
		return
	app.save_read_only = true
	panel.call("show_confirmation", app.identity)
	await _wait_frames(2)
	favorite = shell.find_child("DiscoveryFavorite", true, false) as Button
	favorite_status = shell.find_child("DiscoveryFavoriteStatus", true, false) as Label
	if not _expect(favorite.disabled and favorite_status.text.contains("read-only"), "read-only saves should disable favorite changes with an actionable inline explanation"):
		return
	panel.call("show_browser")
	shell.call("go_back")
	await _wait_frames(2)
	if not _expect(String(shell.get("_screen")) == "title", "Back from the Discovery browser should return to title"):
		return
	root.remove_child(shell)
	root.remove_child(app)
	shell.free()
	app.free()
	print("DISCOVERY_CONTROLLER_FLOW_TEST PASS")
	quit(0)


func _tap_action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _wait_frames(count: int) -> void:
	for _frame in count:
		await process_frame


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("DISCOVERY_CONTROLLER_FLOW_TEST FAIL: " + message)
	quit(1)
	return false