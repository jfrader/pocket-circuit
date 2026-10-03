extends RefCounted
## Review-only composition over the real generated course, never a shipping selector.

const CORE := preload("res://scripts/race/track_builder_core.gd")
const PROPS := preload("res://tools/environment_pilot_props.gd")
const SURFACES := preload("res://scripts/race/household_surface_materials.gd")
const MANIFEST := "res://tools/environment_pilot.json"
const CLEARANCE := 18.0
const SEPARATION := 10.0
const MATERIAL_PERIOD := Vector2(700, 700)
const ANCHOR_GRID := 19
const CLUSTER_HEADINGS := [0.0, PI * 0.5]
const CLUSTER_SEPARATION := 650.0

var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
var placements: Array[Dictionary] = []
var _occupied: Array[PackedVector2Array] = []
var _theme: String
var _assets: Dictionary
var _prepared: Dictionary
var _parent: Node2D
var _cluster_anchors: Array[Vector2] = []
var _surfaces: Dictionary


func prepare(theme: String, layout_seed: int = -1, material_seed: int = -1) -> Dictionary:
	_theme = theme
	var definition: Dictionary = manifest["themes"][theme]
	_assets = definition["assets"].duplicate(true)
	_assets.merge(definition["support_assets"], true)
	var recipe: Dictionary = definition["race"]
	var chosen_seed := int(recipe["seed"]) if layout_seed < 0 else layout_seed
	_prepared = CORE.prepare_route(StringName(theme), StringName(recipe["room"]), chosen_seed, {"length_tier": StringName(recipe.get("length_tier", "compact")), "obstacles_enabled": false})
	var spec: Dictionary = _prepared["spec"]
	_surfaces = SURFACES.resolve(StringName(theme), int(spec["material_seed"]) if material_seed < 0 else material_seed)
	spec["floor_texture"] = PROPS.TEXTURES + theme + "_floor.png"
	spec["track_texture"] = spec["floor_texture"]
	spec["floor_modulate"] = Color.WHITE
	spec["floor_tile_world_size"] = MATERIAL_PERIOD
	spec["island_material_texture"] = PROPS.TEXTURES + theme + "_island.png"
	spec["island_material_world_size"] = MATERIAL_PERIOD
	spec["edge_texture"] = spec["island_material_texture"]
	spec["rim_dark"] = Color(recipe["rim"])
	spec["rim_highlight"] = Color(recipe["lip"])
	spec["island"] = Color(recipe["rim"])
	for key: String in ["ambient_props", "gate_props", "corridor_patterns", "ground_sections", "giants"]:
		spec[key] = []
	return _prepared


func dress(track: Node2D, stage: Callable) -> void:
	placements.clear()
	_occupied.clear()
	_cluster_anchors.clear()
	var definition: Dictionary = manifest["themes"][_theme]
	var recipe: Dictionary = definition["race"]
	var raised: Array[Node] = [track.get_node("InnerBarrier")]
	var seals := track.get_node_or_null("PocketSeals")
	if seals:
		raised.append_array(seals.get_children())
	for rim: Node in raised:
		(rim.get_node("SideFace") as Line2D).position = Vector2(2, 3)
		(rim.get_node("SideFace") as Line2D).default_color = Color(recipe["rim"]).darkened(0.1)
		var edge := rim.get_node("TexturedRim") as Line2D
		edge.texture = null
		edge.default_color = Color(recipe["rim"]).lightened(0.12)
		(rim.get_node("TopLip") as Line2D).width = 3.0
		var pad := rim.get_node_or_null("RaisedPad") as Polygon2D
		if pad:
			pad.texture = load(PROPS.TEXTURES + _theme + "_island.png") as Texture2D
			pad.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			pad.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			pad.color = Color.WHITE
			var uvs := PackedVector2Array()
			for point: Vector2 in pad.polygon:
				uvs.append(point / MATERIAL_PERIOD * pad.texture.get_size())
			pad.uv = uvs
	_parent = Node2D.new()
	_parent.name = "PilotComposition"
	track.add_child(_parent)
	var centerline: PackedVector2Array = _prepared["centerline"]
	var gates := CORE._layout_gate_samples(centerline, _prepared["spec"])
	track.set_meta("generated_moment_indices", CORE._analyze_track_moments(centerline, gates))
	var arc := CORE._arc_lengths(centerline)
	var total: float = arc[arc.size() - 1]
	var island: PackedVector2Array = _prepared["edges"]["inner_boundary"]
	var inset := Geometry2D.offset_polygon(island, -45.0)
	var region: PackedVector2Array = inset[0] if not inset.is_empty() else island
	for candidate_region: PackedVector2Array in inset:
		if absf(CORE._polygon_area(candidate_region)) > absf(CORE._polygon_area(region)):
			region = candidate_region
	for cluster_index in 3:
		var fraction := [0.025, 0.39, 0.73][cluster_index] as float
		var sample := CORE._sample_at_arc(centerline, arc, total * fraction)
		var nearest: Dictionary = CORE._closest_point_on_loop(sample, island)
		var inward := sample.direction_to(nearest["position"])
		var preferred := sample + inward * 330.0
		var slots: Array = recipe["primary"] if cluster_index == 0 else recipe["secondary"]
		var anchor_fit := await _cluster_anchor(slots, preferred, region, stage)
		if not bool(anchor_fit["found"]):
			continue
		var anchor: Vector2 = anchor_fit["position"]
		_cluster_anchors.append(anchor)
		var heading := float(anchor_fit["heading"])
		var cluster_count := 0
		for slot: Array in slots:
			var key := String(slot[0])
			var position := anchor + Vector2(float(slot[1]), float(slot[2])).rotated(heading)
			var item_rotation := heading + float(slot[3])
			var placed := _place_near(key, position, item_rotation, region)
			if not placed.is_empty():
				cluster_count += 1
				placed["body"].set_meta("cluster_index", cluster_index)
			if cluster_index == 0 and key == "hero" and not placed.is_empty():
				track.set_meta("pilot_focal", placed["body"].position)
			await stage.call("Composing " + String(definition["story"]))
		track.set_meta("pilot_cluster_%d_count" % cluster_index, cluster_count)
	await _boundaries(recipe, centerline, arc, total, stage)
	await _gate_posts(recipe, centerline, stage)
	await _grip_patches(track, recipe, centerline, arc, total, stage)
	SURFACES.apply(track, _surfaces)
	track.set_meta("pilot_placement_count", placements.size())
	print("RACE_PILOT_ART theme=%s placements=%d focal=%s" % [_theme, placements.size(), track.get_meta("pilot_focal", Vector2.ZERO)])


