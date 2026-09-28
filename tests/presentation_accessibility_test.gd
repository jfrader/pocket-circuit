extends SceneTree

const CAMERA_SCRIPT := preload("res://scripts/camera/follow_camera.gd")
const KITCHEN_SCENE := preload("res://scenes/tracks/kitchen_circuit.tscn")

class TestVehicle extends RigidBody2D:
	var boosting := true

	func is_boost_active() -> bool:
		return boosting


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var app := root.get_node_or_null("App")
	if not _expect(app != null, "App autoload should be available"):
		return
	var original_reduced_motion := bool(app.get("reduced_motion"))
	app.set("reduced_motion", true)

	var vehicle := TestVehicle.new()
	var camera := CAMERA_SCRIPT.new() as Camera2D
	root.add_child(vehicle)
	root.add_child(camera)
	camera.call("set_target", vehicle)
	camera.set("_boost_pulse", 1.0)
	camera.call("_physics_process", 0.1)
	if not _expect(is_zero_approx(float(camera.get("_boost_pulse"))), "reduced motion should suppress the boost camera pulse"):
		return
	app.set("reduced_motion", false)
	camera.call("_physics_process", 0.1)
	if not _expect(float(camera.get("_boost_pulse")) > 0.0, "the boost camera pulse should remain available when reduced motion is off"):
		return

	app.set("reduced_motion", true)
	var kitchen := KITCHEN_SCENE.instantiate()
	root.add_child(kitchen)
	await process_frame
	var course := kitchen.get_node_or_null("TrackSurface") as Line2D
	if not _expect(course != null and course.material is ShaderMaterial and course.get_meta("course_kind") == "painted_surface", "the kitchen should present its painted course"):
		return

	app.set("reduced_motion", original_reduced_motion)
	root.remove_child(kitchen)
	root.remove_child(camera)
	root.remove_child(vehicle)
	kitchen.free()
	camera.free()
	vehicle.free()
	print("PRESENTATION_ACCESSIBILITY_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	var app := root.get_node_or_null("App")
	if app:
		app.set("reduced_motion", false)
	push_error("PRESENTATION_ACCESSIBILITY_TEST FAIL: " + message)
	quit(1)
	return false
