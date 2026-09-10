class_name TrackBuilderCore
## Runtime + headless track builder: builds a painted toy-racing circuit scene
## (spline corridor, island prop, walls, gates, grid, props) from a theme spec,
## a room shape, and a seed. Pure runtime code — no SceneTree/editor deps — so
## the race can generate any arbitrary seed on demand.

const CHECKPOINT_SCRIPT := preload("res://scripts/race/checkpoint.gd")
const VISUAL_ROLE_CONTRACT := preload("res://scripts/race/generated_world_visual_role.gd")
const GENERATED_RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const WORLD_MATERIALS := preload("res://scripts/race/generated_world_materials.gd")
const TRACK_BUILDER_CATALOG := preload("res://scripts/race/track_builder_catalog.gd")
const TRACK_BUILDER_GEOMETRY := preload("res://scripts/race/track_builder_geometry.gd")
const TRACK_BUILDER_PLANNER := preload("res://scripts/race/track_builder_planner.gd")
const HALF_WIDTH := 125.0
const SAMPLE_COUNT := 260
const GATE_COUNT := 8
const WORLD_SCALE := TrackSeedGen.WORLD_SCALE
const DEFAULT_FLOOR_TILE_WORLD_SIZE := Vector2(512.0, 512.0)
const WORLD_SURFACE_SHADER := preload("res://assets/shaders/world_surface.gdshader")
const RECOVERY_LANE_HALF_LENGTH := 230.0
const RECOVERY_LANE_HALF_WIDTH := 48.0
const SHORTCUT_HALF_SPAN := 10
const SHORTCUT_LANE_OFFSET := 70.0
const SHORTCUT_LANE_HALF_WIDTH := 26.0
const SAFE_RACING_LINE_OFFSET := 58.0
const APEX_MAX_INWARD_OFFSET := 90.0
const APEX_MAX_ENTRY_OFFSET := 32.0
const APEX_SAMPLE_SPAN := 10
const FINISH_APPROACH_SPAN := 20
const GRIP_PATCH_MIN_COUNT := 4
const GRIP_PATCH_MAX_COUNT := 8
const ISLAND_SIDE_FACE_WIDTH := 38.0
const ISLAND_TEXTURED_RIM_WIDTH := 26.0
const ISLAND_TOP_LIP_WIDTH := 8.0
const GATE_SENSOR_THICKNESS := 70.0
const GATE_POST_OFFSET := HALF_WIDTH + 24.0
const GATE_POST_SIZE := Vector2(42.0, 24.0)
const FINISH_LANDMARK_OFFSET := HALF_WIDTH + 26.0
const FINISH_LANDMARK_SIZE := Vector2(64.0, 36.0)
const SHADOW_CIRCLE_TEXTURE := "res://assets/textures/edge_dressing/shadow_soft_circle.png"
const SHADOW_RECT_TEXTURE := "res://assets/textures/edge_dressing/shadow_soft_rect.png"
const SHADOW_DIRECTION := Vector2(0.62, 0.78)
const SHADOW_TINT := Color("3f2a22", 0.35)
const GIANT_CAST_SHADOW_TINT := Color("3f2a22", 0.15)
const COLLISION_SOLID := &"solid"
const COLLISION_FLAT := &"flat"
const VISUAL_ROLE_SOLID := VISUAL_ROLE_CONTRACT.SOLID
const VISUAL_ROLE_FLAT := VISUAL_ROLE_CONTRACT.FLAT
const VISUAL_ROLE_MOVING_HAZARD := VISUAL_ROLE_CONTRACT.MOVING_HAZARD
const COLLISION_ALPHA_THRESHOLD := 0.08
const ORIENTED_FOOTPRINT_MIN_ANISOTROPY := 1.35
const APRON_COLLIDER_CLEARANCE := 36.0
const FLAT_DRESSING_ROUTE_CLEARANCE := 12.0
const ROOM_EDGE_TILE_WORLD_LENGTH := 1024.0
const RACING_LINE_HULL_RADIUS := 22.0
const VEHICLE_WIDTH := 44.0
const MIN_VIABLE_CORRIDOR_WIDTH := VEHICLE_WIDTH * 1.6
const OBSTACLE_ROUTE_CLEARANCE := VEHICLE_WIDTH * 0.5 + 8.0
const OBSTACLE_EDGE_INSET := 8.0

static var GENERATED_OBSTACLE_TYPES: Dictionary = {}


static func _footprint_projected_extent(footprint_size: Vector2, shape_kind: StringName, rotation: float, axis: Vector2) -> float:
	return TRACK_BUILDER_GEOMETRY.footprint_projected_extent(footprint_size, shape_kind, rotation, axis)


static func _plan_generated_obstacles(
		theme: StringName,
		spec: Dictionary,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		moments: Dictionary
) -> Array[Dictionary]:
	return TRACK_BUILDER_PLANNER.plan_obstacles(
		theme,
		spec,
		centerline,
		gate_samples,
		moments,
		GENERATED_OBSTACLE_TYPES.get(theme, []),
		_racing_line_points(centerline, moments, false),
		_racing_line_points(centerline, moments, true)
	)


static func _plan_generated_hazard(theme: StringName, spec: Dictionary, centerline: PackedVector2Array, moments: Dictionary) -> Dictionary:
	return TRACK_BUILDER_PLANNER.plan_hazard(theme, spec, centerline, moments)


static var SOLID_EDGE_SHAPES: Dictionary = {}
static var FLAT_EDGE_ASSETS: Dictionary = {}
static var _texture_footprint_cache: Dictionary = {}
static var _texture_hull_cache: Dictionary = {}
static var _texture_opaque_rect_cache: Dictionary = {}
static var _texture_outline_cache: Dictionary = {}
static var synchronous_outline_builds := 0
static var ASSET_FOOTPRINT_OVERRIDES: Dictionary = {}
static var ROOM_SHAPES: Dictionary = {}
static var BASE_ROOM_SHAPES: Dictionary = {}
static var ISLAND_VIGNETTES: Dictionary = {}
static var ROOM_COMPOSITIONS: Dictionary = {}
static var STORY_KITS: Dictionary = {}
static var PROP_SHAPES: Dictionary = {}
static var LAYOUTS: Dictionary = {}


static func _static_init() -> void:
	var data: Dictionary = TRACK_BUILDER_CATALOG.catalog()
	GENERATED_OBSTACLE_TYPES = data["generated_obstacle_types"]
	SOLID_EDGE_SHAPES = data["solid_edge_shapes"]
	FLAT_EDGE_ASSETS = data["flat_edge_assets"]
	ASSET_FOOTPRINT_OVERRIDES = data["asset_footprint_overrides"]
	ROOM_SHAPES = data["room_shapes"]
	BASE_ROOM_SHAPES = data["base_room_shapes"]
	ISLAND_VIGNETTES = data["island_vignettes"]
	ROOM_COMPOSITIONS = data["room_compositions"]
	STORY_KITS = data["story_kits"]
	PROP_SHAPES = data["prop_shapes"]
	LAYOUTS = data["layouts"]


static func build_packed(theme: StringName, room_shape: StringName, seed: int, generation_options: Dictionary = {}) -> Dictionary:
	var prepared := prepare_layout(theme, room_shape, seed, generation_options)
	if prepared.is_empty():
		return {"scene": null, "seed": seed}
	var root := create_layout_root(prepared)
	_build_scene(root, prepared["spec"], prepared["centerline"], prepared["edges"], prepared["room_polygon"], theme)
	_mark_owned(root)
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return {"scene": packed, "seed": prepared["seed"], "racing_line_metrics": (prepared.get("racing_line_metrics", {}) as Dictionary).duplicate(true)}


static func prepare_layout(theme: StringName, room_shape: StringName, seed: int, generation_options: Dictionary = {}) -> Dictionary:
	if not LAYOUTS.has(theme) or not ROOM_SHAPES.has(room_shape):
		return {}
	var spec: Dictionary = LAYOUTS[theme]
	var room_polygon: PackedVector2Array = ROOM_SHAPES[room_shape] if seed >= 0 else BASE_ROOM_SHAPES[room_shape]
	var used_seed := seed
	if seed >= 0:
		var room_params := {
			"margin": 190.0,
			"min_point_distance": 210.0,
			"max_angle_deg": 80.0,
			"min_self_distance": 320.0,
			"min_loop_length": 1900.0 * WORLD_SCALE,
			"room_polygon": room_polygon,
			"room_shape": room_shape,
		}
		match room_shape:
			&"tall":
				room_params["displacement_scale"] = 0.55
			&"el":
				room_params["displacement_scale"] = 0.5
				room_params["min_loop_length"] = 1500.0 * WORLD_SCALE
			&"long":
				room_params["displacement_scale"] = 1.0
				room_params["min_loop_length"] = 2000.0 * WORLD_SCALE
			&"square":
				room_params["displacement_scale"] = 1.0
				room_params["min_loop_length"] = 2200.0 * WORLD_SCALE
		var gen := TrackSeedGen.generate_with_retries(seed, Rect2(-940, -540, 1880, 1080), room_params)
		if gen["points"].is_empty():
			push_error("TrackBuilderCore: could not generate a valid circuit near seed " + str(seed))
			return {}
		spec = spec.duplicate()
		spec["controls"] = gen["points"]
		spec["seed_obstacles"] = true
		spec["seed"] = int(gen["seed"])
		spec["requested_seed"] = seed
		spec["family"] = StringName(gen["family"])
		spec["realization"] = StringName(gen.get("realization", gen["family"]))
		spec["route_program"] = StringName(gen.get("route_program", gen["family"]))
		spec["route_recipe"] = StringName(gen.get("route_recipe", gen["family"]))
		spec["route_sequence"] = String(gen.get("route_sequence", ""))
		spec["generation_attempt"] = int(gen.get("attempt", 0))
		spec["generation_fallback"] = bool(gen.get("fallback", false))
		spec["loop_length"] = float(gen["length"])
		var sub_seeds: Dictionary = generation_options.get("sub_seeds", {})
		spec["material_seed"] = int(generation_options.get("material_seed", sub_seeds.get("material", _mix_seed(seed, "material"))))
		spec["dressing_seed"] = int(generation_options.get("dressing_seed", sub_seeds.get("dressing", _mix_seed(seed, String(theme)))))
		spec["material_id"] = String(generation_options.get("material_id", ""))
		spec["palette_id"] = String(generation_options.get("palette_id", ""))
		var kits: Array = ROOM_COMPOSITIONS.get(theme, ROOM_COMPOSITIONS[&"kitchen"])
		var kit_index := GENERATED_RULES.story_index(theme, int(spec["dressing_seed"]))
		spec["story_kit"] = (kits[kit_index] as Dictionary).duplicate(true)
		spec["story_id"] = GENERATED_RULES.story_id(theme, int(spec["dressing_seed"]))
		spec["story_kit"]["id"] = spec["story_id"]
		WORLD_MATERIALS.apply_to_spec(
			spec,
			WORLD_MATERIALS.resolve(
				theme,
				spec["story_id"],
				int(spec["material_seed"]),
				String(spec["material_id"]),
				String(spec["palette_id"])
			)
		)
		spec["island_expansion"] = 10.0
		spec.erase("gate_fractions")
		spec["obstacle_seed"] = int(generation_options.get("obstacle_seed", sub_seeds.get("obstacle", _mix_seed(seed, "obstacle_plan"))))
		spec["hazard_seed"] = int(generation_options.get("hazard_seed", sub_seeds.get("hazard", _mix_seed(seed, "hazard_plan"))))
		spec["act"] = clampi(int(generation_options.get("act", GENERATED_RULES.default_act_for_theme(theme))), 1, 3)
		spec["obstacles_enabled"] = bool(generation_options.get("obstacles_enabled", true))
		used_seed = int(gen["seed"])
	var centerline := _sample_centerline(spec["controls"])
	var edges := _corridor_edges(centerline)
	if spec.get("seed_obstacles", false):
		var left: PackedVector2Array = edges["left"]
		var right: PackedVector2Array = edges["right"]
		var outer := left if absf(_polygon_area(left)) > absf(_polygon_area(right)) else right
		var inner := left if absf(_polygon_area(left)) < absf(_polygon_area(right)) else right
		edges["inner_boundary"] = _simple_inner_boundary_loop(inner, centerline)
		edges["outer_boundary"] = _simple_boundary_loop(outer, centerline)
		var gate_samples := _layout_gate_samples(centerline, spec)
		var moments := _analyze_track_moments(centerline, gate_samples)
		spec["obstacle_plan"] = _plan_generated_obstacles(theme, spec, centerline, gate_samples, moments)
		spec["hazard_plan"] = _plan_generated_hazard(theme, spec, centerline, moments)
	var prepared := {"spec": spec, "centerline": centerline, "edges": edges, "room_polygon": room_polygon, "theme": theme, "room_shape": room_shape, "seed": used_seed}
	prepared["racing_line_metrics"] = racing_line_metrics_from_prepared(prepared)
	return prepared


static func racing_line_metrics_from_prepared(prepared: Dictionary) -> Dictionary:
	if prepared.is_empty() or prepared.get("centerline") is not PackedVector2Array or prepared.get("spec") is not Dictionary:
		return {}
	var centerline: PackedVector2Array = prepared["centerline"]
	var spec: Dictionary = prepared["spec"]
	var gate_samples := _layout_gate_samples(centerline, spec)
	var moments := _analyze_track_moments(centerline, gate_samples)
	var racing_line := _racing_line_points(centerline, moments, false)
	if racing_line.size() < 3:
		return {}
	var racing_line_length := 0.0
	var absolute_turn_radians := 0.0
	var technical_samples := 0
	var max_sample_turn_radians := 0.0
	for index in racing_line.size():
		racing_line_length += racing_line[index].distance_to(racing_line[(index + 1) % racing_line.size()])
		var incoming := (racing_line[index] - racing_line[posmod(index - 1, racing_line.size())]).normalized()
		var outgoing := (racing_line[(index + 1) % racing_line.size()] - racing_line[index]).normalized()
		var sample_turn := absf(incoming.angle_to(outgoing))
		absolute_turn_radians += sample_turn
		max_sample_turn_radians = maxf(max_sample_turn_radians, sample_turn)
		if sample_turn >= 0.035:
			technical_samples += 1
	return {
		"racing_line_length": racing_line_length,
		"absolute_turn_radians": absolute_turn_radians,
		"turn_demand": absolute_turn_radians / TAU,
		"technical_fraction": float(technical_samples) / maxf(float(racing_line.size()), 1.0),
		"max_sample_turn_radians": max_sample_turn_radians,
		"sample_count": racing_line.size(),
		"seed": int(prepared["seed"]),
	}


static func create_layout_root(prepared: Dictionary) -> Node2D:
	var spec: Dictionary = prepared["spec"]
	var room_polygon: PackedVector2Array = prepared["room_polygon"]
	var root := Node2D.new()
	root.name = String(spec["root_name"])
	root.add_to_group("track", true)
	if spec.get("seed_obstacles", false):
		root.set_meta("generated_track", true)
		root.set_meta("requested_seed", int(spec["requested_seed"]))
		root.set_meta("family", StringName(spec["family"]))
		root.set_meta("realization", StringName(spec["realization"]))
		root.set_meta("route_program", spec["route_program"])
		root.set_meta("route_recipe", spec["route_recipe"])
		root.set_meta("route_sequence", spec["route_sequence"])
		root.set_meta("generation_attempt", int(spec["generation_attempt"]))
		root.set_meta("generation_fallback", bool(spec["generation_fallback"]))
		root.set_meta("story_id", StringName(spec["story_id"]))
		root.set_meta("loop_length", float(spec["loop_length"]))
		root.set_meta("theme", prepared["theme"])
		root.set_meta("room_shape", prepared["room_shape"])
		root.set_meta("room_bounds", _polygon_bounds_rect(room_polygon))
		root.set_meta("room_polygon", room_polygon)
		root.set_meta("world_scale", WORLD_SCALE)
		root.set_meta("material_seed", int(spec["material_seed"]))
		root.set_meta("dressing_seed", int(spec["dressing_seed"]))
		root.set_meta("material_id", String(spec.get("material_id", "")))
		root.set_meta("palette_id", String(spec.get("palette_id", "")))
		root.set_meta("obstacle_seed", int(spec["obstacle_seed"]))
		root.set_meta("hazard_seed", int(spec["hazard_seed"]))
		root.set_meta("obstacles_enabled", bool(spec["obstacles_enabled"]))
		root.set_meta("generated_obstacle_plan", (spec.get("obstacle_plan", []) as Array).duplicate(true))
		root.set_meta("generated_hazard_plan", (spec.get("hazard_plan", {}) as Dictionary).duplicate(true))
	return root


static func assemble_runtime(root: Node2D, prepared: Dictionary, stage: Callable) -> void:
	await _build_scene(root, prepared["spec"], prepared["centerline"], prepared["edges"], prepared["room_polygon"], prepared["theme"], stage)


static func _sample_centerline(controls: Array) -> PackedVector2Array:
	return TRACK_BUILDER_GEOMETRY.sample_centerline(controls)


static func _catmull_rom_closed(points: Array, t: float) -> Vector2:
	return TRACK_BUILDER_GEOMETRY.catmull_rom_closed(points, t)


static func _corridor_edges(centerline: PackedVector2Array) -> Dictionary:
	return TRACK_BUILDER_GEOMETRY.corridor_edges(centerline)


