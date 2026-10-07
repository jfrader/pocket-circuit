class_name LiveMusic
extends RefCounted

## Thin adapter over the Gamestruments `GamestrumentsPlayer` extension.
##
## The engine owns every musical transition. This module only declares a seed
## and a profile, cues sections, and runs the phase rotation. One score is
## generated per seed and reused.

const RECIPE := "racing"
## The seeded composer is the whole racing pool (grooves, peaks, breather, and
## the defeat/recovery/wrong-way signals) with a per-seed arrangement surface.
const ARRANGEMENT := "seeded"
const PROJECT_SECRET := "guri-pc-dev-salt"
const VOICES := {
	"melody_voice": "pluck",
	"harmony_voice": "warm",
	"drive_voice": "pluck",
	"bass_voice": "bass",
}
const SILENCE_DB := -80.0
const PAUSED_DB := -9.0

## Owning context. Only the race ducks the music while paused.
var context: StringName = &"menu"

var _host: Node
var _player: Node
## The generate seed of the loaded score. Empty means no score yet; a repeated
## seed is a no-op so a context change never regenerates.
var _seed := ""
var _generations := 0
## Last section handed to the engine.
var _requested := ""
var _paused := false
var _deck: Array[String] = []
var _deck_index := 0
var _dwell := 12.0
var _dwell_left := 0.0
var _rotating := false

## How long a section must play before a different one may replace it. Moving
## quickly between screens (results, menu, play again) asks for a new section far
## faster than music can settle, and switching every time never sounds composed.
## Smoothness is worth more than matching the screen exactly, so a too-soon
## request is dropped and the current section keeps playing.
const SECTION_CHANGE_DWELL := 6.0
var _section_elapsed := 0.0

## Test seam only. When true, LiveMusic and AudioDirector pretend the
## Gamestruments GDExtension is absent even if ClassDB sees the class.
static var _test_force_unavailable := false


static func is_gamestruments_available() -> bool:
	if _test_force_unavailable:
		return false
	return ClassDB.class_exists("GamestrumentsPlayer")


func _init(host: Node) -> void:
	_host = host
	if not LiveMusic.is_gamestruments_available():
		_player = null
		return
	_player = ClassDB.instantiate("GamestrumentsPlayer")
	_player.name = "GamestrumentsPlayer"
	_player.set("project_secret", PROJECT_SECRET)
	_player.set("recipe", RECIPE)
	_player.set("arrangement", ARRANGEMENT)
	_player.set("autoplay", false)
	for key: String in VOICES:
		_player.set(key, VOICES[key])
	_host.add_child(_player)
	_apply_volume()


## Generate `seed` if it is not the loaded one, opening directly on the requested
## section so a seed handoff does not stack a second section transition. Hold its
## tour form so the game drives every later phase.
func play(seed: String, profile: Dictionary, opening: String) -> void:
	if _player == null:
		return
	if _seed != seed:
		_apply_profile(profile)
		if not bool(_player.call("generate", seed, opening)):
			push_error("Gamestruments generation failed for seed " + seed)
			return
		_seed = seed
		_generations += 1
		_requested = opening
		_player.call("set_form_hold", true)
		_apply_volume()
		return
	cue(opening)


func has_score() -> bool:
	return not _seed.is_empty()


func seed() -> String:
	return _seed


func generations() -> int:
	return _generations


func requested_section() -> String:
	return _requested


func current_section() -> String:
	if _player == null or not _player.has_method("get_current_section"):
		return ""
	return String(_player.call("get_current_section"))


## Cue a known section. `hold_seconds` keeps the rotation off it for at least
## that long, so a sting or reprise is not stepped on immediately.
func cue(section: String, hold_seconds := 0.0) -> bool:
	if _player == null or not has_score() or not _player.has_method("cue_section"):
		return false
	# The first cue of a score is never held back, and asking again for the section
	# already playing is not a change.
	var changing := not _requested.is_empty() and section != _requested
	if changing and _section_elapsed < SECTION_CHANGE_DWELL:
		return false
	if not bool(_player.call("cue_section", section)):
		return false
	if changing:
		_section_elapsed = 0.0
	_requested = section
	# Keep the rotation clock parked on the section that is actually playing, so
	# a manual sting resumes the deck from there instead of an old pointer.
	var index := _deck.find(section, _deck_index)
	if index < 0:
		index = _deck.find(section)
	if index >= 0:
		_deck_index = index
	if hold_seconds > 0.0:
		_dwell_left = maxf(_dwell_left, hold_seconds)
	return true


func set_race_state(phase: String, intensity: float, pressure: float, final_lap: bool, finish_result := "") -> bool:
	if _player == null or not has_score() or not _player.has_method("set_race_state"):
		return false
	# Phase requests (from set_race_state) are protected by the same dwell/drop
	# as cue(): newest request dropped (not held) while inside SECTION_CHANGE_DWELL.
	# Same-phase request is never a change and does not reset or restart.
	var changing := not _requested.is_empty() and phase != _requested
	if changing and _section_elapsed < SECTION_CHANGE_DWELL:
		return false
	if not bool(_player.call("set_race_state", phase, intensity, pressure, final_lap, finish_result)):
		return false
	if changing:
		_section_elapsed = 0.0
	_requested = phase
	return true


## Start or replace the phase rotation. `first` overrides the opening phase.
func rotate(deck: Array[String], dwell: float, first := "") -> void:
	_deck = deck.duplicate()
	_deck_index = 0
	_dwell = maxf(1.0, dwell)
	_dwell_left = _dwell
	_rotating = not _deck.is_empty()
	var opening := first
	if opening.is_empty() and not _deck.is_empty():
		opening = _deck[0]
	if not opening.is_empty():
		cue(opening)


func stop_rotation() -> void:
	_rotating = false


## Step the rotation now, but only once the current phase has had at least half
## its dwell, so lap boundaries and position changes do not churn transitions.
func advance_rotation() -> void:
	if _rotating and _dwell_left <= _dwell * 0.5:
		_step()


func set_paused(paused: bool) -> void:
	_paused = paused
	_apply_volume()


## Advance the phase rotation clock. Called from the director's `_process`.
func tick(delta: float) -> void:
	# Section changes happen while the rotation is parked or paused (results, menu),
	# so this clock cannot sit behind that early return.
	_section_elapsed += maxf(delta, 0.0)
	if not _rotating or _paused or _dwell_left <= 0.0:
		return
	_dwell_left = maxf(_dwell_left - delta, 0.0)
	if _dwell_left <= 0.0:
		_step()


func _step() -> void:
	_deck_index = (_deck_index + 1) % _deck.size()
	_dwell_left = _dwell
	var next := _deck[_deck_index]
	# The held score is already looping that section; cueing it again would
	# restart a slow opening.
	if next != _requested:
		cue(next)


func _apply_profile(profile: Dictionary) -> void:
	_player.set("style", String(profile.get("style", "funk")))
	_player.set("energy", float(profile.get("energy", 0.62)))
	_player.set("complexity", float(profile.get("complexity", 0.60)))
	_player.set("brightness", float(profile.get("brightness", 0.52)))
	_player.set("syncopation", float(profile.get("syncopation", 0.70)))


func _apply_volume() -> void:
	if _player == null:
		return
	var db := 0.0
	if _paused and context == &"race":
		db += PAUSED_DB
	if _seed.is_empty():
		db = SILENCE_DB
	for child: Node in _player.get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).volume_db = db
