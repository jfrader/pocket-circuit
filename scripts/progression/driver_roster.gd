class_name DriverRoster
extends RefCounted

## Saved opponent identities, independent of future car-catalog additions.

const SCHEMA_VERSION := 1
const GENERATOR_VERSION := 1
const MAX_SEED := 0x7FFFFFFF
const MAX_OPPONENTS := 8
const MAX_NAME_LENGTH := 64
const PLAYER_ID := "player"
const OPPONENT_ROLE := "Racer"

const NAMES_PATH := "res://data/drivers/names.json"

## Opponents are not six independent dice rolls: they get one of the shipped
## rival personalities, so a field always mixes a short-cut taker, a patient
## driver and two all-rounders instead of three identical strangers. These are
## the cast's own tuned profiles, which the AI controller and its tests already
## validate.
const PERSONALITIES := {
	"shortcut": {
		"corner_pace": 1.0, "brake_timing": 1.02, "boost_eagerness": 1.18,
		"overtake_aggression": 1.04, "shortcut_preference": 1.16, "line_commitment": 0.96,
	},
	"patient": {
		"corner_pace": 1.01, "brake_timing": 1.1, "boost_eagerness": 0.94,
		"overtake_aggression": 0.9, "shortcut_preference": 0.96, "line_commitment": 1.06,
	},
	"precise": {
		"corner_pace": 1.04, "brake_timing": 0.9, "boost_eagerness": 1.0,
		"overtake_aggression": 1.0, "shortcut_preference": 1.0, "line_commitment": 1.06,
	},
	"bold": {
		"corner_pace": 1.02, "brake_timing": 0.97, "boost_eagerness": 1.04,
		"overtake_aggression": 1.13, "shortcut_preference": 1.08, "line_commitment": 1.04,
	},
}
## The short-cut taker and the patient driver lead every field so a full grid is
## guaranteed to differ in routing; the two all-rounders swap order per roster.
const PERSONALITY_ORDER := ["shortcut", "patient", "precise", "bold"]
const GUARANTEED_PERSONALITIES := 2

static var _names_cache: Dictionary = {}


static func create(seed: int, vehicle_ids: Array, count: int) -> Dictionary:
	if count <= 0 or count > MAX_OPPONENTS:
		return {}
	if not _is_seed(seed):
		return {}
	var vids: Array[String] = _valid_vehicle_list(vehicle_ids)
	if vids.is_empty():
		return {}
	var names_data := _load_names()
	if names_data.is_empty():
		return {}
	var first_pool: Array = names_data.get("first", [])
	var last_pool: Array = names_data.get("last", [])
	if first_pool.size() < 2 or last_pool.size() < 2:
		return {}

	var opponents: Array = []
	var used_names: Dictionary = {}
	var used_vehicles: Dictionary = {}

	for i: int in range(count):
		var opp_seed := _mix_seed(seed, "op:%d" % i)
		var op_id := _make_opponent_id(seed, i)

		var name := _make_unique_name(opp_seed, first_pool, last_pool, used_names)
		if name.is_empty() or used_names.has(name):
			return {}
		used_names[name] = true

		var vehicle_id := _assign_vehicle(opp_seed, vids, used_vehicles)

		var avatar_seed := _derive_avatar_seed(opp_seed, i)
		var ai_style := _personality_for(seed, i)

		var opp := {
			"id": op_id,
			"name": name,
			"vehicle_id": vehicle_id,
			"avatar_art": {
				"seed": avatar_seed,
				"options": {},
			},
			"ai_style": ai_style,
			"role": OPPONENT_ROLE,
		}
		opponents.append(opp)

	var roster := {
		"schema_version": SCHEMA_VERSION,
		"generator_version": GENERATOR_VERSION,
		"seed": seed,
		"count": count,
		"opponents": opponents,
	}
	roster["fingerprint"] = _roster_fingerprint(roster)
	return roster


