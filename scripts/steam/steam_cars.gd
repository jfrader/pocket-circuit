class_name SteamCars
extends RefCounted

## Cars as Steam inventory items: the item definitions uploaded to Steamworks
## and the one rule that turns an item back into a car.
##
## Steam rolls the car. Winning a car in a run asks the playtime generator for
## a drop; Steam picks a car type and rolls the item's tags. Tags survive
## trades (dynamic properties do not), so a car is only its item definition
## and its tags, and every client that sees the item rebuilds the same car:
##   type    the item definition (one per generator car type)
##   pace    speed against tough   } one bucket each, mirrored onto the pair
##   bite    grip against drift    } the way a run roll is (RunState),
##   punch   accel against boost   } scaled into the type's envelope
##   livery  the look's seed
##
## Ids, weights and drop limits live here and nowhere else; the Steamworks
## file is generated from them (tools/export_steam_itemdefs.gd).

const RUN_STATE := preload("res://scripts/progression/run_state.gd")

const ORIGIN := "steam"
const ID_PREFIX := "steam-"
const GENERATOR_ID := 1000
const CAR_ITEM_IDS := {"compact": 1001, "buggy": 1002, "coupe": 1003, "muscle": 1004}
## How often each type drops, relative to the others.
const TYPE_WEIGHTS := {"compact": 4, "buggy": 4, "coupe": 2, "muscle": 2}
const TAG_GENERATOR_IDS := {"pace": 1101, "bite": 1102, "punch": 1103, "livery": 1104}
## The axis each pair tag moves; its partner gets the mirror (RunState.roll_from_pairs).
const PAIR_AXES := {"pace": "speed", "bite": "grip", "punch": "accel"}
## Bucket weights from the weakest to the strongest step; the middle is level.
const BUCKET_WEIGHTS: Array[int] = [1, 2, 4, 7, 9, 7, 4, 2, 1]
const BUCKET_TOKEN := "b%d"
const LIVERY_COUNT := 256
const LIVERY_TOKEN := "l%d"
## Steam's playtime drop limits: minutes of play between drops, and at most
## DROP_MAX_PER_WINDOW drops in each DROP_WINDOW minutes.
const DROP_INTERVAL_MINUTES := 30
const DROP_WINDOW_MINUTES := 1440
const DROP_MAX_PER_WINDOW := 3
const LOOK_KEY := "pocket-circuit|steam-car|%s|%s"
const SEED_MASK := 0x7FFFFFFF


## The Steamworks item definitions for `app_id`, as the schema file's object.
static func itemdefs(app_id: int) -> Dictionary:
	var items: Array = []
	var bundle := PackedStringArray()
	for car_type: String in CAR_ITEM_IDS:
		bundle.append("%dx%d" % [CAR_ITEM_IDS[car_type], TYPE_WEIGHTS[car_type]])
	items.append({
		"itemdefid": GENERATOR_ID,
		"type": "playtimegenerator",
		"name": "Night drop",
		"bundle": ";".join(bundle),
		"tag_generators": ";".join(PackedStringArray(TAG_GENERATOR_IDS.values().map(func(id: int) -> String: return str(id)))),
		"drop_interval": DROP_INTERVAL_MINUTES,
		"use_drop_window": true,
		"drop_window": DROP_WINDOW_MINUTES,
		"drop_max_per_window": DROP_MAX_PER_WINDOW,
		"hidden": true,
	})
	for car_type: String in CAR_ITEM_IDS:
		items.append({
			"itemdefid": CAR_ITEM_IDS[car_type],
			"type": "item",
			"name": "%s car" % car_type.capitalize(),
			"description": "A %s for the Pocket Circuit garage." % car_type,
			"tags": "type:%s" % car_type,
			"tradable": true,
			"marketable": false,
		})
	for tag: String in TAG_GENERATOR_IDS:
		items.append({
			"itemdefid": TAG_GENERATOR_IDS[tag],
			"type": "tag_generator",
			"name": "%s roll" % tag.capitalize(),
			"tag_generator_name": tag,
			"tag_generator_values": _tag_values(tag),
		})
	return {"appid": app_id, "items": items}


## The car an item is, or {} when the item is not a car or its tags do not
## decode: {id, seed, type, roll, won_from, act}.
static func car_from_item(item_def: int, item_id: int, tags: String) -> Dictionary:
	var car_type := String(CAR_ITEM_IDS.find_key(item_def)) if CAR_ITEM_IDS.find_key(item_def) != null else ""
	if car_type.is_empty() or item_id <= 0:
		return {}
	var values := parse_tags(tags)
	var steps := {}
	for tag: String in PAIR_AXES:
		var bucket := _token_index(String(values.get(tag, "")), BUCKET_TOKEN, BUCKET_WEIGHTS.size())
		if bucket < 0:
			return {}
		steps[tag] = bucket_deviation(bucket, car_type)
	var livery := _token_index(String(values.get("livery", "")), LIVERY_TOKEN, LIVERY_COUNT)
	if livery < 0:
		return {}
	return {
		"id": ID_PREFIX + str(item_id),
		"seed": (LOOK_KEY % [car_type, livery]).hash() & SEED_MASK,
		"type": car_type,
		"roll": RUN_STATE.roll_from_pairs(steps["pace"], steps["bite"], steps["punch"]),
		"won_from": ORIGIN,
		"act": 1,
	}


## A bucket's deviation for a type: evenly spaced across the type's envelope,
## the middle bucket level.
static func bucket_deviation(bucket: int, car_type: String) -> float:
	var middle := float(BUCKET_WEIGHTS.size() - 1) * 0.5
	return (float(bucket) - middle) / middle * RUN_STATE.get_envelope_for_type(car_type)


## Steam's tag string ("cat:value;cat:value") as {cat: value}.
static func parse_tags(tags: String) -> Dictionary:
	var out := {}
	for token: String in tags.split(";", false):
		var parts := token.split(":", true, 1)
		if parts.size() == 2:
			out[parts[0].strip_edges()] = parts[1].strip_edges()
	return out


static func _tag_values(tag: String) -> String:
	var values := PackedStringArray()
	if tag == "livery":
		for index: int in LIVERY_COUNT:
			values.append(LIVERY_TOKEN % index)
	else:
		for index: int in BUCKET_WEIGHTS.size():
			values.append("%s:%d" % [BUCKET_TOKEN % index, BUCKET_WEIGHTS[index]])
	return ";".join(values)


static func _token_index(value: String, pattern: String, count: int) -> int:
	for index: int in count:
		if value == pattern % index:
			return index
	return -1
