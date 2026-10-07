class_name RunState
extends RefCounted

## Run foundations for the championship-as-a-run roguelike (GURI-1372 / GURI-1738).
## Holds the single run seed from which everything (cars, rivals, circuits, parts)
## is derived. Pure, deterministic, no scene or node dependencies.
##
## Six-axis car rolls:
##   Axes: speed, accel, grip, drift, boost, tough
##   Every roll is zero-mean: paired opposites cancel (speed paid by tough/armour,
##   grip paid by drift; accel paid by boost). Each deviation is bounded by the
##   tier's envelope.
##
## Tiers and envelopes (per task spec):
##   Starter:    compact, buggy, hatchback, sedan           -> 0.09
##   Sidegrade:  coupe, muscle, pickup, suv, van           -> 0.18
##   Ceiling:    (future high-end)                         -> 0.30
##   Within a tier, every type uses the identical total budget (same envelope).
##
## Wear/condition (run state, advanced only by the run, not Quick Race):
##   clean -> dusty -> rusty -> dented  (monotonic, read from the car itself)
##   Bench action either restores OR fits a part, never both in one visit.
##   Run ends when a car reaches worn-out (dented and further stress).
##
## Determinism: same (run_seed, vehicle_id, car_type) always yields identical
## rolls and wear transitions are pure functions.
##
## Save shape recommendation (for next slice):
##   Preferred: add a versioned "current_run" field to the main save
##   (save_store.gd CURRENT_VERSION 4 -> 5 with a migration path that can
##   default an empty run or reconstruct from championship seed if needed).
##   Alternative considered: separate "user://pocket_circuit_active_run.json"
##   (or run-specific file per championship seed) so the heavy write path
##   (crash wear updates mid-race) does not touch the meta-progression save.
##   We recommend the main-save field for simplicity of atomicity and
##   single source of truth with championship_circuit, but a side file
##   would isolate run state volatility. Do not wire or bump version here;
##   this ticket only supplies the pure model + serialization shape.
##   See GURI-1738 and the parked GURI-1372 for integration plan.
##
## API (foundations slice):
##   RunState.create(run_seed) -> new empty holder
##   .run_seed, .act, .row (nullable), .car_rolls, .car_wear
##   get_or_create_car_roll(vehicle_id, car_type) -> six-axis dict (cached)
##   set_car_wear(vehicle_id, wear) , get_car_wear(vehicle_id)
##   Static: generate_car_roll(run_seed, tier, car_type, vehicle_id)
##   Static: advance_wear(current, severity), restore_at_bench(current)
##   Static: is_worn_out(wear), get_tier_for_type(car_type), get_envelope_*(...)
##   Static: serialize(rs) -> dict, deserialize(data) -> RunState
##   Helpers: sum_of_axes(roll), max_abs_deviation(roll)

const SCHEMA_VERSION := 1

const AXES: Array[String] = CarProfile.AXES
const WEAR_LEVELS: Array[String] = ["clean", "dusty", "rusty", "dented"]

const TIER_ENVELOPES := {
	"starter": 0.09,
	"sidegrade": 0.18,
	"ceiling": 0.30,
}

const TYPE_TO_TIER := {
	"compact": "starter",
	"buggy": "starter",
	"coupe": "sidegrade",
	"muscle": "sidegrade",
	# Future-proof from spec language; catalog may grow these later.
	"hatchback": "starter",
	"sedan": "starter",
	"pickup": "sidegrade",
	"suv": "sidegrade",
	"van": "sidegrade",
}

# Hash constants (mirrors style in championship_circuit_identity and track_seed_gen
# for cross-module determinism without platform RNG).
const HASH_INITIAL := 0x13579BDF
const HASH_MULTIPLIER := 1103515245
const HASH_ADD := 12345
const HASH_MASK := 0x7FFFFFFF

const ROLL_KEY_PREFIX := "pocket-circuit|run|car-roll|v%d" % SCHEMA_VERSION
const SPEED_SALT := 0x53504544  # SPEE D
const GRIP_SALT := 0x47524950   # GRIP
const ACCEL_SALT := 0x41434345  # ACCE L
const BOOST_SALT := 0x424F4F53  # BOOS T (used for third independent)
const TOUGH_SALT := 0x544F5547  # TOUG H (pair)
const DRIFT_SALT := 0x44524946  # DRIF T (pair)

var run_seed: int = 0
var act: Variant = null  # int or null for now
var row: Variant = null  # int or null for now
var car_rolls: Dictionary = {}  # vehicle_id -> six-axis roll dict
var car_wear: Dictionary = {}   # vehicle_id -> wear string

static func get_tier_for_type(car_type: String) -> String:
	return TYPE_TO_TIER.get(car_type, "starter")

static func get_envelope_for_tier(tier: String) -> float:
	return TIER_ENVELOPES.get(tier, 0.09)

static func get_envelope_for_type(car_type: String) -> float:
	return get_envelope_for_tier(get_tier_for_type(car_type))

static func _hash32(value: int) -> int:
	# Compact avalanche, 31-bit masked for native/headless parity.
	var mixed := value & HASH_MASK
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & HASH_MASK
	mixed = ((mixed ^ (mixed >> 16)) * 0x45D9F3B) & HASH_MASK
	return (mixed ^ (mixed >> 16)) & HASH_MASK

static func _hash_unit(seed: int, salt: int) -> float:
	return float(_hash32(seed ^ salt)) / 2147483647.0

static func _derive_roll_seed(run_seed: int, vehicle_id: String, car_type: String, tier: String) -> int:
	var value := HASH_INITIAL
	var key := (ROLL_KEY_PREFIX + "|seed=%d|vehicle=%s|type=%s|tier=%s") % [
		run_seed, vehicle_id, car_type, tier
	]
	for byte: int in key.to_utf8_buffer():
		value = (value * HASH_MULTIPLIER + byte + HASH_ADD) & HASH_MASK
		value = (value ^ (value >> 11)) & HASH_MASK
	return value

