extends SceneTree

const CARRY := preload("res://scripts/vehicle/surface_carry.gd")
const DATA := preload("res://scripts/race/track_builder_catalog.gd")
const VEHICLE := preload("res://scripts/vehicle/vehicle_controller.gd")
const ZONE := preload("res://scripts/race/surface_zone.gd")
const TRAIL := preload("res://scripts/vehicle/surface_trail_painter.gd")
const PRESENTER := preload("res://scripts/presentation/track_variant_presenter.gd")
const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const FIXED_FPS := 60
const DELTA := 1.0 / FIXED_FPS

var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_rates_and_overlaps()
	_test_determinism()
	_test_profiles()
	await _test_controller_and_cleanup()
	await _test_live_zone()
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
	car.surface_carry.set_seed(1427)
	return car


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
			if tick == 60:
				_expect(player.get_node("VisualRoot/CarSprite").modulate != Color.WHITE, "coating visibly tints existing car sprite")
				_expect(player.surface_grip_multiplier < 0.8, "contact grip also includes carry penalty")
			if tick == 120:
				_expect(player.surface_grip_multiplier < 1.0 and player.surface_speed_multiplier == 1.0, "grip carry persists after contact speed clears")
			_expect(player.surface_trail.active_segments() <= TRAIL.MAX_SEGMENTS, "trail ring buffer remains bounded")
		Input.action_release("accelerate")
		Input.action_release("steer_right")
		_expect(player.surface_carry.amount == 0.0, "controller coating reaches zero after exit")
		_expect(player.get_node("VisualRoot/CarSprite").modulate == Color.WHITE, "clean tyre tint is restored")
		_expect(player.surface_trail.active_segments() > 0, "trail actually paints, not an empty bounded stub")
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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error("SURFACE_CARRY_TEST FAIL: " + message)
