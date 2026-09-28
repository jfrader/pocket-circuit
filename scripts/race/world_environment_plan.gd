class_name WorldEnvironmentPlan
extends RefCounted
## Deterministic physical placements; no scene or texture access in the planner.

const GROUP_COUNT := 4
const SUPPORTS_PER_GROUP := 3
const MICROS_PER_GROUP := 2
const BOUNDARY_COUNT := 8
const LOCAL_ATTEMPTS := 48
const GRID := Vector2i(21, 17)

var room: PackedVector2Array
var island: PackedVector2Array
var line: PackedVector2Array
var arc: PackedFloat32Array
var half_width := 125.0
var world_seed := 0
var open_sector := 0
var pools: Dictionary = {}
var used: Dictionary = {}
var occupied: Array[PackedVector2Array] = []
var reservations: Array[PackedVector2Array] = []
var placements: Array[Dictionary] = []
var diagnostics := {"attempts":0,"focal_count":0,"support_count":0,"micro_count":0,"boundary_count":0,"ground_count":0,"decal_count":0,"notes":[]}


static func plan(theme: StringName, seed: int, geometry: Dictionary, candidates: Array[Dictionary], story: Dictionary) -> Dictionary:
	var planner := WorldEnvironmentPlan.new()
	planner.world_seed = seed
	planner.open_sector = posmod(TrackBuilderCore._mix_seed(seed, "open_apron"), BOUNDARY_COUNT)
	planner.room = geometry.get("room_polygon", PackedVector2Array())
	planner.island = geometry.get("island_polygon", PackedVector2Array())
	planner.line = geometry.get("centerline", PackedVector2Array())
	planner.half_width = float(geometry.get("corridor_half_width", 125.0))
	if planner.room.size() < 3 or planner.line.size() < 3:
		return {"placements":[],"diagnostics":{"error":"insufficient_geometry"}}
	planner.arc = TrackBuilderCore._arc_lengths(planner.line)
	for polygon: PackedVector2Array in geometry.get("reserved_polygons", []):
		planner.occupied.append(polygon)
		planner.reservations.append(polygon)
	planner._catalog(theme, candidates, story)
	planner._compose()
	planner.diagnostics["seed"] = seed
	planner.diagnostics["theme"] = theme
	planner.diagnostics["total_placed"] = planner.placements.size()
	planner.diagnostics["open_sector"] = planner.open_sector
	return {"placements":planner.placements,"diagnostics":planner.diagnostics}


func _catalog(theme: StringName, candidates: Array[Dictionary], story: Dictionary) -> void:
	var allowed: Array = story.get("asset_ids", [])
	var ids := {}
	for asset: Dictionary in candidates:
		var id := String(asset.get("id", ""))
		if id.is_empty() or ids.has(id) or String(theme) not in asset.get("themes", []):
			continue
		if not allowed.is_empty() and id not in allowed:
			continue
		var size: Variant = asset.get("dimensions_mm")
		if not size is Vector2 or size.x <= 0.0 or size.y <= 0.0 or int(asset.get("max_repeats", 0)) <= 0:
			diagnostics["notes"].append("invalid_asset:" + id)
			continue
		ids[id] = true
		for role: String in asset.get("roles", []):
			if not pools.has(role):
				pools[role] = []
			pools[role].append(asset)


func _rng(role: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = TrackBuilderCore._mix_seed(world_seed, role)
	return rng


func _available(role: String, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	for asset: Dictionary in pools.get(role, []):
		if int(used.get(asset["id"], 0)) < int(asset["max_repeats"]):
			choices.append(asset)
	var ordered: Array[Dictionary] = []
	while not choices.is_empty():
		ordered.append(choices.pop_at(rng.randi_range(0, choices.size() - 1)))
	return ordered


func _compose() -> void:
	var rng := _rng("focal")
	var focal_pool := _available("focal", rng)
	focal_pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("visual_weight", 1)) > float(b.get("visual_weight", 1)))
	var focal := Vector2.ZERO
	for asset: Dictionary in focal_pool:
		var fit := _focal_fit(asset, rng)
		if not fit.is_empty():
			_store(asset, "focal", fit)
			focal = fit["position"]
			break
	if int(diagnostics["focal_count"]) == 0:
		diagnostics["notes"].append("no_focal_fit")
	for group in GROUP_COUNT:
		rng = _rng("group:%d" % group)
		var sector := _route_anchor((float(group) + rng.randf_range(0.1, 0.5)) / GROUP_COUNT, 120.0)
		var anchor := focal if group == 0 and int(diagnostics["focal_count"]) == 1 else (sector["position"] if rng.randf() < 0.5 else sector["alternate_position"]) as Vector2
		var supports := 0
		for index in SUPPORTS_PER_GROUP:
			var placed := _near("support", anchor, rng, 100.0)
			if placed.is_empty() and supports == 0 and group > 0:
				anchor = sector["alternate_position"] if anchor == sector["position"] else sector["position"]
				placed = _near("support", anchor, rng, 100.0)
			if not placed.is_empty():
				anchor = placed["position"]
				supports += 1
		if supports > 0:
			var micro_rng := _rng("micro:%d" % group)
			for index in MICROS_PER_GROUP:
				_near("micro", anchor, micro_rng, 45.0)
	rng = _rng("boundary")
	for index in BOUNDARY_COUNT:
		var anchor := _route_anchor((float(index) + rng.randf_range(0.2, 0.8)) / BOUNDARY_COUNT, 95.0)
		_near("boundary", anchor["position"], rng, 0.0, float(anchor["rotation"]))
	for role: String in ["ground", "decal"]:
		rng = _rng(role)
		for index in (3 if role == "ground" else 5):
			var anchor := _route_anchor(rng.randf(), 120.0)
			_near(role, anchor["position"], rng, 0.0)


