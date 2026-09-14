extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const SEED_GEN := preload("res://scripts/race/track_seed_gen.gd")
const VEHICLE_SCENERY_MASK := 2 | 4 | 16
const MIN_POCKET_ROUTES := 3
# Keep earlier fixtures and include compound-corner layouts from every program.
const ORIGINAL_SEEDS: Array[int] = [0, 1, 3, 6]
const UNSAMPLED_SEEDS: Array[int] = [2, 5, 7, 8]
const FOLD_REGRESSION_SEEDS: Array[int] = [7, 9]


func _initialize() -> void:
	call_deferred("_run_test")


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("POCKET_SEAL_TEST FAIL: " + message)
		quit(1)
		return false
	return true


func _polygon_is_simple(points: PackedVector2Array) -> bool:
	if points.size() < 3:
		return false
	for first in points.size():
		var first_next := (first + 1) % points.size()
		for second in range(first + 1, points.size()):
			var second_next := (second + 1) % points.size()
			if first_next == second or second_next == first:
				continue
			if Geometry2D.segment_intersects_segment(points[first], points[first_next], points[second], points[second_next]) != null:
				return false
	return true


func _check_simple_contours(track: Node2D, seals: Node, label: String) -> bool:
	var barrier := track.get_node_or_null("InnerBarrier")
	if barrier != null:
		var island_col: PackedVector2Array = barrier.get_meta("collision_boundary_polygon", PackedVector2Array())
		if not _expect(_polygon_is_simple(island_col), "%s island collider must be a simple polygon" % label):
			return false
	for body: Node in seals.get_children():
		var seal_label := "%s seal[%d]" % [label, int(body.get_meta("pocket_index", -1))]
		var pad := body.get_node_or_null("RaisedPad") as Polygon2D
		if pad != null and not _expect(_polygon_is_simple(pad.polygon), "%s raised pad must be a simple polygon" % seal_label):
			return false
		var col: PackedVector2Array = body.get_meta("collision_boundary_polygon", PackedVector2Array())
		if not _expect(_polygon_is_simple(col), "%s collider must be a simple polygon" % seal_label):
			return false
	return true


func _ray_hits_pad(space: PhysicsDirectSpaceState2D, seals: Node, unrelated: Array[RID], from: Vector2, to: Vector2) -> bool:
	# A bay must be cut-proof in both directions: forward and reverse traversal
	# approach the same mouth from opposite chord ends.
	for endpoints: Array in [[from, to], [to, from]]:
		var query := PhysicsRayQueryParameters2D.create(endpoints[0], endpoints[1], VEHICLE_SCENERY_MASK)
		query.exclude = unrelated
		query.hit_from_inside = true
		var hit := space.intersect_ray(query)
		if hit.is_empty() or not seals.is_ancestor_of(hit["collider"]):
			return false
	return true


