extends SceneTree

## Continuous circle clearance is necessary for a car to fit. The actual capsule
## adds a fixed-heading check; neither test certifies an unrestricted driving line.
const CORE := preload("res://scripts/race/track_builder_core.gd")
const IDS := preload("res://scripts/race/generated_circuit_identity.gd")
const RUSTBUG := preload("res://scenes/vehicles/rustbug.tscn")
const CASES := {"kitchen": [0, 1, 4, 5, 7, 8, 10, 11], "workshop": [0, 1, 2, 4, 5, 11, 13, 20], "office": [0, 1, 3, 5, 6, 8, 14, 23]}
const SECTOR_COUNT := WorldEnvironmentPlan.SECTOR_COUNT
const CHORD_SAMPLES := CORE.CUT_SAMPLES
const TURN_THRESHOLD := CORE.CUT_TURN_THRESHOLD
const MIN_LOOKAHEAD := CORE.CUT_MIN_LOOKAHEAD
const MAX_LOOKAHEAD := CORE.CUT_MAX_LOOKAHEAD
const FOLD_MAX_SPACING_MM := CORE.CUT_FOLD_MAX_SPACING_MM
const FOLD_MIN_LAP_FRACTION := CORE.CUT_FOLD_MIN_LAP_FRACTION

var _viewport: SubViewport
var _space: PhysicsDirectSpaceState2D
var _query: PhysicsShapeQueryParameters2D
var _circle: CircleShape2D
var _capsule: CapsuleShape2D
var _vehicle_local: Transform2D
var _vehicle_mask: int
var _query_failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _load_vehicle():
		_finish(false)
		return
	_viewport = SubViewport.new()
	_viewport.world_2d = World2D.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	get_root().add_child(_viewport)
	_query = PhysicsShapeQueryParameters2D.new()
	_query.collision_mask = _vehicle_mask
	_query.collide_with_bodies = true
	_query.collide_with_areas = false
	_query.margin = 0.0
	if not await _physics_atomics():
		_finish(false)
		return
	var selected := _selected_cases()
	if selected.is_empty():
		_finish(false)
		return
	var checked := 0
	for theme: String in CASES:
		for seed_value: int in CASES[theme]:
			if not selected.has("%s/%d" % [theme, seed_value]):
				continue
			var identity := IDS.create(StringName(theme), IDS.room_for_route_seed(seed_value), seed_value)
			var room := StringName(identity["room"])
			var options: Dictionary = IDS.generation_options(identity)
			var prepared: Dictionary = CORE.prepare_layout(StringName(theme), room, seed_value, options)
			if not _check(not prepared.is_empty(), "prepare_layout %s/%d" % [theme, seed_value]):
				_finish(false)
				return
			var centerline: PackedVector2Array = prepared["centerline"]
			var spec: Dictionary = prepared["spec"]
			var environment: Dictionary = spec.get("environment_plan", {})
			var diagnostics: Dictionary = environment.get("diagnostics", {})
			var open_sector := int(diagnostics.get("open_sector", -1))
			var exit: PackedVector2Array = diagnostics.get("open_exit", PackedVector2Array())
			var built: Dictionary = CORE.build_packed(StringName(theme), room, seed_value, options)
			var packed: PackedScene = built.get("scene", null)
			if not _check(packed != null, "build_packed %s/%d" % [theme, seed_value]):
				_finish(false)
				return
			var track := packed.instantiate() as Node2D
			if not _check(track != null, "instantiate %s/%d" % [theme, seed_value]):
				_finish(false)
				return
			_viewport.add_child(track)
			if not await _sync_space():
				track.free()
				_finish(false)
				return
			var solids := _active_solid_shapes(track)
			var island := track.get_node_or_null("InnerBarrier/BoundaryCollision") as CollisionShape2D
			var island_only: Array[CollisionShape2D] = []
			if island != null:
				island_only.append(island)
			if not _check(not solids.is_empty() and _probe_registered_solid(solids) and solids.has(island) and _probe_registered_solid(island_only), "registered car-masked island and colliders %s/%d" % [theme, seed_value]):
				track.free()
				_finish(false)
				return
			var case_ok := _check(exit.size() == 2 and open_sector >= 0 and open_sector < SECTOR_COUNT, "reserved open exit %s/%d" % [theme, seed_value])
			if case_ok:
				var exit_a: Vector2 = track.global_transform * exit[0]
				var exit_b: Vector2 = track.global_transform * exit[1]
				case_ok = _check(not _hits_solid(exit_a, exit_b, _circle) and not _hits_solid(exit_a, exit_b, _capsule) and not _query_failed, "reserved open exit must remain physically clear %s/%d" % [theme, seed_value])
			if case_ok:
				var n := centerline.size()
				var prefix := PackedFloat64Array([0.0])
				var normals := PackedVector2Array()
				var outward := -1.0 if CORE._polygon_area(centerline) > 0.0 else 1.0
				for index in n:
					prefix.append(prefix[index] + centerline[index].distance_to(centerline[(index + 1) % n]))
					normals.append(CORE._sample_tangent(centerline, index).rotated(PI * 0.5) * outward)
				var offsets := PackedFloat32Array([0.0, (CORE.HALF_WIDTH - _capsule.radius) * 0.5, CORE.HALF_WIDTH - _capsule.radius])
				for pair: Vector2i in _candidate_pairs(centerline):
					var span := CORE._cyclic_index_distance(pair.x, pair.y, n)
					if not _check((pair.x + span) % n == pair.y, "predicate and sweep must use the same directed endpoints %s/%d" % [theme, seed_value]):
						case_ok = false
						break
					var arc := float(prefix[pair.y] - prefix[pair.x]) if pair.y >= pair.x else float(prefix[n] - prefix[pair.x] + prefix[pair.y])
					for from_offset: float in offsets:
						for to_offset: float in offsets:
							var a_local := centerline[pair.x] + normals[pair.x] * from_offset
							var b_local := centerline[pair.y] + normals[pair.y] * to_offset
							var chord := a_local.distance_to(b_local)
							if arc - chord < CORE.CUT_MIN_SAVED_MM or arc < chord * CORE.CUT_MIN_ARC_RATIO:
								continue
							var a := track.global_transform * a_local
							var b := track.global_transform * b_local
							var circle_hit := _hits_solid(a, b, _circle)
							if _query_failed:
								case_ok = false
								break
							if circle_hit:
								continue
							var excursion := _pose_excursion(a_local, b_local, centerline, open_sector)
							if int(excursion["deep"]) < CORE.CUT_MIN_DEEP_SAMPLES or bool(excursion["open"]):
								continue
							var capsule_hit := _hits_solid(a, b, _capsule)
							if _query_failed:
								case_ok = false
								break
							if capsule_hit:
								continue
							push_error("OUTER_CUT_BLOCK_TEST FAIL: circle- and fixed-heading-capsule-clear outside chord %s/%d start=%d end=%d offsets=%.1f/%.1f saved_mm=%.0f deep=%d/%d" % [theme, seed_value, pair.x, pair.y, from_offset, to_offset, arc - chord, int(excursion["deep"]), CHORD_SAMPLES])
							case_ok = false
							break
						if not case_ok:
							break
					if not case_ok:
						break
			track.free()
			if not case_ok:
				_finish(false)
				return
			checked += 1
			print("CUT_SCAN_CASE %s/%d PASS" % [theme, seed_value])
			await process_frame
	if not _check(checked == selected.size(), "completed %d/%d requested cases" % [checked, selected.size()]):
		_finish(false)
		return
	print("OUTER_CUT_BLOCK_TEST PASS completed_cases=%d lane_combinations=9 fixed_heading_capsule" % checked)
	_finish(true)


