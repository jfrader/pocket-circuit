extends RefCounted

const CATALOG := preload("res://scripts/race/world_environment_catalog.gd")
const ART := preload("res://scripts/race/world_environment_art.gd")
const DRESSING := preload("res://scripts/race/track_builder_dressing.gd")
const PLACEMENT := preload("res://scripts/race/track_builder_placement.gd")
const OBSTACLES := preload("res://scripts/race/track_builder_catalog.gd")
const SURFACES := preload("res://scripts/race/household_surface_materials.gd")
const SCENERY_SPACING := 900.0
const OBSTACLE_SPACING := 5700.0
const SURFACE_SPACING := 9000.0
const FLOOR_SECTOR_LENGTH := 8000.0
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
		var index := _at_arc_index(line, distance)
		var normal := (line[mini(index + 1, line.size() - 1)] - line[maxi(index - 1, 0)]).normalized().rotated(PI * 0.5)
		var role: String = "focal" if slot % 13 == 0 else ["support", "micro", "boundary", "ground", "decal"][slot % 5]
		var pool: Array[Dictionary] = pools[role]
		if pool.is_empty():
			continue
		var asset: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		var radius := maxf(24.0, PLACEMENT.asset_radius(String(asset["texture_path"]), (asset["dimensions_mm"] as Vector2).length() * 0.5))
		var offset := 125.0 + radius + MIN_SIDE_CLEARANCE + rng.randf_range(0.0, 140.0)
		var side := -1.0 if slot % 2 == 0 else 1.0
		var point := line[index] + normal * offset * side
		if not PLACEMENT.trackside_placement_is_safe(point, radius, room, line, gate_points, occupied):
			continue
		placements.append({"asset_id": asset["id"], "role": role, "position": point, "rotation": rng.randf_range(-0.4, 0.4), "zone": "apron"})
		occupied.append({"position": point, "radius": radius})
	var obstacles: Array[Dictionary] = []
	var roster: Array = OBSTACLES.GENERATED_OBSTACLE_TYPES.get(theme, [])
	if not roster.is_empty():
		var obstacle_rng := RandomNumberGenerator.new()
		obstacle_rng.seed = int(spec["obstacle_seed"])
		for slot in maxi(1, floori(total / OBSTACLE_SPACING)):
			var distance := START_CLEARANCE + (total - START_CLEARANCE - FINISH_CLEARANCE) * (slot + 0.5) / maxi(1, floori(total / OBSTACLE_SPACING))
			var index := _at_arc_index(line, distance)
			var definition: Dictionary = (roster[obstacle_rng.randi_range(0, roster.size() - 1)] as Dictionary).duplicate(true)
			var size := TrackBuilderCore.PROP_SCALE.size_for(String(definition["asset"]), Vector2(40.0, 40.0))
			var radius := size.length() * 0.5
			var offset := 125.0 - ROAD_OBSTACLE_INSET - radius
			if offset <= radius or 125.0 + offset - radius < MIN_OPEN_LANE:
				continue
			var tangent := (line[mini(index + 1, line.size() - 1)] - line[maxi(index - 1, 0)]).normalized()
			var side := -1.0 if obstacle_rng.randi() % 2 == 0 else 1.0
			var position := line[index] + tangent.rotated(PI * 0.5) * offset * side
			if not PLACEMENT.inside_polygon_with_radius(position, radius, room) or not TrackBuilderCore._clear_of_points(position, gate_points, maxf(160.0, radius + 82.0)):
				continue
			if not TrackBuilderCore._clear_of_occupied(position, radius + 80.0, occupied):
				continue
			if not TrackBuilderCore._line_sweep_clears_footprint(line, position, size, &"rect", tangent.angle(), float(definition["clearance"])):
				continue
			definition.merge({"instance_id": "strip_%d" % slot, "position": position, "rotation": tangent.angle(), "centerline_index": index, "side": side, "footprint_kind": &"rect", "footprint_size": size, "visual_size": size, "visual_bounds": Rect2(-size * 0.5, size), "lateral_footprint_extent": radius, "lateral_center_offset": offset, "viable_corridor_width": 125.0 + offset - radius, "validated_ai_routes": PackedStringArray(["RacingLine"])})
			obstacles.append(definition)
			occupied.append({"position": position, "radius": radius})
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
	var plan: Dictionary = spec["environment_plan"]
	for entry: Dictionary in plan["placements"]:
		ART.render_prop(containers[entry["role"]], CATALOG.get_asset(String(entry["asset_id"])), entry)
		occupied.append({"position": entry["position"], "radius": 60.0})
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
		DRESSING.build_room_ground_sections(sector, story, spec, line, PackedVector2Array(), sector_room)
		DRESSING.build_room_floor_details(sector, spec, line, sector_room, occupied, rng)
	DRESSING.build_edge_and_apron_decor(moments, spec, line, room, gate_points, occupied)
	var outer: PackedVector2Array = prepared["edges"]["left"]
	DRESSING.build_track_formation(moments, "OpeningLandmark", {"asset": story["landmarks"][0], "count": 1}, &"unique", maxi(32, line.size() / 20), line, outer, room, gate_points, occupied)
	var formation: Dictionary = story["object_line"]
	DRESSING.build_track_formation(moments, "StraightFormation", formation, &"few", line.size() / 2, line, outer, room, gate_points, occupied)
	DRESSING.build_track_formation(moments, "CornerFormation", formation, &"few", line.size() * 3 / 4, line, outer, room, gate_points, occupied)
	DRESSING.build_open_generated_surfaces(root, moments, story, spec, line, gate_points, SURFACE_SPACING)
	SURFACES.apply(root, spec["surface_identity"])


static func _gate_points(gates: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for gate: Dictionary in gates:
		points.append(gate["position"])
	return points


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
