extends RefCounted
class_name ProceduralAvatarGenerator

## Vendored from GurisitosGames/procedural-2d at cb4ae73 for GURI-319.
## Deterministic, catalog-driven 64px portrait generation with independent trait domains.

const CATALOG_PATH := "res://data/vendor/procedural_2d/avatar_catalog.json"
const RNG_MODULUS := 2147483647
const TRAIT_FIELDS := [
	"face_shape", "skin_tone", "hair_style", "hair_color", "brow_style",
	"eye_style", "eye_color", "nose_style", "mouth_style", "facial_hair",
	"accessory", "marking", "outfit", "accent_palette", "facing",
]
const TRAIT_IDS := {
	"face_shape": ["oval", "square", "round", "long", "diamond", "heart"],
	"skin_tone": ["porcelain", "ivory", "golden", "olive", "amber", "sienna", "umber", "cocoa", "deep", "ebony"],
	"hair_style": ["bald", "buzz", "crop", "undercut", "side_part", "curls", "afro", "braids", "locs", "ponytail", "top_knot", "long", "mohawk", "quiff"],
	"hair_color": ["black", "espresso", "chestnut", "auburn", "copper", "golden_blond", "platinum", "ash", "silver", "blue_black"],
	"brow_style": ["straight", "arched", "thick", "soft", "angled", "unibrow"],
	"eye_style": ["round", "narrow", "wide", "hooded", "upturned", "downturned"],
	"eye_color": ["coffee", "hazel", "amber", "moss", "slate", "sky", "violet"],
	"nose_style": ["straight", "broad", "short", "angular", "hooked", "button"],
	"mouth_style": ["neutral", "smile", "wide", "serious", "grin", "smirk", "open"],
	"facial_hair": ["none", "stubble", "moustache", "goatee", "short_beard", "full_beard", "chinstrap"],
	"accessory": ["none", "glasses", "round_glasses", "earring", "headband", "hair_clip"],
	"marking": ["none", "freckles", "cheek_scar", "brow_scar", "beauty_spot", "vitiligo"],
	"outfit": ["crew", "jacket", "turtleneck", "hoodie", "collared", "armor"],
	"accent_palette": ["lagoon", "marigold", "berry", "moss", "cobalt", "orchid"],
	"facing": ["left", "right"],
}
const TRAIT_SALTS := {
	"face_shape": 104729, "skin_tone": 130363, "hair_style": 155921,
	"hair_color": 181081, "brow_style": 206369, "eye_style": 231779,
	"eye_color": 257053, "nose_style": 282481, "mouth_style": 307939,
	"facial_hair": 333449, "accessory": 358979, "marking": 384533,
	"outfit": 410117, "accent_palette": 435731, "facing": 461323,
}

static var _catalog_cache: Dictionary = {}


## Returns stable legal IDs for each overridable trait.
static func available_traits() -> Dictionary:
	return TRAIT_IDS.duplicate(true)


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
	return ""


## Generates a self-contained JSON-friendly avatar payload. Invalid requests return {}.
static func generate(input_seed: int, options: Dictionary = {}) -> Dictionary:
	if input_seed < 0:
		push_error("ProceduralAvatarGenerator rejected seed %s; seed must be non-negative." % input_seed)
		return {}
	var option_error := validate_options(options)
	if not option_error.is_empty():
		push_error("ProceduralAvatarGenerator rejected options: %s." % option_error)
		return {}
	var catalog_data := _load_catalog()
	if catalog_data.is_empty():
		return {}

	var traits := {}
	for field: String in TRAIT_FIELDS:
		var ids: Array = TRAIT_IDS[field]
		var generated_id: String
		if field in ["accessory", "marking"]:
			generated_id = _rare_choice(input_seed, field, ids, 4 if field == "accessory" else 5)
		else:
			generated_id = String(ids[_trait_roll(input_seed, field) % ids.size()])
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
		"schema_version": 1,
		"seed": input_seed,
		"sprite_size": {"width": 64, "height": 64},
		"facing": facing,
		"traits": traits,
		"palette": palette,
		"display_name": "%s %s / %s" % [
			String(traits["hair_style"]).capitalize(),
			String(traits["face_shape"]).capitalize(),
			String(traits["outfit"]).capitalize(),
		],
		"tags": tags,
	}


static func _rare_choice(input_seed: int, field: String, ids: Array, chance_in_sixteen: int) -> String:
	if _trait_roll(input_seed, field) % 16 >= chance_in_sixteen:
		return String(ids[0])
	return String(ids[1 + (_trait_roll(input_seed, field, 1) % (ids.size() - 1))])


static func _trait_roll(input_seed: int, field: String, stream_offset: int = 0) -> int:
	var normalized := input_seed % RNG_MODULUS
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
	_catalog_cache = parsed
	return _catalog_cache
