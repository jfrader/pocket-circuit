extends SceneTree
const CORE := preload("res://scripts/race/track_builder_core.gd")
const IDS := preload("res://scripts/race/generated_circuit_identity.gd")
const CATALOG := preload("res://scripts/race/world_environment_catalog.gd")
const CASES := {"kitchen":[0,1,4,5,7,8,10,11], "workshop":[0,1,2,4,5,11,13,20], "office":[0,1,3,5,6,8,14,23]}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not _atomic_failure(): return
	for theme: String in CASES:
		var placed_families := {}
		for seed_value: int in CASES[theme]:
			var identity := IDS.create(StringName(theme),IDS.room_for_route_seed(seed_value),seed_value)
			var prepared := CORE.prepare_layout(StringName(theme),StringName(identity["room"]),seed_value,IDS.generation_options(identity))
			var plan: Dictionary = prepared["spec"]["environment_plan"]
			var runs: Array = plan.get("boundary_runs",[])
			if not _check(runs.size() >= 4,"missing coherent outer sets: %s/%d" % [theme,seed_value]): return
			var major := 0
			var pegs := 0
			var families := {}
			var covered := 0.0
			for run: Dictionary in runs:
				placed_families[run["asset_id"]] = true
				if not _check(run["side"] == "outer","an inner fallback cannot satisfy an outer run"): return
				var members: Array = []
				for placement: Dictionary in plan["placements"]:
					if placement.get("boundary_run_id","") == run["id"]:
						members.append(placement)
				if not _check(members.size() >= 3 and members.size() == int(run["member_count"]),"a run must be a completed physical set"): return
				var previous := -INF
				var previous_front := Vector2.INF
				for member: Dictionary in members:
					var asset := CATALOG.get_asset(member["asset_id"])
					if not _check(member["zone"] == "apron" and member["asset_id"] == run["asset_id"] and asset["collision"] != "flat","outer members must be coherent solid objects outside the course"): return
					if not _check(float(member["boundary_arc_start"]) > previous,"members must advance from the actual fitted arc"): return
					if is_finite(previous) and not _check(float(member["boundary_arc_start"]) - previous <= 25.0,"outer set must not scatter into isolated objects"): return
					if previous_front.is_finite() and not _check(previous_front.distance_to(member["boundary_back"]) <= 40.0,"physical ends must stay joined at driving scale"): return
					previous = float(member["boundary_arc_end"])
					previous_front = member["boundary_front"]
				if run["kind"] == "rail":
					major += 1
					families[run["asset_id"]] = true
					covered += float(run["covered_length_mm"])
				else:
					pegs += 1
			if not _check(major >= 4 and families.size() >= 2,"outer framing needs multiple substantial rail sets, not micro-clutter counts"): return
			if theme == "workshop" and not _check(pegs >= 1,"workshop needs an actual hardware/nail set, not only a rail count"): return
			var coverage := covered / float(plan["diagnostics"]["outer_perimeter_mm"])
			if not _check(coverage >= 0.20,"insufficient substantial outer-edge coverage: %s/%d %.3f" % [theme,seed_value,coverage]): return
			print("OUTER_RUNS ",theme," seed=",seed_value," sets=",runs.size()," major=",major," families=",families.size()," coverage=",coverage)
			if seed_value == int(CASES[theme][0]):
				var built := CORE.build_packed(StringName(theme),StringName(identity["room"]),seed_value,IDS.generation_options(identity))
				var track := (built["scene"] as PackedScene).instantiate()
				var counts := {}
				for body: Node in track.get_node("GeneratedOuterBoundaryVisuals").get_children():
					if body.has_meta("boundary_run_id"):
						if not _check(body is StaticBody2D and body.collision_layer == 16 and not body.find_children("*","CollisionShape2D",true,false).is_empty(),"rendered run members must have real colliders"): track.free(); return
						var id: String = body.get_meta("boundary_run_id")
						counts[id] = int(counts.get(id,0))+1
				for run: Dictionary in track.get_meta("boundary_runs"):
					if not _check(int(counts.get(run["id"],0)) == int(run["member_count"]),"runtime set must preserve every planned member"): track.free(); return
				track.free()
			await process_frame
		if theme == "workshop" and not _check(placed_families.has(CATALOG.for_path("res://assets/textures/edge_dressing/workshop_nail_micro.png")["id"]),"nail sets must actually appear across the workshop sample"): return
		if theme == "office":
			for path: String in ["res://assets/textures/imagine/pencil.png","res://assets/textures/track_boundary/office_pen_rail.png"]:
				if not _check(placed_families.has(CATALOG.for_path(path)["id"]),"pencil and pen sets must actually appear across the office sample"): return
	print("OUTER_BOUNDARY_RUNS_TEST PASS coherent_outer_sets_coverage_not_total_colliders")
	quit(0)


func _atomic_failure() -> bool:
	var planner := WorldEnvironmentPlan.new()
	planner.room = CORE._rect_points(Vector2.ZERO,Vector2(2000,2000))
	planner.island = CORE._rect_points(Vector2.ZERO,Vector2(400,400))
	planner.line = CORE._rect_points(Vector2.ZERO,Vector2(750,750))
	planner.outer_line = CORE._rect_points(Vector2.ZERO,Vector2(1000,1000))
	planner.outer_line.append(planner.outer_line[0])
	planner.outer_arc = CORE._arc_lengths(planner.outer_line)
	planner.density = CATALOG.boundary_density()
	planner.open_sector = -1
	var asset := {"id":"test_rail","dimensions_mm":Vector2(150,20),"clearance_mm":36,"collision":"alpha"}
	var unblocked := planner._fit_outer_run(asset,100,3,10)
	if not _check(unblocked.size()==3,"atomic fixture needs a valid three-piece set"): return false
	planner.occupied.append(CORE._rect_points(unblocked[2]["position"],Vector2(30,30)))
	var before := planner.occupied.duplicate(true)
	return _check(planner._fit_outer_run(asset,100,3,10).is_empty() and planner.occupied==before and planner.placements.is_empty() and planner.used.is_empty(),"failed set must roll back every tentative member and reservation")

func _check(ok: bool, message: String) -> bool:
	if ok: return true
	push_error("OUTER_BOUNDARY_RUNS_TEST FAIL: "+message)
	quit(1)
	return false
