extends RefCounted

const CATALOG := preload("res://scripts/race/world_environment_catalog.gd")
const ART := preload("res://scripts/race/world_environment_art.gd")
const DRESSING := preload("res://scripts/race/track_builder_dressing.gd")
const PLACEMENT := preload("res://scripts/race/track_builder_placement.gd")
const OBSTACLES := preload("res://scripts/race/track_builder_catalog.gd")
const SURFACES := preload("res://scripts/race/household_surface_materials.gd")
const SCENERY_SPACING := 750.0
const SCENERY_CLUSTER_GAP := 190.0
const FORMATION_HALF_SPAN := 75
const GIANT_SLOT_INTERVAL := 14
const EDGE_SPACING := 145.0
const EDGE_SIDE_OFFSET := 16.0
const OBSTACLE_SPACING := 2800.0
const SURFACE_SPACING := 4500.0
const FLOOR_SECTOR_LENGTH := 2000.0
const FLOOR_ROUTE_MARGIN := 500.0
const FLOOR_DETAIL_SPACING := 125.0
const GROUND_SECTION_SPACING := 570.0
const FLOOR_SIDE_INSET := 200.0
const MIN_SIDE_CLEARANCE := 48.0
const ROAD_OBSTACLE_INSET := 12.0
const MIN_OPEN_LANE := 90.0
const START_CLEARANCE := 650.0
const FINISH_CLEARANCE := 450.0


static func plan(spec: Dictionary, theme: StringName, line: PackedVector2Array, room: PackedVector2Array, gates: Array[Dictionary]) -> Dictionary:
	var seed := int(spec["dressing_seed"])
	var rng := RandomNumberGenerator.new()
	rng.seed = PLACEMENT.mix_seed(seed, "strip_environment")
	var candidates := CATALOG.candidates(theme, spec["story_kit"], spec)
	var gate_points := _gate_points(gates)
	var occupied: Array[Dictionary] = []
	var placements: Array[Dictionary] = []
	var total := _length(line)
	var slots := maxi(1, floori(total / SCENERY_SPACING))
	var pools := {}
	for role in ["focal", "support", "micro", "boundary", "ground", "decal"]:
		var pool: Array[Dictionary] = []
		for asset: Dictionary in candidates:
			if role in asset.get("roles", []):
				pool.append(asset)
		pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["id"]) < String(b["id"]))
		pools[role] = pool
	for slot in slots:
		var distance := START_CLEARANCE + (total - START_CLEARANCE - FINISH_CLEARANCE) * (slot + 0.5) / slots
		var role: String = "focal" if slot % GIANT_SLOT_INTERVAL == 0 else ["support", "micro", "boundary", "ground", "decal"][slot % 5]
		var pool: Array[Dictionary] = pools[role]
		if pool.is_empty():
			continue
		var members := 1 if role == "focal" else 2 + slot % 2
		for member in members:
			var member_arc := distance + (float(member) - float(members - 1) * 0.5) * SCENERY_CLUSTER_GAP
			var index := _at_arc_index(line, member_arc)
			var normal := (line[mini(index + 1, line.size() - 1)] - line[maxi(index - 1, 0)]).normalized().rotated(PI * 0.5)
			var asset: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
			var radius := maxf(24.0, PLACEMENT.asset_radius(String(asset["texture_path"]), (asset["dimensions_mm"] as Vector2).length() * 0.5))
			var offset := 125.0 + radius + MIN_SIDE_CLEARANCE + rng.randf_range(0.0, 140.0)
			var side := -1.0 if slot % 2 == 0 else 1.0
			var point := line[index] + normal * offset * side
			if not PLACEMENT.trackside_placement_is_safe(point, radius, room, line, gate_points, occupied):
				continue
			var rotation := rng.randf_range(-0.4, 0.4)
			if role == "boundary":
				var dimensions: Vector2 = asset["dimensions_mm"]
				rotation = normal.angle() - PI * 0.5 + (0.0 if dimensions.x >= dimensions.y else PI * 0.5)
			placements.append({"asset_id": asset["id"], "role": role, "position": point, "rotation": rotation, "zone": "apron"})
			occupied.append({"position": point, "radius": radius})
	var obstacles: Array[Dictionary] = []
	var roster: Array = OBSTACLES.GENERATED_OBSTACLE_TYPES.get(theme, [])
	if not roster.is_empty():
		var obstacle_rng := RandomNumberGenerator.new()
		obstacle_rng.seed = int(spec["obstacle_seed"])
		var obstacle_slots := maxi(1, floori(total / OBSTACLE_SPACING))
		for slot in obstacle_slots:
			var distance := START_CLEARANCE + (total - START_CLEARANCE - FINISH_CLEARANCE) * (slot + 0.5) / obstacle_slots
			var index := _at_arc_index(line, distance)
			var tangent := (line[mini(index + 1, line.size() - 1)] - line[maxi(index - 1, 0)]).normalized()
			var side_choice := -1.0 if obstacle_rng.randi() % 2 == 0 else 1.0
			var asset_start := obstacle_rng.randi_range(0, roster.size() - 1)
			var placed := false
			for asset_attempt in roster.size():
				var definition: Dictionary = (roster[(asset_start + asset_attempt) % roster.size()] as Dictionary).duplicate(true)
				var size := TrackBuilderCore.PROP_SCALE.size_for(String(definition["asset"]), Vector2(40.0, 40.0))
				var radius := size.length() * 0.5
				var offset := 125.0 - ROAD_OBSTACLE_INSET - radius
				if offset <= radius or 125.0 + offset - radius < MIN_OPEN_LANE:
					continue
				for side in [side_choice, -side_choice]:
					var position: Vector2 = line[index] + tangent.rotated(PI * 0.5) * offset * side
					if not PLACEMENT.inside_polygon_with_radius(position, radius, room) or not TrackBuilderCore._clear_of_points(position, gate_points, maxf(160.0, radius + 82.0)):
						continue
					if not TrackBuilderCore._clear_of_occupied(position, radius + 80.0, occupied):
						continue
					if not TrackBuilderCore._line_sweep_clears_footprint(line, position, size, &"rect", tangent.angle(), float(definition["clearance"])):
						continue
					definition.merge({"instance_id": "strip_%d" % slot, "position": position, "rotation": tangent.angle(), "centerline_index": index, "side": side, "footprint_kind": &"rect", "footprint_size": size, "visual_size": size, "visual_bounds": Rect2(-size * 0.5, size), "lateral_footprint_extent": radius, "lateral_center_offset": offset, "viable_corridor_width": 125.0 + offset - radius, "validated_ai_routes": PackedStringArray(["RacingLine"])})
					obstacles.append(definition)
					occupied.append({"position": position, "radius": radius})
					placed = true
					break
				if placed:
					break
	var edge_assets: Array[Dictionary] = []
	for path: String in spec.get("edge_decor", []):
		var asset := CATALOG.for_path(path)
		if not asset.is_empty():
			edge_assets.append(asset)
	if not edge_assets.is_empty():
		var edge_slots := maxi(1, floori(total / EDGE_SPACING))
		for slot in edge_slots:
			var index := _at_arc_index(line, START_CLEARANCE + (total - START_CLEARANCE - FINISH_CLEARANCE) * (slot + 0.5) / edge_slots)
			var normal := (line[mini(index + 1, line.size() - 1)] - line[maxi(index - 1, 0)]).normalized().rotated(PI * 0.5)
			for side in [-1.0, 1.0]:
				var asset: Dictionary = edge_assets[rng.randi_range(0, edge_assets.size() - 1)]
				var radius := maxf(18.0, PLACEMENT.asset_radius(String(asset["texture_path"]), float(asset["length_mm"]) * 0.5))
				var point: Vector2 = line[index] + normal * side * (125.0 + radius + MIN_SIDE_CLEARANCE + EDGE_SIDE_OFFSET)
				if not _edge_is_safe(point, radius, room, line, gate_points, occupied):
					continue
				placements.append({"asset_id": asset["id"], "role": "micro" if String(asset.get("collision", "flat")) == "flat" else "boundary", "position": point, "rotation": rng.randf_range(-0.45, 0.45), "zone": "apron", "edge_detail": true})
				occupied.append({"position": point, "radius": radius})
	return {"placements": placements, "obstacles": obstacles, "diagnostics": {"seed": seed, "total_placed": placements.size()}}


