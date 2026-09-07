extends RefCounted
class_name ProceduralAvatarGenerator

## Deterministic, catalog-driven portrait generation with independent trait domains.

const CATALOG_PATH := "res://data/avatars/avatar_catalog.json"
const RNG_MODULUS := 2147483647
const TRAIT_FIELDS := [
	"gender",
	"face_shape", "skin_tone", "hair_style", "hair_color", "brow_style",
	"eye_style", "eye_color", "nose_style", "mouth_style", "facial_hair",
	"accessory", "marking", "outfit", "accent_palette", "facing",
]
const TRAIT_IDS := {
	"gender": ["male", "female"],
	"face_shape": ["oval", "square", "round", "long", "diamond", "heart", "soft_square", "tapered"],
	"skin_tone": ["porcelain", "ivory", "golden", "olive", "amber", "sienna", "umber", "cocoa", "deep", "ebony"],
	"hair_style": ["bald", "buzz", "crop", "undercut", "side_part", "curls", "afro", "braids", "locs", "ponytail", "top_knot", "long", "mohawk", "quiff", "curtains", "bob", "wavy", "pixie", "slick_back", "messy_crop"],
	"hair_color": ["black", "espresso", "chestnut", "auburn", "copper", "golden_blond", "platinum", "ash", "silver", "blue_black"],
	"brow_style": ["straight", "arched", "thick", "soft", "angled", "unibrow"],
	"eye_style": ["round", "narrow", "wide", "hooded", "upturned", "downturned"],
	"eye_color": ["coffee", "hazel", "amber", "moss", "slate", "sky", "violet"],
	"nose_style": ["straight", "broad", "short", "angular", "hooked", "button"],
	"mouth_style": ["neutral", "smile", "wide", "serious", "grin", "smirk", "open", "closed_smile", "skeptical"],
	"facial_hair": ["none", "stubble", "moustache", "goatee", "short_beard", "full_beard", "chinstrap", "soul_patch", "heavy_stubble"],
	"accessory": ["none", "glasses", "round_glasses", "earring", "headband", "hair_clip", "stud", "aviators"],
	"marking": ["none", "freckles", "cheek_scar", "brow_scar", "beauty_spot", "vitiligo", "dimples", "smile_lines"],
	"outfit": ["crew", "jacket", "turtleneck", "hoodie", "collared", "armor", "polo", "cardigan", "blazer", "denim"],
	"accent_palette": ["lagoon", "marigold", "berry", "moss", "cobalt", "orchid"],
	"facing": ["left", "right"],
}
const TRAIT_SALTS := {
	"gender": 486187,
	"face_shape": 104729, "skin_tone": 130363, "hair_style": 155921,
	"hair_color": 181081, "brow_style": 206369, "eye_style": 231779,
	"eye_color": 257053, "nose_style": 282481, "mouth_style": 307939,
	"facial_hair": 333449, "accessory": 358979, "marking": 384533,
	"outfit": 410117, "accent_palette": 435731, "facing": 461323,
}

const HAIR_BY_GENDER := {
	"male": ["bald", "buzz", "crop", "undercut", "side_part", "curls", "afro", "braids", "locs", "ponytail", "top_knot", "mohawk", "quiff", "curtains", "slick_back", "messy_crop"],
	"female": ["bald", "buzz", "crop", "undercut", "side_part", "curls", "afro", "braids", "locs", "ponytail", "top_knot", "long", "mohawk", "curtains", "bob", "wavy", "pixie"],
}

static var _catalog_cache: Dictionary = {}


## Returns stable legal IDs for each overridable trait.
static func available_traits(gender: String = "") -> Dictionary:
	var traits := TRAIT_IDS.duplicate(true)
	if not gender.is_empty():
		if not HAIR_BY_GENDER.has(gender):
			push_error("gender must be male or female")
			return {}
		traits["hair_style"] = HAIR_BY_GENDER[gender].duplicate()
		if gender == "female":
			traits["facial_hair"] = ["none"]
	return traits


## Returns a deep copy of the source catalog.
static func catalog() -> Dictionary:
	var loaded := _load_catalog()
	return loaded.duplicate(true) if not loaded.is_empty() else {}


