extends SceneTree

const PROFILES := preload("res://scripts/audio/sfx/tyre_surface_profiles.gd")
const CATALOG := preload("res://scripts/race/track_builder_catalog.gd")


func _initialize() -> void:
	var errors := PackedStringArray()
	var base_ids := {}
	for surface_name: StringName in [&"polished counter", &"workbench", &"desktop"]:
		var profile: Dictionary = PROFILES.profile_for(surface_name)
		base_ids[profile["id"]] = true
	if base_ids.size() != 3:
		errors.append("the three room base surfaces must have distinct acoustic profiles: %s" % base_ids)

	var surfaces: Array[StringName] = [
		&"polished counter", &"workbench", &"desktop",
		&"wet spill", &"polish strip", &"oil slick", &"sawdust", &"spark strip",
		&"loose paper", &"keyboard", &"mail shoot",
	]
	for compositions: Array in CATALOG.ROOM_COMPOSITIONS.values():
		for composition: Dictionary in compositions:
			for surface: Dictionary in composition["surfaces"]:
				surfaces.append(surface["name"])
	for layout: Dictionary in CATALOG.LAYOUTS.values():
		for surface: Dictionary in layout["grip_patches"]:
			surfaces.append(surface["name"])
	for surface_name: StringName in surfaces:
		var profile: Dictionary = PROFILES.profile_for(surface_name)
		if profile["id"] == PROFILES.DEFAULT_ID:
			errors.append("defined surface %s fell through to the default profile" % surface_name)
		for parameter: String in ["filter_tilt", "squeal", "rumble", "rattle"]:
			if not profile.has(parameter):
				errors.append("surface %s profile is missing %s" % [surface_name, parameter])

	var fallback: Dictionary = PROFILES.profile_for(&"future unknown material")
	if fallback["id"] != PROFILES.DEFAULT_ID:
		errors.append("unknown surfaces must use the sane neutral default")
	if errors.is_empty():
		print("TYRE_SURFACE_PROFILE_TEST PASS surfaces=%d profiles=%d" % [surfaces.size(), base_ids.size()])
		quit(0)
		return
	for error in errors:
		push_error("TYRE_SURFACE_PROFILE_TEST FAIL: " + error)
	quit(1)
