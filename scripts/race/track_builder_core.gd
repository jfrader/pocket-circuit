class_name TrackBuilderCore
## Runtime + headless track builder: builds a painted toy-racing circuit scene
## (spline corridor, island prop, walls, gates, grid, props) from a theme spec,
## a room shape, and a seed. Pure runtime code — no SceneTree/editor deps — so
## the race can generate any arbitrary seed on demand.

const CHECKPOINT_SCRIPT := preload("res://scripts/race/checkpoint.gd")
const VISUAL_ROLE_CONTRACT := preload("res://scripts/race/generated_world_visual_role.gd")
const GENERATED_RULES := preload("res://scripts/race/generated_circuit_rules.gd")
const WORLD_MATERIALS := preload("res://scripts/race/generated_world_materials.gd")
const PROP_SCALE := preload("res://scripts/race/world_prop_scale.gd")
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
const TRACK_BUILDER_COLLISION := preload("res://scripts/race/track_builder_collision.gd")
const TRACK_BUILDER_RACING := preload("res://scripts/race/track_builder_racing.gd")
const HALF_WIDTH := 125.0
const GRID_ROW_DISTANCES := [100.0, 220.0]
const GRID_LANE_OFFSET := 35.0
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
		var length_tier := StringName(generation_options.get("length_tier", &"standard"))
		var profile := TrackSeedGen.length_profile(length_tier)
		if profile.is_empty():
			return {}
		# Large tiers scale the room footprint (never the road width or corner
		# radii), so the same road/radius constraints hold while the loop runs
		# longer through more sections rather than a wider corridor.
		var room_scale := float(profile.get("room_scale", 1.0))
		if absf(room_scale - 1.0) > 0.001:
			var scaled_room := PackedVector2Array()
			for point: Vector2 in room_polygon:
				scaled_room.append(point * room_scale)
			room_polygon = scaled_room
		var room_params := {
			"margin": 190.0,
			"min_point_distance": 210.0,
			"max_angle_deg": 80.0,
			"min_self_distance": 320.0,
			"min_loop_length": 1900.0 * WORLD_SCALE,
			"room_polygon": room_polygon,
			"room_shape": room_shape,
			"length_tier": length_tier,
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
		spec["pockets"] = gen.get("pockets", [])
		spec["generation_attempt"] = int(gen.get("attempt", 0))
		spec["generation_fallback"] = bool(gen.get("fallback", false))
		spec["loop_length"] = float(gen["length"])
		spec["length_tier"] = String(gen.get("length_tier", "standard"))
		spec["target_length"] = float(gen.get("target_length", gen["length"]))
		spec["corner_profiles"] = gen.get("corner_profiles", {}).duplicate(true)
		spec["motifs"] = gen.get("motifs", []).duplicate()
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
	if not bool(generation_options.get("preview_composer", false)):
		var left: PackedVector2Array = edges["left"]
		var right: PackedVector2Array = edges["right"]
		var inner: PackedVector2Array = edges["inner_boundary"] if edges.has("inner_boundary") else _simple_inner_boundary_loop(left if absf(_polygon_area(left)) < absf(_polygon_area(right)) else right, centerline)
		var story: Dictionary = spec.get("story_kit", STORY_KITS[theme][0]).duplicate(true)
		spec["story_kit"] = story
		spec["environment_theme"] = theme
		spec["environment_room_polygon"] = room_polygon
		spec["environment_island_polygon"] = inner
		var candidates := WorldEnvironmentCatalog.candidates(theme, story, spec)
		spec["environment_assets"] = candidates
		var reserved: Array[PackedVector2Array] = []
		spec["pocket_regions"] = TrackBuilderCollision.pocket_regions(spec, centerline, room_polygon)
		for pocket: Dictionary in spec["pocket_regions"]:
			reserved.append(pocket["collision"])
		var gate_points := _layout_gate_samples(centerline, spec)
		var post_assets: Array = spec.get("gate_props", [])
		if not post_assets.is_empty():
			for gate_index in gate_points.size():
				var closest := _closest_point_on_loop(gate_points[gate_index], centerline)
				var tangent := _sample_tangent(centerline, int(closest["index"]))
				for side in [-1, 1]:
					var path := String(post_assets[posmod(gate_index * 2 + (1 if side > 0 else 0), post_assets.size())])
					var size := PROP_SCALE.size_for(path, GATE_POST_SIZE) + Vector2.ONE * 6.0
					var offset := FINISH_LANDMARK_OFFSET if gate_index == 0 else GATE_POST_OFFSET
					reserved.append(TRACK_BUILDER_BOUNDARY._footprint_polygon(gate_points[gate_index] + tangent.rotated(PI * 0.5) * offset * side, size, tangent.angle()))
		spec["environment_plan"] = WorldEnvironmentPlan.plan(theme, int(spec.get("dressing_seed", _mix_seed(maxi(seed, 0), "dressing"))), {"room_polygon":room_polygon,"island_polygon":inner,"centerline":centerline,"corridor_half_width":HALF_WIDTH,"reserved_polygons":reserved}, candidates, {})
		spec["surface_identity"] = HouseholdSurfaceMaterials.resolve(theme, int(spec.get("material_seed", _mix_seed(maxi(seed, 0), "material"))), String(spec.get("material_id", "")), String(spec.get("palette_id", "")), spec.get("floor_modulate", Color.WHITE))
		spec["floor_texture"] = spec["surface_identity"]["floor"]["texture"]
		spec["track_texture"] = spec["surface_identity"]["course"]["texture"]
		spec["island_material_texture"] = spec["surface_identity"]["island"]["texture"]
		spec["floor_modulate"] = Color.WHITE
		spec["ambient_props"] = []
		spec["corridor_patterns"] = []
		prepared["spec"] = spec
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
		root.set_meta("length_tier", spec.get("length_tier", "standard"))
		root.set_meta("target_length", spec.get("target_length", spec["loop_length"]))
		root.set_meta("corner_profiles", spec.get("corner_profiles", {}))
		root.set_meta("motifs", spec.get("motifs", []))
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


static func assemble_runtime(root: Node2D, prepared: Dictionary, stage: Callable, environment_composer: Callable = Callable()) -> void:
	await _build_scene(root, prepared["spec"], prepared["centerline"], prepared["edges"], prepared["room_polygon"], prepared["theme"], stage, environment_composer)


static func _sample_centerline(controls: Variant) -> PackedVector2Array:
	if controls is PackedVector2Array:
		return TRACK_BUILDER_GEOMETRY.sample_centerline(controls)
	var packed := PackedVector2Array()
	if controls is Array:
		for point: Vector2 in controls:
			packed.append(point)
	return TRACK_BUILDER_GEOMETRY.sample_centerline(packed)


static func _corridor_edges(centerline: PackedVector2Array) -> Dictionary:
	return TRACK_BUILDER_GEOMETRY.corridor_edges(centerline)

static func _build_scene(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, edges: Dictionary, room_polygon: PackedVector2Array, theme: StringName, stage: Callable = Callable(), environment_composer: Callable = Callable()) -> void:
	await TRACK_BUILDER_SCENE.build(root, spec, centerline, edges, room_polygon, theme, stage, environment_composer)




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


static func _formation_assets(data: Dictionary) -> Array[String]:
	return TRACK_BUILDER_DRESSING.formation_assets(data)


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
		occupied: Array[Dictionary],
		stage: Callable = Callable()
) -> void:
	await TRACK_BUILDER_DRESSING.build_track_formation(parent, node_name, data, quantity, moment_index, centerline, outer_loop, room_polygon, gate_samples, occupied, stage)


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
	TRACK_BUILDER_RACING.fill_island(root, spec, inner_loop, centerline)


