extends SceneTree

const VEHICLE_SCENE := preload("res://scenes/vehicles/rustbug.tscn")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")

const VEHICLE_IDS: Array[String] = ["rustbug", "pinbolt", "scrapjaw", "flicker"]


func _initialize() -> void:
	var vehicle := VEHICLE_SCENE.instantiate() as VehicleController
	var collision := vehicle.get_node("CollisionShape2D") as CollisionShape2D
	var collision_shape := collision.shape as CapsuleShape2D
	var collision_height := collision_shape.height
	var collision_radius := collision_shape.radius
	var image_hashes := {}
	for vehicle_id: String in VEHICLE_IDS:
		vehicle.configure_identity("Driver", vehicle_id.capitalize(), vehicle_id)
		var car_sprite := vehicle.get_node("VisualRoot/CarSprite") as Sprite2D
		var texture := car_sprite.texture
		if not _expect(texture != null, "%s should resolve a procedural texture" % vehicle_id):
			return
		if not _expect(texture.get_size() == Vector2(48.0, 64.0), "%s should use the 48x64 race sprite contract" % vehicle_id):
			return
		if not _expect(texture == IDENTITIES.car_texture(vehicle_id), "%s should reuse the shared texture cache" % vehicle_id):
			return
		var image_hash := _texture_hash(texture)
		if not _expect(not image_hashes.has(image_hash), "%s should keep distinct rendered pixels" % vehicle_id):
			return
		image_hashes[image_hash] = vehicle_id
		if not _expect(car_sprite.scale == Vector2.ONE, "%s should render at the race scene's authored footprint" % vehicle_id):
			return
		if not _expect(car_sprite.self_modulate == Color.WHITE, "%s should keep its generated palette instead of a runtime tint" % vehicle_id):
			return
		if not _expect(vehicle.get_node_or_null("VisualRoot/IdentityAccents") == null, "%s should not layer legacy accent polygons" % vehicle_id):
			return
		if not _expect(collision.shape == collision_shape, "%s must not replace collision geometry" % vehicle_id):
			return
		if not _expect(collision_shape.height == collision_height and collision_shape.radius == collision_radius, "%s must not resize collision geometry" % vehicle_id):
			return
	vehicle.configure_racer_marker(Color("71b7ff"))
	var marker := vehicle.get_node_or_null("VisualRoot/RacerMarker") as Line2D
	if not _expect(marker != null and marker.default_color == Color("71b7ff"), "duplicate machine selections should retain a readable racer marker"):
		return
	if not _expect(collision.shape == collision_shape and collision_shape.height == collision_height and collision_shape.radius == collision_radius, "racer markers must not change collision geometry"):
		return
	vehicle.free()
	print("VEHICLE_VISUAL_IDENTITY_TEST PASS")
	quit(0)


func _texture_hash(texture: Texture2D) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(texture.get_image().save_png_to_buffer())
	return context.finish().hex_encode()


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("VEHICLE_VISUAL_IDENTITY_TEST FAIL: " + message)
	quit(1)
	return false
