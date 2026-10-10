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
## The look's seed comes from the type and the three buckets, so two items
## with one name are the same car.
##
## Steam ignores tags without an English string on the partner site;
## tag_labels() lists every one to enter. Ids, names, weights and drop limits
## live here and nowhere else; the Steamworks file is generated from them
## (tools/export_steam_itemdefs.gd).

const RUN_STATE := preload("res://scripts/progression/run_state.gd")

const ORIGIN := "steam"
const ID_PREFIX := "steam-"
const GENERATOR_ID := 1000
const CAR_ITEM_IDS := {"compact": 1001, "buggy": 1002, "coupe": 1003, "muscle": 1004}
## Each type's item name in the Steam inventory.
const TYPE_NAMES := {"compact": "Compact car", "buggy": "Buggy", "coupe": "Coupe", "muscle": "Muscle car"}
const DESCRIPTION := "A %s for the Pocket Circuit garage."
## Where each type's item icon is hosted, "%s" being the type; empty leaves
## the icons to the partner site.
const ICON_URL := ""
const ICON_LARGE_URL := ""
## How often each type drops, relative to the others.
const TYPE_WEIGHTS := {"compact": 4, "buggy": 4, "coupe": 2, "muscle": 2}
const TAG_GENERATOR_IDS := {"pace": 1101, "bite": 1102, "punch": 1103}
## The English strings Steam shows for the tag categories.
const TAG_NAMES := {"type": "Type", "pace": "Pace", "bite": "Bite", "punch": "Punch"}
## The axis each pair tag moves; its partner gets the mirror (RunState.roll_from_pairs).
const PAIR_AXES := {"pace": "speed", "bite": "grip", "punch": "accel"}
## Bucket weights from the weakest to the strongest step; the middle is level.
const BUCKET_WEIGHTS: Array[int] = [1, 2, 4, 7, 9, 7, 4, 2, 1]
const BUCKET_TOKEN := "b%d"
## Steam's playtime drop limits: minutes of play between drops, and at most
## DROP_MAX_PER_WINDOW drops in each DROP_WINDOW minutes.
const DROP_INTERVAL_MINUTES := 30
const DROP_WINDOW_MINUTES := 1440
const DROP_MAX_PER_WINDOW := 3
const LOOK_KEY := "pocket-circuit|steam-car|%s|%d|%d|%d"
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
		var item := {
			"itemdefid": CAR_ITEM_IDS[car_type],
			"type": "item",
			"name": TYPE_NAMES[car_type],
			"description": DESCRIPTION % String(TYPE_NAMES[car_type]).to_lower(),
			"tags": "type:%s" % car_type,
			"tradable": true,
			"marketable": false,
		}
		if not ICON_URL.is_empty():
			item["icon_url"] = ICON_URL % car_type
			item["icon_url_large"] = ICON_LARGE_URL % car_type
		items.append(item)
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
	var buckets := {}
	for tag: String in PAIR_AXES:
		buckets[tag] = _token_index(String(values.get(tag, "")), BUCKET_TOKEN, BUCKET_WEIGHTS.size())
		if buckets[tag] < 0:
			return {}
	var steps := {}
	for tag: String in PAIR_AXES:
		steps[tag] = bucket_deviation(buckets[tag], car_type)
	return {
		"id": ID_PREFIX + str(item_id),
		"seed": (LOOK_KEY % [car_type, buckets["pace"], buckets["bite"], buckets["punch"]]).hash() & SEED_MASK,
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


## Every tag category and value with the English string Steam needs for it:
## {category: {"name": English, "values": {token: English}}}.
static func tag_labels() -> Dictionary:
	var types := {}
	for car_type: String in TYPE_NAMES:
		types[car_type] = TYPE_NAMES[car_type]
	var out := {"type": {"name": TAG_NAMES["type"], "values": types}}
	var middle := int((BUCKET_WEIGHTS.size() - 1) * 0.5)
	for tag: String in PAIR_AXES:
		var values := {}
		for index: int in BUCKET_WEIGHTS.size():
			values[BUCKET_TOKEN % index] = "%+d" % (index - middle) if index != middle else "0"
		out[tag] = {"name": TAG_NAMES[tag], "values": values}
	return out


static func _tag_values(_tag: String) -> String:
	var values := PackedStringArray()
	for index: int in BUCKET_WEIGHTS.size():
		values.append("%s:%d" % [BUCKET_TOKEN % index, BUCKET_WEIGHTS[index]])
	return ";".join(values)


static func _token_index(value: String, pattern: String, count: int) -> int:
	for index: int in count:
		if value == pattern % index:
			return index
	return -1
