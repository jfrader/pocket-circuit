class_name AIVehicleController
extends Node

const DYNAMICS := preload("res://scripts/vehicle/vehicle_dynamics.gd")
const STUCK_TIMEOUT := 2.8
const STUCK_SPEED := 85.0
const RECOVERY_GHOST_TIME := 0.65
const RECOVERY_COOLDOWN := 5.0
const CORNER_GUIDE_AXIS_THRESHOLD := 180.0
const CORNER_GUIDE_BLEND_DISTANCE := 180.0
const CORNER_GUIDE_REACHED_DISTANCE := 40.0
const CORNER_GUIDE_OUTWARD_OFFSET := 22.0
const CORNER_GUIDE_PASS_WIDTH := 80.0
const LOOK_AHEAD_DISTANCE := 340.0
const MAX_LOOK_AHEAD_WEIGHT := 0.38
const TURN_AROUND_HEADING := 1.6
const CORNER_GRIP_UTILIZATION := 0.85
const CORRECTION_GRIP_UTILIZATION := 0.5
const TRACK_COLLISION_MASK := 2
const VEHICLE_COLLISION_MASK := 1
const SCENERY_COLLISION_MASK := 4
const SCATTER_DODGE_MASK := 16
const STATIC_OBSTACLE_MASK := TRACK_COLLISION_MASK | SCENERY_COLLISION_MASK | SCATTER_DODGE_MASK
const OBSTACLE_FEELER_ANGLES: Array[float] = [-0.95, -0.5, 0.0, 0.5, 0.95]
const OBSTACLE_FRONT_OFFSET := 30.0
const OBSTACLE_FEELER_HALF_WIDTH := 14.0
const GATE_TARGET_OFFSETS: Array[float] = [-72.0, -48.0, -24.0, 0.0, 24.0, 48.0, 72.0]
const SURFACE_PROBE_ANGLES: Array[float] = [0.0, -0.34, 0.34]
const SURFACE_PROBE_DISTANCES: Array[float] = [90.0, 170.0, 250.0]
const MAX_RACING_LINE_RADIUS := 2600.0
const OVERTAKE_REACH := 260.0
const OVERTAKE_LATERAL_REACH := 58.0
const OVERTAKE_LINE_OFFSET := 52.0
const OVERTAKE_MERGE_DISTANCE := 82.0
const OVERTAKE_CLEAR_DISTANCE := 220.0
const OVERTAKE_HOLD_TIME := 2.1
const OVERTAKE_COOLDOWN := 0.8
const FOLLOWING_DISTANCE := 70.0
const FOLLOWING_TIME := 0.5
const OVERTAKE_STRAIGHT_RADIUS := 1050.0
const PURSUIT_CLOSING_DISTANCE := 340.0
const PURSUIT_FOLLOW_DISTANCE := 110.0
const PURSUIT_FOLLOW_TIME := 1.2
const PURSUIT_PACE_FRACTION := 0.93
const PURSUIT_START_GRACE := 3.0
const PURSUIT_START_PACE := 0.93
const DRAFT_MIN_DISTANCE := 54.0
const DRAFT_MAX_DISTANCE := 185.0
const DRAFT_LATERAL_WIDTH := 34.0
const DRAFT_RECHARGE_MULTIPLIER := 0.40
const OFF_ROUTE_DISTANCE := 250.0
const OFF_ROUTE_TIMEOUT := 1.25
const NO_PROGRESS_TIMEOUT := 2.0
const WRONG_WAY_PROGRESS_TIMEOUT := 0.75
const SPIN_LIFT_SLIP_DEG := 40.0
const SPIN_RECOVER_SLIP_DEG := 105.0
const SPIN_MIN_SPEED := 80.0
const SPIN_RECOVER_TIMEOUT := 0.3
const ROUTE_PROGRESS_COMMIT_DISTANCE := 18.0
const LOW_SPEED_FEELER_LENGTH := 72.0
const STATIC_CONTACT_CLEARANCE_RATIO := 0.42
const STATIC_CONTACT_TIMEOUT := 0.65
const STATIC_ESCAPE_DURATION := 0.4
const STATIC_ESCAPE_MAX_SPEED := 70.0
const DEFAULT_PERSONALITY: Dictionary = {
	"corner_pace": 1.0,
	"brake_timing": 1.0,
	"boost_eagerness": 1.0,
	"overtake_aggression": 1.0,
	"shortcut_preference": 1.0,
	"line_commitment": 1.0,
}
const PERSONALITY_BOUNDS: Dictionary = {
	"corner_pace": Vector2(1.0, 1.04),
	"brake_timing": Vector2(0.9, 1.1),
	"boost_eagerness": Vector2(0.9, 1.18),
	"overtake_aggression": Vector2(0.85, 1.13),
	"shortcut_preference": Vector2(0.9, 1.16),
	"line_commitment": Vector2(0.95, 1.06),
}
const CORNER_FLOOR_MIN := 0.90

# Single source of truth for every per-tier behaviour the AI controller uses.
# The hot paths read these values directly; there are no per-tier branches left
# in the code (see configure/_physics_process/_configure_personality/
# _shortcut_route_is_suitable/_v1_speed_envelope). Values that do not yet drive
# a code path are neutral: drift disabled and no catch-up for tiers that never had it.
const DIFFICULTY_TUNING: Dictionary = {
	"sunday_drive": {
		"pace": 0.94,
		"corner_constant": 13.0,
		"corner_floor": 0.48,
		"corner_floor_base": 1.0,
		"corner_floor_commit_bias": 0.0,
		"sharp_corner_ratio": 0.50,
		"heading_cap": 0.60,
		"wrong_way_cap": 0.42,
		"braking_near": 190.0,
		"braking_far": 380.0,
		"brake_response": 72.0,
		"baseline_power": 1.0,
		"starting_boost": 0.28,
		"clean_line_recharge": 0.0,
		"boost_turn_threshold": 0.24,
		"boost_radius": 1500.0,
		"reaction_seconds": 0.34,
		"steering_divisor": 0.72,
		"steering_response": 11.0,
		"corner_margin": 0.86,
		"personality_scale": 0.3,
		"room_cuts_allowed": false,
		"shortcut_enabled": false,
		"shortcut_min_steering_rate": 0.0,
		"shortcut_min_retention": 0.70,
		"shortcut_min_grip": 0.38,
		"catch_up": {"max_power": 0.0, "position_weight": 0.0, "progress_weight": 0.0},
		"assist": {"power": 0.01, "grip": 0.01, "brake": 0.01},
		"mistake_rate": 0.12,
		"drift_policy": "disabled",
	},
	"club_circuit": {
		"pace": 1.08,
		"corner_constant": 15.2,
		"corner_floor": 0.53,
		"corner_floor_base": 0.99,
		"corner_floor_commit_bias": 0.10,
		"sharp_corner_ratio": 0.59,
		"heading_cap": 0.67,
		"wrong_way_cap": 0.48,
		"braking_near": 165.0,
		"braking_far": 350.0,
		"brake_response": 56.0,
		"baseline_power": 1.06,
		"starting_boost": 0.58,
		"clean_line_recharge": 0.50,
		"boost_turn_threshold": 0.34,
		"boost_radius": 1150.0,
		"reaction_seconds": 0.22,
		"steering_divisor": 0.72,
		"steering_response": 13.0,
		"corner_margin": 0.96,
		"personality_scale": 0.78,
		"room_cuts_allowed": true,
		"shortcut_enabled": true,
		"shortcut_min_steering_rate": 3.25,
		"shortcut_min_retention": 0.70,
		"shortcut_min_grip": 0.38,
		"catch_up": {"max_power": 0.09, "position_weight": 0.03, "progress_weight": 0.04},
		"assist": {"power": 0.0, "grip": 0.005, "brake": 0.005},
		"mistake_rate": 0.0,
		"drift_policy": "disabled",
	},
	"clockwork": {
		"pace": 1.12,
		"corner_constant": 16.4,
		"corner_floor": 0.58,
		"corner_floor_base": 1.0,
		"corner_floor_commit_bias": 0.0,
		"sharp_corner_ratio": 0.64,
		"heading_cap": 0.72,
		"wrong_way_cap": 0.52,
		"braking_near": 145.0,
		"braking_far": 315.0,
		"brake_response": 48.0,
		"baseline_power": 1.15,
		"starting_boost": 0.78,
		"clean_line_recharge": 0.80,
		"boost_turn_threshold": 0.42,
		"boost_radius": 900.0,
		"reaction_seconds": 0.15,
		"steering_divisor": 0.64,
		"steering_response": 16.0,
		"corner_margin": 0.99,
		"personality_scale": 1.0,
		"room_cuts_allowed": true,
		"shortcut_enabled": true,
		"shortcut_min_steering_rate": 0.0,
		"shortcut_min_retention": 0.64,
		"shortcut_min_grip": 0.34,
		"catch_up": {"max_power": 0.0, "position_weight": 0.0, "progress_weight": 0.0},
		"assist": {"power": 0.0, "grip": 0.0, "brake": 0.0},
		"mistake_rate": 0.0,
		"drift_policy": "disabled",
	},
}

var vehicle: VehicleController
var _unassisted_stats: VehicleStats
var race_manager: RaceManager
var lane_offset: float = 0.0
var difficulty: String = "club_circuit"
var personality_id := "baseline"
var pursuit_target: Node2D = null
var _open_route := false
var _pursuit_returning := false
var personality: Dictionary = DEFAULT_PERSONALITY.duplicate()
var recovery_count := 0
var recovery_reasons: Dictionary = {}
var overtake_attempt_count := 0
var uses_shortcut_line := false

var _checkpoints_by_index: Dictionary = {}
var _stuck_time: float = 0.0
var _recovering: bool = false
var _track_center := Vector2.ZERO
var _guide_checkpoint_index := -1
var _guide_reached := false
var _stuck_target_key := 0
var _best_checkpoint_distance := INF
var _smoothed_steer := 0.0
var _racing_line: PackedVector2Array = PackedVector2Array()
## Off-route recovery reach: the fixed value widened by the track's widest road.
var _off_route_distance := OFF_ROUTE_DISTANCE
var _standard_racing_line: PackedVector2Array = PackedVector2Array()
var _shortcut_racing_line: PackedVector2Array = PackedVector2Array()
var _reference_path: PackedVector2Array = PackedVector2Array()
var _tracking_grip_utilization := CORNER_GRIP_UTILIZATION
var _anticipated_grip := 1.0
var _allow_room_cuts := false
var _room_cut_checkpoint := -1
var _room_cut_start := Vector2.ZERO
var _room_cut_end := Vector2.ZERO
var _room_cut_shape: CapsuleShape2D
var _room_cut_query: PhysicsShapeQueryParameters2D
var _ray_query: PhysicsRayQueryParameters2D
var _ray_excludes: Array[RID] = []
var _overtake_offset := 0.0
var _overtake_hold_remaining := 0.0
var _overtake_cooldown_remaining := 0.0
var _overtake_target_id := 0
var _recovery_cooldown_remaining := 0.0
var _off_route_time := 0.0
var _no_progress_time := 0.0
var _wrong_way_progress_time := 0.0
var _spin_time := 0.0
var _route_progress_accumulator := 0.0
var _watchdog_target_key := 0
var _last_route_arc := 0.0
var _static_contact_time := 0.0
var _escape_time_remaining := 0.0
var _escape_steer := 0.0
var static_escape_attempt_count := 0
var mistake_count := 0
var _mistake_key := ""
var _mistake_steer := 0.0
var _mistake_remaining := 0.0
var _race_collision_layer := 0
var _race_collision_mask := 0
var _finished_ghosted := false

# ── Per-frame hot-path counters (read by the progressive-freeze harness and the
# regression test). Static so they survive the instance and are cheap to bump.
static var tree_group_scan_count := 0      # get_nodes_in_group(...) from _physics_process
static var surface_zone_probe_count := 0   # SurfaceZone.contains_global_point(...)

# ── Per-race tree cache ──────────────────────────────────────────────
# Surface zones and race vehicles are fixed for a race's lifetime, but
# the old hot paths re-scanned the whole scene tree for them every physics tick
# (a ~2800-node walk plus a fresh Array, per AI, several times per tick). Cache
# them once and invalidate when the field is (re)spawned.
var _surface_zone_nodes: Array[Node] = []
var _race_vehicle_nodes: Array[Node] = []
var _track_traffic_nodes: Array[Node] = []
var _tree_cache_dirty := true
# Per-race surface-zone records: the raw node plus a global-space bounding circle
# and the derived risk/lane/role flags, built once per race so the per-tick
# polygon probes can reject far zones with a single distance check.
var _surface_zone_records: Array[Dictionary] = []

# ── Precomputed arc-length tables for the reference/racing-line loops ──
# The pure-pursuit and route-watchdog hot paths used to re-derive every segment
# length (sqrt) and cumulative arc each call, and re-scan the whole loop for the
# nearest segment. Build the tables once per race and walk them incrementally.
var _racing_line_segment_lengths := PackedFloat32Array()
var _racing_line_cumulative := PackedFloat32Array()
var _racing_line_total := 0.0
var _reference_segment_lengths := PackedFloat32Array()
var _reference_cumulative := PackedFloat32Array()
var _reference_total := 0.0
var _racing_line_nearest_index := -1
var _reference_nearest_index := -1
# Scratch results are owned by this controller. Callers must consume them before
# calling the same helper again; none may be retained across physics ticks.
var _reference_goal_result := {"goal": Vector2.ZERO, "lookahead": 0.0}
var _traffic_result := {"target_position": Vector2.ZERO, "speed_scale": 1.0, "speed_limit": INF, "passing": false, "drafting": false}
var _leader_result: Dictionary = {}
var _surface_result := {"weight": 0.0, "speed_scale": 1.0, "grip_scale": 1.0, "risk": 0.0, "avoid_direction": Vector2.ZERO}
var _surface_model_result := {"risk": 0.0, "grip": 1.0, "speed": 1.0}
var _obstacle_result := {"weight": 0.0, "speed_scale": 1.0, "speed_limit": INF, "avoid_direction": Vector2.ZERO, "static_contact": false, "escape_steer": 0.0}
# Tick-local results: callers consume these before calling the same helper again.
var _segment_result := {"index": 0, "fraction": 0.0, "distance_squared": INF}
var _route_sample_result := {"arc": 0.0, "length": 1.0, "distance": 0.0, "closed": false}
var _watchdog_result := {"made_progress": false}
var _hazard_result := {"radius": 0.0, "distance": INF, "speed_limit": INF}
# A wide probe needs all three results alive until the nearest is selected.
var _ray_results := [
	{"clearance": 1.0, "is_vehicle": false, "normal": Vector2.ZERO},
	{"clearance": 1.0, "is_vehicle": false, "normal": Vector2.ZERO},
	{"clearance": 1.0, "is_vehicle": false, "normal": Vector2.ZERO},
]
var _brake_prediction: Array[float] = [0.0, 0.0]
var _brake_prediction_loads: Array[float] = [0.0, 0.0, 0.0, 0.0]


