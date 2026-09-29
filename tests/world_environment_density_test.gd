extends SceneTree

const CORE := preload("res://scripts/race/track_builder_core.gd")
const CIRCUITS := preload("res://scripts/race/generated_circuit_identity.gd")
const CATALOG := preload("res://scripts/race/world_environment_catalog.gd")
const PLANNER := preload("res://scripts/race/world_environment_plan.gd")
const CASES := {"kitchen":[0,1,4,5,7,8,10,11], "workshop":[0,1,2,4,5,11,13,20], "office":[0,1,3,5,6,8,14,23]}
const RESTORED_ASSETS := {"kitchen":"res://assets/textures/track_boundary/kitchen_chopstick_rail.png", "workshop":"res://assets/textures/track_boundary/workshop_dowel_rail.png", "office":"res://assets/textures/track_boundary/office_pen_rail.png"}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var settings := CATALOG.boundary_density()
	assert(int(settings["minimum"]) > 8, "configured density must exceed the former eight-attempt ceiling")
	var long_counts := {}
	for seed_value in 64:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var target := PLANNER._boundary_target(48000.0, settings, rng)
		assert(target >= int(settings["minimum"]) and target <= int(settings["maximum"]))
		long_counts[target] = true
	assert(long_counts.size() >= 8, "long circuits must retain count variation rather than all saturate at the cap")
	for theme: String in CASES:
		var boundary_counts := {}
		var obstacle_counts := {}
		var targets := {}
		var seen_assets := {}
		for seed_value: int in CASES[theme]:
			var room := CIRCUITS.room_for_route_seed(seed_value)
			var identity := CIRCUITS.create(StringName(theme), room, seed_value)
			var options := CIRCUITS.generation_options(identity)
			var prepared := CORE.prepare_layout(StringName(theme), room, seed_value, options)
			assert(not prepared.is_empty())
			var spec: Dictionary = prepared["spec"]
			var plan: Dictionary = spec["environment_plan"]
			var count := int(plan["diagnostics"]["boundary_count"])
			assert(plan["diagnostics"].get("open_exit", PackedVector2Array()).size() == 2, "dense dressing must reserve an actual exit, not only an empty sector label")
			assert(float(plan["diagnostics"]["open_exit_width"]) >= CORE.MIN_VIABLE_CORRIDOR_WIDTH)
			assert(count >= int(settings["minimum"]), "representative tracks must realize the configured minimum boundary density")
			assert(count <= int(plan["diagnostics"]["boundary_target"]) and count <= int(settings["maximum"]))
			boundary_counts[count] = true
			targets[plan["diagnostics"]["boundary_target"]] = true
			obstacle_counts[spec["obstacle_plan"].size()] = true
			var candidate_ids := {}
			for candidate: Dictionary in spec["environment_assets"]:
				if "boundary" in candidate["roles"]:
					candidate_ids[candidate["id"]] = true
			assert(candidate_ids.has(CATALOG.for_path(RESTORED_ASSETS[theme])["id"]), "the existing boundary asset family must reach the new planner")
			for placement: Dictionary in plan["placements"]:
				var asset := CATALOG.get_asset(placement["asset_id"])
				var shape := TrackBuilderBoundary._footprint_polygon(placement["position"], asset["dimensions_mm"], placement["rotation"])
				if asset["collision"] != "flat":
					for obstacle: Dictionary in spec["obstacle_plan"]:
						var obstacle_shape := TrackBuilderBoundary._footprint_polygon(obstacle["position"], obstacle["footprint_size"], obstacle["rotation"])
						assert(Geometry2D.intersect_polygons(shape, obstacle_shape).is_empty(), "environment and on-course obstacles must not overlap")
					var hazard: Dictionary = spec["hazard_plan"]
					if hazard["present"]:
						var half_size: Vector2 = hazard["footprint_size"] * 0.5
						for path: PackedVector2Array in hazard["paths"].values():
							var bounds := CORE._polygon_bounds_rect(path).grow_individual(half_size.x,half_size.y,half_size.x,half_size.y)
							assert(Geometry2D.intersect_polygons(shape,CORE._rect_points(bounds.get_center(),bounds.size)).is_empty(), "scenery must not block either hazard sweep")
				if placement["role"] == "boundary":
					assert(asset["collision"] != "flat", "boundary props must have physical collision")
					seen_assets[asset["id"]] = true
					assert(CORE._line_sweep_clears_footprint(prepared["centerline"], placement["position"], asset["dimensions_mm"], &"rect", placement["rotation"], CORE.HALF_WIDTH + float(asset["clearance_mm"])))
					var nearest := CORE._closest_point_on_loop(placement["position"], prepared["centerline"])
					var sector := mini(PLANNER.SECTOR_COUNT - 1, int(float(nearest["index"]) / prepared["centerline"].size() * PLANNER.SECTOR_COUNT))
					assert(sector != int(plan["diagnostics"]["open_sector"]), "a true open apron sector must survive")
			if seed_value == int(CASES[theme][0]):
				var repeated := CORE.prepare_layout(StringName(theme), room, seed_value, options)
				assert(plan == repeated["spec"]["environment_plan"], "density and placements must be deterministic")
			await process_frame
		assert(boundary_counts.size() >= 3 and targets.size() >= 3, "boundary quantity must vary across seeds")
		assert(obstacle_counts.size() >= 3, "on-course obstacle quantity must vary across seeds")
		assert(seen_assets.size() >= 5, "richer boundaries must use varied assets, not one repeated fence")
		assert(seen_assets.has(CATALOG.for_path(RESTORED_ASSETS[theme])["id"]), "restored rail assets must actually be placed, not merely listed")
		print("DENSITY_RANGE ", theme, " boundaries=", boundary_counts.keys(), " obstacles=", obstacle_counts.keys(), " assets=", seen_assets.size())
	print("WORLD_ENVIRONMENT_DENSITY_TEST PASS varied_counts_shared_assets_collision_clearance_open_apron")
	quit(0)