func _load_vehicle() -> bool:
	var car := RUSTBUG.instantiate() as RigidBody2D
	if not _check(car != null, "Rustbug scene must instantiate"):
		return false
	var collision := car.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var ok := _check(collision != null and collision.shape is CapsuleShape2D and not collision.disabled, "Rustbug must have an enabled collision capsule")
	if ok:
		_capsule = collision.shape as CapsuleShape2D
		_vehicle_local = collision.transform
		_vehicle_mask = car.collision_mask
		_circle = CircleShape2D.new()
		_circle.radius = _capsule.radius
		ok = _check(_vehicle_mask != 0 and _capsule.height > _capsule.radius * 2.0, "Rustbug must have a longer-than-wide capsule and solid mask")
	car.free()
	return ok


func _selected_cases() -> Dictionary:
	var selected := {}
	for theme: String in CASES:
		for seed_value: int in CASES[theme]:
			selected["%s/%d" % [theme, seed_value]] = true
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return selected
	if not _check(args.size() == 2 and args[0] == "--case", "usage: -- --case theme/seed"):
		return {}
	var key := String(args[1])
	if not _check(selected.has(key), "unknown case %s" % key):
		return {}
	return {key: true}


func _pose_excursion(a: Vector2, b: Vector2, centerline: PackedVector2Array, sector: int) -> Dictionary:
	var sectors := PackedInt32Array()
	var n := centerline.size()
	for sample in CHORD_SAMPLES:
		var point := a.lerp(b, float(sample) / float(CHORD_SAMPLES - 1))
		var near: Dictionary = CORE._closest_point_on_loop(point, centerline)
		if point.distance_to(near["position"]) <= CORE.HALF_WIDTH + CORE.CUT_MIN_OFF_CORRIDOR_MM:
			continue
		var index := int(near.get("index", -1))
		if index < 0:
			return {"deep": 0, "open": false}
		sectors.append(mini(SECTOR_COUNT - 1, int(float(index) / float(n) * float(SECTOR_COUNT))))
	return {"deep": sectors.size(), "open": _all_deep_sectors_open(sectors, sector)}


