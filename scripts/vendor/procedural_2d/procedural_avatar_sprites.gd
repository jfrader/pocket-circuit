extends RefCounted
class_name ProceduralAvatarSprites

const Art = preload("res://scripts/vendor/procedural_2d/procedural_avatar_art.gd")
const Generator = preload("res://scripts/vendor/procedural_2d/procedural_avatar_generator.gd")
const IMAGE_SIZE := 64
const TOP_LEVEL_FIELDS := ["schema_version", "seed", "sprite_size", "facing", "traits", "palette", "display_name", "tags"]
const TRAIT_FIELDS := ["gender", "face_shape", "skin_tone", "hair_style", "hair_color", "brow_style", "eye_style", "eye_color", "nose_style", "mouth_style", "facial_hair", "accessory", "marking", "outfit", "accent_palette"]
const PALETTE_FIELDS := ["outline", "skin_shadow", "skin_base", "skin_highlight", "skin_rim", "hair_shadow", "hair_base", "hair_highlight", "eye_white", "eye_dark", "iris", "iris_light", "mouth", "outfit_shadow", "outfit_base", "outfit_light", "accent", "accent_light", "metal"]
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
}


static func validate_payload(payload: Dictionary) -> String:
	var error := _exact_fields_error(payload, "payload", TOP_LEVEL_FIELDS)
	if not error.is_empty():
		return error
	if not _is_integer_value(payload["schema_version"]) or int(payload["schema_version"]) not in [1,2]:
		return "payload.schema_version must be the integer 1 or 2"
	if not _is_integer_value(payload["seed"]) or int(payload["seed"]) < 0:
		return "payload.seed must be a non-negative int"
	if typeof(payload["sprite_size"]) != TYPE_DICTIONARY:
		return "payload.sprite_size must be a Dictionary"
	error = _exact_fields_error(payload["sprite_size"], "payload.sprite_size", ["width", "height"])
	if not error.is_empty():
		return error
	for axis in ["width", "height"]:
		if not _is_integer_value(payload["sprite_size"][axis]) or int(payload["sprite_size"][axis]) != IMAGE_SIZE:
			return "payload.sprite_size must be exactly 64 by 64"
	if typeof(payload["facing"]) != TYPE_STRING or payload["facing"] not in ["left", "right"]:
		return "payload.facing must be 'left' or 'right'"
	if typeof(payload["traits"]) != TYPE_DICTIONARY:
		return "payload.traits must be a Dictionary"
	var fields := TRAIT_FIELDS.duplicate()
	if int(payload["schema_version"]) == 1:
		fields.erase("gender")
	error = _exact_fields_error(payload["traits"], "payload.traits", fields)
	if not error.is_empty():
		return error
	for field in fields:
		if typeof(payload["traits"][field]) != TYPE_STRING or not TRAIT_IDS[field].has(payload["traits"][field]):
			return "payload.traits.%s must be a known %s ID" % [field, field]
	if int(payload["schema_version"]) == 2:
		var gender: String = payload["traits"]["gender"]
		if gender == "female" and payload["traits"]["facial_hair"] != "none":
			return "payload.traits.facial_hair must be none for female"
		if not Generator.HAIR_BY_GENDER[gender].has(payload["traits"]["hair_style"]):
			return "payload.traits.hair_style is not compatible with %s" % gender
	if typeof(payload["palette"]) != TYPE_DICTIONARY:
		return "payload.palette must be a Dictionary"
	error = _exact_fields_error(payload["palette"], "payload.palette", PALETTE_FIELDS)
	if not error.is_empty():
		return error
	for field in PALETTE_FIELDS:
		if typeof(payload["palette"][field]) != TYPE_STRING or not _is_hex_color(payload["palette"][field]):
			return "payload.palette.%s must be a #RRGGBB color" % field
	if typeof(payload["display_name"]) != TYPE_STRING or payload["display_name"].is_empty():
		return "payload.display_name must be a non-empty String"
	if typeof(payload["tags"]) != TYPE_ARRAY or payload["tags"].size() < 6:
		return "payload.tags must contain at least six unique Strings"
	var seen := {}
	for i in range(payload["tags"].size()):
		var tag: Variant = payload["tags"][i]
		if typeof(tag) != TYPE_STRING or tag.is_empty():
			return "payload.tags[%s] must be a non-empty String" % i
		if seen.has(tag):
			return "payload.tags[%s] duplicates '%s'" % [i, tag]
		seen[tag] = true
	return ""


## Both sizes use the new artwork. Scale 2 is the native 128px image.
static func avatar_image(payload: Dictionary, pixel_scale: int = 1) -> Image:
	var error := validate_payload(payload)
	if not error.is_empty():
		push_error("ProceduralAvatarSprites rejected payload: %s." % error)
		return null
	if pixel_scale not in [1, 2]:
		push_error("pixel_scale must be 1 (64px) or 2 (native 128px)")
		return null
	var renderer := Art.new()
	var image: Image = renderer.render(payload, pixel_scale == 2)["portrait"]
	if renderer.escaped_pixels:
		return null
	if pixel_scale == 1:
		var reduced := Image.create(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBA8)
		for y in range(IMAGE_SIZE):
			for x in range(IMAGE_SIZE):
				var rgb := Vector3.ZERO
				var alpha := 0.0
				for dy in range(2):
					for dx in range(2):
						var c := image.get_pixel(x*2+dx,y*2+dy)
						rgb += Vector3(c.r,c.g,c.b)*c.a
						alpha += c.a
				if alpha > 0:
					rgb /= alpha
				reduced.set_pixel(x,y,Color(rgb.x,rgb.y,rgb.z,alpha*0.25))
		if payload["facing"] == "left":
			reduced.flip_x()
		return reduced
	return image


static func avatar_texture(payload: Dictionary, pixel_scale: int = 1) -> Texture2D:
	var image := avatar_image(payload, pixel_scale)
	return ImageTexture.create_from_image(image) if image != null else null


static func save_avatar_png(payload: Dictionary, output_path: String, pixel_scale: int = 1) -> Error:
	if output_path.is_empty():
		push_error("ProceduralAvatarSprites requires a non-empty PNG output path.")
		return ERR_INVALID_PARAMETER
	var image := avatar_image(payload, pixel_scale)
	return image.save_png(output_path) if image != null else ERR_INVALID_DATA


static func _exact_fields_error(value: Dictionary, path: String, fields: Array) -> String:
	for field in fields:
		if not value.has(field):
			return "%s.%s is required" % [path, field]
	for key in value:
		if not fields.has(key):
			return "%s.%s is not supported" % [path, key]
	return ""


static func _is_integer_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	return not is_nan(value) and not is_inf(value) and value == floor(value)


static func _is_hex_color(value: String) -> bool:
	if value.length() != 7 or value[0] != "#":
		return false
	for i in range(1, 7):
		if not "0123456789abcdefABCDEF".contains(value[i]):
			return false
	return true