## Generate a deterministic zero-mean six-axis roll for the given inputs.
## Returned dict always has exactly the AXES keys, values in [-env, +env],
## and exact sum 0.0 (pairing: speed<->tough, grip<->drift, accel<->boost).
static func generate_car_roll(run_seed: int, tier: String, car_type: String, vehicle_id: String = "") -> Dictionary:
	var env := get_envelope_for_tier(tier)
	var base := _derive_roll_seed(run_seed, vehicle_id, car_type, tier)
	# Three independent signed deviations; pairs ensure zero mean.
	var u_speed := _hash_unit(base, SPEED_SALT)
	var u_grip := _hash_unit(base, GRIP_SALT)
	var u_accel := _hash_unit(base, ACCEL_SALT)
	var d_speed := (u_speed * 2.0 - 1.0) * env
	var d_grip := (u_grip * 2.0 - 1.0) * env
	var d_accel := (u_accel * 2.0 - 1.0) * env
	var roll := {
		"speed": d_speed,
		"accel": d_accel,
		"grip": d_grip,
		"drift": -d_grip,
		"boost": -d_accel,
		"tough": -d_speed,
	}
	# Guarantee order and completeness for callers/tests.
	var out := {}
	for axis: String in AXES:
		out[axis] = float(roll[axis])
	return out

static func sum_of_axes(roll: Dictionary) -> float:
	var s := 0.0
	for axis: String in AXES:
		s += float(roll.get(axis, 0.0))
	return s

static func max_abs_deviation(roll: Dictionary) -> float:
	var m := 0.0
	for axis: String in AXES:
		m = maxf(m, absf(float(roll.get(axis, 0.0))))
	return m

## Pure wear transition. severity in [0,1+] ; higher values advance multiple steps (can jump clean to dented in one hit).
## Always monotonic; caps at "dented".
static func advance_wear(current: String, severity: float) -> String:
	var idx := WEAR_LEVELS.find(current)
	if idx < 0:
		idx = 0
	var steps := 0
	if severity > 0.66:
		steps = 2
	elif severity > 0.33:
		steps = 1
	# minor crashes (0.0-0.33) do nothing
	var new_idx := mini(idx + steps, WEAR_LEVELS.size() - 1)
	return WEAR_LEVELS[new_idx]

## Bench action: restores condition. Caller decides "restore OR part", never both.
static func restore_at_bench(_current: String) -> String:
	return "clean"

static func is_worn_out(wear: String) -> bool:
	return wear == "dented"

## Returns a new or cached roll for this vehicle within the run.
## Caches for stability across calls in one run instance.
func get_or_create_car_roll(vehicle_id: String, car_type: String) -> Dictionary:
	if car_rolls.has(vehicle_id):
		return (car_rolls[vehicle_id] as Dictionary).duplicate(true)
	var tier := get_tier_for_type(car_type)
	var roll := generate_car_roll(run_seed, tier, car_type, vehicle_id)
	car_rolls[vehicle_id] = roll.duplicate(true)
	return roll.duplicate(true)

func get_car_wear(vehicle_id: String) -> String:
	return car_wear.get(vehicle_id, "clean")

func set_car_wear(vehicle_id: String, wear: String) -> void:
	if wear in WEAR_LEVELS:
		car_wear[vehicle_id] = wear
	else:
		car_wear[vehicle_id] = "clean"

## Create a fresh run state holder. Rolls and wear populated on demand or explicitly.
static func create(run_seed: int) -> RunState:
	var rs := new()
	rs.run_seed = posmod(run_seed, 0x7FFFFFFF)
	rs.act = null
	rs.row = null
	rs.car_rolls = {}
	rs.car_wear = {}
	return rs

## Serialization shape for save integration (versioned dict, stable keys).
static func serialize(rs: RunState) -> Dictionary:
	var rolls := {}
	for vid: String in rs.car_rolls:
		var r: Dictionary = rs.car_rolls[vid]
		var clean := {}
		for axis: String in AXES:
			clean[axis] = float(r.get(axis, 0.0))
		rolls[vid] = clean
	var wears := rs.car_wear.duplicate(true)
	return {
		"schema_version": SCHEMA_VERSION,
		"run_seed": rs.run_seed,
		"act": rs.act,
		"row": rs.row,
		"car_rolls": rolls,
		"car_wear": wears,
	}

static func deserialize(data: Dictionary) -> RunState:
	var rs := new()
	var ver: Variant = data.get("schema_version", 0)
	if (ver is int or ver is float) and int(ver) == SCHEMA_VERSION:
		rs.run_seed = int(data.get("run_seed", 0))
		var act_val: Variant = data.get("act")
		rs.act = int(act_val) if (act_val is int or act_val is float) else null
		var r: Variant = data.get("row")
		rs.row = int(r) if (r is int or r is float) else null
		var rolls_in: Dictionary = data.get("car_rolls", {}) as Dictionary
		for vid: String in rolls_in:
			var rdict: Dictionary = rolls_in[vid] as Dictionary
			var clean := {}
			for axis: String in AXES:
				clean[axis] = float(rdict.get(axis, 0.0))
			rs.car_rolls[vid] = clean
		var wears_in: Dictionary = data.get("car_wear", {}) as Dictionary
		for vid: String in wears_in:
			var w := String(wears_in[vid])
			if w in WEAR_LEVELS:
				rs.car_wear[vid] = w
	else:
		return null
	return rs

func _to_string() -> String:
	return "RunState(seed=%d, cars=%d, act=%s)" % [run_seed, car_rolls.size(), str(act)]
