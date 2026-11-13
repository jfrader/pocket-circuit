extends SceneTree

const CARRY := preload("res://scripts/vehicle/surface_carry.gd")
const DATA := preload("res://scripts/race/track_builder_catalog.gd")
const VEHICLE := preload("res://scripts/vehicle/vehicle_controller.gd")
const ZONE := preload("res://scripts/race/surface_zone.gd")
const TRAIL := preload("res://scripts/vehicle/surface_trail_painter.gd")
const PRESENTER := preload("res://scripts/presentation/track_variant_presenter.gd")
const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const AI := preload("res://scripts/vehicle/ai_vehicle_controller.gd")
const FIXED_FPS := 60
const DELTA := 1.0 / FIXED_FPS

var _failed := false


class RecordingTrail extends TRAIL:
	var commands: Array[Dictionary] = []

	func _draw_segment(start: Vector2, end: Vector2, tint: Color) -> void:
		commands.append({"start": start, "end": end, "color": tint})


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_rates_and_overlaps()
	_test_determinism()
	_test_profiles()
	_test_trail_draw_commands()
	await _test_race_identity_and_finish()
	await _test_ai_carried_grip()
	await _test_controller_and_cleanup()
	await _test_live_zone()
	await _test_sticky_recovery()
	_test_generated_profiles()
	if _failed:
		quit(1)
		return
	print("SURFACE_CARRY_TEST PASS")
	quit(0)


func _test_rates_and_overlaps() -> void:
	for profile: Dictionary in [DATA.DUST_CARRY, DATA.PAPER_CARRY, DATA.SLOPPY_CARRY, DATA.OIL_CARRY, DATA.STICKY_CARRY]:
		var carry := CARRY.new()
		carry.enter(1, &"material", profile)
		carry.step(0.25)
		_expect(is_equal_approx(carry.amount, float(profile["build_rate"]) * 0.25), "carry builds at the configured rate")
		carry.step(10.0)
		_expect(is_equal_approx(carry.amount, 1.0), "carry saturates at one")
		_expect(is_equal_approx(carry.grip_multiplier, 1.0 - float(profile["grip_penalty"])), "grip penalty scales with carry")
		carry.leave(1)
		carry.step(0.25)
		_expect(is_equal_approx(carry.amount, 1.0 - float(profile["decay_rate"]) * 0.25), "carry decays at its configured rate")
		carry.step(10.0)
		_expect(carry.amount == 0.0 and carry.layers.is_empty() and carry.grip_multiplier == 1.0 and carry.steering_noise == 0.0, "dry tyres remove transient state entirely")
	var overlap := CARRY.new()
	overlap.enter(1, &"dust", DATA.DUST_CARRY)
	overlap.enter(2, &"dust", DATA.DUST_CARRY)
	overlap.step(0.5)
	_expect(is_equal_approx(overlap.amount, 0.4), "same material never double-builds")
	overlap.leave(2)
	overlap.step(0.5)
	_expect(is_equal_approx(overlap.amount, 0.8), "leaving one of two contacts keeps building")
	overlap.enter(3, &"water", DATA.SLOPPY_CARRY)
	overlap.leave(1)
	overlap.step(0.25)
	_expect(is_equal_approx(float(overlap.layers[&"dust"]["amount"]), 0.7125), "previous material decays while a new one builds")
	_expect(is_equal_approx(float(overlap.layers[&"water"]["amount"]), 0.5), "new material has an independent curve")
	overlap.reset()
	_expect(overlap.layers.is_empty() and overlap.amount == 0.0, "recovery clears coating")
	var single := CARRY.new()
	var stacked := CARRY.new()
	var reversed := CARRY.new()
	single.enter(1, &"bench oil", DATA.OIL_CARRY)
	stacked.enter(1, &"bench oil", DATA.OIL_CARRY)
	stacked.enter(2, &"oil slick", DATA.OIL_CARRY)
	reversed.enter(2, &"oil slick", DATA.OIL_CARRY)
	reversed.enter(1, &"bench oil", DATA.OIL_CARRY)
	for tick in 180:
		for carry in [single, stacked, reversed]:
			carry.step(DELTA)
		_expect(single.amount == stacked.amount and single.grip_multiplier == stacked.grip_multiplier and single.steering_noise == stacked.steering_noise, "differently named identical coatings never double-charge grip or wander")
	_expect(stacked.grip_multiplier == reversed.grip_multiplier and stacked.color == reversed.color, "overlap result ignores entry order")
	stacked.enter(3, &"water", DATA.SLOPPY_CARRY)
	stacked.leave(1)
	stacked.leave(2)
	stacked.step(0.4)
	_expect(is_equal_approx(stacked.amount, 0.84) and is_equal_approx(stacked.grip_multiplier, 1.0 - 0.84 * float(DATA.OIL_CARRY["grip_penalty"])) and stacked.color == DATA.OIL_CARRY["color"], "highest remaining contribution owns its complete profile, not the newest contact")