## Returns an empty string for valid partial options or the first field-specific error.
static func validate_options(options: Dictionary) -> String:
	for key: Variant in options.keys():
		if typeof(key) != TYPE_STRING:
			return "options keys must be Strings"
		var field := String(key)
		if field == "expression":
			field = "mouth_style"
		if not TRAIT_FIELDS.has(field):
			return "options.%s is not supported" % key
		if typeof(options[key]) != TYPE_STRING:
			return "options.%s must be a String" % key
		if not TRAIT_IDS[field].has(String(options[key])):
			return "options.%s must be a known %s ID" % [key, field]
	if options.has("mouth_style") and options.has("expression"):
		if String(options["mouth_style"]) != String(options["expression"]):
			return "options.mouth_style and options.expression must match when both are provided"
	if options.get("gender") == "female" and options.get("facial_hair", "none") != "none":
		return "options.facial_hair must be none for female"
	if options.has("gender") and options.has("hair_style") and not HAIR_BY_GENDER[options["gender"]].has(options["hair_style"]):
		return "options.hair_style is not compatible with %s" % options["gender"]
	if _compatible_genders(options).is_empty():
		return "options.hair_style and options.facial_hair have no compatible gender template"
	return ""


static func _compatible_genders(options: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for gender: String in TRAIT_IDS["gender"]:
		if options.has("gender") and options["gender"] != gender:
			continue
		if options.has("hair_style") and not HAIR_BY_GENDER[gender].has(options["hair_style"]):
			continue
		if gender == "female" and options.get("facial_hair", "none") != "none":
			continue
		result.append(gender)
	return result


## Generates a self-contained JSON-friendly avatar payload. Invalid requests return {}.
static func generate(seed: int, options: Dictionary = {}) -> Dictionary:
	if seed < 0:
		push_error("ProceduralAvatarGenerator rejected seed %s; seed must be non-negative." % seed)
		return {}
	var option_error := validate_options(options)
	if not option_error.is_empty():
		push_error("ProceduralAvatarGenerator rejected options: %s." % option_error)
		return {}
	var catalog_data := _load_catalog()
	if catalog_data.is_empty():
		return {}

	var genders := _compatible_genders(options)
	var gender := _weighted_choice(seed, "gender", genders, catalog_data.get("default_weights", {}).get("gender", {"male":1,"female":1}))
	var traits := {"gender": gender}
	for field: String in TRAIT_FIELDS:
		if field == "gender":
			continue
		var ids: Array = TRAIT_IDS[field]
		if field == "hair_style":
			ids = HAIR_BY_GENDER[gender]
		elif field == "facial_hair" and gender == "female":
			ids = ["none"]
		var generated_id: String
		if catalog_data.get("default_weights", {}).has(field):
			var weights: Dictionary = catalog_data["default_weights"][field]
			if field == "hair_style":
				weights = weights.duplicate()
				weights.merge(catalog_data.get("hair_weights_by_gender", {}).get(gender, {}), true)
			generated_id = _weighted_choice(seed, field, ids, weights)
		elif field in ["accessory", "marking"]:
			generated_id = _rare_choice(seed, field, ids, 4 if field == "accessory" else 5)
		else:
			generated_id = String(ids[_trait_roll(seed, field) % ids.size()])
		var option_key := field
		if field == "mouth_style" and options.has("expression") and not options.has("mouth_style"):
			option_key = "expression"
		traits[field] = String(options.get(option_key, generated_id))

	var skin := _record_by_id(catalog_data["skin_tones"], traits["skin_tone"])
	var hair := _record_by_id(catalog_data["hair_colors"], traits["hair_color"])
	var eyes := _record_by_id(catalog_data["eye_colors"], traits["eye_color"])
	var outfit := _record_by_id(catalog_data["outfits"], traits["outfit"])
	var accent := _record_by_id(catalog_data["accent_palettes"], traits["accent_palette"])
	if skin.is_empty() or hair.is_empty() or eyes.is_empty() or outfit.is_empty() or accent.is_empty():
		push_error("ProceduralAvatarGenerator catalog is missing a selected palette record.")
		return {}
	var skin_colors: Dictionary = skin["colors"]
	var hair_colors: Dictionary = hair["colors"]
	var eye_colors: Dictionary = eyes["colors"]
	var outfit_colors: Dictionary = outfit["colors"]
	var accent_colors: Dictionary = accent["colors"]
	var palette := {
		"outline": "#11151C",
		"skin_shadow": skin_colors["shadow"],
		"skin_base": skin_colors["base"],
		"skin_highlight": skin_colors["highlight"],
		"skin_rim": skin_colors["rim"],
		"hair_shadow": hair_colors["shadow"],
		"hair_base": hair_colors["base"],
		"hair_highlight": hair_colors["highlight"],
		"eye_white": "#F5F0E8",
		"eye_dark": "#17212A",
		"iris": eye_colors["iris"],
		"iris_light": eye_colors["light"],
		"mouth": "#783F49",
		"outfit_shadow": outfit_colors["shadow"],
		"outfit_base": outfit_colors["base"],
		"outfit_light": outfit_colors["light"],
		"accent": accent_colors["accent"],
		"accent_light": accent_colors["light"],
		"metal": "#C7D0D6",
	}
	var tags: Array[String] = [
		"gender:%s" % gender,
		"avatar", "portrait", "face:%s" % traits["face_shape"], "hair:%s" % traits["hair_style"],
		"outfit:%s" % traits["outfit"], "accent:%s" % traits["accent_palette"], "facing:%s" % traits["facing"],
	]
	if traits["accessory"] != "none":
		tags.append("accessory:%s" % traits["accessory"])
	if traits["marking"] != "none":
		tags.append("marking:%s" % traits["marking"])
	var facing: String = traits["facing"]
	traits.erase("facing")
	return {
		"schema_version": 2,
		"seed": seed,
		"sprite_size": {"width": 64, "height": 64},
		"facing": facing,
		"traits": traits,
		"palette": palette,
		"display_name": "%s / %s %s / %s" % [
			gender.capitalize(),
			String(traits["hair_style"]).capitalize(),
			String(traits["face_shape"]).capitalize(),
			String(traits["outfit"]).capitalize(),
		],
		"tags": tags,
	}


static func _weighted_choice(seed: int, field: String, ids: Array, weights: Dictionary) -> String:
	var total := 0
	for id in ids:
		total += int(weights[id])
	var roll := _trait_roll(seed, field) % total
	for id in ids:
		roll -= int(weights[id])
		if roll < 0:
			return String(id)
	return String(ids.back())


static func _rare_choice(seed: int, field: String, ids: Array, chance_in_sixteen: int) -> String:
	if _trait_roll(seed, field) % 16 >= chance_in_sixteen:
		return String(ids[0])
	return String(ids[1 + (_trait_roll(seed, field, 1) % (ids.size() - 1))])


static func _trait_roll(seed: int, field: String, stream_offset: int = 0) -> int:
	var normalized := seed % RNG_MODULUS
	var state := (normalized + int(TRAIT_SALTS[field]) + stream_offset * 104729) % RNG_MODULUS
	state = (state * 48271 + 69621) % RNG_MODULUS
	return (state * 40692) % RNG_MODULUS


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
		push_error("ProceduralAvatarGenerator could not read %s." % CATALOG_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(source)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ProceduralAvatarGenerator catalog must contain a JSON object.")
		return {}
	var defaults: Variant = parsed.get("default_weights", {})
	if typeof(defaults) != TYPE_DICTIONARY:
		push_error("avatar_catalog.default_weights must be a Dictionary")
		return {}
	for field in defaults:
		if not TRAIT_IDS.has(field) or typeof(defaults[field]) != TYPE_DICTIONARY:
			push_error("Invalid default-weight trait: %s" % field)
			return {}
		var weights: Dictionary = defaults[field]
		if weights.size() != TRAIT_IDS[field].size():
			push_error("Default weights must name every %s ID" % field)
			return {}
		for id in TRAIT_IDS[field]:
			var weight: Variant = weights.get(id, 0)
			if not _valid_weight(weight):
				push_error("Default weight %s.%s must be a positive integer" % [field,id])
				return {}
	var hair_defaults: Variant = parsed.get("hair_weights_by_gender", {})
	if typeof(hair_defaults) != TYPE_DICTIONARY:
		push_error("hair_weights_by_gender must be a Dictionary")
		return {}
	for gender in hair_defaults:
		if not HAIR_BY_GENDER.has(gender) or typeof(hair_defaults[gender]) != TYPE_DICTIONARY:
			push_error("Invalid hair-weight gender template")
			return {}
		for id in hair_defaults[gender]:
			if not HAIR_BY_GENDER[gender].has(id) or not _valid_weight(hair_defaults[gender][id]):
				push_error("Invalid %s hair weight: %s" % [gender,id])
				return {}
	_catalog_cache = parsed
	return _catalog_cache


static func _valid_weight(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value) == floor(float(value)) and float(value) >= 1 and float(value) <= 1000000
