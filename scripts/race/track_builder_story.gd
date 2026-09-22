class_name TrackBuilderStory
## Generated story dressing: moment container, island focal cluster.


static func compose_generated_story(
		root: Node2D,
		spec: Dictionary,
		centerline: PackedVector2Array,
		inner_loop: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		moments: Dictionary,
		stage: Callable = Callable(),
		room_model: Dictionary = {}
) -> void:
	var story: Dictionary = spec["story_kit"]
	var container := Node2D.new()
	container.name = "GeneratedMoments"
	container.set_meta("story_id", StringName(story["id"]))
	root.add_child(container)

	var occupied: Array[Dictionary] = []
	var reserved_unique_assets := {}
	for formation_data: Dictionary in story["island"]:
		if StringName(formation_data["quantity"]) == &"unique":
			reserved_unique_assets[String(formation_data["asset"])] = true
	var committed_racing_lines: Array[PackedVector2Array] = []
	for line_name: String in ["RacingLine", "ShortcutRacingLine"]:
		var line := root.get_node_or_null(line_name) as Line2D
		if line and not line.points.is_empty():
			committed_racing_lines.append(line.points)
	var giant_spec := spec.duplicate()
	var giant_assets: Array[String] = []
	for path: String in story.get("giants", spec.get("giants", [])):
		if not reserved_unique_assets.has(path):
			giant_assets.append(path)
	giant_spec["giants"] = giant_assets
	await TrackBuilderCore._build_giant_landmarks(container, giant_spec, centerline, room_polygon, gate_samples, occupied, committed_racing_lines, stage)
	if stage.is_valid():
		await stage.call("Dressing the start area")
	var opening_index := TrackBuilderCore._build_opening_landmark(
		container,
		story,
		spec,
		centerline,
		outer_loop,
		room_polygon,
		gate_samples,
		occupied
	)
	var opening := container.get_node("OpeningLandmark")
	if int(opening.get_meta("placed_count", 0)) == 1:
		reserved_unique_assets[String(opening.get_meta("asset_path", ""))] = true
	await build_island_story(container, story, spec, centerline, inner_loop, room_polygon, gate_samples, occupied, stage, room_model)
	if stage.is_valid():
		await stage.call("Placing track objects")
	TrackBuilderCore._build_track_formation(
		container,
		"ObjectLine",
		story["object_line"],
		&"many",
		int(moments["longest_straight"]),
		centerline,
		outer_loop,
		room_polygon,
		gate_samples,
		occupied
	)
	TrackBuilderCore._build_track_formation(
		container,
		"SparseDelimiter",
		story["delimiter"],
		&"few",
		int(moments["early_conflict_forward"]),
		centerline,
		outer_loop,
		room_polygon,
		gate_samples,
		occupied
	)
	TrackBuilderCore._build_corner_landmarks(container, story, spec, moments["corners"], centerline, outer_loop, room_polygon, gate_samples, reserved_unique_assets, occupied)
	if stage.is_valid():
		await stage.call("Dressing the room")
	await TrackBuilderCore._build_room_dressing(container, story, spec, centerline, outer_loop, room_polygon, gate_samples, reserved_unique_assets, occupied, stage)
	if stage.is_valid():
		await stage.call("Adding surface detail")
	await TrackBuilderCore._build_edge_and_apron_decor(container, spec, centerline, room_polygon, gate_samples, occupied, stage)
	if stage.is_valid():
		await stage.call("Preparing grip zones and hazards")
	TrackBuilderCore._build_generated_surfaces(root, container, story, spec, moments, centerline, gate_samples)
	TrackBuilderCore._build_finish_moments(container, centerline)

	var hazard_paths := {}
	var planned_hazard: Dictionary = spec.get("hazard_plan", {})
	var planned_paths: Dictionary = planned_hazard.get("paths", {})
	for direction: String in ["forward", "reverse"]:
		var hazard_index := int(moments["early_conflict_%s" % direction])
		var hazard_path: PackedVector2Array = planned_paths.get(direction, TrackBuilderCore._crossing_path(centerline, hazard_index, 96.0))
		var conflict := Node2D.new()
		conflict.name = "EarlyConflict%s" % direction.capitalize()
		conflict.position = centerline[hazard_index]
		conflict.set_meta("moment_kind", &"early_conflict")
		conflict.set_meta("direction", StringName(direction))
		conflict.set_meta("centerline_index", hazard_index)
		conflict.set_meta("lap_fraction", float(moments["early_conflict_%s_fraction" % direction]))
		conflict.set_meta("path", hazard_path)
		container.add_child(conflict)
		hazard_paths[direction] = hazard_path
	root.set_meta("generated_hazard_paths", hazard_paths)
	root.set_meta("generated_hazard_path", hazard_paths["forward"])
	root.set_meta("generated_moment_indices", {
		"opening": opening_index,
		"early_conflict_forward": int(moments["early_conflict_forward"]),
		"early_conflict_reverse": int(moments["early_conflict_reverse"]),
		"longest_straight": int(moments["longest_straight"]),
		"second_straight": int(moments["second_straight"]),
		"corners": moments["corners"],
		"shortcut": int(moments["shortcut"]),
		"technical": int(moments["technical"]),
		"speed": 0,
		"finish": 0,
		"hazard": int(moments["early_conflict_forward"]),
	})



