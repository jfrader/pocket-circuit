## Shared arc-length sampler for an open strip route.
## Both the traffic manager and its cars need to look up a position along the
## same route every physics tick; this keeps one table and one binary search
## instead of a copy per car.
extends RefCounted

var _points: PackedVector2Array = PackedVector2Array()
var _cumulative: PackedFloat32Array = PackedFloat32Array()
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


func length() -> float:
	return _total


func sample(arc: float) -> Dictionary:
	if _points.size() < 2:
		return {"pos": Vector2.ZERO, "dir": Vector2.UP, "perp": Vector2.RIGHT}
	var clamped := clampf(arc, 0.0, _total)
	var low := 0
	var high := _points.size() - 1
	while low < high - 1:
		var mid := (low + high) >> 1
		if _cumulative[mid] <= clamped:
			low = mid
		else:
			high = mid
	var segment := _points[low + 1] - _points[low]
	var segment_length := segment.length()
	var direction := segment / segment_length if segment_length > 0.001 else Vector2.UP
	var fraction := 0.0 if segment_length <= 0.001 else (clamped - _cumulative[low]) / segment_length
	return {
		"pos": _points[low].lerp(_points[low + 1], fraction),
		"dir": direction,
		"perp": direction.orthogonal(),
	}
