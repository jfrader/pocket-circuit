extends SceneTree

const CAPTURE := preload("res://scripts/race/strip_capture.gd")


func _initialize() -> void:
	var capture := CAPTURE.new()
	if capture.advance(1.49, 90.0, true, true, false) or not capture.advance(0.01, 90.0, true, true, false):
		_fail("Capture threshold")
		return
	for broken in ["range", "section", "sight", "suspend"]:
		capture.clear()
		capture.advance(1.49, 50.0, true, true, false)
		var triggered := capture.advance(0.01, 91.0 if broken == "range" else 50.0, broken != "section", broken != "sight", broken == "suspend")
		if triggered or capture.exposure != 0.0 or capture.advance(0.01, 50.0, true, true, false):
			_fail(broken + " did not reset")
			return
	print("STRIP_CAPTURE_TEST PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