static func build_island_story(
		parent: Node2D,
		story: Dictionary,
		spec: Dictionary,
		centerline: PackedVector2Array,
		inner_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary],
		stage: Callable = Callable(),
		room_model: Dictionary = {}
) -> void:
	var cluster := Node2D.new()
	cluster.name = "IslandFocalCluster"
	cluster.set_meta("story_id", StringName(story["id"]))
	parent.add_child(cluster)
	var anchor := TrackBuilderCore._island_anchor(inner_loop, centerline)
	var island_bounds := TrackBuilderCore._polygon_bounds_rect(inner_loop)
	var scene_angle := -PI * 0.5 if island_bounds.size.x > island_bounds.size.y else 0.0
	if TrackBuilderCore._mix_seed(int(spec.get("dressing_seed", spec["requested_seed"])), String(story["id"])) % 2 == 1:
		scene_angle += PI
	var placement_region := &"island"
	var focal_data: Dictionary = story["island"][0]
	var focal_path := String(focal_data["asset"])
	var focal_base_radius := TrackBuilderCore._asset_radius(focal_path, 24.0)
	var focal_scale := minf(1.0, float(focal_data.get("max_radius", 72.0)) / maxf(focal_base_radius, 1.0))
	var focal_radius := focal_base_radius * focal_scale
	var focal_offset: Vector2 = focal_data.get("offset", Vector2.ZERO)
	var focal_preferred := anchor + focal_offset.rotated(scene_angle)
	var island_fit := TrackBuilderPlacement.best_island_position(focal_preferred, focal_radius, room_polygon, inner_loop, occupied, room_model)
	if not bool(island_fit["found"]):
		var apron_fit := TrackBuilderPlacement.best_offtrack_position(focal_preferred, focal_radius, room_polygon, centerline, gate_samples, occupied, room_model)
		if bool(apron_fit["found"]):
			placement_region = &"apron"
			anchor += (apron_fit["position"] as Vector2) - focal_preferred
	cluster.set_meta("placement_region", placement_region)
	for formation_data: Dictionary in story["island"]:
		if stage.is_valid():
			await stage.call("Dressing the start area")
		var quantity := StringName(formation_data["quantity"])
		var requested_count := TrackBuilderCore._bounded_quantity_count(quantity, int(formation_data["count"]))
		var formation := Node2D.new()
		formation.name = "Formation%s" % String(quantity).to_pascal_case()
		formation.set_meta("semantic_quantity", quantity)
		formation.set_meta("requested_count", requested_count)
		formation.set_meta("asset_path", String(formation_data["asset"]))
		cluster.add_child(formation)
		var asset_path := String(formation_data["asset"])
		var base_radius := TrackBuilderCore._asset_radius(asset_path, 24.0)
		var maximum_radius := 72.0 if quantity == &"unique" else (42.0 if quantity == &"few" else 18.0)
		maximum_radius = float(formation_data.get("max_radius", maximum_radius))
		var size_scale := minf(1.0, maximum_radius / maxf(base_radius, 1.0))
		var radius := base_radius * size_scale
		var authored_offset: Vector2 = formation_data.get("offset", Vector2.ZERO)
		var semantic_spread := 1.45 if quantity == &"many" else (1.65 if quantity == &"few" else 1.0)
		var target: Vector2 = anchor + (authored_offset * semantic_spread).rotated(scene_angle)
		var placed_count := 0
		for item_index in requested_count:
			var local_offset := TrackBuilderCore._semantic_formation_offset(StringName(formation_data["formation"]), item_index, requested_count, radius)
			var placed := false
			var preferred := target + local_offset.rotated(scene_angle)
			for attempt in 36:
				var fallback_distance := float((attempt + 3) / 4) * maxf(radius * 0.6, 20.0)
				var fallback_angle := scene_angle + float(attempt) * 2.399963 + float(item_index) * 0.41
				var fallback := Vector2.ZERO if attempt == 0 else Vector2.RIGHT.rotated(fallback_angle) * fallback_distance
				var candidate := preferred + fallback
				var safe := TrackBuilderPlacement.placement_is_safe(candidate, radius, room_polygon, inner_loop, occupied, room_model) if placement_region == &"island" else TrackBuilderPlacement.trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied, room_model)
				if not safe:
					continue
				TrackBuilderCore._add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, scene_angle + float(item_index) * 0.17, placement_region, quantity, item_index, size_scale)
				occupied.append({"position": candidate, "radius": radius})
				placed_count += 1
				placed = true
				break
			if not placed:
				var exhaustive := TrackBuilderPlacement.best_island_position(preferred, radius, room_polygon, inner_loop, occupied, room_model) if placement_region == &"island" else TrackBuilderPlacement.best_offtrack_position(preferred, radius, room_polygon, centerline, gate_samples, occupied, room_model)
				if bool(exhaustive["found"]):
					var candidate: Vector2 = exhaustive["position"]
					TrackBuilderCore._add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, scene_angle + float(item_index) * 0.17, placement_region, quantity, item_index, size_scale)
					occupied.append({"position": candidate, "radius": radius})
					placed_count += 1
					placed = true
			if not placed and placement_region == &"island":
				var apron_fit := TrackBuilderPlacement.best_offtrack_position(preferred, radius, room_polygon, centerline, gate_samples, occupied, room_model)
				if bool(apron_fit["found"]):
					var candidate: Vector2 = apron_fit["position"]
					TrackBuilderCore._add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, scene_angle + float(item_index) * 0.17, &"apron", quantity, item_index, size_scale)
					occupied.append({"position": candidate, "radius": radius})
					placed_count += 1
					placed = true
					cluster.set_meta("placement_region", &"mixed")
			if not placed and quantity == &"unique":
				# A concave infield can have no room for the authored oversized
				# focal. Keep the unique object readable rather than silently omit it.
				for factor: float in [0.85, 0.70, 0.55]:
					var fitted_radius := minf(radius, maxf(72.0, radius * factor))
					var fitted_scale := size_scale * fitted_radius / radius
					var fit := TrackBuilderPlacement.best_island_position(preferred, fitted_radius, room_polygon, inner_loop, occupied, room_model)
					var region := &"island"
					if not bool(fit["found"]):
						fit = TrackBuilderPlacement.best_offtrack_position(preferred, fitted_radius, room_polygon, centerline, gate_samples, occupied, room_model)
						region = &"apron"
					if bool(fit["found"]):
						TrackBuilderCore._add_generated_prop(formation, "Item%02d" % item_index, fit["position"], asset_path, scene_angle, region, quantity, item_index, fitted_scale)
						occupied.append({"position": fit["position"], "radius": fitted_radius})
						placed_count += 1
						placed = true
						cluster.set_meta("placement_region", &"mixed")
						break
				break
		formation.set_meta("placed_count", placed_count)

