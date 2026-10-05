extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")

const THEMES: Array[StringName] = [&"kitchen", &"workshop", &"office"]
const ROOMS: Array[StringName] = [&"classic", &"wide", &"tall", &"square"]
const SEEDS := [7919, 23757]


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var tracks := 0
	var patches := 0
	var technical := 0
	var obstacles := 0
	var debris := 0
	var debris_left := false
	var debris_right := false
	for theme in THEMES:
		for room in ROOMS:
			for seed: int in SEEDS:
				var label := "%s/%s/%d" % [theme, room, seed]
				var prepared := BUILDER.prepare_layout(theme, room, seed)
				if not _expect(not prepared.is_empty(), "%s should prepare" % label):
					return
				var centerline: PackedVector2Array = prepared["centerline"]
				var clearance := TrackCornerMap.clearances(centerline)
				for obstacle: Dictionary in (prepared["spec"] as Dictionary).get("obstacle_plan", []):
					var index := int(obstacle["centerline_index"])
					if not _expect(TrackCornerMap.is_calm(clearance, index, 0), "%s obstacle %s sits in or near a corner (%.0f from one)" % [label, obstacle.get("instance_id", "?"), clearance[index]]):
						return
					obstacles += 1
				var track := (BUILDER.build_packed(theme, room, seed)["scene"] as PackedScene).instantiate()
				for surface: Dictionary in track.get_meta("generated_surfaces", []):
					var role := StringName(surface["role"])
					if role == &"shortcut" or float(surface["grip"]) >= 1.0:
						continue
					var index := int(surface["centerline_index"])
					var half_span := TrackBuilderDressing.TECHNICAL_HALF_SPAN
					if role == &"patch" or role == &"debris":
						if not _expect(surface.has("half_span"), "%s %s must declare its actual span" % [label, role]):
							return
						half_span = int(surface["half_span"])
					if role == &"debris":
						# Corner water/debris: must sit on a corner, keep a
						# driveable line and never span the full corridor.
						if not _expect(not TrackCornerMap.is_calm(clearance, index, half_span), "%s debris at sample %d must sit on a corner" % [label, index]):
							return
						if not _expect(surface.has("half_width") and surface.has("lateral_mm"), "%s debris must declare its footprint" % label):
							return
						var halfw := float(surface["half_width"])
						var debris_lateral := float(surface["lateral_mm"])
						var driveable := BUILDER.HALF_WIDTH - (absf(debris_lateral) + halfw)
						if not _expect(driveable >= TrackBuilderDressing.GRIP_PATCH_EDGE_MARGIN - 0.1, "%s debris must leave a driveable line (%.1f wide)" % [label, driveable]):
							return
						debris_left = debris_left or debris_lateral < 0.0
						debris_right = debris_right or debris_lateral > 0.0
						debris += 1
						continue
					if not _expect(TrackCornerMap.is_calm(clearance, index, half_span), "%s %s surface at sample %d sits in or near a corner" % [label, role, index]):
						return
					patches += 1 if role == &"patch" else 0
					technical += 1 if role == &"technical" else 0
				track.free()
				tracks += 1
	if not _expect(patches >= tracks * 2, "calm stretches should still fit patches on most tracks (%d over %d tracks)" % [patches, tracks]):
		return
	if not _expect(debris_left and debris_right, "corner water/debris should appear on both sides across the corpus (left=%s right=%s)" % [debris_left, debris_right]):
		return
	print("TRACK_SURFACE_PLACEMENT_TEST PASS tracks=%d patches=%d technical=%d obstacles=%d debris=%d" % [tracks, patches, technical, obstacles, debris])
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_SURFACE_PLACEMENT_TEST FAIL: " + message)
	quit(1)
	return false
