extends AIVehicleController
## Promo-only driver: Clockwork pushed past its tier. Faster, later braking and
## more boost. The director's --ai-<key>=value arguments override single values.

const BOSS_TUNING := {
	"pace": 1.22,
	"corner_constant": 18.0,
	"braking_near": 120.0,
	"braking_far": 260.0,
	"boost_turn_threshold": 0.55,
}
const TUNABLE_KEYS: Array[String] = [
	"pace", "corner_constant", "braking_near", "braking_far", "boost_turn_threshold",
	"boost_radius", "corner_margin", "baseline_power", "sharp_corner_ratio", "corner_floor",
]

var boss_overrides: Dictionary = {}


func _difficulty_tuning() -> Dictionary:
	var tuning: Dictionary = (DIFFICULTY_TUNING["clockwork"] as Dictionary).duplicate(true)
	tuning.merge(BOSS_TUNING, true)
	tuning.merge(boss_overrides, true)
	return tuning