func _route_anchor(fraction: float, offset: float) -> Dictionary:
	var distance := arc[arc.size() - 1] * fraction
	var point := TrackBuilderCore._sample_at_arc(line, arc, distance)
	var tangent := TrackBuilderCore._tangent_at_arc(line, arc, distance)
	var closest := TrackBuilderCore._closest_point_on_loop(point, island) if not island.is_empty() else {"position":TrackBuilderCore._polygon_bounds_rect(room).get_center()}
	var outward := (point - (closest["position"] as Vector2)).normalized()
	return {"position":point + outward * (half_width + offset),"alternate_position":point - outward * (half_width + offset),"rotation":tangent.angle()}


func _focal_fit(asset: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var region := island if not island.is_empty() else room
	var fit := _search_focal_region(asset, rng, region, not island.is_empty())
	if fit.is_empty() and not island.is_empty():
		fit = _search_focal_region(asset, rng, room, false)
	return fit


func _search_focal_region(asset: Dictionary, rng: RandomNumberGenerator, region: PackedVector2Array, island_only: bool) -> Dictionary:
	var bounds := TrackBuilderCore._polygon_bounds_rect(region)
	var preferred := TrackBuilderCore._sample_at_arc(line, arc, arc[arc.size() - 1] * rng.randf())
	var best := {}
	var score := INF
	var phase := Vector2(rng.randf_range(0.15, 0.85), rng.randf_range(0.15, 0.85))
	for row in GRID.y:
		for column in GRID.x:
			var point := bounds.position + bounds.size * (Vector2(column, row) + phase) / Vector2(GRID)
			if point.distance_squared_to(preferred) >= score:
				continue
			for angle: float in [0.0, PI * 0.5]:
				var fit := _validate(asset, point, angle)
				if not fit.is_empty() and (not island_only or fit["zone"] == "island"):
					best = fit
					score = point.distance_squared_to(preferred)
	return best


func _near(role: String, anchor: Vector2, rng: RandomNumberGenerator, initial_radius: float, heading: float = INF) -> Dictionary:
	for asset: Dictionary in _available(role, rng):
		var size: Vector2 = asset["dimensions_mm"]
		for attempt in LOCAL_ATTEMPTS:
			var distance := initial_radius + floorf(float(attempt) / 8.0) * 30.0
			var direction := float(attempt % 8) * TAU / 8.0 + rng.randf_range(-0.15, 0.15)
			var point := anchor + Vector2.from_angle(direction) * distance
			var angle := heading if is_finite(heading) else rng.randf_range(-0.25, 0.25)
			if size.y > size.x and is_finite(heading):
				angle += PI * 0.5
			var fit := _validate(asset, point, angle)
			if not fit.is_empty():
				_store(asset, role, fit)
				return fit
	return {}


func _validate(asset: Dictionary, point: Vector2, angle: float) -> Dictionary:
	diagnostics["attempts"] += 1
	var size: Vector2 = asset["dimensions_mm"]
	var polygon := _make_oriented_rect(point, size, angle)
	if not Geometry2D.clip_polygons(polygon, room).is_empty():
		return {}
	for reserved: PackedVector2Array in reservations:
		if not Geometry2D.intersect_polygons(polygon, reserved).is_empty():
			return {}
	var zone := "apron"
	if not island.is_empty():
		var crosses := not Geometry2D.intersect_polygons(polygon, island).is_empty()
		var outside := not Geometry2D.clip_polygons(polygon, island).is_empty()
		if crosses and outside:
			return {}
		if not outside:
			zone = "island"
	var zones: Array = asset.get("zones", ["island", "apron", "room"])
	if zone not in zones and "room" not in zones:
		return {}
	if zone == "apron" and String(asset.get("collision", "alpha")) != "flat":
		var closest := TrackBuilderCore._closest_point_on_loop(point, line)
		var sector := mini(BOUNDARY_COUNT - 1, int(float(closest["index"]) / line.size() * BOUNDARY_COUNT))
		if sector == open_sector:
			return {}
	var clearance := float(asset.get("clearance_mm", 36.0))
	if not TrackBuilderCore._line_sweep_clears_footprint(line, point, size, &"rect", angle, half_width + clearance + 2.0):
		return {}
	if String(asset.get("collision", "alpha")) != "flat":
		for other: PackedVector2Array in occupied:
			if not Geometry2D.intersect_polygons(polygon, other).is_empty():
				return {}
	return {"position":point,"rotation":angle,"footprint":{"size":size,"kind":&"rect"},"zone":zone}


func _store(asset: Dictionary, role: String, fit: Dictionary) -> void:
	var placement := fit.duplicate(true)
	placement["asset_id"] = String(asset["id"])
	placement["role"] = role
	placements.append(placement)
	used[asset["id"]] = int(used.get(asset["id"], 0)) + 1
	diagnostics[role + "_count"] += 1
	if String(asset.get("collision", "alpha")) != "flat":
		occupied.append(_make_oriented_rect(fit["position"], asset["dimensions_mm"], float(fit["rotation"])))


static func _make_oriented_rect(center: Vector2, size: Vector2, rotation: float) -> PackedVector2Array:
	return TrackBuilderCore.TRACK_BUILDER_BOUNDARY._footprint_polygon(center, size, rotation)
