class_name GeneratedCircuitRules
extends RefCounted

const MAX_SEED := 0x7FFFFFFF
const ROOMS: Array[String] = ["classic", "wide", "tall", "long", "square", "el"]
const STORY_IDS := {
	"kitchen": ["breakfast_service", "vegetable_prep", "afternoon_tea", "counter_cleanup"],
	"workshop": ["carpentry_bench", "paint_station", "repair_job", "garage_sort"],
	"office": ["dual_workstation", "mail_sort", "sketch_session", "coffee_break"],
}
const ACT_OBSTACLE_RANGES := {
	1: Vector2i(0, 1),
	2: Vector2i(1, 2),
	3: Vector2i(2, 3),
}
const HAZARD_PRESENCE_BY_ACT := {1: 0.35, 2: 0.55, 3: 0.75}
const LENGTH_TIERS: Array[String] = ["compact", "standard", "long", "endurance", "marathon"]
const DEFAULT_LENGTH_TIER: String = "standard"
const LENGTH_PROFILE_BANDS := {
	"compact": {"min_length": 4000.0, "max_length": 6000.0, "room_scale": 0.95},
	"standard": {"min_length": 4375.0, "max_length": 9625.0, "room_scale": 1.0},
	"long": {"min_length": 12000.0, "max_length": 16000.0, "room_scale": 1.8},
	"endurance": {"min_length": 18000.0, "max_length": 24000.0, "room_scale": 2.8},
	"marathon": {"min_length": 32000.0, "max_length": 48000.0, "room_scale": 4.5},
}


static func length_profile(tier: String) -> Dictionary:
	if not LENGTH_TIERS.has(tier):
		return {}
	var band: Dictionary = LENGTH_PROFILE_BANDS[tier]
	return {
		"id": tier,
		"label": tier.substr(0, 1).to_upper() + tier.substr(1),
		"min_length": float(band["min_length"]),
		"max_length": float(band["max_length"]),
		"room_scale": float(band["room_scale"]),
	}


static func default_act_for_theme(theme: StringName) -> int:
	match theme:
		&"workshop":
			return 2
		&"office":
			return 3
	return 1


static func room_for_composition_seed(seed: int) -> StringName:
	if seed < 0 or seed > MAX_SEED:
		return &""
	return StringName(ROOMS[posmod(seed, ROOMS.size())])


static func story_index(theme: StringName, dressing_seed: int) -> int:
	var stories: Array = STORY_IDS.get(String(theme), [])
	return posmod(dressing_seed, stories.size()) if not stories.is_empty() else -1


static func story_id(theme: StringName, dressing_seed: int) -> StringName:
	var stories: Array = STORY_IDS.get(String(theme), [])
	var index := story_index(theme, dressing_seed)
	return StringName(stories[index]) if index >= 0 else &""


static func obstacle_range(act: int) -> Vector2i:
	return ACT_OBSTACLE_RANGES[clampi(act, 1, 3)]


static func obstacle_count(act: int, obstacle_seed: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = obstacle_seed
	return roll_obstacle_count(act, rng)


static func roll_obstacle_count(act: int, rng: RandomNumberGenerator) -> int:
	var count_range := obstacle_range(act)
	return rng.randi_range(count_range.x, count_range.y)


static func hazard_chance(act: int) -> float:
	return float(HAZARD_PRESENCE_BY_ACT[clampi(act, 1, 3)])


static func hazard_present(act: int, hazard_seed: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = hazard_seed
	return roll_hazard_present(act, rng)


static func roll_hazard_present(act: int, rng: RandomNumberGenerator) -> bool:
	return rng.randf() < hazard_chance(act)


static func danger_profile(act: int, obstacle_seed: int, hazard_seed: int) -> Dictionary:
	return {
		"level": clampi(act, 1, 3),
		"obstacle_count": obstacle_count(act, obstacle_seed),
		"hazard_present": hazard_present(act, hazard_seed),
		"hazard_chance": hazard_chance(act),
	}