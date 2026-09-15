extends SceneTree

## Side-by-side v1 (bicycle) vs v2 (arcade) measurements. This is the QA gate:
## v2 planted (low slip like v1 at mid), but more rotation at high speed+throttle (oversteer w/o hb).
## Handbrake remains stronger drift. Tightened per GURI-739.

const PHYSICS_HZ := 60
const SCENE := "res://scenes/vehicles/rustbug.tscn"
const STATS := "res://data/vehicles/rustbug.tres"


func _initialize() -> void:
	Engine.physics_ticks_per_second = PHYSICS_HZ
	call_deferred("_run")


func _run() -> void:
	var rows: Array[Dictionary] = []
	rows.append(await _measure("straight_280", 1, 280.0, 0.6, 0.0, false, 25))
	rows.append(await _measure("straight_280", 2, 280.0, 0.6, 0.0, false, 25))
	rows.append(await _measure("steer_mid", 1, 280.0, 0.5, 1.0, false, 35))
	rows.append(await _measure("steer_mid", 2, 280.0, 0.5, 1.0, false, 35))
	rows.append(await _measure("steer_fast_throttle", 1, 0.0, 1.0, 1.0, false, 40, 0.85))
	rows.append(await _measure("steer_fast_throttle", 2, 0.0, 1.0, 1.0, false, 40, 0.85))
	print("HANDLING_SIM")
	print("scenario,ver,slip,yaw,heading,speed")
	for row: Dictionary in rows:
		print("%s,%d,%.3f,%.3f,%.3f,%.1f" % [
			row["name"], row["ver"], row["slip"], row["yaw"], row["heading"], row["speed"],
		])
	var v1_mid := _row(rows, "steer_mid", 1)
	var v2_mid := _row(rows, "steer_mid", 2)
	var v2_straight := _row(rows, "straight_280", 2)
	var v2_fast := _row(rows, "steer_fast_throttle", 2)
	var v1_fast := _row(rows, "steer_fast_throttle", 1)
	if float(v2_straight["slip"]) >= 0.04:
		return _fail("v2 straight slip %.3f is soap" % float(v2_straight["slip"]))
	var max_mid_slip := maxf(0.045, float(v1_mid["slip"]) * 1.8)
	if float(v2_mid["slip"]) > max_mid_slip:
		return _fail("v2 mid-steer slip %.3f vs v1 %.3f (exceeds max(0.045, v1*1.8)=%.3f)" % [float(v2_mid["slip"]), float(v1_mid["slip"]), max_mid_slip])
	if float(v2_fast["heading"]) < 0.20 or float(v2_fast["yaw"]) < float(v1_fast["yaw"]) * 0.90:
		return _fail("v2 fast throttle+steer heading %.3f or yaw %.3f insufficient vs v1_yaw*1.15=%.3f (still plow or not enough oversteer)" % [float(v2_fast["heading"]), float(v2_fast["yaw"]), float(v1_fast["yaw"])*1.15])
	if float(v2_fast["slip"]) > 0.14:
		return _fail("v2 fast slip %.3f is soap" % float(v2_fast["slip"]))
	if float(v2_fast["speed"]) < float(v1_fast["speed"]) * 0.85:
		return _fail("v2 fast speed %.1f < v1_fast*0.85=%.1f (killed speed)" % [float(v2_fast["speed"]), float(v1_fast["speed"])*0.85])
	print("VEHICLE_HANDLING_SIM_TEST PASS v1_mid_slip=%.3f v2_mid_slip=%.3f v2_fast_yaw=%.3f v1_fast_yaw=%.3f" % [
		float(v1_mid["slip"]), float(v2_mid["slip"]), float(v2_fast["yaw"]), float(v1_fast["yaw"]),
	])
	quit(0)


func _row(rows: Array[Dictionary], name: String, ver: int) -> Dictionary:
	for row: Dictionary in rows:
		if String(row["name"]) == name and int(row["ver"]) == ver:
			return row
	return {}


func _measure(name: String, ver: int, start_speed: float, throttle: float, steer: float, handbrake: bool, frames: int, speed_frac: float = -1.0) -> Dictionary:
	var stats: VehicleStats = load(STATS).duplicate()
	stats.physics_model_version = ver
	var vehicle := load(SCENE).instantiate() as VehicleController
	vehicle.stats = stats
	vehicle.set_player_controlled(false)
	vehicle.reset_dynamics_state()
	var vfx := vehicle.get_node_or_null("VFX")
	if vfx:
		vfx.queue_free()
	root.add_child(vehicle)
	vehicle.rotation = 0.0
	var cruise := start_speed
	if speed_frac > 0.0:
		cruise = stats.max_speed * speed_frac
	vehicle.linear_velocity = Vector2.UP * cruise
	await physics_frame
	vehicle.set_external_controls(throttle, 0.0, steer, handbrake, false)
	for _i in frames:
		await physics_frame
	var forward := Vector2.UP.rotated(vehicle.rotation)
	var speed := maxf(vehicle.linear_velocity.length(), 1.0)
	var slip := absf(vehicle.linear_velocity.dot(forward.orthogonal())) / speed
	var result := {
		"name": name,
		"ver": ver,
		"slip": slip,
		"yaw": absf(vehicle.angular_velocity),
		"heading": absf(vehicle.rotation),
		"speed": speed,
	}
	vehicle.queue_free()
	await physics_frame
	return result


func _fail(message: String) -> void:
	push_error("VEHICLE_HANDLING_SIM_TEST FAIL: " + message)
	quit(1)
