extends RefCounted
class_name ProceduralCarGenerator

## Vendored from GurisitosGames/procedural-2d at cb4ae73 for GURI-319.
## Deterministic, JSON-friendly top-down toy car generation.

const CATALOG_PATH := "res://data/vendor/procedural_2d/car_catalog.json"
const RNG_MODULUS := 2147483647
const SUPPORTED_TYPES: Array[String] = ["compact", "coupe", "muscle", "buggy"]
const PALETTE_IDS: Array[String] = [
	"candy_red", "marina_blue", "citrus_pop", "midnight_teal", "desert_sage", "plum_soda",
]
const PART_FIELDS: Array[String] = ["hood", "cabin", "bumpers", "wheels", "spoiler", "livery"]
const PART_IDS := {
	"hood": ["smooth", "twin_vents", "power_scoop"],
	"cabin": ["bubble", "angular", "panoramic"],
	"bumpers": ["chrome", "sport", "utility"],
	"wheels": ["classic", "mesh", "rugged"],
	"spoiler": ["none", "lip", "wing"],
	"livery": ["solid", "center_stripe", "twin_stripe", "side_flash", "checker", "sunburst"],
}
const STREAM_SALTS := {
	"palette": 104729,
	"hood": 130363,
	"cabin": 155921,
	"bumpers": 181081,
	"wheels": 206369,
	"spoiler": 231829,
	"livery": 257053,
	"handling": 282427,
	"name": 307823,
}
const TYPE_SALTS := {
	"compact": 739391,
	"coupe": 1258291,
	"muscle": 1690877,
	"buggy": 2140361,
}

static var _catalog_cache: Dictionary = {}


class CarRng:
	var _state: int

	func _init(seed_value: int) -> void:
		_state = seed_value % RNG_MODULUS
		if _state <= 0:
			_state += RNG_MODULUS - 1

	func next_int() -> int:
		# Avalanche nearby seeds before reducing them into small catalog ranges.
		_state ^= _state >> 16
		_state = (_state * 0x45D9F3B) & 0x7FFFFFFF
		_state ^= _state >> 16
		_state = (_state * 0x45D9F3B) & 0x7FFFFFFF
		_state ^= _state >> 16
		if _state == 0:
			_state = 1
		return _state


static func available_types() -> Array[String]:
	return SUPPORTED_TYPES.duplicate()


static func available_palette_ids() -> Array[String]:
	return PALETTE_IDS.duplicate()


static func available_parts(_car_type: String = "") -> Dictionary:
	if not _car_type.is_empty() and not SUPPORTED_TYPES.has(_car_type):
		push_error("ProceduralCarGenerator rejected type '%s'." % _car_type)
		return {}
	return PART_IDS.duplicate(true)


static func catalog() -> Dictionary:
	var loaded := _load_catalog()
	return loaded.duplicate(true) if not loaded.is_empty() else {}


## Options may use direct slot keys or a partial `parts` Dictionary, but never both for one slot.
## `palette` and the Weapons-style `palette_id` alias accept a palette ID or `auto`.
static func validate_options(car_type: String, options: Dictionary) -> String:
	if not SUPPORTED_TYPES.has(car_type):
		return "type must be compact, coupe, muscle, or buggy"
	var allowed: Array[String] = ["palette", "palette_id", "parts"]
	allowed.append_array(PART_FIELDS)
	for key: Variant in options.keys():
		if typeof(key) != TYPE_STRING:
			return "options keys must be Strings"
		if not allowed.has(String(key)):
			return "options.%s is not supported" % key
	if options.has("palette") and options.has("palette_id"):
		return "options.palette and options.palette_id cannot both be provided"
	for palette_key in ["palette", "palette_id"]:
		if not options.has(palette_key):
			continue
		if typeof(options[palette_key]) != TYPE_STRING:
			return "options.%s must be a String" % palette_key
		var palette_value := String(options[palette_key])
		if palette_value != "auto" and not PALETTE_IDS.has(palette_value):
			return "options.%s must be 'auto' or a known palette ID" % palette_key
	var nested: Dictionary = {}
	if options.has("parts"):
		if typeof(options["parts"]) != TYPE_DICTIONARY:
			return "options.parts must be a Dictionary"
		nested = options["parts"]
		for key: Variant in nested.keys():
			if typeof(key) != TYPE_STRING:
				return "options.parts keys must be Strings"
			if not PART_FIELDS.has(String(key)):
				return "options.parts.%s is not a supported car part slot" % key
	for field in PART_FIELDS:
		if options.has(field) and nested.has(field):
			return "options.%s and options.parts.%s cannot both be provided" % [field, field]
		var container: Dictionary = options if options.has(field) else nested
		if not container.has(field):
			continue
		var path := "options.%s" % field if options.has(field) else "options.parts.%s" % field
		if typeof(container[field]) != TYPE_STRING:
			return "%s must be a String" % path
		if not PART_IDS[field].has(String(container[field])):
			return "%s must be a known %s part ID" % [path, field]
	return ""


