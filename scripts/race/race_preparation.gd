extends Node

var _worker: Thread


## Runs `job` on a background Thread. Caller must `await` the result.
## `priority` defaults to LOW to preserve prior behaviour for all existing call sites.
## Pass PRIORITY_NORMAL (or HIGH) explicitly for CPU-bound work that benefits from
## better OS scheduling (e.g. first-load circuit generation).
func run_data_job(job: Callable, priority: int = Thread.PRIORITY_LOW) -> Dictionary:
	_worker = Thread.new()
	var error := _worker.start(job, priority)
	if error != OK:
		_worker = null
		return {}
	while _worker.is_alive():
		await get_tree().process_frame
	var result: Variant = _worker.wait_to_finish()
	_worker = null
	return result if result is Dictionary else {}


func _exit_tree() -> void:
	if _worker != null and _worker.is_started():
		_worker.wait_to_finish()
	_worker = null