func prepare_props(stage: Callable) -> void:
	for asset: Dictionary in _assets.values():
		PROPS.measure(_theme, asset)
		await stage.call("Preparing painted props")


func _cluster_anchor(slots: Array, preferred: Vector2, region: PackedVector2Array, stage: Callable) -> Dictionary:
	var bounds := CORE._polygon_bounds_rect(region)
	var best := {"found": false}
	var best_score := -INF
	var slot_sizes: Array[Vector2] = []
	for slot: Array in slots:
		slot_sizes.append(PROPS.measure(_theme, _assets[String(slot[0])])["size"])
	for row in ANCHOR_GRID:
		await stage.call("Finding room for the arrangement")
		for column in ANCHOR_GRID:
			var anchor := bounds.position + bounds.size * Vector2(float(column) + 0.5, float(row) + 0.5) / float(ANCHOR_GRID)
			var near_cluster := false
			for previous: Vector2 in _cluster_anchors:
				if anchor.distance_to(previous) < CLUSTER_SEPARATION:
					near_cluster = true
			if near_cluster:
				continue
			for heading: float in CLUSTER_HEADINGS:
				var score := 0.0
				var focal_fits := true
				for index in slots.size():
					var slot: Array = slots[index]
					var position := anchor + Vector2(float(slot[1]), float(slot[2])).rotated(heading)
					var polygon := CORE.TRACK_BUILDER_BOUNDARY._footprint_polygon(position, slot_sizes[index] + Vector2.ONE * SEPARATION, heading + float(slot[3]))
					var fits := Geometry2D.clip_polygons(polygon, region).is_empty() and _clear_occupied(polygon)
					if String(slot[0]) == "hero" and not fits:
						focal_fits = false
					if fits:
						score += 1.0
				if not focal_fits:
					continue
				score = score * 10000.0 - anchor.distance_to(preferred)
				if score > best_score:
					best_score = score
					best = {"found": true, "position": anchor, "heading": heading}
	return best


func _place_near(key: String, desired: Vector2, item_rotation: float, region: PackedVector2Array) -> Dictionary:
	var asset: Dictionary = _assets[key]
	var size: Vector2 = PROPS.measure(_theme, asset)["size"]
	var flat := String(asset.get("collision", "alpha")) == "flat"
	for attempt in 25:
		var ring := ceili(float(attempt) / 8.0)
		var candidate := desired + Vector2.from_angle(float(attempt % 8) * TAU / 8.0) * float(ring) * 30.0
		var polygon := CORE.TRACK_BUILDER_BOUNDARY._footprint_polygon(candidate, size + Vector2.ONE * SEPARATION, item_rotation)
		if not Geometry2D.clip_polygons(polygon, region).is_empty():
			continue
		if not flat and not _clear_occupied(polygon):
			continue
		if not CORE._line_sweep_clears_footprint(_prepared["centerline"], candidate, size, &"rect", item_rotation, CORE.HALF_WIDTH + CLEARANCE):
			continue
		return _spawn(key, candidate, item_rotation, polygon)
	return {}


