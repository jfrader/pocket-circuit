extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const CAR_SPRITES := preload("res://scripts/vendor/procedural_2d/procedural_car_sprites.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	for format in [Image.FORMAT_RGBA8, Image.FORMAT_RGBAF]:
		var image := Image.create(53, 41, false, format)
		image.fill(Color.TRANSPARENT)
		for y in 41:
			for x in 53:
				if (x * 7 + y * 13) % 11 < 3:
					image.set_pixel(x, y, Color(1, 1, 1, 0.081 if x % 2 == 0 else 0.078))
		var texture := ImageTexture.create_from_image(image)
		var dense := PackedVector2Array()
		for y in 41:
			for x in 53:
				if image.get_pixel(x, y).a > BUILDER.COLLISION_ALPHA_THRESHOLD:
					dense.append(Vector2(x + 0.5, y + 0.5))
		var outline: Dictionary = BUILDER._texture_alpha_outline(texture)
		var edge: PackedVector2Array = outline["boundary"]
		for index in 32:
			var axis := Vector2.from_angle(float(index) * TAU / 32.0)
			if not _expect(is_equal_approx(_support(dense, axis), _support(edge, axis)), "cached row endpoints must preserve dense alpha support including threshold-edge pixels"):
				return
	var payload := IDENTITIES.car_payload("rustbug")
	for scale in [1, 2]:
		var reference := CAR_SPRITES.car_steer_frames(payload, 3, scale)
		for pose in 5:
			var single := CAR_SPRITES.car_pose_image(payload, 3, pose, scale)
			if not _expect(single.get_data() == reference[pose].get_data(), "single-pose preparation must be byte-identical to the existing animation renderer"):
				return
	print("TRACK_ALPHA_OUTLINE_TEST PASS exact_support_and_animation_pixels")
	quit(0)


func _support(points: PackedVector2Array, axis: Vector2) -> float:
	var result := -INF
	for point in points:
		result = maxf(result, point.dot(axis))
	return result


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_ALPHA_OUTLINE_TEST FAIL: " + message)
	quit(1)
	return false
