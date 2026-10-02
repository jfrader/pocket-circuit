class_name TrackBuilderDressing
## Generated dressing: moments, formations, giants, room details, surfaces.

## Loose debris varies per track: how many pieces, how big, and where across the
## road. A patch never touches the corridor edge, so it stays a thing to drive
## over rather than a wall.
const GRIP_PATCH_MIN_HALF_WIDTH := 26.0
const GRIP_PATCH_MAX_HALF_WIDTH := 64.0
const GRIP_PATCH_MIN_HALF_SPAN := 2
const GRIP_PATCH_MAX_HALF_SPAN := 5
const GRIP_PATCH_EDGE_MARGIN := 12.0


## Technical surface strip reach, in samples each side of its centre.
const TECHNICAL_HALF_SPAN := 6
## Surfaces keep this many samples from the finish line and from each other.
const SURFACE_START_CLEARANCE := 18
const SURFACE_SEPARATION := 16
const SURFACE_GATE_CLEARANCE := 155.0


static func analyze_track_moments(centerline: PackedVector2Array, gate_samples: PackedVector2Array, surface_seed: int = 0) -> Dictionary:
	var count := centerline.size()
	var straight_candidates: Array[Dictionary] = []
	var corner_candidates: Array[Dictionary] = []
	for index in range(0, count, 2):
		var turn := TrackBuilderCore._turn_strength(centerline, index, 9)
		var chord := centerline[posmod(index + 16, count)].distance_to(centerline[posmod(index - 16, count)])
		straight_candidates.append({"index": index, "score": chord - turn * 720.0})
		corner_candidates.append({"index": index, "score": turn})
	straight_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["index"]) < int(b["index"]) if is_equal_approx(float(a["score"]), float(b["score"])) else float(a["score"]) > float(b["score"]))
	corner_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["index"]) < int(b["index"]) if is_equal_approx(float(a["score"]), float(b["score"])) else float(a["score"]) > float(b["score"]))

	var longest := pick_straight_candidate(straight_candidates, centerline, gate_samples, [0], 30)
	var second := pick_straight_candidate(straight_candidates, centerline, gate_samples, [0, longest], 48)
	var corners := PackedInt32Array()
	for candidate: Dictionary in corner_candidates:
		var index := int(candidate["index"])
		if TrackBuilderCore._cyclic_index_distance(index, 0, count) < 24:
			continue
		var separated := true
		for chosen: int in corners:
			if TrackBuilderCore._cyclic_index_distance(index, chosen, count) < 38:
				separated = false
				break
		if not separated:
			continue
		corners.append(index)
		if corners.size() >= 4:
			break
	for fallback_fraction: float in [0.25, 0.5, 0.75]:
		if corners.size() >= 2:
			break
		var fallback := int(round(float(count) * fallback_fraction)) % count
		var separated := true
		for chosen: int in corners:
			if TrackBuilderCore._cyclic_index_distance(fallback, chosen, count) < 38:
				separated = false
		if separated:
			corners.append(fallback)
	while corners.size() < 2:
		corners.append(posmod(72 + corners.size() * 96, count))

	var shortcut := int(corners[0])
	var shortcut_gain := -INF
	for corner: int in corners:
		var geometry := shortcut_lane_geometry(centerline, corner)
		var gain := float(geometry["safe_length"]) - float(geometry["shortcut_length"])
		if gain > shortcut_gain:
			shortcut_gain = gain
			shortcut = corner
	var clearance := TrackCornerMap.clearances(centerline)
	var technical := pick_calm_surface_index(centerline, gate_samples, clearance, TECHNICAL_HALF_SPAN, PackedInt32Array([shortcut]), surface_seed)
	return {
		"opening": 0,
		"longest_straight": longest,
		"second_straight": second,
		"corners": corners,
		"shortcut": shortcut,
		"technical": technical,
		"corner_clearance": clearance,
	}


## A seeded calm centre index for a surface spanning `half_span` samples, clear
## of the finish line, gates and `avoid`; -1 when the lap has no such room.
static func pick_calm_surface_index(
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		clearance: PackedFloat32Array,
		half_span: int,
		avoid: PackedInt32Array,
		seed: int
) -> int:
	var count := centerline.size()
	var options := PackedInt32Array()
	for index in TrackCornerMap.calm_indices(clearance, half_span):
		if TrackBuilderCore._cyclic_index_distance(index, 0, count) < SURFACE_START_CLEARANCE:
			continue
		var separated := true
		for other: int in avoid:
			if other >= 0 and TrackBuilderCore._cyclic_index_distance(index, other, count) < SURFACE_SEPARATION:
				separated = false
				break
		if separated and TrackBuilderCore._clear_of_points(centerline[index], gate_samples, SURFACE_GATE_CLEARANCE):
			options.append(index)
	if options.is_empty():
		return -1
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return options[rng.randi_range(0, options.size() - 1)]


static func default_act_for_theme(theme: StringName) -> int:
	match theme:
		&"workshop":
			return 2
		&"office":
			return 3
	return 1


static func layout_gate_samples(centerline: PackedVector2Array, spec: Dictionary) -> PackedVector2Array:
	var samples := PackedVector2Array()
	var fractions: Array = spec.get("gate_fractions", [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.84])
	var arc := TrackBuilderCore._arc_lengths(centerline)
	var total := arc[arc.size() - 1]
	for gate_index in TrackBuilderCore.GATE_COUNT:
		samples.append(TrackBuilderCore._sample_at_arc(centerline, arc, total * float(fractions[gate_index])))
	return samples