func _all_deep_sectors_open(deep_sectors: PackedInt32Array, open_sector: int) -> bool:
	if deep_sectors.size() < CORE.CUT_MIN_DEEP_SAMPLES:
		return false
	for sector in deep_sectors:
		if sector != open_sector:
			return false
	return true


func _candidate_pairs(centerline: PackedVector2Array) -> Array[Vector2i]:
	var pairs: Array[Vector2i] = []
	var n := centerline.size()
	var seen := {}
	for i in n:
		if CORE._turn_strength(centerline, i, 6) < TURN_THRESHOLD:
			continue
		for span in range(MIN_LOOKAHEAD, MAX_LOOKAHEAD + 1):
			var j := (i + span) % n
			var key := mini(i, j) * n + maxi(i, j)
			if seen.has(key):
				continue
			seen[key] = true
			pairs.append(Vector2i(i, j))
	var buckets := {}
	for index in n:
		var key := Vector2i(floori(centerline[index].x / FOLD_MAX_SPACING_MM), floori(centerline[index].y / FOLD_MAX_SPACING_MM))
		if not buckets.has(key):
			buckets[key] = PackedInt32Array()
		buckets[key].append(index)
	var minimum_skip := int(float(n) * FOLD_MIN_LAP_FRACTION)
	for index in n:
		var key := Vector2i(floori(centerline[index].x / FOLD_MAX_SPACING_MM), floori(centerline[index].y / FOLD_MAX_SPACING_MM))
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				var neighbour := key + Vector2i(dx, dy)
				if not buckets.has(neighbour):
					continue
				for other: int in buckets[neighbour]:
					if other == index or CORE._cyclic_index_distance(index, other, n) < minimum_skip or centerline[index].distance_to(centerline[other]) > FOLD_MAX_SPACING_MM:
						continue
					var first := mini(index, other)
					var second := maxi(index, other)
					var pair_key := first * n + second
					if seen.has(pair_key):
						continue
					seen[pair_key] = true
					var forward_span := posmod(other - index, n)
					var start := index if forward_span <= float(n) * 0.5 else other
					var end := other if start == index else index
					pairs.append(Vector2i(start, end))
	return pairs


func _hits_solid(a: Vector2, b: Vector2, shape: Shape2D) -> bool:
	_query.shape = shape
	var heading := (b - a).angle() + PI * 0.5
	_query.transform = Transform2D(heading, a) * _vehicle_local
	_query.motion = Vector2.ZERO
	if not _space.intersect_shape(_query, 1).is_empty():
		return true
	_query.motion = b - a
	var fractions: PackedFloat32Array = _space.cast_motion(_query)
	if fractions.size() != 2:
		_query_failed = true
		push_error("OUTER_CUT_BLOCK_TEST FAIL: cast_motion returned %d fractions" % fractions.size())
		return true
	if fractions[1] < 1.0:
		return true
	_query.motion = Vector2.ZERO
	_query.transform = Transform2D(heading, b) * _vehicle_local
	return not _space.intersect_shape(_query, 1).is_empty()