func _run_test() -> void:
	var bay := PackedVector2Array([Vector2(-1200, -750), Vector2(-400, -750), Vector2(-400, 300), Vector2(400, 300), Vector2(400, -750), Vector2(1200, -750), Vector2(1200, 750), Vector2(-1200, 750)])
	var dense_bay := PackedVector2Array()
	for index in bay.size():
		for step in 16:
			dense_bay.append(bay[index].lerp(bay[(index + 1) % bay.size()], float(step) / 16.0))
	var sparse_pockets := SEED_GEN._detect_pockets(bay)
	for offset in [0, 35, 70]:
		var reordered := PackedVector2Array()
		for index in dense_bay.size():
			reordered.append(dense_bay[(index + offset) % dense_bay.size()])
		var detected := SEED_GEN._detect_pockets(reordered)
		if not _expect(sparse_pockets.size() == 1 and detected.size() == 1 and is_equal_approx(float(detected[0]["depth"]), float(sparse_pockets[0]["depth"])), "densifying or reordering straight samples must preserve the whole deep bay"):
			return
	var dense_circle := PackedVector2Array()
	for i in 256:
		dense_circle.append(Vector2.from_angle(TAU * float(i) / 256.0) * 180.0)
	var simplified := TrackBuilderGeometry.simplify_loop(dense_circle)
	if not _expect(simplified.size() >= 8 and _polygon_is_simple(simplified), "simplification must not erase a densely sampled arc"):
		return
	for point: Vector2 in dense_circle:
		var distance := INF
		for i in simplified.size():
			distance = minf(distance, SEED_GEN._point_segment_distance(point, simplified[i], simplified[(i + 1) % simplified.size()]))
		if not _expect(distance <= 0.051, "simplified boundaries must remain within their 0.05u error budget"):
			return
	var routes := 0
	var deep_bays := 0
	var themes := [&"kitchen", &"workshop", &"office"]
	var seeds: Array[int] = []
	seeds.append_array(ORIGINAL_SEEDS)
	seeds.append_array(UNSAMPLED_SEEDS)
	var unsampled_exercised := {}
	for theme: StringName in themes:
		var theme_deep_bays := 0
		unsampled_exercised[theme] = false
		var programs := {}
		for seed in seeds:
			var prepared: Dictionary = BUILDER.prepare_layout(theme, &"classic", seed)
			if prepared.is_empty():
				continue
			var pockets: Array = prepared["spec"].get("pockets", [])
			if pockets.is_empty():
				continue
			print("pocket route %s seed %d" % [theme, seed])
			programs[prepared["spec"]["route_program"]] = true
			routes += 1
			var built: Dictionary = BUILDER.build_packed(theme, &"classic", seed)
			if not _expect(built.get("scene") is PackedScene, "%s seed %d should build" % [theme, seed]):
				return
			var track := (built["scene"] as PackedScene).instantiate() as Node2D
			root.add_child(track)
			await physics_frame
			await physics_frame
			var space := track.get_world_2d().direct_space_state
			var seals := track.get_node_or_null("PocketSeals")
			if not _expect(seals != null, "declared bays must be processed for physical pads"):
				return
			var unrelated: Array[RID] = []
			var centerline: PackedVector2Array = prepared["centerline"]
			for body: CollisionObject2D in track.find_children("*", "CollisionObject2D", true, false):
				if not seals.is_ancestor_of(body):
					unrelated.append(body.get_rid())
			for pocket: Dictionary in pockets:
				var from: Vector2 = pocket.get("from", Vector2.ZERO)
				var to: Vector2 = pocket.get("to", Vector2.ZERO)
				var side: Vector2 = pocket["side"]
				var deepest: Vector2 = pocket.get("deepest", from.lerp(to, 0.5) + side * float(pocket["depth"]))
				var tested_depths := 0
				# Cross the mouth AND the deep interior. Hitting arbitrary furniture
				# once at the mouth is not evidence that the bay cannot be cut.
				for fraction: float in [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75]:
					var ray_from := from.lerp(deepest, fraction)
					var ray_to := to.lerp(deepest, fraction)
					# A tapering bay ends in the driving apron. Only free floor beyond
					# that apron must be solid; filling the apron would block the car.
					var midpoint := ray_from.lerp(ray_to, 0.5)
					if BUILDER._distance_to_centerline(midpoint, centerline) < 210.0:
						continue
					tested_depths += 1
					if not _expect(_ray_hits_pad(space, seals, unrelated, ray_from, ray_to), "%s seed %d bay at depth %.2f must hit its solid pad in both traversal directions, not unrelated scenery" % [theme, seed, fraction]):
						return
				# Shallow excursions may lie wholly in the driving apron. Require
				# real deep coverage below, not walls inside that apron.
				if tested_depths >= 2:
					deep_bays += 1
					theme_deep_bays += 1
			for index in centerline.size():
				var tangent := centerline[posmod(index - 1, centerline.size())].direction_to(centerline[(index + 1) % centerline.size()])
				for lateral: float in [-100.0, 0.0, 100.0]:
					var point := centerline[index] + tangent.orthogonal() * lateral
					for body: Node in seals.get_children():
						if not _expect(not Geometry2D.is_point_in_polygon(point, body.get_meta("collision_boundary_polygon")), "%s seed %d pad must not intrude into racing width" % [theme, seed]):
							return
			if not _check_simple_contours(track, seals, "%s seed %d" % [theme, seed]):
				return
			track.queue_free()
			await physics_frame
			if seed in UNSAMPLED_SEEDS:
				unsampled_exercised[theme] = true
		for program: StringName in [&"infield", &"switchback", &"dogleg", &"harbour"]:
			if not _expect(programs.has(program), "%s physical coverage must exercise %s layouts" % [theme, program]):
				return
		if not _expect(theme_deep_bays > 0, "%s must exercise a traversable deep bay at multiple depths" % theme):
			return
	if not _expect(routes >= MIN_POCKET_ROUTES, "deep bays should declare pockets on at least %d routes (got %d)" % [MIN_POCKET_ROUTES, routes]):
		return
	if not _expect(deep_bays >= MIN_POCKET_ROUTES, "must exercise multiple deep bays, not pass by skipping every probe"):
		return
	for theme: StringName in themes:
		if not _expect(bool(unsampled_exercised[theme]), "%s should exercise at least one unsampled seed (%s)" % [theme, UNSAMPLED_SEEDS]):
			return
	for seed in FOLD_REGRESSION_SEEDS:
		var built: Dictionary = BUILDER.build_packed(&"kitchen", &"classic", seed)
		if not _expect(built.get("scene") is PackedScene, "kitchen seed %d should build for the fold regression" % seed):
			return
		var track := (built["scene"] as PackedScene).instantiate() as Node2D
		root.add_child(track)
		await physics_frame
		await physics_frame
		var seals := track.get_node_or_null("PocketSeals")
		if seals == null or seals.get_child_count() == 0:
			track.queue_free()
			await physics_frame
			continue
		if not _check_simple_contours(track, seals, "kitchen seed %d" % seed):
			return
		track.queue_free()
		await physics_frame
	var unsampled_labels: Array[String] = []
	for seed: int in UNSAMPLED_SEEDS:
		unsampled_labels.append(str(seed))
	var fold_labels: Array[String] = []
	for seed: int in FOLD_REGRESSION_SEEDS:
		fold_labels.append(str(seed))
	print("POCKET_SEAL_TEST PASS pocket_routes=%d unsampled=[%s] fold_seeds=[%s]" % [routes, ", ".join(unsampled_labels), ", ".join(fold_labels)])
	quit(0)
