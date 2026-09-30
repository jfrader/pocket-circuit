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
		stage: Callable = Callable()
) -> void:
	var story: Dictionary = spec["story_kit"]
	var container := Node2D.new()
	container.name = "GeneratedMoments"
	container.set_meta("story_id", StringName(story["id"]))
	root.add_child(container)

	var occupied: Array[Dictionary] = []
	for body: StaticBody2D in root.find_children("*", "StaticBody2D", true, false):
		var sprite := body.get_node_or_null("Sprite") as Sprite2D
		if sprite == null or sprite.texture == null:
			continue
		var size := TrackBuilderCore._texture_opaque_rect(sprite.texture).size * sprite.scale
		occupied.append({"position": root.to_local(body.global_position), "radius": size.length() * 0.5})
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
	await build_island_story(container, story, spec, centerline, inner_loop, room_polygon, gate_samples, occupied, stage)
	for formation: Node in container.get_node("IslandFocalCluster").get_children():
		if StringName(formation.get_meta("semantic_quantity", &"")) == &"unique":
			reserved_unique_assets[String(formation.get_meta("asset_path", ""))] = true
	if stage.is_valid():
		await stage.call("Placing track objects")
	await TrackBuilderCore._build_track_formation(
		container,
		"ObjectLine",
		story["object_line"],
		&"many",
		int(moments["longest_straight"]),
		centerline,
		outer_loop,
		room_polygon,
		gate_samples,
		occupied,
		stage
	)
	if stage.is_valid():
		await stage.call("Placing sparse delimiters")
	await TrackBuilderCore._build_track_formation(
		container,
		"SparseDelimiter",
		story["delimiter"],
		&"few",
		int(moments["second_straight"]),
		centerline,
		outer_loop,
		room_polygon,
		gate_samples,
		occupied,
		stage
	)
	if stage.is_valid():
		await stage.call("Placing corner landmarks")
	TrackBuilderCore._build_corner_landmarks(container, story, spec, moments["corners"], centerline, outer_loop, room_polygon, gate_samples, reserved_unique_assets, occupied)
	if stage.is_valid():
		await stage.call("Dressing the room")
	await TrackBuilderCore._build_room_dressing(container, story, spec, centerline, outer_loop, room_polygon, gate_samples, reserved_unique_assets, occupied, stage)
	if stage.is_valid():
		await stage.call("Adding surface detail")
	await TrackBuilderCore._build_edge_and_apron_decor(container, spec, centerline, room_polygon, gate_samples, occupied, stage)
	if stage.is_valid():
		await stage.call("Preparing grip zones")
	TrackBuilderCore._build_generated_surfaces(root, container, story, spec, moments, centerline, gate_samples)
	TrackBuilderCore._build_finish_moments(container, centerline)
	build_gameplay_moments(root, moments, opening_index)