static func build_opening_landmark(
		parent: Node2D,
		story: Dictionary,
		spec: Dictionary,
		centerline: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary]
) -> int:
	var opening := Node2D.new()
	opening.name = "OpeningLandmark"
	parent.add_child(opening)
	var assets: Array = story["landmarks"]
	var asset_index := posmod(TrackBuilderCore._mix_seed(int(spec.get("dressing_seed", spec["requested_seed"])), "opening_asset"), assets.size())
	var asset_path := String(story.get("opening_asset", assets[asset_index]))
	opening.set_meta("asset_path", asset_path)
	opening.set_meta("semantic_quantity", &"unique")
	opening.set_meta("requested_count", 1)
	var base_radius := TrackBuilderCore._asset_radius(asset_path, 64.0)
	var size_scale := 1.0
	var radius := base_radius * size_scale
	var preferred := int(round(float(centerline.size()) * float(spec.get("opening_fraction", 0.11))))
	var selected_index := preferred
	var placed_count := 0
	# Search the first quarter of the lap rather than trusting one index; long
	# landmarks do not fit on the outer side of every narrow-room opening.
	for index_attempt in 18:
		var index_offset := (index_attempt + 1) / 2 * 4
		var index_direction := -1 if index_attempt % 2 == 0 else 1
		var index := posmod(preferred + index_offset * index_direction, centerline.size())
		var tangent := TrackBuilderCore._sample_tangent(centerline, index)
		var outward := (outer_loop[index] - centerline[index]).normalized()
		for placement_attempt in 12:
			var side := 1.0 if placement_attempt % 2 == 0 else -1.0
			var along := tangent * (float(placement_attempt / 4) - 1.0) * 30.0
			var offset := TrackBuilderCore.HALF_WIDTH + radius + TrackBuilderCore.APRON_COLLIDER_CLEARANCE + float((placement_attempt / 2) % 2) * 12.0
			var candidate := centerline[index] + outward * side * offset + along
			if not TrackBuilderCore._inside_polygon_with_radius(candidate, radius, room_polygon):
				continue
			if TrackBuilderCore._distance_to_centerline(candidate, centerline) < TrackBuilderCore.HALF_WIDTH + radius + 7.0:
				continue
			if not TrackBuilderCore._clear_of_points(candidate, gate_samples, 24.0 + radius):
				continue
			if not TrackBuilderCore._clear_of_recovery_lanes(candidate, radius, centerline, gate_samples):
				continue
			if not TrackBuilderCore._clear_of_occupied(candidate, radius, occupied):
				continue
			TrackBuilderCore._add_generated_prop(opening, "Focal", candidate, asset_path, tangent.angle(), &"opening", &"unique", 0, size_scale)
			occupied.append({"position": candidate, "radius": radius})
			selected_index = index
			placed_count = 1
			break
		if placed_count == 1:
			break
	if placed_count == 0:
		var exhaustive := TrackBuilderCore._best_trackside_position(preferred, radius, centerline, outer_loop, room_polygon, gate_samples, occupied)
		if bool(exhaustive["found"]):
			var candidate: Vector2 = exhaustive["position"]
			selected_index = int(exhaustive["index"])
			TrackBuilderCore._add_generated_prop(opening, "Focal", candidate, asset_path, TrackBuilderCore._sample_tangent(centerline, selected_index).angle(), &"opening", &"unique", 0, size_scale)
			occupied.append({"position": candidate, "radius": radius})
			placed_count = 1
	if placed_count == 0:
		for replacement: String in spec["landmark_fallbacks"]:
			var replacement_radius := TrackBuilderCore._asset_radius(replacement, 24.0)
			var fit := TrackBuilderCore._best_trackside_position(preferred, replacement_radius, centerline, outer_loop, room_polygon, gate_samples, occupied)
			if not bool(fit["found"]):
				continue
			selected_index = int(fit["index"])
			TrackBuilderCore._add_generated_prop(opening, "Focal", fit["position"], replacement, TrackBuilderCore._sample_tangent(centerline, selected_index).angle(), &"opening", &"unique", 0)
			occupied.append({"position": fit["position"], "radius": replacement_radius})
			opening.set_meta("asset_path", replacement)
			opening.set_meta("replaced_asset", asset_path)
			placed_count = 1
			break
	opening.set_meta("centerline_index", selected_index)
	opening.set_meta("placed_count", placed_count)
	return selected_index


static func pick_straight_candidate(
		candidates: Array[Dictionary],
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		excluded: Array,
		minimum_separation: int
) -> int:
	for candidate: Dictionary in candidates:
		var index := int(candidate["index"])
		var allowed := true
		for excluded_index: int in excluded:
			if TrackBuilderCore._cyclic_index_distance(index, excluded_index, centerline.size()) < minimum_separation:
				allowed = false
				break
		if not allowed or not TrackBuilderCore._clear_of_points(centerline[index], gate_samples, 175.0):
			continue
		return index
	return posmod(minimum_separation * maxi(excluded.size(), 1), centerline.size())



static func safe_moment_index(centerline: PackedVector2Array, preferred: int, gate_samples: PackedVector2Array, clearance: float) -> int:
	var count := centerline.size()
	for distance in range(0, 31, 2):
		for direction in [-1, 1]:
			var index := posmod(preferred + distance * direction, count)
			if TrackBuilderCore._cyclic_index_distance(index, 0, count) < 26:
				continue
			if TrackBuilderCore._clear_of_points(centerline[index], gate_samples, clearance):
				return index
	return preferred


static func bounded_quantity_count(quantity: StringName, requested: int) -> int:
	match quantity:
		&"unique":
			return 1
		&"few":
			return clampi(requested, 2, 3)
		&"many":
			return clampi(requested, 8, 20)
	return clampi(requested, 1, 20)


static func formation_assets(data: Dictionary) -> Array[String]:
	var assets: Array[String] = []
	for value: Variant in data.get("assets", []):
		var asset_path := String(value)
		if not asset_path.is_empty() and asset_path not in assets:
			assets.append(asset_path)
	if assets.is_empty():
		var fallback := String(data.get("asset", ""))
		if not fallback.is_empty():
			assets.append(fallback)
	return assets


static func semantic_formation_offset(formation: StringName, index: int, count: int, radius: float) -> Vector2:
	var spacing := maxf(radius * 2.0 + 9.0, 25.0)
	match formation:
		&"line":
			return Vector2((float(index) - float(count - 1) * 0.5) * spacing, 0.0)
		&"arc":
			var arc_angle := lerpf(-1.05, 1.05, float(index) / maxf(float(count - 1), 1.0))
			var arc_radius := maxf(54.0, spacing * float(count) * 0.27)
			return Vector2(cos(arc_angle), sin(arc_angle)) * arc_radius - Vector2(arc_radius * 0.55, 0.0)
		&"cluster":
			var columns := ceili(sqrt(float(count)))
			var row := index / columns
			var column := index % columns
			var rows := ceili(float(count) / float(columns))
			return Vector2(
				(float(column) - float(columns - 1) * 0.5) * spacing,
				(float(row) - float(rows - 1) * 0.5) * spacing
			)
	return Vector2.ZERO


static func island_anchor(inner_loop: PackedVector2Array, centerline: PackedVector2Array) -> Vector2:
	var average := Vector2.ZERO
	var bounds := Rect2(inner_loop[0], Vector2.ZERO)
	for point: Vector2 in inner_loop:
		average += point
		bounds = bounds.expand(point)
	average /= float(inner_loop.size())
	if Geometry2D.is_point_in_polygon(average, inner_loop):
		return average
	var best := average
	var best_clearance := -INF
	for x in 7:
		for y in 7:
			var candidate := bounds.position + Vector2(bounds.size.x * (float(x) + 0.5) / 7.0, bounds.size.y * (float(y) + 0.5) / 7.0)
			if not Geometry2D.is_point_in_polygon(candidate, inner_loop):
				continue
			var clearance := TrackBuilderCore._distance_to_centerline(candidate, centerline)
			if clearance > best_clearance:
				best_clearance = clearance
				best = candidate
	return best



