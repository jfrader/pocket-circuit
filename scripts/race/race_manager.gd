class_name RaceManager
extends Node

signal checkpoint_passed(checkpoint_index: int)
signal lap_completed(lap: int)
signal race_finished(total_time: float)
signal countdown_started
signal countdown_tick(value: String)
signal race_started
signal racer_checkpoint_passed(racer: Node2D, checkpoint_index: int)
signal racer_lap_completed(racer: Node2D, lap: int)
signal racer_finished(racer: Node2D, position: int, total_time: float)
signal position_changed(racer: Node2D, position: int, racer_count: int)
signal wrong_way_changed(racer: Node2D, wrong_way: bool)
signal results_ready(results: Array)
signal racer_recovered(racer: Node2D)

@export_range(1, 99) var laps_to_finish: int = 3
@export_range(0.0, 30.0, 0.5) var finish_grace_seconds: float = 8.0

var direction: StringName = &"forward"
var checkpoints: Array[Node] = []
var current_checkpoint_index: int = 0
var lap_count: int = 0
var race_time: float = 0.0
var is_running: bool = false
var last_recovery_transform: Transform2D = Transform2D.IDENTITY

var _racers: Dictionary = {}
var _registration_order: Array[Node2D] = []
var _finish_order: Array[Node2D] = []
var _checkpoint_by_index: Dictionary = {}
var _checkpoint_order: Dictionary = {}
var _player_vehicle: Node2D
var _prepared: bool = false
var _finish_grace_remaining: float = -1.0
var _results_finalized: bool = false

# ── Route reference (wrong-way tangent seam) ─────────────────────────
# A closed polyline describing the actual drivable route, in global coords and
# forward (checkpoint-index) order. Populated once by the race scene from the
# generated/authored racing line. Used to judge wrong-way motion against the
# real route tangent instead of the checkpoint chord, which lies on long curved
# sections and reverses on hairpins.
var _route_points: PackedVector2Array = PackedVector2Array()
var _route_cumulative: PackedFloat32Array = PackedFloat32Array()
var _route_length := 0.0
var _route_checkpoint_arc: Dictionary = {}
const ROUTE_SECTION_MARGIN := 200.0


func _ready() -> void:
	call_deferred("_initialize_race")


func _process(delta: float) -> void:
	advance_race_time(delta)


func _initialize_race() -> void:
	if checkpoints.is_empty():
		configure_checkpoints(get_tree().get_nodes_in_group("track_checkpoints"))
	var player := get_tree().get_first_node_in_group("player_vehicle") as Node2D
	if player and not _racers.has(player):
		register_racer(player, _read_identity(player, &"driver_display_name", "Driver"), _read_identity(player, &"vehicle_display_name", "Rustbug"), true)
	for node: Node in get_tree().get_nodes_in_group("race_vehicle"):
		var racer := node as Node2D
		if racer and not _racers.has(racer):
			register_racer(racer, _read_identity(racer, &"driver_display_name", str(racer.name)), _read_identity(racer, &"vehicle_display_name", "Rustbug"), racer == player)
	if not _prepared:
		prepare_race()


func configure_checkpoints(ordered_checkpoints: Array) -> void:
	checkpoints.clear()
	for checkpoint: Node in ordered_checkpoints:
		checkpoints.append(checkpoint)
	checkpoints.sort_custom(_checkpoint_precedes)
	_checkpoint_by_index.clear()
	_checkpoint_order.clear()
	for order in checkpoints.size():
		var checkpoint := checkpoints[order]
		var checkpoint_index := int(checkpoint.get("checkpoint_index"))
		_checkpoint_by_index[checkpoint_index] = checkpoint
		_checkpoint_order[checkpoint_index] = order
	_prepared = false
	_refresh_route_checkpoint_arcs()


func set_reverse_direction(enabled: bool) -> void:
	var new_direction: StringName = &"reverse" if enabled else &"forward"
	if direction == new_direction:
		return
	direction = new_direction
	if not checkpoints.is_empty():
		configure_checkpoints(checkpoints.duplicate())


func is_reverse_direction() -> bool:
	return direction == &"reverse"