static func _build_scene(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, edges: Dictionary, room_polygon: PackedVector2Array, theme: StringName, stage: Callable = Callable()) -> void:
	var left: PackedVector2Array = edges["left"]
	var right: PackedVector2Array = edges["right"]

	# The room is a raised household surface surrounded by a deliberately dark
	# overscan void. Floor texture is clipped to the room polygon below instead
	# of continuing across the 760-unit camera safety ring.
	var floor_texture := String(spec.get("floor_texture", ""))
	var room_bounds := _polygon_bounds_rect(room_polygon)
	var backdrop := room_bounds.grow(760.0)
	_add_polygon(root, "Floor", _rect_points(backdrop.get_center(), backdrop.size), Color("111316"), -22)
	_mark_flat_visual(root.get_node("Floor") as Polygon2D, "", &"void_backdrop")
	var room_surface := _expand_loop(room_polygon, 26.0)
	_add_textured_polygon(root, "RoomSurface", room_surface, floor_texture, spec["highlight"], -20, spec.get("floor_tile_world_size", DEFAULT_FLOOR_TILE_WORLD_SIZE), spec.get("floor_modulate", Color.WHITE))
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
	if not spec.get("seed_obstacles", false):
		# Canonical tracks retain their authored painted base. Generated tracks use
		# the themed TrackSurface directly; a translucent annular overlay produces
		# visible triangulation fans in deep notches and L-shaped routes.
		_add_polygon(root, "TrackRibbon", clipped, Color(1.0, 0.96, 0.88, 0.17), -10)
		_mark_flat_visual(root.get_node("TrackRibbon") as Polygon2D, "", &"track_surface")
	var track_texture := String(spec.get("track_texture", ""))
	if not track_texture.is_empty():
		var same_material := track_texture == floor_texture
		var tint: Color = spec.get("floor_modulate", Color.WHITE) if same_material else Color.WHITE
		_add_centerline_tiles(
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
		_add_corridor_patterning(root, spec, centerline, room_polygon)
	if stage.is_valid():
		await stage.call("Building physical track boundaries")

	# No painted delimitation lines: the ribbon, island prop, and placed props
	# define the course
	var outer_loop := left if absf(_polygon_area(left)) > absf(_polygon_area(right)) else right
	var inner_loop := left if absf(_polygon_area(left)) < absf(_polygon_area(right)) else right
	var outer_boundary := outer_loop
	if spec.get("seed_obstacles", false):
		inner_loop = edges["inner_boundary"] if edges.has("inner_boundary") else _simple_inner_boundary_loop(inner_loop, centerline)
		outer_boundary = edges["outer_boundary"] if edges.has("outer_boundary") else _simple_boundary_loop(outer_loop, centerline)
	# Generated centerlines are clearance-validated, so their inner offset is the
	# authoritative island boundary. Boolean subtraction represents the annular
	# ribbon as nested outer/hole polygons and can otherwise select the whole room
	# as a solid collision body.
	var island_region := inner_loop.duplicate() if spec.get("seed_obstacles", false) else _island_region(room_polygon, clipped, inner_loop)
	await _build_island_prop(root, spec, island_region, inner_loop, centerline, stage)
	if stage.is_valid():
		await stage.call("Placing room edges and checkpoints")

	# Legacy authored tracks keep their fixed room-corner dressing. Generated
	# tracks choose landmarks from geometry-aware story moments below.
	if not spec.get("seed_obstacles", false):
		_add_corner_set_pieces(root, spec, room_polygon, clipped)

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
		_add_wall_segment(root, "Wall%d" % wall_index, mid, length, atan2(edge_vector.y, edge_vector.x), edge_texture)
		wall_index += 1

	# Checkpoints along the arc, aligned to the tangent. The last lap gate sits
	# slightly past the corner rejoin so its recovery point stays on a straight.
	var gate_fractions: Array = spec.get("gate_fractions", [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.84])
	var arc := _arc_lengths(centerline)
	var total := arc[arc.size() - 1]
	var start := centerline[0]
	var start_tangent := (centerline[1] - centerline[centerline.size() - 1]).normalized()
	var gate_samples := PackedVector2Array()
	for gate_index in GATE_COUNT:
		if stage.is_valid() and gate_index % 2 == 0:
			await stage.call("Placing room edges and checkpoints")
		var fraction: float = gate_fractions[gate_index]
		var sample := _sample_at_arc(centerline, arc, total * fraction)
		gate_samples.append(sample)
		var tangent := _tangent_at_arc(centerline, arc, total * fraction)
		var rotation := atan2(-tangent.y, -tangent.x)
		var is_finish := gate_index == 0
		var name := "Checkpoint0Finish" if is_finish else "Checkpoint%d" % gate_index
		var span_endpoints := PackedVector2Array()
		if spec.get("seed_obstacles", false):
			span_endpoints = _gate_span_endpoints(sample, tangent, room_polygon, island_region)
		_add_cp(root, name, sample, rotation, gate_index, is_finish, atan2(tangent.x, -tangent.y), span_endpoints)
		if spec.get("seed_obstacles", false):
			_add_gate_posts(root, spec, sample, tangent, gate_index)

	# The checker spans the complete nominal corridor. Each color cell is its own
	# simple polygon so disconnected checks never become a self-crossing polygon.
	_add_finish_checker(root, start, start_tangent)

	# Follow the centerline arc rather than extending one start tangent through a
	# nearby corner. This keeps every grid slot inside the drivable corridor on
	# technical layouts in both directions.
	var forward_positions: Array[Vector2] = []
	var forward_rotations: Array[float] = []
	for grid_distance: float in [100.0, 220.0]:
		var grid_sample := _sample_at_arc(centerline, arc, grid_distance)
		var grid_tangent := _tangent_at_arc(centerline, arc, grid_distance)
		var grid_normal := grid_tangent.rotated(PI * 0.5)
		forward_positions.append(grid_sample - grid_normal * 45.0)
		forward_positions.append(grid_sample + grid_normal * 45.0)
		forward_rotations.append(atan2(grid_tangent.x, -grid_tangent.y))
		forward_rotations.append(atan2(grid_tangent.x, -grid_tangent.y))
	_add_grid(root, "GridForward", 0.0, forward_positions, forward_rotations)
	var reverse_positions: Array[Vector2] = []
	var reverse_rotations: Array[float] = []
	for grid_distance: float in [45.0, 120.0]:
		var target_arc := maxf(total - grid_distance, 0.0)
		var grid_sample := _sample_at_arc(centerline, arc, target_arc)
		var grid_tangent := _tangent_at_arc(centerline, arc, target_arc)
		var grid_normal := grid_tangent.rotated(PI * 0.5)
		reverse_positions.append(grid_sample - grid_normal * 45.0)
		reverse_positions.append(grid_sample + grid_normal * 45.0)
		reverse_rotations.append(atan2(-grid_tangent.x, grid_tangent.y))
		reverse_rotations.append(atan2(-grid_tangent.x, grid_tangent.y))
	_add_grid(root, "GridReverse", 0.0, reverse_positions, reverse_rotations)

	var generated_moments := {}
	if spec.get("seed_obstacles", false):
		generated_moments = _analyze_track_moments(centerline, gate_samples)

	# Racing line the AI follows (curvature-offset ideal path, stored invisibly).
	# Generated AI stays on the safe side of the optional risk shortcut.
	_build_racing_line(root, centerline, generated_moments)
	if stage.is_valid():
		await stage.call("Building trackside scenery")

	if spec.get("seed_obstacles", false):
		_build_generated_outer_boundary_visuals(root, spec, centerline, inner_loop, outer_boundary, room_polygon, generated_moments)
		if stage.is_valid():
			await stage.call("Placing landmarks")
		await _compose_generated_story(root, spec, centerline, inner_loop, outer_loop, room_polygon, gate_samples, generated_moments, stage)
		_build_generated_obstacles(root, spec)
	else:
		# Canonical/static tracks retain their authored legacy dressing.
		_fill_island(root, spec, inner_loop, centerline)
		if not OS.get_environment("PC_NO_BOUNDARY") == "1":
			_line_boundary_props(root, spec, centerline, outer_loop, clipped, room_polygon)
		_add_paperclip_line(root, spec, centerline, outer_loop, room_polygon)
		var decal_rng := RandomNumberGenerator.new()
		decal_rng.seed = int(spec.get("seed", 0)) * 31 + 7
		_scatter_decals(root, spec, room_polygon, corridor, decal_rng)

		# Track obstacles (real props with collision)
		var obstacles: Dictionary = spec["obstacles"]
		for obstacle_name: String in obstacles:
			var data: Dictionary = obstacles[obstacle_name]
			_add_obstacle(root, obstacle_name, data["pos"], float(data["r"]), String(data["tex"]))

		# Apron furniture: real objects off the racing line, some with collision
		var apron_props: Array = spec.get("apron_props", [])
		for prop: Dictionary in apron_props:
			_add_prop_with_collision(root, prop["pos"], float(prop["r"]), String(prop["tex"]))

		# The old cross-theme hardware edge belongs only to canonical static tracks.
		var outer_loop2 := left if absf(_polygon_area(left)) > absf(_polygon_area(right)) else right
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
				_add_prop_with_collision(root, prop_position, 30.0, prop_textures[hardware_index % prop_textures.size()])
				hardware_index += 1


	# Generated races use their paired physical gate-zero landmarks in both
	# directions. Canonical fixtures retain the older one-sided start banner.
	if not spec.get("seed_obstacles", false):
		_add_start_banner(root, start, start_tangent, corridor)


static func _build_island_prop(root: Node2D, spec: Dictionary, region: PackedVector2Array, inner_loop: PackedVector2Array, centerline: PackedVector2Array, stage: Callable = Callable()) -> void:
	var expanded := PackedVector2Array()
	if spec.get("seed_obstacles", false):
		# Geometry2D already returns a simple central polygon. Procedural concave
		# loops can make a naively offset inner centerline self-intersect, which is
		# not a valid CollisionPolygon2D; use the clipped island itself instead.
		expanded = region.duplicate()
	else:
		var last := Vector2(INF, INF)
		for index in inner_loop.size():
			var toward_track := (centerline[index] - inner_loop[index]).normalized()
			var point := inner_loop[index] + toward_track * float(spec.get("island_expansion", 10.0))
			if point.distance_to(last) > 3.0:
				expanded.append(point)
				last = point
	var barrier := StaticBody2D.new()
	barrier.name = "InnerBarrier"
	barrier.collision_layer = 2
	_mark_solid_body(barrier, "", &"raised_island_rim")
	barrier.set_meta("boundary_polygon", expanded)
	barrier.set_meta("visible_collision_backing", &"raised_island_rim")
	root.add_child(barrier)
	if spec.get("seed_obstacles", false):
		# The line art is centered on `expanded`; contact belongs at its outer
		# (track-facing) edge, not invisibly halfway through the 26u textured rim.
		var collision_boundary := _outset_polygon(expanded, ISLAND_TEXTURED_RIM_WIDTH * 0.5)
		# A generated inner offset can be concave enough that solid polygon
		# decomposition fails. A closed concave segment chain is valid on a static
		# body and still makes the household island a physical boundary.
		var segments := PackedVector2Array()
		for index in collision_boundary.size():
			segments.append(collision_boundary[index])
			segments.append(collision_boundary[(index + 1) % collision_boundary.size()])
		var boundary_shape := ConcavePolygonShape2D.new()
		boundary_shape.segments = segments
		var boundary_collision := CollisionShape2D.new()
		boundary_collision.name = "BoundaryCollision"
		boundary_collision.shape = boundary_shape
		barrier.add_child(boundary_collision)
		barrier.set_meta("collision_boundary_polygon", collision_boundary)
		barrier.set_meta("rim_contact_offset", ISLAND_TEXTURED_RIM_WIDTH * 0.5)
		root.set_meta("island_invalid_polygon", collision_boundary)
	else:
		var barrier_collision := CollisionPolygon2D.new()
		barrier_collision.polygon = expanded
		barrier.add_child(barrier_collision)
	if spec.get("seed_obstacles", false):
		_build_raised_island_rim(barrier, spec, expanded)

	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point: Vector2 in region:
		min_point = Vector2(minf(min_point.x, point.x), minf(min_point.y, point.y))
		max_point = Vector2(maxf(max_point.x, point.x), maxf(max_point.y, point.y))

	var visual := Polygon2D.new()
	visual.name = "IslandProp"
	visual.z_index = -9
	visual.polygon = region
	var material_texture := String(spec.get("island_material_texture", ""))
	var prop_texture := material_texture if not material_texture.is_empty() else String(spec.get("prop_texture", ""))
	var texture := load(prop_texture) as Texture2D if not prop_texture.is_empty() else null
	if texture:
		# Transparent artwork margins must not make the solid island look hollow.
		_add_polygon(root, "IslandMaterial", region, spec["island"], -9)
		_mark_solid_visual(root.get_node("IslandMaterial") as Polygon2D, "", &"raised_island")
		visual.texture = texture
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		visual.modulate = Color(1.2, 1.2, 1.2)
		var uvs := PackedVector2Array()
		if not material_texture.is_empty():
			visual.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			visual.modulate = Color.WHITE
			var period: Vector2 = spec.get("island_material_world_size", DEFAULT_FLOOR_TILE_WORLD_SIZE)
			for point: Vector2 in region:
				uvs.append(point / period * texture.get_size())
		else:
			for point: Vector2 in region:
				uvs.append(Vector2(
					(point.x - min_point.x) / maxf(max_point.x - min_point.x, 1.0),
					(point.y - min_point.y) / maxf(max_point.y - min_point.y, 1.0)
				) * texture.get_size())
		visual.uv = uvs
	else:
		visual.color = spec["island"]
	_mark_solid_visual(visual, prop_texture, &"raised_island")
	root.add_child(visual)
	if spec.get("seed_obstacles", false):
		await _add_island_rim_landmarks(root, spec, expanded, centerline, stage)


static func _build_raised_island_rim(parent: StaticBody2D, spec: Dictionary, points: PackedVector2Array) -> void:
	var face := Line2D.new()
	face.name = "SideFace"
	face.points = points
	face.closed = true
	face.width = ISLAND_SIDE_FACE_WIDTH
	face.position = SHADOW_DIRECTION * 10.0
	face.default_color = (spec.get("rim_dark", Color("3f2a22")) as Color).darkened(0.28)
	face.joint_mode = Line2D.LINE_JOINT_ROUND
	face.antialiased = true
	face.z_index = -8
	face.set_meta("backs_collision", true)
	_mark_solid_visual(face, "", &"raised_island_rim")
	parent.add_child(face)

	var textured := Line2D.new()
	textured.name = "TexturedRim"
	textured.points = points
	textured.closed = true
	textured.width = ISLAND_TEXTURED_RIM_WIDTH
	textured.default_color = Color(0.9, 0.9, 0.9)
	textured.joint_mode = Line2D.LINE_JOINT_ROUND
	textured.antialiased = true
	textured.z_index = -7
	var edge_texture_path := String(spec.get("edge_texture", ""))
	var edge_texture := load(edge_texture_path) as Texture2D if not edge_texture_path.is_empty() else null
	if edge_texture:
		textured.texture = edge_texture
		textured.texture_mode = Line2D.LINE_TEXTURE_TILE
		textured.set_meta("asset_path", edge_texture_path)
	textured.set_meta("backs_collision", true)
	_mark_solid_visual(textured, edge_texture_path, &"raised_island_rim")
	parent.add_child(textured)

	var lip := Line2D.new()
	lip.name = "TopLip"
	lip.points = points
	lip.closed = true
	lip.width = ISLAND_TOP_LIP_WIDTH
	lip.default_color = spec.get("rim_highlight", Color("ead6aa", 0.76))
	lip.joint_mode = Line2D.LINE_JOINT_ROUND
	lip.antialiased = true
	lip.z_index = -5
	lip.set_meta("backs_collision", true)
	_mark_solid_visual(lip, "", &"raised_island_rim")
	parent.add_child(lip)


static func _add_island_rim_landmarks(root: Node2D, spec: Dictionary, boundary: PackedVector2Array, centerline: PackedVector2Array, stage: Callable = Callable()) -> void:
	var assets: Array = spec.get("island_fill_textures", [])
	if assets.is_empty() or boundary.size() < 12:
		return
	var container := Node2D.new()
	container.name = "IslandRimLandmarks"
	container.set_meta("placed_count", 3)
	root.add_child(container)
	var seed := _mix_seed(int(spec.get("dressing_seed", spec.get("requested_seed", spec.get("seed", 0)))), "island_rim_landmarks")
	var offset := posmod(seed, boundary.size())
	for landmark_index in 3:
		if stage.is_valid():
			await stage.call("Building physical track boundaries")
		var boundary_index := posmod(offset + int(round(float(landmark_index) * float(boundary.size()) / 3.0)), boundary.size())
		var boundary_point := boundary[boundary_index]
		var center_sample: Vector2 = _closest_point_on_loop(boundary_point, centerline)["position"]
		var inward := (boundary_point - center_sample).normalized()
		var position := boundary_point + inward * 22.0
		var next_point := boundary[(boundary_index + 1) % boundary.size()]
		var texture_path := String(assets[posmod(seed + landmark_index * 5, assets.size())])
		_add_generated_prop(container, "Landmark%02d" % landmark_index, position, texture_path, (next_point - boundary_point).angle(), &"island_rim", &"few", landmark_index, 0.72)


static func _build_generated_outer_boundary_visuals(
	root: Node2D,
	spec: Dictionary,
	centerline: PackedVector2Array,
	inner_boundary: PackedVector2Array,
	outer_boundary: PackedVector2Array,
	room_polygon: PackedVector2Array,
	moments: Dictionary
) -> void:
	var assets: Dictionary = spec.get("generated_boundary", {})
	var section_path := String(assets.get("section", ""))
	var section_paths: Array = assets.get("sections", [section_path])
	var accent_path := String(assets.get("accent", ""))
	var section_textures: Array[Texture2D] = []
	for candidate_path: String in section_paths:
		var candidate_texture := load(candidate_path) as Texture2D
		if candidate_texture:
			section_textures.append(candidate_texture)
	var accent_texture := load(accent_path) as Texture2D if not accent_path.is_empty() else null
	if section_textures.is_empty() or accent_texture == null:
		push_error("TrackBuilderCore: generated boundary assets are missing")
		return
	var container := Node2D.new()
	container.name = "GeneratedOuterBoundaryVisuals"
	container.set_meta("section_asset", section_path)
	container.set_meta("section_assets", section_paths)
	container.set_meta("accent_asset", accent_path)
	container.set_meta("corridor_clearance", HALF_WIDTH)
	root.add_child(container)

	# Compose sparse runs instead of lining the whole course. Every seed gets
	# stretches with no furniture, one-sided stretches on each edge, and a small
	# number of both-sided moments. Rotating and mirroring the authored pattern
	# keeps that hierarchy deterministic without reading like a repeating fence.
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix_seed(int(spec.get("dressing_seed", spec["requested_seed"])), "boundary_runs:%s" % String(spec["story_id"]))
	var base_modes: Array[StringName] = [&"both", &"inner", &"both", &"outer", &"both", &"both", &"both", &"none"]
	var mode_offset := rng.randi_range(0, base_modes.size() - 1)
	var swap_sides := rng.randf() < 0.5
	var run_modes: Array[StringName] = []
	var section_count := 0
	var outer_section_count := 0
	var inner_section_count := 0
	var one_sided_runs := 0
	var both_sided_runs := 0
	var empty_runs := 0
	var outer_runs := 0
	var inner_runs := 0
	for run_index in base_modes.size():
		var planned_mode: StringName = base_modes[(run_index + mode_offset) % base_modes.size()]
		var run_center := int(round((float(run_index) + 0.5) * float(centerline.size()) / float(base_modes.size()))) % centerline.size()
		if swap_sides:
			if planned_mode == &"outer":
				planned_mode = &"inner"
			elif planned_mode == &"inner":
				planned_mode = &"outer"
		var run_outer_sections := 0
		var run_inner_sections := 0
		if planned_mode != &"none":
			var run_half_span := rng.randi_range(7, 8)
			for sample_offset in range(-run_half_span, run_half_span + 1, 3):
				var centerline_index := posmod(run_center + sample_offset, centerline.size())
				if _cyclic_index_distance(centerline_index, 0, centerline.size()) < 14:
					continue
				if planned_mode in [&"outer", &"both"]:
					if _add_generated_boundary_section(container, section_textures, centerline, outer_boundary, room_polygon, centerline_index, run_index, &"outer", outer_section_count):
						outer_section_count += 1
						run_outer_sections += 1
						section_count += 1
				if planned_mode in [&"inner", &"both"]:
					if _add_generated_boundary_section(container, section_textures, centerline, inner_boundary, room_polygon, centerline_index, run_index, &"inner", inner_section_count):
						inner_section_count += 1
						run_inner_sections += 1
						section_count += 1
			if planned_mode in [&"outer", &"both"] and run_outer_sections == 0:
				if _add_generated_boundary_run_fallback(container, section_textures, centerline, outer_boundary, room_polygon, run_center, run_index, &"outer", outer_section_count):
					outer_section_count += 1
					run_outer_sections += 1
					section_count += 1
			if planned_mode in [&"inner", &"both"] and run_inner_sections == 0:
				if _add_generated_boundary_run_fallback(container, section_textures, centerline, inner_boundary, room_polygon, run_center, run_index, &"inner", inner_section_count):
					inner_section_count += 1
					run_inner_sections += 1
					section_count += 1
			# A tight room edge can make one requested side physically impossible at
			# the full apron margin. Preserve the authored one-sided beat on the safe
			# edge rather than pulling its collider back into the driving corridor.
			if planned_mode == &"outer" and run_outer_sections == 0:
				if _add_generated_boundary_run_fallback(container, section_textures, centerline, inner_boundary, room_polygon, run_center, run_index, &"inner", inner_section_count):
					inner_section_count += 1
					run_inner_sections += 1
					section_count += 1
			elif planned_mode == &"inner" and run_inner_sections == 0:
				if _add_generated_boundary_run_fallback(container, section_textures, centerline, outer_boundary, room_polygon, run_center, run_index, &"outer", outer_section_count):
					outer_section_count += 1
					run_outer_sections += 1
					section_count += 1
		var actual_mode := &"both" if run_outer_sections > 0 and run_inner_sections > 0 else (&"outer" if run_outer_sections > 0 else (&"inner" if run_inner_sections > 0 else &"none"))
		run_modes.append(actual_mode)
		if actual_mode == &"none":
			empty_runs += 1
			# A flat ground hint gives the single open sector texture without
			# turning it into another barrier run.
			_add_boundary_worn_hint(container, centerline, outer_boundary if rng.randf() > 0.5 else inner_boundary, run_center, room_polygon)
		elif actual_mode == &"both":
			both_sided_runs += 1
		else:
			one_sided_runs += 1
		if actual_mode in [&"outer", &"both"]:
			outer_runs += 1
		if actual_mode in [&"inner", &"both"]:
			inner_runs += 1

	var accent_count := 0
	var corners: PackedInt32Array = moments.get("corners", PackedInt32Array())
	for slot in range(corners.size() - 1, -1, -1):
		if accent_count >= 2 or slot % 2 != 0:
			continue
		var preferred_index := int(corners[slot])
		if _cyclic_index_distance(preferred_index, 0, centerline.size()) < 18:
			continue
		var accent_scale := Vector2(160.0 / accent_texture.get_width(), 70.0 / accent_texture.get_height())
		var accent_footprint := _texture_collision_footprint(accent_texture, &"convex", true)
		var accent_size: Vector2 = (accent_footprint["size"] as Vector2) * accent_scale + Vector2.ONE * 2.0
		var preferred_side := &"outer" if (slot + mode_offset) % 3 != 0 else &"inner"
		var placement := {}
		for index_offset: int in [0, -3, 3, -6, 6, -9, 9]:
			var index := posmod(preferred_index + index_offset, centerline.size())
			for side: StringName in [preferred_side, &"inner" if preferred_side == &"outer" else &"outer"]:
				var boundary := outer_boundary if side == &"outer" else inner_boundary
				var boundary_sample := _closest_point_on_loop(centerline[index], boundary)
				var boundary_index := int(boundary_sample["index"])
				var boundary_position: Vector2 = boundary_sample["position"]
				var tangent := (boundary[(boundary_index + 1) % boundary.size()] - boundary[boundary_index]).normalized()
				var away_from_track := (boundary_position - centerline[index]).normalized()
				var position := boundary_position + away_from_track * 8.0
				position = _push_footprint_outside_corridor(position, centerline, away_from_track, accent_size, tangent.angle())
				position = _advance_footprint_outside_corridor(position, centerline, away_from_track, accent_size, tangent.angle())
				position = _pull_inside_room(position, centerline, room_polygon)
				if (
					_oriented_rect_inside_polygon(position, accent_size, tangent.angle(), room_polygon)
					and _line_sweep_clears_footprint(centerline, position, accent_size, &"rect", tangent.angle(), HALF_WIDTH + APRON_COLLIDER_CLEARANCE)
				):
					placement = {"index": index, "side": side, "position": position, "rotation": tangent.angle()}
					break
			if not placement.is_empty():
				break
		if placement.is_empty():
			continue
		var index := int(placement["index"])
		var side := StringName(placement["side"])
		var position: Vector2 = placement["position"]
		var accent_body := StaticBody2D.new()
		accent_body.name = "CornerAccent%02d" % accent_count
		accent_body.position = position
		accent_body.rotation = float(placement["rotation"])
		accent_body.collision_layer = 16
		accent_body.z_index = -3
		accent_body.set_meta("boundary_kind", &"corner_mouth_accent")
		accent_body.set_meta("boundary_side", side)
		accent_body.set_meta("centerline_index", index)
		accent_body.set_meta("footprint_size", accent_size)
		_mark_solid_body(accent_body, accent_path, &"boundary_prop")
		container.add_child(accent_body)
		var accent_offset := _add_texture_collision(accent_body, accent_texture, accent_scale, &"convex", true, 2.0)
		_add_directional_shadow(accent_body, accent_path, 160.0, 1.0, accent_size)
		var accent_sprite := Sprite2D.new()
		accent_sprite.name = "Sprite"
		accent_sprite.texture = accent_texture
		accent_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		accent_sprite.scale = accent_scale
		accent_sprite.position = -accent_offset
		_mark_solid_visual(accent_sprite, accent_path, &"boundary_prop")
		accent_body.add_child(accent_sprite)
		accent_count += 1
	container.set_meta("section_count", section_count)
	container.set_meta("outer_section_count", outer_section_count)
	container.set_meta("inner_section_count", inner_section_count)
	container.set_meta("accent_count", accent_count)
	container.set_meta("run_modes", run_modes)
	container.set_meta("one_sided_run_count", one_sided_runs)
	container.set_meta("both_sided_run_count", both_sided_runs)
	container.set_meta("empty_run_count", empty_runs)
	container.set_meta("outer_run_count", outer_runs)
	container.set_meta("inner_run_count", inner_runs)
	container.set_meta("outer_accent_coverage", float(outer_runs) / 8.0 * 0.72)
	container.set_meta("inner_accent_coverage", float(inner_runs) / 8.0 * 0.72)
	root.set_meta("generated_outer_boundary", {
		"section_asset": section_path,
		"section_assets": section_paths,
		"accent_asset": accent_path,
		"section_count": section_count,
		"outer_section_count": outer_section_count,
		"inner_section_count": inner_section_count,
		"accent_count": accent_count,
		"run_modes": run_modes,
	})


static func _add_generated_boundary_section(
	container: Node2D,
	textures: Array[Texture2D],
	centerline: PackedVector2Array,
	boundary: PackedVector2Array,
	room_polygon: PackedVector2Array,
	centerline_index: int,
	run_index: int,
	side: StringName,
	side_index: int
) -> bool:
	var texture := textures[posmod(run_index + side_index, textures.size())]
	var boundary_sample := _closest_point_on_loop(centerline[centerline_index], boundary)
	var boundary_index := int(boundary_sample["index"])
	var boundary_position: Vector2 = boundary_sample["position"]
	var tangent := (boundary[(boundary_index + 1) % boundary.size()] - boundary[boundary_index]).normalized()
	var away_from_track := (boundary_position - centerline[centerline_index]).normalized()
	var sprite_scale := Vector2(156.0 / texture.get_width(), 56.0 / texture.get_height())
	var footprint := _texture_collision_footprint(texture, &"convex", true)
	var footprint_size: Vector2 = (footprint["size"] as Vector2) * sprite_scale
	var position := boundary_position + away_from_track * 8.0
	position = _push_footprint_outside_corridor(position, centerline, away_from_track, footprint_size, tangent.angle())
	position = _advance_footprint_outside_corridor(position, centerline, away_from_track, footprint_size, tangent.angle())
	position = _pull_inside_room(position, centerline, room_polygon)
	var nearest_centerline_sample := _closest_point_on_loop(position, centerline)
	var nearest_centerline: Vector2 = nearest_centerline_sample["position"]
	var run_center := int(round((float(run_index) + 0.5) * float(centerline.size()) / 8.0)) % centerline.size()
	if (
		position.distance_to(nearest_centerline) < HALF_WIDTH
		or not _oriented_rect_inside_polygon(position, footprint_size, tangent.angle(), room_polygon)
		or not _line_sweep_clears_footprint(centerline, position, footprint_size, &"rect", tangent.angle(), HALF_WIDTH + APRON_COLLIDER_CLEARANCE)
		or _cyclic_index_distance(int(nearest_centerline_sample["index"]), run_center, centerline.size()) >= centerline.size() / 16
	):
		return false
	var body := StaticBody2D.new()
	body.name = "%sSection%03d" % [String(side).capitalize(), side_index]
	body.position = position
	body.rotation = tangent.angle()
	body.collision_layer = 16
	body.z_index = -4
	body.set_meta("boundary_kind", &"partial_section")
	body.set_meta("boundary_side", side)
	body.set_meta("run_index", run_index)
	body.set_meta("centerline_index", centerline_index)
	body.set_meta("asset_path", texture.resource_path)
	body.set_meta("footprint_size", footprint_size)
	body.set_meta("visible_collision_backing", &"rail_sprite")
	_mark_solid_body(body, texture.resource_path, &"rail")
	container.add_child(body)
	var offset := _add_texture_collision(body, texture, sprite_scale, &"convex", true, 0.0)
	(body.get_node("AssetCollision") as CollisionShape2D).name = "RailCollision"
	_add_directional_shadow(body, texture.resource_path, 156.0, 1.0, footprint_size)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.scale = sprite_scale
	sprite.position = -offset
	_mark_solid_visual(sprite, texture.resource_path, &"rail")
	body.add_child(sprite)
	return true


static func _add_generated_boundary_run_fallback(
	container: Node2D,
	textures: Array[Texture2D],
	centerline: PackedVector2Array,
	boundary: PackedVector2Array,
	room_polygon: PackedVector2Array,
	run_center: int,
	run_index: int,
	side: StringName,
	side_index: int
) -> bool:
	# The primary samples preserve authored spacing. Search nearest-first only when
	# a required side had no valid room/corridor placement at those samples.
	var sector_half_span := maxi(1, centerline.size() / 16 - 1)
	for distance in range(0, sector_half_span + 1):
		for direction in [-1, 1]:
			if distance == 0 and direction < 0:
				continue
			var centerline_index := posmod(run_center + distance * direction, centerline.size())
			if _cyclic_index_distance(centerline_index, 0, centerline.size()) < 14:
				continue
			if _add_generated_boundary_section(container, textures, centerline, boundary, room_polygon, centerline_index, run_index, side, side_index):
				return true
	return false


static func _push_outside_corridor(position: Vector2, centerline: PackedVector2Array, fallback_direction: Vector2) -> Vector2:
	var nearest: Vector2 = _closest_point_on_loop(position, centerline)["position"]
	var direction := (position - nearest).normalized()
	if direction.is_zero_approx():
		direction = fallback_direction
	var clearance := position.distance_to(nearest)
	return position + direction * maxf(HALF_WIDTH + 8.0 - clearance, 0.0)


static func _push_footprint_outside_corridor(
		position: Vector2,
		centerline: PackedVector2Array,
		fallback_direction: Vector2,
		footprint_size: Vector2,
		rotation: float
) -> Vector2:
	var nearest: Vector2 = _closest_point_on_loop(position, centerline)["position"]
	var direction := (position - nearest).normalized()
	if direction.is_zero_approx():
		direction = fallback_direction
	var local_direction := direction.rotated(-rotation)
	var half_size := footprint_size * 0.5
	var footprint_extent := absf(local_direction.x) * half_size.x + absf(local_direction.y) * half_size.y
	var required := HALF_WIDTH + APRON_COLLIDER_CLEARANCE + footprint_extent
	return position + direction * maxf(required - position.distance_to(nearest), 0.0)


static func _advance_footprint_outside_corridor(
		position: Vector2,
		centerline: PackedVector2Array,
		fallback_direction: Vector2,
		footprint_size: Vector2,
		rotation: float
) -> Vector2:
	var result := position
	var direction := fallback_direction.normalized()
	for _attempt in 12:
		if _line_sweep_clears_footprint(centerline, result, footprint_size, &"rect", rotation, HALF_WIDTH + APRON_COLLIDER_CLEARANCE):
			break
		var nearest: Vector2 = _closest_point_on_loop(result, centerline)["position"]
		var updated_direction := (result - nearest).normalized()
		if not updated_direction.is_zero_approx():
			direction = updated_direction
		result += direction * 8.0
	return result


static func _pull_inside_room(position: Vector2, centerline: PackedVector2Array, room_polygon: PackedVector2Array) -> Vector2:
	if Geometry2D.is_point_in_polygon(position, room_polygon):
		return position
	var nearest: Vector2 = _closest_point_on_loop(position, centerline)["position"]
	var offset := position - nearest
	var direction := offset.normalized()
	for clearance in range(int(floor(offset.length())), int(HALF_WIDTH) - 1, -2):
		var candidate := nearest + direction * float(clearance)
		var candidate_nearest: Vector2 = _closest_point_on_loop(candidate, centerline)["position"]
		if Geometry2D.is_point_in_polygon(candidate, room_polygon) and candidate.distance_to(candidate_nearest) >= HALF_WIDTH:
			return candidate
	return position


static func _closest_point_on_loop(point: Vector2, loop: PackedVector2Array) -> Dictionary:
	var result := {"index": 0, "position": loop[0]}
	var nearest_distance := INF
	for index in loop.size():
		var from := loop[index]
		var to := loop[(index + 1) % loop.size()]
		var segment := to - from
		var fraction := clampf((point - from).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
		var candidate := from + segment * fraction
		var distance := point.distance_squared_to(candidate)
		if distance < nearest_distance:
			nearest_distance = distance
			result = {"index": index, "position": candidate}
	return result


static func _island_region(room_polygon: PackedVector2Array, ribbon: PackedVector2Array, hint_polygon: PackedVector2Array) -> PackedVector2Array:
	var pieces: Array[PackedVector2Array] = Geometry2D.clip_polygons(room_polygon, ribbon)
	var hint_centroid := Vector2.ZERO
	for point: Vector2 in hint_polygon:
		hint_centroid += point
	hint_centroid /= float(hint_polygon.size())
	var best := PackedVector2Array()
	var best_score := -1.0
	for piece: PackedVector2Array in pieces:
		var score := 0.0
		for sample in 40:
			var index := int(float(sample) * float(hint_polygon.size()) / 40.0)
			var hint_point: Vector2 = hint_polygon[index].lerp(hint_centroid, 0.3)
			if Geometry2D.is_point_in_polygon(hint_point, piece):
				score += 1.0
		if score > best_score:
			best_score = score
			best = piece
	return best


static func _rounded_rect_points(center: Vector2, size: Vector2, radius: float, corner_segments: int) -> PackedVector2Array:
	return TRACK_BUILDER_GEOMETRY.rounded_rect_points(center, size, radius, corner_segments)


static func _polygon_area(points: PackedVector2Array) -> float:
	return TRACK_BUILDER_GEOMETRY.polygon_area(points)


static func _outset_polygon(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	return TRACK_BUILDER_GEOMETRY.outset_polygon(points, distance)


static func _simple_island_loop(points: PackedVector2Array) -> PackedVector2Array:
	return TRACK_BUILDER_GEOMETRY.simple_island_loop(points)


static func _simple_boundary_loop(points: PackedVector2Array, centerline: PackedVector2Array) -> PackedVector2Array:
	return TRACK_BUILDER_GEOMETRY.simple_boundary_loop(points, centerline)


static func _simple_inner_boundary_loop(points: PackedVector2Array, centerline: PackedVector2Array) -> PackedVector2Array:
	return TRACK_BUILDER_GEOMETRY.simple_inner_boundary_loop(points, centerline)


static func _simple_corridor_boundary_loop(_points: PackedVector2Array, centerline: PackedVector2Array, select_outer: bool) -> PackedVector2Array:
	return TRACK_BUILDER_GEOMETRY.simple_corridor_boundary_loop(_points, centerline, select_outer)


static func _deduplicate_loop(points: PackedVector2Array) -> PackedVector2Array:
	return TRACK_BUILDER_GEOMETRY.deduplicate_loop(points)


static func _has_self_intersection(points: PackedVector2Array) -> bool:
	return TRACK_BUILDER_GEOMETRY.has_self_intersection(points)


static func _loop_hugs_centerline(loop: PackedVector2Array, centerline: PackedVector2Array) -> bool:
	return TRACK_BUILDER_GEOMETRY.loop_hugs_centerline(loop, centerline)


static func _arc_lengths(centerline: PackedVector2Array) -> PackedFloat32Array:
	return TRACK_BUILDER_GEOMETRY.arc_lengths(centerline)


static func _sample_at_arc(centerline: PackedVector2Array, arc: PackedFloat32Array, target: float) -> Vector2:
	return TRACK_BUILDER_GEOMETRY.sample_at_arc(centerline, arc, target)


static func _tangent_at_arc(centerline: PackedVector2Array, arc: PackedFloat32Array, target: float) -> Vector2:
	return TRACK_BUILDER_GEOMETRY.tangent_at_arc(centerline, arc, target)


static func _rect_points(center: Vector2, size: Vector2) -> PackedVector2Array:
	return TRACK_BUILDER_GEOMETRY.rect_points(center, size)


static func _add_polygon(parent: Node, node_name: String, points: PackedVector2Array, color: Color, z: int) -> void:
	var polygon := Polygon2D.new()
	polygon.name = node_name
	polygon.polygon = points
	polygon.color = color
	polygon.z_index = z
	parent.add_child(polygon)


static func _add_finish_checker(parent: Node2D, finish: Vector2, tangent: Vector2) -> void:
	var along := tangent.normalized()
	var across := along.rotated(PI * 0.5)
	var columns := 6
	var rows := 2
	var cell_width := HALF_WIDTH * 2.0 / float(columns)
	var cell_depth := 36.0
	var color_counts := {&"White": 0, &"Black": 0}
	for row in rows:
		for column in columns:
			var color_key := &"White" if (row + column) % 2 == 0 else &"Black"
			var color_index := int(color_counts[color_key])
			var node_name := "StartFinish%s" % String(color_key) if color_index == 0 else "StartFinish%sCell%02d" % [String(color_key), color_index]
			var center := finish
			center += along * (float(row) - float(rows - 1) * 0.5) * cell_depth
			center += across * (float(column) - float(columns - 1) * 0.5) * cell_width
			var half_along := along * cell_depth * 0.5
			var half_across := across * cell_width * 0.5
			var cell := Polygon2D.new()
			cell.name = node_name
			cell.polygon = PackedVector2Array([
				center - half_along - half_across,
				center + half_along - half_across,
				center + half_along + half_across,
				center - half_along + half_across,
			])
			cell.color = Color("f5eec8") if color_key == &"White" else Color("0d0f14")
			cell.z_index = -7 if color_key == &"White" else -6
			cell.set_meta("checker_color", color_key)
			cell.set_meta("checker_cell", row * columns + column)
			_mark_flat_visual(cell, "", &"checker")
			parent.add_child(cell)
			color_counts[color_key] = color_index + 1
	for color_key: StringName in color_counts:
		var first := parent.get_node("StartFinish%s" % String(color_key))
		first.set_meta("checker_cell_count", int(color_counts[color_key]))
		first.set_meta("corridor_span", HALF_WIDTH * 2.0)
		first.set_meta("bidirectional", true)


static func _add_wall_segment(parent: Node, node_name: String, position: Vector2, length: float, rotation: float, edge_texture_path: String) -> void:
	var wall := StaticBody2D.new()
	wall.name = node_name
	wall.position = position
	wall.rotation = rotation
	wall.collision_layer = 2
	_mark_solid_body(wall, edge_texture_path, &"room_wall")
	parent.add_child(wall)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(length + 60.0, 50.0)
	var cs := CollisionShape2D.new()
	cs.shape = shape
	wall.add_child(cs)
	_record_shape_probe_points(wall, Vector2.ZERO, shape.size, &"rect")
	var visual := Polygon2D.new()
	visual.name = "Visual"
	visual.polygon = _rect_points(Vector2.ZERO, Vector2(length + 60.0, 50.0))
	visual.color = Color("0e1524")
	_mark_solid_visual(visual, edge_texture_path, &"room_wall")
	wall.add_child(visual)
	var side_face := Polygon2D.new()
	side_face.name = "SideFace"
	side_face.polygon = _rect_points(Vector2(0.0, -14.0), Vector2(length + 60.0, 22.0))
	side_face.color = Color("262e3a")
	_mark_solid_visual(side_face, "", &"room_wall")
	wall.add_child(side_face)
	var edge_texture_side := load(edge_texture_path) as Texture2D
	if edge_texture_side:
		var side_strip := Sprite2D.new()
		side_strip.name = "SideStrip"
		side_strip.texture = edge_texture_side
		side_strip.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		side_strip.position = Vector2(0.0, -14.0)
		var side_tiles := maxi(1, int(ceil((length + 60.0) / ROOM_EDGE_TILE_WORLD_LENGTH)))
		side_strip.region_enabled = true
		side_strip.region_rect = Rect2(0, 0, edge_texture_side.get_width() * side_tiles, edge_texture_side.get_height())
		side_strip.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		side_strip.scale = Vector2((length + 60.0) / (edge_texture_side.get_width() * float(side_tiles)), 34.0 / edge_texture_side.get_height())
		side_strip.modulate = Color(0.85, 0.85, 0.85)
		side_strip.set_meta("asset_path", edge_texture_path)
		VISUAL_ROLE_CONTRACT.assign(side_strip, VISUAL_ROLE_SOLID)
		wall.add_child(side_strip)
	var top_lip := Polygon2D.new()
	top_lip.name = "TopLip"
	top_lip.polygon = _rect_points(Vector2(0.0, -28.0), Vector2(length + 60.0, 5.0))
	top_lip.color = Color("e8d9b8", 0.85)
	_mark_solid_visual(top_lip, "", &"room_wall")
	wall.add_child(top_lip)
	var edge_texture := load(edge_texture_path) as Texture2D
	if edge_texture:
		var tile_count := maxi(1, int(ceil((length + 60.0) / ROOM_EDGE_TILE_WORLD_LENGTH)))
		for tile in tile_count:
			var strip := Sprite2D.new()
			strip.name = "EdgeStrip"
			strip.texture = edge_texture
			strip.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			var offset := (float(tile) - float(tile_count - 1) * 0.5) * ((length + 60.0) / float(tile_count))
			strip.position = Vector2(offset, 0.0)
			strip.scale = Vector2((length + 60.0) / (edge_texture.get_width() * float(tile_count)), 50.0 / edge_texture.get_height())
			strip.set_meta("asset_path", edge_texture_path)
			VISUAL_ROLE_CONTRACT.assign(strip, VISUAL_ROLE_SOLID)
			wall.add_child(strip)


static func _gate_span_endpoints(sample: Vector2, tangent: Vector2, room_polygon: PackedVector2Array, island_polygon: PackedVector2Array) -> PackedVector2Array:
	var normal := tangent.rotated(PI * 0.5).normalized()
	var positive_island := _nearest_gate_boundary(sample, normal, PackedVector2Array(), island_polygon)
	var negative_island := _nearest_gate_boundary(sample, -normal, PackedVector2Array(), island_polygon)
	var positive_distance := (positive_island - sample).dot(normal)
	var negative_distance := (negative_island - sample).dot(-normal)
	var inner_direction := normal if positive_distance <= negative_distance else -normal
	var outer_direction := -inner_direction
	return PackedVector2Array([
		_corridor_gate_endpoint(sample, inner_direction, room_polygon, island_polygon),
		_nearest_gate_boundary(sample, outer_direction, room_polygon, island_polygon),
	])


static func _corridor_gate_endpoint(sample: Vector2, direction: Vector2, room_polygon: PackedVector2Array, island_polygon: PackedVector2Array) -> Vector2:
	var boundary := _nearest_gate_boundary(sample, direction, room_polygon, island_polygon)
	var projected := (boundary - sample).dot(direction.normalized())
	return sample + direction.normalized() * minf(projected, HALF_WIDTH)


static func _nearest_gate_boundary(sample: Vector2, direction: Vector2, room_polygon: PackedVector2Array, island_polygon: PackedVector2Array) -> Vector2:
	var ray_end := sample + direction * 12000.0
	var nearest := ray_end
	var nearest_distance := INF
	for polygon: PackedVector2Array in [island_polygon, room_polygon]:
		for edge_index in polygon.size():
			var intersection: Variant = Geometry2D.segment_intersects_segment(sample, ray_end, polygon[edge_index], polygon[(edge_index + 1) % polygon.size()])
			if not intersection is Vector2:
				continue
			var point := intersection as Vector2
			var projected := (point - sample).dot(direction)
			if projected > 0.5 and projected < nearest_distance:
				nearest = point
				nearest_distance = projected
	return nearest


static func _add_gate_posts(root: Node2D, spec: Dictionary, sample: Vector2, tangent: Vector2, gate_index: int) -> void:
	var container := root.get_node_or_null("GatePosts") as Node2D
	if container == null:
		container = Node2D.new()
		container.name = "GatePosts"
		container.set_meta("placed_count", 0)
		root.add_child(container)
	var boundary_assets: Dictionary = spec.get("generated_boundary", {})
	var asset_paths: Array = boundary_assets.get("sections", [boundary_assets.get("section", "")])
	if asset_paths.is_empty():
		return
	var normal := tangent.rotated(PI * 0.5).normalized()
	for side in [-1, 1]:
		var asset_path := String(asset_paths[posmod(gate_index * 2 + (1 if side > 0 else 0), asset_paths.size())])
		var texture := load(asset_path) as Texture2D
		if texture == null:
			continue
		var post := StaticBody2D.new()
		post.name = "Gate%02d%s" % [gate_index, "Right" if side > 0 else "Left"]
		var post_size := FINISH_LANDMARK_SIZE if gate_index == 0 else GATE_POST_SIZE
		var post_offset := FINISH_LANDMARK_OFFSET if gate_index == 0 else GATE_POST_OFFSET
		post.position = sample + normal * post_offset * float(side)
		post.rotation = tangent.angle()
		post.collision_layer = 16
		post.z_index = -1 if gate_index == 0 else -2
		post.set_meta("asset_path", asset_path)
		post.set_meta("gate_index", gate_index)
		post.set_meta("visible_collision_backing", &"gate_post_sprite")
		if gate_index == 0:
			post.set_meta("finish_landmark", true)
			post.set_meta("landmark_side", &"right" if side > 0 else &"left")
			post.set_meta("race_directions", PackedStringArray(["forward", "reverse"]))
		_mark_solid_body(post, asset_path, &"gate_post")
		container.add_child(post)
		var sprite_scale := Vector2(post_size.x / texture.get_width(), post_size.y / texture.get_height())
		var footprint := _texture_collision_footprint(texture, &"convex", true)
		var footprint_size: Vector2 = (footprint["size"] as Vector2) * sprite_scale + Vector2.ONE * 2.0
		var offset := _add_texture_collision(post, texture, sprite_scale, &"convex", true, 2.0)
		(post.get_node("AssetCollision") as CollisionShape2D).name = "PostCollision"
		_add_directional_shadow(post, asset_path, GATE_POST_SIZE.x, 1.0, footprint_size)
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.scale = sprite_scale
		sprite.position = -offset
		_mark_solid_visual(sprite, asset_path, &"gate_post")
		post.add_child(sprite)
		container.set_meta("placed_count", int(container.get_meta("placed_count", 0)) + 1)
	if gate_index == 0:
		container.set_meta("finish_landmark_paths", [NodePath("Gate00Left"), NodePath("Gate00Right")])
		container.set_meta("finish_landmark_offset", FINISH_LANDMARK_OFFSET)


static func _add_cp(parent: Node, node_name: String, position: Vector2, rotation: float, index: int, is_finish: bool, recovery_rotation: float, span_endpoints: PackedVector2Array = PackedVector2Array()) -> void:
	var cp := Area2D.new()
	cp.name = node_name
	cp.position = position
	cp.rotation = rotation
	cp.visible = false
	cp.collision_layer = 0
	cp.set_script(CHECKPOINT_SCRIPT)
	cp.add_to_group("track_checkpoints", true)
	cp.set("checkpoint_index", index)
	cp.set("is_finish_line", is_finish)
	cp.set("recovery_rotation", recovery_rotation)
	cp.set("recovery_offset", 70.0)
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	cp.add_child(collision)
	if span_endpoints.size() == 2:
		var forgiving := RectangleShape2D.new()
		forgiving.size = Vector2(GATE_SENSOR_THICKNESS, span_endpoints[0].distance_to(span_endpoints[1]) + 8.0)
		collision.shape = forgiving
		var checkpoint_transform := Transform2D(rotation, position)
		collision.position = checkpoint_transform.affine_inverse() * span_endpoints[0].lerp(span_endpoints[1], 0.5)
		cp.set_meta("sensor_endpoints", span_endpoints)
		cp.set_meta("sensor_inner_endpoint", span_endpoints[0])
		cp.set_meta("sensor_outer_endpoint", span_endpoints[1])
		cp.set_meta("sensor_span", span_endpoints[0].distance_to(span_endpoints[1]))
		cp.set_meta("sensor_asymmetric_span", true)
	elif not is_finish:
		var forgiving := RectangleShape2D.new()
		forgiving.size = Vector2(70.0, 300.0)
		collision.shape = forgiving
	else:
		var finish_shape := RectangleShape2D.new()
		finish_shape.size = Vector2(34.0, 280.0)
		collision.shape = finish_shape
	parent.add_child(cp)


static func _add_grid(parent: Node, node_name: String, rotation: float, positions: Array, rotations: Array = []) -> void:
	var grid := Node2D.new()
	grid.name = node_name
	parent.add_child(grid)
	for index in positions.size():
		var marker := Node2D.new()
		marker.name = str(index)
		marker.position = positions[index]
		marker.rotation = float(rotations[index]) if index < rotations.size() else rotation
		grid.add_child(marker)


static func _scatter_decals(root: Node2D, spec: Dictionary, room_polygon: PackedVector2Array, corridor: PackedVector2Array, rng: RandomNumberGenerator) -> void:
	var decals: Array = spec.get("decals", [])
	if decals.is_empty():
		return
	for decal in 26:
		var position := Vector2(rng.randf_range(-830.0, 830.0), rng.randf_range(-530.0, 530.0))
		if not Geometry2D.is_point_in_polygon(position, room_polygon):
			continue
		if Geometry2D.is_point_in_polygon(position, corridor):
			continue
		var texture_path := String(decals[rng.randi_range(0, decals.size() - 1)])
		var sprite := Sprite2D.new()
		sprite.name = "Decal"
		sprite.texture = load(texture_path) as Texture2D
		if sprite.texture == null:
			sprite.free()
			continue
		sprite.scale = Vector2.ONE * rng.randf_range(0.5, 1.1)
		sprite.rotation = rng.randf_range(0.0, TAU)
		sprite.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(0.4, 0.9))
		sprite.z_index = -15
		_mark_flat_visual(sprite, texture_path, &"floor_decal")
		root.add_child(sprite)


static func _compose_generated_story(
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
	await _build_giant_landmarks(container, giant_spec, centerline, room_polygon, gate_samples, occupied, committed_racing_lines, stage)
	if stage.is_valid():
		await stage.call("Dressing the start area")
	var opening_index := _build_opening_landmark(
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
	await _build_island_story(container, story, spec, centerline, inner_loop, room_polygon, gate_samples, occupied, stage)
	if stage.is_valid():
		await stage.call("Placing track objects")
	_build_track_formation(
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
	_build_track_formation(
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
	_build_corner_landmarks(container, story, spec, moments["corners"], centerline, outer_loop, room_polygon, gate_samples, reserved_unique_assets, occupied)
	if stage.is_valid():
		await stage.call("Dressing the room")
	await _build_room_dressing(container, story, spec, centerline, outer_loop, room_polygon, gate_samples, reserved_unique_assets, occupied, stage)
	if stage.is_valid():
		await stage.call("Adding surface detail")
	await _build_edge_and_apron_decor(container, spec, centerline, room_polygon, gate_samples, occupied, stage)
	if stage.is_valid():
		await stage.call("Preparing grip zones and hazards")
	_build_generated_surfaces(root, container, story, spec, moments, centerline, gate_samples)
	_build_finish_moments(container, centerline)

	var hazard_paths := {}
	var planned_hazard: Dictionary = spec.get("hazard_plan", {})
	var planned_paths: Dictionary = planned_hazard.get("paths", {})
	for direction: String in ["forward", "reverse"]:
		var hazard_index := int(moments["early_conflict_%s" % direction])
		var hazard_path: PackedVector2Array = planned_paths.get(direction, _crossing_path(centerline, hazard_index, 96.0))
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


static func _analyze_track_moments(centerline: PackedVector2Array, gate_samples: PackedVector2Array) -> Dictionary:
	var count := centerline.size()
	var arc_positions := _centerline_arc_positions(centerline)
	var total_length := arc_positions[arc_positions.size() - 1] + centerline[centerline.size() - 1].distance_to(centerline[0])
	var conflict_forward := _pick_conflict_candidate(centerline, gate_samples, arc_positions, total_length, 0.14, 0.23)
	var conflict_reverse := _pick_conflict_candidate(centerline, gate_samples, arc_positions, total_length, 0.77, 0.86)
	var straight_candidates: Array[Dictionary] = []
	var corner_candidates: Array[Dictionary] = []
	for index in range(0, count, 2):
		var turn := _turn_strength(centerline, index, 9)
		var chord := centerline[posmod(index + 16, count)].distance_to(centerline[posmod(index - 16, count)])
		straight_candidates.append({"index": index, "score": chord - turn * 720.0})
		corner_candidates.append({"index": index, "score": turn})
	straight_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["index"]) < int(b["index"]) if is_equal_approx(float(a["score"]), float(b["score"])) else float(a["score"]) > float(b["score"]))
	corner_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["index"]) < int(b["index"]) if is_equal_approx(float(a["score"]), float(b["score"])) else float(a["score"]) > float(b["score"]))

	var longest := _pick_straight_candidate(straight_candidates, centerline, gate_samples, [0], 30)
	var second := _pick_straight_candidate(straight_candidates, centerline, gate_samples, [0, longest], 48)
	var corners := PackedInt32Array()
	for candidate: Dictionary in corner_candidates:
		var index := int(candidate["index"])
		if _cyclic_index_distance(index, 0, count) < 24:
			continue
		if _cyclic_index_distance(index, conflict_forward, count) < 24 or _cyclic_index_distance(index, conflict_reverse, count) < 24:
			continue
		var separated := true
		for chosen: int in corners:
			if _cyclic_index_distance(index, chosen, count) < 38:
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
		var separated := _cyclic_index_distance(fallback, conflict_forward, count) >= 24 and _cyclic_index_distance(fallback, conflict_reverse, count) >= 24
		for chosen: int in corners:
			if _cyclic_index_distance(fallback, chosen, count) < 38:
				separated = false
		if separated:
			corners.append(fallback)
	while corners.size() < 2:
		corners.append(posmod(72 + corners.size() * 96, count))

	var shortcut := int(corners[0])
	var shortcut_gain := -INF
	for corner: int in corners:
		var geometry := _shortcut_lane_geometry(centerline, corner)
		var gain := float(geometry["safe_length"]) - float(geometry["shortcut_length"])
		if gain > shortcut_gain:
			shortcut_gain = gain
			shortcut = corner
	var technical := int(corners[0])
	for corner: int in corners:
		if corner != shortcut:
			technical = corner
			break
	return {
		"opening": 0,
		"early_conflict_forward": conflict_forward,
		"early_conflict_reverse": conflict_reverse,
		"early_conflict_forward_fraction": arc_positions[conflict_forward] / maxf(total_length, 1.0),
		"early_conflict_reverse_fraction": 1.0 - arc_positions[conflict_reverse] / maxf(total_length, 1.0),
		"longest_straight": longest,
		"second_straight": second,
		"corners": corners,
		"shortcut": shortcut,
		"technical": technical,
	}


static func _default_act_for_theme(theme: StringName) -> int:
	match theme:
		&"workshop":
			return 2
		&"office":
			return 3
	return 1


static func _layout_gate_samples(centerline: PackedVector2Array, spec: Dictionary) -> PackedVector2Array:
	var samples := PackedVector2Array()
	var fractions: Array = spec.get("gate_fractions", [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.84])
	var arc := _arc_lengths(centerline)
	var total := arc[arc.size() - 1]
	for gate_index in GATE_COUNT:
		samples.append(_sample_at_arc(centerline, arc, total * float(fractions[gate_index])))
	return samples


static func _centerline_arc_positions(centerline: PackedVector2Array) -> PackedFloat32Array:
	var positions := PackedFloat32Array([0.0])
	for index in range(1, centerline.size()):
		positions.append(positions[index - 1] + centerline[index - 1].distance_to(centerline[index]))
	return positions


static func _pick_conflict_candidate(
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		arc_positions: PackedFloat32Array,
		total_length: float,
		minimum_fraction: float,
		maximum_fraction: float
) -> int:
	var best_index := int(round(float(centerline.size()) * (minimum_fraction + maximum_fraction) * 0.5))
	var best_score := -INF
	for index in range(0, centerline.size(), 2):
		var fraction := arc_positions[index] / maxf(total_length, 1.0)
		if fraction < minimum_fraction or fraction > maximum_fraction:
			continue
		var turn := _turn_strength(centerline, index, 7)
		var chord := centerline[posmod(index + 10, centerline.size())].distance_to(centerline[posmod(index - 10, centerline.size())])
		var gate_clearance := INF
		for gate: Vector2 in gate_samples:
			gate_clearance = minf(gate_clearance, centerline[index].distance_to(gate))
		var score := chord - turn * 540.0 + minf(gate_clearance, 180.0) * 0.35
		if score > best_score or (is_equal_approx(score, best_score) and index < best_index):
			best_score = score
			best_index = index
	return best_index


static func _build_opening_landmark(
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
	var asset_index := posmod(_mix_seed(int(spec.get("dressing_seed", spec["requested_seed"])), "opening_asset"), assets.size())
	var asset_path := String(story.get("opening_asset", assets[asset_index]))
	opening.set_meta("asset_path", asset_path)
	opening.set_meta("semantic_quantity", &"unique")
	opening.set_meta("requested_count", 1)
	var base_radius := _asset_radius(asset_path, 64.0)
	var size_scale := minf(1.0, 72.0 / maxf(base_radius, 1.0))
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
		var tangent := _sample_tangent(centerline, index)
		var outward := (outer_loop[index] - centerline[index]).normalized()
		for placement_attempt in 12:
			var side := 1.0 if placement_attempt % 2 == 0 else -1.0
			var along := tangent * (float(placement_attempt / 4) - 1.0) * 30.0
			var offset := HALF_WIDTH + radius + APRON_COLLIDER_CLEARANCE + float((placement_attempt / 2) % 2) * 12.0
			var candidate := centerline[index] + outward * side * offset + along
			if not _inside_polygon_with_radius(candidate, radius, room_polygon):
				continue
			if _distance_to_centerline(candidate, centerline) < HALF_WIDTH + radius + 7.0:
				continue
			if not _clear_of_points(candidate, gate_samples, 24.0 + radius):
				continue
			if not _clear_of_recovery_lanes(candidate, radius, centerline, gate_samples):
				continue
			if not _clear_of_occupied(candidate, radius, occupied):
				continue
			_add_generated_prop(opening, "Focal", candidate, asset_path, tangent.angle(), &"opening", &"unique", 0, size_scale)
			occupied.append({"position": candidate, "radius": radius})
			selected_index = index
			placed_count = 1
			break
		if placed_count == 1:
			break
	if placed_count == 0:
		var exhaustive := _best_trackside_position(preferred, radius, centerline, outer_loop, room_polygon, gate_samples, occupied)
		if bool(exhaustive["found"]):
			var candidate: Vector2 = exhaustive["position"]
			selected_index = int(exhaustive["index"])
			_add_generated_prop(opening, "Focal", candidate, asset_path, _sample_tangent(centerline, selected_index).angle(), &"opening", &"unique", 0, size_scale)
			occupied.append({"position": candidate, "radius": radius})
			placed_count = 1
	opening.set_meta("centerline_index", selected_index)
	opening.set_meta("placed_count", placed_count)
	return selected_index


static func _pick_straight_candidate(
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
			if _cyclic_index_distance(index, excluded_index, centerline.size()) < minimum_separation:
				allowed = false
				break
		if not allowed or not _clear_of_points(centerline[index], gate_samples, 175.0):
			continue
		return index
	return posmod(minimum_separation * maxi(excluded.size(), 1), centerline.size())


static func _turn_strength(centerline: PackedVector2Array, index: int, span: int) -> float:
	return TRACK_BUILDER_GEOMETRY.turn_strength(centerline, index, span)


static func _cyclic_index_distance(first: int, second: int, count: int) -> int:
	return TRACK_BUILDER_GEOMETRY.cyclic_index_distance(first, second, count)


static func _safe_moment_index(centerline: PackedVector2Array, preferred: int, gate_samples: PackedVector2Array, clearance: float) -> int:
	var count := centerline.size()
	for distance in range(0, 31, 2):
		for direction in [-1, 1]:
			var index := posmod(preferred + distance * direction, count)
			if _cyclic_index_distance(index, 0, count) < 26:
				continue
			if _clear_of_points(centerline[index], gate_samples, clearance):
				return index
	return preferred


static func _build_island_story(
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
	var anchor := _island_anchor(inner_loop, centerline)
	var island_bounds := _polygon_bounds_rect(inner_loop)
	var scene_angle := -PI * 0.5 if island_bounds.size.x > island_bounds.size.y else 0.0
	if _mix_seed(int(spec.get("dressing_seed", spec["requested_seed"])), String(story["id"])) % 2 == 1:
		scene_angle += PI
	var placement_region := &"island"
	var focal_data: Dictionary = story["island"][0]
	var focal_path := String(focal_data["asset"])
	var focal_base_radius := _asset_radius(focal_path, 24.0)
	var focal_scale := minf(1.0, float(focal_data.get("max_radius", 72.0)) / maxf(focal_base_radius, 1.0))
	var focal_radius := focal_base_radius * focal_scale
	var focal_offset: Vector2 = focal_data.get("offset", Vector2.ZERO)
	var focal_preferred := anchor + focal_offset.rotated(scene_angle)
	var island_fit := _best_island_position(focal_preferred, focal_radius, room_polygon, inner_loop, occupied)
	if not bool(island_fit["found"]):
		var apron_fit := _best_offtrack_position(focal_preferred, focal_radius, room_polygon, centerline, gate_samples, occupied)
		if bool(apron_fit["found"]):
			placement_region = &"apron"
			anchor += (apron_fit["position"] as Vector2) - focal_preferred
	cluster.set_meta("placement_region", placement_region)
	for formation_data: Dictionary in story["island"]:
		if stage.is_valid():
			await stage.call("Dressing the start area")
		var quantity := StringName(formation_data["quantity"])
		var requested_count := _bounded_quantity_count(quantity, int(formation_data["count"]))
		var formation := Node2D.new()
		formation.name = "Formation%s" % String(quantity).to_pascal_case()
		formation.set_meta("semantic_quantity", quantity)
		formation.set_meta("requested_count", requested_count)
		formation.set_meta("asset_path", String(formation_data["asset"]))
		cluster.add_child(formation)
		var asset_path := String(formation_data["asset"])
		var base_radius := _asset_radius(asset_path, 24.0)
		var maximum_radius := 72.0 if quantity == &"unique" else (42.0 if quantity == &"few" else 18.0)
		maximum_radius = float(formation_data.get("max_radius", maximum_radius))
		var size_scale := minf(1.0, maximum_radius / maxf(base_radius, 1.0))
		var radius := base_radius * size_scale
		var authored_offset: Vector2 = formation_data.get("offset", Vector2.ZERO)
		var semantic_spread := 1.45 if quantity == &"many" else (1.65 if quantity == &"few" else 1.0)
		var target: Vector2 = anchor + (authored_offset * semantic_spread).rotated(scene_angle)
		var placed_count := 0
		for item_index in requested_count:
			var local_offset := _semantic_formation_offset(StringName(formation_data["formation"]), item_index, requested_count, radius)
			var placed := false
			var preferred := target + local_offset.rotated(scene_angle)
			for attempt in 36:
				var fallback_distance := float((attempt + 3) / 4) * maxf(radius * 0.6, 20.0)
				var fallback_angle := scene_angle + float(attempt) * 2.399963 + float(item_index) * 0.41
				var fallback := Vector2.ZERO if attempt == 0 else Vector2.RIGHT.rotated(fallback_angle) * fallback_distance
				var candidate := preferred + fallback
				var safe := _placement_is_safe(candidate, radius, room_polygon, inner_loop, occupied) if placement_region == &"island" else _trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied)
				if not safe:
					continue
				_add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, scene_angle + float(item_index) * 0.17, placement_region, quantity, item_index, size_scale)
				occupied.append({"position": candidate, "radius": radius})
				placed_count += 1
				placed = true
				break
			if not placed:
				var exhaustive := _best_island_position(preferred, radius, room_polygon, inner_loop, occupied) if placement_region == &"island" else _best_offtrack_position(preferred, radius, room_polygon, centerline, gate_samples, occupied)
				if bool(exhaustive["found"]):
					var candidate: Vector2 = exhaustive["position"]
					_add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, scene_angle + float(item_index) * 0.17, placement_region, quantity, item_index, size_scale)
					occupied.append({"position": candidate, "radius": radius})
					placed_count += 1
					placed = true
			if not placed and placement_region == &"island":
				var apron_fit := _best_offtrack_position(preferred, radius, room_polygon, centerline, gate_samples, occupied)
				if bool(apron_fit["found"]):
					var candidate: Vector2 = apron_fit["position"]
					_add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, scene_angle + float(item_index) * 0.17, &"apron", quantity, item_index, size_scale)
					occupied.append({"position": candidate, "radius": radius})
					placed_count += 1
					placed = true
					cluster.set_meta("placement_region", &"mixed")
			if not placed and quantity == &"unique":
				break
		formation.set_meta("placed_count", placed_count)


static func _bounded_quantity_count(quantity: StringName, requested: int) -> int:
	match quantity:
		&"unique":
			return 1
		&"few":
			return clampi(requested, 2, 3)
		&"many":
			return clampi(requested, 8, 20)
	return clampi(requested, 1, 20)


static func _semantic_formation_offset(formation: StringName, index: int, count: int, radius: float) -> Vector2:
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


static func _island_anchor(inner_loop: PackedVector2Array, centerline: PackedVector2Array) -> Vector2:
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
			var clearance := _distance_to_centerline(candidate, centerline)
			if clearance > best_clearance:
				best_clearance = clearance
				best = candidate
	return best


static func _polygon_bounds_rect(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


static func _build_track_formation(
		parent: Node2D,
		node_name: String,
		data: Dictionary,
		quantity: StringName,
		moment_index: int,
		centerline: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary]
) -> void:
	var formation := Node2D.new()
	formation.name = node_name
	formation.set_meta("semantic_quantity", quantity)
	formation.set_meta("centerline_index", moment_index)
	formation.set_meta("asset_path", String(data["asset"]))
	parent.add_child(formation)
	var requested_count := _bounded_quantity_count(quantity, int(data["count"]))
	formation.set_meta("requested_count", requested_count)
	var asset_path := String(data["asset"])
	var radius := _asset_radius(asset_path, 18.0)
	var sample_step := (5 if radius > 20.0 else (4 if radius > 12.0 else 3)) if quantity == &"many" else maxi(6, ceili((radius * 2.0 + 10.0) / 10.0))
	var placed_count := 0
	for item_index in requested_count:
		var sample_offset := int(round((float(item_index) - float(requested_count - 1) * 0.5) * float(sample_step)))
		var placed := false
		for adjustment_attempt in 17:
			var adjustment_magnitude := (adjustment_attempt + 1) / 2
			var adjustment_direction := -1 if adjustment_attempt % 2 == 0 else 1
			var adjustment := 0 if adjustment_attempt == 0 else adjustment_magnitude * adjustment_direction
			var index := posmod(moment_index + sample_offset + adjustment, centerline.size())
			var tangent := _sample_tangent(centerline, index)
			var outward := (outer_loop[index] - centerline[index]).normalized()
			for attempt in 8:
				var side := 1.0 if attempt % 2 == 0 else -1.0
				var direction := outward * side
				var offset := HALF_WIDTH + radius + APRON_COLLIDER_CLEARANCE + float(attempt / 2) * 8.0
				var candidate := centerline[index] + direction * offset
				if not _trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied):
					continue
				_add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, tangent.angle(), &"trackside", quantity, item_index)
				occupied.append({"position": candidate, "radius": radius})
				placed_count += 1
				placed = true
				break
			if placed:
				break
		if not placed:
			var exhaustive := _best_trackside_position(moment_index + sample_offset, radius, centerline, outer_loop, room_polygon, gate_samples, occupied)
			if bool(exhaustive["found"]):
				var candidate: Vector2 = exhaustive["position"]
				var index := int(exhaustive["index"])
				_add_generated_prop(formation, "Item%02d" % item_index, candidate, asset_path, _sample_tangent(centerline, index).angle(), &"trackside", quantity, item_index)
				occupied.append({"position": candidate, "radius": radius})
				placed_count += 1
				placed = true
		if not placed:
			continue
	formation.set_meta("placed_count", placed_count)


