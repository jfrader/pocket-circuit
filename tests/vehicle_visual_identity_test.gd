extends SceneTree

const VEHICLE_SCENE := preload("res://scenes/vehicles/rustbug.tscn")


func _initialize() -> void:
	var vehicle := VEHICLE_SCENE.instantiate() as VehicleController
	var collision := vehicle.get_node("CollisionShape2D") as CollisionShape2D
	var collision_shape := collision.shape
	vehicle.configure_identity("Rae", "Rustbug", "rustbug")
	if not _expect(vehicle.get_node_or_null("VisualRoot/IdentityAccents") == null, "Rustbug should keep its authored silhouette unchanged"):
		return

	vehicle.configure_identity("Juniper", "Pinbolt", "pinbolt")
	if not _expect(_has_polygons(vehicle, ["NarrowNose", "LeftGripFin", "RightGripFin"]), "Pinbolt should add a narrow nose and side grip fins"):
		return
	vehicle.configure_identity("Milo", "Scrapjaw", "scrapjaw")
	if not _expect(_has_polygons(vehicle, ["WideFrontBumper", "WideRearBumper", "HeavyRoofBlock"]), "Scrapjaw should add wide bumpers and a heavy roof block"):
		return
	vehicle.configure_identity("Tess", "Flicker", "flicker")
	if not _expect(_has_polygons(vehicle, ["RearWing", "DriftStripe"]), "Flicker should add a rear wing and drift stripe"):
		return
	if not _expect(collision.shape == collision_shape, "runtime visual identity must not replace or resize collision geometry"):
		return
	vehicle.free()
	print("VEHICLE_VISUAL_IDENTITY_TEST PASS")
	quit(0)


func _has_polygons(vehicle: VehicleController, child_names: Array[String]) -> bool:
	var accents := vehicle.get_node_or_null("VisualRoot/IdentityAccents")
	if accents == null:
		return false
	for child_name: String in child_names:
		if accents.get_node_or_null(child_name) is not Polygon2D:
			return false
	return true


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("VEHICLE_VISUAL_IDENTITY_TEST FAIL: " + message)
	quit(1)
	return false
