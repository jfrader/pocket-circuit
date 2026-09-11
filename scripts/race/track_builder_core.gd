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
const TRACK_BUILDER_SCENE := preload("res://scripts/race/track_builder_scene.gd")
const TRACK_BUILDER_ISLAND := preload("res://scripts/race/track_builder_island.gd")
const TRACK_BUILDER_STORY := preload("res://scripts/race/track_builder_story.gd")
const TRACK_BUILDER_DRESSING := preload("res://scripts/race/track_builder_dressing.gd")
const TRACK_BUILDER_BOUNDARY := preload("res://scripts/race/track_builder_boundary.gd")
const TRACK_BUILDER_NODES := preload("res://scripts/race/track_builder_nodes.gd")
const TRACK_BUILDER_PLACEMENT := preload("res://scripts/race/track_builder_placement.gd")
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
	await TRACK_BUILDER_SCENE.build(root, spec, centerline, edges, room_polygon, theme, stage)




static func _build_island_prop(root: Node2D, spec: Dictionary, region: PackedVector2Array, inner_loop: PackedVector2Array, centerline: PackedVector2Array, stage: Callable = Callable()) -> void:
	await TRACK_BUILDER_ISLAND.build_island_prop(root, spec, region, inner_loop, centerline, stage)


static func _build_raised_island_rim(parent: StaticBody2D, spec: Dictionary, points: PackedVector2Array) -> void:
	TRACK_BUILDER_ISLAND.build_raised_island_rim(parent, spec, points)


static func _add_island_rim_landmarks(root: Node2D, spec: Dictionary, boundary: PackedVector2Array, centerline: PackedVector2Array, stage: Callable = Callable()) -> void:
	await TRACK_BUILDER_ISLAND.add_island_rim_landmarks(root, spec, boundary, centerline, stage)


static func _build_generated_outer_boundary_visuals(
	root: Node2D,
	spec: Dictionary,
	centerline: PackedVector2Array,
	inner_boundary: PackedVector2Array,
	outer_boundary: PackedVector2Array,
	room_polygon: PackedVector2Array,
	moments: Dictionary
) -> void:
	TRACK_BUILDER_BOUNDARY.build_generated_outer_boundary_visuals(root, spec, centerline, inner_boundary, outer_boundary, room_polygon, moments)


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
	return TRACK_BUILDER_BOUNDARY.add_generated_boundary_section(container, textures, centerline, boundary, room_polygon, centerline_index, run_index, side, side_index)


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
	return TRACK_BUILDER_BOUNDARY.add_generated_boundary_run_fallback(container, textures, centerline, boundary, room_polygon, run_center, run_index, side, side_index)


static func _push_outside_corridor(position: Vector2, centerline: PackedVector2Array, fallback_direction: Vector2) -> Vector2:
	return TRACK_BUILDER_BOUNDARY.push_outside_corridor(position, centerline, fallback_direction)


static func _push_footprint_outside_corridor(
		position: Vector2,
		centerline: PackedVector2Array,
		fallback_direction: Vector2,
		footprint_size: Vector2,
		rotation: float
) -> Vector2:
	return TRACK_BUILDER_BOUNDARY.push_footprint_outside_corridor(position, centerline, fallback_direction, footprint_size, rotation)


static func _advance_footprint_outside_corridor(
		position: Vector2,
		centerline: PackedVector2Array,
		fallback_direction: Vector2,
		footprint_size: Vector2,
		rotation: float
) -> Vector2:
	return TRACK_BUILDER_BOUNDARY.advance_footprint_outside_corridor(position, centerline, fallback_direction, footprint_size, rotation)


static func _pull_inside_room(position: Vector2, centerline: PackedVector2Array, room_polygon: PackedVector2Array) -> Vector2:
	return TRACK_BUILDER_BOUNDARY.pull_inside_room(position, centerline, room_polygon)


static func _closest_point_on_loop(point: Vector2, loop: PackedVector2Array) -> Dictionary:
	return TRACK_BUILDER_BOUNDARY.closest_point_on_loop(point, loop)


static func _island_region(room_polygon: PackedVector2Array, ribbon: PackedVector2Array, hint_polygon: PackedVector2Array) -> PackedVector2Array:
	return TRACK_BUILDER_BOUNDARY.island_region(room_polygon, ribbon, hint_polygon)


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
	TRACK_BUILDER_NODES.add_polygon(parent, node_name, points, color, z)


static func _add_finish_checker(parent: Node2D, finish: Vector2, tangent: Vector2) -> void:
	TRACK_BUILDER_NODES.add_finish_checker(parent, finish, tangent)


static func _add_wall_segment(parent: Node, node_name: String, position: Vector2, length: float, rotation: float, edge_texture_path: String) -> void:
	TRACK_BUILDER_NODES.add_wall_segment(parent, node_name, position, length, rotation, edge_texture_path)