static func _build_corner_landmarks(
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
	var asset_start := posmod(_mix_seed(int(spec.get("dressing_seed", spec["requested_seed"])), "landmark_asset"), assets.size())
	var available_assets: Array[String] = []
	for asset_offset in assets.size():
		var asset_path := String(assets[(asset_start + asset_offset) % assets.size()])
		if not reserved_unique_assets.has(asset_path):
			available_assets.append(asset_path)
	var target_count := mini(1 + posmod(_mix_seed(int(spec.get("dressing_seed", spec["requested_seed"])), "landmarks"), 2), available_assets.size())
	landmarks.set_meta("requested_count", target_count)
	var placed_count := 0
	for corner_slot in corner_indices.size():
		if placed_count >= target_count:
			break
		var index := int(corner_indices[corner_slot])
		var asset_path := available_assets[placed_count]
		var base_radius := _asset_radius(asset_path, 64.0)
		var size_scale := minf(1.0, 72.0 / maxf(base_radius, 1.0))
		var radius := base_radius * size_scale
		var outward := (outer_loop[index] - centerline[index]).normalized()
		for attempt in 12:
			var side := 1.0 if attempt % 2 == 0 else -1.0
			var along := _sample_tangent(centerline, index) * (float(attempt / 4) - 1.0) * 28.0
			var offset := HALF_WIDTH + radius + APRON_COLLIDER_CLEARANCE + float((attempt / 2) % 2) * 12.0
			var candidate := centerline[index] + outward * side * offset + along
			if not _trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied):
				continue
			_add_generated_prop(landmarks, "Landmark%02d" % placed_count, candidate, asset_path, float(corner_slot) * 0.37, &"corner", &"unique", placed_count, size_scale)
			occupied.append({"position": candidate, "radius": radius})
			reserved_unique_assets[asset_path] = true
			placed_count += 1
			break
	while placed_count < target_count:
		var asset_path := available_assets[placed_count]
		var base_radius := _asset_radius(asset_path, 64.0)
		var size_scale := minf(1.0, 72.0 / maxf(base_radius, 1.0))
		var radius := base_radius * size_scale
		var preferred_index := int(corner_indices[mini(placed_count, corner_indices.size() - 1)])
		var exhaustive := _best_trackside_position(preferred_index, radius, centerline, outer_loop, room_polygon, gate_samples, occupied)
		if not bool(exhaustive["found"]):
			break
		var candidate: Vector2 = exhaustive["position"]
		var index := int(exhaustive["index"])
		_add_generated_prop(landmarks, "Landmark%02d" % placed_count, candidate, asset_path, _sample_tangent(centerline, index).angle(), &"corner", &"unique", placed_count, size_scale)
		occupied.append({"position": candidate, "radius": radius})
		reserved_unique_assets[asset_path] = true
		placed_count += 1
	landmarks.set_meta("placed_count", placed_count)


