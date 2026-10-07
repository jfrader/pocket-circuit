extends SceneTree

const DIRECTOR_SCRIPT := preload("res://scripts/audio/audio_director.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
const LIVE_MUSIC := preload("res://scripts/audio/live_music.gd")


class StatsVehicle extends Node:
	var speed := 0.0
	var engine_load := 0.0
	var stats: VehicleStats = preload("res://data/vehicles/rustbug.tres")

	func get_engine_load() -> float:
		return engine_load

	func get_throttle_input() -> float:
		return engine_load


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	# Force the no-native path via the test seam. Real runs (and other tests)
	# keep the native path when the addon is present.
	LIVE_MUSIC._test_force_unavailable = true

	var director := DIRECTOR_SCRIPT.new()
	root.add_child(director)
	await process_frame

	if not _expect(not director.has_live_music(), "has_live_music() must be false when Gamestruments unavailable"):
		return
	var gm := director.get_node_or_null("GamestrumentsPlayer")
	if not _expect(gm == null, "GamestrumentsPlayer node must not be added on no-native path"):
		return
	if not _expect(not director.has_live_score(), "has_live_score() must be false without live music"):
		return
	if not _expect(director.get_live_seed().is_empty(), "live seed empty without native"):
		return
	if not _expect(director.get_live_section().is_empty(), "live section empty without native"):
		return

	# Director and generated paths remain fully usable.
	director.play_menu_music()
	director.play_race_music()
	director.begin_live_rotation(["grid", "drive"], 5.0)
	director.stop_live_rotation()
	director.advance_live_rotation()
	director.set_live_race_state("drive", 0.5, 0.1, false)
	if not _expect(director.cue_live_section("drive") == false, "cue_live must return false (no-op) without live"):
		return
	if not _expect(director.cue_live_section_timed("grid", 1.0) == false, "timed cue must return false without live"):
		return

	# Exercise generated one-shots / SFX and engine fallback by temporarily
	# disabling the headless guard (same pattern as audio_director_test).
	director.set("_headless", false)
	var vehicle := StatsVehicle.new()
	root.add_child(vehicle)
	director.set_local_vehicle(vehicle, "rustbug")
	await process_frame
	if not _expect(director.has_generated_sfx(&"impact"), "crash one-shot must still generate on no-native path"):
		return
	if not _expect(director.has_generated_sfx(&"boost"), "boost one-shot must still generate on no-native path"):
		return
	if not _expect(director.play_sfx(&"impact", 0.7), "generated crash must still play"):
		return
	if not _expect(director.play_sfx(&"boost", 0.6), "generated boost must still play"):
		return

	# Interface SFX (global) are always built regardless of live.
	if not _expect(director.play_sfx(&"ui_confirm", 0.4), "global interface SFX must still be available"):
		return

	# Cleanup seam and objects.
	LIVE_MUSIC._test_force_unavailable = false
	vehicle.queue_free()
	root.remove_child(director)
	director.free()
	await process_frame
	print("AUDIO_NATIVE_FALLBACK_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("AUDIO_NATIVE_FALLBACK_TEST FAIL: " + message)
	quit(1)
	return false