static func _line_boundary_props(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, outer_loop: PackedVector2Array, corridor: PackedVector2Array, room_polygon: PackedVector2Array) -> void:
	TRACK_BUILDER_RACING.line_boundary_props(root, spec, centerline, outer_loop, corridor, room_polygon)


static func _build_racing_line(root: Node2D, centerline: PackedVector2Array, moments: Dictionary = {}) -> void:
	TRACK_BUILDER_RACING.build_racing_line(root, centerline, moments)


static func _racing_line_points(centerline: PackedVector2Array, moments: Dictionary, use_shortcut: bool) -> PackedVector2Array:
	return TRACK_BUILDER_RACING.racing_line_points(centerline, moments, use_shortcut)


static func _add_hidden_racing_line(parent: Node2D, line_name: String, points: PackedVector2Array) -> Line2D:
	return TRACK_BUILDER_RACING.add_hidden_racing_line(parent, line_name, points)


static func _curvature_apex_line(centerline: PackedVector2Array) -> PackedVector2Array:
	return TRACK_BUILDER_RACING.curvature_apex_line(centerline)


static func _signed_turn_at(centerline: PackedVector2Array, index: int, span: int) -> float:
	return TRACK_BUILDER_RACING.signed_turn_at(centerline, index, span)


static func _add_corner_set_pieces(root: Node2D, spec: Dictionary, room_polygon: PackedVector2Array, corridor: PackedVector2Array) -> void:
	TRACK_BUILDER_RACING.add_corner_set_pieces(root, spec, room_polygon, corridor)