func _test_determinism() -> void:
	var first := CARRY.new()
	var second := CARRY.new()
	var other := CARRY.new()
	first.set_seed(1427)
	second.set_seed(1427)
	other.set_seed(9671)
	for carry in [first, second, other]:
		carry.enter(1, &"water", DATA.SLOPPY_CARRY)
	var differs := false
	var nonzero := false
	var previous := 0.0
	for tick in 240:
		first.step(DELTA)
		second.step(DELTA)
		other.step(DELTA)
		_expect(first.steering_noise == second.steering_noise, "fixed seed reproduces every steering sample")
		_expect(absf(first.steering_noise) <= float(DATA.SLOPPY_CARRY["steering_noise"]), "noise is bounded by profile amplitude")
		_expect(absf(first.steering_noise - previous) < 0.02, "noise wanders smoothly rather than jumping each tick")
		previous = first.steering_noise
		differs = differs or not is_equal_approx(first.steering_noise, other.steering_noise)
		nonzero = nonzero or absf(first.steering_noise) > 0.01
	_expect(differs and nonzero, "seed matters and steering noise is not a zero stub")


func _test_profiles() -> void:
	var catalog := DATA.catalog()
	for stories: Array in (catalog["story_kits"] as Dictionary).values():
		for story: Dictionary in stories:
			for surface: Dictionary in story["surfaces"]:
				_expect(surface.has("carry") and (surface["carry"] as Dictionary).size() == 5, "every story surface defines a full carry profile")
	for layout: Dictionary in (catalog["layouts"] as Dictionary).values():
		for surface: Dictionary in layout["grip_patches"]:
			_expect(surface.has("carry"), "every patch/debris material has a carry profile")


func _make_vehicle(world: Node2D, player: bool) -> VehicleController:
	var car := VEHICLE.new() as VehicleController
	var visual := Node2D.new()
	visual.name = "VisualRoot"
	var sprite := Sprite2D.new()
	sprite.name = "CarSprite"
	visual.add_child(sprite)
	car.add_child(visual)
	car.set_player_controlled(player)
	car.freeze = true
	world.add_child(car)
	car.set_physics_process(false)
	car.start_surface_carry(1427, 0)
	return car