## Generates a self-contained payload. Every choice has its own seed stream so overrides are isolated.
static func generate(input_seed: int, car_type: String, options: Dictionary = {}) -> Dictionary:
	if input_seed < 0:
		push_error("ProceduralCarGenerator rejected seed %s; seed must be non-negative." % input_seed)
		return {}
	if not SUPPORTED_TYPES.has(car_type):
		push_error(
			"ProceduralCarGenerator rejected type '%s'; expected one of %s."
			% [car_type, SUPPORTED_TYPES]
		)
		return {}
	var option_error := validate_options(car_type, options)
	if not option_error.is_empty():
		push_error("ProceduralCarGenerator rejected options: %s." % option_error)
		return {}
	var catalog_data := _load_catalog()
	if catalog_data.is_empty():
		return {}

	var mixed_seed := _mix_seed(input_seed, car_type)
	var nested: Dictionary = options.get("parts", {})
	var selected_parts := {}
	for field in PART_FIELDS:
		var ids: Array = PART_IDS[field]
		var generated_id: String = ids[_choice_index(mixed_seed, STREAM_SALTS[field], ids.size())]
		var selected_id := generated_id
		if nested.has(field):
			selected_id = String(nested[field])
		if options.has(field):
			selected_id = String(options[field])
		selected_parts[field] = selected_id

	var generated_palette: String = PALETTE_IDS[
		_choice_index(mixed_seed, STREAM_SALTS["palette"], PALETTE_IDS.size())
	]
	var requested_palette := String(options.get("palette", options.get("palette_id", "auto")))
	var palette_id := generated_palette if requested_palette == "auto" else requested_palette
	var palette_record := _record_by_id(catalog_data["palettes"], palette_id)
	var type_record: Dictionary = catalog_data["types"][car_type]
	if palette_record.is_empty() or type_record.is_empty():
		push_error("ProceduralCarGenerator catalog is incomplete for %s/%s." % [car_type, palette_id])
		return {}

	var handling_records: Array = type_record["handling"]
	var handling_record: Dictionary = handling_records[
		_choice_index(mixed_seed, STREAM_SALTS["handling"], handling_records.size())
	]
	var nouns: Array = type_record["name_nouns"]
	var noun: String = nouns[_choice_index(mixed_seed, STREAM_SALTS["name"], nouns.size())]
	var catalog_bounds: Dictionary = type_record["collision_bounds"]
	var collision_bounds := {
		"x": int(catalog_bounds["x"]),
		"y": int(catalog_bounds["y"]),
		"width": int(catalog_bounds["width"]),
		"height": int(catalog_bounds["height"]),
	}
	var tags: Array[String] = ["car", "top_down", "toy_scale", car_type, palette_id]
	for field in PART_FIELDS:
		tags.append("%s:%s" % [field, selected_parts[field]])
	tags.append("handling:%s" % handling_record["id"])

	return {
		"schema_version": 1,
		"seed": input_seed,
		"type": car_type,
		"sprite_size": {"width": 48, "height": 64},
		"palette_id": palette_id,
		"palette": palette_record["colors"].duplicate(true),
		"parts": selected_parts,
		"collision_bounds": collision_bounds,
		"anchors": {
			"pivot": {"x": 24, "y": 32},
			"front": {"x": 24, "y": 5},
			"rear": {"x": 24, "y": 59},
			"driver": {"x": 21, "y": 32},
		},
		"handling": {
			"identity": handling_record["id"],
			"display_name": handling_record["display_name"],
			"description": handling_record["description"],
			"traits": handling_record["traits"].duplicate(),
		},
		"display_name": "%s %s" % [palette_record["name_prefix"], noun],
		"tags": tags,
	}


static func _choice_index(mixed_seed: int, salt: int, size: int) -> int:
	var rng := CarRng.new(_stream_seed(mixed_seed, salt))
	return rng.next_int() % size


static func _record_by_id(records: Array, record_id: String) -> Dictionary:
	for record: Variant in records:
		if typeof(record) == TYPE_DICTIONARY and String(record.get("id", "")) == record_id:
			return record
	return {}


static func _load_catalog() -> Dictionary:
	if not _catalog_cache.is_empty():
		return _catalog_cache
	var source := FileAccess.get_file_as_string(CATALOG_PATH)
	if source.is_empty():
		push_error("ProceduralCarGenerator could not read %s." % CATALOG_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(source)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ProceduralCarGenerator catalog must contain a JSON object.")
		return {}
	_catalog_cache = parsed
	return _catalog_cache


static func _mix_seed(input_seed: int, car_type: String) -> int:
	var normalized := input_seed % RNG_MODULUS
	return ((normalized + int(TYPE_SALTS[car_type])) * 48271 + 69621) % RNG_MODULUS


static func _stream_seed(mixed_seed: int, stream_salt: int) -> int:
	return (mixed_seed + stream_salt) % RNG_MODULUS