static func _build_room_dressing(
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
	var asset_pool := _room_dressing_assets(story, spec, reserved_unique_assets)
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix_seed(int(spec.get("dressing_seed", spec["requested_seed"])), "room_dressing:%s" % String(story["id"]))
	var room_area := absf(_polygon_area(room_polygon))
	var target_pockets := clampi(int(round(room_area / 450000.0)), 4, 6)
	var target_count := target_pockets * 3
	dressing.set_meta("requested_count", target_count)
	var anchors := _room_dressing_anchors(room_polygon, centerline, gate_samples, occupied, target_pockets, rng)
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
			var asset_path := String(asset_pool[(placed_count + pocket_index * 3) % asset_pool.size()])
			var base_radius := _asset_radius(asset_path, 24.0)
			var size_scale := minf(1.0, 16.0 / maxf(base_radius, 1.0)) * rng.randf_range(0.86, 1.0)
			var radius := base_radius * size_scale
			var placed := false
			for attempt in 12:
				var ring := 30.0 + float(attempt / 6) * 10.0
				var angle := base_angle + TAU * float(item_index) / float(pocket_count) + TAU * float(attempt % 6) / 18.0
				var candidate := anchor + Vector2.RIGHT.rotated(angle) * ring
				if not _trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied):
					continue
				_add_generated_prop(pocket, "Item%02d" % item_index, candidate, asset_path, rng.randf_range(0.0, TAU), &"ambient", &"few", placed_count, size_scale)
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
	var ground_section_count: int = await _build_room_ground_sections(dressing, story, spec, centerline, outer_loop, room_polygon, stage)
	if stage.is_valid():
		await stage.call("Adding floor detail")
	var decal_count := _build_room_floor_details(dressing, spec, centerline, room_polygon, occupied, rng)
	dressing.set_meta("placed_count", placed_count)
	dressing.set_meta("pocket_count", anchors.size())
	dressing.set_meta("ground_section_count", ground_section_count)
	dressing.set_meta("decal_count", decal_count)