static func _island_apexes(inner_loop: PackedVector2Array) -> PackedVector2Array:
	return TRACK_BUILDER_RACING.island_apexes(inner_loop)


static func _add_paperclip_line(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, outer_loop: PackedVector2Array, room_polygon: PackedVector2Array) -> void:
	TRACK_BUILDER_RACING.add_paperclip_line(root, spec, centerline, outer_loop, room_polygon)


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
	TRACK_BUILDER_COLLISION.mark_solid_body(body, texture_path, solid_class)


static func _mark_solid_visual(visual: CanvasItem, texture_path: String, solid_class: StringName) -> void:
	TRACK_BUILDER_COLLISION.mark_solid_visual(visual, texture_path, solid_class)


static func _mark_flat_visual(visual: CanvasItem, texture_path: String, flat_class: StringName) -> void:
	TRACK_BUILDER_COLLISION.mark_flat_visual(visual, texture_path, flat_class)


static func _texture_opaque_rect(texture: Texture2D) -> Rect2:
	return TRACK_BUILDER_COLLISION.texture_opaque_rect(texture)


static func _texture_alpha_outline(texture: Texture2D) -> Dictionary:
	return TRACK_BUILDER_COLLISION.texture_alpha_outline(texture)


static func has_prepared_outline(texture: Texture2D) -> bool:
	return TRACK_BUILDER_COLLISION.has_prepared_outline(texture)


static func has_prepared_outline_path(path: String) -> bool:
	return TRACK_BUILDER_COLLISION.has_prepared_outline_path(path)


static func install_prepared_outline(texture: Texture2D, outline: Dictionary) -> void:
	TRACK_BUILDER_COLLISION.install_prepared_outline(texture, outline)


static func preparation_texture_paths(value: Variant) -> Array[String]:
	return TRACK_BUILDER_COLLISION.preparation_texture_paths(value)


static func compute_alpha_outline(image: Image, width: int, height: int) -> Dictionary:
	return TRACK_BUILDER_COLLISION.compute_alpha_outline(image, width, height)


static func _texture_collision_footprint(texture: Texture2D, shape_kind: StringName, force_axis_aligned: bool = false) -> Dictionary:
	return TRACK_BUILDER_COLLISION.texture_collision_footprint(texture, shape_kind, force_axis_aligned)


static func _axis_aligned_texture_footprint(used: Rect2, shape_kind: StringName) -> Dictionary:
	return TRACK_BUILDER_COLLISION.axis_aligned_texture_footprint(used, shape_kind)


static func _texture_convex_hull(texture: Texture2D) -> PackedVector2Array:
	return TRACK_BUILDER_COLLISION.texture_convex_hull(texture)


static func _balanced_circle_texture_footprint(texture: Texture2D, used: Rect2) -> Dictionary:
	return TRACK_BUILDER_COLLISION.balanced_circle_texture_footprint(texture, used)


static func _record_shape_probe_points(parent: Node, center: Vector2, size: Vector2, shape_kind: StringName, rotation: float = 0.0) -> void:
	TRACK_BUILDER_COLLISION.record_shape_probe_points(parent, center, size, shape_kind, rotation)


static func _record_convex_probe_points(parent: Node, points: PackedVector2Array) -> void:
	TRACK_BUILDER_COLLISION.record_convex_probe_points(parent, points)