func register_racer(
		vehicle: Node2D,
		driver_name: String,
		vehicle_name: String,
		is_player: bool = false
) -> void:
	if _racers.has(vehicle):
		var existing: Dictionary = _racers[vehicle]
		existing["driver_name"] = driver_name
		existing["vehicle_name"] = vehicle_name
		existing["is_player"] = is_player or bool(existing["is_player"])
		_racers[vehicle] = existing
	else:
		var state := {
			"vehicle": vehicle,
			"driver_name": driver_name,
			"vehicle_name": vehicle_name,
			"is_player": is_player,
			"expected_checkpoint": _first_racing_checkpoint_index(),
			"last_checkpoint_order": 0,
			"lap": 0,
			"elapsed": 0.0,
			"finished": false,
			"dnf": false,
			"finish_position": 0,
			"finish_time": 0.0,
			"recovery_transform": vehicle.global_transform,
			"progress": 0.0,
			"position": _registration_order.size() + 1,
			"wrong_way": false,
			"wrong_way_time": 0.0,
			"registration_index": _registration_order.size(),
		}
		_racers[vehicle] = state
		_registration_order.append(vehicle)
	if is_player:
		_player_vehicle = vehicle
		_sync_player_compatibility()
	_prepared = false


func prepare_race() -> void:
	race_time = 0.0
	is_running = false
	_finish_order.clear()
	_finish_grace_remaining = -1.0
	_results_finalized = false
	var first_checkpoint := _first_racing_checkpoint_index()
	for vehicle: Node2D in _registration_order:
		if not is_instance_valid(vehicle):
			continue
		var state: Dictionary = _racers[vehicle]
		state["expected_checkpoint"] = first_checkpoint
		state["last_checkpoint_order"] = 0
		state["lap"] = 0
		state["elapsed"] = 0.0
		state["finished"] = false
		state["dnf"] = false
		state["finish_position"] = 0
		state["finish_time"] = 0.0
		state["recovery_transform"] = vehicle.global_transform
		state["progress"] = 0.0
		state["position"] = int(state["registration_index"]) + 1
		state["wrong_way"] = false
		state["wrong_way_time"] = 0.0
		_racers[vehicle] = state
		_set_vehicle_controls_locked(vehicle, true)
	_prepared = true
	_sync_player_compatibility()
	refresh_rankings()


func begin_countdown() -> void:
	prepare_race()
	countdown_started.emit()


func report_countdown_tick(value: String) -> void:
	countdown_tick.emit(value)


func start_race() -> void:
	if not _prepared:
		prepare_race()
	is_running = true
	for vehicle: Node2D in _registration_order:
		if is_instance_valid(vehicle):
			_set_vehicle_controls_locked(vehicle, false)
	race_started.emit()


func stop_race() -> void:
	is_running = false
	for vehicle: Node2D in _registration_order:
		if is_instance_valid(vehicle):
			_set_vehicle_controls_locked(vehicle, true)


func advance_race_time(delta: float) -> void:
	if not is_running:
		return
	race_time += delta
	for vehicle: Node2D in _registration_order:
		if not is_instance_valid(vehicle):
			continue
		var state: Dictionary = _racers[vehicle]
		if not bool(state["finished"]):
			state["elapsed"] = float(state["elapsed"]) + delta
			_update_spatial_progress(vehicle, state, delta)
			_racers[vehicle] = state
	_refresh_positions()
	_sync_player_compatibility()
	if _finish_grace_remaining >= 0.0:
		_finish_grace_remaining -= delta
		if _finish_grace_remaining <= 0.0:
			finalize_remaining_racers_as_dnf()