static func polygon_bounds_rect(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


static func build_track_formation(
		parent: Node2D,
		node_name: String,
		data: Dictionary,
		quantity: StringName,
		moment_index: int,
		centerline: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary],
		stage: Callable = Callable()
) -> void:
	var asset_paths := formation_assets(data)
	if asset_paths.is_empty():
		return
	var formation := Node2D.new()
	formation.name = node_name
	formation.set_meta("semantic_quantity", quantity)
	formation.set_meta("centerline_index", moment_index)
	formation.set_meta("asset_path", asset_paths[0])
	formation.set_meta("asset_paths", PackedStringArray(asset_paths))
	parent.add_child(formation)
	var requested_count := bounded_quantity_count(quantity, int(data["count"]))
	formation.set_meta("requested_count", requested_count)
	var maximum_radius := 0.0
	for asset_path: String in asset_paths:
		maximum_radius = maxf(maximum_radius, TrackBuilderCore._asset_radius(asset_path, 18.0))
	var sample_step := (5 if maximum_radius > 20.0 else (4 if maximum_radius > 12.0 else 3)) if quantity == &"many" else maxi(6, ceili((maximum_radius * 2.0 + 10.0) / 10.0))
	var variant_start := posmod(TrackBuilderCore._mix_seed(moment_index, node_name), asset_paths.size())
	var placed_count := 0
	for item_index in requested_count:
		if stage.is_valid() and item_index > 0:
			await stage.call("Placing track objects")
		var asset_path := asset_paths[(variant_start + item_index) % asset_paths.size()]
		var radius := TrackBuilderCore._asset_radius(asset_path, 18.0)
		var sample_offset := int(round((float(item_index) - float(requested_count - 1) * 0.5) * float(sample_step)))
		var placed := false
		for adjustment_attempt in 17:
			var adjustment_magnitude := (adjustment_attempt + 1) / 2
			var adjustment_direction := -1 if adjustment_attempt % 2 == 0 else 1
			var adjustment := 0 if adjustment_attempt == 0 else adjustment_magnitude * adjustment_direction
			var index := posmod(moment_index + sample_offset + adjustment, centerline.size())
			var tangent := TrackBuilderCore._sample_tangent(centerline, index)
			var outward := (outer_loop[index] - centerline[index]).normalized()
			for attempt in 8:
				var side := 1.0 if attempt % 2 == 0 else -1.0
				var direction := outward * side
				var offset := TrackBuilderCore.HALF_WIDTH + radius + TrackBuilderCore.APRON_COLLIDER_CLEARANCE + float(attempt / 2) * 8.0
				var candidate := centerline[index] + direction * offset
				if not TrackBuilderCore._trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied):
					continue
				TrackBuilderCore._add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, tangent.angle(), &"trackside", quantity, item_index)
				occupied.append({"position": candidate, "radius": radius})
				placed_count += 1
				placed = true
				break
			if placed:
				break
		if not placed:
			var exhaustive := TrackBuilderCore._best_trackside_position(moment_index + sample_offset, radius, centerline, outer_loop, room_polygon, gate_samples, occupied)
			if bool(exhaustive["found"]):
				var candidate: Vector2 = exhaustive["position"]
				var index := int(exhaustive["index"])
				TrackBuilderCore._add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, TrackBuilderCore._sample_tangent(centerline, index).angle(), &"trackside", quantity, item_index)
				occupied.append({"position": candidate, "radius": radius})
				placed_count += 1
				placed = true
		if not placed:
			continue
	formation.set_meta("placed_count", placed_count)


static func build_corner_landmarks(
		parent: Node2D,
		story: Dictionary,
		spec: Dictionary,
		corner_indices: PackedInt32Array,
		centerline: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		reserved_unique_assets: Dictionary,
		occupied: Array[Dictionary]
) -> void:
	var landmarks := Node2D.new()
	landmarks.name = "CornerLandmarks"
	parent.add_child(landmarks)
	var assets: Array = story["landmarks"]
	var asset_start := posmod(TrackBuilderCore._mix_seed(int(spec.get("dressing_seed", spec["requested_seed"])), "landmark_asset"), assets.size())
	var available_assets: Array[String] = []
	for asset_offset in assets.size():
		var asset_path := String(assets[(asset_start + asset_offset) % assets.size()])
		if not reserved_unique_assets.has(asset_path):
			available_assets.append(asset_path)
	var target_count := mini(1 + posmod(TrackBuilderCore._mix_seed(int(spec.get("dressing_seed", spec["requested_seed"])), "landmarks"), 2), available_assets.size())
	for asset_path: String in spec["landmark_fallbacks"]:
		if not reserved_unique_assets.has(asset_path) and asset_path not in available_assets:
			available_assets.append(asset_path)
	landmarks.set_meta("requested_count", target_count)
	var placed_count := 0
	for corner_slot in corner_indices.size():
		if placed_count >= target_count:
			break
		var index := int(corner_indices[corner_slot])
		var asset_path := available_assets[placed_count]
		var base_radius := TrackBuilderCore._asset_radius(asset_path, 64.0)
		var size_scale := 1.0
		var radius := base_radius * size_scale
		var outward := (outer_loop[index] - centerline[index]).normalized()
		for attempt in 12:
			var side := 1.0 if attempt % 2 == 0 else -1.0
			var along := TrackBuilderCore._sample_tangent(centerline, index) * (float(attempt / 4) - 1.0) * 28.0
			var offset := TrackBuilderCore.HALF_WIDTH + radius + TrackBuilderCore.APRON_COLLIDER_CLEARANCE + float((attempt / 2) % 2) * 12.0
			var candidate := centerline[index] + outward * side * offset + along
			if not TrackBuilderCore._trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied):
				continue
			TrackBuilderCore._add_generated_prop(landmarks, "Landmark%02d" % placed_count, candidate, asset_path, float(corner_slot) * 0.37, &"corner", &"unique", placed_count, size_scale)
			occupied.append({"position": candidate, "radius": radius})
			reserved_unique_assets[asset_path] = true
			placed_count += 1
			break
	for asset_path: String in available_assets:
		if placed_count >= target_count:
			break
		if reserved_unique_assets.has(asset_path):
			continue
		var base_radius := TrackBuilderCore._asset_radius(asset_path, 64.0)
		var size_scale := 1.0
		var radius := base_radius * size_scale
		var preferred_index := int(corner_indices[mini(placed_count, corner_indices.size() - 1)])
		var exhaustive := TrackBuilderCore._best_trackside_position(preferred_index, radius, centerline, outer_loop, room_polygon, gate_samples, occupied)
		if not bool(exhaustive["found"]):
			continue
		var candidate: Vector2 = exhaustive["position"]
		var index := int(exhaustive["index"])
		TrackBuilderCore._add_generated_prop(landmarks, "Landmark%02d" % placed_count, candidate, asset_path, TrackBuilderCore._sample_tangent(centerline, index).angle(), &"corner", &"unique", placed_count, size_scale)
		occupied.append({"position": candidate, "radius": radius})
		reserved_unique_assets[asset_path] = true
		placed_count += 1
	landmarks.set_meta("placed_count", placed_count)


