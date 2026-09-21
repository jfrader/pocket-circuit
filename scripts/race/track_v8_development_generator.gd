class_name TrackV8DevelopmentGenerator
extends RefCounted

const MODULES := preload("res://scripts/race/track_module_catalog.gd")
const VALIDATION := preload("res://scripts/race/track_layout_validation.gd")
const ROOM_MODEL := preload("res://scripts/race/track_room_model.gd")

const CATALOG_KERNEL_FIXTURE := &"catalog_kernel"


static func generate(request: Dictionary) -> Dictionary:
	if StringName(request.get("development_fixture", &"")) != CATALOG_KERNEL_FIXTURE:
		return _error(&"v8_not_implemented", "Track generator schema 2 version 8 has no general solver; select the catalog_kernel development fixture explicitly.")
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
