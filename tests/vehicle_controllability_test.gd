extends SceneTree

## Controllability regression test using real RigidBody2D + VehicleController + external controls.
## Fixed 60Hz, no time scale. 3+ repeats. All 4 cars.
## Scenarios: short taps 300/600 (digital), neutral release residual, S-turn, analog partial,
## brake-turn, deliberate slide recovery.
## NOT formula self-tests; uses actual physics body integration.
## Bounds from released v0 baseline + explicit rationale (high-speed tap must not ~27+20 coast).
## Target for v1: responsive initial, limited overshoot, no widening.
## Prints CONTROLLABILITY_CMP rows + table. Real exit code on fail.

const PHYSICS_HZ := 60
const DELTA := 1.0 / float(PHYSICS_HZ)
const CARS := {
	"rustbug": {"scene": "res://scenes/vehicles/rustbug.tscn", "stats": "res://data/vehicles/rustbug.tres"},
	"pinbolt": {"scene": "res://scenes/vehicles/rustbug.tscn", "stats": "res://data/vehicles/pinbolt.tres"},
	"scrapjaw": {"scene": "res://scenes/vehicles/rustbug.tscn", "stats": "res://data/vehicles/scrapjaw.tres"},
	"flicker": {"scene": "res://scenes/vehicles/rustbug.tscn", "stats": "res://data/vehicles/flicker.tres"},
}

var _world: Node2D
var _failures: int = 0
var _results: Array = []

func _initialize() -> void:
	Engine.physics_ticks_per_second = PHYSICS_HZ
	Engine.time_scale = 1.0
	call_deferred("_run")

func _run() -> void:
	_world = Node2D.new()
	_world.name = "ControllabilityTestWorld"
	root.add_child(_world)
	current_scene = _world

	for car_name in CARS.keys():
		var cfg: Dictionary = CARS[car_name]
		var base_stats: VehicleStats = load(cfg["stats"]).duplicate()
		print("CAR_BASE,%s,ver_default=%d,mass=%.3f,max=%.1f" % [car_name, base_stats.physics_model_version, base_stats.mass, base_stats.max_speed])
		for ver in [0, 1]:
			for rep in range(3):
				# 1. short full digital tap 300
				await _run_tap(car_name, base_stats, ver, rep, 300.0, 1.0, 6, 60)
				# 2. tap 600
				await _run_tap(car_name, base_stats, ver, rep, 600.0, 1.0, 6, 60)
				# 3. analog partial 0.35 @400
				await _run_tap(car_name, base_stats, ver, rep, 400.0, 0.35, 30, 60)
				# 4. S-turn
				await _run_sturn(car_name, base_stats, ver, rep, 400.0, 0.5, 24, 60)
				# 5. brake-turn (steer + brake input)
				await _run_brake_turn(car_name, base_stats, ver, rep, 350.0, 0.7, 8, 60)
				# 6. deliberate slide recovery (handbrake+steer then neutral recover)
				await _run_slide_recovery(car_name, base_stats, ver, rep, 280.0, 0.6, 12, 60)
				await _run_slide_recovery(car_name, base_stats, ver, rep, 500.0, 1.0, 12, 60)

	_world.queue_free()
	await process_frame

	_print_table()

	if _failures > 0:
		push_error("CONTROLLABILITY: %d bound violations (see logs)" % _failures)
		quit(1)
	else:
		print("CONTROLLABILITY: all green (v1 within bounds from baseline)")
		print("VEHICLE_CONTROLLABILITY_TEST PASS")
		quit(0)

func _spawn(car_name: String, stats: VehicleStats) -> RigidBody2D:
	var path: String = CARS[car_name]["scene"]
	var vehicle: RigidBody2D = load(path).instantiate() as RigidBody2D
	if vehicle is VehicleController:
		var vc := vehicle as VehicleController
		vc.stats = stats
		vc.surface_speed_multiplier = 1.0
		vc.surface_grip_multiplier = 1.0
		vc.set_player_controlled(false)
		vc.reset_dynamics_state()
		var vfx := vc.get_node_or_null("VFX")
		if vfx: vfx.queue_free()
	_world.add_child(vehicle)
	vehicle.rotation = 0.0
	vehicle.position = Vector2.ZERO
	vehicle.linear_velocity = Vector2.ZERO
	vehicle.angular_velocity = 0.0
	await physics_frame
	return vehicle

func _remove(v: RigidBody2D) -> void:
	if is_instance_valid(v): v.queue_free()
	await physics_frame

func _set_ctrl(v: RigidBody2D, th: float, br: float, st: float, hb: bool = false) -> void:
	if v.has_method("set_external_controls"):
		v.call("set_external_controls", th, br, st, hb, false)

func _hdg_change(from: float, to: float) -> float:
	var d := rad_to_deg( fmod( (to - from) + TAU , TAU ) )
	if d > 180.0: d -= 360.0
	return d

func _run_tap(car: String, base: VehicleStats, ver: int, rep: int, init: float, st: float, tapf: int, relf: int) -> void:
	var s := base.duplicate() as VehicleStats
	s.physics_model_version = ver
	var v := await _spawn(car, s)
	v.linear_velocity = Vector2.UP * init
	v.angular_velocity = 0.0
	await physics_frame
	var irot := v.rotation
	_set_ctrl(v, 0.0, 0.0, st)
	for _i in range(tapf): await physics_frame
	var rrot := v.rotation
	_set_ctrl(v, 0.0, 0.0, 0.0)
	var max_os := 0.0
	for _i in range(relf):
		await physics_frame
		var dd := absf( _hdg_change(rrot, v.rotation) )
		max_os = maxf(max_os, dd)
	var frot := v.rotation
	var hdur := _hdg_change(irot, rrot)
	var htot := _hdg_change(irot, frot)
	_emit(car, "tap", ver, rep, init, hdur, htot, max_os)
	await _remove(v)

