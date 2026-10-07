class_name CircuitPreviewQueue
extends Node

const GENERATED_CIRCUITS := preload("res://scripts/race/generated_circuit_identity.gd")
const CIRCUIT_PREVIEW := preload("res://scripts/race/circuit_route_preview.gd")
const RACE_PREPARATION := preload("res://scripts/race/race_preparation.gd")
const MAX_PENDING := 3
const CACHE_LIMIT := 8

class PreviewTicket extends RefCounted:
	signal completed(result: Dictionary)

var _pending_order: Array[String] = []
var _pending: Dictionary = {}
var _active_fingerprint := ""
var _active_entry: Dictionary = {}
var _cache: Dictionary = {}
var _cache_order: Array[String] = []
var _worker: Node
var _active_workers := 0
var _max_concurrent_workers := 0
var _job_count := 0


func request(identity_value: Dictionary) -> Dictionary:
	var identity := GENERATED_CIRCUITS.normalize(identity_value)
	if identity.is_empty():
		return {}
	var fingerprint := String(identity["fingerprint"])
	if _cache.has(fingerprint):
		_touch_cache(fingerprint)
		return (_cache[fingerprint] as Dictionary).duplicate(true)
	var ticket := PreviewTicket.new()
	if fingerprint == _active_fingerprint:
		(_active_entry["tickets"] as Array).append(ticket)
	elif _pending.has(fingerprint):
		(_pending[fingerprint]["tickets"] as Array).append(ticket)
	else:
		while _pending_order.size() >= MAX_PENDING:
			_complete_dropped(_pending_order.pop_front())
		_pending_order.append(fingerprint)
		_pending[fingerprint] = {
			"identity": identity.duplicate(true),
			"tickets": [ticket],
		}
		call_deferred("_run_next")
	var result: Dictionary = await ticket.completed
	return result.duplicate(true)


func get_debug_metrics() -> Dictionary:
	return {
		"active_workers": _active_workers,
		"max_concurrent_workers": _max_concurrent_workers,
		"job_count": _job_count,
		"pending_count": _pending_order.size(),
		"cache_count": _cache_order.size(),
	}


func _run_next() -> void:
	if not _active_fingerprint.is_empty() or _pending_order.is_empty():
		return
	_active_fingerprint = _pending_order.pop_front()
	_active_entry = _pending.get(_active_fingerprint, {})
	_pending.erase(_active_fingerprint)
	if _active_entry.is_empty():
		_active_fingerprint = ""
		call_deferred("_run_next")
		return
	_worker = RACE_PREPARATION.new()
	add_child(_worker)
	_active_workers += 1
	_max_concurrent_workers = maxi(_max_concurrent_workers, _active_workers)
	_job_count += 1
	var identity: Dictionary = _active_entry["identity"]
	var result: Dictionary = await _worker.run_data_job(CIRCUIT_PREVIEW.prepare.bind(identity))
	var completed_fingerprint := _active_fingerprint
	_active_workers -= 1
	_worker.queue_free()
	_worker = null
	if String(result.get("identity_fingerprint", "")) != completed_fingerprint or String(result.get("loaded_fingerprint", "")).length() != 16:
		result = {}
	elif not result.is_empty():
		_store_cache(completed_fingerprint, result)
	var tickets: Array = (_active_entry.get("tickets", []) as Array).duplicate()
	_active_entry.clear()
	_active_fingerprint = ""
	for ticket: PreviewTicket in tickets:
		ticket.completed.emit(result.duplicate(true))
	call_deferred("_run_next")


func _complete_dropped(fingerprint: String) -> void:
	var entry: Dictionary = _pending.get(fingerprint, {})
	_pending.erase(fingerprint)
	for ticket: PreviewTicket in entry.get("tickets", []):
		call_deferred("_complete_ticket", ticket, {})


func _complete_ticket(ticket: PreviewTicket, result: Dictionary) -> void:
	ticket.completed.emit(result)


func _store_cache(fingerprint: String, preview: Dictionary) -> void:
	_cache[fingerprint] = preview.duplicate(true)
	_touch_cache(fingerprint)
	while _cache_order.size() > CACHE_LIMIT:
		_cache.erase(_cache_order.pop_front())


func _exit_tree() -> void:
	# Deterministic teardown (GURI-1680): drop pending tickets, the cache and the
	# worker so a quit mid-preview cannot leave state behind.
	_pending_order.clear()
	_pending.clear()
	_active_entry.clear()
	_active_fingerprint = ""
	_cache.clear()
	_cache_order.clear()
	if is_instance_valid(_worker):
		_worker.free()
	_worker = null
	_active_workers = 0


func _touch_cache(fingerprint: String) -> void:
	_cache_order.erase(fingerprint)
	_cache_order.append(fingerprint)