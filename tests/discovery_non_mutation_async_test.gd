extends SceneTree

const IDENTITIES := preload("res://scripts/race/generated_circuit_identity.gd")

class FrameTicker extends Node:
	var frames := 0

	func _process(_delta: float) -> void:
		frames += 1


const PROTECTED_KEYS: Array[String] = [
	"championship_started",
	"championship_circuit",
	"best_event_finishes",
	"best_event_points",
	"completed_events",
	"completed_acts",
	"unlocked_vehicles",
	"mastery_circuit_metrics",
	"mastery_records",
	"personal_ghosts",
	"ending_seen",
]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload should be available"):
		return
	var save: Dictionary = app.call("get_save_data")
	save["championship_started"] = true
	save["best_event_finishes"] = {"kitchen_crumb_rush": 1}
	save["best_event_points"] = {"kitchen_crumb_rush": 10}
	save["completed_events"] = ["kitchen_crumb_rush"]
	save["mastery_records"] = [{"sentinel": "mastery"}]
	save["personal_ghosts"] = [{"sentinel": "ghost"}]
	app.set("_save_data", save)
	var protected_before := _protected(save)

	var ticker := FrameTicker.new()
	root.add_child(ticker)
	var identity := IDENTITIES.create(&"office", IDENTITIES.room_for_route_seed(778899), 778899, true, 3)
	var preview: Dictionary = await app.call("prepare_circuit_preview", identity)
	if not _expect(ticker.frames > 0 and not preview.is_empty(), "expensive route preparation should yield frames while a low-priority data job runs"):
		return
	if not _expect(String(preview["identity_fingerprint"]) == String(identity["fingerprint"]) and String(preview["loaded_fingerprint"]).length() == 16, "an asynchronous preview should carry both confirmed identity and loaded-route fingerprints"):
		return
	if not _expect(_protected(app.call("get_save_data")) == protected_before, "preview preparation must not mutate any championship or mastery data"):
		return
	if not _expect(not app.call("start_discovery_race", identity, "rustbug", "") and app.call("get_current_race_session").is_empty(), "an imported identity must not launch before a verified preview is confirmed"):
		return

	var launched: bool = app.call("start_discovery_race", identity, "rustbug", String(preview["loaded_fingerprint"]))
	var session: Dictionary = app.call("get_current_race_session")
	if not _expect(launched and String(session.get("mode", "")) == "discovery" and bool(session.get("event", {}).get("reverse", false)) and session.get("event", {}).get("generated_circuit_identity", {}) == identity and String(session.get("event", {}).get("preview_fingerprint", "")) == String(preview["loaded_fingerprint"]), "confirmed import should launch only a reverse discovery exhibition with the exact preview identity"):
		return
	if not _expect(_protected(app.call("get_save_data")) == protected_before, "launching discovery may add history but must preserve championship identities, points, unlocks, mastery, and ghosts"):
		return
	if not _expect(app.call("report_race_result", 1, 60.0, [], false, {}) and _protected(app.call("get_save_data")) == protected_before, "discovery results must never enter championship or mastery result persistence"):
		return
	var library: Dictionary = app.call("get_circuit_library")
	if not _expect(not (library["history"] as Array).is_empty() and library["history"][0] == identity, "launching an imported generated circuit should record it in recent history"):
		return

	if is_instance_valid(app.get("_loading_screen")):
		(app.get("_loading_screen") as Node).queue_free()
	app.set("_transitioning_to_race", false)
	root.remove_child(ticker)
	ticker.free()
	print("DISCOVERY_NON_MUTATION_ASYNC_TEST PASS")
	quit(0)


func _protected(save: Dictionary) -> Dictionary:
	var output := {}
	for key: String in PROTECTED_KEYS:
		output[key] = save.get(key).duplicate(true) if save.get(key) is Array or save.get(key) is Dictionary else save.get(key)
	return output


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("DISCOVERY_NON_MUTATION_ASYNC_TEST FAIL: " + message)
	quit(1)
	return false