static func build_room_dressing(
		parent: Node2D,
		story: Dictionary,
		spec: Dictionary,
		centerline: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		reserved_unique_assets: Dictionary,
		occupied: Array[Dictionary],
		stage: Callable = Callable()
) -> void:
	var dressing := Node2D.new()
	dressing.name = "RoomDressing"
	dressing.set_meta("moment_kind", &"ambient")
	dressing.set_meta("semantic_quantity", &"many")
	parent.add_child(dressing)
	var asset_pool := room_dressing_assets(story, spec, reserved_unique_assets)
	var rng := RandomNumberGenerator.new()
	rng.seed = TrackBuilderCore._mix_seed(int(spec.get("dressing_seed", spec["requested_seed"])), "room_dressing:%s" % String(story["id"]))
	var room_area := absf(TrackBuilderCore._polygon_area(room_polygon))
	var target_pockets := clampi(int(round(room_area / 450000.0)), 4, 6)
	var target_count := target_pockets * 3
	dressing.set_meta("requested_count", target_count)
	var anchors := room_dressing_anchors(room_polygon, centerline, gate_samples, occupied, target_pockets, rng)
	var placed_count := 0
	for pocket_index in anchors.size():
		if stage.is_valid():
			await stage.call("Dressing the room")
		var pocket := Node2D.new()
		pocket.name = "Pocket%02d" % pocket_index
		pocket.set_meta("semantic_quantity", &"few")
		dressing.add_child(pocket)
		var anchor: Vector2 = anchors[pocket_index]
		var base_angle := rng.randf_range(0.0, TAU)
		var pocket_count := mini(3, target_count - placed_count)
		var pocket_placed := 0
		for item_index in pocket_count:
			if asset_pool.is_empty():
				break
			var asset_path := String(asset_pool[(pocket_index * 3 + item_index) % asset_pool.size()])
			var base_radius := TrackBuilderCore._asset_radius(asset_path, 24.0)
			var size_scale := 1.0
			var radius := base_radius * size_scale
			var placed := false
			for attempt in 12:
				var ring := radius * 2.0 + 12.0 + float(attempt / 6) * 10.0
				var angle := base_angle + TAU * float(item_index) / float(pocket_count) + TAU * float(attempt % 6) / 18.0
				var candidate := anchor + Vector2.RIGHT.rotated(angle) * ring
				if not TrackBuilderCore._trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied):
					continue
				TrackBuilderCore._add_generated_prop(pocket, "Item%02d" % item_index, candidate, asset_path, rng.randf_range(0.0, TAU), &"ambient", &"few", placed_count, size_scale)
				occupied.append({"position": candidate, "radius": radius})
				placed_count += 1
				pocket_placed += 1
				placed = true
				break
			if not placed:
				continue
		pocket.set_meta("placed_count", pocket_placed)
	if stage.is_valid():
		await stage.call("Laying room materials")
	var ground_section_count: int = await build_room_ground_sections(dressing, story, spec, centerline, outer_loop, room_polygon, stage)
	if stage.is_valid():
		await stage.call("Adding floor detail")
	var decal_count := build_room_floor_details(dressing, spec, centerline, room_polygon, occupied, rng)
	dressing.set_meta("placed_count", placed_count)
	dressing.set_meta("pocket_count", anchors.size())
	dressing.set_meta("ground_section_count", ground_section_count)
	dressing.set_meta("decal_count", decal_count)


static func build_edge_and_apron_decor(
		parent: Node2D,
		spec: Dictionary,
		centerline: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary],
		stage: Callable = Callable()
) -> void:
	var decor: Array = spec.get("edge_decor", [])
	if decor.is_empty():
		return
	var container := Node2D.new()
	container.name = "EdgeApronDecor"
	container.set_meta("moment_kind", &"edge_decor")
	parent.add_child(container)
	var rng := RandomNumberGenerator.new()
	rng.seed = TrackBuilderCore._mix_seed(int(spec.get("dressing_seed", spec.get("requested_seed", 0))), "edge_decor:%s" % String(spec.get("story_id", "")))
	var target := clampi(24 + int(rng.randf() * 17), 24, 40)
	var placed := 0
	var bounds := polygon_bounds_rect(room_polygon)
	# A few readable details sit along both edges and into the apron. Painted
	# material details stay FLAT; recognizable hardware becomes SOLID scenery.
	var last_yield := Time.get_ticks_usec()
	for attempt in 1200:
		if stage.is_valid() and Time.get_ticks_usec() - last_yield >= 6000:
			await stage.call("Adding surface detail")
			last_yield = Time.get_ticks_usec()
		var candidate := Vector2(
			rng.randf_range(bounds.position.x, bounds.end.x),
			rng.randf_range(bounds.position.y, bounds.end.y)
		)
		var d := TrackBuilderCore._distance_to_centerline(candidate, centerline)
		if d > TrackBuilderCore.HALF_WIDTH + 380.0:
			continue
		if not Geometry2D.is_point_in_polygon(candidate, room_polygon):
			continue
		if candidate.distance_to(centerline[0]) < 300.0:
			continue
		var tex_path := String(decor[rng.randi() % decor.size()])
		var tex := TrackBuilderCore.asset_texture(tex_path)
		if tex == null:
			continue
		var sz := TrackBuilderCore.PROP_SCALE.length_for(tex_path, rng.randf_range(22.0, 52.0))
		var sprite_scale := TrackBuilderCore.PROP_SCALE.sprite_scale(tex, TrackBuilderCore._texture_opaque_rect(tex), sz)
		var rotation := rng.randf_range(0.0, TAU)
		var alpha := rng.randf_range(0.55, 0.92)
		var is_flat := TrackBuilderCore.FLAT_EDGE_ASSETS.has(tex_path.get_file())
		var shape_kind := StringName(TrackBuilderCore.SOLID_EDGE_SHAPES.get(tex_path.get_file(), &""))
		if not is_flat and shape_kind.is_empty():
			push_error("TrackBuilderCore: edge object has no explicit SOLID/FLAT contract: %s" % tex_path)
			continue
		var visible_footprint := TrackBuilderCore._texture_opaque_rect(tex).size * sprite_scale
		var clearance_radius := 0.0 if is_flat else (maxf(visible_footprint.x, visible_footprint.y) * 0.5 if shape_kind == &"circle" else visible_footprint.length() * 0.5)
		var corridor_margin := 8.0 if is_flat else clearance_radius + TrackBuilderCore.APRON_COLLIDER_CLEARANCE
		if d < TrackBuilderCore.HALF_WIDTH + corridor_margin:
			continue
		if clearance_radius > 0.0 and not TrackBuilderCore._inside_polygon_with_radius(candidate, clearance_radius, room_polygon):
			continue
		if not TrackBuilderCore._clear_of_points(candidate, gate_samples, 82.0 + clearance_radius):
			continue
		if not TrackBuilderCore._clear_of_recovery_lanes(candidate, maxf(18.0, clearance_radius), centerline, gate_samples):
			continue
		if not TrackBuilderCore._clear_of_occupied(candidate, maxf(18.0, clearance_radius), occupied):
			continue
		if is_flat:
			var spr := Sprite2D.new()
			spr.name = "EdgeDecor%03d" % placed
			spr.texture = tex
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			spr.position = candidate
			spr.rotation = rotation
			spr.scale = Vector2.ONE * sprite_scale
			spr.modulate = Color(1.0, 1.0, 1.0, alpha)
			spr.z_index = -14
			spr.set_meta("moment_kind", &"edge_decor")
			TrackBuilderCore._mark_flat_visual(spr, tex_path, &"floor_detail")
			container.add_child(spr)
		else:
			var body := StaticBody2D.new()
			body.name = "EdgeDecor%03d" % placed
			body.position = candidate
			body.rotation = rotation
			body.collision_layer = 16
			body.z_index = -14
			body.set_meta("moment_kind", &"edge_decor")
			body.set_meta("placement_clearance_radius", clearance_radius)
			TrackBuilderCore._mark_solid_body(body, tex_path, &"apron_prop")
			container.add_child(body)
			var offset := TrackBuilderCore._add_scaled_texture_collision(body, tex, sprite_scale, shape_kind)
			var spr := Sprite2D.new()
			spr.name = "Sprite"
			spr.texture = tex
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			spr.scale = Vector2.ONE * sprite_scale
			spr.position = -offset
			spr.modulate = Color.WHITE
			TrackBuilderCore._mark_solid_visual(spr, tex_path, &"apron_prop")
			body.add_child(spr)
			TrackBuilderCore._add_directional_shadow(spr)
		placed += 1
		if placed >= target:
			break
	# Existing colliding props carry unified directional shadows at construction.
	container.set_meta("placed_count", placed)


