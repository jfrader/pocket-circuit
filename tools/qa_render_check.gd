extends SceneTree

## Render QA: loads a captured frame (PC_QA_FRAME) and verifies the projected
## screen pixels show what the scene promises: cars aligned on the grid, the
## checker strip alternating, the island prop visible, the painted ribbon dark.
## Uses the known camera state at capture time (player parked on the grid,
## camera clamped, zoom settled near 1.12).

const CAMERA_CENTER := Vector2.ZERO
const ZOOM := 0.46
const VIEWPORT := Vector2(1280.0, 720.0)
const THEMES := {
	&"workshop": {"start": Vector2(640.0, 370.0), "tangent": Vector2(-1.0, 0.0)},
	&"office": {"start": Vector2(640.0, 370.0), "tangent": Vector2(-1.0, 0.0)},
}

var _theme: StringName = &"workshop"
var _image: Image
var _failures: Array[String] = []


func _initialize() -> void:
	var env := OS.get_environment("PC_THEME")
	if env in [&"workshop", &"office"]:
		_theme = StringName(env)
	call_deferred("_run")


func _run() -> void:
	var frame_path := OS.get_environment("PC_QA_FRAME")
	if frame_path.is_empty():
		push_error("QA_RENDER: PC_QA_FRAME not set")
		quit(1)
		return
	_image = Image.load_from_file(frame_path)
	if _image == null or _image.is_empty():
		push_error("QA_RENDER: could not load " + frame_path)
		quit(1)
		return

	var spec: Dictionary = THEMES[_theme]
	var start: Vector2 = spec["start"]
	var tangent: Vector2 = spec["tangent"]
	var normal := tangent.rotated(PI * 0.5)

	# 1. The 2x2 grid: four car pixels aligned behind the finish line.
	var car_offsets := [
		start + tangent * 100.0 - normal * 45.0,
		start + tangent * 100.0 + normal * 45.0,
		start + tangent * 220.0 - normal * 45.0,
		start + tangent * 220.0 + normal * 45.0,
	]
	var floor_sample := _sample_world(start + normal * 400.0)
	for offset: Vector2 in car_offsets:
		if not _neighborhood_has_car(offset):
			_failures.append("no car rendered at grid slot %s" % str(offset.round()))

	# 2. Checker strip alternates white/black along the finish line.
	var strip_colors := PackedStringArray()
	for block in 6:
		var sample := start + tangent * 10.0 + normal * ((float(block) - 2.5) * 44.0)
		var pixel := _sample_world(sample)
		strip_colors.append("light" if pixel.r > 0.7 and pixel.g > 0.7 else "dark")
	for block in range(1, strip_colors.size()):
		if strip_colors[block] == strip_colors[block - 1]:
			_failures.append("checker strip does not alternate at block %d (%s)" % [block, strip_colors[block]])
			break

	# 3. Island prop texture visible at the island center.
	var prop_pixel := _sample_world(Vector2(0.0, -100.0))
	var asphalt := _sample_world(start)
	var prop_distance := _color_distance(prop_pixel, asphalt)
	if prop_distance < 0.1:
		_failures.append("island prop not visible at center (pixel %s vs asphalt %s)" % [str(prop_pixel), str(asphalt)])

	# 4. Painted ribbon is dark at the centerline.
	var ribbon := _sample_world(Vector2(0.0, 370.0))
	if ribbon.r > 0.45 and ribbon.g > 0.45 and ribbon.b > 0.45:
		_failures.append("painted ribbon is not dark at the centerline (%s)" % str(ribbon))

	# 5. Floor texture differs from the ribbon (environment reads as a room).
	if _color_distance(floor_sample, asphalt) < 0.25:
		_failures.append("floor and track surfaces are too similar")

	if _failures.is_empty():
		print("QA_RENDER PASS %s" % _theme)
		quit(0)
	for failure: String in _failures:
		push_error("QA_RENDER FAIL: " + failure)
	quit(1)


func _sample_world(world: Vector2) -> Color:
	var screen := (world - CAMERA_CENTER) * ZOOM + VIEWPORT * 0.5
	var x := clampi(int(round(screen.x)), 0, int(VIEWPORT.x) - 1)
	var y := clampi(int(round(screen.y)), 0, int(VIEWPORT.y) - 1)
	return _image.get_pixel(x, y)


func _neighborhood_has_car(world: Vector2) -> bool:
	var center := (world - CAMERA_CENTER) * ZOOM + VIEWPORT * 0.5
	for offset_x in range(-8, 9, 2):
		for offset_y in range(-8, 9, 2):
			var x := clampi(int(round(center.x)) + offset_x, 0, int(VIEWPORT.x) - 1)
			var y := clampi(int(round(center.y)) + offset_y, 0, int(VIEWPORT.y) - 1)
			var pixel := _image.get_pixel(x, y)
			var max_channel := maxf(pixel.r, maxf(pixel.g, pixel.b))
			var min_channel := minf(pixel.r, minf(pixel.g, pixel.b))
			if max_channel > 0.55 and max_channel - min_channel > 0.25:
				return true
	return false


func _color_distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
