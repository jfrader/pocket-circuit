class_name TrackLayoutSignatures
extends RefCounted


static func describe(route: Dictionary) -> Dictionary:
	var runs: Array[Dictionary] = []
	for primitive: Dictionary in route.get("primitives", []):
		var turn := float(primitive["signed_turn"])
		var hand := int(signf(turn))
		var radii: Array[float] = []
		if hand != 0:
			radii.append(float(primitive["radius"]))
		if not runs.is_empty() and int(runs.back()["hand"]) == hand:
			runs.back()["turn"] += absf(turn)
			(runs.back()["radii"] as Array).append_array(radii)
		else:
			runs.append({"hand": hand, "turn": absf(turn), "radii": radii})
	if runs.size() > 1 and runs.front()["hand"] == runs.back()["hand"]:
		var last: Dictionary = runs.pop_back()
		runs.front()["turn"] += float(last["turn"])
		var radii: Array = last["radii"]
		radii.append_array(runs.front()["radii"])
		runs.front()["radii"] = radii
	return {
		"structural": _canonical(runs, false),
		"profile": _canonical(runs, true),
		"semantic_count": runs.size(),
	}


static func _canonical(runs: Array[Dictionary], with_profile: bool) -> String:
	var best := ""
	for mirror: int in [1, -1]:
		for direction: int in [1, -1]:
			for start in runs.size():
				var tokens := PackedStringArray()
				for offset in runs.size():
					var run: Dictionary = runs[posmod(start + offset * direction, runs.size())]
					var hand := int(run["hand"]) * mirror * direction
					if hand == 0:
						tokens.append("S")
						continue
					var token := ("L" if hand > 0 else "R") + str(_angle_class(float(run["turn"])))
					if with_profile:
						var radii: Array = (run["radii"] as Array).duplicate()
						if direction < 0:
							radii.reverse()
						token += ":" + _profile(radii)
					tokens.append(token)
				var candidate := ".".join(tokens)
				if best.is_empty() or candidate < best:
					best = candidate
	return best


static func _angle_class(turn: float) -> int:
	if turn < PI / 3.0 - 0.000001:
		return 1
	if turn < 2.0 * PI / 3.0 - 0.000001:
		return 2
	return 3 if turn <= PI + 0.000001 else 4


static func _profile(radii: Array) -> String:
	var profiles := PackedStringArray()
	var increasing := false
	var decreasing := false
	for index in radii.size():
		var radius := float(radii[index])
		var profile := "tight" if radius < 260.0 else ("medium" if radius < 520.0 else "sweeper")
		if profiles.is_empty() or profiles[-1] != profile:
			profiles.append(profile)
		if index > 0:
			increasing = increasing or radius > float(radii[index - 1]) + 0.000001
			decreasing = decreasing or radius < float(radii[index - 1]) - 0.000001
	if increasing and not decreasing:
		return "opening"
	if decreasing and not increasing:
		return "tightening"
	return "+".join(profiles)