static func build_giant_landmarks(
		parent: Node2D,
		spec: Dictionary,
		centerline: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary],
		committed_racing_lines: Array[PackedVector2Array] = [],
		stage: Callable = Callable()
) -> void:
	var giants: Array = spec.get("giants", [])
	if giants.is_empty():
		return
	var container := Node2D.new()
	container.name = "GiantLandmarks"
	container.set_meta("moment_kind", &"giant")
	parent.add_child(container)
	var rng := RandomNumberGenerator.new()
	rng.seed = TrackBuilderCore._mix_seed(int(spec.get("dressing_seed", spec.get("requested_seed", 0))), "giants:%s" % String(spec.get("story_id", "")))
	var target := rng.randi_range(1, 3)
	var placed := 0
	var used_assets := {}
	# Prefer near curves in the outer apron, but scan the complete room for a
	# safe fallback so compact and concave canvases still receive a landmark.
	var corners := PackedInt32Array()
	for i in range(0, centerline.size(), 22):
		corners.append(i)
	for gi in target:
		var tex_path := ""
		var tex: Texture2D
		var desired_size := 0.0
		var world_shape_size := Vector2.ZERO
		var used_rect := Rect2()
		var sprite_scale := 1.0
		var visual_center_offset := Vector2.ZERO
		var local_footprint_rotation := 0.0
		var placement := {}
		var footprint := {}
		var asset_offset := rng.randi_range(0, giants.size() - 1)
		var pref_idx := corners[rng.randi() % corners.size()]
		for asset_attempt in giants.size():
			if stage.is_valid():
				await stage.call("Placing landmarks")
			tex_path = String(giants[(asset_offset + asset_attempt) % giants.size()])
			if bool(spec.get("distinct_giant_assets", false)) and used_assets.has(tex_path):
				continue
			tex = TrackBuilderCore.asset_texture(tex_path)
			if tex == null:
				continue
			var shape_entry: Dictionary = TrackBuilderCore.PROP_SHAPES.get(tex_path.get_file(), {})
			if not bool(shape_entry.get("solid", false)):
				push_error("TrackBuilderCore: giant roster contains an asset without a SOLID contract: %s" % tex_path)
				continue
			used_rect = TrackBuilderCore._texture_opaque_rect(tex)
			footprint = TrackBuilderCore._texture_collision_footprint(tex, StringName(shape_entry.get("shape", &"rect")))
			var footprint_size: Vector2 = footprint["size"]
			desired_size = TrackBuilderCore.PROP_SCALE.length_for(tex_path, TrackBuilderCore._prop_visual_size(tex_path, 300.0))
			sprite_scale = desired_size / maxf(footprint_size.x, footprint_size.y)
			visual_center_offset = ((footprint["center"] as Vector2) - Vector2(tex.get_width(), tex.get_height()) * 0.5) * sprite_scale
			world_shape_size = footprint_size * sprite_scale
			local_footprint_rotation = float(footprint["rotation"])
			placement = TrackBuilderCore._best_giant_position(pref_idx, world_shape_size, StringName(footprint["kind"]), local_footprint_rotation, room_polygon, centerline, gate_samples, occupied, committed_racing_lines)
			if bool(placement.get("found", false)):
				break
		if not bool(placement.get("found", false)) or tex == null:
			continue
		var footprint_radius := world_shape_size.length() * 0.5
		var pos: Vector2 = placement["position"]
		var landmark := Node2D.new()
		landmark.name = "GiantLandmark%02d" % placed
		landmark.position = pos
		landmark.rotation = float(placement["rotation"])
		landmark.z_index = -4
		landmark.set_meta("asset_path", tex_path)
		landmark.set_meta("moment_kind", &"giant")
		landmark.set_meta("world_size", desired_size)
		landmark.set_meta("footprint_size", world_shape_size)
		landmark.set_meta("footprint_kind", StringName(footprint["kind"]))
		landmark.set_meta("footprint_radius", footprint_radius)
		landmark.set_meta("colliding", true)
		landmark.set_meta("collision_contract", TrackBuilderCore.COLLISION_SOLID)
		TrackBuilderCore.VISUAL_ROLE_CONTRACT.assign(landmark, TrackBuilderCore.VISUAL_ROLE_SOLID)
		landmark.set_meta("visual_opaque_rect", used_rect)
		landmark.set_meta("footprint_rotation", local_footprint_rotation)
		container.add_child(landmark)
		used_assets[tex_path] = true
		var spr := Sprite2D.new()
		spr.name = "Sprite"
		spr.texture = tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		spr.position = -visual_center_offset
		spr.scale = Vector2.ONE * sprite_scale
		TrackBuilderCore._mark_solid_visual(spr, tex_path, &"giant")
		landmark.add_child(spr)
		TrackBuilderCore._add_directional_shadow(spr, true)
		var body := StaticBody2D.new()
		body.name = "GiantBody"
		body.collision_layer = 4 | 16
		TrackBuilderCore._mark_solid_body(body, tex_path, &"giant")
		landmark.add_child(body)
		var _offset := TrackBuilderCore._add_giant_collision(body, tex_path, sprite_scale)
		occupied.append({"position": pos, "radius": footprint_radius})
		placed += 1
	container.set_meta("placed_count", placed)


static func room_dressing_assets(story: Dictionary, spec: Dictionary, reserved_unique_assets: Dictionary) -> Array[String]:
	var assets: Array[String] = []
	for asset_path: String in spec.get("ambient_props", []):
		if not reserved_unique_assets.has(asset_path) and asset_path not in assets:
			assets.append(asset_path)
	for formation: Dictionary in story["island"]:
		var asset_path := String(formation["asset"])
		if StringName(formation["quantity"]) != &"unique" and asset_path not in assets:
			assets.append(asset_path)
	for field: String in ["object_line", "delimiter"]:
		var asset_path := String(story[field]["asset"])
		if asset_path not in assets:
			assets.append(asset_path)
	return TrackBuilderCore.PROP_SCALE.small_assets(assets)


static func room_dressing_anchors(
		room_polygon: PackedVector2Array,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary],
		target_count: int,
		rng: RandomNumberGenerator
) -> PackedVector2Array:
	var bounds := polygon_bounds_rect(room_polygon)
	var candidates: Array[Dictionary] = []
	for x in 17:
		for y in 11:
			var candidate := bounds.position + Vector2(
				bounds.size.x * (float(x) + 0.5) / 17.0,
				bounds.size.y * (float(y) + 0.5) / 11.0
			)
			if not TrackBuilderCore._trackside_placement_is_safe(candidate, 47.0, room_polygon, centerline, gate_samples, occupied):
				continue
			var occupied_clearance := 260.0
			for entry: Dictionary in occupied:
				occupied_clearance = minf(occupied_clearance, candidate.distance_to(entry["position"]) - float(entry["radius"]))
			var score := minf(TrackBuilderCore._distance_to_centerline(candidate, centerline), 360.0)
			score += minf(occupied_clearance, 260.0) * 0.65
			score += rng.randf_range(0.0, 18.0)
			candidates.append({
				"position": candidate,
				"score": score,
				"sector": Vector2i(clampi(int(float(x) / 17.0 * 3.0), 0, 2), clampi(int(float(y) / 11.0 * 2.0), 0, 1)),
			})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["score"]) > float(b["score"]))
	var anchors := PackedVector2Array()
	var occupied_sectors := {}
	# First claim the best blank pocket in each coarse room sector. A second pass
	# fills any remaining slots without forcing unsafe scenery into tight rooms.
	for candidate_data: Dictionary in candidates:
		var sector: Vector2i = candidate_data["sector"]
		if occupied_sectors.has(sector):
			continue
		var candidate: Vector2 = candidate_data["position"]
		if not TrackBuilderCore._clear_of_points(candidate, anchors, 210.0):
			continue
		anchors.append(candidate)
		occupied_sectors[sector] = true
		if anchors.size() >= target_count:
			break
	if anchors.size() < target_count:
		for candidate_data: Dictionary in candidates:
			var candidate: Vector2 = candidate_data["position"]
			if not TrackBuilderCore._clear_of_points(candidate, anchors, 210.0):
				continue
			anchors.append(candidate)
			if anchors.size() >= target_count:
				break
	return anchors