static func _add_scaled_texture_collision(parent: Node, texture: Texture2D, sprite_scale: float, shape_kind: StringName) -> Vector2:
	return TRACK_BUILDER_COLLISION.add_scaled_texture_collision(parent, texture, sprite_scale, shape_kind)


static func _add_texture_collision(
		parent: Node,
		texture: Texture2D,
		sprite_scale: Vector2,
		shape_kind: StringName,
		force_axis_aligned: bool = false,
		padding: float = 0.0
) -> Vector2:
	return TRACK_BUILDER_COLLISION.add_texture_collision(parent, texture, sprite_scale, shape_kind, force_axis_aligned, padding)


static func _add_giant_collision(parent: Node, texture_path: String, sprite_scale: float) -> Vector2:
	return TRACK_BUILDER_COLLISION.add_giant_collision(parent, texture_path, sprite_scale)


static func _add_boundary_prop(parent: Node, position: Vector2, radius: float, texture_path: String, rotation: float) -> void:
	TRACK_BUILDER_COLLISION.add_boundary_prop(parent, position, radius, texture_path, rotation)


static func _add_fill_prop(parent: Node, position: Vector2, radius: float, texture_path: String, rotation: float) -> void:
	TRACK_BUILDER_COLLISION.add_fill_prop(parent, position, radius, texture_path, rotation)


static func _add_directional_shadow(
		parent: Node2D,
		texture_path: String,
		fallback_diameter: float,
		size_scale: float = 1.0,
		footprint_override: Vector2 = Vector2.ZERO,
		add_cast_shadow: bool = false,
		footprint_rotation: float = 0.0
) -> void:
	TRACK_BUILDER_COLLISION.add_directional_shadow(parent, texture_path, fallback_diameter, size_scale, footprint_override, add_cast_shadow, footprint_rotation)


static func _build_generated_obstacles(root: Node2D, spec: Dictionary) -> void:
	TRACK_BUILDER_COLLISION.build_generated_obstacles(root, spec)


static func _add_planned_obstacle(parent: Node2D, data: Dictionary) -> void:
	TRACK_BUILDER_COLLISION.add_planned_obstacle(parent, data)


static func _add_obstacle(parent: Node, node_name: String, position: Vector2, radius: float, texture_path: String) -> void:
	TRACK_BUILDER_COLLISION.add_obstacle(parent, node_name, position, radius, texture_path)


static func _add_prop_with_collision(parent: Node, position: Vector2, radius: float, texture_path: String) -> void:
	TRACK_BUILDER_COLLISION.add_prop_with_collision(parent, position, radius, texture_path)


static func _seal_pockets(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, room_polygon: PackedVector2Array) -> void:
	TRACK_BUILDER_COLLISION.seal_pockets(root, spec, centerline, room_polygon)


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
	TRACK_BUILDER_COLLISION.add_textured_polygon(parent, node_name, points, texture_path, fallback_color, z, tile_world_size, modulate_color)


static func _expand_loop(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	return TRACK_BUILDER_COLLISION.expand_loop(points, distance)


static func _add_centerline_tiles(parent: Node, centerline: PackedVector2Array, texture_path: String, modulate_value: float = 1.35, world_tile_size: Vector2 = Vector2.ZERO, opacity: float = 0.52, tint: Color = Color.WHITE, edge_feather: float = 0.16) -> void:
	TRACK_BUILDER_COLLISION.add_centerline_tiles(parent, centerline, texture_path, modulate_value, world_tile_size, opacity, tint, edge_feather)


static func _add_start_banner(parent: Node, start: Vector2, tangent: Vector2, corridor: PackedVector2Array) -> void:
	TRACK_BUILDER_COLLISION.add_start_banner(parent, start, tangent, corridor)


static func _add_corridor_patterning(root: Node2D, spec: Dictionary, centerline: PackedVector2Array, room_polygon: PackedVector2Array) -> void:
	TRACK_BUILDER_COLLISION.add_corridor_patterning(root, spec, centerline, room_polygon)


static func _add_boundary_worn_hint(container: Node2D, centerline: PackedVector2Array, boundary: PackedVector2Array, run_center: int, room_polygon: PackedVector2Array) -> void:
	TRACK_BUILDER_COLLISION.add_boundary_worn_hint(container, centerline, boundary, run_center, room_polygon)


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