func _active_solid_shapes(track: Node2D) -> Array[CollisionShape2D]:
	var shapes: Array[CollisionShape2D] = []
	for node in track.find_children("*", "CollisionShape2D", true, false):
		var collision := node as CollisionShape2D
		var body := collision.get_parent() as StaticBody2D
		if body != null and (body.collision_layer & _vehicle_mask) != 0 and not collision.disabled and collision.shape != null:
			shapes.append(collision)
	return shapes


func _probe_registered_solid(shapes: Array[CollisionShape2D]) -> bool:
	_query.shape = _circle
	for collision in shapes:
		var point := Vector2.ZERO
		if collision.shape is ConvexPolygonShape2D:
			var points := (collision.shape as ConvexPolygonShape2D).points
			if points.is_empty():
				continue
			point = points[0]
		elif collision.shape is ConcavePolygonShape2D:
			var segments := (collision.shape as ConcavePolygonShape2D).segments
			if segments.is_empty():
				continue
			point = segments[0]
		elif not (collision.shape is CircleShape2D or collision.shape is RectangleShape2D or collision.shape is CapsuleShape2D):
			continue
		_query.transform = Transform2D(0.0, collision.global_transform * point)
		_query.motion = Vector2.ZERO
		var body := collision.get_parent() as StaticBody2D
		for hit in _space.intersect_shape(_query):
			if hit.get("rid") == body.get_rid():
				return true
	return false


func _fixture(shape: Shape2D, position: Vector2, parent: Node2D, layer: int, disabled: bool = false) -> CollisionShape2D:
	var body := StaticBody2D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	parent.add_child(body)
	body.position = position
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.disabled = disabled
	body.add_child(collision)
	return collision


func _sync_space() -> bool:
	await physics_frame
	await process_frame
	_space = _viewport.world_2d.direct_space_state
	return _check(_space != null, "isolated World2D/direct_space_state unavailable")


