class_name WorldEnvironmentPlan
extends RefCounted
## Deterministic physical placements; no scene or texture access in the planner.

const GROUP_COUNT := 4
const SUPPORTS_PER_GROUP := 3
const MICROS_PER_GROUP := 2
const SECTOR_COUNT := 8
const APRON_EXIT_DISTANCES: Array[float] = [210.0, 280.0, 360.0]
const LOCAL_ATTEMPTS := 48
const GRID := Vector2i(21, 17)

var room: PackedVector2Array
var island: PackedVector2Array
var line: PackedVector2Array
var arc: PackedFloat32Array
var outer_line: PackedVector2Array
var outer_arc: PackedFloat32Array
var boundary_runs: Array[Dictionary] = []
var last_rejection := ""
var half_width := 125.0
var world_seed := 0
var open_sector := 0
var pools: Dictionary = {}
var assets_by_id: Dictionary = {}
var used: Dictionary = {}
var occupied: Array[PackedVector2Array] = []
var reservations: Array[PackedVector2Array] = []
var density: Dictionary = {}
var placements: Array[Dictionary] = []
var diagnostics := {"attempts":0,"focal_count":0,"support_count":0,"micro_count":0,"boundary_count":0,"ground_count":0,"decal_count":0,"notes":[]}


static func plan(theme: StringName, seed: int, geometry: Dictionary, candidates: Array[Dictionary], story: Dictionary) -> Dictionary:
	var planner := WorldEnvironmentPlan.new()
	planner.world_seed = seed
	planner.open_sector = posmod(TrackBuilderCore._mix_seed(seed, "open_apron"), SECTOR_COUNT)
	planner.density = WorldEnvironmentCatalog.boundary_density()
	planner.room = geometry.get("room_polygon", PackedVector2Array())
	planner.island = geometry.get("island_polygon", PackedVector2Array())
	planner.line = geometry.get("centerline", PackedVector2Array())
	planner.half_width = float(geometry.get("corridor_half_width", 125.0))
	if planner.room.size() < 3 or planner.line.size() < 3:
		return {"placements":[],"diagnostics":{"error":"insufficient_geometry"}}
	planner.arc = TrackBuilderCore._arc_lengths(planner.line)
	planner.outer_line = (geometry.get("outer_boundary", PackedVector2Array()) as PackedVector2Array).duplicate()
	if planner.outer_line.is_empty():
		var edges := TrackBuilderCore._corridor_edges(planner.line)
		planner.outer_line = edges["left"] if absf(TrackBuilderCore._polygon_area(edges["left"])) > absf(TrackBuilderCore._polygon_area(edges["right"])) else edges["right"]
	if not planner.outer_line[0].is_equal_approx(planner.outer_line[-1]):
		planner.outer_line.append(planner.outer_line[0])
	planner.outer_arc = TrackBuilderCore._arc_lengths(planner.outer_line)
	for polygon: PackedVector2Array in geometry.get("reserved_polygons", []):
		planner.occupied.append(polygon)
		planner.reservations.append(polygon)
	for polygon: PackedVector2Array in geometry.get("solid_footprints", []):
		planner.occupied.append(polygon)
	planner._reserve_open_exit()
	planner._catalog(theme, candidates, story)
	planner._compose()
	planner.diagnostics["seed"] = seed
	planner.diagnostics["theme"] = theme
	planner.diagnostics["total_placed"] = planner.placements.size()
	planner.diagnostics["open_sector"] = planner.open_sector
	return {"placements":planner.placements,"boundary_runs":planner.boundary_runs,"diagnostics":planner.diagnostics}


func _reserve_open_exit() -> void:
	var clearance := TrackBuilderCore.MIN_VIABLE_CORRIDOR_WIDTH * 0.5
	var span := maxi(12, line.size() / (SECTOR_COUNT * 2) - 2)
	for trial in SECTOR_COUNT:
		var sector := posmod(open_sector + trial, SECTOR_COUNT)
		var center := int(round((float(sector) + 0.5) * line.size() / SECTOR_COUNT)) % line.size()
		for offset in range(-span, span + 1, 3):
			var index := posmod(center + offset, line.size())
			var tangent := TrackBuilderCore._sample_tangent(line, index)
			for side: float in [-1.0, 1.0]:
				var normal := tangent.rotated(PI * 0.5) * side
				for distance: float in APRON_EXIT_DISTANCES:
					var target := line[index] + normal * distance
					var footprint := _make_oriented_rect((line[index] + target) * 0.5, Vector2(distance + clearance * 2.0, clearance * 2.0), normal.angle())
					if not Geometry2D.clip_polygons(footprint, room).is_empty() or (not island.is_empty() and not Geometry2D.intersect_polygons(footprint, island).is_empty()):
						continue
					var blocked := false
					for other: PackedVector2Array in occupied:
						if not Geometry2D.intersect_polygons(footprint, other).is_empty():
							blocked = true
							break
					if not blocked:
						open_sector = sector
						occupied.append(footprint)
						diagnostics["open_exit"] = PackedVector2Array([line[index], target])
						diagnostics["open_exit_width"] = clearance * 2.0
						return
	diagnostics["notes"].append("no_open_exit_fit")


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
		assets_by_id[id] = asset
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
	_compose_boundary()
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
	for role: String in ["ground", "decal"]:
		rng = _rng(role)
		for index in (3 if role == "ground" else 5):
			var anchor := _route_anchor(rng.randf(), 120.0)
			_near(role, anchor["position"], rng, 0.0)


