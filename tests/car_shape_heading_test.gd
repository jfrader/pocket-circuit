extends SceneTree

const VIEW := preload("res://scripts/ui/car_shape_view.gd")
const SKIN := preload("res://scripts/ui/motorsport_skin.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var font := SKIN.display_font()
	for rect: Rect2 in [Rect2(0, 0, 420, 400), Rect2(720, 80, 456, 330), Rect2(600, 50, 380, 330)]:
		for title: String in ["VS DESERT PICO", "CAR SHAPE", "VS NIGHT COUPE"]:
			var header := VIEW.header_geometry(rect, title)
			var baseline: Vector2 = header.text_position
			var text_bounds: Rect2 = header.text_bounds
			var tape_bounds: Rect2 = header.tape_bounds
			if not _expect(baseline.y - font.get_ascent(VIEW.HEADER_FONT_SIZE) >= rect.position.y, "%s: actual font ascent stays below the card top" % title):
				return
			if not _expect(baseline.y + font.get_descent(VIEW.HEADER_FONT_SIZE) <= rect.end.y, "%s: actual font descent stays above the card bottom" % title):
				return
			if not _expect(rect.encloses(text_bounds) and rect.encloses(tape_bounds), "%s: text and rotated torn tape stay within %s" % [title, rect]):
				return
			if not _expect(is_equal_approx(text_bounds.position.y, baseline.y - font.get_ascent(VIEW.HEADER_FONT_SIZE)) and is_equal_approx(text_bounds.end.y, baseline.y + font.get_descent(VIEW.HEADER_FONT_SIZE)), "exposed text bounds describe the drawn font metrics"):
				return
			for corner: Vector2 in [Vector2.ZERO, Vector2(header.tape_size.x, 0), header.tape_size, Vector2(0, header.tape_size.y)]:
				var rotated: Vector2 = header.tape_center + (corner - header.tape_size * 0.5).rotated(VIEW.HEADER_TAPE_ANGLE)
				if not _expect(tape_bounds.has_point(rotated), "tape bounds contain its rotated corners"):
					return
	print("CAR_SHAPE_HEADING_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("CAR_SHAPE_HEADING_TEST FAIL: " + message)
		quit(1)
	return condition