static func _gate_span_endpoints(sample: Vector2, tangent: Vector2, room_polygon: PackedVector2Array, island_polygon: PackedVector2Array) -> PackedVector2Array:
	return TRACK_BUILDER_NODES.gate_span_endpoints(sample, tangent, room_polygon, island_polygon)


static func _corridor_gate_endpoint(sample: Vector2, direction: Vector2, room_polygon: PackedVector2Array, island_polygon: PackedVector2Array) -> Vector2:
	return TRACK_BUILDER_NODES.corridor_gate_endpoint(sample, direction, room_polygon, island_polygon)


static func _nearest_gate_boundary(sample: Vector2, direction: Vector2, room_polygon: PackedVector2Array, island_polygon: PackedVector2Array) -> Vector2:
	return TRACK_BUILDER_NODES.nearest_gate_boundary(sample, direction, room_polygon, island_polygon)


static func _add_gate_posts(root: Node2D, spec: Dictionary, sample: Vector2, tangent: Vector2, gate_index: int) -> void:
	TRACK_BUILDER_NODES.add_gate_posts(root, spec, sample, tangent, gate_index)


static func _add_cp(parent: Node, node_name: String, position: Vector2, rotation: float, index: int, is_finish: bool, recovery_rotation: float, span_endpoints: PackedVector2Array = PackedVector2Array()) -> void:
	TRACK_BUILDER_NODES.add_cp(parent, node_name, position, rotation, index, is_finish, recovery_rotation, span_endpoints)


static func _add_grid(parent: Node, node_name: String, rotation: float, positions: Array, rotations: Array = []) -> void:
	TRACK_BUILDER_NODES.add_grid(parent, node_name, rotation, positions, rotations)


static func _scatter_decals(root: Node2D, spec: Dictionary, room_polygon: PackedVector2Array, corridor: PackedVector2Array, rng: RandomNumberGenerator) -> void:
	TRACK_BUILDER_NODES.scatter_decals(root, spec, room_polygon, corridor, rng)


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
	await TRACK_BUILDER_STORY.compose_generated_story(root, spec, centerline, inner_loop, outer_loop, room_polygon, gate_samples, moments, stage)


static func _analyze_track_moments(centerline: PackedVector2Array, gate_samples: PackedVector2Array) -> Dictionary:
	return TRACK_BUILDER_DRESSING.analyze_track_moments(centerline, gate_samples)


static func _default_act_for_theme(theme: StringName) -> int:
	return TRACK_BUILDER_DRESSING.default_act_for_theme(theme)


static func _layout_gate_samples(centerline: PackedVector2Array, spec: Dictionary) -> PackedVector2Array:
	return TRACK_BUILDER_DRESSING.layout_gate_samples(centerline, spec)


static func _centerline_arc_positions(centerline: PackedVector2Array) -> PackedFloat32Array:
	return TRACK_BUILDER_DRESSING.centerline_arc_positions(centerline)


static func _pick_conflict_candidate(
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		arc_positions: PackedFloat32Array,
		total_length: float,
		minimum_fraction: float,
		maximum_fraction: float
) -> int:
	return TRACK_BUILDER_DRESSING.pick_conflict_candidate(centerline, gate_samples, arc_positions, total_length, minimum_fraction, maximum_fraction)


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
	return TRACK_BUILDER_DRESSING.build_opening_landmark(parent, story, spec, centerline, outer_loop, room_polygon, gate_samples, occupied)


static func _pick_straight_candidate(
		candidates: Array[Dictionary],
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		excluded: Array,
		minimum_separation: int
) -> int:
	return TRACK_BUILDER_DRESSING.pick_straight_candidate(candidates, centerline, gate_samples, excluded, minimum_separation)


static func _turn_strength(centerline: PackedVector2Array, index: int, span: int) -> float:
	return TRACK_BUILDER_GEOMETRY.turn_strength(centerline, index, span)


static func _cyclic_index_distance(first: int, second: int, count: int) -> int:
	return TRACK_BUILDER_GEOMETRY.cyclic_index_distance(first, second, count)


static func _safe_moment_index(centerline: PackedVector2Array, preferred: int, gate_samples: PackedVector2Array, clearance: float) -> int:
	return TRACK_BUILDER_DRESSING.safe_moment_index(centerline, preferred, gate_samples, clearance)


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
	await TRACK_BUILDER_STORY.build_island_story(parent, story, spec, centerline, inner_loop, room_polygon, gate_samples, occupied, stage)


static func _bounded_quantity_count(quantity: StringName, requested: int) -> int:
	return TRACK_BUILDER_DRESSING.bounded_quantity_count(quantity, requested)


static func _semantic_formation_offset(formation: StringName, index: int, count: int, radius: float) -> Vector2:
	return TRACK_BUILDER_DRESSING.semantic_formation_offset(formation, index, count, radius)


