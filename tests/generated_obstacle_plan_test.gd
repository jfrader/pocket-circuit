extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const IDENTITIES := preload("res://scripts/progression/championship_circuit_identity.gd")
const CATALOG := preload("res://data/championship/catalog.gd")
const VISUAL_ROLE := preload("res://scripts/race/generated_world_visual_role.gd")

const CASES := [
	{"theme": &"kitchen", "act": 1, "range": Vector2i(0, 1), "seed": 3},
	{"theme": &"workshop", "act": 2, "range": Vector2i(1, 2), "seed": 5},
	{"theme": &"office", "act": 3, "range": Vector2i(2, 3), "seed": 8},
]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	for case: Dictionary in CASES:
		var options := {"act": case["act"], "obstacle_seed": 663100 + int(case["act"]), "hazard_seed": 663200}
		var prepared := BUILDER.prepare_layout(case["theme"], &"classic", case["seed"], options)
		var repeated := BUILDER.prepare_layout(case["theme"], &"classic", case["seed"], options)
		if not _expect(not prepared.is_empty() and prepared["centerline"] == repeated["centerline"], "%s route should remain deterministic" % case["theme"]):
			return
		var plan: Array = prepared["spec"]["obstacle_plan"]
		if not _expect(plan == repeated["spec"]["obstacle_plan"], "%s obstacle stream should reproduce exactly" % case["theme"]):
			return
		var expected_range: Vector2i = case["range"]
		if not _expect(plan.size() >= expected_range.x and plan.size() <= expected_range.y, "%s permanent obstacle count should scale within %d-%d" % [case["theme"], expected_range.x, expected_range.y]):
			return
		if not _check_plan(prepared):
			return
		var disabled := BUILDER.prepare_layout(case["theme"], &"classic", case["seed"], {
			"act": case["act"],
			"obstacle_seed": options["obstacle_seed"],
			"hazard_seed": options["hazard_seed"],
			"obstacles_enabled": false,
		})
		if not _expect(disabled["centerline"] == prepared["centerline"] and (disabled["spec"]["obstacle_plan"] as Array).is_empty(), "disabling %s obstacles must not perturb route geometry" % case["theme"]):
			return

	var office := BUILDER.prepare_layout(&"office", &"classic", 8, {"act": 3, "obstacle_seed": 9001, "hazard_seed": 7001})
	var changed_plan: Array = []
	var changed_seed := 0
	var gate_samples := BUILDER._layout_gate_samples(office["centerline"], office["spec"])
	var moments := BUILDER._analyze_track_moments(office["centerline"], gate_samples)
	for obstacle_seed in range(9002, 9020):
		var changed_spec: Dictionary = office["spec"].duplicate(true)
		changed_spec["obstacle_seed"] = obstacle_seed
		changed_plan = BUILDER._plan_generated_obstacles(&"office", changed_spec, office["centerline"], gate_samples, moments)
		if changed_plan != office["spec"]["obstacle_plan"]:
			changed_seed = obstacle_seed
			break
	if not _expect(changed_seed > 0 and office["centerline"] == BUILDER.prepare_layout(&"office", &"classic", 8, {"act": 3, "obstacle_seed": changed_seed, "hazard_seed": 7001})["centerline"], "an independent obstacle seed should change only the obstacle plan"):
		return

	if not _check_hazard_progression(office, moments):
		return
	if not _check_championship_identity():
		return
	if not _check_built_metadata():
		return

	print("GENERATED_OBSTACLE_PLAN_TEST PASS")
	quit(0)


func _check_plan(prepared: Dictionary) -> bool:
	var plan: Array = prepared["spec"]["obstacle_plan"]
	var centerline: PackedVector2Array = prepared["centerline"]
	var gate_samples := BUILDER._layout_gate_samples(centerline, prepared["spec"])
	var moments := BUILDER._analyze_track_moments(centerline, gate_samples)
	var routes := [
		BUILDER._racing_line_points(centerline, moments, false),
		BUILDER._racing_line_points(centerline, moments, true),
	]
	for entry: Dictionary in plan:
		var footprint_size: Vector2 = entry.get("footprint_size", Vector2.ZERO)
		var visual_bounds: Rect2 = entry.get("visual_bounds", Rect2())
		var centerline_index := int(entry.get("centerline_index", 0))
		var tangent := BUILDER._sample_tangent(centerline, centerline_index)
		var normal := tangent.rotated(PI * 0.5)
		var projected_extent := maxf(footprint_size.x, footprint_size.y) * 0.5
		if StringName(entry["footprint_kind"]) == &"rect":
			var local_x := Vector2.RIGHT.rotated(float(entry["rotation"]))
			var local_y := Vector2.DOWN.rotated(float(entry["rotation"]))
			projected_extent = absf(normal.dot(local_x)) * footprint_size.x * 0.5 + absf(normal.dot(local_y)) * footprint_size.y * 0.5
		var center_offset := absf((entry["position"] - centerline[centerline_index]).dot(normal))
		var realized_corridor_width := BUILDER.HALF_WIDTH + center_offset - projected_extent
		if not _expect(
			StringName(entry.get("role", &"")) == &"permanent_obstacle"
			and footprint_size.x > 0.0
			and footprint_size.y > 0.0
			and visual_bounds.size == entry.get("visual_size", Vector2.ZERO)
			and float(entry.get("clearance", 0.0)) >= BUILDER.VEHICLE_WIDTH * 0.5
			and is_equal_approx(float(entry.get("lateral_footprint_extent", 0.0)), projected_extent)
			and is_equal_approx(float(entry.get("lateral_center_offset", 0.0)), center_offset)
			and is_equal_approx(float(entry.get("viable_corridor_width", 0.0)), realized_corridor_width)
			and float(entry.get("viable_corridor_width", 0.0)) >= BUILDER.MIN_VIABLE_CORRIDOR_WIDTH,
			"each obstacle should derive its 1.6-car corridor from the realized rotated footprint"
		):
			return false
		for route: PackedVector2Array in routes:
			if not _expect(BUILDER._line_sweep_clears_footprint(route, entry["position"], footprint_size, entry["footprint_kind"], entry["rotation"], entry["clearance"]), "every committed AI route should clear each permanent obstacle"):
				return false
	return true


func _check_hazard_progression(prepared: Dictionary, moments: Dictionary) -> bool:
	var counts := {1: 0, 2: 0, 3: 0}
	var saw_progression_split := false
	for hazard_seed in 100:
		var presence := {}
		for act in [1, 2, 3]:
			var spec: Dictionary = prepared["spec"].duplicate(true)
			spec["hazard_seed"] = hazard_seed
			spec["act"] = act
			var plan := BUILDER._plan_generated_hazard(&"office", spec, prepared["centerline"], moments)
			presence[act] = bool(plan["present"])
			counts[act] += int(plan["present"])
		if not presence[1] and presence[3]:
			saw_progression_split = true
	if not _expect(counts[1] > 0 and counts[3] < 100 and counts[1] < counts[2] and counts[2] < counts[3] and saw_progression_split, "hazards should be deterministic, occasional, and increasingly present by act (%s)" % str(counts)):
		return false
	var first := BUILDER._plan_generated_hazard(&"office", prepared["spec"], prepared["centerline"], moments)
	var second := BUILDER._plan_generated_hazard(&"office", prepared["spec"], prepared["centerline"], moments)
	return _expect(first == second and first["paths"] is Dictionary and (first["danger_states"] as PackedStringArray) == PackedStringArray(["active", "exit"]), "same hazard stream should reproduce its complete motion and collision plan")


func _check_championship_identity() -> bool:
	var championship := IDENTITIES.create_championship(663)
	var event: Dictionary = CATALOG.EVENTS[4]
	var identity := IDENTITIES.event_identity(championship, String(event["id"]))
	var applied := IDENTITIES.apply_to_event(event, identity)
	var options := {"act": applied["act"], "sub_seeds": identity["sub_seeds"]}
	var first := BUILDER.prepare_layout(StringName(applied["theme"]), StringName(applied["room"]), int(applied["seed"]), options)
	var second := BUILDER.prepare_layout(StringName(applied["theme"]), StringName(applied["room"]), int(applied["seed"]), options)
	return _expect(
		first["spec"]["obstacle_seed"] == identity["sub_seeds"]["obstacle"]
		and first["spec"]["hazard_seed"] == identity["sub_seeds"]["hazard"]
		and first["spec"]["obstacle_plan"] == second["spec"]["obstacle_plan"]
		and first["spec"]["hazard_plan"] == second["spec"]["hazard_plan"],
		"same championship identity should reproduce independent obstacle and hazard plans"
	)


func _check_built_metadata() -> bool:
	var built := BUILDER.build_packed(&"office", &"classic", 8, {"act": 3, "obstacle_seed": 9001, "hazard_seed": 7001})
	if not _expect(built.get("scene") is PackedScene, "metadata fixture should build"):
		return false
	var track := (built["scene"] as PackedScene).instantiate() as Node2D
	var container := track.get_node_or_null("PermanentObstacles") as Node2D
	var plan: Array = track.get_meta("generated_obstacle_plan", [])
	if not _expect(container != null and container.get_child_count() == plan.size() and plan.size() >= 2, "built Office track should realize its 2-3 planned permanent obstacles"):
		track.free()
		return false
	var plan_by_id := {}
	for entry: Dictionary in plan:
		plan_by_id[String(entry["instance_id"])] = entry
	var runtime_routes: Array[PackedVector2Array] = []
	for route_name: String in ["RacingLine", "ShortcutRacingLine"]:
		var route := track.get_node_or_null(route_name) as Line2D
		if route:
			runtime_routes.append(route.points)
	if not _expect(runtime_routes.size() == 2, "runtime fixture should expose both AI routes used for obstacle clearance"):
		track.free()
		return false
	if not _expect(runtime_routes.size() == 2, "runtime obstacle fixture should expose both AI routes used during footprint clearance"):
		track.free()
		return false
	for obstacle: StaticBody2D in container.get_children():
		var collisions := obstacle.find_children("*", "CollisionShape2D", true, false)
		var collision := collisions[0] as CollisionShape2D if not collisions.is_empty() else null
		var sprite := obstacle.get_node_or_null("Sprite") as Sprite2D
		var entry: Dictionary = plan_by_id.get(String(obstacle.get_meta("instance_id", "")), {})
		var footprint_size: Vector2 = entry.get("footprint_size", Vector2.ZERO)
		var footprint_kind := StringName(entry.get("footprint_kind", &""))
		var has_fitted_shape := collision != null and (
			(footprint_kind == &"circle" and collision.shape is CircleShape2D)
			or (footprint_kind == &"rect" and collision.shape is RectangleShape2D)
		)
		if not _expect(
			has_fitted_shape
			and sprite != null
			and not entry.is_empty()
			and collision.position.is_zero_approx()
			and obstacle.position.is_equal_approx(entry["position"])
			and is_equal_approx(obstacle.rotation, float(entry["rotation"]))
			and obstacle.get_meta("collision_footprint_size", Vector2.ZERO) == footprint_size
			and VISUAL_ROLE.read(obstacle) == VISUAL_ROLE.SOLID
			and VISUAL_ROLE.read(sprite) == VISUAL_ROLE.SOLID,
			"realized obstacles should keep planned placement while fitting collision to visible art"
		):
			track.free()
			return false
		for route: PackedVector2Array in runtime_routes:
			if not _expect(BUILDER._line_sweep_clears_footprint(route, obstacle.position, footprint_size, footprint_kind, obstacle.rotation, entry["clearance"]), "runtime obstacle geometry should be the same footprint cleared against AI routes"):
				track.free()
				return false
	track.free()
	return true


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("GENERATED_OBSTACLE_PLAN_TEST FAIL: " + message)
	quit(1)
	return false