static func compose(root: Node2D, prepared: Dictionary) -> void:
	var spec: Dictionary = prepared["spec"]
	var line: PackedVector2Array = prepared["centerline"]
	var room: PackedVector2Array = prepared["room_polygon"]
	var story: Dictionary = spec["story_kit"]
	var gate_points := _gate_points(prepared["strip_gates"])
	var occupied: Array[Dictionary] = []
	var moments := Node2D.new()
	moments.name = "GeneratedMoments"
	root.add_child(moments)
	var containers := {}
	for role in ["focal", "support", "micro", "boundary", "ground", "decal"]:
		var container := Node2D.new()
		container.name = {"focal": "GiantLandmarks", "support": "ObjectLine", "micro": "MicroDetails", "boundary": "EdgeProps", "ground": "GroundProps", "decal": "FloorProps"}[role]
		moments.add_child(container)
		containers[role] = container
	var edge_container := Node2D.new()
	edge_container.name = "EdgeApronDecor"
	moments.add_child(edge_container)
	var plan: Dictionary = spec["environment_plan"]
	for entry: Dictionary in plan["placements"]:
		var asset := CATALOG.get_asset(String(entry["asset_id"]))
		ART.render_prop(edge_container if bool(entry.get("edge_detail", false)) else containers[entry["role"]], asset, entry)
		occupied.append({"position": entry["position"], "radius": PLACEMENT.asset_radius(String(asset["texture_path"]), float(asset["length_mm"]) * 0.5)})
	root.set_meta("environment_diagnostics", plan["diagnostics"])
	root.set_meta("environment_placements", plan["placements"])
	TrackBuilderCore._build_generated_obstacles(root, spec)
	for obstacle: Dictionary in spec["obstacle_plan"]:
		occupied.append({"position": obstacle["position"], "radius": (obstacle["footprint_size"] as Vector2).length() * 0.5})
	var rng := RandomNumberGenerator.new()
	rng.seed = PLACEMENT.mix_seed(int(spec["dressing_seed"]), "strip_floor")
	var bounds := TrackBuilderCore._polygon_bounds_rect(room)
	var sector_count := maxi(1, ceili(bounds.size.y / FLOOR_SECTOR_LENGTH))
	for sector_index in sector_count:
		var top := lerpf(bounds.position.y, bounds.end.y, float(sector_index) / sector_count)
		var bottom := lerpf(bounds.position.y, bounds.end.y, float(sector_index + 1) / sector_count)
		var half_width := bounds.size.x * 0.5 - FLOOR_SIDE_INSET
		var center_x := bounds.get_center().x
		var sector_room := PackedVector2Array([Vector2(center_x - half_width, top), Vector2(center_x + half_width, top), Vector2(center_x + half_width, bottom), Vector2(center_x - half_width, bottom)])
		var sector := Node2D.new()
		sector.name = "RunnerFloor%02d" % sector_index
		moments.add_child(sector)
		var sector_line := PackedVector2Array()
		for point: Vector2 in line:
			if point.y >= top - FLOOR_ROUTE_MARGIN and point.y <= bottom + FLOOR_ROUTE_MARGIN:
				sector_line.append(point)
		DRESSING.build_room_ground_sections(sector, story, spec, sector_line, PackedVector2Array(), sector_room, Callable(), ceili((bottom - top) / GROUND_SECTION_SPACING))
		DRESSING.build_room_floor_details(sector, spec, sector_line, sector_room, occupied, rng, ceili((bottom - top) / FLOOR_DETAIL_SPACING))
	var outer: PackedVector2Array = prepared["edges"]["left"]
	_build_local_formation(moments, "OpeningLandmark", {"asset": story["landmarks"][0], "count": 1}, &"unique", maxi(32, line.size() / 20), line, outer, room, gate_points, occupied)
	var formation: Dictionary = story["object_line"]
	_build_local_formation(moments, "StraightFormation", formation, &"few", line.size() / 2, line, outer, room, gate_points, occupied)
	_build_local_formation(moments, "CornerFormation", formation, &"few", line.size() * 3 / 4, line, outer, room, gate_points, occupied)
	DRESSING.build_open_generated_surfaces(root, moments, story, spec, line, gate_points, SURFACE_SPACING)
	SURFACES.apply(root, spec["surface_identity"])


