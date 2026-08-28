extends RefCounted
class_name ProceduralAvatarSprites

## Vendored from GurisitosGames/procedural-2d at cb4ae73 for GURI-319.
## Hard-pixel 64x64 head-and-shoulders rendering from self-contained payloads only.

const IMAGE_SIZE := 64
const TOP_LEVEL_FIELDS := [
	"schema_version", "seed", "sprite_size", "facing", "traits", "palette",
	"display_name", "tags",
]
const TRAIT_FIELDS := [
	"face_shape", "skin_tone", "hair_style", "hair_color", "brow_style",
	"eye_style", "eye_color", "nose_style", "mouth_style", "facial_hair",
	"accessory", "marking", "outfit", "accent_palette",
]
const PALETTE_FIELDS := [
	"outline", "skin_shadow", "skin_base", "skin_highlight", "skin_rim",
	"hair_shadow", "hair_base", "hair_highlight", "eye_white", "eye_dark",
	"iris", "iris_light", "mouth", "outfit_shadow", "outfit_base",
	"outfit_light", "accent", "accent_light", "metal",
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
}


## Returns an empty string for a valid payload or the first precise field error.
static func validate_payload(payload: Dictionary) -> String:
	var error := _exact_fields_error(payload, "payload", TOP_LEVEL_FIELDS)
	if not error.is_empty():
		return error
	if not _is_integer_value(payload["schema_version"]) or int(payload["schema_version"]) != 1:
		return "payload.schema_version must be the integer 1"
	if not _is_integer_value(payload["seed"]) or int(payload["seed"]) < 0:
		return "payload.seed must be a non-negative int"
	if typeof(payload["sprite_size"]) != TYPE_DICTIONARY:
		return "payload.sprite_size must be a Dictionary"
	error = _exact_fields_error(payload["sprite_size"], "payload.sprite_size", ["width", "height"])
	if not error.is_empty():
		return error
	if (
		not _is_integer_value(payload["sprite_size"]["width"])
		or not _is_integer_value(payload["sprite_size"]["height"])
		or int(payload["sprite_size"]["width"]) != IMAGE_SIZE
		or int(payload["sprite_size"]["height"]) != IMAGE_SIZE
	):
		return "payload.sprite_size must be exactly 64 by 64"
	if typeof(payload["facing"]) != TYPE_STRING or String(payload["facing"]) not in ["left", "right"]:
		return "payload.facing must be 'left' or 'right'"
	if typeof(payload["traits"]) != TYPE_DICTIONARY:
		return "payload.traits must be a Dictionary"
	error = _exact_fields_error(payload["traits"], "payload.traits", TRAIT_FIELDS)
	if not error.is_empty():
		return error
	for field: String in TRAIT_FIELDS:
		if (
			typeof(payload["traits"][field]) != TYPE_STRING
			or not TRAIT_IDS[field].has(String(payload["traits"][field]))
		):
			return "payload.traits.%s must be a known %s ID" % [field, field]
	if typeof(payload["palette"]) != TYPE_DICTIONARY:
		return "payload.palette must be a Dictionary"
	error = _exact_fields_error(payload["palette"], "payload.palette", PALETTE_FIELDS)
	if not error.is_empty():
		return error
	for field: String in PALETTE_FIELDS:
		if typeof(payload["palette"][field]) != TYPE_STRING or not _is_hex_color(String(payload["palette"][field])):
			return "payload.palette.%s must be a #RRGGBB color" % field
	if typeof(payload["display_name"]) != TYPE_STRING or String(payload["display_name"]).is_empty():
		return "payload.display_name must be a non-empty String"
	if typeof(payload["tags"]) != TYPE_ARRAY or payload["tags"].size() < 6:
		return "payload.tags must contain at least six unique Strings"
	var seen_tags := {}
	for index in range(payload["tags"].size()):
		var tag: Variant = payload["tags"][index]
		if typeof(tag) != TYPE_STRING or String(tag).is_empty():
			return "payload.tags[%s] must be a non-empty String" % index
		if seen_tags.has(tag):
			return "payload.tags[%s] duplicates '%s'" % [index, tag]
		seen_tags[tag] = true
	return ""