static func _island_anchor(inner_loop: PackedVector2Array, centerline: PackedVector2Array) -> Vector2:
	return TRACK_BUILDER_DRESSING.island_anchor(inner_loop, centerline)


static func _polygon_bounds_rect(points: PackedVector2Array) -> Rect2:
	return TRACK_BUILDER_DRESSING.polygon_bounds_rect(points)


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
	TRACK_BUILDER_DRESSING.build_track_formation(parent, node_name, data, quantity, moment_index, centerline, outer_loop, room_polygon, gate_samples, occupied)


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
	TRACK_BUILDER_DRESSING.build_corner_landmarks(parent, story, spec, corner_indices, centerline, outer_loop, room_polygon, gate_samples, reserved_unique_assets, occupied)


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
	await TRACK_BUILDER_DRESSING.build_room_dressing(parent, story, spec, centerline, outer_loop, room_polygon, gate_samples, reserved_unique_assets, occupied, stage)


static func _build_edge_and_apron_decor(
		parent: Node2D,
		spec: Dictionary,
		centerline: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary],
		stage: Callable = Callable()
) -> void:
	await TRACK_BUILDER_DRESSING.build_edge_and_apron_decor(parent, spec, centerline, room_polygon, gate_samples, occupied, stage)


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
	await TRACK_BUILDER_DRESSING.build_giant_landmarks(parent, spec, centerline, room_polygon, gate_samples, occupied, committed_racing_lines, stage)


static func _room_dressing_assets(story: Dictionary, spec: Dictionary, reserved_unique_assets: Dictionary) -> Array[String]:
	return TRACK_BUILDER_DRESSING.room_dressing_assets(story, spec, reserved_unique_assets)


static func _room_dressing_anchors(
		room_polygon: PackedVector2Array,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary],
		target_count: int,
		rng: RandomNumberGenerator
) -> PackedVector2Array:
	return TRACK_BUILDER_DRESSING.room_dressing_anchors(room_polygon, centerline, gate_samples, occupied, target_count, rng)


static func _build_room_ground_sections(
		parent: Node2D,
		story: Dictionary,
		spec: Dictionary,
		centerline: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		stage: Callable = Callable()
) -> int:
	return await TRACK_BUILDER_DRESSING.build_room_ground_sections(parent, story, spec, centerline, outer_loop, room_polygon, stage)


static func _build_room_floor_details(
		parent: Node2D,
		spec: Dictionary,
		centerline: PackedVector2Array,
		room_polygon: PackedVector2Array,
		occupied: Array[Dictionary],
		rng: RandomNumberGenerator
) -> int:
	return TRACK_BUILDER_DRESSING.build_room_floor_details(parent, spec, centerline, room_polygon, occupied, rng)


static func _build_generated_surfaces(root: Node2D, parent: Node2D, story: Dictionary, spec: Dictionary, moments: Dictionary, centerline: PackedVector2Array, gate_samples: PackedVector2Array) -> void:
	TRACK_BUILDER_DRESSING.build_generated_surfaces(root, parent, story, spec, moments, centerline, gate_samples)


static func _surface_strip(centerline: PackedVector2Array, center_index: int, half_span: int, half_width: float) -> PackedVector2Array:
	return TRACK_BUILDER_DRESSING.surface_strip(centerline, center_index, half_span, half_width)


static func _add_surface_decals(
		parent: Node2D,
		centerline: PackedVector2Array,
		center_index: int,
		half_span: int,
		texture_path: String,
		lateral_offset: float = 0.0
) -> void:
	TRACK_BUILDER_DRESSING.add_surface_decals(parent, centerline, center_index, half_span, texture_path, lateral_offset)


static func _shortcut_lane_geometry(centerline: PackedVector2Array, center_index: int) -> Dictionary:
	return TRACK_BUILDER_DRESSING.shortcut_lane_geometry(centerline, center_index)


static func _offset_section_path(
		centerline: PackedVector2Array,
		center_index: int,
		half_span: int,
		lateral_offset: float
) -> PackedVector2Array:
	return TRACK_BUILDER_DRESSING.offset_section_path(centerline, center_index, half_span, lateral_offset)


static func _lane_strip(path: PackedVector2Array, half_width: float) -> PackedVector2Array:
	return TRACK_BUILDER_DRESSING.lane_strip(path, half_width)


static func _open_path_length(path: PackedVector2Array) -> float:
	return TRACK_BUILDER_DRESSING.open_path_length(path)


static func _crossing_path(centerline: PackedVector2Array, center_index: int, half_width: float) -> PackedVector2Array:
	return TRACK_BUILDER_GEOMETRY.crossing_path(centerline, center_index, half_width)