static func _build_local_formation(parent: Node2D, name: String, data: Dictionary, quantity: StringName, preferred: int, line: PackedVector2Array, outer: PackedVector2Array, room: PackedVector2Array, gates: PackedVector2Array, occupied: Array[Dictionary]) -> void:
	var first := maxi(0, preferred - FORMATION_HALF_SPAN)
	var last := mini(line.size() - 1, preferred + FORMATION_HALF_SPAN)
	var local_line := PackedVector2Array()
	var local_outer := PackedVector2Array()
	for index in range(first, last + 1):
		local_line.append(line[index])
		local_outer.append(outer[index])
	DRESSING.build_track_formation(parent, name, data, quantity, preferred - first, local_line, local_outer, room, gates, occupied)
	var formation := parent.get_node_or_null(name)
	if formation != null:
		formation.set_meta("centerline_index", preferred)


static func _gate_points(gates: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for gate: Dictionary in gates:
		points.append(gate["position"])
	return points


static func _edge_is_safe(point: Vector2, radius: float, room: PackedVector2Array, line: PackedVector2Array, gates: PackedVector2Array, occupied: Array[Dictionary]) -> bool:
	# Edge pieces sit beyond the corridor plus the apron clearance. This also
	# clears the narrower centreline recovery lanes on both sides.
	return PLACEMENT.inside_polygon_with_radius(point, radius, room) \
		and TrackBuilderCore._distance_to_centerline(point, line) >= TrackBuilderCore.HALF_WIDTH + radius + TrackBuilderCore.APRON_COLLIDER_CLEARANCE \
		and TrackBuilderCore._clear_of_points(point, gates, radius + 24.0) \
		and TrackBuilderCore._clear_of_occupied(point, radius, occupied)


static func _at_arc_index(line: PackedVector2Array, distance: float) -> int:
	var arc := 0.0
	for index in range(1, line.size()):
		arc += line[index - 1].distance_to(line[index])
		if arc >= distance:
			return index
	return line.size() - 2


static func _length(line: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(1, line.size()):
		total += line[index - 1].distance_to(line[index])
	return total