func configure(
		controlled_vehicle: VehicleController,
		manager: RaceManager,
		preferred_lane_offset: float,
		difficulty_id: String = "club_circuit",
		driver_id: String = "baseline",
		driver_style: Dictionary = {},
		pursuit_target: Node2D = null
) -> void:
	if vehicle != controlled_vehicle or _unassisted_stats == null:
		_unassisted_stats = controlled_vehicle.stats
	vehicle = controlled_vehicle
	if _room_cut_query != null:
		_room_cut_query.exclude = [vehicle.get_rid()]
	if vehicle.stats != _unassisted_stats:
		vehicle.apply_stats(_unassisted_stats)
	race_manager = manager
	lane_offset = preferred_lane_offset
	difficulty = difficulty_id if DIFFICULTY_TUNING.has(difficulty_id) else "club_circuit"
	self.pursuit_target = pursuit_target
	_pursuit_returning = false
	_configure_personality(driver_id, driver_style)
	var tuning := _difficulty_tuning()
	var assist := tuning["assist"] as Dictionary
	if float(assist["grip"]) > 0.0 or float(assist["brake"]) > 0.0:
		# VehicleStats is a shared resource. Give this AI its own copy so neither
		# other racers nor the human inherit its tire and brake forces.
		var assisted_stats := vehicle.stats.duplicate() as VehicleStats
		assisted_stats.front_grip *= 1.0 + float(assist["grip"])
		assisted_stats.rear_grip *= 1.0 + float(assist["grip"])
		assisted_stats.brake_force *= 1.0 + float(assist["brake"])
		vehicle.apply_stats(assisted_stats)
	vehicle.boost_amount = minf(
		vehicle.get_boost_capacity(),
		vehicle.get_boost_capacity()
		* float(tuning["starting_boost"])
		* float(personality["boost_eagerness"])
	)
	_cache_checkpoints()
	if not race_manager.race_started.is_connected(_cache_checkpoints):
		race_manager.race_started.connect(_cache_checkpoints)
	vehicle.set_player_controlled(false)
	_race_collision_layer = vehicle.collision_layer
	_race_collision_mask = vehicle.collision_mask
	_finished_ghosted = false
	_recovery_cooldown_remaining = 0.0
	recovery_reasons.clear()
	mistake_count = 0
	_mistake_key = ""
	_mistake_steer = 0.0
	_mistake_remaining = 0.0
	_stuck_time = 0.0
	_reset_route_watchdog()
	_tree_cache_dirty = true
	if not race_manager.race_started.is_connected(_restore_racing_collisions):
		race_manager.race_started.connect(_restore_racing_collisions)
	if not race_manager.racer_recovered.is_connected(_on_external_recovery):
		race_manager.racer_recovered.connect(_on_external_recovery)
	if not race_manager.racer_registered.is_connected(_on_racer_registered):
		race_manager.racer_registered.connect(_on_racer_registered)


func _cache_checkpoints() -> void:
	_checkpoints_by_index.clear()
	_track_center = Vector2.ZERO
	for checkpoint: Node in race_manager.get_ordered_checkpoints():
		_checkpoints_by_index[int(checkpoint.get("checkpoint_index"))] = checkpoint
		_track_center += (checkpoint as Node2D).global_position
	if not _checkpoints_by_index.is_empty():
		_track_center /= float(_checkpoints_by_index.size())
	_racing_line = PackedVector2Array()
	_open_route = false
	_standard_racing_line = PackedVector2Array()
	_shortcut_racing_line = PackedVector2Array()
	uses_shortcut_line = false
	_allow_room_cuts = false
	_room_cut_checkpoint = -1
	var track: Node = null
	if not _checkpoints_by_index.is_empty():
		track = (_checkpoints_by_index.values()[0] as Node).get_parent()
		while track != null and not track.is_in_group("track"):
			track = track.get_parent()
	if track:
		_allow_room_cuts = bool(track.get_meta("generated_track", false)) and bool(_difficulty_tuning()["room_cuts_allowed"])
		_off_route_distance = OFF_ROUTE_DISTANCE + maxf(0.0, float(track.get_meta("corridor_max_half_width", TrackBuilderCore.HALF_WIDTH)) - TrackBuilderCore.HALF_WIDTH)

		var racing_line := track.get_node_or_null("RacingLine") as Line2D
		if racing_line:
			_open_route = not racing_line.closed
			for point: Vector2 in racing_line.points:
				_standard_racing_line.append(racing_line.to_global(point))
		elif vehicle.stats.physics_model_version != VehicleStats.LEGACY_MODEL_VERSION:
			# Older authored fixtures store ordered centerline samples as surface
			# tiles, not RacingLine. Use that actual route rather than inventing
			# axis-aligned turns between sparse checkpoint gates.
			var tiles := track.get_node_or_null("TrackSurfaceTiles")
			if tiles != null:
				var samples := PackedVector2Array()
				for tile: Node in tiles.get_children():
					if tile is Node2D:
						samples.append((tile as Node2D).global_position)
				if samples.size() >= 3:
					var lengths := PackedFloat32Array()
					var total := 0.0
					for i in samples.size():
						var length := samples[i].distance_to(samples[(i + 1) % samples.size()])
						lengths.append(length)
						total += length
					var segment := 0
					var walked := 0.0
					for i in 260:
						var arc := total * float(i) / 260.0
						while segment < samples.size() - 1 and walked + lengths[segment] < arc:
							walked += lengths[segment]
							segment += 1
						_standard_racing_line.append(samples[segment].lerp(samples[(segment + 1) % samples.size()], (arc - walked) / maxf(lengths[segment], 0.001)))
		var shortcut_line := track.get_node_or_null("ShortcutRacingLine") as Line2D
		if shortcut_line:
			for point: Vector2 in shortcut_line.points:
				_shortcut_racing_line.append(shortcut_line.to_global(point))
		uses_shortcut_line = _shortcut_route_is_suitable(track)
		_racing_line = _shortcut_racing_line if uses_shortcut_line else _standard_racing_line
	# Pure pursuit tracks one dense, closed reference path. Authored tracks
	# ship a hand-authored racing line; tracks that only expose sparse
	# checkpoints fall back to a path built from the ordered gate nodes and
	# their corner-guide apexes, so every fixture gets consistent path
	# following rather than steering at a faraway gate.
	_reference_path = _racing_line if _racing_line.size() >= 2 else _build_checkpoint_reference_path()
	_build_arc_tables()


func prepare_strip_start() -> void:
	if not _open_route:
		return
	# The complete field (including civilian traffic) now exists. Build the
	# final route/group caches under loading, not again on the GO signal.
	_cache_checkpoints()
	_refresh_tree_cache()
	_reference_nearest_index = int(_nearest_open_segment(_reference_path, vehicle.global_position, -1)["index"])
	_racing_line_nearest_index = int(_nearest_open_segment(_racing_line, vehicle.global_position, -1)["index"])
	if race_manager.race_started.is_connected(_cache_checkpoints):
		race_manager.race_started.disconnect(_cache_checkpoints)


func _build_arc_tables() -> void:
	var racing_line_tables := _arc_tables_for(_racing_line)
	_racing_line_segment_lengths = racing_line_tables["lengths"]
	_racing_line_cumulative = racing_line_tables["cumulative"]
	_racing_line_total = racing_line_tables["total"]
	var reference_tables := _arc_tables_for(_reference_path)
	_reference_segment_lengths = reference_tables["lengths"]
	_reference_cumulative = reference_tables["cumulative"]
	_reference_total = reference_tables["total"]
	_racing_line_nearest_index = -1
	_reference_nearest_index = -1


func _arc_tables_for(path: PackedVector2Array) -> Dictionary:
	var count := path.size()
	var lengths := PackedFloat32Array()
	var cumulative := PackedFloat32Array()
	if count < 2:
		return {"lengths": lengths, "cumulative": cumulative, "total": 0.0}
	lengths.resize(count)
	cumulative.resize(count)
	var total := 0.0
	for index in count:
		lengths[index] = 0.0 if _open_route and index == count - 1 else path[index].distance_to(path[(index + 1) % count])
		cumulative[index] = total
		total += lengths[index]
	return {"lengths": lengths, "cumulative": cumulative, "total": total}


func _ensure_arc_tables_current() -> void:
	## The arc-length tables are a derived cache of _racing_line/_reference_path,
	## rebuilt in _cache_checkpoints. Both source paths can also be replaced
	## directly (route fixtures and tests set them without going through
	## _cache_checkpoints), so a stale table would silently describe a different
	## loop. Rebuild lazily when the cached table sizes no longer match their
	## source path, keeping the hot paths consistent with whatever line is active.
	if _racing_line_segment_lengths.size() != _racing_line.size() or _reference_segment_lengths.size() != _reference_path.size():
		_build_arc_tables()


## Nearest loop segment by projection, searched around `cached_index` (temporal
## coherence). Cars move far less than one segment per tick, so the true nearest
## is always a few indices from last frame's; a cold cache (or a teleport that
## reset it) falls back to a full scan. Returns index, fraction and squared
## distance so every caller can skip re-projecting.
func _nearest_segment_local(path: PackedVector2Array, position: Vector2, cached_index: int) -> Dictionary:
	var count := path.size()
	if _open_route:
		return _nearest_open_segment(path, position, cached_index)
	if cached_index >= 0 and cached_index < count:
		var best_index := cached_index
		var best_fraction := 0.0
		var best_dsq := INF
		for delta in 65:
			var index := posmod(cached_index - 32 + delta, count)
			var from := path[index]
			var to := path[(index + 1) % count]
			var segment := to - from
			var length_squared := segment.length_squared()
			var fraction := 0.0
			if length_squared > 0.001:
				fraction = clampf((position - from).dot(segment) / length_squared, 0.0, 1.0)
			var nearest := from + segment * fraction
			var dsq := position.distance_squared_to(nearest)
			if dsq < best_dsq:
				best_dsq = dsq
				best_index = index
				best_fraction = fraction
		_segment_result["index"] = best_index
		_segment_result["fraction"] = best_fraction
		_segment_result["distance_squared"] = best_dsq
		return _segment_result
	var best_index := 0
	var best_fraction := 0.0
	var best_dsq := INF
	for index in count:
		var from := path[index]
		var to := path[(index + 1) % count]
		var segment := to - from
		var length_squared := segment.length_squared()
		var fraction := 0.0
		if length_squared > 0.001:
			fraction = clampf((position - from).dot(segment) / length_squared, 0.0, 1.0)
		var nearest := from + segment * fraction
		var dsq := position.distance_squared_to(nearest)
		if dsq < best_dsq:
			best_dsq = dsq
			best_index = index
			best_fraction = fraction
	_segment_result["index"] = best_index
	_segment_result["fraction"] = best_fraction
	_segment_result["distance_squared"] = best_dsq
	return _segment_result