## Renders a transparent, unfiltered RGBA8 portrait, or null for an invalid payload.
static func avatar_image(payload: Dictionary) -> Image:
	var error := validate_payload(payload)
	if not error.is_empty():
		push_error("ProceduralAvatarSprites rejected payload: %s." % error)
		return null
	var image := Image.create(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	_render_avatar(image, payload)
	if payload["facing"] == "left":
		image.flip_x()
	return image


## Creates a texture directly from the crisp payload-rendered image.
static func avatar_texture(payload: Dictionary) -> Texture2D:
	var image := avatar_image(payload)
	return ImageTexture.create_from_image(image) if image != null else null


## Saves a payload-rendered PNG and returns the Godot Error code.
static func save_avatar_png(payload: Dictionary, output_path: String) -> Error:
	if output_path.is_empty():
		push_error("ProceduralAvatarSprites requires a non-empty PNG output path.")
		return ERR_INVALID_PARAMETER
	var image := avatar_image(payload)
	if image == null:
		return ERR_INVALID_DATA
	var save_error := image.save_png(output_path)
	if save_error != OK:
		push_error("ProceduralAvatarSprites could not save %s: %s" % [output_path, error_string(save_error)])
	return save_error


static func _render_avatar(image: Image, payload: Dictionary) -> void:
	var traits: Dictionary = payload["traits"]
	var colors := _colors(payload["palette"])
	_draw_hair_back(image, traits["hair_style"], colors)
	_draw_outfit(image, traits["outfit"], colors)
	_draw_neck(image, colors)
	_draw_ears(image, colors)
	_draw_face(image, traits["face_shape"], colors)
	_draw_marking(image, traits["marking"], colors)
	_draw_brows(image, traits["brow_style"], colors)
	_draw_eyes(image, traits["eye_style"], colors)
	_draw_nose(image, traits["nose_style"], colors)
	_draw_mouth(image, traits["mouth_style"], colors)
	_draw_facial_hair(image, traits["facial_hair"], colors)
	_draw_hair_front(image, traits["hair_style"], colors)
	_draw_accessory(image, traits["accessory"], colors)


static func _draw_outfit(image: Image, style: String, colors: Dictionary) -> void:
	var core := {}
	for y in range(48, 60):
		var span: Vector2i
		if y == 48:
			span = Vector2i(24, 40)
		elif y == 49:
			span = Vector2i(19, 46)
		elif y == 50:
			span = Vector2i(15, 50)
		elif y == 51:
			span = Vector2i(12, 54)
		elif y == 52:
			span = Vector2i(10, 56)
		else:
			span = Vector2i(8, 57)
		for x in range(span.x, span.y + 1):
			var color: Color = colors["outfit_base"]
			if x >= 43:
				color = colors["outfit_shadow"]
			elif x <= 15 and y >= 53:
				color = colors["outfit_light"]
			_core_pixel(core, x, y, color)
	_draw_core(image, core, colors["outline"], 2)
	match style:
		"jacket":
			_triangle_lapel(image, 18, 48, 31, colors["outfit_light"])
			_triangle_lapel(image, 45, 48, 34, colors["outfit_shadow"])
			_rect(image, 31, 52, 3, 8, colors["accent"])
		"turtleneck":
			_rect(image, 24, 47, 18, 7, colors["outfit_shadow"])
			_rect(image, 26, 48, 14, 2, colors["outfit_light"])
		"hoodie":
			_rect(image, 15, 49, 6, 10, colors["outfit_shadow"])
			_rect(image, 45, 49, 7, 10, colors["outfit_shadow"])
			_rect(image, 29, 51, 2, 9, colors["accent_light"])
			_rect(image, 36, 51, 2, 9, colors["accent"])
		"collared":
			_triangle_lapel(image, 21, 47, 31, colors["accent_light"])
			_triangle_lapel(image, 44, 47, 35, colors["accent"])
			_rect(image, 32, 52, 2, 8, colors["outfit_shadow"])
		"armor":
			_rect(image, 11, 53, 12, 3, colors["metal"])
			_rect(image, 45, 53, 11, 3, colors["outfit_shadow"])
			_rect(image, 28, 52, 10, 3, colors["accent"])
			_rect(image, 31, 55, 4, 4, colors["metal"])
		_:
			_rect(image, 12, 54, 5, 2, colors["accent"])
			_rect(image, 18, 54, 8, 2, colors["outfit_light"])


static func _triangle_lapel(image: Image, outside_x: int, top_y: int, inside_x: int, color: Color) -> void:
	var direction := 1 if outside_x < inside_x else -1
	for row in range(8):
		var start := outside_x + direction * row
		var end := inside_x
		for x in range(mini(start, end), maxi(start, end) + 1):
			_set_pixel(image, x, top_y + row, color)


static func _draw_neck(image: Image, colors: Dictionary) -> void:
	var core := {}
	for y in range(40, 51):
		for x in range(27, 41):
			var color: Color = colors["skin_base"]
			if x >= 36:
				color = colors["skin_shadow"]
			elif x <= 29:
				color = colors["skin_highlight"]
			_core_pixel(core, x, y, color)
	_draw_core(image, core, colors["outline"], 2)


static func _draw_ears(image: Image, colors: Dictionary) -> void:
	_rect(image, 13, 23, 6, 11, colors["outline"])
	_rect(image, 15, 25, 4, 7, colors["skin_shadow"])
	_rect(image, 46, 22, 6, 11, colors["outline"])
	_rect(image, 46, 24, 4, 7, colors["skin_base"])
	_rect(image, 48, 26, 2, 3, colors["skin_shadow"])


static func _draw_face(image: Image, shape: String, colors: Dictionary) -> void:
	for y in range(9, 45):
		var span := _face_span(shape, y)
		if span.x > span.y:
			continue
		_span(image, y, span.x, span.y, colors["outline"])
		if y < 11 or y > 42 or span.y - span.x < 6:
			continue
		var inner_start := span.x + 2
		var inner_end := span.y - 2
		_span(image, y, inner_start, inner_end, colors["skin_base"])
		if y >= 15 and y <= 39:
			_span(image, y, maxi(inner_start, inner_end - 8), inner_end, colors["skin_shadow"])
		if y >= 13 and y <= 32:
			_span(image, y, inner_start, mini(inner_start + 3, inner_end), colors["skin_highlight"])
		if y in [13, 14, 18, 19] and inner_start + 5 <= inner_end:
			_span(image, y, inner_start + 2, inner_start + 5, colors["skin_rim"])
	# A deliberate near-cheek plane sells the three-quarter turn.
	_rect(image, 39, 28, 5, 8, colors["skin_shadow"])
	_rect(image, 18, 31, 3, 5, colors["skin_highlight"])


static func _face_span(shape: String, y: int) -> Vector2i:
	if y < 9 or y > 44:
		return Vector2i(1, 0)
	var left := 18
	var right := 48
	if y <= 11:
		left = 23 - (y - 9) * 2
		right = 41 + (y - 9) * 2
	elif y <= 16:
		left = 18 - mini(y - 12, 2)
		right = 46 + mini(y - 12, 2)
	elif y >= 36:
		var taper := y - 35
		left = 17 + taper
		right = 49 - taper
	match shape:
		"square":
			if y >= 16 and y <= 39:
				left = 16
				right = 49
			if y >= 40:
				left = 19
				right = 46
		"round":
			if y >= 16 and y <= 31:
				left = 15
				right = 49
			if y >= 32:
				left += 1
				right -= 1
		"long":
			left += 2
			right -= 1
			if y >= 36:
				left -= 1
				right += 1
		"diamond":
			if y <= 16:
				left += 2
				right -= 2
			elif y <= 30:
				left = 15
				right = 50
			elif y >= 34:
				left += 2
				right -= 2
		"heart":
			if y <= 23:
				left -= 1
				right += 1
			elif y >= 31:
				left += 2
				right -= 2
		_:
			pass
	return Vector2i(left, right)


static func _draw_brows(image: Image, style: String, colors: Dictionary) -> void:
	var color: Color = colors["hair_shadow"]
	var thickness := 2 if style == "thick" else 1
	match style:
		"arched":
			_rect(image, 21, 23, 2, 1, color); _rect(image, 23, 22, 5, thickness, color)
			_rect(image, 36, 22, 5, thickness, color); _rect(image, 41, 23, 3, 1, color)
		"soft":
			_rect(image, 21, 23, 4, 1, color); _rect(image, 25, 24, 3, 1, color)
			_rect(image, 36, 24, 3, 1, color); _rect(image, 39, 23, 5, 1, color)
		"angled":
			_rect(image, 21, 24, 3, thickness, color); _rect(image, 24, 22, 5, thickness, color)
			_rect(image, 36, 22, 5, thickness, color); _rect(image, 41, 24, 3, thickness, color)
		"unibrow":
			_rect(image, 21, 22, 23, 2, color)
		_:
			_rect(image, 21, 23, 7, thickness, color); _rect(image, 36, 23, 8, thickness, color)


static func _draw_eyes(image: Image, style: String, colors: Dictionary) -> void:
	var far_rect := Rect2i(22, 26, 6, 4)
	var near_rect := Rect2i(36, 26, 8, 4)
	if style == "narrow":
		far_rect = Rect2i(22, 27, 6, 2); near_rect = Rect2i(36, 27, 8, 2)
	elif style == "wide":
		far_rect = Rect2i(21, 26, 7, 5); near_rect = Rect2i(36, 25, 8, 6)
	elif style == "hooded":
		_rect(image, 21, 25, 8, 2, colors["skin_shadow"])
		_rect(image, 35, 25, 10, 2, colors["skin_shadow"])
	elif style == "upturned":
		_rect(image, 20, 27, 2, 1, colors["eye_dark"])
		_rect(image, 44, 25, 2, 1, colors["eye_dark"])
	elif style == "downturned":
		far_rect.position.y += 1
		near_rect.position.y += 1
		_rect(image, 20, 26, 2, 1, colors["eye_dark"])
		_rect(image, 44, 29, 2, 1, colors["eye_dark"])
	_rect(image, far_rect.position.x, far_rect.position.y, far_rect.size.x, far_rect.size.y, colors["eye_white"])
	_rect(image, near_rect.position.x, near_rect.position.y, near_rect.size.x, near_rect.size.y, colors["eye_white"])
	_rect(image, far_rect.position.x + 3, far_rect.position.y, 2, far_rect.size.y, colors["iris"])
	_rect(image, near_rect.position.x + 2, near_rect.position.y, 3, near_rect.size.y, colors["iris_light"])
	_rect(image, far_rect.position.x + 4, far_rect.position.y + 1, 1, maxi(1, far_rect.size.y - 1), colors["eye_dark"])
	_rect(image, near_rect.position.x + 3, near_rect.position.y + 1, 2, maxi(1, near_rect.size.y - 1), colors["eye_dark"])
	_set_pixel(image, near_rect.position.x + 2, near_rect.position.y, colors["eye_white"])


static func _draw_nose(image: Image, style: String, colors: Dictionary) -> void:
	var shadow: Color = colors["skin_shadow"]
	var light: Color = colors["skin_highlight"]
	match style:
		"broad":
			_rect(image, 34, 29, 2, 6, light); _rect(image, 36, 34, 7, 2, shadow); _rect(image, 41, 33, 2, 2, shadow)
		"short":
			_rect(image, 35, 30, 2, 4, light); _rect(image, 37, 33, 4, 2, shadow)
		"angular":
			_rect(image, 35, 29, 2, 5, light); _rect(image, 37, 33, 2, 2, shadow); _rect(image, 39, 34, 3, 2, shadow)
		"hooked":
			_rect(image, 35, 28, 2, 7, light); _rect(image, 37, 33, 3, 2, shadow); _rect(image, 39, 34, 4, 2, shadow); _set_pixel(image, 42, 33, shadow)
		"button":
			_rect(image, 36, 32, 2, 2, light); _rect(image, 37, 34, 4, 2, shadow); _set_pixel(image, 41, 33, shadow)
		_:
			_rect(image, 35, 29, 2, 6, light); _rect(image, 37, 34, 4, 2, shadow)


static func _draw_mouth(image: Image, style: String, colors: Dictionary) -> void:
	var mouth: Color = colors["mouth"]
	match style:
		"smile":
			_set_pixel(image, 30, 38, mouth); _rect(image, 31, 39, 9, 2, mouth); _set_pixel(image, 40, 38, mouth)
		"wide":
			_rect(image, 29, 39, 13, 2, mouth)
		"serious":
			_rect(image, 30, 40, 10, 2, mouth); _rect(image, 40, 39, 2, 1, mouth)
		"grin":
			_rect(image, 30, 38, 11, 2, mouth); _rect(image, 32, 38, 7, 1, colors["eye_white"]); _rect(image, 32, 40, 7, 1, mouth)
		"smirk":
			_rect(image, 30, 40, 8, 2, mouth); _rect(image, 38, 39, 4, 2, mouth)
		"open":
			_rect(image, 31, 38, 10, 4, mouth); _rect(image, 33, 39, 6, 1, colors["eye_white"])
		_:
			_rect(image, 30, 39, 11, 2, mouth)


static func _draw_facial_hair(image: Image, style: String, colors: Dictionary) -> void:
	var hair: Color = colors["hair_base"]
	match style:
		"stubble":
			for point in [Vector2i(24, 36), Vector2i(28, 38), Vector2i(43, 37), Vector2i(23, 40), Vector2i(27, 43), Vector2i(32, 44), Vector2i(38, 43), Vector2i(43, 41)]:
				_set_pixel(image, point.x, point.y, colors["hair_shadow"])
		"moustache":
			# Broad tapered wings; never a narrow centered toothbrush block.
			_rect(image, 27, 37, 5, 2, hair); _rect(image, 39, 37, 5, 2, hair)
			_rect(image, 29, 39, 4, 1, hair); _rect(image, 38, 39, 4, 1, hair)
		"goatee":
			_rect(image, 29, 37, 4, 2, hair); _rect(image, 39, 37, 4, 2, hair)
			_rect(image, 34, 41, 5, 5, hair)
		"short_beard":
			_rect(image, 20, 35, 4, 7, hair); _rect(image, 42, 34, 4, 8, hair)
			_rect(image, 24, 42, 18, 4, hair); _rect(image, 27, 38, 5, 2, hair); _rect(image, 39, 38, 4, 2, hair)
		"full_beard":
			_rect(image, 19, 33, 5, 10, hair); _rect(image, 42, 33, 5, 10, hair)
			_rect(image, 23, 41, 20, 7, hair); _rect(image, 28, 37, 5, 2, hair); _rect(image, 39, 37, 5, 2, hair)
		"chinstrap":
			_rect(image, 19, 35, 3, 8, hair); _rect(image, 44, 34, 3, 9, hair); _rect(image, 22, 43, 22, 3, hair)
		_:
			pass


static func _draw_marking(image: Image, style: String, colors: Dictionary) -> void:
	match style:
		"freckles":
			for point in [Vector2i(21, 32), Vector2i(24, 34), Vector2i(27, 33), Vector2i(42, 32), Vector2i(44, 34)]:
				_set_pixel(image, point.x, point.y, colors["skin_shadow"])
		"cheek_scar":
			_rect(image, 42, 31, 2, 7, colors["skin_rim"]); _rect(image, 44, 32, 1, 5, colors["skin_shadow"])
		"brow_scar":
			_rect(image, 24, 20, 2, 6, colors["skin_rim"])
		"beauty_spot":
			_rect(image, 41, 36, 2, 2, colors["hair_shadow"])
		"vitiligo":
			_rect(image, 18, 28, 4, 6, colors["skin_highlight"]); _rect(image, 21, 31, 3, 4, colors["skin_rim"])
		_:
			pass


static func _draw_hair_back(image: Image, style: String, colors: Dictionary) -> void:
	var core := {}
	if style == "long":
		_core_rect(core, 11, 13, 8, 34, colors["hair_base"])
		_core_rect(core, 45, 12, 8, 36, colors["hair_shadow"])
		_core_rect(core, 14, 42, 36, 6, colors["hair_base"])
	elif style == "ponytail":
		_core_rect(core, 48, 16, 8, 22, colors["hair_base"])
		_core_rect(core, 52, 35, 7, 10, colors["hair_shadow"])
		_core_rect(core, 55, 42, 4, 6, colors["hair_base"])
	elif style == "locs":
		for x in [12, 16, 48, 52]:
			_core_rect(core, x, 17, 4, 27 if x in [12, 52] else 23, colors["hair_base"] if x < 48 else colors["hair_shadow"])
	elif style == "braids":
		for x in [13, 17, 48, 52]:
			for y in range(18, 44, 4):
				_core_rect(core, x + (2 if floori(float(y) / 4.0) % 2 else 0), y, 3, 3, colors["hair_base"])
	if not core.is_empty():
		_draw_core(image, core, colors["outline"], 2)


static func _draw_hair_front(image: Image, style: String, colors: Dictionary) -> void:
	if style == "bald":
		_rect(image, 23, 11, 9, 2, colors["skin_rim"])
		_rect(image, 18, 15, 3, 2, colors["skin_highlight"])
		return
	var core := {}
	match style:
		"buzz":
			_core_rect(core, 19, 9, 25, 5, colors["hair_base"])
			_core_rect(core, 17, 12, 4, 8, colors["hair_shadow"])
			_core_rect(core, 43, 12, 5, 8, colors["hair_shadow"])
			_core_rect(core, 23, 10, 8, 1, colors["hair_highlight"])
		"crop":
			_core_rect(core, 17, 8, 31, 8, colors["hair_base"])
			_core_rect(core, 20, 5, 9, 5, colors["hair_base"])
			_core_rect(core, 31, 6, 12, 4, colors["hair_base"])
			_core_rect(core, 21, 7, 15, 2, colors["hair_highlight"])
		"undercut":
			_core_rect(core, 17, 12, 5, 9, colors["hair_shadow"])
			_core_rect(core, 18, 7, 29, 7, colors["hair_base"])
			_core_rect(core, 25, 4, 22, 6, colors["hair_base"])
			_core_rect(core, 29, 5, 14, 2, colors["hair_highlight"])
		"side_part":
			_core_rect(core, 17, 8, 31, 8, colors["hair_base"])
			_core_rect(core, 16, 13, 7, 8, colors["hair_shadow"])
			_core_rect(core, 22, 6, 25, 4, colors["hair_base"])
			_core_rect(core, 23, 7, 3, 7, colors["hair_highlight"])
			_core_rect(core, 28, 7, 15, 2, colors["hair_highlight"])
		"curls":
			for blob in [Rect2i(15, 8, 8, 8), Rect2i(20, 4, 9, 9), Rect2i(27, 3, 10, 10), Rect2i(35, 5, 9, 9), Rect2i(42, 9, 7, 9), Rect2i(14, 15, 7, 7)]:
				_core_rect(core, blob.position.x, blob.position.y, blob.size.x, blob.size.y, colors["hair_base"])
			_core_rect(core, 22, 6, 4, 3, colors["hair_highlight"])
			_core_rect(core, 31, 4, 4, 3, colors["hair_highlight"])
		"afro":
			for blob in [Rect2i(10, 11, 9, 14), Rect2i(13, 7, 12, 14), Rect2i(20, 4, 13, 14), Rect2i(29, 4, 13, 14), Rect2i(39, 7, 12, 15), Rect2i(46, 12, 7, 13)]:
				_core_rect(core, blob.position.x, blob.position.y, blob.size.x, blob.size.y, colors["hair_base"])
			_core_rect(core, 17, 6, 6, 4, colors["hair_highlight"])
			_core_rect(core, 27, 5, 6, 3, colors["hair_highlight"])
		"braids":
			_core_rect(core, 16, 8, 33, 11, colors["hair_base"])
			for x in range(19, 47, 6):
				_core_rect(core, x, 7, 2, 12, colors["hair_highlight"])
		"locs":
			_core_rect(core, 14, 7, 36, 13, colors["hair_base"])
			for x in [17, 24, 31, 38, 45]:
				_core_rect(core, x, 6, 3, 15, colors["hair_highlight"] if x in [24, 38] else colors["hair_shadow"])
		"ponytail":
			_core_rect(core, 17, 8, 31, 9, colors["hair_base"])
			_core_rect(core, 16, 14, 6, 8, colors["hair_shadow"])
			_core_rect(core, 25, 7, 20, 3, colors["hair_highlight"])
		"top_knot":
			_core_rect(core, 17, 9, 31, 9, colors["hair_base"])
			_core_rect(core, 27, 5, 13, 8, colors["hair_base"])
			_core_rect(core, 30, 4, 8, 3, colors["hair_highlight"])
		"long":
			_core_rect(core, 16, 7, 34, 11, colors["hair_base"])
			_core_rect(core, 15, 14, 7, 17, colors["hair_base"])
			_core_rect(core, 45, 13, 7, 18, colors["hair_shadow"])
			_core_rect(core, 23, 7, 18, 3, colors["hair_highlight"])
		"mohawk":
			_core_rect(core, 28, 3, 10, 14, colors["hair_base"])
			_core_rect(core, 18, 14, 30, 5, colors["hair_shadow"])
			_core_rect(core, 31, 4, 4, 8, colors["hair_highlight"])
		"quiff":
			_core_rect(core, 17, 11, 31, 8, colors["hair_base"])
			_core_rect(core, 24, 6, 24, 8, colors["hair_base"])
			_core_rect(core, 38, 3, 12, 7, colors["hair_base"])
			_core_rect(core, 28, 7, 17, 3, colors["hair_highlight"])
	_draw_core(image, core, colors["outline"], 2)


static func _draw_accessory(image: Image, style: String, colors: Dictionary) -> void:
	match style:
		"glasses":
			_outline_rect(image, Rect2i(19, 24, 11, 8), colors["accent"])
			_outline_rect(image, Rect2i(34, 24, 12, 8), colors["accent"])
			_rect(image, 30, 26, 5, 2, colors["accent"])
		"round_glasses":
			_round_frame(image, Vector2i(25, 28), colors["metal"])
			_round_frame(image, Vector2i(40, 28), colors["metal"])
			_rect(image, 30, 27, 5, 2, colors["metal"])
		"earring":
			_rect(image, 49, 31, 3, 3, colors["metal"]); _rect(image, 50, 34, 3, 4, colors["accent_light"])
		"headband":
			_rect(image, 14, 15, 38, 4, colors["accent"]); _rect(image, 17, 15, 29, 1, colors["accent_light"])
		"hair_clip":
			_rect(image, 43, 13, 7, 3, colors["accent_light"]); _rect(image, 45, 12, 3, 5, colors["metal"])
		_:
			pass


static func _outline_rect(image: Image, rect: Rect2i, color: Color) -> void:
	_rect(image, rect.position.x, rect.position.y, rect.size.x, 2, color)
	_rect(image, rect.position.x, rect.end.y - 2, rect.size.x, 2, color)
	_rect(image, rect.position.x, rect.position.y, 2, rect.size.y, color)
	_rect(image, rect.end.x - 2, rect.position.y, 2, rect.size.y, color)


static func _round_frame(image: Image, center: Vector2i, color: Color) -> void:
	_rect(image, center.x - 4, center.y - 4, 8, 2, color)
	_rect(image, center.x - 4, center.y + 3, 8, 2, color)
	_rect(image, center.x - 5, center.y - 3, 2, 7, color)
	_rect(image, center.x + 3, center.y - 3, 2, 7, color)


static func _draw_core(image: Image, core: Dictionary, outline: Color, radius: int) -> void:
	for key: Variant in core.keys():
		var point := Vector2i(int(key) % IMAGE_SIZE, floori(float(int(key)) / float(IMAGE_SIZE)))
		for offset_y in range(-radius, radius + 1):
			for offset_x in range(-radius, radius + 1):
				if absi(offset_x) + absi(offset_y) > radius:
					continue
				var neighbor := point + Vector2i(offset_x, offset_y)
				if not core.has(_key(neighbor.x, neighbor.y)):
					_set_pixel(image, neighbor.x, neighbor.y, outline)
	for key: Variant in core.keys():
		var point := Vector2i(int(key) % IMAGE_SIZE, floori(float(int(key)) / float(IMAGE_SIZE)))
		_set_pixel(image, point.x, point.y, core[key])


static func _core_rect(core: Dictionary, x: int, y: int, width: int, height: int, color: Color) -> void:
	for py in range(y, y + height):
		for px in range(x, x + width):
			_core_pixel(core, px, py, color)


static func _core_pixel(core: Dictionary, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < IMAGE_SIZE and y >= 0 and y < IMAGE_SIZE:
		core[_key(x, y)] = color


static func _span(image: Image, y: int, from_x: int, to_x: int, color: Color) -> void:
	for x in range(from_x, to_x + 1):
		_set_pixel(image, x, y, color)


static func _rect(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	for py in range(y, y + height):
		for px in range(x, x + width):
			_set_pixel(image, px, py, color)


static func _set_pixel(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < IMAGE_SIZE and y >= 0 and y < IMAGE_SIZE:
		image.set_pixel(x, y, color)


static func _key(x: int, y: int) -> int:
	return y * IMAGE_SIZE + x


static func _colors(palette: Dictionary) -> Dictionary:
	var result := {}
	for field: String in PALETTE_FIELDS:
		result[field] = Color(palette[field])
	return result


static func _exact_fields_error(value: Dictionary, path: String, fields: Array) -> String:
	for field: Variant in fields:
		if not value.has(field):
			return "%s.%s is required" % [path, field]
	for key: Variant in value.keys():
		if not fields.has(key):
			return "%s.%s is not supported" % [path, key]
	return ""


static func _is_integer_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return not is_nan(number) and not is_inf(number) and number == floor(number)


static func _is_hex_color(value: String) -> bool:
	if value.length() != 7 or value[0] != "#":
		return false
	for index in range(1, 7):
		if not "0123456789abcdefABCDEF".contains(value[index]):
			return false
	return true