func _test_race_identity_and_finish() -> void:
	var baseline := get_node_count()
	var samples: Array[float] = []
	for replay in 2:
		var world := Node2D.new()
		root.add_child(world)
		var manager := RaceManager.new()
		world.add_child(manager)
		manager.set_physics_process(false)
		manager.race_seed = 1427
		var first := _make_vehicle(world, true)
		var second := _make_vehicle(world, false)
		for car in [first, second]:
			car.configure_identity("Same driver", "Rustbug", "rustbug")
			manager.register_racer(car, "Same driver", "Rustbug", car == first)
		manager.prepare_race()
		for car in [first, second]:
			car.apply_surface_modifier(1, &"wet", 0.8, 1.0, DATA.SLOPPY_CARRY)
		for tick in 10 + replay * 15:
			first._physics_process(DELTA)
		_expect(first.surface_carry.amount == 0.0, "countdown contact does not acquire carry or advance race noise")
		manager.start_race()
		var differs := false
		for tick in 30:
			for car in [first, second]:
				car.update_surface_carry(DELTA)
			if replay == 0:
				samples.append(first.surface_carry.steering_noise)
			else:
				_expect(first.surface_carry.steering_noise == samples[tick], "production race seed reproduces despite different countdown lengths")
			differs = differs or not is_equal_approx(first.surface_carry.steering_noise, second.surface_carry.steering_noise)
		_expect(differs, "same-livery racers receive distinct slot-seeded noise, including the player")
		var phase_sample := first.surface_carry.steering_noise
		first.configure_identity("Cosmetic change", "Rustbug", "rustbug")
		_expect(first.surface_carry.steering_noise == phase_sample, "cosmetics do not reset gameplay noise")
		first.position += Vector2(5.0, 0.0)
		first.update_surface_carry(0.1)
		_expect(first.surface_trail.active_segments() == 2, "two tyre marks emitted before finish")
		var trail_id := first.surface_trail.get_instance_id()
		var carry_ref: WeakRef = weakref(first.surface_carry)
		manager._finish_racer(first, manager._racers[first])
		for tick in 60:
			first.apply_surface_modifier(1, &"wet", 0.8, 1.0, DATA.SLOPPY_CARRY)
			first.position += Vector2(5.0, 0.0)
			first._physics_process(DELTA)
		_expect(first.surface_carry.amount == 0.0 and first.surface_carry.layers.is_empty(), "finish inside a zone stops acquisition")
		_expect(first.surface_trail.active_segments() == 0, "finish clears existing marks and emits no new segments")
		_expect(first.get_node("VisualRoot/CarSprite").modulate == Color.WHITE, "finish clears coating tint")
		manager.stop_race()
		world.queue_free()
		await process_frame
		_expect(not is_instance_id_valid(trail_id) and carry_ref.get_ref() == null and get_node_count() == baseline, "finished race teardown releases carry and trail without node leaks")