func _spawn(key: String, position: Vector2, item_rotation: float, polygon: PackedVector2Array) -> Dictionary:
	var role := key if key in ["hero", "medium", "micro", "boundary"] else "medium"
	var item := PROPS.add(_parent, manifest, _theme, _assets[key], {"role": role, "position": [position.x, position.y], "rotation": item_rotation})
	item["asset_key"] = key
	placements.append(item)
	if not item["flat"]:
		_occupied.append(polygon)
	return item


func _clear_occupied(polygon: PackedVector2Array) -> bool:
	for other: PackedVector2Array in _occupied:
		if not Geometry2D.intersect_polygons(polygon, other).is_empty():
			return false
	return true


func _boundaries(recipe: Dictionary, centerline: PackedVector2Array, arc: PackedFloat32Array, total: float, stage: Callable) -> void:
	var island: PackedVector2Array = _prepared["edges"]["inner_boundary"]
	for index in 8:
		var distance := total * (floorf(float(index) / 2.0) + 0.45) / 4.0 + (float(index % 2) - 0.5) * 230.0
		var sample := CORE._sample_at_arc(centerline, arc, distance)
		var tangent := CORE._tangent_at_arc(centerline, arc, distance)
		var nearest: Dictionary = CORE._closest_point_on_loop(sample, island)
		var outward := (sample - (nearest["position"] as Vector2)).normalized()
		var family: Array = recipe["boundary_family"]
		var key := String(family[index % family.size()])
		var size: Vector2 = PROPS.measure(_theme, _assets[key])["size"]
		var position := sample + outward * (CORE.HALF_WIDTH + size.y * 0.5 + 30.0)
		_place_near(key, position, tangent.angle(), _prepared["room_polygon"])
		await stage.call("Placing household boundaries")


func _gate_posts(recipe: Dictionary, centerline: PackedVector2Array, stage: Callable) -> void:
	var key := String(recipe["gate_asset"])
	var gates := CORE._layout_gate_samples(centerline, _prepared["spec"])
	for gate: Vector2 in gates:
		var closest: Dictionary = CORE._closest_point_on_loop(gate, centerline)
		var tangent := CORE._sample_tangent(centerline, int(closest["index"]))
		for side in [-1, 1]:
			var position := gate + tangent.orthogonal() * CORE.GATE_POST_OFFSET * float(side)
			_place_near(key, position, 0.0, _prepared["room_polygon"])
			await stage.call("Marking checkpoints")


func _grip_patches(track: Node2D, recipe: Dictionary, centerline: PackedVector2Array, arc: PackedFloat32Array, total: float, stage: Callable) -> void:
	var surfaces: Array[Dictionary] = []
	var island: PackedVector2Array = _prepared["edges"]["inner_boundary"]
	var blocked_regions: Array[PackedVector2Array] = []
	for body: Node in track.find_children("*", "StaticBody2D", true, false):
		if body.has_meta("collision_boundary_polygon"):
			blocked_regions.append_array(Geometry2D.offset_polygon(body.get_meta("collision_boundary_polygon"), CLEARANCE))
	var key := String(recipe["surface_asset"])
	var size: Vector2 = PROPS.measure(_theme, _assets[key])["size"]
	for fraction: float in [0.30, 0.64]:
		var position := Vector2.ZERO
		var heading := 0.0
		var found := false
		for arc_offset: float in [0.0, 0.025, -0.025, 0.05, -0.05, 0.075, -0.075]:
			await stage.call("Finding a clear grip surface")
			var distance := total * wrapf(fraction + arc_offset, 0.0, 1.0)
			var sample := CORE._sample_at_arc(centerline, arc, distance)
			heading = CORE._tangent_at_arc(centerline, arc, distance).angle()
			if size.y > size.x:
				heading -= PI * 0.5
			var nearest: Dictionary = CORE._closest_point_on_loop(sample, island)
			var outward := (sample - (nearest["position"] as Vector2)).normalized()
			for step in 10:
				var candidate := sample + outward * float(step) * 15.0
				var polygon := CORE.TRACK_BUILDER_BOUNDARY._footprint_polygon(candidate, size, heading)
				var clear := Geometry2D.clip_polygons(polygon, _prepared["room_polygon"]).is_empty()
				for blocked: PackedVector2Array in blocked_regions:
					clear = clear and Geometry2D.intersect_polygons(polygon, blocked).is_empty()
				if clear:
					position = candidate
					found = true
					break
			if found:
				break
		if not found:
			continue
		var item := _spawn(key, position, heading, PackedVector2Array())
		var points: PackedVector2Array = item["outlines"][0]
		surfaces.append({"name": StringName(recipe["surface_name"]), "grip": float(recipe["grip"]), "speed": float(recipe["speed"]), "points": points, "role": &"grip_patch"})
		await stage.call("Laying grip surfaces")
	track.set_meta("generated_surfaces", surfaces)