func report_checkpoint(checkpoint: Area2D, body: Node2D) -> bool:
	if not is_running or not _racers.has(body):
		return false
	var state: Dictionary = _racers[body]
	if bool(state["finished"]):
		return false
	var checkpoint_index := int(checkpoint.get("checkpoint_index"))
	if checkpoint_index != int(state["expected_checkpoint"]):
		_set_wrong_way(body, state, true)
		_racers[body] = state
		return false

	_set_wrong_way(body, state, false)
	state["wrong_way_time"] = 0.0
	state["recovery_transform"] = _get_recovery_transform(checkpoint)
	state["last_checkpoint_order"] = int(_checkpoint_order.get(checkpoint_index, 0))
	racer_checkpoint_passed.emit(body, checkpoint_index)
	if body == _player_vehicle:
		checkpoint_passed.emit(checkpoint_index)

	if bool(checkpoint.get("is_finish_line")):
		state["lap"] = int(state["lap"]) + 1
		state["last_checkpoint_order"] = 0
		state["expected_checkpoint"] = _first_racing_checkpoint_index()
		racer_lap_completed.emit(body, int(state["lap"]))
		if body == _player_vehicle:
			lap_completed.emit(int(state["lap"]))
		if int(state["lap"]) >= laps_to_finish:
			_finish_racer(body, state)
			return true
	else:
		state["expected_checkpoint"] = get_checkpoint_after_index(checkpoint_index)

	_racers[body] = state
	refresh_rankings()
	_sync_player_compatibility()
	return true


func refresh_rankings() -> Array[Node2D]:
	for vehicle: Node2D in _registration_order:
		if not is_instance_valid(vehicle):
			continue
		var state: Dictionary = _racers[vehicle]
		_update_spatial_progress(vehicle, state, 0.0)
		_racers[vehicle] = state
	return _refresh_positions()


func get_rankings() -> Array[Node2D]:
	var rankings: Array[Node2D] = []
	for vehicle: Node2D in _registration_order:
		if is_instance_valid(vehicle):
			rankings.append(vehicle)
	rankings.sort_custom(_racer_precedes)
	return rankings


func get_results() -> Array:
	var results: Array = []
	var rankings := get_rankings()
	for index in rankings.size():
		var vehicle := rankings[index]
		var state: Dictionary = _racers[vehicle]
		results.append({
			"position": index + 1,
			"driver_name": String(state["driver_name"]),
			"vehicle_name": String(state["vehicle_name"]),
			"finished": bool(state["finished"]),
			"dnf": bool(state.get("dnf", false)),
			"time": float(state["finish_time"]) if bool(state["finished"]) else float(state["elapsed"]),
			"vehicle": vehicle,
		})
	return results


func get_racer_state(vehicle: Node2D) -> Dictionary:
	return _racers[vehicle].duplicate() if _racers.has(vehicle) else {}


func get_racer_position(vehicle: Node2D) -> int:
	return int(_racers[vehicle]["position"]) if _racers.has(vehicle) else 0


func get_racer_progress(vehicle: Node2D) -> float:
	return float(_racers[vehicle]["progress"]) if _racers.has(vehicle) else 0.0


func get_racer_count() -> int:
	return _registration_order.size()


func get_expected_checkpoint(vehicle: Node2D) -> int:
	return int(_racers[vehicle]["expected_checkpoint"]) if _racers.has(vehicle) else -1


func is_racer_finished(vehicle: Node2D) -> bool:
	return bool(_racers[vehicle]["finished"]) if _racers.has(vehicle) else false


func is_racer_wrong_way(vehicle: Node2D) -> bool:
	return bool(_racers[vehicle]["wrong_way"]) if _racers.has(vehicle) else false


func report_recovery(vehicle: Node2D) -> void:
	if not _racers.has(vehicle):
		return
	var state: Dictionary = _racers[vehicle]
	state["wrong_way_time"] = 0.0
	_set_wrong_way(vehicle, state, false)
	_racers[vehicle] = state
	racer_recovered.emit(vehicle)


func finalize_remaining_racers_as_dnf() -> void:
	if _results_finalized:
		return
	var rankings := get_rankings()
	for vehicle: Node2D in rankings:
		var state: Dictionary = _racers[vehicle]
		if bool(state["finished"]):
			continue
		state["finished"] = true
		state["dnf"] = true
		state["finish_position"] = _finish_order.size() + 1
		state["finish_time"] = float(state["elapsed"])
		_racers[vehicle] = state
		_finish_order.append(vehicle)
		_set_vehicle_controls_locked(vehicle, true)
		racer_finished.emit(vehicle, int(state["finish_position"]), float(state["finish_time"]))
	_finish_grace_remaining = -1.0
	_refresh_positions()
	_emit_results_if_complete()


func get_ordered_checkpoints() -> Array[Node]:
	return checkpoints.duplicate()


