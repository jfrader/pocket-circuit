extends SceneTree

## A new circuit generates its own score. Leaving the race for the menu does
## not. That change asks the loaded score for the garage phase.

const AUDIO_DIRECTOR := preload("res://scripts/audio/audio_director.gd")


class FakeApp extends Node:
	var current_race_session: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var director := AUDIO_DIRECTOR.new()
	root.add_child(director)
	await process_frame
	director.call("ensure_buses")

	director.call("play_menu_music")
	await process_frame
	if not _expect(bool(director.call("get_music_context") == &"menu"), "a cold start should report the menu context"):
		return

	if not ClassDB.class_exists("GamestrumentsPlayer"):
		push_error("MUSIC_TRANSITION_TEST FAIL: GamestrumentsPlayer extension is required; no WAV fallback")
		quit(1)
		return

	if not _expect(bool(director.call("has_live_score")), "a cold menu start should load a live score"):
		return
	var menu_seed := String(director.call("get_live_seed"))
	if not _expect(menu_seed.begins_with("pc_menu_") and menu_seed != "pc_menu", "a cold start should generate a fresh menu piece"):
		return
	if not _expect(int(director.call("get_live_score_generations")) == 1, "a cold start should generate exactly one score"):
		return

	_set_race_session(director, "kitchen", "classic", 4242, "standard")
	director.call("play_race_music")
	await process_frame
	if not _expect(int(director.call("get_live_score_generations")) == 2, "a new circuit should generate its own score"):
		return
	var track_seed := String(director.call("get_live_seed"))
	if not _expect(track_seed != menu_seed, "the circuit score seed should differ from the menu score"):
		return
	director.call("play_race_music")
	await process_frame
	if not _expect(int(director.call("get_live_score_generations")) == 2, "re-entering the same circuit must reuse its score"):
		return
	if not _expect(String(director.call("get_live_seed")) == track_seed, "a circuit score must be reproducible from its track identity"):
		return

	_set_race_session(director, "workshop", "wide", 4243, "long")
	director.call("play_race_music")
	await process_frame
	if not _expect(int(director.call("get_live_score_generations")) == 3, "a different circuit should generate a different score"):
		return
	if not _expect(String(director.call("get_live_seed")) != track_seed, "different circuits must not share a seed"):
		return

	var before_menu := int(director.call("get_live_score_generations"))
	var race_seed := String(director.call("get_live_seed"))
	director.call("play_menu_music")
	await process_frame
	if not _expect(int(director.call("get_live_score_generations")) == before_menu, "returning to the menu must not regenerate the score"):
		return
	if not _expect(String(director.call("get_live_seed")) == race_seed, "returning to the menu must keep the score that is already playing"):
		return
	if not _expect(String(director.call("get_live_requested_section")) == "grid", "returning to the menu should ask the engine for the grid phase"):
		return
	director.call("play_menu_music")
	await process_frame
	if not _expect(int(director.call("get_live_score_generations")) == before_menu, "re-entering the menu must reuse its score"):
		return

	director.queue_free()
	await process_frame
	print("MUSIC_TRANSITION_TEST PASS")
	quit(0)


func _set_race_session(_director: Node, theme: String, room: String, seed: int, tier: String) -> void:
	var app := root.get_node_or_null("App")
	if app == null:
		app = FakeApp.new()
		app.name = "App"
		root.add_child(app)
	app.set("current_race_session", {
		"event_id": "circuit_%s_%s_%d" % [theme, room, seed],
		"event": {"theme": theme, "room": room, "seed": seed, "length_tier": tier},
	})


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("MUSIC_TRANSITION_TEST FAIL: " + message)
	quit(1)
	return false