func _physics_atomics() -> bool:
	if not _check(CORE.CUT_MIN_OFF_CORRIDOR_MM == 40.0 and CORE.CUT_MIN_DEEP_SAMPLES == 3 and CORE.CUT_MIN_SAVED_MM == 50.0 and CORE.CUT_MIN_ARC_RATIO == 1.25 and CHORD_SAMPLES == 41, "cut contract changed"):
		return false
	if not _check(_all_deep_sectors_open(PackedInt32Array([3, 3, 3]), 3) and not _all_deep_sectors_open(PackedInt32Array([3, 2, 3]), 3) and not _all_deep_sectors_open(PackedInt32Array([3, 3]), 3), "mixed or too-short deep excursion cannot inherit the open-sector exemption"):
		return false
	var straight := PackedVector2Array()
	for step in 200:
		straight.append(Vector2(step * 10.0, 0.0))
	if not _check(not bool(CORE.exploitable_cut(straight, 0, 20)["exploitable"]), "straight must not be a cut"):
		return false
	var anchor_identity := IDS.create(&"kitchen", IDS.room_for_route_seed(7), 7)
	var anchor: Dictionary = CORE.prepare_layout(&"kitchen", StringName(anchor_identity["room"]), 7, IDS.generation_options(anchor_identity))
	var anchor_line: PackedVector2Array = anchor["centerline"]
	if not _check(bool(CORE.exploitable_cut(anchor_line, 223, 22)["exploitable"]) and not bool(CORE.exploitable_cut(anchor_line, 223, 2)["exploitable"]), "known cut versus short hop"):
		return false
	for pair: Vector2i in _candidate_pairs(anchor_line):
		var span := CORE._cyclic_index_distance(pair.x, pair.y, anchor_line.size())
		if not _check((pair.x + span) % anchor_line.size() == pair.y, "fold/turn chord direction must agree with predicate"):
			return false
	var root := Node2D.new()
	_viewport.add_child(root)
	var ancestor := Node2D.new()
	root.add_child(ancestor)
	ancestor.position = Vector2(240.0, 160.0)
	ancestor.rotation = PI / 4.0
	ancestor.scale = Vector2.ONE * 1.5
	var nested := Node2D.new()
	ancestor.add_child(nested)
	nested.position = Vector2(30.0, -10.0)
	nested.rotation = PI / 3.0
	var disc := CircleShape2D.new()
	disc.radius = 10.0
	var nested_collision := _fixture(disc, Vector2(12.0, 0.0), nested, _vehicle_mask)
	var obstacle := CapsuleShape2D.new()
	obstacle.radius = 10.0
	obstacle.height = 100.0
	_fixture(obstacle, Vector2(700.0, 0.0), root, _vehicle_mask)
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(20.0, 20.0)
	_fixture(rectangle, Vector2(1000.0, 0.0), root, _vehicle_mask)
	var tip_disc := CircleShape2D.new()
	tip_disc.radius = 8.0
	_fixture(tip_disc, Vector2(32.0, 0.0), root, _vehicle_mask)
	var disabled_disc := CircleShape2D.new()
	disabled_disc.radius = 100.0
	_fixture(disabled_disc, Vector2(1300.0, 0.0), root, _vehicle_mask, true)
	var excluded_disc := CircleShape2D.new()
	excluded_disc.radius = 100.0
	_fixture(excluded_disc, Vector2(1600.0, 0.0), root, 1)
	var area := Area2D.new()
	area.collision_layer = _vehicle_mask
	root.add_child(area)
	area.position = Vector2(1900.0, 0.0)
	var area_collision := CollisionShape2D.new()
	var area_disc := CircleShape2D.new()
	area_disc.radius = 100.0
	area_collision.shape = area_disc
	area.add_child(area_collision)
	if not await _sync_space():
		root.free()
		return false
	var active := _active_solid_shapes(root)
	var center := nested_collision.global_transform.origin
	var ok := _check(active.size() == 4 and _probe_registered_solid(active), "registered solids exclude disabled shapes, other layers and areas")
	ok = _check(_hits_solid(center + Vector2.LEFT, center + Vector2.RIGHT, _circle), "nested rotated/scaled collision must hit") and ok
	ok = _check(not _hits_solid(Vector2(-1.0, 0.0), Vector2(1.0, 0.0), _circle), "ancestor origin must not hit") and ok
	ok = _check(_hits_solid(Vector2(700.0, 0.0), Vector2(850.0, 0.0), _circle), "starting overlap must hit") and ok
	ok = _check(_hits_solid(Vector2(695.0, 60.0), Vector2(705.0, 60.0), _circle), "continuous sweep against capsule must hit") and ok
	ok = _check(not _hits_solid(Vector2(695.0, 69.0), Vector2(705.0, 69.0), _circle), "capsule beyond clearance must not hit") and ok
	ok = _check(not _hits_solid(Vector2(1025.0, 25.0), Vector2(1026.0, 25.0), _circle), "rounded rectangle corner must clear") and ok
	ok = _check(_hits_solid(Vector2(1020.0, 20.0), Vector2(1021.0, 20.0), _circle), "rectangle edge must hit") and ok
	ok = _check(not _hits_solid(Vector2(-20.0, 0.0), Vector2.ZERO, _circle) and _hits_solid(Vector2(-20.0, 0.0), Vector2.ZERO, _capsule), "circle-clear chord must still detect Rustbug capsule tip collision") and ok
	ok = _check(not _hits_solid(Vector2(1290.0, 0.0), Vector2(1310.0, 0.0), _circle), "disabled shape ignored") and ok
	ok = _check(not _hits_solid(Vector2(1590.0, 0.0), Vector2(1610.0, 0.0), _circle), "other layer ignored") and ok
	ok = _check(not _hits_solid(Vector2(1890.0, 0.0), Vector2(1910.0, 0.0), _circle), "area ignored") and ok
	ok = _check(not _query_failed, "physics queries valid") and ok
	root.free()
	if not await _sync_space():
		return false
	return _check(not _hits_solid(Vector2(695.0, 60.0), Vector2(705.0, 60.0), _circle), "freed fixtures removed from isolated space") and ok


func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("OUTER_CUT_BLOCK_TEST FAIL: " + message)
	return false


func _finish(success: bool) -> void:
	_space = null
	_query = null
	if _viewport != null:
		_viewport.free()
		_viewport = null
	quit(0 if success else 1)