func _test_controller_and_cleanup() -> void:
	var baseline := get_node_count()
	var shared_stats: Resource = load("res://data/vehicles/rustbug.tres")
	var before := _resource_values(shared_stats)
	for race in 4:
		var world := Node2D.new()
		root.add_child(world)
		var player := _make_vehicle(world, true)
		var ai := _make_vehicle(world, false)
		_expect(player.stats == ai.stats and player.stats == shared_stats, "both modes really share the immutable resource")
		player.surface_grip_multiplier = 0.7
		player.surface_speed_multiplier = 0.8
		player.update_surface_carry(DELTA)
		_expect(player.surface_grip_multiplier == 0.7 and player.surface_speed_multiplier == 0.8, "dry coating does not overwrite public surface overrides used by physics probes")
		player.reset_surface_modifiers()
		var zone := ZONE.new() as SurfaceZone
		world.add_child(zone)
		zone.configure(&"dust", PackedVector2Array([Vector2(-40, -40), Vector2(40, -40), Vector2(40, 40), Vector2(-40, 40)]), 0.8, 0.75, Color.TRANSPARENT, "", DATA.DUST_CARRY)
		# Exercise the actual zone-to-controller API, including debris's identical path.
		zone.set_meta("role", &"debris")
		zone._on_body_entered(player)
		zone._on_body_entered(ai)
		Input.action_press("accelerate", 1.0)
		Input.action_press("steer_right", 0.2)
		ai.set_external_controls(1.0, 0.0, 0.2)
		var trail_id := player.surface_trail.get_instance_id()
		var carry_ref: WeakRef = weakref(player.surface_carry)
		for tick in 300:
			if tick == 120:
				zone._on_body_exited(player)
				zone._on_body_exited(ai)
			player.position = Vector2(tick * 4.0, 0.0)
			ai.position = Vector2(tick * 4.0, 200.0)
			player._physics_process(DELTA)
			ai._physics_process(DELTA)
			_expect(player.surface_carry.amount == ai.surface_carry.amount, "player and AI share every build/decay sample")
			_expect(is_equal_approx(player._steer_input, ai._steer_input), "both inputs receive identical seeded steering wander")
			var expected_steer := clampf(0.2 + player.surface_carry.steering_noise, -1.0, 1.0)
			_expect(is_equal_approx(player._steer_input, expected_steer) and is_equal_approx(ai._steer_input, expected_steer), "player and external controls apply the actual noise sample")
			if tick == 60:
				var phase := float(posmod("0:1427".hash(), 65536)) / 65536.0 * TAU
				var elapsed := 61.0 * DELTA
				var weight := float(DATA.DUST_CARRY["build_rate"]) * elapsed
				var noise := float(DATA.DUST_CARRY["steering_noise"]) * weight * lerpf(sin(elapsed * 4.1 + phase * 1.7), sin(elapsed * 2.3 + phase), 0.65)
				_expect(absf(noise) > 0.001 and is_equal_approx(player._steer_input, 0.2 + noise) and is_equal_approx(ai._steer_input, 0.2 + noise), "known seeded steering delta is nonzero on both production input paths")
				_expect(player.get_node("VisualRoot/CarSprite").modulate != Color.WHITE, "coating visibly tints existing car sprite")
				_expect(player.surface_grip_multiplier < 0.8, "contact grip also includes carry penalty")
			if tick == 120:
				_expect(player.surface_grip_multiplier < 1.0 and player.surface_speed_multiplier == 1.0, "grip carry persists after contact speed clears")
			_expect(player.surface_trail.active_segments() <= TRAIL.MAX_SEGMENTS, "trail ring buffer remains bounded")
		Input.action_release("accelerate")
		Input.action_release("steer_right")
		_expect(player.surface_carry.amount == 0.0, "controller coating reaches zero after exit")
		_expect(player.get_node("VisualRoot/CarSprite").modulate == Color.WHITE, "clean tyre tint is restored")
		_expect(player.surface_trail.active_segments() > 0, "controller emits segments into its bounded trail node")
		_expect(player.surface_trail.global_transform == Transform2D.IDENTITY, "world-space trail does not inherit car movement or rotation")
		player.update_surface_carry(TRAIL.LIFETIME)
		_expect(player.surface_trail.active_segments() == 0, "trail fades away with time even when stationary")
		_expect(player.surface_trail.get_child_count() == 0, "trail has no per-segment nodes, physics or zones")
		_expect(_resource_values(shared_stats) == before, "every stored VehicleStats property is unchanged after a carry cycle")
		player.reset_surface_modifiers()
		world.queue_free()
		await process_frame
		_expect(not is_instance_id_valid(trail_id) and carry_ref.get_ref() == null, "race teardown releases trail node and coating state")
		_expect(get_node_count() == baseline, "node count returns to baseline across repeated races")


func _resource_values(resource: Resource) -> Dictionary:
	var values := {}
	for property: Dictionary in resource.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_STORAGE:
			values[property["name"]] = resource.get(property["name"])
	return values


