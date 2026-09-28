class_name TrackBuilderScene
## Assembles the visible track from a prepared layout. Helpers stay on TrackBuilderCore.


static func build(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, edges: Dictionary, room_polygon: PackedVector2Array, theme: StringName, stage: Callable = Callable(), environment_composer: Callable = Callable()) -> void:
	var left: PackedVector2Array = edges["left"]
	var right: PackedVector2Array = edges["right"]

	# The room is a raised household surface surrounded by a deliberately dark
	# overscan void. Floor texture is clipped to the room polygon below instead
	# of continuing across the 760-unit camera safety ring.
	var floor_texture := String(spec.get("floor_texture", ""))
	var room_bounds := TrackBuilderCore._polygon_bounds_rect(room_polygon)
	var backdrop := room_bounds.grow(760.0)
	TrackBuilderCore._add_polygon(root, "Floor", TrackBuilderCore._rect_points(backdrop.get_center(), backdrop.size), Color("111316"), -22)
	TrackBuilderCore._mark_flat_visual(root.get_node("Floor") as Polygon2D, "", &"void_backdrop")
	var room_surface := TrackBuilderCore._expand_loop(room_polygon, 26.0)
	TrackBuilderCore._add_textured_polygon(root, "RoomSurface", room_surface, floor_texture, spec["highlight"], -20, spec.get("floor_tile_world_size", TrackBuilderCore.DEFAULT_FLOOR_TILE_WORLD_SIZE), spec.get("floor_modulate", Color.WHITE))
	if stage.is_valid():
		await stage.call("Laying the racing surface")

	# Painted track ribbon (visual only — no collision)
	var corridor := PackedVector2Array()
	corridor.append_array(left)
	for index in range(right.size() - 1, -1, -1):
		corridor.append(right[index])
	var clipped_pieces: Array[PackedVector2Array] = Geometry2D.intersect_polygons(room_polygon, corridor)
	var clipped := PackedVector2Array()
	for piece: PackedVector2Array in clipped_pieces:
		if piece.size() > clipped.size():
			clipped = piece
	var track_texture := String(spec.get("track_texture", ""))
	if not track_texture.is_empty():
		var same_material := track_texture == floor_texture
		var tint: Color = spec.get("floor_modulate", Color.WHITE) if same_material else Color.WHITE
		TrackBuilderCore._add_centerline_tiles(
			root,
			centerline,
			track_texture,
			1.0 if same_material else float(spec.get("track_tile_modulate", 1.35)),
			spec.get("track_world_tile_size", Vector2.ZERO),
			1.0 if same_material else float(spec.get("track_opacity", 0.52)),
			tint,
			0.0 if same_material else 0.16
		)

	if spec.get("seed_obstacles", false):
		TrackBuilderCore._add_corridor_patterning(root, spec, centerline, room_polygon)
	if stage.is_valid():
		await stage.call("Building physical track boundaries")

	# No painted delimitation lines: the ribbon, island prop, and placed props
	# define the course
	var outer_loop := left if absf(TrackBuilderCore._polygon_area(left)) > absf(TrackBuilderCore._polygon_area(right)) else right
	var inner_loop := left if absf(TrackBuilderCore._polygon_area(left)) < absf(TrackBuilderCore._polygon_area(right)) else right
	var outer_boundary := outer_loop
	if spec.get("seed_obstacles", false) or spec.has("environment_plan"):
		inner_loop = edges["inner_boundary"] if edges.has("inner_boundary") else TrackBuilderCore._simple_inner_boundary_loop(inner_loop, centerline)
		outer_boundary = edges["outer_boundary"] if edges.has("outer_boundary") else TrackBuilderCore._simple_boundary_loop(outer_loop, centerline)
	# Generated centerlines are clearance-validated, so their inner offset is the
	# authoritative island boundary. Boolean subtraction represents the annular
	# ribbon as nested outer/hole polygons and can otherwise select the whole room
	# as a solid collision body.
	var island_region := inner_loop.duplicate() if spec.get("seed_obstacles", false) or spec.has("environment_plan") else TrackBuilderCore._island_region(room_polygon, clipped, inner_loop)
	await TrackBuilderCore._build_island_prop(root, spec, island_region, inner_loop, centerline, stage)
	if stage.is_valid():
		await stage.call("Placing room edges and checkpoints")

	# Legacy authored tracks keep their fixed room-corner dressing. Generated
	# tracks choose landmarks from geometry-aware story moments below.
	if not spec.get("seed_obstacles", false) and not spec.has("environment_plan"):
		TrackBuilderCore._add_corner_set_pieces(root, spec, room_polygon, clipped)

	# Room walls (real furniture edges along the room outline)
	var edge_texture := String(spec.get("edge_texture", "res://assets/textures/kitchen/counter_edge.png"))
	var wall_index := 0
	for index in room_polygon.size():
		var from: Vector2 = room_polygon[index]
		var to: Vector2 = room_polygon[(index + 1) % room_polygon.size()]
		var mid := (from + to) * 0.5
		var edge_vector := to - from
		var length := edge_vector.length()
		if length < 1.0:
			continue
		TrackBuilderCore._add_wall_segment(root, "Wall%d" % wall_index, mid, length, atan2(edge_vector.y, edge_vector.x), edge_texture)
		wall_index += 1

	# Checkpoints along the arc, aligned to the tangent. The last lap gate sits
	# slightly past the corner rejoin so its recovery point stays on a straight.
	var gate_fractions: Array = spec.get("gate_fractions", [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.84])
	var arc := TrackBuilderCore._arc_lengths(centerline)
	var total := arc[arc.size() - 1]
	var start := centerline[0]
	var start_tangent := (centerline[1] - centerline[centerline.size() - 1]).normalized()
	var gate_samples := PackedVector2Array()
	for gate_index in TrackBuilderCore.GATE_COUNT:
		if stage.is_valid() and gate_index % 2 == 0:
			await stage.call("Placing room edges and checkpoints")
		var fraction: float = gate_fractions[gate_index]
		var sample := TrackBuilderCore._sample_at_arc(centerline, arc, total * fraction)
		gate_samples.append(sample)
		var tangent := TrackBuilderCore._tangent_at_arc(centerline, arc, total * fraction)
		var rotation := atan2(-tangent.y, -tangent.x)
		var is_finish := gate_index == 0
		var name := "Checkpoint0Finish" if is_finish else "Checkpoint%d" % gate_index
		var span_endpoints := PackedVector2Array()
		if spec.get("seed_obstacles", false):
			span_endpoints = TrackBuilderCore._gate_span_endpoints(sample, tangent, room_polygon, island_region)
		TrackBuilderCore._add_cp(root, name, sample, rotation, gate_index, is_finish, atan2(tangent.x, -tangent.y), span_endpoints)
		if spec.get("seed_obstacles", false):
			TrackBuilderCore._add_gate_posts(root, spec, sample, tangent, gate_index)

	# The checker spans the complete nominal corridor. Each color cell is its own
	# simple polygon so disconnected checks never become a self-crossing polygon.
	TrackBuilderCore._add_finish_checker(root, start, start_tangent)

	# Follow the centerline arc rather than extending one start tangent through a
	# nearby corner. This keeps every grid slot inside the drivable corridor on
	# technical layouts in both directions.
	var forward_positions: Array[Vector2] = []
	var forward_rotations: Array[float] = []
	for grid_distance: float in TrackBuilderNodes.grid_arc_distances(centerline, false, room_polygon, island_region):
		var grid_sample := TrackBuilderCore._sample_at_arc(centerline, arc, grid_distance)
		var grid_tangent := TrackBuilderCore._tangent_at_arc(centerline, arc, grid_distance)
		var grid_normal := grid_tangent.rotated(PI * 0.5)
		forward_positions.append(grid_sample - grid_normal * TrackBuilderCore.GRID_LANE_OFFSET)
		forward_positions.append(grid_sample + grid_normal * TrackBuilderCore.GRID_LANE_OFFSET)
		forward_rotations.append(atan2(grid_tangent.x, -grid_tangent.y))
		forward_rotations.append(atan2(grid_tangent.x, -grid_tangent.y))
	TrackBuilderCore._add_grid(root, "GridForward", 0.0, forward_positions, forward_rotations)
	var reverse_positions: Array[Vector2] = []
	var reverse_rotations: Array[float] = []
	for grid_distance: float in TrackBuilderNodes.grid_arc_distances(centerline, true, room_polygon, island_region):
		var target_arc := maxf(total - grid_distance, 0.0)
		var grid_sample := TrackBuilderCore._sample_at_arc(centerline, arc, target_arc)
		var grid_tangent := TrackBuilderCore._tangent_at_arc(centerline, arc, target_arc)
		var grid_normal := grid_tangent.rotated(PI * 0.5)
		reverse_positions.append(grid_sample - grid_normal * TrackBuilderCore.GRID_LANE_OFFSET)
		reverse_positions.append(grid_sample + grid_normal * TrackBuilderCore.GRID_LANE_OFFSET)
		reverse_rotations.append(atan2(-grid_tangent.x, grid_tangent.y))
		reverse_rotations.append(atan2(-grid_tangent.x, grid_tangent.y))
	TrackBuilderCore._add_grid(root, "GridReverse", 0.0, reverse_positions, reverse_rotations)

	var generated_moments := {}
	if spec.get("seed_obstacles", false):
		generated_moments = TrackBuilderCore._analyze_track_moments(centerline, gate_samples)

	# Racing line the AI follows (curvature-offset ideal path, stored invisibly).
	# Generated AI stays on the safe side of the optional risk shortcut.
	TrackBuilderCore._build_racing_line(root, centerline, generated_moments)
	if stage.is_valid():
		await stage.call("Building trackside scenery")

	if spec.get("seed_obstacles", false):
		TrackBuilderCore._seal_pockets(root, spec, centerline, room_polygon)
		if stage.is_valid():
			await stage.call("Building trackside scenery")
		if environment_composer.is_valid():
			await environment_composer.call(root, stage)
		elif spec.has("environment_plan"):
			await WorldEnvironmentArt.compose(root, spec, centerline, stage)
			TrackBuilderCore._build_generated_obstacles(root, spec)
		else:
			TrackBuilderCore._build_generated_outer_boundary_visuals(root, spec, centerline, inner_loop, outer_boundary, room_polygon, generated_moments)
			if stage.is_valid():
				await stage.call("Placing landmarks")
			await TrackBuilderCore._compose_generated_story(root, spec, centerline, inner_loop, outer_loop, room_polygon, gate_samples, generated_moments, stage)
			TrackBuilderCore._build_generated_obstacles(root, spec)
	elif spec.has("environment_plan"):
		await WorldEnvironmentArt.compose(root, spec, centerline, stage)
	else:
		# Canonical/static tracks retain their authored legacy dressing.
		TrackBuilderCore._fill_island(root, spec, inner_loop, centerline)
		if not OS.get_environment("PC_NO_BOUNDARY") == "1":
			TrackBuilderCore._line_boundary_props(root, spec, centerline, outer_loop, clipped, room_polygon)
		TrackBuilderCore._add_paperclip_line(root, spec, centerline, outer_loop, room_polygon)
		var decal_rng := RandomNumberGenerator.new()
		decal_rng.seed = int(spec.get("seed", 0)) * 31 + 7
		TrackBuilderCore._scatter_decals(root, spec, room_polygon, corridor, decal_rng)

		# Track obstacles (real props with collision)
		var obstacles: Dictionary = spec["obstacles"]
		for obstacle_name: String in obstacles:
			var data: Dictionary = obstacles[obstacle_name]
			TrackBuilderCore._add_obstacle(root, obstacle_name, data["pos"], float(data["r"]), String(data["tex"]))

		# Apron furniture: real objects off the racing line, some with collision
		var apron_props: Array = spec.get("apron_props", [])
		for prop: Dictionary in apron_props:
			TrackBuilderCore._add_prop_with_collision(root, prop["pos"], float(prop["r"]), String(prop["tex"]))

		# The old cross-theme hardware edge belongs only to canonical static tracks.
		var outer_loop2 := left if absf(TrackBuilderCore._polygon_area(left)) > absf(TrackBuilderCore._polygon_area(right)) else right
		var prop_textures := [
			"res://assets/textures/kitchen/lime_cartoon.png",
			"res://assets/textures/kitchen/apple_cartoon.png",
			"res://assets/textures/imagine/hazard_workshop_socket.png",
			"res://assets/textures/kitchen/sponge_wet.png",
		]
		var hardware_index := 0
		for index in range(24, centerline.size() - 24, 6):
			var tangent := (centerline[(index + 1) % centerline.size()] - centerline[(index - 1 + centerline.size()) % centerline.size()]).normalized()
			if absf(tangent.x) < 0.45 or absf(tangent.y) < 0.45:
				continue
			var outward := (outer_loop2[index] - centerline[index]).normalized()
			var prop_position := centerline[index] + outward * 175.0
			if not Geometry2D.is_point_in_polygon(prop_position, room_polygon):
				continue
			if not Geometry2D.is_point_in_polygon(prop_position, corridor):
				TrackBuilderCore._add_prop_with_collision(root, prop_position, 30.0, prop_textures[hardware_index % prop_textures.size()])
				hardware_index += 1


	# Generated races use their paired physical gate-zero landmarks in both
	# directions. Canonical fixtures retain the older one-sided start banner.
	if not spec.get("seed_obstacles", false):
		TrackBuilderCore._add_start_banner(root, start, start_tangent, corridor)
