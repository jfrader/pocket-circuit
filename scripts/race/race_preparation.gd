extends Node

var _worker: Thread


func run_data_job(job: Callable) -> Dictionary:
	_worker = Thread.new()
	var error := _worker.start(job, Thread.PRIORITY_LOW)
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
