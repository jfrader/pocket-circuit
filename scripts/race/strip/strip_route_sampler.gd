## Shared arc-length sampler for an open strip route.
## Both the traffic manager and its cars need to look up a position along the
## same route every physics tick; this keeps one table and one binary search
## instead of a copy per car.
extends RefCounted

var _points: PackedVector2Array = PackedVector2Array()
var _cumulative: PackedFloat32Array = PackedFloat32Array()
var _tangents := PackedVector2Array()
var _total := 0.0


func configure(route: PackedVector2Array) -> void:
	_points = route.duplicate()
	_cumulative = PackedFloat32Array()
	_total = 0.0
	if _points.size() < 2:
		return
	_cumulative.resize(_points.size())
	var cumulative := 0.0
	for index in _points.size():
		_cumulative[index] = cumulative
		if index < _points.size() - 1:
			cumulative += _points[index].distance_to(_points[index + 1])
	_total = cumulative
	_tangents.resize(_points.size())
	for index in _points.size():
		_tangents[index] = (_points[mini(index + 1, _points.size() - 1)] - _points[maxi(index - 1, 0)]).normalized()


func length() -> float:
	return _total


func sample(arc: float) -> Dictionary:
	if _points.size() < 2:
		return {"pos": Vector2.ZERO, "dir": Vector2.UP, "perp": Vector2.RIGHT}
	var clamped := clampf(arc, 0.0, _total)
	var low := _segment_index(clamped)
	var segment := _points[low + 1] - _points[low]
	var segment_length := segment.length()
	var direction := segment / segment_length if segment_length > 0.001 else Vector2.UP
	var fraction := 0.0 if segment_length <= 0.001 else (clamped - _cumulative[low]) / segment_length
	direction = _tangents[low].lerp(_tangents[low + 1], fraction).normalized()
	return {
		"pos": _points[low].lerp(_points[low + 1], fraction),
		"dir": direction,
		"perp": direction.orthogonal(),
	}


func project(point: Vector2, hint: float = -1.0) -> Dictionary:
	var best := {"arc": 0.0, "distance_squared": INF}
	if _points.size() < 2:
		return best
	# The actual body position, never elapsed time, owns progress. A bounded
	# window is sufficient in normal motion; displaced bodies get a full search.
	var first := _segment_index(maxf(0.0, hint - 600.0)) if hint >= 0.0 else 0
	var last := _segment_index(minf(_total, hint + 600.0)) + 1 if hint >= 0.0 else _points.size() - 1
	for index in range(first, last):
		var segment := _points[index + 1] - _points[index]
		var fraction := clampf((point - _points[index]).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
		var distance := point.distance_squared_to(_points[index] + segment * fraction)
		if distance < float(best["distance_squared"]):
			best = {"arc": lerpf(_cumulative[index], _cumulative[index + 1], fraction), "distance_squared": distance}
	if hint >= 0.0 and float(best["distance_squared"]) > 40000.0:
		return project(point)
	return best


func _segment_index(arc: float) -> int:
	var low := 0
	var high := _points.size() - 1
	while low < high - 1:
		var mid := (low + high) >> 1
		if _cumulative[mid] <= arc:
			low = mid
		else:
			high = mid
	return low
