class_name CircuitRoster
extends RefCounted

const CLASSIC_SEEDS: Array[int] = [16, 28, 88, 92, 96, 104, 13, 29, 53, 93, 129, 137, 6, 58, 118, 83]
const WIDE_SEEDS: Array[int] = [0, 5, 10, 13, 16]
const TALL_SEEDS: Array[int] = [6, 16, 72, 78, 128]
const ROOM_CIRCUITS: Dictionary = {
	"classic": CLASSIC_SEEDS,
	"wide": WIDE_SEEDS,
	"tall": TALL_SEEDS,
}


static func scene_path(theme: StringName, room: StringName, seed: int) -> String:
	if room == &"classic":
		return "res://scenes/tracks/circuits/%s_seed_%d.tscn" % [String(theme), seed]
	return "res://scenes/tracks/circuits/%s_%s_seed_%d.tscn" % [String(theme), String(room), seed]


static func entries() -> Array:
	var circuit_entries: Array = []
	for theme: String in [&"workshop", &"office"]:
		for room: String in ROOM_CIRCUITS:
			var seeds: Array = ROOM_CIRCUITS[room]
			for seed_index in seeds.size():
				circuit_entries.append({
					"theme": theme,
					"room": room,
					"seed": int(seeds[seed_index]),
					"label": "%s %s Circuit %02d" % [theme.capitalize(), room.capitalize(), seed_index + 1],
				})
	return circuit_entries