static func _build_edge_and_apron_decor(
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
	rng.seed = _mix_seed(int(spec.get("dressing_seed", spec.get("requested_seed", 0))), "edge_decor:%s" % String(spec.get("story_id", "")))
	var target := clampi(70 + int(rng.randf() * 80), 60, 150)
	var placed := 0
	var bounds := _polygon_bounds_rect(room_polygon)
	# Dense along both edges + into apron. Painted material details stay FLAT;
	# recognizable hardware becomes small SOLID scenery.
	var last_yield := Time.get_ticks_usec()
	for attempt in 1200:
		if stage.is_valid() and Time.get_ticks_usec() - last_yield >= 6000:
			await stage.call("Adding surface detail")
			last_yield = Time.get_ticks_usec()
		var candidate := Vector2(
			rng.randf_range(bounds.position.x, bounds.end.x),
			rng.randf_range(bounds.position.y, bounds.end.y)
		)
		var d := _distance_to_centerline(candidate, centerline)
		if d > HALF_WIDTH + 380.0:
			continue
		if not Geometry2D.is_point_in_polygon(candidate, room_polygon):
			continue
		if candidate.distance_to(centerline[0]) < 300.0:
			continue
		var tex_path := String(decor[rng.randi() % decor.size()])
		var tex := load(tex_path) as Texture2D
		if tex == null:
			continue
		var longest := maxf(tex.get_width(), tex.get_height())
		var sz := rng.randf_range(22.0, 52.0)
		var sprite_scale := sz / maxf(longest, 1.0)
		var rotation := rng.randf_range(0.0, TAU)
		var alpha := rng.randf_range(0.55, 0.92)
		var is_flat := FLAT_EDGE_ASSETS.has(tex_path.get_file())
		var shape_kind := StringName(SOLID_EDGE_SHAPES.get(tex_path.get_file(), &""))
		if not is_flat and shape_kind.is_empty():
			push_error("TrackBuilderCore: edge object has no explicit SOLID/FLAT contract: %s" % tex_path)
			continue
		var visible_footprint := _texture_opaque_rect(tex).size * sprite_scale
		var clearance_radius := 0.0 if is_flat else (maxf(visible_footprint.x, visible_footprint.y) * 0.5 if shape_kind == &"circle" else visible_footprint.length() * 0.5)
		var corridor_margin := 8.0 if is_flat else clearance_radius + APRON_COLLIDER_CLEARANCE
		if d < HALF_WIDTH + corridor_margin:
			continue
		if clearance_radius > 0.0 and not _inside_polygon_with_radius(candidate, clearance_radius, room_polygon):
			continue
		if not _clear_of_points(candidate, gate_samples, 82.0 + clearance_radius):
			continue
		if not _clear_of_recovery_lanes(candidate, maxf(18.0, clearance_radius), centerline, gate_samples):
			continue
		if not _clear_of_occupied(candidate, maxf(18.0, clearance_radius), occupied):
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
			_mark_flat_visual(spr, tex_path, &"floor_detail")
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
			_mark_solid_body(body, tex_path, &"apron_prop")
			container.add_child(body)
			var offset := _add_scaled_texture_collision(body, tex, sprite_scale, shape_kind)
			_add_directional_shadow(body, tex_path, sz, 1.0, visible_footprint)
			var spr := Sprite2D.new()
			spr.name = "Sprite"
			spr.texture = tex
			spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			spr.scale = Vector2.ONE * sprite_scale
			spr.position = -offset
			spr.modulate = Color(1.0, 1.0, 1.0, alpha)
			_mark_solid_visual(spr, tex_path, &"apron_prop")
			body.add_child(spr)
		placed += 1
		if placed >= target:
			break
	# Existing colliding props carry unified directional shadows at construction.
	container.set_meta("placed_count", placed)


static func _build_giant_landmarks(
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
	rng.seed = _mix_seed(int(spec.get("dressing_seed", spec.get("requested_seed", 0))), "giants:%s" % String(spec.get("story_id", "")))
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
			tex = load(tex_path) as Texture2D
			if tex == null:
				continue
			var shape_entry: Dictionary = PROP_SHAPES.get(tex_path.get_file(), {})
			if not bool(shape_entry.get("solid", false)):
				push_error("TrackBuilderCore: giant roster contains an asset without a SOLID contract: %s" % tex_path)
				continue
			used_rect = _texture_opaque_rect(tex)
			footprint = _texture_collision_footprint(tex, StringName(shape_entry.get("shape", &"rect")))
			var footprint_size: Vector2 = footprint["size"]
			desired_size = rng.randf_range(300.0, float(shape_entry.get("giant_max_size", 600.0))) if asset_attempt == 0 else 300.0
			sprite_scale = desired_size / maxf(footprint_size.x, footprint_size.y)
			visual_center_offset = ((footprint["center"] as Vector2) - Vector2(tex.get_width(), tex.get_height()) * 0.5) * sprite_scale
			world_shape_size = footprint_size * sprite_scale
			local_footprint_rotation = float(footprint["rotation"])
			placement = _best_giant_position(pref_idx, world_shape_size, StringName(footprint["kind"]), local_footprint_rotation, room_polygon, centerline, gate_samples, occupied, committed_racing_lines)
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
		landmark.set_meta("collision_contract", COLLISION_SOLID)
		VISUAL_ROLE_CONTRACT.assign(landmark, VISUAL_ROLE_SOLID)
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
		_mark_solid_visual(spr, tex_path, &"giant")
		landmark.add_child(spr)
		_add_directional_shadow(landmark, tex_path, desired_size, 1.0, world_shape_size, true, local_footprint_rotation)
		var body := StaticBody2D.new()
		body.name = "GiantBody"
		body.collision_layer = 4 | 16
		_mark_solid_body(body, tex_path, &"giant")
		landmark.add_child(body)
		var _offset := _add_giant_collision(body, tex_path, sprite_scale)
		occupied.append({"position": pos, "radius": footprint_radius})
		placed += 1
	container.set_meta("placed_count", placed)


static func _room_dressing_assets(story: Dictionary, spec: Dictionary, reserved_unique_assets: Dictionary) -> Array[String]:
	var assets: Array[String] = []
	for asset_path: String in spec.get("island_fill_textures", []):
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
	return assets


static func _room_dressing_anchors(
		room_polygon: PackedVector2Array,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary],
		target_count: int,
		rng: RandomNumberGenerator
) -> PackedVector2Array:
	var bounds := _polygon_bounds_rect(room_polygon)
	var candidates: Array[Dictionary] = []
	for x in 17:
		for y in 11:
			var candidate := bounds.position + Vector2(
				bounds.size.x * (float(x) + 0.5) / 17.0,
				bounds.size.y * (float(y) + 0.5) / 11.0
			)
			if not _trackside_placement_is_safe(candidate, 47.0, room_polygon, centerline, gate_samples, occupied):
				continue
			var occupied_clearance := 260.0
			for entry: Dictionary in occupied:
				occupied_clearance = minf(occupied_clearance, candidate.distance_to(entry["position"]) - float(entry["radius"]))
			var score := minf(_distance_to_centerline(candidate, centerline), 360.0)
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
		if not _clear_of_points(candidate, anchors, 210.0):
			continue
		anchors.append(candidate)
		occupied_sectors[sector] = true
		if anchors.size() >= target_count:
			break
	if anchors.size() < target_count:
		for candidate_data: Dictionary in candidates:
			var candidate: Vector2 = candidate_data["position"]
			if not _clear_of_points(candidate, anchors, 210.0):
				continue
			anchors.append(candidate)
			if anchors.size() >= target_count:
				break
	return anchors


static func _build_room_ground_sections(
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
	rng.seed = _mix_seed(int(spec.get("material_seed", spec["requested_seed"])), "ground_sections:%s" % String(story["id"]))
	var room_area := absf(_polygon_area(room_polygon))
	var target_count := clampi(int(round(room_area / 750000.0)), 2, 4)
	sections.set_meta("requested_count", target_count)
	var bounds := _polygon_bounds_rect(room_polygon)
	var placements: Array[Dictionary] = []
	var occupied_sectors := {}
	var asset_offset := rng.randi_range(0, definitions.size() - 1)
	for section_index in target_count:
		if stage.is_valid():
			await stage.call("Laying room materials")
		var definition: Dictionary = definitions[(asset_offset + section_index) % definitions.size()]
		var asset_path := String(definition["asset"])
		var texture := load(asset_path) as Texture2D
		if texture == null:
			continue
		var visible_bounds := _texture_opaque_rect(texture)
		var source_size := texture.get_size()
		var source_radius := visible_bounds.size.length() * 0.5 + visible_bounds.get_center().distance_to(source_size * 0.5)
		var base_world_size := float(definition.get("size", 240.0)) * rng.randf_range(0.90, 1.08)
		var alpha := float(definition.get("alpha", 0.94))
		var last_yield := Time.get_ticks_usec()
		for attempt in 520:
			if stage.is_valid() and Time.get_ticks_usec() - last_yield >= 6000:
				await stage.call("Laying room materials")
				last_yield = Time.get_ticks_usec()
			var size_factor := lerpf(1.0, 0.6, float(attempt) / 519.0)
			var world_size := base_world_size * size_factor
			var footprint_radius := source_radius * world_size / maxf(source_size.x, source_size.y)
			var candidate := Vector2(
				rng.randf_range(bounds.position.x, bounds.end.x),
				rng.randf_range(bounds.position.y, bounds.end.y)
			)
			if Geometry2D.is_point_in_polygon(candidate, outer_loop):
				continue
			if not _inside_polygon_with_radius(candidate, footprint_radius, room_polygon):
				continue
			if _distance_to_centerline(candidate, centerline) < HALF_WIDTH + footprint_radius + FLAT_DRESSING_ROUTE_CLEARANCE:
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
			var longest := maxf(texture.get_width(), texture.get_height())
			sprite.scale = Vector2.ONE * (world_size / maxf(longest, 1.0))
			sprite.modulate = Color(1.0, 1.0, 1.0, alpha)
			sprite.z_index = -17
			sprite.set_meta("asset_path", asset_path)
			sprite.set_meta("moment_kind", &"ambient_ground")
			sprite.set_meta("world_size", world_size)
			sprite.set_meta("footprint_radius", footprint_radius)
			_mark_flat_visual(sprite, asset_path, &"ground_dressing")
			sections.add_child(sprite)
			placements.append({"position": candidate, "radius": footprint_radius})
			occupied_sectors[sector] = true
			break
	sections.set_meta("placed_count", placements.size())
	return placements.size()


static func _build_room_floor_details(
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
	var bounds := _polygon_bounds_rect(room_polygon)
	var target_count := clampi(int(round(absf(_polygon_area(room_polygon)) / 28000.0)), 60, 120)
	var positions := PackedVector2Array()
	for attempt in 820:
		var candidate := Vector2(
			rng.randf_range(bounds.position.x, bounds.end.x),
			rng.randf_range(bounds.position.y, bounds.end.y)
		)
		if not _inside_polygon_with_radius(candidate, 18.0, room_polygon):
			continue
		if _distance_to_centerline(candidate, centerline) < HALF_WIDTH + 18.0:
			continue
		if not _clear_of_points(candidate, positions, 46.0):
			continue
		var texture_path := String(decals[rng.randi_range(0, decals.size() - 1)])
		var texture := load(texture_path) as Texture2D
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
		_mark_flat_visual(sprite, texture_path, &"floor_decal")
		details.add_child(sprite)
		positions.append(candidate)
		if positions.size() >= target_count:
			break
	details.set_meta("placed_count", positions.size())
	return positions.size()


static func _build_generated_surfaces(root: Node2D, parent: Node2D, story: Dictionary, spec: Dictionary, moments: Dictionary, centerline: PackedVector2Array, gate_samples: PackedVector2Array) -> void:
	var definitions: Array[Dictionary] = []
	var surfaces: Array = story["surfaces"]

	var shortcut_surface_index := 0 if float((surfaces[0] as Dictionary)["grip"]) <= float((surfaces[1] as Dictionary)["grip"]) else 1
	var technical_surface_index := 1 - shortcut_surface_index
	var technical_data: Dictionary = surfaces[technical_surface_index]
	var technical_index := int(moments["technical"])
	var technical_polygon := _surface_strip(centerline, technical_index, 6, 92.0)
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
	_add_surface_decals(technical, centerline, technical_index, 6, String(technical_data["decal"]))

	var shortcut_data: Dictionary = surfaces[shortcut_surface_index]
	var shortcut_index := int(moments["shortcut"])
	var shortcut_geometry := _shortcut_lane_geometry(centerline, shortcut_index)
	var shortcut_path: PackedVector2Array = shortcut_geometry["shortcut_path"]
	var safe_path: PackedVector2Array = shortcut_geometry["safe_path"]
	var shortcut_polygon := _lane_strip(shortcut_path, SHORTCUT_LANE_HALF_WIDTH)
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
	_add_surface_decals(shortcut, centerline, shortcut_index, SHORTCUT_HALF_SPAN, String(shortcut_data["decal"]), float(shortcut_geometry["inside_sign"]) * SHORTCUT_LANE_OFFSET)

	# Additional in-corridor grip patches are data for TrackVariantPresenter,
	# which creates the authoritative SurfaceZone nodes at runtime. Keep them
	# separated from gates, the grids, and the two designed surface moments.
	var extra_patches: Array = spec.get("grip_patches", [])
	if extra_patches.size() > 0:
		var patch_rng := RandomNumberGenerator.new()
		patch_rng.seed = _mix_seed(int(spec.get("material_seed", spec.get("requested_seed", 0))), "grip_patches:%s" % String(story.get("id", "")))
		var target_count := patch_rng.randi_range(GRIP_PATCH_MIN_COUNT, GRIP_PATCH_MAX_COUNT)
		var used_indices := PackedInt32Array([technical_index, shortcut_index])
		var added := 0
		for attempt in 240:
			if added >= target_count:
				break
			var pidx_center := patch_rng.randi_range(0, centerline.size() - 1)
			if _cyclic_index_distance(pidx_center, 0, centerline.size()) < 18:
				continue
			var separated := true
			for used_index: int in used_indices:
				if _cyclic_index_distance(pidx_center, used_index, centerline.size()) < 16:
					separated = false
					break
			if not separated or not _clear_of_points(centerline[pidx_center], gate_samples, 155.0):
				continue
			var data: Dictionary = extra_patches[added % extra_patches.size()]
			var halfw := 42.0 + patch_rng.randf_range(0, 12)
			var poly := _surface_strip(centerline, pidx_center, 3, halfw)
			var patch_node := Node2D.new()
			patch_node.name = "ExtraGripPatch%d" % added
			patch_node.set_meta("moment_kind", &"grip_patch")
			patch_node.set_meta("surface_name", StringName(data["name"]))
			patch_node.set_meta("grip", float(data["grip"]))
			patch_node.set_meta("speed", float(data.get("speed", data["grip"])))
			patch_node.set_meta("polygon", poly)
			patch_node.set_meta("decal_texture", String(data["decal"]))
			parent.add_child(patch_node)
			_add_surface_decals(patch_node, centerline, pidx_center, 3, String(data["decal"]), 0.0)
			var def := {
				"name": StringName(data["name"]),
				"role": &"patch",
				"lane": &"mixed",
				"grip": float(data["grip"]),
				"speed": float(data.get("speed", data["grip"])),
				"points": poly,
				"decal": String(data["decal"]),
				"centerline_index": pidx_center,
			}
			definitions.append(def)
			used_indices.append(pidx_center)
			added += 1
		parent.set_meta("grip_patch_count", added)
	root.set_meta("generated_surfaces", definitions)


static func _surface_strip(centerline: PackedVector2Array, center_index: int, half_span: int, half_width: float) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for offset in range(-half_span, half_span + 1, 2):
		var index := posmod(center_index + offset, centerline.size())
		var normal := _sample_tangent(centerline, index).rotated(PI * 0.5)
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


static func _add_surface_decals(
		parent: Node2D,
		centerline: PackedVector2Array,
		center_index: int,
		half_span: int,
		texture_path: String,
		lateral_offset: float = 0.0
) -> void:
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return
	var decal_count := 7
	for decal_index in decal_count:
		var fraction := float(decal_index) / float(decal_count - 1)
		var offset := int(round(lerpf(float(-half_span), float(half_span), fraction)))
		var index := posmod(center_index + offset, centerline.size())
		var sprite := Sprite2D.new()
		sprite.name = "CenterlineDecal%02d" % decal_index
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var normal := _sample_tangent(centerline, index).rotated(PI * 0.5)
		sprite.position = centerline[index] + normal * lateral_offset
		sprite.rotation = _sample_tangent(centerline, index).angle() + float(decal_index % 2) * 0.31
		var longest := maxf(texture.get_width(), texture.get_height())
		sprite.scale = Vector2.ONE * (104.0 / maxf(longest, 1.0))
		sprite.modulate = Color(1.0, 1.0, 1.0, 0.78)
		sprite.z_index = -6
		sprite.set_meta("asset_path", texture_path)
		_mark_flat_visual(sprite, texture_path, &"surface_decal")
		parent.add_child(sprite)


static func _shortcut_lane_geometry(centerline: PackedVector2Array, center_index: int) -> Dictionary:
	var positive := _offset_section_path(centerline, center_index, SHORTCUT_HALF_SPAN, SHORTCUT_LANE_OFFSET)
	var negative := _offset_section_path(centerline, center_index, SHORTCUT_HALF_SPAN, -SHORTCUT_LANE_OFFSET)
	var positive_length := _open_path_length(positive)
	var negative_length := _open_path_length(negative)
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


static func _offset_section_path(
		centerline: PackedVector2Array,
		center_index: int,
		half_span: int,
		lateral_offset: float
) -> PackedVector2Array:
	var path := PackedVector2Array()
	for offset in range(-half_span, half_span + 1):
		var index := posmod(center_index + offset, centerline.size())
		var normal := _sample_tangent(centerline, index).rotated(PI * 0.5)
		path.append(centerline[index] + normal * lateral_offset)
	return path


static func _lane_strip(path: PackedVector2Array, half_width: float) -> PackedVector2Array:
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


static func _open_path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for index in range(1, path.size()):
		total += path[index - 1].distance_to(path[index])
	return total


static func _crossing_path(centerline: PackedVector2Array, center_index: int, half_width: float) -> PackedVector2Array:
	return TRACK_BUILDER_GEOMETRY.crossing_path(centerline, center_index, half_width)


static func _build_finish_moments(parent: Node2D, centerline: PackedVector2Array) -> void:
	var forward_path := PackedVector2Array()
	var reverse_path := PackedVector2Array()
	for offset in range(-FINISH_APPROACH_SPAN, 1):
		forward_path.append(centerline[posmod(offset, centerline.size())])
	for offset in range(FINISH_APPROACH_SPAN, -1, -1):
		reverse_path.append(centerline[posmod(offset, centerline.size())])

	var speed := Node2D.new()
	speed.name = "SpeedSection"
	speed.position = centerline[0]
	speed.set_meta("moment_kind", &"speed")
	speed.set_meta("centerline_index", 0)
	speed.set_meta("forward_path", forward_path)
	speed.set_meta("reverse_path", reverse_path)
	speed.set_meta("forward_length", _open_path_length(forward_path))
	speed.set_meta("reverse_length", _open_path_length(reverse_path))
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
	finish.set_meta("corridor_span", HALF_WIDTH * 2.0)
	finish.set_meta("bidirectional_landmarks", true)
	parent.add_child(finish)


static func _sample_tangent(centerline: PackedVector2Array, index: int) -> Vector2:
	return TRACK_BUILDER_GEOMETRY.sample_tangent(centerline, index)


static func _placement_is_safe(
		candidate: Vector2,
		radius: float,
		room_polygon: PackedVector2Array,
		allowed_polygon: PackedVector2Array,
		occupied: Array[Dictionary]
) -> bool:
	if not _inside_polygon_with_radius(candidate, radius, room_polygon):
		return false
	if not _inside_polygon_with_radius(candidate, radius, allowed_polygon):
		return false
	return _clear_of_occupied(candidate, radius, occupied)


static func _best_island_position(
		preferred: Vector2,
		radius: float,
		room_polygon: PackedVector2Array,
		island_polygon: PackedVector2Array,
		occupied: Array[Dictionary]
) -> Dictionary:
	var bounds := _polygon_bounds_rect(island_polygon)
	var best_position := Vector2.ZERO
	var best_score := INF
	# A deterministic dense scan is the final placement path for strongly
	# concave islands where an authored local formation lands in a bay or waist.
	for x in 17:
		for y in 17:
			var candidate := bounds.position + Vector2(
				bounds.size.x * (float(x) + 0.5) / 17.0,
				bounds.size.y * (float(y) + 0.5) / 17.0
			)
			if not _placement_is_safe(candidate, radius, room_polygon, island_polygon, occupied):
				continue
			var score := candidate.distance_squared_to(preferred)
			if score < best_score:
				best_score = score
				best_position = candidate
	return {"found": best_score < INF, "position": best_position}


static func _best_offtrack_position(
		preferred: Vector2,
		radius: float,
		room_polygon: PackedVector2Array,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary]
) -> Dictionary:
	var bounds := _polygon_bounds_rect(room_polygon)
	var best_position := Vector2.ZERO
	var best_score := INF
	for x in 25:
		for y in 17:
			var candidate := bounds.position + Vector2(
				bounds.size.x * (float(x) + 0.5) / 25.0,
				bounds.size.y * (float(y) + 0.5) / 17.0
			)
			if not _trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied):
				continue
			var score := candidate.distance_squared_to(preferred)
			if score < best_score:
				best_score = score
				best_position = candidate
	return {"found": best_score < INF, "position": best_position}


static func _best_giant_position(
		preferred_index: int,
		size: Vector2,
		shape_kind: StringName,
		local_footprint_rotation: float,
		room_polygon: PackedVector2Array,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary],
		committed_racing_lines: Array[PackedVector2Array] = []
) -> Dictionary:
	var bounds := _polygon_bounds_rect(room_polygon)
	var preferred := centerline[preferred_index]
	var best := {}
	var best_score := INF
	for x in 29:
		for y in 19:
			var candidate := bounds.position + Vector2(
				bounds.size.x * (float(x) + 0.5) / 29.0,
				bounds.size.y * (float(y) + 0.5) / 19.0
			)
			var closest: Dictionary = _closest_point_on_loop(candidate, centerline)
			var centerline_index := int(closest["index"])
			var tangent_angle := _sample_tangent(centerline, centerline_index).angle()
			var rotation := tangent_angle - local_footprint_rotation if size.x >= size.y else tangent_angle - PI * 0.5 - local_footprint_rotation
			if not _giant_placement_is_safe(candidate, size, shape_kind, rotation + local_footprint_rotation, room_polygon, centerline, gate_samples, occupied, committed_racing_lines):
				continue
			var score := candidate.distance_squared_to(preferred)
			if score < best_score:
				best_score = score
				best = {"found": true, "position": candidate, "rotation": rotation}
	return best if not best.is_empty() else {"found": false}