static func build_room_ground_sections(
		parent: Node2D,
		story: Dictionary,
		spec: Dictionary,
		centerline: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		stage: Callable = Callable()
) -> int:
	var definitions: Array = spec.get("ground_sections", [])
	if definitions.is_empty():
		return 0
	var sections := Node2D.new()
	sections.name = "GroundSections"
	sections.set_meta("moment_kind", &"ambient_ground")
	parent.add_child(sections)
	var rng := RandomNumberGenerator.new()
	rng.seed = TrackBuilderCore._mix_seed(int(spec.get("material_seed", spec["requested_seed"])), "ground_sections:%s" % String(story["id"]))
	var room_area := absf(TrackBuilderCore._polygon_area(room_polygon))
	var target_count := mini(clampi(int(round(room_area / 750000.0)), 2, 4), definitions.size())
	sections.set_meta("requested_count", target_count)
	var bounds := polygon_bounds_rect(room_polygon)
	var placements: Array[Dictionary] = []
	var occupied_sectors := {}
	var asset_offset := rng.randi_range(0, definitions.size() - 1)
	for section_index in target_count:
		if stage.is_valid():
			await stage.call("Laying room materials")
		var definition: Dictionary = definitions[(asset_offset + section_index) % definitions.size()]
		var asset_path := String(definition["asset"])
		var texture := TrackBuilderCore.asset_texture(asset_path)
		if texture == null:
			continue
		var visible_bounds := TrackBuilderCore._texture_opaque_rect(texture)
		var source_size := texture.get_size()
		var source_radius := visible_bounds.size.length() * 0.5 + visible_bounds.get_center().distance_to(source_size * 0.5)
		var base_world_size := TrackBuilderCore.PROP_SCALE.length_for(asset_path, float(definition.get("size", 240.0)))
		var alpha := float(definition.get("alpha", 0.94))
		var last_yield := Time.get_ticks_usec()
		for attempt in 520:
			if stage.is_valid() and Time.get_ticks_usec() - last_yield >= 6000:
				await stage.call("Laying room materials")
				last_yield = Time.get_ticks_usec()
			var world_size := base_world_size
			var sprite_scale := TrackBuilderCore.PROP_SCALE.sprite_scale(texture, visible_bounds, world_size)
			var footprint_radius := source_radius * sprite_scale
			var candidate := Vector2(
				rng.randf_range(bounds.position.x, bounds.end.x),
				rng.randf_range(bounds.position.y, bounds.end.y)
			)
			if Geometry2D.is_point_in_polygon(candidate, outer_loop):
				continue
			if not TrackBuilderCore._inside_polygon_with_radius(candidate, footprint_radius, room_polygon):
				continue
			if TrackBuilderCore._distance_to_centerline(candidate, centerline) < TrackBuilderCore.HALF_WIDTH + footprint_radius + TrackBuilderCore.FLAT_DRESSING_ROUTE_CLEARANCE:
				continue
			var normalized: Vector2 = (candidate - bounds.position) / bounds.size
			var sector := Vector2i(clampi(int(normalized.x * 3.0), 0, 2), clampi(int(normalized.y * 2.0), 0, 1))
			if attempt < 300 and occupied_sectors.has(sector):
				continue
			var clear := true
			for placement: Dictionary in placements:
				if candidate.distance_to(placement["position"]) < (footprint_radius + float(placement["radius"])) * 0.72:
					clear = false
					break
			if not clear:
				continue
			var sprite := Sprite2D.new()
			sprite.name = "Section%02d" % placements.size()
			sprite.texture = texture
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			sprite.position = candidate
			sprite.rotation = rng.randf_range(-PI, PI)
			sprite.scale = Vector2.ONE * sprite_scale
			sprite.modulate = Color(1.0, 1.0, 1.0, alpha)
			sprite.z_index = -17
			sprite.set_meta("asset_path", asset_path)
			sprite.set_meta("moment_kind", &"ambient_ground")
			sprite.set_meta("world_size", world_size)
			sprite.set_meta("footprint_radius", footprint_radius)
			TrackBuilderCore._mark_flat_visual(sprite, asset_path, &"ground_dressing")
			sections.add_child(sprite)
			placements.append({"position": candidate, "radius": footprint_radius})
			occupied_sectors[sector] = true
			break
	sections.set_meta("placed_count", placements.size())
	return placements.size()


static func build_room_floor_details(
		parent: Node2D,
		spec: Dictionary,
		centerline: PackedVector2Array,
		room_polygon: PackedVector2Array,
		occupied: Array[Dictionary],
		rng: RandomNumberGenerator
) -> int:
	var decals: Array = spec.get("decals", [])
	if decals.is_empty():
		return 0
	var details := Node2D.new()
	details.name = "FloorDetails"
	parent.add_child(details)
	var bounds := polygon_bounds_rect(room_polygon)
	var target_count := clampi(int(round(absf(TrackBuilderCore._polygon_area(room_polygon)) / 90000.0)), 18, 30)
	var positions := PackedVector2Array()
	for attempt in 820:
		var candidate := Vector2(
			rng.randf_range(bounds.position.x, bounds.end.x),
			rng.randf_range(bounds.position.y, bounds.end.y)
		)
		if not TrackBuilderCore._inside_polygon_with_radius(candidate, 18.0, room_polygon):
			continue
		if TrackBuilderCore._distance_to_centerline(candidate, centerline) < TrackBuilderCore.HALF_WIDTH + 18.0:
			continue
		if not TrackBuilderCore._clear_of_points(candidate, positions, 46.0):
			continue
		var texture_path := String(decals[rng.randi_range(0, decals.size() - 1)])
		var texture := TrackBuilderCore.asset_texture(texture_path)
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.name = "Detail%02d" % positions.size()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.position = candidate
		sprite.rotation = rng.randf_range(0.0, TAU)
		var longest := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (rng.randf_range(32.0, 68.0) / maxf(longest, 1.0))
		sprite.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(0.32, 0.68))
		sprite.z_index = -15
		sprite.set_meta("asset_path", texture_path)
		sprite.set_meta("moment_kind", &"ambient_decal")
		TrackBuilderCore._mark_flat_visual(sprite, texture_path, &"floor_decal")
		details.add_child(sprite)
		positions.append(candidate)
		if positions.size() >= target_count:
			break
	details.set_meta("placed_count", positions.size())
	return positions.size()