static func _build_finish_moments(parent: Node2D, centerline: PackedVector2Array) -> void:
	TRACK_BUILDER_DRESSING.build_finish_moments(parent, centerline)


static func _sample_tangent(centerline: PackedVector2Array, index: int) -> Vector2:
	return TRACK_BUILDER_GEOMETRY.sample_tangent(centerline, index)


static func _placement_is_safe(
		candidate: Vector2,
		radius: float,
		room_polygon: PackedVector2Array,
		allowed_polygon: PackedVector2Array,
		occupied: Array[Dictionary]
) -> bool:
	return TRACK_BUILDER_PLACEMENT.placement_is_safe(candidate, radius, room_polygon, allowed_polygon, occupied)


static func _best_island_position(
		preferred: Vector2,
		radius: float,
		room_polygon: PackedVector2Array,
		island_polygon: PackedVector2Array,
		occupied: Array[Dictionary]
) -> Dictionary:
	return TRACK_BUILDER_PLACEMENT.best_island_position(preferred, radius, room_polygon, island_polygon, occupied)


static func _best_offtrack_position(
		preferred: Vector2,
		radius: float,
		room_polygon: PackedVector2Array,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary]
) -> Dictionary:
	return TRACK_BUILDER_PLACEMENT.best_offtrack_position(preferred, radius, room_polygon, centerline, gate_samples, occupied)


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
	return TRACK_BUILDER_PLACEMENT.best_giant_position(preferred_index, size, shape_kind, local_footprint_rotation, room_polygon, centerline, gate_samples, occupied, committed_racing_lines)


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
	return TRACK_BUILDER_PLACEMENT.giant_placement_is_safe(candidate, size, shape_kind, rotation, room_polygon, centerline, gate_samples, occupied, committed_racing_lines)


static func _committed_lines_clear_giant(
		committed_racing_lines: Array[PackedVector2Array],
		candidate: Vector2,
		size: Vector2,
		shape_kind: StringName,
		rotation: float
) -> bool:
	return TRACK_BUILDER_PLACEMENT.committed_lines_clear_giant(committed_racing_lines, candidate, size, shape_kind, rotation)


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
	return TRACK_BUILDER_PLACEMENT.oriented_rect_inside_polygon(center, size, rotation, polygon)


static func _point_to_oriented_rect_distance(point: Vector2, center: Vector2, size: Vector2, rotation: float) -> float:
	return TRACK_BUILDER_PLACEMENT.point_to_oriented_rect_distance(point, center, size, rotation)


static func _trackside_placement_is_safe(
		candidate: Vector2,
		radius: float,
		room_polygon: PackedVector2Array,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary]
) -> bool:
	return TRACK_BUILDER_PLACEMENT.trackside_placement_is_safe(candidate, radius, room_polygon, centerline, gate_samples, occupied)


static func _best_trackside_position(
		preferred_index: int,
		radius: float,
		centerline: PackedVector2Array,
		outer_loop: PackedVector2Array,
		room_polygon: PackedVector2Array,
		gate_samples: PackedVector2Array,
		occupied: Array[Dictionary]
) -> Dictionary:
	return TRACK_BUILDER_PLACEMENT.best_trackside_position(preferred_index, radius, centerline, outer_loop, room_polygon, gate_samples, occupied)


static func _inside_polygon_with_radius(point: Vector2, radius: float, polygon: PackedVector2Array) -> bool:
	return TRACK_BUILDER_PLACEMENT.inside_polygon_with_radius(point, radius, polygon)


static func _clear_of_points(point: Vector2, points: PackedVector2Array, clearance: float) -> bool:
	return TRACK_BUILDER_GEOMETRY.clear_of_points(point, points, clearance)


static func _clear_of_recovery_lanes(
		point: Vector2,
		radius: float,
		centerline: PackedVector2Array,
		gate_samples: PackedVector2Array
) -> bool:
	return TRACK_BUILDER_PLACEMENT.clear_of_recovery_lanes(point, radius, centerline, gate_samples)


static func _point_to_segment_distance(point: Vector2, from: Vector2, to: Vector2) -> float:
	return TRACK_BUILDER_GEOMETRY.point_to_segment_distance(point, from, to)


static func _clear_of_occupied(point: Vector2, radius: float, occupied: Array[Dictionary]) -> bool:
	return TRACK_BUILDER_GEOMETRY.clear_of_occupied(point, radius, occupied)


static func _asset_radius(texture_path: String, fallback_radius: float) -> float:
	return TRACK_BUILDER_PLACEMENT.asset_radius(texture_path, fallback_radius)


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
	TRACK_BUILDER_PLACEMENT.add_generated_prop(parent, node_name, position, texture_path, rotation, moment_kind, quantity, formation_index, size_scale)


static func _mix_seed(seed: int, stream: String) -> int:
	return TRACK_BUILDER_PLACEMENT.mix_seed(seed, stream)


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