static func _giant_placement_is_safe(
		candidate: Vector2,
		size: Vector2,
		shape_kind: StringName,
		rotation: float,
		room_polygon: PackedVector2Array,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary],
		committed_racing_lines: Array[PackedVector2Array] = []
) -> bool:
	var bounding_radius := size.length() * 0.5
	if not _clear_of_occupied(candidate, bounding_radius, occupied):
		return false
	if shape_kind == &"circle":
		var radius := maxf(size.x, size.y) * 0.5
		if not _inside_polygon_with_radius(candidate, radius, room_polygon):
			return false
		if not _line_sweep_clears_footprint(centerline, candidate, size, shape_kind, rotation, HALF_WIDTH + APRON_COLLIDER_CLEARANCE):
			return false
		for gate: Vector2 in gate_samples:
			if candidate.distance_to(gate) < radius + 82.0:
				return false
		return _committed_lines_clear_giant(committed_racing_lines, candidate, size, shape_kind, rotation)
	var half_size := size * 0.5
	for corner: Vector2 in [
		Vector2(-half_size.x, -half_size.y),
		Vector2(half_size.x, -half_size.y),
		Vector2(half_size.x, half_size.y),
		Vector2(-half_size.x, half_size.y),
	]:
		if not Geometry2D.is_point_in_polygon(candidate + corner.rotated(rotation), room_polygon):
			return false
	if not _line_sweep_clears_footprint(centerline, candidate, size, shape_kind, rotation, HALF_WIDTH + APRON_COLLIDER_CLEARANCE):
		return false
	for gate: Vector2 in gate_samples:
		if _point_to_oriented_rect_distance(gate, candidate, size, rotation) < 82.0:
			return false
	return _committed_lines_clear_giant(committed_racing_lines, candidate, size, shape_kind, rotation)


static func _committed_lines_clear_giant(
		committed_racing_lines: Array[PackedVector2Array],
		candidate: Vector2,
		size: Vector2,
		shape_kind: StringName,
		rotation: float
) -> bool:
	for line: PackedVector2Array in committed_racing_lines:
		if not _line_sweep_clears_footprint(line, candidate, size, shape_kind, rotation, RACING_LINE_HULL_RADIUS):
			return false
	return true


static func _line_sweep_clears_footprint(
		line: PackedVector2Array,
		center: Vector2,
		size: Vector2,
		shape_kind: StringName,
		rotation: float,
		hull_radius: float
) -> bool:
	return TRACK_BUILDER_GEOMETRY.line_sweep_clears_footprint(line, center, size, shape_kind, rotation, hull_radius)


static func _segment_intersects_axis_rect(from: Vector2, to: Vector2, half_size: Vector2) -> bool:
	return TRACK_BUILDER_GEOMETRY.segment_intersects_axis_rect(from, to, half_size)


static func _oriented_rect_inside_polygon(center: Vector2, size: Vector2, rotation: float, polygon: PackedVector2Array) -> bool:
	var half_size := size * 0.5
	return (
		Geometry2D.is_point_in_polygon(center + Vector2(-half_size.x, -half_size.y).rotated(rotation), polygon)
		and Geometry2D.is_point_in_polygon(center + Vector2(half_size.x, -half_size.y).rotated(rotation), polygon)
		and Geometry2D.is_point_in_polygon(center + Vector2(half_size.x, half_size.y).rotated(rotation), polygon)
		and Geometry2D.is_point_in_polygon(center + Vector2(-half_size.x, half_size.y).rotated(rotation), polygon)
	)


static func _point_to_oriented_rect_distance(point: Vector2, center: Vector2, size: Vector2, rotation: float) -> float:
	var local := (point - center).rotated(-rotation)
	var outside := Vector2(maxf(absf(local.x) - size.x * 0.5, 0.0), maxf(absf(local.y) - size.y * 0.5, 0.0))
	return outside.length()


static func _trackside_placement_is_safe(
		candidate: Vector2,
		radius: float,
		room_polygon: PackedVector2Array,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary]
) -> bool:
	if not _inside_polygon_with_radius(candidate, radius, room_polygon):
		return false
	if _distance_to_centerline(candidate, centerline) < HALF_WIDTH + radius + APRON_COLLIDER_CLEARANCE:
		return false
	if candidate.distance_to(centerline[0]) < 245.0 + radius:
		return false
	if not _clear_of_points(candidate, gate_samples, 24.0 + radius):
		return false
	if not _clear_of_recovery_lanes(candidate, radius, centerline, gate_samples):
		return false
	return _clear_of_occupied(candidate, radius, occupied)


static func _best_trackside_position(
		preferred_index: int,
		radius: float,
		centerline: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary]
) -> Dictionary:
	var best_position := Vector2.ZERO
	var best_index := 0
	var best_score := INF
	for index in range(0, centerline.size(), 2):
		var outward := (outer_loop[index] - centerline[index]).normalized()
		for attempt in 8:
			var side := 1.0 if attempt % 2 == 0 else -1.0
			var offset := HALF_WIDTH + radius + APRON_COLLIDER_CLEARANCE + float(attempt / 2) * 8.0
			var candidate := centerline[index] + outward * side * offset
			if not _trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied):
				continue
			var score := float(_cyclic_index_distance(index, posmod(preferred_index, centerline.size()), centerline.size())) + float(attempt) * 0.01
			if score < best_score:
				best_score = score
				best_position = candidate
				best_index = index
	return {"found": best_score < INF, "position": best_position, "index": best_index}


static func _inside_polygon_with_radius(point: Vector2, radius: float, polygon: PackedVector2Array) -> bool:
	if polygon.is_empty() or not Geometry2D.is_point_in_polygon(point, polygon):
		return false
	for sample in 8:
		var test_point := point + Vector2.RIGHT.rotated(TAU * float(sample) / 8.0) * radius
		if not Geometry2D.is_point_in_polygon(test_point, polygon):
			return false
	return true


static func _clear_of_points(point: Vector2, points: PackedVector2Array, clearance: float) -> bool:
	return TRACK_BUILDER_GEOMETRY.clear_of_points(point, points, clearance)


static func _clear_of_recovery_lanes(
		point: Vector2,
		radius: float,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array
) -> bool:
	for gate: Vector2 in gate_samples:
		var nearest_index := 0
		var nearest_distance := INF
		for index in centerline.size():
			var distance := gate.distance_squared_to(centerline[index])
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_index = index
		var tangent := _sample_tangent(centerline, nearest_index)
		var lane_from := gate - tangent * RECOVERY_LANE_HALF_LENGTH
		var lane_to := gate + tangent * RECOVERY_LANE_HALF_LENGTH
		if _point_to_segment_distance(point, lane_from, lane_to) < RECOVERY_LANE_HALF_WIDTH + radius:
			return false
	return true


static func _point_to_segment_distance(point: Vector2, from: Vector2, to: Vector2) -> float:
	return TRACK_BUILDER_GEOMETRY.point_to_segment_distance(point, from, to)


static func _clear_of_occupied(point: Vector2, radius: float, occupied: Array[Dictionary]) -> bool:
	return TRACK_BUILDER_GEOMETRY.clear_of_occupied(point, radius, occupied)


static func _asset_radius(texture_path: String, fallback_radius: float) -> float:
	var radius := _prop_visual_size(texture_path, fallback_radius * 2.0) * 0.5
	return radius if bool(PROP_SHAPES.get(texture_path.get_file(), {}).get("large_focal", false)) else minf(radius, 96.0)


static func _add_generated_prop(
		parent: Node2D,
		node_name: String,
		position: Vector2,
		texture_path: String,
		rotation: float,
		moment_kind: StringName,
		quantity: StringName,
		formation_index: int,
		size_scale: float = 1.0
) -> void:
	var prop := StaticBody2D.new()
	prop.name = node_name
	prop.position = position
	prop.rotation = rotation
	prop.collision_layer = 16
	_mark_solid_body(prop, texture_path, moment_kind)
	prop.set_meta("moment_kind", moment_kind)
	prop.set_meta("semantic_quantity", quantity)
	prop.set_meta("formation_index", formation_index)
	prop.set_meta("size_scale", size_scale)
	parent.add_child(prop)
	var radius := _asset_radius(texture_path, 24.0) * size_scale
	_add_directional_shadow(prop, texture_path, radius * 2.0, size_scale)
	var texture := load(texture_path) as Texture2D
	if texture:
		var longest := maxf(texture.get_width(), texture.get_height())
		var sprite_scale := _prop_visual_size(texture_path, 48.0) * size_scale / maxf(longest, 1.0)
		var entry: Dictionary = PROP_SHAPES.get(texture_path.get_file(), {})
		var offset := _add_scaled_texture_collision(prop, texture, sprite_scale, StringName(entry.get("shape", &"circle")))
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.scale = Vector2.ONE * sprite_scale
		sprite.position = -offset
		_mark_solid_visual(sprite, texture_path, moment_kind)
		prop.add_child(sprite)


static func _mix_seed(seed: int, stream: String) -> int:
	var value := (seed ^ int(stream.hash()) ^ 0x6D2B79F5) & 0x7FFFFFFF
	value = ((value ^ (value >> 16)) * 0x45D9F3B) & 0x7FFFFFFF
	value = ((value ^ (value >> 15)) * 0x45D9F3B) & 0x7FFFFFFF
	return (value ^ (value >> 16)) & 0x7FFFFFFF


static func _fill_island(root: Node2D, spec: Dictionary, inner_loop: PackedVector2Array, centerline: PackedVector2Array) -> void:
	# The island hosts one authored VIGNETTE per theme (a designed scene, not a
	# random scatter): focal props at hand-authored offsets from the centroid,
	# plus a scatter of tiny many-items for life. The vignette is chosen by the
	# seed so it stays procedural but always reads as a scene.
	var vignettes: Array = []
	match String(spec.get("root_name", "")):
		"WorkshopWorkbench":
			vignettes = ISLAND_VIGNETTES[&"workshop"]
		"OfficeDesk":
			vignettes = ISLAND_VIGNETTES[&"office"]
		_:
			vignettes = ISLAND_VIGNETTES[&"kitchen"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0))
	var vignette: Array = vignettes[posmod(int(spec.get("seed", 0)), vignettes.size())]
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for point: Vector2 in inner_loop:
		min_point = min_point.min(point)
		max_point = max_point.max(point)
	var centroid := (min_point + max_point) * 0.5
	var half_extent := (max_point - min_point) * 0.5
	for entry: Dictionary in vignette:
		var offset: Vector2 = entry["pos"]
		var position := centroid + Vector2(offset.x * half_extent.x, offset.y * half_extent.y)
		if not Geometry2D.is_point_in_polygon(position, inner_loop):
			continue
		var center_distance := _distance_to_centerline(position, centerline)
		if center_distance < 125.0 + 40.0:
			continue
		var texture_path := String(entry["tex"])
		if bool(entry.get("decal", false)):
			var sprite := Sprite2D.new()
			sprite.name = "VignetteDecal"
			sprite.texture = load(texture_path) as Texture2D
			if sprite.texture == null:
				sprite.free()
				continue
			sprite.position = position
			sprite.rotation = float(entry.get("rot", 0.0))
			sprite.scale = Vector2.ONE * rng.randf_range(0.7, 1.2)
			sprite.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(0.55, 0.8))
			sprite.z_index = -13
			root.add_child(sprite)
			continue
		var visual := _prop_visual_size(texture_path, 36.0)
		var radius := minf(visual * 0.5, 52.0)
		_add_fill_prop(root, position, radius, texture_path, float(entry.get("rot", 0.0)))
	# Life: a scatter of tiny many-items (paperclips, coins, screws) around the vignette
	var many_pool: Array = spec.get("island_fill_tiny", [])
	if many_pool.is_empty():
		many_pool = ["res://assets/textures/imagine/paperclip.png", "res://assets/textures/imagine/coin.png"]
	for scatter in 12:
		var position := centroid + Vector2(rng.randf_range(-0.85, 0.85) * half_extent.x, rng.randf_range(-0.85, 0.85) * half_extent.y)
		if not Geometry2D.is_point_in_polygon(position, inner_loop):
			continue
		if _distance_to_centerline(position, centerline) < 125.0 + 40.0:
			continue
		var texture_path := String(many_pool[rng.randi_range(0, many_pool.size() - 1)])
		var visual := _prop_visual_size(texture_path, 18.0)
		_add_fill_prop(root, position, minf(visual * 0.5, 20.0), texture_path, rng.randf_range(0.0, TAU))


static func _line_boundary_props(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, outer_loop: PackedVector2Array, corridor: PackedVector2Array, room_polygon: PackedVector2Array) -> void:
	# Props delimiting the OUTER side of the track: long flat props on straights,
	# bulky props on corners, placed just outside the painted corridor. The
	# corridor-band test is distance-to-centerline (polygon membership is
	# unreliable inside the corridor's fold regions).
	var long_pool: Array = spec.get("boundary_long", [])
	var corner_pool: Array = spec.get("boundary_corner", [])
	if long_pool.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0))
	var count := centerline.size()
	var index := 0
	while index < count - 1:
		var tangent := (centerline[(index + 1) % count] - centerline[(index - 1 + count) % count]).normalized()
		var ahead := centerline[(index + 8) % count] - centerline[(index - 8 + count) % count]
		var turn := tangent.angle_to(ahead.normalized())
		var is_corner := absf(turn) > 0.16
		var offset := 78.0 if is_corner else 65.0
		var radius := 34.0 if is_corner else 27.0
		var position := outer_loop[index] + (outer_loop[index] - centerline[index]).normalized() * offset
		if position.distance_to(centerline[0]) < 230.0:
			index += 7
			continue
		if not Geometry2D.is_point_in_polygon(position, room_polygon):
			index += 7
			continue
		if _distance_to_centerline(position, centerline) < 150.0:
			index += 7
			continue
		var pool := corner_pool if is_corner else long_pool
		var texture_path := String(pool[rng.randi_range(0, pool.size() - 1)])
		var prop_rotation := rng.randf_range(0.0, TAU) if is_corner else tangent.angle()
		_add_boundary_prop(root, position, radius, texture_path, prop_rotation)
		index += 7


static func _build_racing_line(root: Node2D, centerline: PackedVector2Array, moments: Dictionary = {}) -> void:
	var line_points := _racing_line_points(centerline, moments, false)
	var shortcut_index := int(moments.get("shortcut", -1))
	_add_hidden_racing_line(root, "RacingLine", line_points)
	if shortcut_index >= 0:
		var shortcut_points := _racing_line_points(centerline, moments, true)
		var shortcut_line := _add_hidden_racing_line(root, "ShortcutRacingLine", shortcut_points)
		shortcut_line.set_meta("role", &"shortcut")
		shortcut_line.set_meta("centerline_index", shortcut_index)
		shortcut_line.set_meta("ai_path_clear", true)