static func build_generated_surfaces(root: Node2D, parent: Node2D, story: Dictionary, spec: Dictionary, moments: Dictionary, centerline: PackedVector2Array, gate_samples: PackedVector2Array, emit_decals: bool = true) -> void:
	var definitions: Array[Dictionary] = []
	var surfaces: Array = story["surfaces"]

	var shortcut_surface_index := 0 if float((surfaces[0] as Dictionary)["grip"]) <= float((surfaces[1] as Dictionary)["grip"]) else 1
	var technical_surface_index := 1 - shortcut_surface_index
	var technical_data: Dictionary = surfaces[technical_surface_index]
	# The technical surface sits on a calm stretch picked by the moments; a lap
	# without one skips it rather than putting a slippery strip in a corner.
	var technical_index := int(moments["technical"])
	if technical_index >= 0:
		var technical_polygon := surface_strip(centerline, technical_index, TECHNICAL_HALF_SPAN, 92.0)
		var technical_definition := {
			"name": StringName(technical_data["name"]),
			"role": &"technical",
			"lane": &"full",
			"grip": float(technical_data["grip"]),
			"speed": float(technical_data["speed"]),
			"points": technical_polygon,
			"decal": String(technical_data["decal"]),
			"centerline_index": technical_index,
		}
		definitions.append(technical_definition)
		var technical := Node2D.new()
		technical.name = "TechnicalSurfaceMoment"
		technical.set_meta("moment_kind", &"technical")
		technical.set_meta("surface_name", technical_definition["name"])
		technical.set_meta("grip", technical_definition["grip"])
		technical.set_meta("speed", technical_definition["speed"])
		technical.set_meta("polygon", technical_polygon)
		technical.set_meta("decal_texture", technical_definition["decal"])
		technical.set_meta("centerline_index", technical_index)
		parent.add_child(technical)
		if emit_decals:
			add_surface_decals(technical, centerline, technical_index, TECHNICAL_HALF_SPAN, String(technical_data["decal"]))

	var shortcut_data: Dictionary = surfaces[shortcut_surface_index]
	var shortcut_index := int(moments["shortcut"])
	var shortcut_geometry := shortcut_lane_geometry(centerline, shortcut_index)
	var shortcut_path: PackedVector2Array = shortcut_geometry["shortcut_path"]
	var safe_path: PackedVector2Array = shortcut_geometry["safe_path"]
	var shortcut_polygon := lane_strip(shortcut_path, TrackBuilderCore.SHORTCUT_LANE_HALF_WIDTH)
	var shortcut_definition := {
		"name": StringName(shortcut_data["name"]),
		"role": &"shortcut",
		"lane": &"inside",
		"grip": float(shortcut_data["grip"]),
		"speed": maxf(float(shortcut_data["speed"]), 1.06),
		"points": shortcut_polygon,
		"decal": String(shortcut_data["decal"]),
		"centerline_index": shortcut_index,
		"inside_sign": float(shortcut_geometry["inside_sign"]),
		"ai_path_clear": true,
	}
	definitions.append(shortcut_definition)
	var shortcut := Node2D.new()
	shortcut.name = "ShortcutDecision"
	shortcut.set_meta("moment_kind", &"shortcut")
	shortcut.set_meta("surface_name", shortcut_definition["name"])
	shortcut.set_meta("grip", shortcut_definition["grip"])
	shortcut.set_meta("speed", shortcut_definition["speed"])
	shortcut.set_meta("polygon", shortcut_polygon)
	shortcut.set_meta("decal_texture", shortcut_definition["decal"])
	shortcut.set_meta("centerline_index", shortcut_index)
	shortcut.set_meta("inside_sign", shortcut_definition["inside_sign"])
	shortcut.set_meta("ai_path_clear", shortcut_definition["ai_path_clear"])
	shortcut.set_meta("shortcut_path", shortcut_path)
	shortcut.set_meta("safe_path", safe_path)
	shortcut.set_meta("shortcut_length", float(shortcut_geometry["shortcut_length"]))
	shortcut.set_meta("safe_length", float(shortcut_geometry["safe_length"]))
	parent.add_child(shortcut)
	if emit_decals:
		add_surface_decals(shortcut, centerline, shortcut_index, TrackBuilderCore.SHORTCUT_HALF_SPAN, String(shortcut_data["decal"]), float(shortcut_geometry["inside_sign"]) * TrackBuilderCore.SHORTCUT_LANE_OFFSET)

	# Additional in-corridor grip patches are data for TrackVariantPresenter,
	# which creates the authoritative SurfaceZone nodes at runtime. They only go
	# on calm stretches (see TrackCornerMap), separated from gates, the grids and
	# the two designed surface moments; a lap short of calm room gets fewer.
	var extra_patches: Array = spec.get("grip_patches", [])
	var calm_patch_centres := TrackCornerMap.calm_indices(moments["corner_clearance"], GRIP_PATCH_MIN_HALF_SPAN)
	if extra_patches.size() > 0 and not calm_patch_centres.is_empty():
		var patch_rng := RandomNumberGenerator.new()
		patch_rng.seed = TrackBuilderCore._mix_seed(int(spec.get("material_seed", spec.get("requested_seed", 0))), "grip_patches:%s" % String(story.get("id", "")))
		var target_count := patch_rng.randi_range(TrackBuilderCore.GRIP_PATCH_MIN_COUNT, TrackBuilderCore.GRIP_PATCH_MAX_COUNT)
		var used_indices := PackedInt32Array([technical_index, shortcut_index])
		var added := 0
		for attempt in 240:
			if added >= target_count:
				break
			var pidx_center := calm_patch_centres[patch_rng.randi_range(0, calm_patch_centres.size() - 1)]
			if TrackBuilderCore._cyclic_index_distance(pidx_center, 0, centerline.size()) < SURFACE_START_CLEARANCE:
				continue
			var separated := true
			for used_index: int in used_indices:
				if used_index >= 0 and TrackBuilderCore._cyclic_index_distance(pidx_center, used_index, centerline.size()) < SURFACE_SEPARATION:
					separated = false
					break
			if not separated or not TrackBuilderCore._clear_of_points(centerline[pidx_center], gate_samples, SURFACE_GATE_CLEARANCE):
				continue
			var half_span := patch_rng.randi_range(GRIP_PATCH_MIN_HALF_SPAN, GRIP_PATCH_MAX_HALF_SPAN)
			if not TrackCornerMap.is_calm(moments["corner_clearance"], pidx_center, half_span):
				continue
			var data: Dictionary = extra_patches[added % extra_patches.size()]
			var halfw := patch_rng.randf_range(GRIP_PATCH_MIN_HALF_WIDTH, GRIP_PATCH_MAX_HALF_WIDTH)
			# Debris is not a centre stripe: each patch sits somewhere across the
			# road, either side, and only sometimes near the racing line.
			var room := maxf(0.0, TrackBuilderCore.HALF_WIDTH - halfw - GRIP_PATCH_EDGE_MARGIN)
			var lateral := (-1.0 if patch_rng.randi() % 2 == 0 else 1.0) * patch_rng.randf_range(0.15, 1.0) * room
			var shifted := offset_centerline(centerline, lateral)
			var poly := surface_strip(shifted, pidx_center, half_span, halfw)
			var patch_node := Node2D.new()
			patch_node.name = "ExtraGripPatch%d" % added
			patch_node.set_meta("moment_kind", &"grip_patch")
			patch_node.set_meta("surface_name", StringName(data["name"]))
			patch_node.set_meta("grip", float(data["grip"]))
			patch_node.set_meta("speed", float(data.get("speed", data["grip"])))
			patch_node.set_meta("polygon", poly)
			patch_node.set_meta("lateral_mm", lateral)
			patch_node.set_meta("half_span", half_span)
			patch_node.set_meta("decal_texture", String(data["decal"]))
			parent.add_child(patch_node)
			if emit_decals:
				add_surface_decals(patch_node, centerline, pidx_center, half_span, String(data["decal"]), lateral)
			var def := {
				"name": StringName(data["name"]),
				"role": &"patch",
				"lane": &"mixed",
				"grip": float(data["grip"]),
				"speed": float(data.get("speed", data["grip"])),
				"points": poly,
				"decal": String(data["decal"]),
				"centerline_index": pidx_center,
				"lateral_mm": lateral,
				"half_span": half_span,
			}
			definitions.append(def)
			used_indices.append(pidx_center)
			added += 1
		parent.set_meta("grip_patch_count", added)
	root.set_meta("generated_surfaces", definitions)


