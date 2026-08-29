class_name CircuitRoster
extends RefCounted

const CIRCUIT_SEEDS: Dictionary = {
	"workshop": [0, 4, 6, 10, 25, 29, 31, 33, 35, 43, 46, 49, 51, 53],
	"office": [0, 4, 6, 10, 25, 29, 31, 33, 35, 43, 46, 49, 51, 53],
}


static func scene_path(theme: StringName, seed: int) -> String:
	return "res://scenes/tracks/circuits/%s_seed_%d.tscn" % [String(theme), seed]


static func entries() -> Array:
	var circuit_entries: Array = []
	for theme: String in CIRCUIT_SEEDS:
		var seeds: Array = CIRCUIT_SEEDS[theme]
		for seed_index in seeds.size():
			circuit_entries.append({
				"theme": theme,
				"seed": int(seeds[seed_index]),
				"label": "%s Circuit %02d" % [theme.capitalize(), seed_index + 1],
			})
	return circuit_entries