func _run_sturn(car: String, base: VehicleStats, ver: int, rep: int, init: float, mag: float, hf: int, relf: int) -> void:
	var s := base.duplicate() as VehicleStats
	s.physics_model_version = ver
	var v := await _spawn(car, s)
	v.linear_velocity = Vector2.UP * init
	await physics_frame
	var irot := v.rotation
	_set_ctrl(v, 0.0, 0.0, mag)
	for _i in range(hf): await physics_frame
	_set_ctrl(v, 0.0, 0.0, -mag)
	for _i in range(hf): await physics_frame
	var rrot := v.rotation
	_set_ctrl(v, 0.0, 0.0, 0.0)
	var mos := 0.0
	for _i in range(relf):
		await physics_frame
		mos = maxf(mos, absf(_hdg_change(rrot, v.rotation)))
	var hdur := _hdg_change(irot, rrot)
	var htot := _hdg_change(irot, v.rotation)
	_emit(car, "sturn", ver, rep, init, hdur, htot, mos)
	await _remove(v)

func _run_brake_turn(car: String, base: VehicleStats, ver: int, rep: int, init: float, st: float, tapf: int, relf: int) -> void:
	var s := base.duplicate() as VehicleStats
	s.physics_model_version = ver
	var v := await _spawn(car, s)
	v.linear_velocity = Vector2.UP * init
	await physics_frame
	var irot := v.rotation
	_set_ctrl(v, 0.0, 0.4, st)  # brake + steer
	for _i in range(tapf): await physics_frame
	var rrot := v.rotation
	_set_ctrl(v, 0.0, 0.0, 0.0)
	var mos := 0.0
	for _i in range(relf):
		await physics_frame
		mos = maxf(mos, absf(_hdg_change(rrot, v.rotation)))
	var hdur := _hdg_change(irot, rrot)
	var htot := _hdg_change(irot, v.rotation)
	_emit(car, "brake_turn", ver, rep, init, hdur, htot, mos)
	await _remove(v)

func _run_slide_recovery(car: String, base: VehicleStats, ver: int, rep: int, init: float, st: float, tapf: int, relf: int) -> void:
	var s := base.duplicate() as VehicleStats
	s.physics_model_version = ver
	var v := await _spawn(car, s)
	v.linear_velocity = Vector2.UP * init
	await physics_frame
	var irot := v.rotation
	_set_ctrl(v, 1.0 if init >= 500.0 else 0.3, 0.0, st, true)
	for _i in range(tapf): await physics_frame
	var rrot := v.rotation
	_set_ctrl(v, 1.0 if init >= 500.0 else 0.0, 0.0, 0.0, false)
	var mos := 0.0
	for _i in range(relf):
		await physics_frame
		mos = maxf(mos, absf(_hdg_change(rrot, v.rotation)))
	var hdur := _hdg_change(irot, rrot)
	var htot := _hdg_change(irot, v.rotation)
	_emit(car, "slide_recover", ver, rep, init, hdur, htot, mos)
	await _remove(v)

func _emit(car: String, scen: String, ver: int, rep: int, init: float, hdur: float, htot: float, os: float) -> void:
	var row := "CONTROLLABILITY_CMP,%s,%s,%d,rep%d,init=%.1f,hdur=%.2f,htot=%.2f,overshoot=%.2f" % [car, scen, ver, rep, init, hdur, htot, os]
	print(row)
	_results.append({ "car": car, "scen": scen, "ver": ver, "hdur": hdur, "htot": htot, "os": os })
	# Bounds: from released v0 baseline. Rationale: v0 high tap ~9deg total/4deg os arcade; v1 must not regress to 27+20.
	# Do not widen. High-speed tap cannot coast 20deg after release.
	if ver == 1:
		if scen == "slide_recover" and os > (45.0 if init >= 500.0 else 30.0):
			_failures += 1
			push_error("Released handbrake must restore grip without a spin: %s %.2f degrees" % [car, os])
		if scen == "tap" and init > 550.0:
			if car == "rustbug":
				if absf(htot) > 15.0 or os > 7.0:
					_failures += 1
					print("BOUND_FAIL,rustbug,tap600,htot=%.2f>15,os=%.2f>7" % [htot, os])
			else:
				if absf(htot) > 18.0 or os > 9.0:
					_failures += 1
					print("BOUND_FAIL,%s,tap600,htot=%.2f>18,os=%.2f>9" % [car, htot, os])
		# analog/sustained not bounded strictly (v1 has distinct cornering); only tap transients per task spec


func _print_table() -> void:
	print("\n=== CONTROLLABILITY v0/v1 (RB2D 60Hz x3, all cars) ===")
	print("car,scen,ver,avg_hdur,avg_htot,avg_os")
	var groups := {}
	for r in _results:
		var k := "%s_%s_v%d" % [r.car, r.scen, r.ver]
		if not groups.has(k): groups[k] = []
		groups[k].append(r)
	for car in CARS.keys():
		for scen in ["tap", "sturn", "brake_turn", "slide_recover"]:
			for ver in [0,1]:
				var k := "%s_%s_v%d" % [car, scen, ver]
				if not groups.has(k): continue
				var arr: Array = groups[k]
				var n := arr.size()
				var ah := 0.0; var at := 0.0; var ao := 0.0
				for x in arr:
					ah += x.hdur; at += x.htot; ao += x.os
				print("%s,%s,v%d,%.2f,%.2f,%.2f" % [car, scen, ver, ah/n, at/n, ao/n])
	print("=== END (bounds enforced only on v1; see CMP lines) ===\n")
