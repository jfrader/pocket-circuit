extends Node2D
## One owned CanvasItem and a fixed ring buffer, no particles, bodies or tweens.
const MAX_SEGMENTS := 128
const LIFETIME := 2.4
const SAMPLE_INTERVAL := 0.055
const MIN_DISTANCE := 2.0
const MAX_DISTANCE := 100.0
const TYRE_OFFSET := Vector2(14.0, 22.0)
const WIDTH := 5.0

var _starts := PackedVector2Array()
var _ends := PackedVector2Array()
var _colors := PackedColorArray()
var _ages := PackedFloat32Array()
var _cursor := 0
var _clock := 0.0
var _previous := Transform2D.IDENTITY
var _has_previous := false


func _init() -> void:
	_starts.resize(MAX_SEGMENTS)
	_ends.resize(MAX_SEGMENTS)
	_colors.resize(MAX_SEGMENTS)
	_ages.resize(MAX_SEGMENTS)
	_ages.fill(LIFETIME)
	z_as_relative = false
	z_index = -1


func step(delta: float, pose: Transform2D, color: Color, carry: float) -> void:
	for index in MAX_SEGMENTS:
		_ages[index] = minf(_ages[index] + delta, LIFETIME)
	_clock += delta
	if not _has_previous:
		_previous = pose
		_has_previous = true
	if _clock >= SAMPLE_INTERVAL:
		_clock = fmod(_clock, SAMPLE_INTERVAL)
		var distance := pose.origin.distance_to(_previous.origin)
		if carry > 0.0 and distance >= MIN_DISTANCE and distance <= MAX_DISTANCE:
			for side in [-1.0, 1.0]:
				var offset := Vector2(TYRE_OFFSET.x * side, TYRE_OFFSET.y)
				_starts[_cursor] = _previous * offset
				_ends[_cursor] = pose * offset
				_colors[_cursor] = Color(color, carry * 0.65)
				_ages[_cursor] = 0.0
				_cursor = (_cursor + 1) % MAX_SEGMENTS
		_previous = pose
	queue_redraw()


func reset() -> void:
	_ages.fill(LIFETIME)
	_has_previous = false
	_clock = 0.0
	_cursor = 0
	queue_redraw()


func active_segments() -> int:
	var count := 0
	for age in _ages:
		if age < LIFETIME:
			count += 1
	return count


func _draw() -> void:
	for index in MAX_SEGMENTS:
		if _ages[index] >= LIFETIME:
			continue
		var tint := _colors[index]
		tint.a *= 1.0 - _ages[index] / LIFETIME
		draw_line(to_local(_starts[index]), to_local(_ends[index]), tint, WIDTH, true)