## Every point of the racing line moved sideways, so a strip built from it lies
## off-centre like real debris instead of tracing the driving line.
static func offset_centerline(centerline: PackedVector2Array, lateral: float) -> PackedVector2Array:
	if is_zero_approx(lateral):
		return centerline
	var shifted := PackedVector2Array()
	shifted.resize(centerline.size())
	for index in centerline.size():
		shifted[index] = centerline[index] + TrackBuilderCore._sample_tangent(centerline, index).rotated(PI * 0.5) * lateral
	return shifted


static func surface_strip(centerline: PackedVector2Array, center_index: int, half_span: int, half_width: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for offset in range(-half_span, half_span + 1, 2):
		var index := posmod(center_index + offset, centerline.size())
		var normal := TrackBuilderCore._sample_tangent(centerline, index).rotated(PI * 0.5)
		left.append(centerline[index] + normal * half_width)
		right.append(centerline[index] - normal * half_width)
	var polygon := PackedVector2Array()
	polygon.append_array(left)
	for index in range(right.size() - 1, -1, -1):
		polygon.append(right[index])
	var hull := Geometry2D.convex_hull(polygon)
	if hull.size() > 2 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.resize(hull.size() - 1)
	return hull


static func add_surface_decals(
		parent: Node2D,
		centerline: PackedVector2Array,
		center_index: int,
		half_span: int,
		texture_path: String,
		lateral_offset: float = 0.0
) -> void:
	var asset := WorldEnvironmentCatalog.for_path(texture_path)
	if asset.is_empty():
		return
	var polygon: PackedVector2Array = parent.get_meta("polygon", PackedVector2Array())
	if polygon.is_empty():
		var path := centerline.duplicate()
		for index in path.size():
			path[index] += TrackBuilderCore._sample_tangent(centerline, index).rotated(PI * 0.5) * lateral_offset
		polygon = surface_strip(path, center_index, half_span, TrackBuilderCore.HALF_WIDTH)
	WorldEnvironmentArt._draw_grip_surface(parent, "SurfaceRegion", asset, polygon, center_index)


static func shortcut_lane_geometry(centerline: PackedVector2Array, center_index: int) -> Dictionary:
	var positive := offset_section_path(centerline, center_index, TrackBuilderCore.SHORTCUT_HALF_SPAN, TrackBuilderCore.SHORTCUT_LANE_OFFSET)
	var negative := offset_section_path(centerline, center_index, TrackBuilderCore.SHORTCUT_HALF_SPAN, -TrackBuilderCore.SHORTCUT_LANE_OFFSET)
	var positive_length := open_path_length(positive)
	var negative_length := open_path_length(negative)
	if positive_length <= negative_length:
		return {
			"inside_sign": 1.0,
			"shortcut_path": positive,
			"safe_path": negative,
			"shortcut_length": positive_length,
			"safe_length": negative_length,
		}
	return {
		"inside_sign": -1.0,
		"shortcut_path": negative,
		"safe_path": positive,
		"shortcut_length": negative_length,
		"safe_length": positive_length,
	}


static func offset_section_path(
		centerline: PackedVector2Array,
		center_index: int,
		half_span: int,
		lateral_offset: float
) -> PackedVector2Array:
	var path := PackedVector2Array()
	for offset in range(-half_span, half_span + 1):
		var index := posmod(center_index + offset, centerline.size())
		var normal := TrackBuilderCore._sample_tangent(centerline, index).rotated(PI * 0.5)
		path.append(centerline[index] + normal * lateral_offset)
	return path


static func lane_strip(path: PackedVector2Array, half_width: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for index in path.size():
		var before := path[maxi(index - 1, 0)]
		var after := path[mini(index + 1, path.size() - 1)]
		var normal := before.direction_to(after).rotated(PI * 0.5)
		left.append(path[index] + normal * half_width)
		right.append(path[index] - normal * half_width)
	var polygon := PackedVector2Array()
	polygon.append_array(left)
	for index in range(right.size() - 1, -1, -1):
		polygon.append(right[index])
	var hull := Geometry2D.convex_hull(polygon)
	if hull.size() > 2 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.resize(hull.size() - 1)
	return hull


static func open_path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(1, path.size()):
		total += path[index - 1].distance_to(path[index])
	return total



static func build_finish_moments(parent: Node2D, centerline: PackedVector2Array) -> void:
	var forward_path := PackedVector2Array()
	var reverse_path := PackedVector2Array()
	for offset in range(-TrackBuilderCore.FINISH_APPROACH_SPAN, 1):
		forward_path.append(centerline[posmod(offset, centerline.size())])
	for offset in range(TrackBuilderCore.FINISH_APPROACH_SPAN, -1, -1):
		reverse_path.append(centerline[posmod(offset, centerline.size())])

	var speed := Node2D.new()
	speed.name = "SpeedSection"
	speed.position = centerline[0]
	speed.set_meta("moment_kind", &"speed")
	speed.set_meta("centerline_index", 0)
	speed.set_meta("forward_path", forward_path)
	speed.set_meta("reverse_path", reverse_path)
	speed.set_meta("forward_length", open_path_length(forward_path))
	speed.set_meta("reverse_length", open_path_length(reverse_path))
	speed.set_meta("reserved_clear", true)
	parent.add_child(speed)

	var finish := Node2D.new()
	finish.name = "DramaticFinish"
	finish.position = centerline[0]
	finish.set_meta("moment_kind", &"finish")
	finish.set_meta("centerline_index", 0)
	finish.set_meta("forward_approach", forward_path)
	finish.set_meta("reverse_approach", reverse_path)
	finish.set_meta("finish_gate", NodePath("../../Checkpoint0Finish"))
	finish.set_meta("checker_white", NodePath("../../StartFinishWhite"))
	finish.set_meta("checker_black", NodePath("../../StartFinishBlack"))
	finish.set_meta("finish_landmark_left", NodePath("../../GatePosts/Gate00Left"))
	finish.set_meta("finish_landmark_right", NodePath("../../GatePosts/Gate00Right"))
	finish.set_meta("corridor_span", TrackBuilderCore.HALF_WIDTH * 2.0)
	finish.set_meta("bidirectional_landmarks", true)
	parent.add_child(finish)
