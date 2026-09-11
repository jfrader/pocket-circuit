extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")
const SEED_GEN := preload("res://scripts/race/track_seed_gen.gd")
const VEHICLE_SCENERY_MASK := 2 | 4 | 16
const MIN_POCKET_ROUTES := 3


func _initialize() -> void:
	call_deferred("_run_test")


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("POCKET_SEAL_TEST FAIL: " + message)
		quit(1)
	return true


func _run_test() -> void:
	var sealed := 0
	var routes := 0
	var themes := [&"kitchen", &"workshop", &"office"]
	for theme: StringName in themes:
		for seed in 120:
			var prepared: Dictionary = BUILDER.prepare_layout(theme, &"classic", seed)
			if prepared.is_empty():
				continue
			var pockets: Array = prepared["spec"].get("pockets", [])
			if pockets.is_empty():
				continue
			print("pocket route %s seed %d" % [theme, seed])
			routes += 1
			var built: Dictionary = BUILDER.build_packed(theme, &"classic", seed)
			if not _expect(built.get("scene") is PackedScene, "%s seed %d should build" % [theme, seed]):
				return
			var track := (built["scene"] as PackedScene).instantiate() as Node2D
			root.add_child(track)
			await physics_frame
			await physics_frame
			var space := track.get_world_2d().direct_space_state
			for pocket: Dictionary in pockets:
				var from: Vector2 = pocket.get("from", Vector2.ZERO)
				var to: Vector2 = pocket.get("to", Vector2.ZERO)
				var direction := (to - from).normalized()
				# The mouth must be solidly blocked: raycast across the chord.
				var blocked := false
				for fraction: float in [0.2, 0.5, 0.8]:
					var origin := from.lerp(to, fraction) - direction.rotated(PI * 0.5) * 260.0
					var query := PhysicsRayQueryParameters2D.create(origin, origin + direction.rotated(PI * 0.5) * 520.0, VEHICLE_SCENERY_MASK)
					if not space.intersect_ray(query).is_empty():
						blocked = true
						break
				if not _expect(blocked, "%s seed %d pocket mouth should be solidly sealed" % [theme, seed]):
					return
			track.queue_free()
			await physics_frame
			sealed += 1
			if routes >= 12:
				break
		if routes >= 12:
			break
	_expect(routes >= MIN_POCKET_ROUTES, "deep bays should declare pockets on at least %d routes (got %d)" % [MIN_POCKET_ROUTES, routes])
	print("POCKET_SEAL_TEST PASS pocket_routes=%d" % routes)
	quit(0)