func configure_route_reference(points: PackedVector2Array) -> void:
	## Route-reference seam. The race scene supplies the actual drivable route
	## (generated/authored racing line in global coords, forward order) once.
	## Wrong-way detection then follows the real route tangent within the active
	## checkpoint section instead of the checkpoint chord, which lies on long
	## curved sections and reverses across hairpins.
	_route_points = PackedVector2Array()
	_route_cumulative = PackedFloat32Array()
	_route_length = 0.0
	_route_checkpoint_arc.clear()
	if points.size() < 2:
		return
	_route_points = points.duplicate()
	_route_cumulative.resize(_route_points.size())
	for index in _route_points.size():
		_route_cumulative[index] = _route_length
		_route_length += _route_points[index].distance_to(_route_points[(index + 1) % _route_points.size()])
	_refresh_route_checkpoint_arcs()


func has_route_reference() -> bool:
	return _route_points.size() >= 2


func _refresh_route_checkpoint_arcs() -> void:
	_route_checkpoint_arc.clear()
	if _route_points.size() < 2:
		return
	for checkpoint: Node in checkpoints:
		var arc := _nearest_route_arc((checkpoint as Node2D).global_position)
		if arc >= 0.0:
			_route_checkpoint_arc[int(checkpoint.get("checkpoint_index"))] = arc


func _nearest_route_arc(position: Vector2) -> float:
	var nearest := _nearest_route_segment(position, 0.0, _route_length)
	if int(nearest["index"]) < 0:
		return -1.0
	var index := int(nearest["index"])
	var segment_length := _route_points[index].distance_to(_route_points[(index + 1) % _route_points.size()])
	return fposmod(_route_cumulative[index] + segment_length * float(nearest["fraction"]), _route_length)


func get_route_forward_direction(position: Vector2, previous_checkpoint_index: int, expected_checkpoint_index: int) -> Vector2:
	## Forward (race-direction) unit tangent at the nearest route point inside
	## the current checkpoint section. Vector2.ZERO when the section cannot be
	## resolved, so the caller falls back to the direct checkpoint chord.
	if _route_points.size() < 2:
		return Vector2.ZERO
	var previous_arc := float(_route_checkpoint_arc.get(previous_checkpoint_index, -1.0))
	var expected_arc := float(_route_checkpoint_arc.get(expected_checkpoint_index, -1.0))
	if previous_arc < 0.0 or expected_arc < 0.0:
		return Vector2.ZERO
	# Directed arc window from the previous checkpoint to the expected one in the
	# race direction, expanded by the margin. Reverse races travel decreasing
	# arc, so the window runs expected_arc -> previous_arc there.
	var lo := previous_arc - ROUTE_SECTION_MARGIN
	var hi := expected_arc + ROUTE_SECTION_MARGIN
	if is_reverse_direction():
		lo = expected_arc - ROUTE_SECTION_MARGIN
		hi = previous_arc + ROUTE_SECTION_MARGIN
	var nearest := _nearest_route_segment(position, lo, hi)
	if int(nearest["index"]) < 0:
		return Vector2.ZERO
	var index := int(nearest["index"])
	var tangent := (_route_points[(index + 1) % _route_points.size()] - _route_points[index]).normalized()
	if is_reverse_direction():
		tangent = -tangent
	return tangent


func _nearest_route_segment(position: Vector2, arc_lo: float, arc_hi: float) -> Dictionary:
	## Nearest route segment whose arc falls within [arc_lo, arc_hi] on the
	## closed loop (may wrap). A window spanning the whole loop searches it all.
	var best_index := -1
	var best_fraction := 0.0
	var best_distance := INF
	var count := _route_points.size()
	for index in count:
		if arc_hi - arc_lo < _route_length and not _arc_in_window(_route_cumulative[index], arc_lo, arc_hi):
			continue
		var from := _route_points[index]
		var to := _route_points[(index + 1) % count]
		var segment := to - from
		var length_squared := segment.length_squared()
		var fraction := 0.0
		if length_squared > 0.001:
			fraction = clampf((position - from).dot(segment) / length_squared, 0.0, 1.0)
		var nearest := from + segment * fraction
		var distance := position.distance_squared_to(nearest)
		if distance < best_distance:
			best_distance = distance
			best_index = index
			best_fraction = fraction
	return {"index": best_index, "fraction": best_fraction, "distance_squared": best_distance}


