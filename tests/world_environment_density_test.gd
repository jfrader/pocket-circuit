extends SceneTree

const CORE := preload("res://scripts/race/track_builder_core.gd")
const CIRCUITS := preload("res://scripts/race/generated_circuit_identity.gd")
const CATALOG := preload("res://scripts/race/world_environment_catalog.gd")
const PLANNER := preload("res://scripts/race/world_environment_plan.gd")
const CASES := {"kitchen":[0,4], "workshop":[0,1], "office":[0,1]}
const RESTORED_ASSETS := {"kitchen":"res://assets/textures/track_boundary/kitchen_chopstick_rail.png", "workshop":"res://assets/textures/track_boundary/workshop_dowel_rail.png", "office":"res://assets/textures/track_boundary/office_pen_rail.png"}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var settings := CATALOG.boundary_density()
	if not _expect(int(settings["minimum"]) > 8, "configured density must exceed the former eight-attempt ceiling"): return
	var long_counts := {}
	for seed_value in 8:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var target := int(PLANNER._run_targets(48000.0, settings, rng)["members"])
		if not _expect(target >= int(settings["minimum"]) and target <= int(settings["maximum"]), "target within bounds"): return
		long_counts[target] = true
	if not _expect(long_counts.size() >= 3, "long circuits must retain count variation rather than all saturate at the cap"): return
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
			if not _expect(plan["diagnostics"].get("open_exit", PackedVector2Array()).size() == 2, "dense dressing must reserve an actual exit, not only an empty sector label"): return
			if not _expect(float(plan["diagnostics"]["open_exit_width"]) >= CORE.MIN_VIABLE_CORRIDOR_WIDTH, "viable corridor width"): return
			if not _expect(count >= int(settings["minimum"]), "representative tracks must realize the configured minimum boundary density"): return
			if not _expect(count <= int(plan["diagnostics"]["boundary_target"]) and count <= int(settings["maximum"]), "count within bounds"): return
			boundary_counts[count] = true
			targets[plan["diagnostics"]["boundary_target"]] = true
			obstacle_counts[spec["obstacle_plan"].size()] = true
			var candidate_ids := {}
			for candidate: Dictionary in spec["environment_assets"]:
				if "boundary" in candidate["roles"]:
					candidate_ids[candidate["id"]] = true
			if not _expect(candidate_ids.has(CATALOG.for_path(RESTORED_ASSETS[theme])["id"]), "the existing boundary asset family must reach the new planner"): return
			for placement: Dictionary in plan["placements"]:
				var asset := CATALOG.get_asset(placement["asset_id"])
				var shape := TrackBuilderBoundary._footprint_polygon(placement["position"], asset["dimensions_mm"], placement["rotation"])
				if asset["collision"] != "flat":
					for obstacle: Dictionary in spec["obstacle_plan"]:
						var obstacle_shape := TrackBuilderBoundary._footprint_polygon(obstacle["position"], obstacle["footprint_size"], obstacle["rotation"])
						if not _expect(Geometry2D.intersect_polygons(shape, obstacle_shape).is_empty(), "environment and on-course obstacles must not overlap"): return
				if placement["role"] == "boundary":
					if not _expect(asset["collision"] != "flat", "boundary props must have physical collision"): return
					seen_assets[asset["id"]] = true
					if not _expect(CORE._line_sweep_clears_footprint(prepared["centerline"], placement["position"], asset["dimensions_mm"], &"rect", placement["rotation"], CORE.HALF_WIDTH + float(asset["clearance_mm"])), "clears footprint"): return
					var nearest := CORE._closest_point_on_loop(placement["position"], prepared["centerline"])
					var sector := mini(PLANNER.SECTOR_COUNT - 1, int(float(nearest["index"]) / prepared["centerline"].size() * PLANNER.SECTOR_COUNT))
					if not _expect(sector != int(plan["diagnostics"]["open_sector"]), "a true open apron sector must survive"): return
			if seed_value == int(CASES[theme][0]):
				var repeated := CORE.prepare_layout(StringName(theme), room, seed_value, options)
				if not _expect(plan == repeated["spec"]["environment_plan"], "density and placements must be deterministic"): return
		if not _expect(boundary_counts.size() >= 2 and targets.size() >= 2, "boundary quantity must vary across seeds"): return
		if not _expect(obstacle_counts.size() >= 2, "on-course obstacle quantity must vary across seeds"): return
		if not _expect(seen_assets.size() >= 2, "richer boundaries must use varied assets, not one repeated fence"): return
		if not _expect(seen_assets.has(CATALOG.for_path(RESTORED_ASSETS[theme])["id"]), "restored rail assets must actually be placed, not merely listed"): return
		print("DENSITY_RANGE ", theme, " boundaries=", boundary_counts.keys(), " obstacles=", obstacle_counts.keys(), " assets=", seen_assets.size())
	if _failed:
		return
	print("WORLD_ENVIRONMENT_DENSITY_TEST PASS varied_counts_shared_assets_collision_clearance_open_apron")
	quit(0)

var _failed := false
func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error("FAIL: " + message)
		quit(1)
		return false
	return true