func _compose_boundary() -> void:
	var rng := _rng("boundary:density")
	var targets := _run_targets(outer_arc[-1], density, rng)
	diagnostics["boundary_target"] = targets["members"]
	diagnostics["outer_perimeter_mm"] = outer_arc[-1]
	diagnostics["outer_runs_target"] = targets["rail"]
	var uses := {}
	for kind: String in ["rail", "peg"]:
		var count := int(targets[kind])
		for slot in count:
			var run_rng := _rng("outer:%s:%d" % [kind, slot])
			var assets := _available("boundary", run_rng).filter(func(asset: Dictionary) -> bool: return _run_kind(asset) == kind)
			assets.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(uses.get(a["id"],0)) < int(uses.get(b["id"],0)))
			var preferred := outer_arc[-1] * (float(slot) + run_rng.randf_range(0.15,0.85)) / count
			var committed := false
			for asset: Dictionary in assets:
				var member_range: Array = density["rail_members" if kind == "rail" else "peg_members"]
				var size: Vector2 = asset["dimensions_mm"]
				var members := clampi(ceili(float(density["run_span_mm"]) / maxf(size.x,size.y)),int(member_range[0]),int(member_range[1]))
				if kind == "rail": members = int(member_range[0])
				members = mini(members,int(asset["max_repeats"])-int(used.get(asset["id"],0)))
				if members < int(member_range[0]):
					continue
				var gap := run_rng.randf_range(float(density["gap_mm"][0]),float(density["gap_mm"][1]))
				var fits := _search_outer_run(asset,preferred,members,int(member_range[0]),gap)
				if fits.is_empty(): continue
				var id := "outer_%02d" % boundary_runs.size()
				for index in fits.size():
					fits[index]["boundary_run_id"] = id
					fits[index]["boundary_member"] = index
					_store(asset,"boundary",fits[index])
				var covered := (float(fits[0]["boundary_arc_end"])-float(fits[0]["boundary_arc_start"]))*fits.size()
				boundary_runs.append({"id":id,"side":"outer","kind":kind,"asset_id":asset["id"],"member_count":fits.size(),"start_arc":fits[0]["boundary_arc_start"],"end_arc":fits[-1]["boundary_arc_end"],"outset_mm":fits[0]["boundary_outset_mm"],"covered_length_mm":covered})
				uses[asset["id"]] = int(uses.get(asset["id"],0))+1
				committed = true
				if committed: break
			if not committed:
				diagnostics["notes"].append("unfit_outer_run:%s:%d" % [kind,slot])
	_extend_outer_runs()
	# Inner accents have their own budget and never satisfy an outer-set target.
	for index in int(targets["inner"]):
		_boundary_near(arc[-1] * (float(index)+rng.randf()) / int(targets["inner"]), -1.0, rng)
	var covered := 0.0
	for run: Dictionary in boundary_runs:
		if run["kind"] == "rail": covered += float(run["covered_length_mm"])
	diagnostics["outer_rail_coverage"] = covered / outer_arc[-1]


func _run_kind(asset: Dictionary) -> String:
	if String(asset.get("collision","flat")) == "flat": return ""
	var size: Vector2 = asset["dimensions_mm"]
	var length := maxf(size.x,size.y)
	var aspect := length / minf(size.x,size.y)
	if length >= float(density["rail_min_length_mm"]) and aspect >= float(density["rail_min_aspect"]): return "rail"
	if length >= float(density["peg_length_mm"][0]) and length <= float(density["peg_length_mm"][1]) and aspect >= float(density["peg_min_aspect"]): return "peg"
	return ""


