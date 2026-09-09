extends SceneTree

const RECT_SHADOW := "res://assets/textures/edge_dressing/shadow_soft_rect.png"


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var texture := load(RECT_SHADOW) as Texture2D
	var image := texture.get_image()
	var used := image.get_used_rect()
	var center := used.get_center()
	if not _expect(image.get_pixelv(center).a > 0.6, "contact-shadow core should remain visible"):
		return
	var probes := [
		Vector2i(used.position.x + 1, center.y),
		Vector2i(used.end.x - 2, center.y),
		Vector2i(center.x, used.position.y + 1),
		Vector2i(center.x, used.end.y - 2),
	]
	for point: Vector2i in probes:
		var edge_alpha := image.get_pixelv(point).a
		print("SHADOW_EDGE_ALPHA point=%s alpha=%.4f" % [point, edge_alpha])
		if not _expect(edge_alpha < 0.05, "rectangular shadow must fade out instead of ending in a visible grey edge"):
			return
	var previous := 0.0
	for x in range(used.position.x - 1, center.x + 1):
		var alpha := image.get_pixel(x, center.y).a
		if not _expect(alpha >= previous - 0.01 and alpha - previous < 0.1, "shadow feather should increase smoothly toward its core"):
			return
		previous = alpha
	print("SHADOW_MASK_TEST PASS feathered_edges_and_retained_core")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("SHADOW_MASK_TEST FAIL: " + message)
	quit(1)
	return false