static func normalize(raw: Variant, vehicle_ids: Array, count: int) -> Dictionary:
	if raw is not Dictionary or count <= 0 or count > MAX_OPPONENTS:
		return {}
	var r := raw as Dictionary
	if not _is_seed(r.get("schema_version")) or int(r["schema_version"]) != SCHEMA_VERSION:
		return {}
	if not _is_seed(r.get("generator_version")) or int(r["generator_version"]) != GENERATOR_VERSION:
		return {}
	if not _is_seed(r.get("seed")) or not _is_seed(r.get("count")) or int(r["count"]) != count:
		return {}
	var vids: Array[String] = _valid_vehicle_list(vehicle_ids)
	if vids.is_empty():
		return {}
	var raw_opps_v: Variant = r.get("opponents")
	if raw_opps_v is not Array or (raw_opps_v as Array).size() != count:
		return {}
	var raw_opps: Array = raw_opps_v
	var seen_names: Dictionary = {}
	var norm_opps: Array = []
	for index in count:
		var o: Variant = raw_opps[index]
		if o is not Dictionary:
			return {}
		var op := o as Dictionary
		if op.get("id") != _make_opponent_id(int(r["seed"]), index):
			return {}
		var oname: Variant = op.get("name")
		if oname is not String or oname.is_empty() or oname.length() > MAX_NAME_LENGTH or seen_names.has(oname):
			return {}
		var ovid: Variant = op.get("vehicle_id")
		if ovid is not String or not ovid in vids:
			return {}
		seen_names[oname] = true

		var art_v: Variant = op.get("avatar_art")
		if art_v is not Dictionary:
			return {}
		var art := art_v as Dictionary
		if not _is_seed(art.get("seed")) or art.get("options") is not Dictionary or not art["options"].is_empty():
			return {}
		var style_v: Variant = op.get("ai_style")
		if style_v is not Dictionary:
			return {}
		var style := style_v as Dictionary
		if not _is_known_personality(style):
			return {}
		norm_opps.append({
			"id": op["id"], "name": oname, "vehicle_id": ovid,
			"avatar_art": {"seed": int(art["seed"]), "options": {}},
			"ai_style": style.duplicate(true), "role": OPPONENT_ROLE,
		})

	var norm := {
		"schema_version": SCHEMA_VERSION,
		"generator_version": GENERATOR_VERSION,
		"seed": int(r["seed"]),
		"count": count,
		"opponents": norm_opps,
	}
	norm["fingerprint"] = _roster_fingerprint(norm)

	var raw_fp: Variant = r.get("fingerprint")
	if raw_fp is not String or raw_fp != norm["fingerprint"]:
		return {}
	return norm


static func opponents_for_slots(roster: Dictionary, slots: Array) -> Array:
	if roster.is_empty() or slots.is_empty():
		return []
	var opps_v: Variant = roster.get("opponents")
	if opps_v is not Array or (opps_v as Array).is_empty():
		return []
	var opps: Array = opps_v
	var out: Array = []
	var seen := {}
	for slot: Variant in slots:
		if not _is_seed(slot) or int(slot) >= opps.size() or seen.has(int(slot)):
			return []
		if opps[int(slot)] is not Dictionary:
			return []
		seen[int(slot)] = true
		out.append((opps[int(slot)] as Dictionary).duplicate(true))
	return out


static func _is_seed(v: Variant) -> bool:
	if v is not int and v is not float:
		return false
	return is_finite(float(v)) and float(v) >= 0.0 and float(v) <= MAX_SEED and float(v) == floorf(float(v))


static func _mix_seed(seed: int, stream: String) -> int:
	return ("driver-roster:v%d:%d:%s" % [GENERATOR_VERSION, seed, stream]).hash() & MAX_SEED


static func _valid_vehicle_list(raw: Array) -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = {}
	for item: Variant in raw:
		if item is not String or item.is_empty() or seen.has(item):
			return []
		seen[item] = true
		out.append(item)
	return out


