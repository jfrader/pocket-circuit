extends SceneTree

## A new circuit generates its own score. Leaving the race for the menu does
## not. That change asks the loaded score for the garage phase.

const AUDIO_DIRECTOR := preload("res://scripts/audio/audio_director.gd")
const SILENCE_DB := -80.0


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

	# A seed swap must crossfade, not cut. The extension rewinds its transport on
	# generate(), so the old score has to fade out under the new one: both players
	# exist and are audible for the fade window.
	var outgoing := director.get_node_or_null("GamestrumentsPlayerOutgoing")
	var incoming := director.get_node_or_null("GamestrumentsPlayer")
	if not _expect(outgoing != null, "a seed swap should keep the old score as a fading player, not cut it"):
		return
	if not _expect(incoming != null and incoming != outgoing, "the incoming score should be a separate live player"):
		return
	# Step partway through the fade by hand: headless frames are too short to
	# advance it on wall-clock time. Both scores must be audible at once.
	director.call("_update_live_volume", 0.2)
	director.call("_update_live_volume", 0.2)
	if not _expect(_music_child_db(outgoing) > SILENCE_DB and _music_child_db(incoming) > SILENCE_DB, "both scores should be audible during the crossfade"):
		return
	# Finish the fade: the old score is released and the new one holds full level.
	for _step in 6:
		director.call("_update_live_volume", 0.2)
	await process_frame
	if not _expect(not is_instance_valid(outgoing), "the outgoing score should be released once the crossfade lands"):
		return
	if not _expect(director.get_node_or_null("GamestrumentsPlayer") == incoming, "the incoming score should be the live player after the crossfade"):
		return
	if not _expect(is_zero_approx(_music_child_db(incoming)), "the live score should sit at full level once the crossfade ends"):
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


## The level of the score player's own stream, used to tell a live score from a
## fading one.
func _music_child_db(player: Node) -> float:
	if not is_instance_valid(player):
		return -200.0
	for child: Node in player.get_children():
		if child is AudioStreamPlayer:
			return (child as AudioStreamPlayer).volume_db
	return -200.0


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("MUSIC_TRANSITION_TEST FAIL: " + message)
	quit(1)
	return false
