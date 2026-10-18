extends CanvasLayer

const SKIN := preload("res://scripts/ui/motorsport_skin.gd")
const SWEEP_SECONDS := 0.34
const FADE_SECONDS := 0.12
const RESULTS_SECONDS := 0.24
const RESULTS_INITIAL_OPACITY := 0.96
const BAND_HEIGHT := 152.0
const RESULTS_STAMP_SCALE := Vector2(1.035, 1.035)

class TapeBand extends Control:
	func _draw() -> void:
		var edge := 12.0
		var points := PackedVector2Array([
			Vector2(0, edge), Vector2(size.x * 0.24, 0),
			Vector2(size.x * 0.7, edge), Vector2(size.x, 0),
			Vector2(size.x - edge, size.y * 0.4), Vector2(size.x, size.y - edge),
			Vector2(size.x * 0.67, size.y), Vector2(size.x * 0.3, size.y - edge),
			Vector2(0, size.y), Vector2(edge, size.y * 0.6),
		])
		var shadow := points.duplicate()
		for i in shadow.size():
			shadow[i] += Vector2(5, 9)
		draw_colored_polygon(shadow, SKIN.SHADOW_TINT)
		draw_colored_polygon(points, SKIN.CREAM)
		draw_line(Vector2(32, size.y - 25), Vector2(size.x - 32, size.y - 25), SKIN.YELLOW, 3)

var _surface: Control
var _band: Control
var _label: Label
var _tween: Tween


static func instant_for(app: Node) -> bool:
	return bool(app.get("_test_mode")) if app != null else "--script" in OS.get_cmdline_args()


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_surface = Control.new()
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_surface)
	var shade := ColorRect.new()
	shade.color = Color(SKIN.INK, 0.28)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(shade)
	_band = TapeBand.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(_band)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("font", SKIN.display_font())
	_label.add_theme_font_size_override("font_size", 32)
	_label.add_theme_color_override("font_color", SKIN.INK)
	_band.add_child(_label)
	hide()


func play(kicker: String, instant: bool, reduced_motion: bool) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	hide()
	if instant:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_band.size = Vector2(viewport_size.x + 48, BAND_HEIGHT)
	_band.position = Vector2(-24, (viewport_size.y - BAND_HEIGHT) * 0.5)
	_label.text = kicker
	_surface.modulate = Color.WHITE
	show()
	_tween = create_tween()
	if reduced_motion:
		_tween.tween_property(_surface, "modulate:a", 0.0, FADE_SECONDS)
	else:
		_band.position.x = -_band.size.x
		_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_property(_band, "position:x", -24.0, SWEEP_SECONDS * 0.3)
		_tween.tween_interval(SWEEP_SECONDS * 0.38)
		_tween.set_ease(Tween.EASE_IN)
		_tween.tween_property(_band, "position:x", viewport_size.x + 24, SWEEP_SECONDS * 0.32)
		_tween.parallel().tween_property(_surface, "modulate:a", 0.0, SWEEP_SECONDS * 0.32)
	_tween.tween_callback(hide)


static func results_entrance(panel: Control, instant: bool, reduced_motion: bool) -> Tween:
	panel.show()
	panel.scale = Vector2.ONE
	panel.modulate = Color.WHITE
	if instant:
		return null
	panel.modulate.a = 0.0 if reduced_motion else RESULTS_INITIAL_OPACITY
	var tween := panel.create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, FADE_SECONDS)
	if not reduced_motion:
		panel.pivot_offset = panel.size * 0.5
		panel.scale = RESULTS_STAMP_SCALE
		tween.tween_property(panel, "scale", Vector2.ONE, RESULTS_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween
