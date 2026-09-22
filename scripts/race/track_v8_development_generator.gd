class_name TrackV8DevelopmentGenerator
extends RefCounted

const MODULES := preload("res://scripts/race/track_module_catalog.gd")
const VALIDATION := preload("res://scripts/race/track_layout_validation.gd")
const ROOM_MODEL := preload("res://scripts/race/track_room_model.gd")
const LAYOUT_SOLVER := preload("res://scripts/race/track_layout_solver.gd")

const CATALOG_KERNEL_FIXTURE := &"catalog_kernel"


static func generate(request: Dictionary) -> Dictionary:
	if StringName(request.get("development_fixture", &"")) != CATALOG_KERNEL_FIXTURE:
		return _generate_solved_lap(request)
	if StringName(request.get("room_shape", &"")) != &"el":
		return _error(&"fixture_room_mismatch", "The catalog_kernel development fixture is certified only in the EL room.")
	if StringName((request.get("generation_options", {}) as Dictionary).get("length_tier", &"standard")) != &"standard":
		return _error(&"fixture_tier_mismatch", "The catalog_kernel development fixture is certified only at the standard length tier.")
	var room: Dictionary = request.get("room_model", {})
	if not bool(room.get("valid", false)):
		return _error(&"fixture_room_model", "The catalog_kernel development fixture requires a validated free-polygon room model.")
	var room_polygon: PackedVector2Array = room["outer"]
	var route := place_catalog_kernel(room)
	if not bool(route.get("ok", false)):
		return route
	var continuous := VALIDATION.validate_continuous(route, room_polygon)
	if not bool(continuous.get("valid", false)):
		return continuous
	var sampling := MODULES.sample_route(route, 260, 35.0, 0.25)
	if not bool(sampling.get("ok", false)):
		return sampling
	var sampled := VALIDATION.validate_sampled(route, sampling, room_polygon)
	if not bool(sampled.get("valid", false)):
		return sampled
	return {
		"ok": true,
		"points": sampling["points"],
		"centerline_is_sampled": true,
		"seed": int(request.get("seed", 0)),
		"family": &"catalog_kernel_fixture",
		"realization": CATALOG_KERNEL_FIXTURE,
		"route_program": CATALOG_KERNEL_FIXTURE,
		"route_recipe": CATALOG_KERNEL_FIXTURE,
		"route_sequence": "S.R.S.R.S.R.S.R",
		"length": float(route["length"]),
		"target_length": float(route["length"]),
		"length_tier": StringName((request.get("generation_options", {}) as Dictionary).get("length_tier", &"standard")),
		"attempt": 0,
		"fallback": false,
		"pockets": [],
		"corner_profiles": {},
		"motifs": [],
		"analytic_route": route,
		"analytic_validation": continuous,
		"sampling": sampling,
		"sampled_validation": sampled,
		"room_model": room,
		"room_placement": route["room_placement"],
	}


static func generate_route(room_shape: StringName, tier: StringName, seed: int, room_geometry_seed: int = -1) -> Dictionary:
	if room_geometry_seed < 0:
		room_geometry_seed = _named_seed(seed, "room_geometry")
	var room := ROOM_MODEL.generate_recipe(room_shape, room_geometry_seed, tier)
	return generate({
		"seed": seed,
		"room_shape": room_shape,
		"room_geometry_seed": room_geometry_seed,
		"room_model": room,
		"generation_options": {
			"schema_version": 2,
			"generator_version": 8,
			"length_tier": tier,
			"room_geometry_seed": room_geometry_seed,
		},
	})


static func _generate_solved_lap(request: Dictionary) -> Dictionary:
	var options: Dictionary = request.get("generation_options", {})
	var room_seed := int(options.get("room_geometry_seed", request.get("room_geometry_seed", -1)))
	var solver_request := {
		"seed": int(request.get("seed", -1)),
		"room_shape": StringName(request.get("room_shape", &"")),
		"length_tier": StringName(options.get("length_tier", &"standard")),
		"room_geometry_seed": room_seed,
		"room_model": request.get("room_model", {}),
	}
	if options.has("room_recipe_id"):
		solver_request["room_recipe_id"] = options["room_recipe_id"]
	if options.has("room_recipe_revision"):
		solver_request["room_recipe_revision"] = options["room_recipe_revision"]
	if request.has("solver_limits"):
		solver_request["solver_limits"] = request["solver_limits"]
	var solved := LAYOUT_SOLVER.solve(solver_request)
	if not bool(solved.get("ok", false)):
		return solved
	var route: Dictionary = solved["analytic_route"]
	var cycle: Array = solved["gameplay_cycle"]
	var graph_id := &"solved_cycle"
	if not cycle.is_empty():
		graph_id = StringName("%s_%s" % [request.get("room_shape", "room"), options.get("length_tier", "tier")])
	return {
		"ok": true,
		"points": solved["points"],
		"centerline_is_sampled": true,
		"seed": int(request.get("seed", 0)),
		"family": solved["identity"]["family"],
		"realization": graph_id,
		"route_program": graph_id,
		"route_recipe": graph_id,
		"route_sequence": solved["structural_signature"],
		"length": float(route["length"]),
		"target_length": (float(route["length"])),
		"length_tier": StringName(options.get("length_tier", &"standard")),
		"attempt": int((solved["search"] as Dictionary).get("graph_candidates", 1)) - 1,
		"fallback": false,
		"pockets": [],
		"corner_profiles": {},
		"motifs": [],
		"analytic_route": route,
		"analytic_validation": solved["analytic_validation"],
		"sampling": solved["sampling"],
		"sampled_validation": solved["sampled_validation"],
		"room_model": solved["room_model"],
		"room_placement": ROOM_MODEL.route_fits(solved["room_model"], route, MODULES.RESERVED_RADIUS),
		"identity": solved["identity"],
		"gameplay_cycle": cycle,
		"region_visits": solved["region_visits"],
		"portal_traversals": solved["portal_traversals"],
		"search": solved["search"],
		"metrics": solved["metrics"],
		"structural_signature": solved["structural_signature"],
		"profile_signature": solved["profile_signature"],
	}


static func catalog_kernel_fixture() -> Dictionary:
	var instances: Array[Dictionary] = [
		MODULES.instantiate(&"straight_setup", {"length": 1600.0, "finish": true}),
		MODULES.instantiate(&"corner_medium", {"radius": 300.0, "angle_deg": 90.0, "hand": 1.0}),
		MODULES.instantiate(&"straight_link", {"length": 300.0}),
		MODULES.instantiate(&"corner_medium", {"radius": 300.0, "angle_deg": 90.0, "hand": 1.0}),
		MODULES.instantiate(&"straight_setup", {"length": 1600.0}),
		MODULES.instantiate(&"corner_medium", {"radius": 300.0, "angle_deg": 90.0, "hand": 1.0}),
		MODULES.instantiate(&"straight_link", {"length": 300.0}),
		MODULES.instantiate(&"corner_medium", {"radius": 300.0, "angle_deg": 90.0, "hand": 1.0}),
	]
	return MODULES.compose(instances, Vector2(-800.0, 100.0), 0.0)


static func place_catalog_kernel(room: Dictionary) -> Dictionary:
	var route := catalog_kernel_fixture()
	if not bool(route.get("ok", false)):
		return route
	var placement := ROOM_MODEL.route_fits(room, route, MODULES.RESERVED_RADIUS)
	if not bool(placement.get("valid", false)):
		return placement
	route["room_placement"] = placement
	return route


static func _error(kind: StringName, message: String) -> Dictionary:
	return {"ok": false, "valid": false, "kind": kind, "error": message, "reason": message}


static func _named_seed(seed: int, domain: String) -> int:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(("v8:%s:%d" % [domain, seed]).to_utf8_buffer())
	var digest := context.finish()
	return ((int(digest[0]) << 24) | (int(digest[1]) << 16) | (int(digest[2]) << 8) | int(digest[3])) & 0x7fffffff