func _search_outer_run(asset: Dictionary, preferred: float, maximum: int, minimum: int, gap: float) -> Array[Dictionary]:
	var attempts := int(density["search_attempts"])
	for members in range(maximum,minimum-1,-1):
		for outset: float in density["run_outsets_mm"]:
			for attempt in attempts * 2:
				var offset := ceilf(float(attempt)/2.0)*float(density["search_stride_mm"])*(1.0 if attempt%2==0 else -1.0)
				if attempt >= attempts:
					offset = outer_arc[-1]*float(attempt-attempts)/attempts
				var fits := _fit_outer_run(asset,fposmod(preferred+offset,outer_arc[-1]),members,gap,"",Vector2.INF,outset)
				if not fits.is_empty(): return fits
	return []


func _extend_outer_runs() -> void:
	for run: Dictionary in boundary_runs:
		if run["kind"] != "rail": continue
		var asset: Dictionary = assets_by_id[run["asset_id"]]
		var rng := _rng("outer:extend:"+String(run["id"]))
		var wanted := rng.randi_range(int(density["rail_members"][0]),int(density["rail_members"][1]))
		var gap := rng.randf_range(float(density["gap_mm"][0]),float(density["gap_mm"][1]))
		while int(run["member_count"]) < wanted and int(used[asset["id"]]) < int(asset["max_repeats"]):
			var front := Vector2.INF
			for placement: Dictionary in placements:
				if placement.get("boundary_run_id","") == run["id"]: front = placement["boundary_front"]
			var fits := _fit_outer_run(asset,float(run["end_arc"])+gap,1,gap,run["id"],front,float(run["outset_mm"]))
			if fits.is_empty(): break
			fits[0]["boundary_run_id"] = run["id"]
			fits[0]["boundary_member"] = run["member_count"]
			_store(asset,"boundary",fits[0])
			run["member_count"] = int(run["member_count"])+1
			run["end_arc"] = fits[0]["boundary_arc_end"]
			var size: Vector2 = asset["dimensions_mm"]
			run["covered_length_mm"] = float(run["covered_length_mm"])+maxf(size.x,size.y)


func _fit_outer_run(asset: Dictionary, start: float, members: int, gap: float, extending_id: String = "", previous_front: Vector2 = Vector2.INF, outset_mm: float = 0.0) -> Array[Dictionary]:
	var size: Vector2 = asset["dimensions_mm"]
	var pegs := _run_kind(asset) == "peg"
	var length := minf(size.x,size.y) if pegs else maxf(size.x,size.y)
	var depth := maxf(size.x,size.y) if pegs else minf(size.x,size.y)
	var end := start + members * length + (members-1)*gap
	if end > outer_arc[-1]: return []
	for run: Dictionary in boundary_runs:
		if run["id"] == extending_id: continue
		for shift: float in [-outer_arc[-1],0.0,outer_arc[-1]]:
			if start < float(run["end_arc"])+shift+float(density["run_separation_mm"]) and end > float(run["start_arc"])+shift-float(density["run_separation_mm"]): return []
	var occupied_before := occupied.size()
	var fits: Array[Dictionary] = []
	var normal_sign := -1.0 if TrackBuilderCore._polygon_area(outer_line) > 0.0 else 1.0
	for member in members:
		var at := start + length*0.5 + member*(length+gap)
		var point := TrackBuilderCore._sample_at_arc(outer_line,outer_arc,at)
		var tangent := TrackBuilderCore._tangent_at_arc(outer_line,outer_arc,at)
		var normal := tangent.rotated(PI*0.5)*normal_sign
		var angle := tangent.angle()+(PI*0.5 if (size.x >= size.y if pegs else size.y > size.x) else 0.0)
		var position := point + normal * (depth*0.5 + float(asset["clearance_mm"]) + gap + outset_mm)
		var nearest := TrackBuilderCore._closest_point_on_loop(position,line)
		var sector := mini(SECTOR_COUNT-1,int(float(nearest["index"])/line.size()*SECTOR_COUNT))
		var fit := _validate(asset,position,angle)
		if sector == open_sector or fit.is_empty() or fit["zone"] != "apron" or (previous_front.is_finite() and previous_front.distance_to(position-tangent*length*0.5) > float(density["max_join_gap_mm"])):
			var reason := "open_sector" if sector == open_sector else (last_rejection if fit.is_empty() else ("inner" if fit["zone"] != "apron" else "join_gap"))
			if not diagnostics.has("outer_rejections"): diagnostics["outer_rejections"] = {}
			diagnostics["outer_rejections"][reason] = int(diagnostics["outer_rejections"].get(reason,0))+1
			occupied.resize(occupied_before)
			return []
		fit["boundary_arc_start"] = at-length*0.5
		fit["boundary_arc_end"] = at+length*0.5
		fit["boundary_outset_mm"] = outset_mm
		fit["boundary_front"] = position+tangent*length*0.5
		fit["boundary_back"] = position-tangent*length*0.5
		fits.append(fit)
		occupied.append(_make_oriented_rect(position,size,angle))
		previous_front = position+tangent*length*0.5
	occupied.resize(occupied_before)
	return fits


