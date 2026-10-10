class_name RunParts
extends RefCounted

## The run's parts: what each one does to the car (written by hand) and what
## each parts van stocks (rolled from the run seed).
##
## A part is an upside and a downside, never one alone. The van rolls which
## parts it stocks and the downside each carries; a downside never touches the
## stats its upside moves. A part is {"part": id, "downside": id}.
##
## Both sides move VehicleStats fields by a fraction of the room left toward
## the edge of the field's range (CarProfile.move_field, the rule a car's roll
## uses), so stacked parts stay inside every range.

const UPSIDES := {
	"power_scoop": {"name": "Power Scoop", "cost": 10, "copy": "Drifts fill the boost faster", "moves": {"boost_recharge": 0.6, "drift_boost_max_reward": 0.4}},
	"slick_tyres": {"name": "Slick Tyres", "cost": 10, "copy": "More grip in the corners", "moves": {"front_grip": 0.45, "rear_grip": 0.45}},
	"short_gears": {"name": "Short Gears", "cost": 5, "copy": "Quicker off the line", "moves": {"launch_torque_multiplier": 0.7, "engine_force": 0.3}},
	"long_gears": {"name": "Long Gears", "cost": 10, "copy": "Higher top speed", "moves": {"max_speed": 0.5}},
	"quick_rack": {"name": "Quick Rack", "cost": 5, "copy": "Sharper turn-in", "moves": {"steering_response": 0.6, "max_steer_angle_deg": 0.3}},
	"drift_diff": {"name": "Drift Diff", "cost": 10, "copy": "Drifts start easier and swing wider", "moves": {"drift_entry_steer": -0.5, "drift_min_speed": -0.5, "drift_yaw_assist": 0.4}},
	"big_tank": {"name": "Big Tank", "cost": 5, "copy": "More boost in the tank", "moves": {"boost_capacity": 0.7}},
	"nitro_jets": {"name": "Nitro Jets", "cost": 15, "copy": "Boost shoves harder", "moves": {"boost_power": 0.6}},
	"race_brakes": {"name": "Race Brakes", "cost": 5, "copy": "Brakes bite harder", "moves": {"brake_force": 0.6, "handbrake_force": 0.3}},
	"big_block": {"name": "Big Block", "cost": 15, "copy": "More pull at every speed", "moves": {"engine_force": 0.5}},
}

const DOWNSIDES := {
	"top_speed": {"copy": "Top speed drops on the straights", "moves": {"max_speed": -0.35}},
	"launch": {"copy": "Slower off the line", "moves": {"launch_torque_multiplier": -0.5}},
	"pull": {"copy": "Less pull at every speed", "moves": {"engine_force": -0.3}},
	"front_bite": {"copy": "Pushes wide in the corners", "moves": {"front_grip": -0.3}},
	"loose_rear": {"copy": "The rear steps out", "moves": {"rear_grip": -0.3}},
	"lazy_rack": {"copy": "Slower turn-in", "moves": {"steering_response": -0.4}},
	"twitchy": {"copy": "Slides are harder to catch", "moves": {"yaw_stability_rate": -0.45}},
	"thirsty": {"copy": "Boost burns faster", "moves": {"boost_drain_rate": 0.5}},
	"small_tank": {"copy": "Less boost in the tank", "moves": {"boost_capacity": -0.45}},
	"heavy": {"copy": "Heavier: slower to speed up and to turn", "moves": {"mass": 0.35}},
	"stiff_drift": {"copy": "Drifts are harder to start", "moves": {"drift_entry_steer": 0.4, "drift_min_speed": 0.4}},
	"soft_brakes": {"copy": "Softer brakes", "moves": {"brake_force": -0.4}},
}

## How many parts one van stocks.
const VAN_STOCK := 3


## The parts a van stocks, from that stop's roll: distinct parts, each with a
## downside dealt from the ones it allows.
static func deal(stop_roll: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = stop_roll
	var pool: Array = UPSIDES.keys()
	var stock: Array[Dictionary] = []
	while stock.size() < VAN_STOCK and not pool.is_empty():
		var part_id := String(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
		var allowed := downsides_for(part_id)
		stock.append({"part": part_id, "downside": allowed[rng.randi_range(0, allowed.size() - 1)]})
	return stock


## The downsides a part can carry: every one that moves none of its upside's stats.
static func downsides_for(part_id: String) -> Array[String]:
	var upside: Dictionary = (UPSIDES.get(part_id, {}) as Dictionary).get("moves", {})
	var out: Array[String] = []
	for downside_id: String in DOWNSIDES:
		var moves: Dictionary = DOWNSIDES[downside_id]["moves"]
		if not moves.keys().any(func(field: String) -> bool: return upside.has(field)):
			out.append(downside_id)
	return out


## A copy of `stats` with every part's upside and downside applied in order.
static func apply(stats: VehicleStats, parts: Array) -> VehicleStats:
	var fitted := stats.duplicate(true) as VehicleStats
	for part: Dictionary in parts:
		for side: Dictionary in [UPSIDES[part["part"]], DOWNSIDES[part["downside"]]]:
			var moves: Dictionary = side["moves"]
			for field: String in moves:
				CarProfile.move_field(fitted, field, float(moves[field]))
	return fitted


## A stored part with both sides checked, or {} when it cannot be trusted.
static func normalize(value: Variant) -> Dictionary:
	if value is not Dictionary:
		return {}
	var part_id: Variant = (value as Dictionary).get("part")
	var downside_id: Variant = (value as Dictionary).get("downside")
	if part_id is not String or not UPSIDES.has(part_id) or downside_id not in downsides_for(String(part_id)):
		return {}
	return {"part": String(part_id), "downside": String(downside_id)}


## Stored parts, each checked; the ones that cannot be trusted are dropped.
static func normalize_list(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if value is Array:
		for entry: Variant in value as Array:
			var part := normalize(entry)
			if not part.is_empty():
				out.append(part)
	return out


static func part_name(part: Dictionary) -> String:
	return String(UPSIDES[part["part"]]["name"])


static func cost(part: Dictionary) -> int:
	return int(UPSIDES[part["part"]]["cost"])


static func upside_copy(part: Dictionary) -> String:
	return String(UPSIDES[part["part"]]["copy"])


static func downside_copy(part: Dictionary) -> String:
	return String(DOWNSIDES[part["downside"]]["copy"])