static func _racing_line_points(centerline: PackedVector2Array, moments: Dictionary, use_shortcut: bool) -> PackedVector2Array:
	var count := centerline.size()
	var points := _curvature_apex_line(centerline)
	var shortcut_index := int(moments.get("shortcut", -1))
	if shortcut_index < 0:
		return points
	var inside_sign := float(_shortcut_lane_geometry(centerline, shortcut_index)["inside_sign"])
	var taper_span := SHORTCUT_HALF_SPAN + (8 if use_shortcut else 6)
	for index in count:
		var shortcut_distance := _cyclic_index_distance(index, shortcut_index, count)
		if shortcut_distance > taper_span:
			continue
		var influence := 1.0 - smoothstep(float(SHORTCUT_HALF_SPAN), float(taper_span), float(shortcut_distance))
		var normal := _sample_tangent(centerline, index).rotated(PI * 0.5)
		var lane_offset := inside_sign * SHORTCUT_LANE_OFFSET if use_shortcut else -inside_sign * SAFE_RACING_LINE_OFFSET
		points[index] = points[index].lerp(centerline[index] + normal * lane_offset, influence)
	return points


static func _add_hidden_racing_line(parent: Node2D, line_name: String, points: PackedVector2Array) -> Line2D:
	var line := Line2D.new()
	line.name = line_name
	line.points = points
	line.closed = true
	line.width = 2.0
	line.visible = false
	parent.add_child(line)
	return line


static func _curvature_apex_line(centerline: PackedVector2Array) -> PackedVector2Array:
	var line_points := PackedVector2Array()
	var count := centerline.size()
	if count < APEX_SAMPLE_SPAN * 2 + 1:
		return centerline.duplicate()
	for index in count:
		var local_turn := _signed_turn_at(centerline, index, APEX_SAMPLE_SPAN)
		var entry_turn := _signed_turn_at(centerline, index + APEX_SAMPLE_SPAN, APEX_SAMPLE_SPAN)
		var exit_turn := _signed_turn_at(centerline, index - APEX_SAMPLE_SPAN, APEX_SAMPLE_SPAN)
		var strongest_turn := local_turn
		if absf(entry_turn) > absf(strongest_turn):
			strongest_turn = entry_turn
		if absf(exit_turn) > absf(strongest_turn):
			strongest_turn = exit_turn
		var severity := clampf(absf(strongest_turn) / 0.78, 0.0, 1.0)
		if severity < 0.04:
			line_points.append(centerline[index])
			continue
		var apex_weight := clampf(absf(local_turn) / maxf(absf(strongest_turn), 0.001), 0.0, 1.0)
		apex_weight = pow(apex_weight, 1.45)
		var inward_offset := APEX_MAX_INWARD_OFFSET * severity * apex_weight
		var setup_offset := APEX_MAX_ENTRY_OFFSET * severity * (1.0 - apex_weight)
		var signed_offset := signf(strongest_turn) * (inward_offset - setup_offset)
		var normal := _sample_tangent(centerline, index).rotated(PI * 0.5)
		line_points.append(centerline[index] + normal * signed_offset)
	return line_points


static func _signed_turn_at(centerline: PackedVector2Array, index: int, span: int) -> float:
	var count := centerline.size()
	var wrapped := posmod(index, count)
	var incoming := (
		centerline[wrapped]
		- centerline[posmod(wrapped - span, count)]
	).normalized()
	var outgoing := (
		centerline[posmod(wrapped + span, count)]
		- centerline[wrapped]
	).normalized()
	return incoming.angle_to(outgoing)


static func _add_corner_set_pieces(root: Node2D, spec: Dictionary, room_polygon: PackedVector2Array, corridor: PackedVector2Array) -> void:
	var giants: Array = spec.get("corner_giants", [])
	if giants.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 0)) * 7 + 3
	var candidates := PackedVector2Array()
	var count := room_polygon.size()
	for index in count:
		var corner: Vector2 = room_polygon[index]
		var toward_center := Vector2.ZERO
		for point: Vector2 in room_polygon:
			toward_center += point
		toward_center /= float(count)
		var inward := (toward_center - corner).normalized()
		candidates.append(corner + inward * 190.0)
	var placed := 0
	for candidate: Vector2 in candidates:
		if placed >= 3:
			break
		if Geometry2D.is_point_in_polygon(candidate, corridor):
			continue
		if _distance_to_centerline(candidate, _sample_centerline(spec["controls"])) < 200.0:
			continue
		var texture_path := String(giants[placed % giants.size()])
		var texture := load(texture_path) as Texture2D
		if texture == null:
			continue
		var prop := StaticBody2D.new()
		prop.name = "CornerGiant"
		prop.position = candidate
		prop.rotation = rng.randf_range(0.0, TAU)
		prop.collision_layer = 4
		_mark_solid_body(prop, texture_path, &"corner_giant")
		root.add_child(prop)
		_add_directional_shadow(prop, texture_path, 168.0, 1.0, Vector2(168.0, 168.0), true)
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		var sprite_scale := 215.0 / maxf(longest, 1.0)
		sprite.scale = Vector2.ONE * sprite_scale
		var entry: Dictionary = PROP_SHAPES.get(texture_path.get_file(), {})
		var offset := _add_scaled_texture_collision(prop, texture, sprite_scale, StringName(entry.get("shape", &"circle")))
		sprite.position = -offset
		_mark_solid_visual(sprite, texture_path, &"corner_giant")
		prop.add_child(sprite)
		placed += 1


static func _island_apexes(inner_loop: PackedVector2Array) -> PackedVector2Array:
	var apexes := PackedVector2Array()
	var count := inner_loop.size()
	for index in count:
		var behind := (inner_loop[index] - inner_loop[(index - 12 + count) % count]).normalized()
		var ahead := (inner_loop[(index + 12) % count] - inner_loop[index]).normalized()
		var turn := behind.angle_to(ahead)
		if absf(turn) > 0.18 and (apexes.is_empty() or apexes[apexes.size() - 1].distance_to(inner_loop[index]) > 120.0):
			apexes.append(inner_loop[index])
	return apexes


static func _add_paperclip_line(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, outer_loop: PackedVector2Array, room_polygon: PackedVector2Array) -> void:
	var count := centerline.size()
	var best_start := 0
	var best_straight := -1.0
	for index in count:
		var chord := centerline[(index + 20) % count].distance_to(centerline[(index + count - 20) % count])
		if chord > best_straight:
			best_straight = chord
			best_start = index
	var index := best_start
	var placed := 0
	var attempts := 0
	while placed < 18 and attempts < count:
		var tangent := (centerline[(index + 1) % count] - centerline[(index - 1 + count) % count]).normalized()
		var position := outer_loop[index] + (outer_loop[index] - centerline[index]).normalized() * 58.0
		if Geometry2D.is_point_in_polygon(position, room_polygon) and _distance_to_centerline(position, centerline) >= 165.0:
			var clip := StaticBody2D.new()
			clip.name = "PaperclipLine"
			clip.position = position
			clip.rotation = tangent.angle()
			clip.collision_layer = 16
			_mark_solid_body(clip, "res://assets/textures/imagine/paperclip.png", &"boundary_prop")
			root.add_child(clip)
			var shape := RectangleShape2D.new()
			shape.size = Vector2(16.0, 7.0)
			var cs := CollisionShape2D.new()
			cs.shape = shape
			clip.add_child(cs)
			_record_shape_probe_points(clip, Vector2.ZERO, shape.size, &"rect")
			var texture := load("res://assets/textures/imagine/paperclip.png") as Texture2D
			if texture:
				var sprite := Sprite2D.new()
				sprite.texture = texture
				sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
				sprite.scale = Vector2.ONE * (16.0 / maxf(texture.get_width(), texture.get_height()))
				_mark_solid_visual(sprite, "res://assets/textures/imagine/paperclip.png", &"boundary_prop")
				clip.add_child(sprite)
			placed += 1
		index = (index + 2) % count
		attempts += 1


static func _distance_to_centerline(point: Vector2, centerline: PackedVector2Array) -> float:
	var best := 999999.0
	for index in centerline.size():
		best = minf(best, _point_to_segment_distance(point, centerline[index], centerline[(index + 1) % centerline.size()]))
	return best


static func _prop_visual_size(texture_path: String, fallback_diameter: float) -> float:
	var entry: Dictionary = PROP_SHAPES.get(texture_path.get_file(), {})
	var size: Vector2 = entry.get("size", Vector2.ZERO)
	if size.x > 0.0 or size.y > 0.0:
		return maxf(size.x, size.y)
	return fallback_diameter


static func _mark_solid_body(body: CollisionObject2D, texture_path: String, solid_class: StringName) -> void:
	body.set_meta("collision_contract", COLLISION_SOLID)
	VISUAL_ROLE_CONTRACT.assign(body, VISUAL_ROLE_SOLID)
	body.set_meta("solid_class", solid_class)
	if not texture_path.is_empty():
		body.set_meta("asset_path", texture_path)


static func _mark_solid_visual(visual: CanvasItem, texture_path: String, solid_class: StringName) -> void:
	visual.set_meta("collision_contract", COLLISION_SOLID)
	VISUAL_ROLE_CONTRACT.assign(visual, VISUAL_ROLE_SOLID)
	visual.set_meta("solid_class", solid_class)
	if not texture_path.is_empty():
		visual.set_meta("asset_path", texture_path)


static func _mark_flat_visual(visual: CanvasItem, texture_path: String, flat_class: StringName) -> void:
	visual.set_meta("collision_contract", COLLISION_FLAT)
	VISUAL_ROLE_CONTRACT.assign(visual, VISUAL_ROLE_FLAT)
	visual.set_meta("flat_class", flat_class)
	if not texture_path.is_empty():
		visual.set_meta("asset_path", texture_path)


static func _texture_opaque_rect(texture: Texture2D) -> Rect2:
	var cache_key := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
	if _texture_opaque_rect_cache.has(cache_key):
		return _texture_opaque_rect_cache[cache_key]
	var result: Rect2 = _texture_alpha_outline(texture)["used"]
	_texture_opaque_rect_cache[cache_key] = result
	return result


static func _texture_alpha_outline(texture: Texture2D) -> Dictionary:
	var cache_key := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
	if _texture_outline_cache.has(cache_key):
		return _texture_outline_cache[cache_key]
	synchronous_outline_builds += 1
	var result := compute_alpha_outline(texture.get_image(), texture.get_width(), texture.get_height())
	_texture_outline_cache[cache_key] = result
	return result


static func has_prepared_outline(texture: Texture2D) -> bool:
	var key := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
	return _texture_outline_cache.has(key)


static func has_prepared_outline_path(path: String) -> bool:
	return _texture_outline_cache.has(path)


static func install_prepared_outline(texture: Texture2D, outline: Dictionary) -> void:
	var key := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
	_texture_outline_cache[key] = outline


static func preparation_texture_paths(value: Variant) -> Array[String]:
	var found: Array[String] = []
	if value is Dictionary:
		for child: Variant in value.values():
			for path in preparation_texture_paths(child):
				if not found.has(path):
					found.append(path)
	elif value is Array:
		for child: Variant in value:
			for path in preparation_texture_paths(child):
				if not found.has(path):
					found.append(path)
	elif value is String or value is StringName:
		var path := String(value)
		if path.begins_with("res://assets/") and path.get_extension() in ["png", "jpg", "webp", "svg"]:
			found.append(path)
	return found


static func compute_alpha_outline(image: Image, width: int, height: int) -> Dictionary:
	var rows_first := PackedInt32Array()
	var rows_last := PackedInt32Array()
	var columns_first := PackedInt32Array()
	var columns_last := PackedInt32Array()
	rows_first.resize(height)
	rows_last.resize(height)
	columns_first.resize(width)
	columns_last.resize(width)
	rows_first.fill(-1)
	rows_last.fill(-1)
	columns_first.fill(-1)
	columns_last.fill(-1)
	var boundary := PackedVector2Array()
	var bounds := Rect2(Vector2.ZERO, Vector2(width, height))
	if image != null and not image.is_empty():
		if image.is_compressed():
			image.decompress()
		var used := image.get_used_rect()
		var byte_alpha := image.get_format() == Image.FORMAT_RGBA8
		var pixels := image.get_data() if byte_alpha else PackedByteArray()
		var threshold := int(floor(COLLISION_ALPHA_THRESHOLD * 255.0))
		if used.size.x > 0 and used.size.y > 0:
			var minimum := Vector2i(used.end)
			var maximum := Vector2i(used.position - Vector2i.ONE)
			for y in range(used.position.y, used.end.y):
				var offset := (y * width + used.position.x) * 4 + 3
				for x in range(used.position.x, used.end.x):
					var opaque := pixels[offset] > threshold if byte_alpha else image.get_pixel(x, y).a > COLLISION_ALPHA_THRESHOLD
					if opaque:
						if rows_first[y] < 0:
							rows_first[y] = x
						rows_last[y] = x
						if columns_first[x] < 0:
							columns_first[x] = y
						columns_last[x] = y
					offset += 4
				if rows_first[y] >= 0:
					minimum = minimum.min(Vector2i(rows_first[y], y))
					maximum = maximum.max(Vector2i(rows_last[y], y))
					boundary.append(Vector2(rows_first[y] + 0.5, y + 0.5))
					boundary.append(Vector2(rows_last[y] + 0.5, y + 0.5))
			if maximum.x >= minimum.x and maximum.y >= minimum.y:
				bounds = Rect2(Vector2(minimum), Vector2(maximum - minimum + Vector2i.ONE))
	var result := {"used": bounds, "rows_first": rows_first, "rows_last": rows_last, "columns_first": columns_first, "columns_last": columns_last, "boundary": boundary}
	return result


static func _texture_collision_footprint(texture: Texture2D, shape_kind: StringName, force_axis_aligned: bool = false) -> Dictionary:
	var override: Dictionary = ASSET_FOOTPRINT_OVERRIDES.get(texture.resource_path.get_file(), {})
	var resolved_kind := StringName(override.get("kind", shape_kind))
	var no_rotation := force_axis_aligned or bool(override.get("no_rotation", false))
	var cache_key := "%s:%s:%s" % [texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id()), resolved_kind, no_rotation]
	if _texture_footprint_cache.has(cache_key):
		return _texture_footprint_cache[cache_key]
	var used := _texture_opaque_rect(texture)
	var fallback := {"center": used.get_center(), "size": used.size, "rotation": 0.0, "kind": resolved_kind}
	if resolved_kind == &"circle":
		var circle_result := _balanced_circle_texture_footprint(texture, used)
		_texture_footprint_cache[cache_key] = circle_result
		return circle_result
	if resolved_kind == &"convex":
		_texture_footprint_cache[cache_key] = fallback
		return fallback
	if no_rotation:
		var forced_axis_result := _axis_aligned_texture_footprint(used, resolved_kind)
		_texture_footprint_cache[cache_key] = forced_axis_result
		return forced_axis_result
	var outline := _texture_alpha_outline(texture)
	if (outline["boundary"] as PackedVector2Array).is_empty():
		_texture_footprint_cache[cache_key] = fallback
		return fallback
	# Gather the first and last opaque pixel on sampled rows and columns. This
	# keeps diagonal silhouettes tight without scanning every interior pixel or
	# paying the fit cost again for repeated props.
	var points := PackedVector2Array()
	var scan_step := maxi(1, int(ceil(maxf(used.size.x, used.size.y) / 192.0)))
	var left := int(used.position.x)
	var top := int(used.position.y)
	var right := int(used.end.x)
	var bottom := int(used.end.y)
	for y in range(top, bottom, scan_step):
		var first_x: int = outline["rows_first"][y]
		var last_x: int = outline["rows_last"][y]
		if first_x >= 0:
			points.append(Vector2(first_x + 0.5, y + 0.5))
			points.append(Vector2(last_x + 0.5, y + 0.5))
	for x in range(left, right, scan_step):
		var first_y: int = outline["columns_first"][x]
		var last_y: int = outline["columns_last"][x]
		if first_y >= 0:
			points.append(Vector2(x + 0.5, first_y + 0.5))
			points.append(Vector2(x + 0.5, last_y + 0.5))
	if points.size() < 3:
		_texture_footprint_cache[cache_key] = fallback
		return fallback
	# Use principal axis (covariance) of border points for robust long-axis
	# orientation. Finishes the cached alpha-derived oriented footprint so that
	# for rotated sprites the rect aligns with alpha even for paperclip/screw
	# style and diagonal giants.
	var sum := Vector2.ZERO
	var n := 0
	for pt: Vector2 in points:
		sum += pt
		n += 1
	var mean := sum / maxf(n, 1.0)
	var cxx := 0.0
	var cxy := 0.0
	var cyy := 0.0
	for pt: Vector2 in points:
		var d := pt - mean
		cxx += d.x * d.x
		cxy += d.x * d.y
		cyy += d.y * d.y
	cxx /= maxf(n, 1)
	cxy /= maxf(n, 1)
	cyy /= maxf(n, 1)
	var best_rotation := 0.5 * atan2(2.0 * cxy, cxx - cyy)
	# consider both orientations from PCA, pick by largest extent on one axis (robust long)
	var cands := [best_rotation, best_rotation + PI * 0.5]
	var best_max_extent := -1.0
	for c in cands:
		var angle := float(c)
		var axis_x := Vector2(cos(angle), sin(angle))
		var axis_y := axis_x.rotated(PI * 0.5)
		var min_x := INF
		var max_x := -INF
		var min_y := INF
		var max_y := -INF
		for point: Vector2 in points:
			var px := point.dot(axis_x)
			var py := point.dot(axis_y)
			min_x = minf(min_x, px)
			max_x = maxf(max_x, px)
			min_y = minf(min_y, py)
			max_y = maxf(max_y, py)
		var ex := maxf(max_x - min_x, max_y - min_y)
		if ex > best_max_extent:
			best_max_extent = ex
			best_rotation = angle
	var best_axis_x := Vector2(cos(best_rotation), sin(best_rotation))
	var best_axis_y := best_axis_x.rotated(PI * 0.5)
	# Linear projection extrema on each row occur at its first or last opaque
	# pixel. These endpoints preserve the dense scan's exact support bounds.
	var min_projection := Vector2(INF, INF)
	var max_projection := Vector2(-INF, -INF)
	for pt: Vector2 in outline["boundary"]:
		var pr := Vector2(pt.dot(best_axis_x), pt.dot(best_axis_y))
		min_projection = min_projection.min(pr)
		max_projection = max_projection.max(pr)
	var center_projection := (min_projection + max_projection) * 0.5
	var fitted_size := max_projection - min_projection
	var anisotropy := maxf(fitted_size.x, fitted_size.y) / maxf(minf(fitted_size.x, fitted_size.y), 0.001)
	if anisotropy < ORIENTED_FOOTPRINT_MIN_ANISOTROPY:
		var low_anisotropy_result := _axis_aligned_texture_footprint(used, resolved_kind)
		_texture_footprint_cache[cache_key] = low_anisotropy_result
		return low_anisotropy_result
	var result := {
		"center": best_axis_x * center_projection.x + best_axis_y * center_projection.y,
		# A slight symmetric inset balances rounded silhouette corners against
		# cardinal support while staying within the six-unit contact contract.
		"size": fitted_size * 0.98,
		"rotation": best_rotation,
		"kind": resolved_kind,
	}
	# Canonicalize so longer axis on size.x; equivalent rect (rot +90, dims swap).
	var sz: Vector2 = result["size"]
	if sz.x < sz.y:
		result["size"] = Vector2(sz.y, sz.x)
		result["rotation"] = float(result["rotation"]) + PI * 0.5
	_texture_footprint_cache[cache_key] = result
	return result


static func _axis_aligned_texture_footprint(used: Rect2, shape_kind: StringName) -> Dictionary:
	return {
		"center": used.get_center(),
		"size": used.size * 0.98,
		"rotation": 0.0,
		"kind": shape_kind,
	}


static func _texture_convex_hull(texture: Texture2D) -> PackedVector2Array:
	var cache_key := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_instance_id())
	if _texture_hull_cache.has(cache_key):
		return _texture_hull_cache[cache_key]
	var points: PackedVector2Array = _texture_alpha_outline(texture)["boundary"]
	var hull := Geometry2D.convex_hull(points) if points.size() >= 3 else points
	if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.remove_at(hull.size() - 1)
	_texture_hull_cache[cache_key] = hull
	return hull


static func _balanced_circle_texture_footprint(texture: Texture2D, used: Rect2) -> Dictionary:
	var center := used.get_center()
	var hull := _texture_convex_hull(texture)
	if hull.is_empty():
		return {"center": center, "size": used.size, "rotation": 0.0, "kind": &"circle"}
	var minimum_support := INF
	var maximum_support := -INF
	for direction_index in 8:
		var direction := Vector2.RIGHT.rotated(TAU * float(direction_index) / 8.0)
		var support := -INF
		for point: Vector2 in hull:
			support = maxf(support, (point - center).dot(direction))
		minimum_support = minf(minimum_support, support)
		maximum_support = maxf(maximum_support, support)
	var radius := (minimum_support + maximum_support) * 0.5
	return {"center": center, "size": Vector2.ONE * radius * 2.0, "rotation": 0.0, "kind": &"circle"}


static func _record_shape_probe_points(parent: Node, center: Vector2, size: Vector2, shape_kind: StringName, rotation: float = 0.0) -> void:
	var probes := PackedVector2Array([center])
	if shape_kind == &"circle":
		var radius := size.x * 0.5
		probes.append(center + Vector2(radius * 0.86, 0.0))
		probes.append(center - Vector2(radius * 0.86, 0.0))
	elif size.x >= size.y:
		probes.append(center + Vector2(size.x * 0.44, 0.0).rotated(rotation))
		probes.append(center - Vector2(size.x * 0.44, 0.0).rotated(rotation))
	else:
		probes.append(center + Vector2(0.0, size.y * 0.44).rotated(rotation))
		probes.append(center - Vector2(0.0, size.y * 0.44).rotated(rotation))
	parent.set_meta("collision_probe_points", probes)
	parent.set_meta("collision_footprint_size", size)
	parent.set_meta("collision_shape_kind", shape_kind)
	parent.set_meta("collision_footprint_rotation", rotation)