func _arc_in_window(arc: float, arc_lo: float, arc_hi: float) -> bool:
	var lo := fposmod(arc_lo, _route_length)
	var hi := fposmod(arc_hi, _route_length)
	var a := fposmod(arc, _route_length)
	if lo <= hi:
		return a >= lo and a <= hi
	return a >= lo or a <= hi


func get_checkpoint_after(checkpoint_index: int) -> Node:
	return _checkpoint_by_index.get(get_checkpoint_after_index(checkpoint_index)) as Node


func get_checkpoint_before(checkpoint_index: int) -> Node:
	if checkpoints.is_empty():
		return null
	var order := int(_checkpoint_order.get(checkpoint_index, 0))
	return checkpoints[posmod(order - 1, checkpoints.size())]


func get_checkpoint_after_index(checkpoint_index: int) -> int:
	if checkpoints.is_empty():
		return 0
	var order := int(_checkpoint_order.get(checkpoint_index, 0))
	return int(checkpoints[(order + 1) % checkpoints.size()].get("checkpoint_index"))


func get_checkpoint_count() -> int:
	return checkpoints.size()


func get_last_recovery_transform(vehicle: Node2D = null) -> Transform2D:
	var racer := vehicle if vehicle else _player_vehicle
	if racer and _racers.has(racer):
		return _racers[racer]["recovery_transform"] as Transform2D
	return last_recovery_transform


func _finish_racer(vehicle: Node2D, state: Dictionary) -> void:
	state["finished"] = true
	state["dnf"] = false
	state["finish_position"] = _finish_order.size() + 1
	state["finish_time"] = float(state["elapsed"])
	state["progress"] = float(laps_to_finish * maxi(1, checkpoints.size()))
	_racers[vehicle] = state
	_finish_order.append(vehicle)
	_set_vehicle_controls_locked(vehicle, true)
	racer_finished.emit(vehicle, int(state["finish_position"]), float(state["finish_time"]))
	if _finish_order.size() == 1 and _finish_order.size() < _registration_order.size():
		_finish_grace_remaining = finish_grace_seconds
	if vehicle == _player_vehicle:
		_sync_player_compatibility()
		race_finished.emit(float(state["finish_time"]))
	_refresh_positions()
	if _finish_grace_remaining == 0.0:
		finalize_remaining_racers_as_dnf()
	else:
		_emit_results_if_complete()


func _emit_results_if_complete() -> void:
	if _results_finalized or _finish_order.size() != _registration_order.size():
		return
	_results_finalized = true
	is_running = false
	results_ready.emit(get_results())


func _update_spatial_progress(vehicle: Node2D, state: Dictionary, delta: float) -> void:
	var checkpoint_count := checkpoints.size()
	if checkpoint_count == 0:
		state["progress"] = float(state["lap"])
		return
	var expected_index := int(state["expected_checkpoint"])
	var expected_checkpoint := _checkpoint_by_index.get(expected_index) as Node2D
	var previous_order := int(state["last_checkpoint_order"])
	var previous_checkpoint := checkpoints[clampi(previous_order, 0, checkpoint_count - 1)] as Node2D
	var fraction := 0.0
	if expected_checkpoint and previous_checkpoint:
		var segment := expected_checkpoint.global_position - previous_checkpoint.global_position
		if segment.length_squared() > 0.001:
			fraction = clampf((vehicle.global_position - previous_checkpoint.global_position).dot(segment) / segment.length_squared(), 0.0, 0.99)
			_update_wrong_way_from_motion(vehicle, state, previous_checkpoint, expected_checkpoint, delta)
	state["progress"] = float(int(state["lap"]) * checkpoint_count + previous_order) + fraction


