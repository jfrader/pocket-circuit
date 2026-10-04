class_name RaceAssetPreloader
extends Node
## Menu-time background warm-up for the per-session race assets.
##
## Prewarms scenery outlines + the pool of vehicle visual keys (plain + rae-liveried
## variants via possible_field_visual_keys) so that any rolled quick-race or championship
## roster's motion sprites are already installed before prototype_race section 2.
## The first race after boot pays for two big... (rest unchanged).

signal completed

const TRACK_BUILDER := preload("res://scripts/race/track_builder_core.gd")
const TRACK_BUILDER_CATALOG := preload("res://scripts/race/track_builder_catalog.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
const RACE_PREPARATION := preload("res://scripts/race/race_preparation.gd")
const RACE_SCENE := "res://scenes/race/prototype_race.tscn"

var _app: Node
var _active := false
var _finished := false
var _texture_paths: Array[String] = []
var _texture_index := 0
var _vehicle_ids: Array[String] = []
var _vehicle_index := 0
var _worker: Node


func start(app: Node) -> void:
	_app = app
	if _active or _finished:
		return
	_active = true
	_texture_paths = _collect_texture_paths()
	_vehicle_ids = IDENTITIES.possible_field_visual_keys()
	call_deferred("_run")


func is_finished() -> bool:
	return _finished


func debug_metrics() -> Dictionary:
	return {
		"active": _active,
		"finished": _finished,
		"textures_remaining": maxi(0, _texture_paths.size() - _texture_index),
		"visual_keys_remaining": maxi(0, _vehicle_ids.size() - _vehicle_index),
		# "vehicles_remaining" kept for back-compat with any external prints
		"vehicles_remaining": maxi(0, _vehicle_ids.size() - _vehicle_index),
	}


func _collect_texture_paths() -> Array[String]:
	# Every full-path texture the generated-track catalog can place. This is the
	# union the race's own outline loop walks across all themes and story kits.
	var collected: Array[String] = []
	for path: String in TRACK_BUILDER.preparation_texture_paths(TRACK_BUILDER_CATALOG.catalog()):
		if ResourceLoader.exists(path) and not TRACK_BUILDER.has_prepared_outline_path(path):
			collected.append(path)
	return collected


func _run() -> void:
	await _warm_race_compilation()
	if not is_inside_tree():
		return
	await _precompute_outlines()
	if not is_inside_tree():
		return
	await _precompute_vehicles()
	if not is_inside_tree():
		return
	_active = false
	_finished = true
	completed.emit()


## Suspends the coroutine until the menu shell is visible again. This is the
## whole gate: as soon as a race begins (loading screen or race scene) the shell
## hides, so a quick race start always wins and the precompute never competes
## with a live load or rasterizes wheels during gameplay.
func _wait_until_menu() -> bool:
	while is_inside_tree() and is_instance_valid(_app) and _app.has_method("is_menu_visible") and not _app.is_menu_visible():
		await get_tree().process_frame
	return is_inside_tree()


## Compiles the race scene's scripts on a worker so `App._load_scene_resources`
## no longer pays GDScript compilation on its first dependency pass.
func _warm_race_compilation() -> void:
	if not await _wait_until_menu():
		return
	_worker = RACE_PREPARATION.new()
	_worker.name = "RaceAssetCompileWorker"
	add_child(_worker)
	await _worker.run_data_job(_load_scene_tree.bind(RACE_SCENE, {}))
	_worker.queue_free()
	_worker = null


static func _load_scene_tree(path: String, visited: Dictionary) -> Dictionary:
	# Mirrors App._load_scene_resources' recursive dependency walk, but on a
	# worker thread. `load()` compiles GDScript and is thread-safe; the compiled
	# resources land in the shared loader cache for the race to reuse.
	if visited.has(path):
		return {}
	visited[path] = true
	for dependency in ResourceLoader.get_dependencies(path):
		_load_scene_tree(String(dependency).split("::")[-1], visited)
	load(path)
	return {}


func _precompute_outlines() -> void:
	_worker = RACE_PREPARATION.new()
	_worker.name = "RaceAssetOutlineWorker"
	add_child(_worker)
	for path: String in _texture_paths:
		if not await _wait_until_menu():
			return
		_texture_index += 1
		if TRACK_BUILDER.has_prepared_outline_path(path):
			continue
		var texture := load(path) as Texture2D
		if texture == null:
			continue
		# Image decompression is not worker-safe and must stay on the main
		# thread; only the pixel scan runs on the worker.
		var image := texture.get_image()
		if image == null or image.is_empty():
			continue
		if TRACK_BUILDER.has_prepared_outline(texture):
			continue
		var outline: Dictionary = await _worker.run_data_job(TRACK_BUILDER.compute_alpha_outline.bind(image, texture.get_width(), texture.get_height()))
		if outline.is_empty():
			continue
		TRACK_BUILDER.install_prepared_outline(texture, outline)
	_worker.queue_free()
	_worker = null


func _precompute_vehicles() -> void:
	await _precompute_motions_for(_vehicle_ids, true)


## Called from App.prewarm_championship_event (and potentially other hooks) to
## ensure the exact roster + selected vehicle looks are motion-warmed even if
## the full-pool precompute has not finished or for emphasis on known set.
## Idempotent: plan_for_key returns no jobs for already-installed keys.
## Work only proceeds while menu is visible; one key at a time on data worker.
func prewarm_additional(keys: Array) -> void:
	if keys.is_empty():
		return
	call_deferred("_warm_additional_deferred", keys)


func _warm_additional_deferred(raw_keys: Array) -> void:
	if not is_inside_tree():
		return
	var keys: Array[String] = []
	for k in raw_keys:
		var sk := String(k)
		if not sk.is_empty() and not keys.has(sk):
			keys.append(sk)
	if keys.is_empty():
		return
	if not await _wait_until_menu():
		return
	await _precompute_motions_for(keys, false)


## Race-start warm-up: the rolled roster is only known when the player commits,
## so its missing looks are rendered immediately on a dedicated worker while the
## loading screen runs. Not menu-gated; the race path still renders anything the
## pass does not reach, and both installs are idempotent.
var _roster_worker: Node
var _roster_keys: Array[String] = []


func prewarm_roster(keys: Array) -> void:
	if keys.is_empty():
		return
	for raw_key: Variant in keys:
		var visual_key := String(raw_key)
		if not visual_key.is_empty() and not _roster_keys.has(visual_key):
			_roster_keys.append(visual_key)
	if _roster_worker == null and is_inside_tree():
		_run_roster_pass()


func _run_roster_pass() -> void:
	_roster_worker = RACE_PREPARATION.new()
	_roster_worker.name = "RaceRosterMotionWorker"
	add_child(_roster_worker)
	while not _roster_keys.is_empty():
		var visual_key: String = _roster_keys.pop_front()
		var plan := IDENTITIES.motion_preparation_plan_for_key(visual_key)
		if (plan["jobs"] as Array).is_empty():
			continue
		var rendered: Dictionary = await _roster_worker.run_data_job(IDENTITIES.render_motion_plan.bind(plan))
		if rendered.is_empty():
			continue
		var jobs: Array = rendered["jobs"]
		var images: Array = rendered["images"]
		for index in jobs.size():
			IDENTITIES.install_motion_image_for_key(visual_key, jobs[index], images[index])
	if _roster_worker != null:
		_roster_worker.queue_free()
	_roster_worker = null


## Shared implementation. count_toward_index only for the boot full-pool pass.
## One pass at a time: the boot pool already covers every field look, so a
## concurrent emphasis request is skipped rather than racing the same worker.
func _precompute_motions_for(keys: Array[String], count_toward_index: bool = true) -> void:
	if _worker != null:
		return
	_worker = RACE_PREPARATION.new()
	_worker.name = "RaceAssetMotionWorker"
	add_child(_worker)
	for visual_key: String in keys:
		if not await _wait_until_menu():
			break
		if count_toward_index:
			_vehicle_index += 1
		var plan := IDENTITIES.motion_preparation_plan_for_key(visual_key)
		if (plan["jobs"] as Array).is_empty():
			continue
		var rendered: Dictionary = await _worker.run_data_job(IDENTITIES.render_motion_plan.bind(plan))
		if rendered.is_empty():
			continue
		var jobs: Array = rendered["jobs"]
		var images: Array = rendered["images"]
		for index in jobs.size():
			IDENTITIES.install_motion_image_for_key(visual_key, jobs[index], images[index])
	_worker.queue_free()
	_worker = null