func _test_trail_draw_commands() -> void:
	var painter := RecordingTrail.new()
	root.add_child(painter)
	var nodes := get_node_count()
	painter.step(0.1, Transform2D.IDENTITY, Color.RED, 0.5)
	painter.step(0.1, Transform2D(0.0, Vector2(10.0, 0.0)), Color.RED, 0.5)
	painter._draw()
	_expect(painter.active_segments() == 2 and painter.commands.size() == 2, "two tyre segments produce exactly two draw commands")
	if painter.commands.size() == 2:
		var first: Dictionary = painter.commands[0]
		_expect(first["start"] == Vector2(-14.0, 22.0) and first["end"] == Vector2(-4.0, 22.0), "draw commands contain emitted world-space tyre geometry")
		_expect(is_equal_approx((first["color"] as Color).a, 0.5 * TRAIL.OPACITY), "draw command carries coating opacity")
		painter.commands.clear()
		painter.step(TRAIL.LIFETIME * 0.5, Transform2D.IDENTITY, Color.WHITE, 0.0)
		painter._draw()
		_expect(painter.commands.size() == 2 and is_equal_approx((painter.commands[0]["color"] as Color).a, 0.25 * TRAIL.OPACITY), "drawn segments fade to half alpha halfway through lifetime")
	painter.commands.clear()
	painter.step(TRAIL.LIFETIME, Transform2D.IDENTITY, Color.WHITE, 0.0)
	painter._draw()
	_expect(painter.commands.is_empty() and painter.active_segments() == 0, "expired marks issue no draw commands")
	_expect(painter.get_child_count() == 0 and get_node_count() == nodes, "emitting and fading allocate no per-segment nodes")
	painter.free()


func _test_ai_carried_grip() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var car := _make_vehicle(world, false)
	var manager := RaceManager.new()
	world.add_child(manager)
	manager.set_physics_process(false)
	manager.register_racer(car, "AI", "Rustbug")
	var ai := AI.new() as AIVehicleController
	car.add_child(ai)
	ai.configure(car, manager, 0.0)
	ai.set_physics_process(false)
	var plan := {"risk": 0.8, "grip_scale": 0.48}
	var dry_grip := ai._planned_surface_grip(plan)
	var dry_target := ai._surface_driving_speed_scale(1.0, 0.48, Vector2.RIGHT)
	ai._anticipated_grip = dry_grip
	ai._prepare_v1_speed_envelope()
	var dry_braking := ai._envelope_braking_accel
	var dry_corner := ai._prepared_v1_speed_envelope(100.0, 0.0)
	car.apply_surface_modifier(1, &"sticky", 1.0, 1.0, DATA.STICKY_CARRY)
	car.update_surface_carry(10.0)
	var carried_grip := ai._planned_surface_grip(plan)
	_expect(is_equal_approx(carried_grip, 0.48 * 0.58), "AI anticipates zone grip multiplied by existing carried grip")
	_expect(ai._surface_driving_speed_scale(1.0, 0.48, Vector2.RIGHT) < dry_target, "AI correction speed target accounts for carried grip")
	ai._anticipated_grip = carried_grip
	ai._prepare_v1_speed_envelope()
	_expect(ai._envelope_braking_accel < dry_braking and ai._prepared_v1_speed_envelope(100.0, 0.0) < dry_corner, "AI braking capacity and corner target decrease before entering the upcoming zone")
	world.queue_free()
	await process_frame


func _test_live_zone() -> void:
	Engine.physics_ticks_per_second = FIXED_FPS
	var world := Node2D.new()
	root.add_child(world)
	var car := _make_vehicle(world, false)
	car.set_controls_locked(true)
	car.freeze = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	car.add_child(shape)
	car.collision_layer = 1
	var zone := ZONE.new() as SurfaceZone
	world.add_child(zone)
	zone.configure(&"suds", PackedVector2Array([Vector2(-40, -40), Vector2(40, -40), Vector2(40, 40), Vector2(-40, 40)]), 0.8, 0.9, Color.TRANSPARENT, "", DATA.SLOPPY_CARRY)
	car.set_physics_process(true)
	for tick in 20:
		await physics_frame
	_expect(zone.overlaps_body(car), "real physics overlap detects the vehicle")
	var built := car.surface_carry.amount
	_expect(built > 0.1 and built < 1.0, "real body-entered signal builds carry over physics ticks")
	car.position = Vector2(500.0, 0.0)
	for tick in 10:
		await physics_frame
	_expect(not zone.overlaps_body(car), "real physics exit clears contact")
	_expect(car.surface_carry.amount > 0.0 and car.surface_carry.amount < built, "real body-exited signal leaves decaying coating")
	zone.queue_free()
	for tick in 100:
		await physics_frame
	_expect(car.surface_carry.amount == 0.0 and car.surface_grip_multiplier == 1.0, "live coating decays to dry grip")
	world.queue_free()
	await process_frame