static func _load_names() -> Dictionary:
	if not _names_cache.is_empty():
		return _names_cache
	if not FileAccess.file_exists(NAMES_PATH):
		push_error("DriverRoster: missing names list at %s" % NAMES_PATH)
		return {}
	var text := FileAccess.get_file_as_string(NAMES_PATH)
	var p: Variant = JSON.parse_string(text)
	if p is not Dictionary:
		push_error("DriverRoster: names.json must be object")
		return {}
	var d := p as Dictionary
	var f: Variant = d.get("first")
	var l: Variant = d.get("last")
	if f is not Array or l is not Array or (f as Array).size() < 2 or (l as Array).size() < 2:
		push_error("DriverRoster: names.json requires non-empty first/last arrays")
		return {}
	_names_cache = {
		"first": (f as Array).duplicate(),
		"last": (l as Array).duplicate(),
	}
	return _names_cache


static func _make_opponent_id(seed: int, index: int) -> String:
	return "op-%08x-%02d" % [seed, index]


static func _make_unique_name(opp_seed: int, firsts: Array, lasts: Array, used: Dictionary) -> String:
	var available: Array[String] = []
	for first: String in firsts:
		for last: String in lasts:
			var full := first + " " + last
			if not used.has(full):
				available.append(full)
	if available.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = _mix_seed(opp_seed, "name")
	return available[rng.randi_range(0, available.size() - 1)]


static func _assign_vehicle(opp_seed: int, vids: Array[String], used: Dictionary) -> String:
	var vseed := _mix_seed(opp_seed, "vehicle")
	var rng := RandomNumberGenerator.new()
	rng.seed = vseed
	var unused: Array[String] = []
	for v: String in vids:
		if int(used.get(v, 0)) == 0:
			unused.append(v)
	var pool: Array[String] = unused if not unused.is_empty() else vids
	var idx := rng.randi_range(0, pool.size() - 1)
	var chosen := pool[idx]
	used[chosen] = int(used.get(chosen, 0)) + 1
	return chosen


static func _derive_avatar_seed(opp_seed: int, index: int) -> int:
	return posmod(_mix_seed(opp_seed, "avatar:%d" % index), MAX_SEED)


## Slot `index` in a roster of `seed`. The first two slots are always the
## short-cut taker and the patient driver; the rest follow a seeded order, so a
## full grid mixes behaviour and no two rosters order the all-rounders the same.
static func _personality_for(seed: int, index: int) -> Dictionary:
	if index < GUARANTEED_PERSONALITIES:
		return (PERSONALITIES[PERSONALITY_ORDER[index]] as Dictionary).duplicate()
	var tail := _seeded_order(seed, PERSONALITY_ORDER.slice(GUARANTEED_PERSONALITIES))
	return (PERSONALITIES[tail[(index - GUARANTEED_PERSONALITIES) % tail.size()]] as Dictionary).duplicate()


## Deterministic ordering: sort by a seed-derived key rather than the global RNG.
static func _seeded_order(seed: int, names: Array) -> Array:
	var keyed: Array = []
	for name: String in names:
		keyed.append({"name": name, "key": _mix_seed(seed, "order:" + name)})
	keyed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["key"]) != int(b["key"]):
			return int(a["key"]) < int(b["key"])
		return String(a["name"]) < String(b["name"]))
	var order: Array = []
	for entry: Dictionary in keyed:
		order.append(String(entry["name"]))
	return order


## A saved personality must be one of the shipped profiles, so a roster can never
## smuggle in an out-of-bounds or half-written style.
static func _is_known_personality(style: Dictionary) -> bool:
	for personality: Dictionary in PERSONALITIES.values():
		var matches := true
		for trait_key: String in personality:
			if not style.has(trait_key) or not is_equal_approx(float(style[trait_key]), float(personality[trait_key])):
				matches = false
				break
		if matches and style.size() == personality.size():
			return true
	return false


static func _roster_fingerprint(roster: Dictionary) -> String:
	var canonical := roster.duplicate(true)
	canonical.erase("fingerprint")
	return JSON.stringify(canonical).sha256_text().substr(0, 16)
