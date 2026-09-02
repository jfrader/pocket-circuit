extends SceneTree

const VEHICLE_SCRIPT := preload("res://scripts/vehicle/vehicle_controller.gd")


func _initialize() -> void:
	var vehicle := VEHICLE_SCRIPT.new() as VehicleController
	var original_grip := vehicle.stats.grip
	var original_lateral_grip := vehicle.stats.lateral_grip
	var original_max_speed := vehicle.stats.max_speed
	vehicle.configure_base_surface(&"workbench")
	vehicle.apply_surface_modifier(101, &"oil slick", 0.45, 0.92)
	if not _expect(vehicle.current_surface == &"oil slick" and is_equal_approx(vehicle.surface_grip_multiplier, 0.45), "oil should apply its named grip modifier"):
		return
	if not _expect(is_equal_approx(vehicle.get_effective_max_speed(), original_max_speed * 0.92), "surface speed should be derived from immutable vehicle stats"):
		return
	vehicle.apply_surface_modifier(202, &"sawdust", 0.78, 0.72)
	if not _expect(vehicle.current_surface == &"sawdust", "the most recently entered overlapping zone should be active"):
		return
	vehicle.clear_surface_modifier(202)
	if not _expect(vehicle.current_surface == &"oil slick", "leaving an overlap should restore the still-active surface"):
		return
	vehicle.reset_surface_modifiers()
	if not _expect(vehicle.current_surface == &"workbench" and is_equal_approx(vehicle.surface_grip_multiplier, 1.0) and is_equal_approx(vehicle.surface_speed_multiplier, 1.0), "recovery reset should restore the configured base surface"):
		return
	if not _expect(is_equal_approx(vehicle.stats.grip, original_grip) and is_equal_approx(vehicle.stats.lateral_grip, original_lateral_grip) and is_equal_approx(vehicle.stats.max_speed, original_max_speed), "surface changes must never mutate VehicleStats"):
		return

	print("SURFACE_MODIFIER_TEST PASS")
	vehicle.free()
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("SURFACE_MODIFIER_TEST FAIL: " + message)
	quit(1)
	return false