func _test_generated_profiles() -> void:
	var saw_debris := false
	for theme: StringName in [&"kitchen", &"workshop", &"office"]:
		var track := (BUILDER.build_packed(theme, &"classic", 23757)["scene"] as PackedScene).instantiate() as Node2D
		var definitions: Array = track.get_meta("generated_surfaces", [])
		_expect(not definitions.is_empty(), "generated track supplies physical surfaces")
		for definition: Dictionary in definitions:
			_expect(definition.has("carry") and not (definition.get("carry", {}) as Dictionary).is_empty(), "builder preserves carry for technical, shortcut, patch and debris definitions")
			saw_debris = saw_debris or StringName(definition["role"]) == &"debris"
		var presenter := PRESENTER.new() as TrackVariantPresenter
		track.add_child(presenter)
		presenter.configure(track, theme)
		_expect(presenter.surface_zones.size() == definitions.size(), "presenter instantiates all generated zones")
		for index in definitions.size():
			_expect(presenter.surface_zones[index].carry_profile == definitions[index]["carry"], "presenter forwards carry even with transparent zone visuals")
		track.free()
	_expect(saw_debris, "generated profile coverage includes actual corner debris")


func _test_sticky_recovery() -> void:
	_expect(1.0 / float(DATA.STICKY_CARRY["decay_rate"]) <= 4.0, "saturated sticky carry clears within four seconds after exit")
	for vehicle_id: String in ["rustbug", "pinbolt", "scrapjaw", "flicker"]:
		var world := Node2D.new()
		root.add_child(world)
		var car := (load("res://scenes/vehicles/rustbug.tscn") as PackedScene).instantiate() as VehicleController
		car.stats = load("res://data/vehicles/%s.tres" % vehicle_id)
		car.set_player_controlled(false)
		world.add_child(car)
		car.set_physics_process(false)
		car.start_surface_carry(1427, 0)
		car.apply_surface_modifier(1, &"sticky", 0.55, 1.0, DATA.STICKY_CARRY)
		car.update_surface_carry(10.0)
		_expect(is_equal_approx(car.surface_grip_multiplier, 0.319), "saturated sticky on a low-grip patch retains configured grip")
		car.clear_surface_modifier(1)
		car.linear_velocity = Vector2.UP * 280.0
		car.set_external_controls(0.5, 0.25, 0.6)
		car.set_physics_process(true)
		for tick in 30:
			await physics_frame
		var heading := absf(car.rotation)
		_expect(heading > 0.05 and heading < PI * 0.5 and absf(car.position.x) > 10.0, "%s can steer clear with saturated sticky carry without spinning" % vehicle_id)
		car.set_external_controls(0.5, 0.0, 0.0)
		for tick in 210:
			await physics_frame
		_expect(car.surface_carry.amount == 0.0 and car.surface_grip_multiplier == 1.0, "%s recovers dry grip within four seconds" % vehicle_id)
		_expect(is_finite(car.rotation) and car.linear_velocity.is_finite() and absf(car.slip_angle) < 15.0, "%s settles after steering out of sticky carry" % vehicle_id)
		print("STICKY_RECOVERY %s heading=%.3f exit_x=%.2f final_slip=%.3f" % [vehicle_id, heading, car.position.x, car.slip_angle])
		world.queue_free()
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("SURFACE_CARRY_TEST FAIL: " + message)