func _update_wrong_way_from_motion(vehicle: Node2D, state: Dictionary, previous_checkpoint: Node2D, expected_checkpoint: Node2D, delta: float) -> void:
	if delta <= 0.0 or vehicle is not RigidBody2D:
		return
	var rigid_body := vehicle as RigidBody2D
	var velocity := rigid_body.linear_velocity
	if velocity.length() < 80.0:
		state["wrong_way_time"] = maxf(0.0, float(state["wrong_way_time"]) - delta)
		return
	# Judge alignment against the actual route tangent within the current
	# checkpoint section. This keeps a car moving away from the next gate but
	# still travelling along a curved section from being flagged wrong way,
	# while a car genuinely driving backward on that same section is caught.
	var forward_direction := get_route_forward_direction(
		vehicle.global_position,
		int(previous_checkpoint.get("checkpoint_index")),
		int(expected_checkpoint.get("checkpoint_index"))
	)
	if forward_direction.length_squared() < 0.001:
		# Legacy fallback: no route reference, judge against the direct chord.
		forward_direction = vehicle.global_position.direction_to(expected_checkpoint.global_position)
	var alignment := velocity.normalized().dot(forward_direction)
	if alignment < -0.4:
		state["wrong_way_time"] = float(state["wrong_way_time"]) + delta
		if float(state["wrong_way_time"]) > 0.55:
			_set_wrong_way(vehicle, state, true)
	elif alignment > 0.15:
		state["wrong_way_time"] = 0.0
		_set_wrong_way(vehicle, state, false)


func _refresh_positions() -> Array[Node2D]:
	var rankings := get_rankings()
	for index in rankings.size():
		var vehicle := rankings[index]
		var state: Dictionary = _racers[vehicle]
		var new_position := index + 1
		if int(state["position"]) != new_position:
			state["position"] = new_position
			_racers[vehicle] = state
			position_changed.emit(vehicle, new_position, rankings.size())
	return rankings


func _racer_precedes(a: Node2D, b: Node2D) -> bool:
	var state_a: Dictionary = _racers[a]
	var state_b: Dictionary = _racers[b]
	if bool(state_a["finished"]) != bool(state_b["finished"]):
		return bool(state_a["finished"])
	if bool(state_a["finished"]):
		return int(state_a["finish_position"]) < int(state_b["finish_position"])
	var progress_difference := float(state_a["progress"]) - float(state_b["progress"])
	if absf(progress_difference) > 0.0001:
		return progress_difference > 0.0
	return int(state_a["registration_index"]) < int(state_b["registration_index"])


func _first_racing_checkpoint_index() -> int:
	if checkpoints.is_empty():
		return 0
	for checkpoint: Node in checkpoints:
		if not bool(checkpoint.get("is_finish_line")):
			return int(checkpoint.get("checkpoint_index"))
	return int(checkpoints[0].get("checkpoint_index"))


func _checkpoint_precedes(a: Node, b: Node) -> bool:
	var a_finish := bool(a.get("is_finish_line"))
	var b_finish := bool(b.get("is_finish_line"))
	if a_finish != b_finish:
		return a_finish
	var a_index := int(a.get("checkpoint_index"))
	var b_index := int(b.get("checkpoint_index"))
	return a_index > b_index if is_reverse_direction() else a_index < b_index


func _get_recovery_transform(checkpoint: Node) -> Transform2D:
	var recovery := checkpoint.call("get_recovery_transform") as Transform2D
	if not is_reverse_direction():
		return recovery
	var checkpoint_position := (checkpoint as Node2D).global_position
	var original_offset := recovery.origin - checkpoint_position
	return Transform2D(
		wrapf(recovery.get_rotation() + PI, -PI, PI),
		checkpoint_position - original_offset
	)


func _set_wrong_way(vehicle: Node2D, state: Dictionary, value: bool) -> void:
	if bool(state["wrong_way"]) == value:
		return
	state["wrong_way"] = value
	wrong_way_changed.emit(vehicle, value)


func _set_vehicle_controls_locked(vehicle: Node2D, locked: bool) -> void:
	if vehicle.has_method("set_controls_locked"):
		vehicle.call("set_controls_locked", locked)


func _sync_player_compatibility() -> void:
	if not is_instance_valid(_player_vehicle) or not _racers.has(_player_vehicle):
		return
	var state: Dictionary = _racers[_player_vehicle]
	current_checkpoint_index = int(state["expected_checkpoint"])
	lap_count = int(state["lap"])
	last_recovery_transform = state["recovery_transform"] as Transform2D


func _read_identity(vehicle: Node2D, key: StringName, fallback: String) -> String:
	if vehicle.has_meta(key):
		return str(vehicle.get_meta(key))
	var value: Variant = vehicle.get(String(key))
	return str(value) if value != null else fallback