func _boundary_near(distance: float, side: float, rng: RandomNumberGenerator) -> Dictionary:
	for asset: Dictionary in _available("boundary", rng):
		if String(asset.get("collision", "flat")) == "flat":
			continue
		var size: Vector2 = asset["dimensions_mm"]
		var gaps: Array = density["gap_mm"]
		var gap := rng.randf_range(float(gaps[0]), float(gaps[1]))
		for attempt in int(density["search_attempts"]):
			var step := ceilf(float(attempt) / 2.0) * float(density["search_stride_mm"])
			var offset := step if attempt % 2 == 0 else -step
			var at := fposmod(distance + offset, arc[-1])
			var point := TrackBuilderCore._sample_at_arc(line, arc, at)
			var tangent := TrackBuilderCore._tangent_at_arc(line, arc, at)
			var closest := TrackBuilderCore._closest_point_on_loop(point, island) if not island.is_empty() else {"position":TrackBuilderCore._polygon_bounds_rect(room).get_center()}
			var normal := tangent.rotated(PI * 0.5)
			if normal.dot(point - (closest["position"] as Vector2)) < 0.0:
				normal = -normal
			var angle := tangent.angle() + (PI * 0.5 if size.y > size.x else 0.0)
			var clearance := float(asset.get("clearance_mm", 36.0))
			var candidate := point + normal * side * (half_width + minf(size.x, size.y) * 0.5 + clearance + gap)
			var nearest := TrackBuilderCore._closest_point_on_loop(candidate, line)
			if mini(SECTOR_COUNT - 1, int(float(nearest["index"]) / line.size() * SECTOR_COUNT)) == open_sector:
				continue
			var fit := _validate(asset, candidate, angle)
			if not fit.is_empty():
				_store(asset, "boundary", fit)
				return {"advance_mm":maxf(size.x, size.y) + gap}
	return {}


static func _run_targets(length: float, settings: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var coverage := rng.randf_range(float(settings["outer_coverage"][0]),float(settings["outer_coverage"][1]))
	var rail := clampi(ceili(length*coverage/float(settings["run_span_mm"])),int(settings["outer_runs"][0]),int(settings["outer_runs"][1]))
	var peg := rng.randi_range(int(settings["peg_runs"][0]),int(settings["peg_runs"][1]))
	var inner := rng.randi_range(int(settings["inner_members"][0]),int(settings["inner_members"][1]))
	return {"rail":rail,"peg":peg,"inner":inner,"members":mini(int(settings["maximum"]),rail*int(settings["rail_members"][1])+peg*int(settings["peg_members"][1])+inner)}


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
	last_rejection = ""
	var size: Vector2 = asset["dimensions_mm"]
	var polygon := _make_oriented_rect(point, size, angle)
	if not Geometry2D.clip_polygons(polygon, room).is_empty():
		return _reject("room")
	for reserved: PackedVector2Array in reservations:
		if not Geometry2D.intersect_polygons(polygon, reserved).is_empty():
			return _reject("reservation")
	var zone := "apron"
	if not island.is_empty():
		var crosses := not Geometry2D.intersect_polygons(polygon, island).is_empty()
		var outside := not Geometry2D.clip_polygons(polygon, island).is_empty()
		if crosses and outside:
			return _reject("island_edge")
		if not outside:
			zone = "island"
	var zones: Array = asset.get("zones", ["island", "apron", "room"])
	if zone not in zones and "room" not in zones:
		return _reject("zone")
	if zone == "apron" and String(asset.get("collision", "alpha")) != "flat":
		var closest := TrackBuilderCore._closest_point_on_loop(point, line)
		var sector := mini(SECTOR_COUNT - 1, int(float(closest["index"]) / line.size() * SECTOR_COUNT))
		if sector == open_sector:
			return _reject("open_sector")
	var clearance := float(asset.get("clearance_mm", 36.0))
	if not TrackBuilderCore._line_sweep_clears_footprint(line, point, size, &"rect", angle, half_width + clearance + 2.0):
		return _reject("corridor")
	if String(asset.get("collision", "alpha")) != "flat":
		for other: PackedVector2Array in occupied:
			if not Geometry2D.intersect_polygons(polygon, other).is_empty():
				return _reject("occupied")
	return {"position":point,"rotation":angle,"footprint":{"size":size,"kind":&"rect"},"zone":zone}


func _reject(reason: String) -> Dictionary:
	last_rejection = reason
	return {}


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