func _nearest_open_segment(path: PackedVector2Array, position: Vector2, cached_index: int) -> Dictionary:
	var best_index := -1
	var best_fraction := 0.0
	var best_distance := INF
	var start := maxi(0, cached_index - 32) if cached_index >= 0 and cached_index < path.size() - 1 else 0
	var end := mini(path.size() - 1, cached_index + 33) if cached_index >= 0 and cached_index < path.size() - 1 else path.size() - 1
	for index in range(start, end):
		var segment := path[index + 1] - path[index]
		var fraction := clampf((position - path[index]).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
		var distance := position.distance_squared_to(path[index] + segment * fraction)
		if distance < best_distance:
			best_index = index
			best_fraction = fraction
			best_distance = distance
	_segment_result["index"] = best_index
	_segment_result["fraction"] = best_fraction
	_segment_result["distance_squared"] = best_distance
	return _segment_result


func _physics_process(delta: float) -> void:
	_recovery_cooldown_remaining = maxf(0.0, _recovery_cooldown_remaining - delta)
	if not is_instance_valid(vehicle) or not is_instance_valid(race_manager) or _recovering:
		return
	if race_manager.is_racer_finished(vehicle):
		_ghost_finished_vehicle()
		vehicle.set_external_controls(0.0, 0.0, 0.0)
		_reset_route_watchdog()
		return
	if vehicle.controls_locked or not race_manager.is_running:
		vehicle.set_external_controls(0.0, 0.0, 0.0)
		_stuck_time = 0.0
		_reset_route_watchdog()
		return

	var expected_index := race_manager.get_expected_checkpoint(vehicle)
	var target_checkpoint := _checkpoints_by_index.get(expected_index) as Node2D
	if target_checkpoint == null:
		vehicle.set_external_controls(0.0, 1.0, 0.0)
		return

	var next_checkpoint := race_manager.get_checkpoint_after(expected_index) as Node2D
	var checkpoint_position := target_checkpoint.global_position
	var target_position := _active_target_position(expected_index)
	var targeting_guide := not _guide_reached
	var distance_to_target := vehicle.global_position.distance_to(target_position)
	var distance_to_gate := vehicle.global_position.distance_to(checkpoint_position)
	if next_checkpoint and not targeting_guide and distance_to_gate < LOOK_AHEAD_DISTANCE:
		var look_ahead_weight := clampf(
			(LOOK_AHEAD_DISTANCE - distance_to_gate) / LOOK_AHEAD_DISTANCE,
			0.0,
			MAX_LOOK_AHEAD_WEIGHT
		)
		var next_index := int(next_checkpoint.get("checkpoint_index"))
		var next_guide: Variant = _checkpoint_entry_guide_position(next_index)
		var next_target: Vector2 = _checkpoint_target_position(next_index)
		if next_guide != null:
			next_target = next_guide
		target_position = target_position.lerp(
			next_target,
			look_ahead_weight
		)

	var forward := Vector2.UP.rotated(vehicle.rotation)
	_update_room_cut(expected_index, forward)
	var is_pursuit_return := _is_pursuit_active() and _pursuit_returning
	var heading_to_checkpoint := absf(forward.angle_to(vehicle.global_position.direction_to(checkpoint_position)))
	var turn_around := heading_to_checkpoint > TURN_AROUND_HEADING and not is_pursuit_return
	var watchdog := _update_route_watchdog(delta, expected_index, turn_around)
	if is_pursuit_return:
		_stuck_time = 0.0
		_no_progress_time = 0.0
		_wrong_way_progress_time = 0.0
	if _recovering:
		return
	if _update_spin_recovery(delta):
		return
	if vehicle.stats.physics_model_version != 0:
		var route_error := float(_active_route_sample(expected_index)["distance"])
		var correction := clampf(maxf(route_error / 70.0, absf(vehicle.slip_angle) / 20.0), 0.0, 1.0)
		_tracking_grip_utilization = lerpf(CORNER_GRIP_UTILIZATION, CORRECTION_GRIP_UTILIZATION, correction)
	var line_radius := _racing_line_radius(vehicle.global_position)
	var curvature_hazard := _v1_curvature_hazard(expected_index) if vehicle.stats.physics_model_version != 0 else _hazard_result
	var pursuit_lookahead := _lookahead_distance()
	if line_radius > 0.0:
		# Steering follows local curvature. A future hairpin may constrain
		# braking, but must not shorten pursuit on the preceding straight.
		var min_turn_radius := vehicle.stats.wheelbase / maxf(tan(deg_to_rad(vehicle.stats.max_steer_angle_deg)), 0.001)
		pursuit_lookahead = minf(pursuit_lookahead, maxf(line_radius, min_turn_radius))
	var pursuit_goal := _reference_goal(forward, pursuit_lookahead)
	target_position = pursuit_goal["goal"] as Vector2
	if _room_cut_checkpoint == expected_index:
		target_position = _room_cut_end
		curvature_hazard = _checkpoint_curvature_hazard(expected_index)
		line_radius = 0.0
	var traffic_plan := _traffic_plan(delta, forward, target_position, line_radius)
	target_position = traffic_plan["target_position"] as Vector2
	if _is_pursuit_active():
		var pinfo := _pursuit_distance_and_ahead(forward)
		var pahead := float(pinfo["ahead"])
		if pahead < 0:
			_pursuit_returning = true
		else:
			_pursuit_returning = false
	is_pursuit_return = _is_pursuit_active() and _pursuit_returning
	if is_pursuit_return and _is_pursuit_active():
		var pinfo := _pursuit_distance_and_ahead(forward)
		var pahead := float(pinfo["ahead"])
		if pahead < -100:
			# drive back along the route (approx opposite forward to return to target without prediction or off-path ambush)
			target_position = vehicle.global_position - forward * 800.0
	var goal_chord := vehicle.global_position.distance_to(target_position)
	var desired_direction := vehicle.global_position.direction_to(target_position)
	var surface_plan := _surface_anticipation(desired_direction)
	_anticipated_grip = _planned_surface_grip(surface_plan)
	if float(surface_plan["weight"]) > 0.0:
		desired_direction = desired_direction.lerp(
			surface_plan["avoid_direction"] as Vector2,
			float(surface_plan["weight"])
		).normalized()
	var obstacle_plan := _obstacle_avoidance(forward, desired_direction)
	if _update_static_escape(delta, obstacle_plan, bool(watchdog["made_progress"])):
		return
	if float(obstacle_plan["weight"]) > 0.35:
		desired_direction = desired_direction.lerp(
			obstacle_plan["avoid_direction"] as Vector2,
			float(obstacle_plan["weight"])
		).normalized()
	var steering_angle := forward.angle_to(desired_direction)
	var tuning := _difficulty_tuning()
	var pace_multiplier := float(tuning["pace"])
	var effective_max_speed := vehicle.get_effective_max_speed()
	var rack_max := 0.0
	if vehicle.stats.physics_model_version != 0:
		rack_max = DYNAMICS.calculate_target_steer_angle(
			1.0,
			vehicle.stats.max_steer_angle_deg,
			vehicle.speed,
			effective_max_speed,
			vehicle.stats.high_speed_steer_ratio,
			vehicle.stats.steer_fade_start_ratio,
		)
	var requested_steer: float
	if vehicle.stats.physics_model_version != 0:
		# Pure pursuit: curvature from the heading error to the projected goal
		# and the exact look-ahead arc distance used to select that goal. The
		# single consistent reference path (racing line, or checkpoint+guide
		# fallback) removes the old clamp against the raw gate distance, which
		# over- or under-steered differently on every fixture and direction.
		if absf(steering_angle) < TURN_AROUND_HEADING:
			var curvature := 2.0 * sin(steering_angle) / maxf(goal_chord, 5.0)
			var wheel_steer := atan(vehicle.stats.wheelbase * curvature)
			# A heavy front-biased car needs more rack angle than a rigid-wheel
			# bicycle to produce the same curvature. Use its real axle stiffness
			# rather than giving every chassis the same steering response.
			var stiffness := DYNAMICS.calculate_progressive_stiffness(vehicle.surface_grip_multiplier)
			var front_slip := vehicle.stats.front_weight_ratio / (vehicle.stats.front_cornering_stiffness * stiffness)
			var rear_slip := (1.0 - vehicle.stats.front_weight_ratio) / (vehicle.stats.rear_cornering_stiffness * stiffness)
			var slip_correction := vehicle.stats.mass * vehicle.speed * vehicle.speed * curvature * (front_slip - rear_slip)
			wheel_steer += clampf(slip_correction, -0.1, 0.1)
			requested_steer = clampf(wheel_steer / maxf(absf(rack_max), 0.001), -1.0, 1.0)
		else:
			# Goal well off the current heading (past the point where pure
			# pursuit curvature stops growing): commit full lock toward the
			# target so the vehicle turns around instead of arcing wide.
			requested_steer = 1.0 if steering_angle >= 0.0 else -1.0
	else:
		requested_steer = clampf(steering_angle / float(tuning["steering_divisor"]), -1.0, 1.0)
	requested_steer = clampf(requested_steer + _corner_mistake(delta, tuning, expected_index, line_radius), -1.0, 1.0)
	var steering_response := float(tuning["steering_response"])
	_smoothed_steer = lerpf(_smoothed_steer, requested_steer, 1.0 - exp(-steering_response * delta))
	var turn_severity := _checkpoint_turn_severity(expected_index)
	var next_turn_severity := 0.0
	if next_checkpoint:
		next_turn_severity = _checkpoint_turn_severity(int(next_checkpoint.get("checkpoint_index")))
	var planned_turn_severity := maxf(turn_severity, next_turn_severity * 0.84)
	var corner_ratio := clampf(planned_turn_severity / 1.45, 0.0, 1.0)
	var handling_pace := clampf(vehicle.stats.steering_rate / 3.75, 0.78, 1.08)
	var corner_speed := effective_max_speed
	var commit := float(personality["line_commitment"])

	# Brake against the distance to the upcoming curvature hazard, not the
	# checkpoint/gate target distance. v0 keeps its legacy planning path.
	var hazard_distance := distance_to_target
	if vehicle.stats.physics_model_version != 0:
		var upcoming_radius := float(curvature_hazard["radius"])
		hazard_distance = float(curvature_hazard["distance"])
		corner_speed = float(curvature_hazard.get("speed_limit", _v1_speed_envelope(upcoming_radius, hazard_distance)))
	elif line_radius > 40.0:
		var floor_base := float(tuning["corner_floor_base"])
		var floor_adj := clampf(
			floor_base - float(tuning["corner_floor_commit_bias"]) * (commit - 1.0),
			CORNER_FLOOR_MIN,
			floor_base
		)
		var corner_floor := float(tuning["corner_floor"]) * floor_adj
		corner_speed = clampf(
			float(tuning["corner_constant"]) * sqrt(line_radius) * pace_multiplier * float(personality["corner_pace"]),
			effective_max_speed * corner_floor,
			effective_max_speed
		)

	var target_speed := corner_speed if vehicle.stats.physics_model_version != 0 else minf(
		effective_max_speed * lerpf(0.98, float(tuning["sharp_corner_ratio"]), corner_ratio) * pace_multiplier,
		corner_speed
	)
	if vehicle.stats.physics_model_version == 0:
		target_speed *= lerpf(1.0, handling_pace, corner_ratio)
		target_speed *= float(surface_plan["speed_scale"])
	else:
		# Surface speed is an absolute limit relative to the dry chassis, not
		# another multiplier on an already surface-limited target.
		target_speed = minf(target_speed, vehicle.stats.max_speed * float(surface_plan["speed_scale"]))
		# Rejoining or entering an apron cut can demand a tighter turn than
		# the route ahead. Respect that immediate steering arc as well.
		var turn_sine := absf(sin(steering_angle))
		if turn_sine > 0.05:
			var pursuit_radius := maxf(goal_chord, 5.0) / (2.0 * turn_sine)
			target_speed = minf(target_speed, _v1_speed_envelope(pursuit_radius, 0.0))
	if vehicle.stats.physics_model_version != 0:
		target_speed = minf(target_speed, float(obstacle_plan["speed_limit"]))
	else:
		target_speed *= float(obstacle_plan["speed_scale"])
	if vehicle.stats.physics_model_version != 0:
		target_speed = minf(target_speed, float(traffic_plan["speed_limit"]))
	else:
		target_speed *= float(traffic_plan["speed_scale"])
	if _is_pursuit_active() and not is_pursuit_return and race_manager.race_time < PURSUIT_START_GRACE:
		target_speed *= PURSUIT_START_PACE
	if is_pursuit_return and _is_pursuit_active():
		var pinfo := _pursuit_distance_and_ahead(forward)
		var pa := float(pinfo["ahead"])
		var ch_lead := -pa
		if ch_lead > 250:
			target_speed = minf(target_speed, 250.0)
		elif ch_lead > 0:
			target_speed = minf(target_speed, 150.0)
	var heading_error := absf(steering_angle)
	if heading_error > 1.05:
		target_speed = minf(target_speed, effective_max_speed * float(tuning["heading_cap"]))
	var wrong_way := race_manager.is_racer_wrong_way(vehicle) and not is_pursuit_return
	if heading_error > 1.45 or wrong_way:
		target_speed = minf(target_speed, effective_max_speed * float(tuning["wrong_way_cap"]))
	if heading_error > TURN_AROUND_HEADING:
		# A near-180 heading change cannot be made at pace without a wide arc;
		# crawl while the rack swings over so the turn-around stays on the road.
		target_speed = minf(target_speed, effective_max_speed * 0.12)

	var braking_distance := 0.0
	if vehicle.stats.physics_model_version != 0:
		var surface_grip := _planned_surface_grip(surface_plan)
		var reaction_seconds := float(tuning["reaction_seconds"])
		var reaction_margin := vehicle.speed * reaction_seconds
		braking_distance = vehicle.get_braking_distance(vehicle.speed, target_speed, surface_grip, _brake_prediction, _brake_prediction_loads) + reaction_margin
		braking_distance *= float(personality["brake_timing"])
	else:
		braking_distance = lerpf(
			float(tuning["braking_near"]),
			float(tuning["braking_far"]),
			corner_ratio
		) * float(personality["brake_timing"])

	var should_brake := vehicle.speed > target_speed and hazard_distance < braking_distance
	if vehicle.stats.physics_model_version != 0:
		# The envelope already includes braking distance and reaction time.
		should_brake = vehicle.speed > target_speed + 3.0
		# A sharp heading change, wrong-way state, or an obstacle/low-grip
		# surface demanding an immediate slowdown must be corrected now, not
		# gated by proximity to a checkpoint.
		if (
			heading_error > 1.45
			or (race_manager.is_racer_wrong_way(vehicle) and not is_pursuit_return)
			or float(obstacle_plan["speed_scale"]) < 0.95
			or float(surface_plan["speed_scale"]) < 0.95
		):
			should_brake = vehicle.speed > target_speed
	var throttle := 0.0 if should_brake else 1.0
	if heading_error > 1.45 or (race_manager.is_racer_wrong_way(vehicle) and not is_pursuit_return):
		throttle = 0.42 if not should_brake else 0.0
	if is_pursuit_return and not should_brake:
		throttle = 1.0
	var brake := clampf(
		(vehicle.speed - target_speed) / float(tuning["brake_response"]),
		0.0,
		1.0
	) if should_brake else 0.0
	var position := race_manager.get_racer_position(vehicle)
	var baseline_power := float(tuning["baseline_power"])
	var catch_up := tuning["catch_up"] as Dictionary
	var catch_up_max := float(catch_up["max_power"])
	var catch_up_power := 0.0
	if catch_up_max > 0.0 and not _is_pursuit_active():
		for racer: Node in _group_nodes(&"race_vehicle"):
			if is_instance_valid(racer) and racer.is_in_group("player_vehicle"):
				var progress := race_manager.get_racer_progress(vehicle)
				var player_progress := race_manager.get_racer_progress(racer as Node2D)
				if progress < player_progress:
					catch_up_power = calculate_catch_up_power(tuning, position, progress, player_progress, _leader_progress_deficit())
				break
	vehicle.set_external_power_multiplier(baseline_power + float((tuning["assist"] as Dictionary)["power"]) + catch_up_power)
	_apply_drafting_recharge(delta, traffic_plan, should_brake)
	if catch_up_power > 0.0 and not should_brake:
		vehicle.add_boost(
			vehicle.stats.boost_recharge * (catch_up_power / catch_up_max) * 0.75 * delta,
			"catch-up",
		)
	# Boost gating uses local safe distance + curvature (not stale checkpoint dist/turn_severity) so clear straights get boosts.
	var local_turn := planned_turn_severity
	if vehicle.stats.physics_model_version != 0 and not curvature_hazard.is_empty():
		local_turn = 0.0
		var hr := float(curvature_hazard.get("radius", 9999.0))
		if hr < float(tuning["boost_radius"]):
			local_turn = clampf((float(tuning["boost_radius"]) - hr) / 1400.0, 0.0, 1.3)
	var boost_dist_clear := (hazard_distance > braking_distance * 1.25 / float(personality["boost_eagerness"]) or hazard_distance >= 800.0 or hazard_distance == INF)
	var exit_acceleration_window := vehicle.stats.physics_model_version != 0 and target_speed > vehicle.speed + 120.0 and boost_dist_clear
	var boost := (
		absf(steering_angle) < 0.26
		and (local_turn < float(tuning["boost_turn_threshold"]) * float(personality["boost_eagerness"]) or exit_acceleration_window)
		and (line_radius <= 0.0 or line_radius >= float(tuning["boost_radius"]) / float(personality["boost_eagerness"]) or exit_acceleration_window)
		and boost_dist_clear
		and float(surface_plan["risk"]) < 0.12
		and float(obstacle_plan["speed_scale"]) > 0.96
		and not should_brake
		and vehicle.speed > 180.0
		and vehicle.boost_amount > 10.0
	)
	if (
		not boost
		and not should_brake
		and absf(_smoothed_steer) < 0.16
		and local_turn < 0.3
		and float(surface_plan["risk"]) < 0.12
		and vehicle.speed > effective_max_speed * 0.55
	):
		vehicle.add_boost(
			vehicle.stats.boost_recharge * float(tuning["clean_line_recharge"]) * delta,
			"clean-line",
		)
	# Lift throttle while the body slides past a controlled drift so the arcade
	# throttle-oversteer (throttle-on rear cut) does not escalate the slide into a
	# full spin. Coasting lets the rear tyres regain grip.
	if absf(vehicle.slip_angle) > SPIN_LIFT_SLIP_DEG and vehicle.speed > SPIN_MIN_SPEED:
		throttle = 0.0
		boost = false
	vehicle.set_external_controls(throttle, brake, _smoothed_steer, false, boost)
	var stuck_target_key: int = (expected_index << 1) | (1 if targeting_guide else 0)
	_update_stuck_recovery(delta, stuck_target_key, distance_to_target)


static func calculate_catch_up_power(tuning: Dictionary, position: int, progress: float, player_progress: float, leader_deficit: float) -> float:
	if progress >= player_progress:
		return 0.0
	var catch_up := tuning["catch_up"] as Dictionary
	var baseline := float(tuning["baseline_power"]) + float((tuning["assist"] as Dictionary)["power"])
	return minf(
		minf(float(catch_up["max_power"]), maxf(0.0, VehicleController.MAX_EXTERNAL_POWER_MULTIPLIER - baseline)),
		maxf(float(maxi(0, position - 1)) * float(catch_up["position_weight"]), leader_deficit * float(catch_up["progress_weight"]))
	)


func _corner_mistake(delta: float, tuning: Dictionary, checkpoint_index: int, radius: float) -> float:
	if float(tuning["mistake_rate"]) <= 0.0:
		return 0.0
	var lap := int(race_manager.get_racer_state_ref(vehicle).get("lap", 0))
	var key := "%d:%d" % [lap, checkpoint_index]
	if key != _mistake_key:
		_mistake_key = key
		_mistake_steer = 0.0
		_mistake_remaining = 0.0
		if radius > 100.0 and radius < 650.0 and vehicle.speed >= 160.0 and not vehicle.has_static_contact:
			var rng := RandomNumberGenerator.new()
			rng.seed = ("%s:%s" % [personality_id, key]).hash()
			if rng.randf() < float(tuning["mistake_rate"]):
				_mistake_steer = 0.025 if rng.randf() < 0.5 else -0.025
				_mistake_remaining = 0.18
				mistake_count += 1
	# Only a momentary line correction on a corner; normal pure pursuit recovers
	# as the steering unwinds. No changes to collision, brake or vehicle physics.
	if radius < 100.0 or radius > 650.0 or vehicle.speed < 160.0 or vehicle.has_static_contact:
		return 0.0
	_mistake_remaining = maxf(0.0, _mistake_remaining - delta)
	return _mistake_steer if _mistake_remaining > 0.0 else 0.0


func _update_room_cut(expected_index: int, forward: Vector2) -> void:
	if _open_route:
		_room_cut_checkpoint = -1
		return
	if _room_cut_checkpoint != expected_index:
		_room_cut_checkpoint = -1
	if not _allow_room_cuts or vehicle.has_static_contact:
		_room_cut_checkpoint = -1
		return
	var checkpoint := _checkpoints_by_index.get(expected_index) as Node2D
	if checkpoint == null:
		return
	var goal := checkpoint.global_position
	var delta := goal - vehicle.global_position
	if delta.length() < 40.0:
		return
	var direction := delta.normalized()
	if _room_cut_checkpoint < 0 and absf(forward.angle_to(direction)) > 0.75:
		return
	if _room_cut_checkpoint < 0 and _racing_line.size() >= 3:
		var count := _racing_line.size()
		var index := _nearest_line_index(vehicle.global_position)
		var gate_index := _nearest_line_index(goal)
		var step := -1 if race_manager.is_reverse_direction() else 1
		var route_distance := 0.0
		for sample in count:
			if index == gate_index:
				break
			var next := posmod(index + step, count)
			route_distance += _racing_line[index].distance_to(_racing_line[next])
			index = next
		if route_distance < delta.length() * 1.1:
			return
	# Sweep the whole car, not separated rays which could miss small props.
	# Gate Areas are sensors and do not obstruct this solid-body query.
	if _room_cut_shape == null:
		_room_cut_shape = CapsuleShape2D.new()
		_room_cut_shape.radius = 22.0
		_room_cut_shape.height = 56.0
	if _room_cut_query == null:
		_room_cut_query = PhysicsShapeQueryParameters2D.new()
		_room_cut_query.exclude = [vehicle.get_rid()]
	var query := _room_cut_query
	query.shape = _room_cut_shape
	query.transform = Transform2D(direction.angle() + PI * 0.5, vehicle.global_position)
	query.collision_mask = STATIC_OBSTACLE_MASK
	query.motion = Vector2.ZERO
	var space := vehicle.get_world_2d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		_room_cut_checkpoint = -1
		return
	query.motion = delta
	var sweep := space.cast_motion(query)
	if sweep.size() != 2 or sweep[0] < 0.999:
		_room_cut_checkpoint = -1
		return
	if _room_cut_checkpoint < 0:
		_room_cut_start = vehicle.global_position
		_room_cut_end = goal
		_room_cut_checkpoint = expected_index
		_reset_route_watchdog()


func _active_target_position(checkpoint_index: int) -> Vector2:
	if checkpoint_index != _guide_checkpoint_index:
		_guide_checkpoint_index = checkpoint_index
		_guide_reached = false
	var guide_position: Variant = _checkpoint_entry_guide_position(checkpoint_index)
	if guide_position == null:
		_guide_reached = true
		return _checkpoint_target_position(checkpoint_index)
	var guide_target: Vector2 = guide_position
	if not _guide_reached:
		var guide_distance := vehicle.global_position.distance_to(guide_target)
		var checkpoint_target := _checkpoint_target_position(checkpoint_index)
		if guide_distance <= CORNER_GUIDE_REACHED_DISTANCE or _has_passed_guide(guide_target, checkpoint_target):
			_guide_reached = true
		else:
			var blend_weight := clampf(
				(CORNER_GUIDE_BLEND_DISTANCE - guide_distance) / CORNER_GUIDE_BLEND_DISTANCE,
				0.0,
				0.68
			)
			return guide_target.lerp(_checkpoint_target_position(checkpoint_index), blend_weight)
	return _checkpoint_target_position(checkpoint_index)


func _has_passed_guide(guide_position: Vector2, checkpoint_position: Vector2) -> bool:
	var outgoing_direction := guide_position.direction_to(checkpoint_position)
	var relative_position := vehicle.global_position - guide_position
	return (
		relative_position.dot(outgoing_direction) > 0.0
		and absf(relative_position.cross(outgoing_direction)) <= CORNER_GUIDE_PASS_WIDTH
	)


func _checkpoint_entry_guide_position(checkpoint_index: int) -> Variant:
	if _open_route:
		return null
	var checkpoint := _checkpoints_by_index.get(checkpoint_index) as Node2D
	var previous := race_manager.get_checkpoint_before(checkpoint_index) as Node2D
	if checkpoint == null or previous == null:
		return null
	return _entry_guide_position(checkpoint, previous)


func _entry_guide_position(checkpoint: Node2D, before_checkpoint: Node2D) -> Variant:
	var segment := checkpoint.global_position - before_checkpoint.global_position
	if (
		absf(segment.x) < CORNER_GUIDE_AXIS_THRESHOLD
		or absf(segment.y) < CORNER_GUIDE_AXIS_THRESHOLD
	):
		return null
	var x_then_y := Vector2(checkpoint.global_position.x, before_checkpoint.global_position.y)
	var y_then_x := Vector2(before_checkpoint.global_position.x, checkpoint.global_position.y)
	var guide_position := y_then_x
	if x_then_y.distance_squared_to(_track_center) > y_then_x.distance_squared_to(_track_center):
		guide_position = x_then_y
	var outward_offset := Vector2.ZERO
	if absf(segment.x) >= absf(segment.y):
		outward_offset.y = signf(guide_position.y - _track_center.y) * CORNER_GUIDE_OUTWARD_OFFSET
	else:
		outward_offset.x = signf(guide_position.x - _track_center.x) * CORNER_GUIDE_OUTWARD_OFFSET
	return guide_position + outward_offset


func _checkpoint_target_position(checkpoint_index: int) -> Vector2:
	var checkpoint := _checkpoints_by_index.get(checkpoint_index) as Node2D
	if checkpoint == null:
		return vehicle.global_position if is_instance_valid(vehicle) else Vector2.ZERO
	var corner_ratio := clampf(_checkpoint_turn_severity(checkpoint_index) / 1.45, 0.0, 1.0)
	var gate_lane_direction := Vector2.DOWN.rotated(checkpoint.global_rotation)
	var lane_scale := lerpf(1.0, 0.12, corner_ratio)
	var preferred_target := (
		checkpoint.global_position
		+ gate_lane_direction * lane_offset * lane_scale
	)
	return _select_clear_gate_target(
		checkpoint_index,
		checkpoint.global_position,
		gate_lane_direction,
		preferred_target
	)


func _select_clear_gate_target(
		checkpoint_index: int,
		checkpoint_position: Vector2,
		gate_lane_direction: Vector2,
		preferred_target: Vector2
) -> Vector2:
	if not vehicle.is_inside_tree():
		return preferred_target
	var entry_position: Vector2
	var guide_position: Variant = _checkpoint_entry_guide_position(checkpoint_index)
	if guide_position != null:
		entry_position = guide_position
	else:
		var previous := race_manager.get_checkpoint_before(checkpoint_index) as Node2D
		entry_position = previous.global_position if previous else vehicle.global_position
	var best_target := preferred_target
	var best_score := -INF
	for offset: float in GATE_TARGET_OFFSETS:
		var candidate := checkpoint_position + gate_lane_direction * offset
		var path := entry_position.direction_to(candidate)
		var path_length := entry_position.distance_to(candidate)
		var clearance := _ray_clearance_from(entry_position, path, path_length)
		var preference_penalty := candidate.distance_to(preferred_target) / 10000.0
		var score := clearance - preference_penalty
		if score > best_score:
			best_score = score
			best_target = candidate
	return best_target


func _checkpoint_turn_severity(checkpoint_index: int) -> float:
	var checkpoint := _checkpoints_by_index.get(checkpoint_index) as Node2D
	var previous := race_manager.get_checkpoint_before(checkpoint_index) as Node2D
	var next := race_manager.get_checkpoint_after(checkpoint_index) as Node2D
	if checkpoint == null or previous == null or next == null:
		return 0.0
	var guide_position: Variant = _checkpoint_entry_guide_position(checkpoint_index)
	if guide_position != null:
		var guide: Vector2 = guide_position
		var guide_path_in := (guide - previous.global_position).normalized()
		var guide_path_out := (checkpoint.global_position - guide).normalized()
		return absf(guide_path_in.angle_to(guide_path_out))
	var path_in := (checkpoint.global_position - previous.global_position).normalized()
	var path_out := (next.global_position - checkpoint.global_position).normalized()
	return absf(path_in.angle_to(path_out))


func _lookahead_distance() -> float:
	## Speed-proportional look-ahead used both to select the pure-pursuit goal
	## and as the pursuit radius, keeping the curvature math self-consistent.
	return (70.0 + vehicle.speed * 0.4) / float(personality["line_commitment"])


func _build_checkpoint_reference_path() -> PackedVector2Array:
	## Dense-enough closed reference loop from the ordered gate nodes. Each
	## checkpoint inserts its corner-guide apex (when the incoming segment is
	## not axis-aligned) so the path turns around the outside of corners instead
	## of cutting through the interior. Built in forward checkpoint_index order
	## regardless of the active race direction, matching the authored racing
	## line convention, so `_reference_goal` walks it backward uniformly for
	## reverse races.
	var ordered := race_manager.get_ordered_checkpoints()
	var count := ordered.size()
	if count < 3:
		return PackedVector2Array()
	var forward: Array[Node] = []
	for checkpoint: Node in ordered:
		forward.append(checkpoint)
	forward.sort_custom(func(a: Node, b: Node) -> bool:
		return int(a.get("checkpoint_index")) < int(b.get("checkpoint_index"))
	)
	var path := PackedVector2Array()
	for i in forward.size():
		var checkpoint := forward[i] as Node2D
		var previous := forward[(i - 1 + forward.size()) % forward.size()] as Node2D
		if checkpoint == null or previous == null:
			return PackedVector2Array()
		if i == 0:
			path.append(previous.global_position)
		var guide: Variant = _entry_guide_position(checkpoint, previous)
		if guide != null:
			path.append(guide)
		path.append(checkpoint.global_position)
	return path


func _reference_goal(forward: Vector2, lookahead: float) -> Dictionary:
	## Classic pure-pursuit goal: project the vehicle onto the reference loop,
	## advance by `lookahead` along the race direction, and return that point
	## plus the look-ahead distance actually used (the pursuit radius).
	_reference_goal_result["lookahead"] = lookahead
	if _reference_path.size() < 2:
		_reference_goal_result["goal"] = vehicle.global_position + forward * lookahead
		return _reference_goal_result
	_ensure_arc_tables_current()
	var count := _reference_path.size()
	var segment_lengths := _reference_segment_lengths
	var cumulative := _reference_cumulative
	var total := _reference_total
	if total < 0.001:
		_reference_goal_result["goal"] = vehicle.global_position + forward * lookahead
		return _reference_goal_result

	var nearest := _nearest_segment_local(_reference_path, vehicle.global_position, _reference_nearest_index)
	_reference_nearest_index = int(nearest["index"])
	var best_index := int(nearest["index"])
	var best_fraction := float(nearest["fraction"])

	var arc := cumulative[best_index] + segment_lengths[best_index] * best_fraction
	var direction := -1.0 if race_manager.is_reverse_direction() else 1.0
	var target_arc := clampf(arc + direction * lookahead, 0.0, total) if _open_route else fposmod(arc + direction * lookahead, total)
	var target_index := count - 1
	for i in count:
		if cumulative[i] <= target_arc:
			target_index = i
		else:
			break
	var target_fraction := clampf(
		(target_arc - cumulative[target_index]) / maxf(segment_lengths[target_index], 0.001),
		0.0,
		1.0
	)
	var goal := _reference_path[target_index].lerp(_reference_path[mini(target_index + 1, count - 1)] if _open_route else _reference_path[(target_index + 1) % count], target_fraction)
	_reference_goal_result["goal"] = goal
	return _reference_goal_result


func _leader_progress_deficit() -> float:
	var mine := race_manager.get_racer_progress(vehicle)
	var best := mine
	for racer: Node in _group_nodes(&"race_vehicle"):
		if not is_instance_valid(racer):
			continue
		best = maxf(best, race_manager.get_racer_progress(racer as Node2D))
	return maxf(0.0, best - mine)


func _is_pursuit_active() -> bool:
	if not is_instance_valid(pursuit_target) or not is_instance_valid(race_manager) or not race_manager.is_running:
		return false
	if race_manager.has_method("is_racer_finished") and race_manager.is_racer_finished(pursuit_target):
		return false
	return true


func _pursuit_distance_and_ahead(forward: Vector2) -> Dictionary:
	var result := {"distance": INF, "ahead": 0.0, "lateral": 0.0, "vehicle": null}
	if not _is_pursuit_active():
		return result
	var sep: Vector2 = pursuit_target.global_position - vehicle.global_position
	result["distance"] = sep.length()
	result["ahead"] = sep.dot(forward)
	result["lateral"] = sep.dot(forward.orthogonal())
	if pursuit_target is VehicleController:
		result["vehicle"] = pursuit_target
	return result


func _traffic_plan(
		delta: float,
		forward: Vector2,
		line_target: Vector2,
		line_radius: float
) -> Dictionary:
	var was_holding_overtake := _overtake_hold_remaining > 0.0
	_overtake_cooldown_remaining = maxf(0.0, _overtake_cooldown_remaining - delta)
	_overtake_hold_remaining = maxf(0.0, _overtake_hold_remaining - delta)
	if was_holding_overtake and _overtake_hold_remaining <= 0.0:
		_overtake_target_id = 0
		_overtake_cooldown_remaining = maxf(
			_overtake_cooldown_remaining,
			OVERTAKE_COOLDOWN / float(personality["overtake_aggression"])
		)
	var plan := _traffic_result
	plan["target_position"] = line_target
	plan["speed_scale"] = 1.0
	plan["speed_limit"] = INF
	plan["passing"] = false
	plan["drafting"] = false
	if not vehicle.is_inside_tree() or forward.length_squared() < 0.001:
		return plan
	if _open_route and _avoid_oncoming(forward, line_target, plan):
		_cancel_overtake()
		return plan

	var pursuit_info := _pursuit_distance_and_ahead(forward)
	var pursuit_dist := float(pursuit_info["distance"])
	var pursuit_ahead := float(pursuit_info["ahead"])
	var pursuit_vehicle := pursuit_info.get("vehicle") as VehicleController
	var in_pursuit_follow := _is_pursuit_active() and pursuit_dist < PURSUIT_CLOSING_DISTANCE and pursuit_ahead > 28.0

	var leader_info := _nearest_vehicle_ahead(forward)
	var leader := leader_info.get("vehicle") as Node2D
	var leader_speed := 0.0
	var leader_vel := Vector2.ZERO
	if leader:
		if leader is VehicleController:
			var vc := leader as VehicleController
			leader_speed = vc.speed
			leader_vel = vc.linear_velocity
		else:
			leader_vel = leader.get("linear_velocity") if "linear_velocity" in leader else Vector2.ZERO
			leader_speed = leader_vel.length()
	# In pursuit, always consider the pursuit_target for speed/closing logic (even if beyond normal overtake reach or traffic in between) so chaser closes by overtaking traffic to reach player.
	if _is_pursuit_active():
		var pinfo := _pursuit_distance_and_ahead(forward)
		var pdist := float(pinfo["distance"])
		var pahead := float(pinfo["ahead"])
		if pahead > 28.0 and pdist < 2000.0 and (leader == null or pdist < float(leader_info.get("distance", INF))):
			leader = pinfo.get("vehicle") as Node2D
			if leader:
				if leader is VehicleController:
					var vc2 := leader as VehicleController
					leader_speed = vc2.speed
					leader_vel = vc2.linear_velocity
				else:
					leader_vel = Vector2.ZERO
					leader_speed = 0.0
			leader_info = {"vehicle": leader, "distance": pdist, "lateral_distance": float(pinfo.get("lateral", 0.0))}
	var is_straight := line_radius <= 0.0 or line_radius >= OVERTAKE_STRAIGHT_RADIUS
	if in_pursuit_follow and leader == pursuit_vehicle:
		# suppress lateral overtake offset while following pursuit target inside closing range
		if _overtake_target_id != 0 and _overtake_target_id == (pursuit_vehicle.get_instance_id() if pursuit_vehicle else 0):
			_cancel_overtake()
	if _overtake_hold_remaining > 0.0 and _overtake_target_id != 0 and is_straight:
		var side := signf(_overtake_offset)
		if _overtake_side_clear(forward, side, leader):
			if in_pursuit_follow and leader == pursuit_vehicle:
				_cancel_overtake()
			else:
				plan["target_position"] = line_target + forward.orthogonal() * _overtake_offset
				plan["passing"] = true
				return plan
		_cancel_overtake()
	if _overtake_cooldown_remaining > 0.0 and not is_zero_approx(_overtake_offset):
		plan["target_position"] = line_target + forward.orthogonal() * _overtake_offset
	if leader == null:
		_overtake_offset = move_toward(_overtake_offset, 0.0, OVERTAKE_LINE_OFFSET * delta * 2.5)
		if not is_zero_approx(_overtake_offset):
			plan["target_position"] = line_target + forward.orthogonal() * _overtake_offset
		return plan

	var distance := float(leader_info["distance"])
	var lateral_distance := absf(float(leader_info["lateral_distance"]))
	var is_traffic_leader := leader != null and leader.is_in_group(&"track_traffic")
	plan["drafting"] = (
		is_straight
		and distance >= DRAFT_MIN_DISTANCE
		and distance <= DRAFT_MAX_DISTANCE
		and lateral_distance <= DRAFT_LATERAL_WIDTH
		and not is_traffic_leader
	)
	var aggression := float(personality["overtake_aggression"])
	var leader_is_slower := leader_speed + 22.0 / aggression < vehicle.speed or leader_speed < vehicle.get_effective_max_speed() * (0.75 + (aggression - 1.0) * 0.08)
	# only commit overtake when gap/room truly clear (corridor/apron checks inside side_score)
	var launch_complete := race_manager.race_time >= 1.0
	var pass_speed_ready := vehicle.speed >= 160.0 or leader_speed < 20.0
	if is_straight and leader_is_slower and launch_complete and pass_speed_ready and _overtake_cooldown_remaining <= 0.0 and distance > 55.0:
		if in_pursuit_follow and leader == pursuit_vehicle:
			# inside closing range (~340 units): suppress passing behavior on the pursuit target.
			# never fly far ahead; speed limit below settles at following gap just inside capture band.
			# far behind (>340): normal overtake logic (including this) remains available to close.
			pass
		else:
			var selected_side := _select_overtake_side(forward, leader)
			if not is_zero_approx(selected_side):
				_overtake_offset = selected_side * OVERTAKE_LINE_OFFSET
				_overtake_hold_remaining = OVERTAKE_HOLD_TIME * aggression
				_overtake_target_id = leader.get_instance_id()
				overtake_attempt_count += 1
				plan["target_position"] = line_target + forward.orthogonal() * _overtake_offset
				plan["passing"] = true
				return plan

	# A blocked pass remains a controlled tow rather than the former heavy brake.
	# For track_traffic: treat as things to pass (overtake logic above), do not follow/slow or draft.
	if is_traffic_leader:
		plan["speed_scale"] = 1.0
		plan["speed_limit"] = INF
	else:
		plan["speed_scale"] = 0.84
		var fdist := FOLLOWING_DISTANCE
		var ftime := FOLLOWING_TIME
		if in_pursuit_follow and leader == pursuit_vehicle:
			fdist = PURSUIT_FOLLOW_DISTANCE
			ftime = PURSUIT_FOLLOW_TIME
		plan["speed_limit"] = maxf(0.0, leader_vel.dot(forward)) + maxf(0.0, distance - fdist) / ftime
	return plan


func _nearest_vehicle_ahead(forward: Vector2) -> Dictionary:
	var nearest: Node2D
	var nearest_distance := INF
	var nearest_lateral := 0.0
	var lateral_axis := forward.orthogonal()
	var ahead_nodes: Array[Node] = []
	ahead_nodes.append_array(_group_nodes(&"race_vehicle"))
	ahead_nodes.append_array(_group_nodes(&"track_traffic"))
	for node: Node in ahead_nodes:
		if not is_instance_valid(node):
			continue
		var is_traffic := node.is_in_group(&"track_traffic")
		if is_traffic and int(node.get_meta("strip_direction", 1)) < 0:
			continue
		var candidate := node as Node2D
		if candidate == null or candidate == vehicle:
			continue
		if not is_traffic:
			var as_racer := node as VehicleController
			if as_racer == null:
				continue
			if race_manager.is_racer_finished(as_racer) or bool(race_manager.get_racer_state_ref(as_racer).get("dnf", false)):
				continue
		var separation := candidate.global_position - vehicle.global_position
		var distance_ahead := separation.dot(forward)
		var lateral_distance := separation.dot(lateral_axis)
		if distance_ahead < 28.0 or distance_ahead > OVERTAKE_REACH * float(personality["overtake_aggression"]):
			continue
		if absf(lateral_distance) > OVERTAKE_LATERAL_REACH:
			continue
		if distance_ahead < nearest_distance:
			nearest = candidate
			nearest_distance = distance_ahead
			nearest_lateral = lateral_distance
	if nearest == null:
		_leader_result.clear()
		return _leader_result
	_leader_result["vehicle"] = nearest
	_leader_result["distance"] = nearest_distance
	_leader_result["lateral_distance"] = nearest_lateral
	return _leader_result


func _avoid_oncoming(forward: Vector2, line_target: Vector2, plan: Dictionary) -> bool:
	# Oncoming traffic is a closing obstacle, never a drafting/following leader.
	# The reference path is the middle of the northbound carriageway, so either
	# evasive offset remains on that carriageway rather than crossing the divider.
	var nearest := INF
	var hazard_lateral := 0.0
	var right := forward.rotated(PI * 0.5)
	for node: Node in _group_nodes(&"track_traffic"):
		if not is_instance_valid(node) or int(node.get_meta("strip_direction", 1)) >= 0:
			continue
		var body := node as RigidBody2D
		if body == null:
			continue
		var separation := body.global_position - vehicle.global_position
		var ahead := separation.dot(forward)
		var closing := maxf(0.0, (vehicle.linear_velocity - body.linear_velocity).dot(forward))
		var lateral := separation.dot(right)
		if ahead <= 0.0 or ahead > maxf(OVERTAKE_REACH, closing * FOLLOWING_TIME) or absf(lateral) > OVERTAKE_LINE_OFFSET:
			continue
		if ahead < nearest:
			nearest = ahead
			hazard_lateral = lateral
	if nearest == INF:
		return false
	var side := -1.0 if hazard_lateral > 0.0 else 1.0
	plan["target_position"] = line_target + right * side * OVERTAKE_LINE_OFFSET
	plan["passing"] = true
	plan["speed_limit"] = maxf(0.0, nearest - FOLLOWING_DISTANCE) / FOLLOWING_TIME
	return true


func _select_overtake_side(forward: Vector2, leader: Node2D) -> float:
	var best_side := 0.0
	var best_score := -INF
	for side: float in [-1.0, 1.0]:
		var score := _overtake_side_score(forward, side, leader)
		if score > best_score:
			best_score = score
			best_side = side
	return best_side if best_score >= 0.90 else 0.0


func _overtake_side_clear(forward: Vector2, side: float, leader: Node2D) -> bool:
	return _overtake_side_score(forward, side, leader) >= 0.86


func _overtake_side_score(forward: Vector2, side: float, leader: Node2D) -> float:
	if is_zero_approx(side):
		return -INF
	var origin := vehicle.global_position + forward * OBSTACLE_FRONT_OFFSET
	var lateral := forward.orthogonal() * side
	var merge_end := origin + forward * OVERTAKE_MERGE_DISTANCE + lateral * OVERTAKE_LINE_OFFSET
	var merge_vector := merge_end - origin
	var excluded: Array[RID] = []
	if is_instance_valid(leader):
		excluded.append(leader.get_rid())
	var side_clearance := float(_ray_probe_from(
		origin,
		lateral,
		OVERTAKE_LINE_OFFSET,
		STATIC_OBSTACLE_MASK | VEHICLE_COLLISION_MASK,
		excluded
	)["clearance"])
	var merge_clearance := float(_ray_probe_from(
		origin,
		merge_vector.normalized(),
		merge_vector.length(),
		STATIC_OBSTACLE_MASK | VEHICLE_COLLISION_MASK,
		excluded
	)["clearance"])
	var lane_origin := origin + lateral * OVERTAKE_LINE_OFFSET
	var lane_clearance := float(_ray_probe_from(
		lane_origin,
		forward,
		OVERTAKE_CLEAR_DISTANCE,
		STATIC_OBSTACLE_MASK | VEHICLE_COLLISION_MASK
	)["clearance"])
	var base := minf(side_clearance, minf(merge_clearance, lane_clearance))
	# An obstacle on the opposite side does not make the clear side unsafe.
	# Bound the pass to the actual route instead of inferring a corridor
	# from unrelated walls in an intentionally open room.
	if _room_cut_checkpoint >= 0:
		for point: Vector2 in [lane_origin, merge_end]:
			var nearest := Geometry2D.get_closest_point_to_segment(point, _room_cut_start, _room_cut_end)
			if point.distance_to(nearest) > OVERTAKE_LINE_OFFSET + OBSTACLE_FEELER_HALF_WIDTH:
				return 0.0
	elif _reference_path.size() >= 3:
		for point: Vector2 in [lane_origin, merge_end]:
			var distance := INF
			for i in _reference_path.size():
				var nearest := Geometry2D.get_closest_point_to_segment(point, _reference_path[i], _reference_path[(i + 1) % _reference_path.size()])
				distance = minf(distance, point.distance_to(nearest))
			if distance > OVERTAKE_LINE_OFFSET + OBSTACLE_FEELER_HALF_WIDTH:
				return 0.0
	return base


func _cancel_overtake() -> void:
	_overtake_hold_remaining = 0.0
	_overtake_target_id = 0
	_overtake_cooldown_remaining = OVERTAKE_COOLDOWN / float(personality["overtake_aggression"])
	_overtake_offset = 0.0


func _apply_drafting_recharge(delta: float, traffic_plan: Dictionary, should_brake: bool) -> void:
	if should_brake or not bool(traffic_plan.get("drafting", false)):
		return
	vehicle.add_boost(vehicle.stats.boost_recharge * DRAFT_RECHARGE_MULTIPLIER * delta, "drafting")


func _group_nodes(group_name: StringName) -> Array[Node]:
	if _tree_cache_dirty:
		_refresh_tree_cache()
	match group_name:
		&"surface_zone":
			return _surface_zone_nodes
		&"race_vehicle":
			return _race_vehicle_nodes
		&"track_traffic":
			return _track_traffic_nodes
	return _scan_group(group_name)


func _refresh_tree_cache() -> void:
	if not is_instance_valid(vehicle) or not vehicle.is_inside_tree():
		return
	_surface_zone_nodes = _scan_group(&"surface_zone")
	_race_vehicle_nodes = _scan_group(&"race_vehicle")
	_track_traffic_nodes = _scan_group(&"track_traffic")
	for traffic: Node in _track_traffic_nodes:
		var on_exit := _on_traffic_exiting.bind(traffic)
		if not traffic.tree_exiting.is_connected(on_exit):
			traffic.tree_exiting.connect(on_exit, CONNECT_ONE_SHOT)
	_rebuild_surface_zone_records()
	_tree_cache_dirty = false


func _on_traffic_exiting(traffic: Node) -> void:
	_track_traffic_nodes.erase(traffic)


func _rebuild_surface_zone_records() -> void:
	_surface_zone_records.clear()
	for node: Node in _surface_zone_nodes:
		_surface_zone_records.append(_surface_zone_record(node as SurfaceZone))


func _surface_zone_record(zone: SurfaceZone) -> Dictionary:
	## Per-race snapshot of a surface zone: a global-space bounding circle around
	## the collision polygon (conservative — the polygon lies entirely inside it)
	## plus the derived risk and meta flags the probe loops re-read every tick.
	if zone == null or not is_instance_valid(zone):
		return {"zone": null, "center": Vector2.ZERO, "radius_sq": INF}
	var center := Vector2.ZERO
	var radius_sq := 0.0
	var vertex_count := 0
	var collision := zone.get_node_or_null("SurfaceCollision") as CollisionPolygon2D
	var polygon := collision.polygon if collision != null else PackedVector2Array()
	for point: Vector2 in polygon:
		center += zone.to_global(point)
		vertex_count += 1
	if vertex_count > 0:
		center /= float(vertex_count)
		for point: Vector2 in polygon:
			radius_sq = maxf(radius_sq, center.distance_squared_to(zone.to_global(point)))
	else:
		center = zone.global_position
	return {
		"zone": zone,
		"center": center,
		"radius_sq": radius_sq,
		"risk": _surface_zone_risk(zone),
		"lane": StringName(zone.get_meta("lane", &"full")),
		"role": StringName(zone.get_meta("role", &"")),
		"ai_path_clear": bool(zone.get_meta("ai_path_clear", false)),
		"grip": zone.grip_multiplier,
		"speed": zone.speed_multiplier,
	}


func _surface_zone_records_for_tick() -> Array[Dictionary]:
	if _tree_cache_dirty:
		_refresh_tree_cache()
	return _surface_zone_records


func _probe_ray_near_zone(record: Dictionary, origin: Vector2, direction: Vector2) -> bool:
	## Broad phase: does the zone's bounding circle intersect the probe ray
	## [origin, origin + direction * max_probe]? If not, no probe point along it
	## can lie inside the polygon, so the polygon test is skipped entirely.
	var center: Vector2 = record["center"]
	var radius_sq: float = record["radius_sq"]
	var ray := direction * SURFACE_PROBE_DISTANCES[-1]
	var to_center := center - origin
	var ray_length_sq := ray.length_squared()
	if ray_length_sq < 0.001:
		return to_center.length_squared() <= radius_sq
	var t := clampf(to_center.dot(ray) / ray_length_sq, 0.0, 1.0)
	return (origin + ray * t).distance_squared_to(center) <= radius_sq


func _scan_group(group_name: StringName) -> Array[Node]:
	tree_group_scan_count += 1
	return vehicle.get_tree().get_nodes_in_group(group_name)


func _zone_contains(zone: SurfaceZone, point: Vector2) -> bool:
	surface_zone_probe_count += 1
	return zone.contains_global_point(point)


func _difficulty_tuning() -> Dictionary:
	return DIFFICULTY_TUNING.get(difficulty, DIFFICULTY_TUNING["club_circuit"]) as Dictionary


func _configure_personality(driver_id: String, driver_style: Dictionary) -> void:
	personality_id = driver_id if not driver_id.is_empty() else "baseline"
	personality = DEFAULT_PERSONALITY.duplicate()
	var personality_scale := float(_difficulty_tuning()["personality_scale"])
	for key: String in DEFAULT_PERSONALITY:
		var bounds: Vector2 = PERSONALITY_BOUNDS[key]
		var requested := clampf(float(driver_style.get(key, 1.0)), bounds.x, bounds.y)
		personality[key] = lerpf(1.0, requested, personality_scale)


func _shortcut_route_is_suitable(track: Node) -> bool:
	var tuning := _difficulty_tuning()
	if not bool(tuning["shortcut_enabled"]) or _shortcut_racing_line.is_empty():
		return false
	var min_steering_rate := float(tuning["shortcut_min_steering_rate"])
	if min_steering_rate > 0.0 and vehicle.stats.physics_model_version != 0 and vehicle.stats.steering_rate < min_steering_rate:
		return false
	var definitions: Variant = track.get_meta("generated_surfaces", [])
	if definitions is not Array:
		return false
	for definition: Dictionary in definitions:
		if StringName(definition.get("role", &"")) != &"shortcut":
			continue
		if not bool(definition.get("ai_path_clear", false)):
			return false
		var preference := float(personality["shortcut_preference"])
		if vehicle.stats.physics_model_version != 0:
			var shortcut_grip := float(definition.get("grip", 0.0))
			var dry_corner := vehicle.get_safe_corner_speed(300.0, 1.0)
			var shortcut_corner := vehicle.get_safe_corner_speed(300.0, shortcut_grip)
			var retained_corner_speed := shortcut_corner / maxf(dry_corner, 0.001)
			var minimum_retention := float(tuning["shortcut_min_retention"]) / preference
			return retained_corner_speed >= minimum_retention and float(definition.get("speed", 0.0)) >= 1.0
		var combined_grip := float(definition.get("grip", 0.0)) * vehicle.stats.grip
		var minimum_grip := float(tuning["shortcut_min_grip"]) / preference
		return combined_grip >= minimum_grip and float(definition.get("speed", 0.0)) >= 1.0
	return false


func _planned_surface_grip(surface_plan: Dictionary) -> float:
	if float(surface_plan.get("risk", 0.0)) > 0.0:
		return float(surface_plan.get("grip_scale", 1.0))
	return vehicle.surface_grip_multiplier


func _surface_anticipation(desired_direction: Vector2) -> Dictionary:
	var plan := _surface_result
	plan["weight"] = 0.0
	plan["speed_scale"] = 1.0
	plan["grip_scale"] = 1.0
	plan["risk"] = 0.0
	plan["avoid_direction"] = desired_direction
	if not vehicle.is_inside_tree():
		return plan
	var shortcut_zone := _upcoming_shortcut_zone(desired_direction)
	if shortcut_zone != null:
		var shortcut_risk := _surface_zone_risk(shortcut_zone)
		plan["risk"] = shortcut_risk
		plan["grip_scale"] = shortcut_zone.grip_multiplier
		if vehicle.stats.physics_model_version != 0:
			plan["speed_scale"] = _surface_driving_speed_scale(shortcut_zone.speed_multiplier, shortcut_zone.grip_multiplier, desired_direction)
		else:
			var combined_grip := vehicle.stats.grip * shortcut_zone.grip_multiplier
			plan["speed_scale"] = clampf(0.74 + combined_grip * 0.32, 0.78, 0.94)
		return plan
	var center_model := _surface_model(desired_direction)
	var center_risk := float(center_model["risk"])
	plan["risk"] = center_risk
	plan["grip_scale"] = float(center_model["grip"])
	plan["speed_scale"] = (
		_surface_driving_speed_scale(float(center_model["speed"]), float(center_model["grip"]), desired_direction)
		if vehicle.stats.physics_model_version != 0
		else lerpf(1.0, 0.72, center_risk)
	)
	if center_risk < 0.12 or not _surface_route_can_avoid(desired_direction):
		return plan
	var best_direction := desired_direction
	var best_risk := center_risk
	for angle: float in SURFACE_PROBE_ANGLES:
		if is_zero_approx(angle):
			continue
		var candidate := desired_direction.rotated(angle)
		if _ray_clearance_from(vehicle.global_position, candidate, SURFACE_PROBE_DISTANCES[-1]) < 0.82:
			continue
		var candidate_risk := _surface_exposure(candidate)
		if candidate_risk < best_risk - 0.08:
			best_risk = candidate_risk
			best_direction = candidate
	if best_direction != desired_direction:
		plan["avoid_direction"] = best_direction
		plan["weight"] = clampf(0.28 + center_risk * 0.34, 0.0, 0.58)
		plan["speed_scale"] = lerpf(1.0, 0.82, best_risk)
	return plan


func _surface_driving_speed_scale(speed_scale: float, grip_scale: float, direction: Vector2) -> float:
	# Low grip limits correction/turning authority, not forward speed by
	# itself. A straight, aligned car may carry its momentum across a slick.
	var forward := Vector2.UP.rotated(vehicle.rotation)
	var correction := maxf(absf(forward.angle_to(direction)) / 0.12, absf(vehicle.slip_angle) / 8.0)
	var traction_limit := lerpf(1.0, sqrt(maxf(grip_scale, 0.01)), clampf(correction, 0.0, 1.0))
	return minf(speed_scale, traction_limit)


func _surface_model(direction: Vector2) -> Dictionary:
	var model := _surface_model_result
	model["risk"] = 0.0
	model["grip"] = 1.0
	model["speed"] = 1.0
	var model_risk := 0.0
	var origin := vehicle.global_position
	for record: Dictionary in _surface_zone_records_for_tick():
		if not _probe_ray_near_zone(record, origin, direction):
			continue
		var zone := record["zone"] as SurfaceZone
		for distance: float in SURFACE_PROBE_DISTANCES:
			if not _zone_contains(zone, origin + direction * distance):
				continue
			var risk := float(record["risk"])
			if risk >= model_risk:
				model_risk = risk
				model["risk"] = risk
				model["grip"] = float(record["grip"])
				model["speed"] = float(record["speed"])
			break
	return model


func _upcoming_shortcut_zone(direction: Vector2) -> SurfaceZone:
	if not uses_shortcut_line:
		return null
	var origin := vehicle.global_position
	for record: Dictionary in _surface_zone_records_for_tick():
		if StringName(record["role"]) != &"shortcut":
			continue
		if not bool(record["ai_path_clear"]):
			continue
		if not _probe_ray_near_zone(record, origin, direction):
			continue
		var zone := record["zone"] as SurfaceZone
		for distance: float in SURFACE_PROBE_DISTANCES:
			if _zone_contains(zone, origin + direction * distance):
				return zone
	return null


func _surface_exposure(direction: Vector2) -> float:
	var exposure := 0.0
	var origin := vehicle.global_position
	for record: Dictionary in _surface_zone_records_for_tick():
		var zone_risk := float(record["risk"])
		if zone_risk <= 0.0:
			continue
		if not _probe_ray_near_zone(record, origin, direction):
			continue
		var zone := record["zone"] as SurfaceZone
		for distance: float in SURFACE_PROBE_DISTANCES:
			if _zone_contains(zone, origin + direction * distance):
				exposure = maxf(exposure, zone_risk)
				break
	return exposure


func _surface_route_can_avoid(direction: Vector2) -> bool:
	var found_risk := false
	var origin := vehicle.global_position
	for record: Dictionary in _surface_zone_records_for_tick():
		var zone_risk := float(record["risk"])
		if zone_risk <= 0.0:
			continue
		if not _probe_ray_near_zone(record, origin, direction):
			continue
		var zone := record["zone"] as SurfaceZone
		for distance: float in SURFACE_PROBE_DISTANCES:
			if not _zone_contains(zone, origin + direction * distance):
				continue
			found_risk = true
			if StringName(record["lane"]) == &"full":
				return false
			break
	return found_risk


func _surface_zone_risk(zone: SurfaceZone) -> float:
	return maxf(
		clampf((0.72 - zone.grip_multiplier) / 0.4, 0.0, 1.0),
		clampf((0.84 - zone.speed_multiplier) / 0.4, 0.0, 1.0)
	)


func _obstacle_avoidance(forward: Vector2, desired_direction: Vector2) -> Dictionary:
	var plan := _obstacle_result
	plan["weight"] = 0.0
	plan["speed_scale"] = 1.0
	plan["speed_limit"] = INF
	plan["avoid_direction"] = desired_direction
	plan["static_contact"] = false
	plan["escape_steer"] = 0.0
	if not vehicle.is_inside_tree():
		return plan
	var origin := vehicle.global_position + forward * OBSTACLE_FRONT_OFFSET
	var feeler_length := clampf(vehicle.speed * 0.75, LOW_SPEED_FEELER_LENGTH, 360.0)
	var best_clearance := -1.0
	var best_direction := desired_direction
	var center_clearance := 1.0
	var hitting_vehicle := false
	var wall_normal := Vector2.ZERO
	for angle: float in OBSTACLE_FEELER_ANGLES:
		var probe_direction := desired_direction.rotated(angle)
		var probe := _ray_probe_from(origin, probe_direction, feeler_length, STATIC_OBSTACLE_MASK | VEHICLE_COLLISION_MASK)
		var probe_clearance := float(probe["clearance"])
		if is_zero_approx(angle):
			center_clearance = probe_clearance
			hitting_vehicle = bool(probe["is_vehicle"])
			wall_normal = probe["normal"] as Vector2
		if probe_clearance > best_clearance:
			best_clearance = probe_clearance
			best_direction = probe_direction
	if vehicle.has_static_contact and vehicle.speed <= STATIC_ESCAPE_MAX_SPEED:
		center_clearance = 0.0
		hitting_vehicle = false
		wall_normal = vehicle.static_contact_normal
	if center_clearance >= 0.92:
		return plan
	if hitting_vehicle and center_clearance * feeler_length >= 20.0:
		# Traffic planning owns following and passing. Do not add an unplanned
		# swerve toward scenery merely because the leader is visible ahead.
		return plan
	if wall_normal.length_squared() > 0.01 and not hitting_vehicle:
		var slide := Vector2(-wall_normal.y, wall_normal.x)
		if slide.dot(desired_direction) < 0.0:
			slide = -slide
		if slide.dot(forward) < 0.15:
			slide = forward.slerp(slide, 0.65)
		best_direction = slide.normalized()
	var obstruction := 1.0 - center_clearance
	plan["avoid_direction"] = best_direction.normalized()
	var minimum_weight := 0.34 if hitting_vehicle else (0.68 if vehicle.speed < 60.0 else 0.52)
	plan["weight"] = clampf(minimum_weight + obstruction * 0.5, 0.0, 0.95)
	if (
		not hitting_vehicle
		and wall_normal.length_squared() > 0.01
		and center_clearance <= STATIC_CONTACT_CLEARANCE_RATIO
		and vehicle.speed <= STATIC_ESCAPE_MAX_SPEED
	):
		plan["static_contact"] = true
		var escape_angle := forward.angle_to(best_direction)
		plan["escape_steer"] = signf(escape_angle) if not is_zero_approx(escape_angle) else 1.0
	# Traffic pace is planned by _traffic_plan; obstacle avoidance still chooses
	# a safe direction without multiplying it into a permanent slow train.
	plan["speed_scale"] = 1.0 if hitting_vehicle else lerpf(0.78, 0.34, obstruction)
	if not hitting_vehicle:
		# Steering has already chosen the escape/slide direction. Preserve
		# enough rolling speed to follow it, without multiplying a corner's
		# independently safe speed by this obstacle limit a second time.
		plan["speed_limit"] = vehicle.get_effective_max_speed() * float(plan["speed_scale"])
	return plan


func _ray_clearance_from(origin: Vector2, direction: Vector2, feeler_length: float) -> float:
	return float(_ray_probe_from(origin, direction, feeler_length, STATIC_OBSTACLE_MASK)["clearance"])


func _ray_probe_from(
		origin: Vector2,
		direction: Vector2,
		feeler_length: float,
		mask: int,
		excluded_rids: Array[RID] = []
) -> Dictionary:
	if feeler_length <= 0.001:
		var empty: Dictionary = _ray_results[0]
		empty["clearance"] = 1.0
		empty["is_vehicle"] = false
		empty["normal"] = Vector2.ZERO
		return empty
	var side_offset := direction.orthogonal() * OBSTACLE_FEELER_HALF_WIDTH
	var center := _single_ray_probe(origin, direction, feeler_length, mask, excluded_rids, 0)
	var left := _single_ray_probe(origin + side_offset, direction, feeler_length, mask, excluded_rids, 1)
	var right := _single_ray_probe(origin - side_offset, direction, feeler_length, mask, excluded_rids, 2)
	var closest := center
	if float(left["clearance"]) < float(closest["clearance"]):
		closest = left
	if float(right["clearance"]) < float(closest["clearance"]):
		closest = right
	return closest


func _single_ray_probe(
		origin: Vector2,
		direction: Vector2,
		feeler_length: float,
		mask: int,
		excluded_rids: Array[RID] = [],
		slot: int = 0
) -> Dictionary:
	var result: Dictionary = _ray_results[slot]
	if _ray_query == null:
		_ray_query = PhysicsRayQueryParameters2D.new()
	_ray_excludes.clear()
	_ray_excludes.append(vehicle.get_rid())
	_ray_excludes.append_array(excluded_rids)
	var query := _ray_query
	query.from = origin
	query.to = origin + direction * feeler_length
	query.collision_mask = mask
	query.exclude = _ray_excludes
	var hit := vehicle.get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		result["clearance"] = 1.0
		result["is_vehicle"] = false
		result["normal"] = Vector2.ZERO
		return result
	var collider: Variant = hit.get("collider")
	var is_vehicle := collider is Node and ((collider as Node).is_in_group("race_vehicle") or (collider as Node).is_in_group("track_traffic"))
	var hit_normal := (hit.get("normal", Vector2.ZERO) as Vector2).normalized()
	result["clearance"] = origin.distance_to(hit["position"]) / feeler_length
	result["is_vehicle"] = is_vehicle
	result["normal"] = hit_normal
	return result


func _update_spin_recovery(delta: float) -> bool:
	## A car facing roughly the right way but sliding backward makes no route
	## progress, and its heading-based steering will not correct the slide. The
	## throttle lift in _physics_process usually catches the slide early; if the
	## backward slide persists, reuse the standard recovery teleport instead of
	## ploughing on for seconds.
	if vehicle.speed > SPIN_MIN_SPEED and absf(vehicle.slip_angle) > SPIN_RECOVER_SLIP_DEG:
		_spin_time += delta
	else:
		_spin_time = 0.0
	if _spin_time >= SPIN_RECOVER_TIMEOUT and not _recovery_cooldown_active():
		_recover_vehicle(&"spin")
		return true
	return false


func _update_stuck_recovery(delta: float, target_key: int, distance_to_target: float) -> void:
	if target_key != _stuck_target_key:
		_stuck_target_key = target_key
		_best_checkpoint_distance = distance_to_target
		_stuck_time = 0.0
		return
	if _recovery_cooldown_active():
		_stuck_time = 0.0
		return
	if distance_to_target < _best_checkpoint_distance - 18.0:
		_best_checkpoint_distance = distance_to_target
		_stuck_time = 0.0
		return
	if vehicle.speed >= STUCK_SPEED:
		_stuck_time = 0.0
		return
	_stuck_time += delta
	if _stuck_time >= STUCK_TIMEOUT:
		_recover_vehicle(&"checkpoint_stall")


func _update_route_watchdog(delta: float, expected_index: int, turn_around: bool = false) -> Dictionary:
	var sample := _active_route_sample(expected_index)
	var target_key: int = ((expected_index + 1) << 8) | ((_room_cut_checkpoint + 1) & 0xFF)
	if target_key != _watchdog_target_key:
		_watchdog_target_key = target_key
		_last_route_arc = float(sample["arc"])
		_route_progress_accumulator = 0.0
		_off_route_time = 0.0
		_no_progress_time = 0.0
		_wrong_way_progress_time = 0.0
		_watchdog_result["made_progress"] = true
		return _watchdog_result

	var route_length := maxf(float(sample["length"]), 0.001)
	var route_delta := float(sample["arc"]) - _last_route_arc
	if bool(sample["closed"]):
		if route_delta > route_length * 0.5:
			route_delta -= route_length
		elif route_delta < -route_length * 0.5:
			route_delta += route_length
	_last_route_arc = float(sample["arc"])
	var made_progress := false
	# A reverse/forward escape must earn net route progress, not count the
	# same few units repeatedly while oscillating against a solid object.
	_route_progress_accumulator += route_delta
	if _route_progress_accumulator >= ROUTE_PROGRESS_COMMIT_DISTANCE:
		made_progress = true
		_route_progress_accumulator = 0.0
		_no_progress_time = 0.0
	elif turn_around and absf(vehicle.angular_velocity) > 0.35:
		# Actual rotation earns more time, not permanent immunity to recovery.
		_no_progress_time += delta * 0.5
	else:
		_no_progress_time += delta

	var lateral_distance := float(sample["distance"])
	if lateral_distance >= _off_route_distance:
		_off_route_time += delta
	else:
		_off_route_time = 0.0

	var moving_against_route := route_delta < -4.0
	if _escape_time_remaining > 0.0:
		_wrong_way_progress_time = maxf(0.0, _wrong_way_progress_time - delta)
	elif turn_around and absf(vehicle.angular_velocity) > 0.35:
		_wrong_way_progress_time = 0.0
	elif race_manager.is_racer_wrong_way(vehicle) or moving_against_route:
		_wrong_way_progress_time += delta
	elif route_delta > 2.0:
		_wrong_way_progress_time = 0.0
	else:
		_wrong_way_progress_time = maxf(0.0, _wrong_way_progress_time - delta * 0.5)

	if _off_route_time >= OFF_ROUTE_TIMEOUT:
		if not _recovery_cooldown_active():
			_recover_vehicle(&"off_route")
	elif (
		_no_progress_time >= NO_PROGRESS_TIMEOUT
		or _wrong_way_progress_time >= WRONG_WAY_PROGRESS_TIMEOUT
	):
		if not _recovery_cooldown_active():
			_recover_vehicle(&"wrong_way" if _wrong_way_progress_time >= WRONG_WAY_PROGRESS_TIMEOUT else &"no_progress")
	_watchdog_result["made_progress"] = made_progress
	return _watchdog_result


func _active_route_sample(expected_index: int) -> Dictionary:
	if _room_cut_checkpoint == expected_index:
		var segment := _room_cut_end - _room_cut_start
		var fraction := clampf((vehicle.global_position - _room_cut_start).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
		var nearest := _room_cut_start + segment * fraction
		_route_sample_result["arc"] = segment.length() * fraction
		_route_sample_result["length"] = segment.length()
		_route_sample_result["distance"] = vehicle.global_position.distance_to(nearest)
		_route_sample_result["closed"] = false
		return _route_sample_result
	if _racing_line.size() >= 2:
		_ensure_arc_tables_current()
		var count := _racing_line.size()
		var nearest := _nearest_segment_local(_racing_line, vehicle.global_position, _racing_line_nearest_index)
		_racing_line_nearest_index = int(nearest["index"])
		var best_index := int(nearest["index"])
		var best_fraction := float(nearest["fraction"])
		var best_distance_squared := float(nearest["distance_squared"])
		var total := _racing_line_total
		var best_arc := _racing_line_cumulative[best_index] + _racing_line_segment_lengths[best_index] * best_fraction
		var directional_arc := fposmod(total - best_arc, total) if race_manager.is_reverse_direction() and not _open_route else best_arc
		_route_sample_result["arc"] = directional_arc
		_route_sample_result["length"] = total
		_route_sample_result["distance"] = sqrt(best_distance_squared)
		_route_sample_result["closed"] = not _open_route
		return _route_sample_result

	var checkpoint := _checkpoints_by_index.get(expected_index) as Node2D
	var previous := race_manager.get_checkpoint_before(expected_index) as Node2D
	if checkpoint == null or previous == null:
		_route_sample_result["arc"] = 0.0
		_route_sample_result["length"] = 1.0
		_route_sample_result["distance"] = 0.0
		_route_sample_result["closed"] = false
		return _route_sample_result
	var segment := checkpoint.global_position - previous.global_position
	var fraction := clampf(
		(vehicle.global_position - previous.global_position).dot(segment) / maxf(segment.length_squared(), 0.001),
		0.0,
		1.0
	)
	var nearest := previous.global_position + segment * fraction
	_route_sample_result["arc"] = segment.length() * fraction
	_route_sample_result["length"] = segment.length()
	_route_sample_result["distance"] = vehicle.global_position.distance_to(nearest)
	_route_sample_result["closed"] = false
	return _route_sample_result


func _update_static_escape(delta: float, obstacle_plan: Dictionary, made_progress: bool) -> bool:
	if _escape_time_remaining > 0.0:
		_escape_time_remaining = maxf(0.0, _escape_time_remaining - delta)
		vehicle.set_external_controls(0.0, 1.0, _escape_steer)
		if _escape_time_remaining <= 0.0:
			_static_contact_time = 0.0
		return true
	if made_progress:
		_static_contact_time = 0.0
		return false
	if bool(obstacle_plan.get("static_contact", false)):
		_static_contact_time += delta
	else:
		_static_contact_time = maxf(0.0, _static_contact_time - delta * 2.0)
	if _static_contact_time < STATIC_CONTACT_TIMEOUT:
		return false
	_escape_time_remaining = STATIC_ESCAPE_DURATION
	_escape_steer = clampf(float(obstacle_plan.get("escape_steer", 1.0)), -1.0, 1.0)
	if is_zero_approx(_escape_steer):
		_escape_steer = 1.0
	static_escape_attempt_count += 1
	vehicle.set_external_controls(0.0, 1.0, _escape_steer)
	return true


func _recover_vehicle(reason: StringName = &"unknown") -> void:
	if _recovering:
		return
	_recovering = true
	if race_manager.has_method("report_recovery"):
		race_manager.call("report_recovery", vehicle)
	_room_cut_checkpoint = -1
	recovery_count += 1
	recovery_reasons[reason] = int(recovery_reasons.get(reason, 0)) + 1
	_recovery_cooldown_remaining = RECOVERY_COOLDOWN
	_stuck_time = 0.0
	_guide_checkpoint_index = -1
	_guide_reached = false
	_stuck_target_key = 0
	_best_checkpoint_distance = INF
	_smoothed_steer = 0.0
	_reset_overtake_state()
	_reset_route_watchdog()
	vehicle.set_external_controls(0.0, 0.0, 0.0)
	var saved_layer := vehicle.collision_layer
	var saved_mask := vehicle.collision_mask
	var recovery_transform := race_manager.get_last_recovery_transform(vehicle)
	var recovery_forward := Vector2.UP.rotated(recovery_transform.get_rotation())
	recovery_transform.origin += recovery_forward.orthogonal() * lane_offset
	vehicle.freeze = true
	vehicle.global_transform = recovery_transform
	vehicle.linear_velocity = Vector2.ZERO
	vehicle.angular_velocity = 0.0
	vehicle.reset_surface_modifiers()
	_racing_line_nearest_index = -1
	_reference_nearest_index = -1
	if vehicle.has_method("reset_dynamics_state"):
		vehicle.call("reset_dynamics_state")
	vehicle.collision_layer = 0
	vehicle.collision_mask = 0
	vehicle.modulate.a = 0.45
	vehicle.freeze = false
	var eff_max := 650.0
	if vehicle.has_method("get_effective_max_speed"):
		eff_max = vehicle.call("get_effective_max_speed")
	vehicle.linear_velocity = recovery_forward * clampf(eff_max * 0.28, 170.0, 210.0)
	vehicle.boost_amount = maxf(vehicle.boost_amount * 0.5, vehicle.get_boost_capacity() * 0.35)

	# process_in_physics keeps the recovery ghost on the fixed physics step so a
	# recovery teleport is deterministic, matching the race-time determinism work.
	await get_tree().create_timer(RECOVERY_GHOST_TIME, false, true).timeout
	if is_instance_valid(vehicle) and is_instance_valid(race_manager) and not race_manager.is_racer_finished(vehicle):
		vehicle.collision_layer = saved_layer
		vehicle.collision_mask = saved_mask
		vehicle.modulate.a = 1.0
	elif is_instance_valid(vehicle):
		vehicle.collision_layer = 0
		vehicle.collision_mask = 0
	_recovering = false


func _recovery_cooldown_active() -> bool:
	return _recovery_cooldown_remaining > 0.0


func _reset_overtake_state() -> void:
	_overtake_hold_remaining = 0.0
	_overtake_cooldown_remaining = 0.0
	_overtake_target_id = 0
	_overtake_offset = 0.0


func _reset_route_watchdog() -> void:
	_off_route_time = 0.0
	_no_progress_time = 0.0
	_wrong_way_progress_time = 0.0
	_spin_time = 0.0
	_route_progress_accumulator = 0.0
	_watchdog_target_key = 0
	_last_route_arc = 0.0
	_static_contact_time = 0.0
	_escape_time_remaining = 0.0
	_escape_steer = 0.0


func _ghost_finished_vehicle() -> void:
	if _finished_ghosted:
		return
	_finished_ghosted = true
	vehicle.collision_layer = 0
	vehicle.collision_mask = 0


func _restore_racing_collisions() -> void:
	_finished_ghosted = false
	if is_instance_valid(vehicle):
		vehicle.collision_layer = _race_collision_layer
		vehicle.collision_mask = _race_collision_mask
	_reset_route_watchdog()


func _on_external_recovery(racer: Node2D) -> void:
	## A player-facing recovery (ResetManager) teleports the car without going
	## through this controller's own _recover_vehicle. Re-anchor the route
	## watchdog so the arc discontinuity is not charged as backward travel.
	if racer == vehicle:
		_reset_route_watchdog()
		_racing_line_nearest_index = -1
		_reference_nearest_index = -1


func _on_racer_registered(_racer: Node2D) -> void:
	## The per-race scene-tree cache (surface zones, race vehicles) is
	## only valid once the field is fully placed. A racer registered after this
	## controller first populated the cache means the cached vehicle list is
	## stale — a grid-launch traffic scan would otherwise miss cars still being
	## placed and treat the track as empty. Mark the cache dirty so the next
	## scan re-reads the tree instead of trusting the frozen list.
	_tree_cache_dirty = true


func _nearest_line_index(position: Vector2) -> int:
	var count := _racing_line.size()
	if _racing_line_nearest_index >= 0 and _racing_line_nearest_index < count:
		var best := _racing_line_nearest_index
		var best_distance := _racing_line[best].distance_squared_to(position)
		for delta in 65:
			var index := clampi(_racing_line_nearest_index - 32 + delta, 0, count - 1) if _open_route else posmod(_racing_line_nearest_index - 32 + delta, count)
			var distance := _racing_line[index].distance_squared_to(position)
			if distance < best_distance:
				best_distance = distance
				best = index
		_racing_line_nearest_index = best
		return best
	var best := 0
	var best_distance := INF
	for index in count:
		var distance := _racing_line[index].distance_squared_to(position)
		if distance < best_distance:
			best_distance = distance
			best = index
	_racing_line_nearest_index = best
	return best


func _racing_line_target(forward: Vector2) -> Vector2:
	if _racing_line.is_empty():
		return vehicle.global_position + forward * 200.0
	var count := _racing_line.size()
	var index := _nearest_line_index(vehicle.global_position)
	var direction := -1 if race_manager.is_reverse_direction() else 1
	var lookahead := (70.0 + vehicle.speed * 0.4) / float(personality["line_commitment"])
	var walked := 0.0
	for step in count:
		if _open_route and (index + direction < 0 or index + direction >= count):
			return _racing_line[index]
		var next := (index + direction + count) % count
		var segment := _racing_line[index].distance_to(_racing_line[next])
		if walked + segment >= lookahead and segment > 0.001:
			return _racing_line[index].lerp(_racing_line[next], (lookahead - walked) / segment)
		walked += segment
		index = next
	return _racing_line[index]


func _racing_line_radius(position: Vector2) -> float:
	if _racing_line.size() < 20:
		return 0.0
	return _radius_at_line_index(_nearest_line_index(position))


func _radius_at_line_index(index: int) -> float:
	var count := _racing_line.size()
	var direction := -1 if race_manager.is_reverse_direction() else 1
	var a := _racing_line[index]
	var b := _racing_line[clampi(index + 9 * direction, 0, count - 1)] if _open_route else _racing_line[(index + 9 * direction + count) % count]
	var c := _racing_line[clampi(index + 18 * direction, 0, count - 1)] if _open_route else _racing_line[(index + 18 * direction + count) % count]
	var ab := a.distance_to(b)
	var bc := b.distance_to(c)
	var ac := a.distance_to(c)
	if ab < 0.001 or bc < 0.001 or ac < 0.001:
		return 0.0
	var cross := absf((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x))
	if cross < 0.001:
		return 0.0
	# The cross product is twice the triangle's area: R = abc / (2 * cross).
	var radius := ab * bc * ac / (2.0 * cross)
	return clampf(radius, 0.0, MAX_RACING_LINE_RADIUS)


func _v1_curvature_hazard(expected_index: int) -> Dictionary:
	## Upcoming corner for the v1 planner: the tightest radius ahead and the
	## distance to that corner's entry. Falls back to checkpoint geometry (no
	## constant straight-radius) when the racing line is unavailable.
	if _racing_line.size() >= 20:
		return _racing_line_curvature_hazard()
	return _checkpoint_curvature_hazard(expected_index)


func _racing_line_curvature_hazard() -> Dictionary:
	# Each radius is paired with its own distance. The tightest braking
	# envelope wins, rather than a distant apex imposing its speed everywhere.
	var count := _racing_line.size()
	var direction := -1 if race_manager.is_reverse_direction() else 1
	var index := _nearest_line_index(vehicle.global_position)
	var effective_max_speed := vehicle.get_effective_max_speed()
	var horizon := 900.0
	var walked := 0.0
	var hazard_radius := MAX_RACING_LINE_RADIUS
	var hazard_distance := INF
	var speed_limit := effective_max_speed
	for _step in count:
		if walked > horizon:
			break
		var radius := _radius_at_line_index(index)
		if radius > 0.0:
			var allowed := _v1_speed_envelope(radius, walked)
			if allowed < speed_limit:
				speed_limit = allowed
				hazard_distance = walked
				hazard_radius = radius
		if _open_route and (index + direction < 0 or index + direction >= count):
			break
		var next := (index + direction + count) % count
		walked += _racing_line[index].distance_to(_racing_line[next])
		index = next
	_hazard_result["radius"] = hazard_radius
	_hazard_result["distance"] = hazard_distance
	_hazard_result["speed_limit"] = speed_limit
	return _hazard_result


func _v1_speed_envelope(radius: float, distance: float) -> float:
	var maximum := vehicle.get_effective_max_speed()
	if radius <= 0.0 or is_inf(distance):
		return maximum
	# Grip anticipation belongs in corner capacity, not a blanket straight-
	# line speed penalty. The previous frame's short horizon is conservative
	# on entry while actual surface grip always takes precedence when lower.
	var grip := minf(vehicle.surface_grip_multiplier, _anticipated_grip)
	# Reserve some tire capacity for braking and tracking corrections instead
	# of planning every corner at the theoretical steady-state grip peak.
	var lateral_accel := minf(vehicle.stats.front_grip, vehicle.stats.rear_grip) * grip * DYNAMICS.REFERENCE_GRAVITY * _tracking_grip_utilization
	var tuning := _difficulty_tuning()
	var margin := float(tuning["corner_margin"])
	var corner := minf(maximum, sqrt(lateral_accel * radius) * margin * float(personality["corner_pace"]))
	var rack := DYNAMICS.calculate_target_steer_angle(1.0, vehicle.stats.max_steer_angle_deg, corner, maximum, vehicle.stats.high_speed_steer_ratio, vehicle.stats.steer_fade_start_ratio)
	var minimum_radius := vehicle.stats.wheelbase / maxf(tan(rack), 0.001)
	corner *= minf(1.0, radius / minimum_radius)
	var reaction_seconds := float(tuning["reaction_seconds"])
	var braking_distance := maxf(0.0, distance - vehicle.speed * reaction_seconds * float(personality["brake_timing"]))
	var braking_accel := DYNAMICS.get_effective_brake_accel(vehicle.stats, grip, _brake_prediction, _brake_prediction_loads)
	return minf(maximum, sqrt(corner * corner + 2.0 * braking_accel * braking_distance))


func _checkpoint_curvature_hazard(expected_index: int) -> Dictionary:
	var radius := _checkpoint_derived_radius(expected_index)
	if radius >= MAX_RACING_LINE_RADIUS:
		_hazard_result["radius"] = radius
		_hazard_result["distance"] = INF
		_hazard_result.erase("speed_limit")
		return _hazard_result
	# The corner apex is at the checkpoint itself (direction-independent); the
	# entry guide is forward-biased and would mis-measure the brake distance in
	# reverse. Braking to reach corner speed at the apex is correct either way.
	var checkpoint := _checkpoints_by_index.get(expected_index) as Node2D
	var corner_point: Vector2 = checkpoint.global_position if checkpoint != null else vehicle.global_position
	_hazard_result["radius"] = radius
	_hazard_result["distance"] = vehicle.global_position.distance_to(corner_point)
	_hazard_result.erase("speed_limit")
	return _hazard_result


func _checkpoint_derived_radius(checkpoint_index: int) -> float:
	## Conservative corner radius from checkpoint geometry: a sharp turn yields
	## a small radius and a straight yields the maximum radius, so a straight is
	## never mistaken for a hairpin.
	var theta := _checkpoint_turn_severity(checkpoint_index)
	if theta < 0.06:
		return MAX_RACING_LINE_RADIUS
	var checkpoint := _checkpoints_by_index.get(checkpoint_index) as Node2D
	var previous := race_manager.get_checkpoint_before(checkpoint_index) as Node2D
	var next := race_manager.get_checkpoint_after(checkpoint_index) as Node2D
	if checkpoint == null or previous == null or next == null:
		return MAX_RACING_LINE_RADIUS
	var segment := minf(
		previous.global_position.distance_to(checkpoint.global_position),
		checkpoint.global_position.distance_to(next.global_position),
	)
	var sin_half := sin(theta * 0.5)
	if sin_half < 0.001:
		return MAX_RACING_LINE_RADIUS
	return clampf(segment / (2.0 * sin_half), 0.0, MAX_RACING_LINE_RADIUS)
