extends SceneTree

const BUILDER := preload("res://scripts/race/track_builder_core.gd")

const THEMES: Array[StringName] = [&"kitchen", &"workshop", &"office"]
const ROOMS: Array[StringName] = [&"classic", &"wide", &"tall", &"square"]
const SEEDS := [7919, 23757]
## Surface strips reach this many samples each side of their centre.
const SPAN_BY_ROLE := {&"technical": TrackBuilderDressing.TECHNICAL_HALF_SPAN, &"patch": TrackBuilderDressing.GRIP_PATCH_HALF_SPAN}


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var tracks := 0
	var patches := 0
	var technical := 0
	var obstacles := 0
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
					if not _expect(TrackCornerMap.is_calm(clearance, index, int(SPAN_BY_ROLE[role])), "%s %s surface at sample %d sits in or near a corner" % [label, role, index]):
						return
					patches += 1 if role == &"patch" else 0
					technical += 1 if role == &"technical" else 0
				track.free()
				tracks += 1
	if not _expect(patches >= tracks * 2, "calm stretches should still fit patches on most tracks (%d over %d tracks)" % [patches, tracks]):
		return
	print("TRACK_SURFACE_PLACEMENT_TEST PASS tracks=%d patches=%d technical=%d obstacles=%d" % [tracks, patches, technical, obstacles])
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("TRACK_SURFACE_PLACEMENT_TEST FAIL: " + message)
	quit(1)
	return false