static func _record_convex_probe_points(parent: Node, points: PackedVector2Array) -> void:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	var axis := Vector2.RIGHT if bounds.size.x >= bounds.size.y else Vector2.DOWN
	var minimum_point := points[0]
	var maximum_point := points[0]
	for point: Vector2 in points:
		if point.dot(axis) < minimum_point.dot(axis):
			minimum_point = point
		if point.dot(axis) > maximum_point.dot(axis):
			maximum_point = point
	parent.set_meta("collision_probe_points", PackedVector2Array([
		Vector2.ZERO,
		minimum_point.lerp(Vector2.ZERO, 0.14),
		maximum_point.lerp(Vector2.ZERO, 0.14),
	]))
	parent.set_meta("collision_footprint_size", bounds.size)
	parent.set_meta("collision_shape_kind", &"convex")
	parent.set_meta("collision_footprint_rotation", 0.0)


static func _add_scaled_texture_collision(parent: Node, texture: Texture2D, sprite_scale: float, shape_kind: StringName) -> Vector2:
	return _add_texture_collision(parent, texture, Vector2.ONE * sprite_scale, shape_kind)


static func _add_texture_collision(
		parent: Node,
		texture: Texture2D,
		sprite_scale: Vector2,
		shape_kind: StringName,
		force_axis_aligned: bool = false,
		padding: float = 0.0
) -> Vector2:
	var footprint := _texture_collision_footprint(texture, shape_kind, force_axis_aligned)
	var footprint_center: Vector2 = footprint["center"]
	var footprint_size: Vector2 = (footprint["size"] as Vector2) * sprite_scale + Vector2.ONE * padding
	var canvas_size := Vector2(texture.get_width(), texture.get_height())
	var visual_center_offset := (footprint_center - canvas_size * 0.5) * sprite_scale
	var resolved_kind := StringName(footprint["kind"])
	if resolved_kind == &"circle":
		var circle := CircleShape2D.new()
		circle.radius = maxf(footprint_size.x, footprint_size.y) * 0.5
		var circle_collision := CollisionShape2D.new()
		circle_collision.name = "AssetCollision"
		circle_collision.shape = circle
		parent.add_child(circle_collision)
		_record_shape_probe_points(parent, Vector2.ZERO, Vector2.ONE * circle.radius * 2.0, &"circle")
		return visual_center_offset
	if resolved_kind == &"capsule":
		var capsule := CapsuleShape2D.new()
		capsule.radius = minf(footprint_size.x, footprint_size.y) * 0.5
		capsule.height = maxf(footprint_size.x, footprint_size.y)
		var capsule_collision := CollisionShape2D.new()
		capsule_collision.name = "AssetCollision"
		capsule_collision.rotation = float(footprint["rotation"]) + (PI * 0.5 if footprint_size.x >= footprint_size.y else 0.0)
		capsule_collision.shape = capsule
		parent.add_child(capsule_collision)
		_record_shape_probe_points(parent, Vector2.ZERO, footprint_size, &"capsule", float(footprint["rotation"]))
		return visual_center_offset
	if resolved_kind == &"convex":
		var hull := _texture_convex_hull(texture)
		var scaled_hull := PackedVector2Array()
		for point: Vector2 in hull:
			scaled_hull.append((point - footprint_center) * sprite_scale)
		var convex := ConvexPolygonShape2D.new()
		convex.points = scaled_hull
		var convex_collision := CollisionShape2D.new()
		convex_collision.name = "AssetCollision"
		convex_collision.shape = convex
		parent.add_child(convex_collision)
		_record_convex_probe_points(parent, scaled_hull)
		return visual_center_offset
	var rect := RectangleShape2D.new()
	# The local rectangle follows the texture's alpha-fitted orientation instead
	# of creating invisible AABB corners around diagonal tools and utensils.
	rect.size = footprint_size
	var rect_collision := CollisionShape2D.new()
	rect_collision.name = "AssetCollision"
	rect_collision.rotation = float(footprint["rotation"])
	rect_collision.shape = rect
	parent.add_child(rect_collision)
	_record_shape_probe_points(parent, Vector2.ZERO, rect.size, &"rect", rect_collision.rotation)
	return visual_center_offset


static func _add_giant_collision(parent: Node, texture_path: String, sprite_scale: float) -> Vector2:
	var entry: Dictionary = PROP_SHAPES.get(texture_path.get_file(), {})
	if not bool(entry.get("solid", false)):
		push_error("TrackBuilderCore: giant asset is missing an explicit SOLID contract: %s" % texture_path)
		return Vector2.ZERO
	var texture := load(texture_path) as Texture2D
	if texture == null:
		push_error("TrackBuilderCore: giant collision texture is missing: %s" % texture_path)
		return Vector2.ZERO
	return _add_scaled_texture_collision(parent, texture, sprite_scale, StringName(entry.get("shape", &"rect")))


static func _add_boundary_prop(parent: Node, position: Vector2, radius: float, texture_path: String, rotation: float) -> void:
	var prop := StaticBody2D.new()
	prop.name = "BoundaryProp"
	prop.position = position
	prop.rotation = rotation
	prop.collision_layer = 16
	_mark_solid_body(prop, texture_path, &"boundary_prop")
	parent.add_child(prop)
	_add_directional_shadow(prop, texture_path, radius * 2.2)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		var sprite_scale := radius * 2.2 / maxf(longest, 1.0)
		sprite.scale = Vector2.ONE * sprite_scale
		var entry: Dictionary = PROP_SHAPES.get(texture_path.get_file(), {})
		var offset := _add_scaled_texture_collision(prop, texture, sprite_scale, StringName(entry.get("shape", &"circle")))
		sprite.position = -offset
		_mark_solid_visual(sprite, texture_path, &"boundary_prop")
		prop.add_child(sprite)


static func _add_fill_prop(parent: Node, position: Vector2, radius: float, texture_path: String, rotation: float) -> void:
	var prop := StaticBody2D.new()
	prop.name = "IslandFill"
	prop.position = position
	prop.rotation = rotation
	prop.collision_layer = 16
	_mark_solid_body(prop, texture_path, &"island_prop")
	parent.add_child(prop)
	_add_directional_shadow(prop, texture_path, radius * 2.2)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		var visual := _prop_visual_size(texture_path, radius * 2.2)
		var sprite_scale := visual / maxf(longest, 1.0)
		sprite.scale = Vector2.ONE * sprite_scale
		var entry: Dictionary = PROP_SHAPES.get(texture_path.get_file(), {})
		var offset := _add_scaled_texture_collision(prop, texture, sprite_scale, StringName(entry.get("shape", &"circle")))
		sprite.position = -offset
		_mark_solid_visual(sprite, texture_path, &"island_prop")
		prop.add_child(sprite)


static func _add_directional_shadow(
		parent: Node2D,
		texture_path: String,
		fallback_diameter: float,
		size_scale: float = 1.0,
		footprint_override: Vector2 = Vector2.ZERO,
		add_cast_shadow: bool = false,
		footprint_rotation: float = 0.0
) -> void:
	var entry: Dictionary = PROP_SHAPES.get(texture_path.get_file(), {})
	var override: Dictionary = ASSET_FOOTPRINT_OVERRIDES.get(texture_path.get_file(), {})
	var shape_kind := StringName(entry.get("shadow_shape", override.get("kind", entry.get("shape", "circle"))))
	var footprint: Vector2 = footprint_override
	if footprint.is_zero_approx():
		footprint = (entry.get("size", Vector2.ONE * fallback_diameter) as Vector2) * size_scale
	if footprint.x <= 0.0 or footprint.y <= 0.0:
		footprint = Vector2.ONE * fallback_diameter
	var shadow_path := SHADOW_CIRCLE_TEXTURE if shape_kind == &"circle" else SHADOW_RECT_TEXTURE
	var shadow_texture := load(shadow_path) as Texture2D
	if shadow_texture == null:
		push_error("TrackBuilderCore: directional shadow asset is missing: %s" % shadow_path)
		return
	var visual_shadow_kind := &"circle" if shape_kind == &"circle" else &"rect"
	var longest := maxf(footprint.x, footprint.y)
	var local_light_direction := SHADOW_DIRECTION.rotated(-parent.rotation).normalized()
	var contact := Sprite2D.new()
	contact.name = "ContactShadow"
	contact.texture = shadow_texture
	contact.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	contact.position = local_light_direction * longest * 0.10
	contact.rotation = footprint_rotation
	contact.scale = Vector2(footprint.x * 1.08 / shadow_texture.get_width(), footprint.y * 1.08 / shadow_texture.get_height())
	contact.modulate = SHADOW_TINT
	contact.z_index = -2
	contact.set_meta("shadow_shape", visual_shadow_kind)
	contact.set_meta("light_direction", SHADOW_DIRECTION)
	_mark_flat_visual(contact, shadow_path, &"shadow")
	parent.add_child(contact)
	if not add_cast_shadow:
		return
	var cast_texture := load(SHADOW_RECT_TEXTURE) as Texture2D
	if cast_texture == null:
		return
	var cast := Sprite2D.new()
	cast.name = "CastShadow"
	cast.texture = cast_texture
	cast.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	cast.position = local_light_direction * longest * 0.34
	cast.rotation = SHADOW_DIRECTION.angle() - parent.rotation
	cast.scale = Vector2(longest * 0.56 / cast_texture.get_width(), minf(footprint.x, footprint.y) * 0.66 / cast_texture.get_height())
	cast.modulate = GIANT_CAST_SHADOW_TINT
	cast.z_index = -3
	cast.set_meta("light_direction", SHADOW_DIRECTION)
	_mark_flat_visual(cast, SHADOW_RECT_TEXTURE, &"shadow")
	parent.add_child(cast)


static func _build_generated_obstacles(root: Node2D, spec: Dictionary) -> void:
	var container := Node2D.new()
	container.name = "PermanentObstacles"
	container.set_meta("seed", int(spec.get("obstacle_seed", 0)))
	container.set_meta("enabled", bool(spec.get("obstacles_enabled", true)))
	container.set_meta("role", &"permanent_obstacle_set")
	root.add_child(container)
	var plan: Array = spec.get("obstacle_plan", [])
	var minimum_clearance := INF
	for entry_value: Variant in plan:
		var entry := entry_value as Dictionary
		_add_planned_obstacle(container, entry)
		minimum_clearance = minf(minimum_clearance, float(entry.get("viable_corridor_width", 0.0)))
	container.set_meta("placed_count", container.get_child_count())
	container.set_meta("minimum_viable_corridor_width", minimum_clearance if not plan.is_empty() else HALF_WIDTH * 2.0)
	root.set_meta("minimum_obstacle_corridor_width", minimum_clearance if not plan.is_empty() else HALF_WIDTH * 2.0)


static func _add_planned_obstacle(parent: Node2D, data: Dictionary) -> void:
	var obstacle := StaticBody2D.new()
	obstacle.name = String(data.get("instance_id", data.get("id", "Obstacle"))).to_pascal_case()
	obstacle.position = data["position"]
	obstacle.rotation = float(data.get("rotation", 0.0))
	obstacle.collision_layer = 16
	var asset_path := String(data["asset"])
	_mark_solid_body(obstacle, asset_path, &"permanent_obstacle")
	for key: String in ["id", "instance_id", "role", "footprint_kind", "footprint_size", "visual_bounds", "clearance", "centerline_index", "side", "lateral_footprint_extent", "lateral_center_offset", "viable_corridor_width", "validated_ai_routes"]:
		if data.has(key):
			obstacle.set_meta(key, data[key])
	parent.add_child(obstacle)
	var texture := load(asset_path) as Texture2D
	if texture == null:
		return
	var visual_size: Vector2 = data["visual_size"]
	var sprite_scale := maxf(visual_size.x, visual_size.y) / maxf(texture.get_width(), texture.get_height())
	var shape_kind := StringName(data["footprint_kind"])
	var offset := _add_scaled_texture_collision(obstacle, texture, sprite_scale, shape_kind)
	obstacle.set_meta("collision_footprint_size", data["footprint_size"])
	obstacle.set_meta("collision_shape_kind", shape_kind)
	obstacle.set_meta("collision_footprint_rotation", 0.0)
	_add_directional_shadow(obstacle, asset_path, maxf(visual_size.x, visual_size.y), 1.0, data["footprint_size"])
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.scale = Vector2.ONE * sprite_scale
	sprite.position = -offset
	_mark_solid_visual(sprite, asset_path, &"permanent_obstacle")
	sprite.set_meta("visual_bounds", data["visual_bounds"])
	obstacle.add_child(sprite)


static func _add_obstacle(parent: Node, node_name: String, position: Vector2, radius: float, texture_path: String) -> void:
	var obstacle := StaticBody2D.new()
	obstacle.name = node_name
	obstacle.position = position
	obstacle.collision_layer = 2
	_mark_solid_body(obstacle, texture_path, &"obstacle")
	parent.add_child(obstacle)
	_add_directional_shadow(obstacle, texture_path, radius * 2.4)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		var sprite_scale := radius * 2.4 / maxf(longest, 1.0)
		sprite.scale = Vector2.ONE * sprite_scale
		var entry: Dictionary = PROP_SHAPES.get(texture_path.get_file(), {})
		var offset := _add_scaled_texture_collision(obstacle, texture, sprite_scale, StringName(entry.get("shape", &"circle")))
		sprite.position = -offset
		_mark_solid_visual(sprite, texture_path, &"obstacle")
		obstacle.add_child(sprite)


static func _add_prop_with_collision(parent: Node, position: Vector2, radius: float, texture_path: String) -> void:
	var prop := StaticBody2D.new()
	prop.name = "ApronProp"
	prop.position = position
	prop.collision_layer = 2
	_mark_solid_body(prop, texture_path, &"apron_prop")
	parent.add_child(prop)
	_add_directional_shadow(prop, texture_path, radius * 2.4)
	var texture := load(texture_path) as Texture2D
	if texture:
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var longest := maxf(texture.get_width(), texture.get_height())
		var sprite_scale := radius * 2.4 / maxf(longest, 1.0)
		sprite.scale = Vector2.ONE * sprite_scale
		var entry: Dictionary = PROP_SHAPES.get(texture_path.get_file(), {})
		var offset := _add_scaled_texture_collision(prop, texture, sprite_scale, StringName(entry.get("shape", &"circle")))
		sprite.position = -offset
		_mark_solid_visual(sprite, texture_path, &"apron_prop")
		prop.add_child(sprite)


static func _add_textured_polygon(
		parent: Node,
		node_name: String,
		points: PackedVector2Array,
		texture_path: String,
		fallback_color: Color,
		z: int,
		tile_world_size: Vector2 = DEFAULT_FLOOR_TILE_WORLD_SIZE,
		modulate_color: Color = Color.WHITE
) -> void:
	var visual := Polygon2D.new()
	visual.name = node_name
	visual.z_index = z
	visual.polygon = points
	var texture := load(texture_path) as Texture2D if not texture_path.is_empty() else null
	if texture:
		visual.texture = texture
		visual.color = modulate_color
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		visual.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		var uvs := PackedVector2Array()
		# Polygon2D UVs are texture pixels. Track-space coordinates keep adjacent
		# surface pieces in phase instead of stretching a few texels over the room.
		for point: Vector2 in points:
			uvs.append(point / tile_world_size * texture.get_size())
		visual.uv = uvs
	else:
		visual.color = fallback_color
	_mark_flat_visual(visual, texture_path, &"ground_surface")
	parent.add_child(visual)


static func _expand_loop(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var count := points.size()
	var result := PackedVector2Array()
	for index in count:
		var prev := points[(index - 1 + count) % count]
		var next := points[(index + 1) % count]
		var tangent := (next - prev).normalized()
		var normal := tangent.rotated(-PI * 0.5)
		var centroid := Vector2.ZERO
		for point: Vector2 in points:
			centroid += point
		centroid /= float(count)
		if normal.dot(centroid - points[index]) < 0.0:
			normal = -normal
		result.append(points[index] + normal * distance)
	return result


static func _add_centerline_tiles(parent: Node, centerline: PackedVector2Array, texture_path: String, modulate_value: float = 1.35, world_tile_size: Vector2 = Vector2.ZERO, opacity: float = 0.52, tint: Color = Color.WHITE, edge_feather: float = 0.16) -> void:
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return
	# A single textured ribbon avoids the overlapping square cards that made
	# every circuit read as the same scalloped chain of floor tiles.
	var surface := Line2D.new()
	surface.name = "TrackSurface"
	surface.points = centerline
	surface.closed = true
	surface.width = HALF_WIDTH * 2.0
	surface.texture = texture
	surface.texture_mode = Line2D.LINE_TEXTURE_TILE
	surface.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	surface.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	surface.default_color = Color(tint.r * modulate_value, tint.g * modulate_value, tint.b * modulate_value, opacity)
	if world_tile_size.x > 0 and world_tile_size.y > 0:
		var material := ShaderMaterial.new()
		material.shader = WORLD_SURFACE_SHADER
		material.set_shader_parameter("tile_world_size", world_tile_size)
		material.set_shader_parameter("edge_feather", edge_feather)
		surface.material = material
	surface.joint_mode = Line2D.LINE_JOINT_ROUND
	surface.begin_cap_mode = Line2D.LINE_CAP_ROUND
	surface.end_cap_mode = Line2D.LINE_CAP_ROUND
	surface.antialiased = true
	surface.z_index = -9
	_mark_flat_visual(surface, texture_path, &"track_surface")
	parent.add_child(surface)


static func _add_start_banner(parent: Node, start: Vector2, tangent: Vector2, corridor: PackedVector2Array) -> void:
	var normal := tangent.rotated(PI * 0.5)
	var along := Vector2(tangent.y, -tangent.x)
	if Geometry2D.is_point_in_polygon(start + normal * (HALF_WIDTH + 60.0), corridor):
		normal = -normal
	var banner_center := start - normal * (HALF_WIDTH + 46.0)
	for block in 6:
		var center := banner_center + along * (float(block) - 2.5) * 22.0
		_add_polygon(parent, "BannerBlock%d" % block, PackedVector2Array([
			center - tangent * 22.0 - along * 11.0,
			center + tangent * 22.0 - along * 11.0,
			center + tangent * 22.0 + along * 11.0,
			center - tangent * 22.0 + along * 11.0,
		]), Color("f2ead7") if block % 2 == 0 else Color("c94f38"), -8)
		_mark_flat_visual(parent.get_node("BannerBlock%d" % block) as Polygon2D, "", &"start_banner")


static func _add_corridor_patterning(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, room_polygon: PackedVector2Array) -> void:
	# Visual-only overlays inside the corridor band to sell theme material
	# (woodgrain, cork, desk pad) without racing lines or grip changes.
	var patterns: Array = spec.get("corridor_patterns", [])
	if patterns.is_empty():
		return
	var container := Node2D.new()
	container.name = "CorridorPatterns"
	container.z_index = -8
	root.add_child(container)
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix_seed(int(spec.get("material_seed", spec.get("requested_seed", 0))), "corridor_pattern:%s" % String(spec.get("story_id", "")))
	var target := 32
	var placed := 0
	for attempt in 220:
		var t := rng.randf()
		var idx := int(t * centerline.size())
		var pos := centerline[idx]
		var normal := _sample_tangent(centerline, idx).rotated(PI * 0.5)
		var dist := rng.randf_range(18.0, HALF_WIDTH - 32.0)
		var side := 1 if rng.randf() > 0.5 else -1
		var candidate := pos + normal * dist * side
		if not Geometry2D.is_point_in_polygon(candidate, room_polygon):
			continue
		var tex_path := String(patterns[rng.randi() % patterns.size()])
		var tex := load(tex_path) as Texture2D
		if tex == null:
			continue
		var spr := Sprite2D.new()
		spr.name = "Pattern%02d" % placed
		spr.texture = tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		spr.position = candidate
		spr.rotation = rng.randf_range(0.0, TAU)
		var sz := rng.randf_range(36.0, 68.0)
		var longest := maxf(tex.get_width(), tex.get_height())
		spr.scale = Vector2.ONE * (sz / maxf(longest, 1.0))
		spr.modulate = Color(1.0, 1.0, 1.0, rng.randf_range(0.11, 0.26))
		spr.z_index = -8
		spr.set_meta("asset_path", tex_path)
		spr.set_meta("moment_kind", &"corridor_pattern")
		_mark_flat_visual(spr, tex_path, &"corridor_pattern")
		container.add_child(spr)
		placed += 1
		if placed >= target:
			break
	container.set_meta("placed_count", placed)


static func _add_boundary_worn_hint(container: Node2D, centerline: PackedVector2Array, boundary: PackedVector2Array, run_center: int, room_polygon: PackedVector2Array) -> void:
	var tex := load("res://assets/textures/edge_dressing/worn_floor_hint.png") as Texture2D
	if tex == null:
		tex = load("res://assets/textures/edge_dressing/shadow_strip.png") as Texture2D
	if tex == null:
		return
	var idx := posmod(run_center + 4, centerline.size())
	var sample := _closest_point_on_loop(centerline[idx], boundary)
	var pos: Vector2 = sample["position"]
	var away := (pos - centerline[idx]).normalized()
	pos += away * 6.0
	if not Geometry2D.is_point_in_polygon(pos, room_polygon):
		pos = sample["position"]
	var spr := Sprite2D.new()
	spr.name = "EmptyRunHint"
	spr.texture = tex
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	spr.position = pos
	spr.rotation = _sample_tangent(centerline, idx).angle()
	var sc := 220.0 / maxf(tex.get_width(), 1.0)
	spr.scale = Vector2.ONE * sc
	spr.modulate = Color(1.0, 1.0, 1.0, 0.55)
	spr.z_index = -5
	_mark_flat_visual(spr, tex.resource_path, &"worn_hint")
	container.add_child(spr)


static func _mark_owned(root: Node) -> void:
	for child in root.get_children():
		child.owner = root
		if child.scene_file_path.is_empty():
			_assign_owners(child, root)


static func _assign_owners(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		if child.scene_file_path.is_empty():
			_assign_owners(child, owner)