static func build_gameplay_moments(root: Node2D, moments: Dictionary, opening_index: int) -> void:
	root.set_meta("generated_moment_indices", {
		"opening": opening_index,
		"longest_straight": int(moments["longest_straight"]),
		"second_straight": int(moments["second_straight"]),
		"corners": moments["corners"],
		"shortcut": int(moments["shortcut"]),
		"technical": int(moments["technical"]),
		"speed": 0,
		"finish": 0,
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
		stage: Callable = Callable()
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
	var focal_path := TrackBuilderCore._formation_assets(focal_data)[0]
	var focal_base_radius := TrackBuilderCore._asset_radius(focal_path, 24.0)
	var focal_radius := focal_base_radius
	var focal_offset: Vector2 = focal_data.get("offset", Vector2.ZERO)
	var focal_preferred := anchor + focal_offset.rotated(scene_angle)
	var island_fit := TrackBuilderCore._best_island_position(focal_preferred, focal_radius, room_polygon, inner_loop, occupied)
	if not bool(island_fit["found"]):
		var apron_fit := TrackBuilderCore._best_offtrack_position(focal_preferred, focal_radius, room_polygon, centerline, gate_samples, occupied)
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
		var asset_paths := TrackBuilderCore._formation_assets(formation_data)
		formation.set_meta("asset_path", asset_paths[0])
		formation.set_meta("asset_paths", PackedStringArray(asset_paths))
		cluster.add_child(formation)
		var size_scale := 1.0
		var authored_offset: Vector2 = formation_data.get("offset", Vector2.ZERO)
		var semantic_spread := 1.45 if quantity == &"many" else (1.65 if quantity == &"few" else 1.0)
		var target: Vector2 = anchor + (authored_offset * semantic_spread).rotated(scene_angle)
		var variant_start := posmod(TrackBuilderCore._mix_seed(int(spec.get("dressing_seed", spec["requested_seed"])), String(story["id"]) + String(quantity)), asset_paths.size())
		var placed_count := 0
		for item_index in requested_count:
			if stage.is_valid() and item_index > 0:
				await stage.call("Dressing the start area")
			var asset_path := asset_paths[(variant_start + item_index) % asset_paths.size()]
			var radius := TrackBuilderCore._asset_radius(asset_path, 24.0) * size_scale
			var local_offset := TrackBuilderCore._semantic_formation_offset(StringName(formation_data["formation"]), item_index, requested_count, radius)
			var placed := false
			var preferred := target + local_offset.rotated(scene_angle)
			for attempt in 36:
				var fallback_distance := float((attempt + 3) / 4) * maxf(radius * 0.6, 20.0)
				var fallback_angle := scene_angle + float(attempt) * 2.399963 + float(item_index) * 0.41
				var fallback := Vector2.ZERO if attempt == 0 else Vector2.RIGHT.rotated(fallback_angle) * fallback_distance
				var candidate := preferred + fallback
				var safe := TrackBuilderCore._placement_is_safe(candidate, radius, room_polygon, inner_loop, occupied) if placement_region == &"island" else TrackBuilderCore._trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied)
				if not safe:
					continue
				TrackBuilderCore._add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, scene_angle + float(item_index) * 0.17, placement_region, quantity, item_index, size_scale)
				occupied.append({"position": candidate, "radius": radius})
				placed_count += 1
				placed = true
				break
			if not placed:
				var exhaustive := TrackBuilderCore._best_island_position(preferred, radius, room_polygon, inner_loop, occupied) if placement_region == &"island" else TrackBuilderCore._best_offtrack_position(preferred, radius, room_polygon, centerline, gate_samples, occupied)
				if bool(exhaustive["found"]):
					var candidate: Vector2 = exhaustive["position"]
					TrackBuilderCore._add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, scene_angle + float(item_index) * 0.17, placement_region, quantity, item_index, size_scale)
					occupied.append({"position": candidate, "radius": radius})
					placed_count += 1
					placed = true
			if not placed and placement_region == &"island":
				var apron_fit := TrackBuilderCore._best_offtrack_position(preferred, radius, room_polygon, centerline, gate_samples, occupied)
				if bool(apron_fit["found"]):
					var candidate: Vector2 = apron_fit["position"]
					TrackBuilderCore._add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, scene_angle + float(item_index) * 0.17, &"apron", quantity, item_index, size_scale)
					occupied.append({"position": candidate, "radius": radius})
					placed_count += 1
					placed = true
					cluster.set_meta("placement_region", &"mixed")
			if not placed and quantity == &"unique":
				var replacement := String(spec["focal_fallback"])
				var replacement_radius := TrackBuilderCore._asset_radius(replacement, 24.0)
				var fit := TrackBuilderCore._best_offtrack_position(preferred, replacement_radius, room_polygon, centerline, gate_samples, occupied)
				if bool(fit["found"]):
					TrackBuilderCore._add_generated_prop(formation, "Item%02d" % item_index, fit["position"], replacement, scene_angle, &"apron", quantity, item_index)
					occupied.append({"position": fit["position"], "radius": replacement_radius})
					formation.set_meta("asset_path", replacement)
					formation.set_meta("replaced_asset", asset_path)
					cluster.set_meta("placement_region", &"mixed")
					placed_count += 1
		formation.set_meta("placed_count", placed_count)
