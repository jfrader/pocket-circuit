extends RefCounted
## Vendored from GurisitosGames/procedural-2d at f8eb038 for GURI-319.
class_name ProceduralAvatarSprites

## Hard-pixel 64x64 head-and-shoulders rendering from self-contained payloads only.

const IMAGE_SIZE := 64
const FACE_CENTER_X := 32
const FAR_EYE_CENTER_X := 24
const NEAR_EYE_CENTER_X := 40
const NOSE_CENTER_X := FACE_CENTER_X + 1
const MOUTH_CENTER_X := FACE_CENTER_X + 1
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
	_draw_ears(image, traits["face_shape"], colors)
	_draw_face(image, traits["face_shape"], colors)
	_draw_marking(image, traits["marking"], colors)
	_draw_brows(image, traits["face_shape"], traits["brow_style"], colors)
	_draw_eyes(image, traits["face_shape"], traits["eye_style"], colors)
	_draw_nose(image, traits["nose_style"], colors)
	_draw_mouth(image, traits["mouth_style"], colors)
	_draw_facial_hair(image, traits["face_shape"], traits["facial_hair"], colors)
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


static func _draw_ears(image: Image, shape: String, colors: Dictionary) -> void:
	var face_width := _face_span(shape, 27)
	var left_x := face_width.x - 4
	var right_x := face_width.y
	_rect(image, left_x, 24, 5, 10, colors["outline"])
	_rect(image, left_x + 2, 26, 3, 6, colors["skin_shadow"])
	_rect(image, right_x, 24, 5, 10, colors["outline"])
	_rect(image, right_x, 26, 3, 6, colors["skin_base"])
	_rect(image, right_x + 1, 28, 2, 2, colors["skin_shadow"])


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
			_span(image, y, maxi(inner_start, inner_end - 2), inner_end, colors["skin_shadow"])
		if y >= 21 and y <= 34:
			_set_pixel(image, inner_start, y, colors["skin_highlight"])
		if y in [16, 17] and inner_start + 3 <= inner_end:
			_span(image, y, inner_start + 2, inner_start + 3, colors["skin_rim"])


static func _face_span(shape: String, y: int) -> Vector2i:
	if y < 9 or y > 44:
		return Vector2i(1, 0)
	var left := 16
	var right := 49
	if y == 9:
		left = 24
		right = 40
	elif y == 10:
		left = 21
		right = 43
	elif y == 11:
		left = 18
		right = 46
	elif y <= 15:
		left = 16
		right = 48
	match shape:
		"square":
			if y < 16:
				pass
			elif y <= 36:
				left = 16
				right = 49
			elif y <= 40:
				left = 17
				right = 48
			elif y >= 41:
				left = 19
				right = 46
		"round":
			if y < 16:
				pass
			elif y <= 29:
				left = 15
				right = 50
			elif y <= 33:
				left = 16
				right = 49
			elif y <= 36:
				left = 17
				right = 48
			elif y <= 38:
				left = 18
				right = 47
			else:
				var round_taper := y - 39
				left = 20 + round_taper * 2
				right = 45 - round_taper * 2
		"long":
			if y < 12:
				pass
			elif y <= 34:
				left = 18
				right = 47
			elif y <= 37:
				left = 19
				right = 46
			elif y <= 40:
				left = 20
				right = 45
			else:
				var long_taper := y - 41
				left = 22 + long_taper * 2
				right = 43 - long_taper * 2
		"diamond":
			if y < 12:
				pass
			elif y <= 21:
				left = 17
				right = 48
			elif y <= 29:
				left = 15
				right = 50
			elif y <= 32:
				left = 16
				right = 49
			elif y <= 35:
				left = 18
				right = 47
			else:
				var diamond_taper := y - 36
				left = 20 + diamond_taper
				right = 45 - diamond_taper
		"heart":
			if y < 16:
				pass
			elif y <= 23:
				left = 15
				right = 50
			elif y <= 29:
				left = 16
				right = 49
			elif y <= 32:
				left = 18
				right = 47
			elif y <= 35:
				left = 19
				right = 46
			elif y <= 37:
				left = 20
				right = 45
			elif y <= 42:
				var heart_taper := y - 38
				left = 21 + heart_taper
				right = 44 - heart_taper
			elif y == 43:
				left = 27
				right = 38
			else:
				left = 29
				right = 36
		_:
			if y < 31:
				pass
			elif y <= 34:
				left = 17
				right = 48
			elif y <= 37:
				left = 18
				right = 47
			elif y <= 39:
				left = 19
				right = 46
			elif y == 40:
				left = 21
				right = 44
			elif y >= 41:
				var oval_taper := y - 41
				left = 22 + oval_taper * 2
				right = 43 - oval_taper * 2
	return Vector2i(left, right)


static func _draw_face_span(image: Image, shape: String, y: int, from_x: int, to_x: int, color: Color, inset: int = 2) -> void:
	var face := _face_span(shape, y)
	var left := maxi(from_x, face.x + inset)
	var right := mini(to_x, face.y - inset)
	if left <= right:
		_span(image, y, left, right, color)


static func _draw_face_rect(image: Image, shape: String, rect: Rect2i, color: Color, inset: int = 2) -> void:
	for y in range(rect.position.y, rect.end.y):
		_draw_face_span(image, shape, y, rect.position.x, rect.end.x - 1, color, inset)


static func _draw_face_pixel(image: Image, shape: String, x: int, y: int, color: Color, inset: int = 2) -> void:
	var face := _face_span(shape, y)
	if x >= face.x + inset and x <= face.y - inset:
		_set_pixel(image, x, y, color)


static func _draw_brows(image: Image, shape: String, style: String, colors: Dictionary) -> void:
	var color: Color = colors["hair_shadow"]
	_draw_brow(image, shape, FAR_EYE_CENTER_X, -1, style, color)
	_draw_brow(image, shape, NEAR_EYE_CENTER_X, 1, style, color)
	if style == "unibrow":
		_draw_face_span(image, shape, 23, 28, 36, color)


static func _draw_brow(image: Image, shape: String, center_x: int, outer_direction: int, style: String, color: Color) -> void:
	for index in range(8):
		var x := center_x + outer_direction * (4 - index)
		var y := 22
		match style:
			"arched":
				y = 23 if index in [0, 7] else (22 if index in [1, 6] else 21)
			"soft":
				y = 22 if index <= 3 else 23
			"angled":
				y = 23 if index <= 2 else (22 if index <= 4 else 21)
			"thick", "unibrow":
				y = 21
			_:
				pass
		_draw_face_pixel(image, shape, x, y, color)
		if style in ["thick", "unibrow"]:
			_draw_face_pixel(image, shape, x, y + 1, color)


static func _draw_eyes(image: Image, shape: String, style: String, colors: Dictionary) -> void:
	_draw_eye(image, shape, FAR_EYE_CENTER_X, -1, style, colors["iris"], colors)
	_draw_eye(image, shape, NEAR_EYE_CENTER_X, 1, style, colors["iris_light"], colors)


static func _draw_eye(image: Image, shape: String, center_x: int, outer_direction: int, style: String, iris: Color, colors: Dictionary) -> void:
	var white_top := 26
	var white_height := 3
	if style in ["narrow", "hooded"]:
		white_top = 27
		white_height = 2
	elif style == "wide":
		white_top = 25
		white_height = 4
	var white_left := center_x - 2
	var white_right := center_x + 2
	_draw_face_span(image, shape, white_top - 1, white_left, white_right, colors["eye_dark"])
	_draw_face_span(image, shape, white_top + white_height, white_left, white_right, colors["eye_dark"])
	for y in range(white_top, white_top + white_height):
		_draw_face_pixel(image, shape, white_left - 1, y, colors["eye_dark"])
		_draw_face_pixel(image, shape, white_right + 1, y, colors["eye_dark"])
	_draw_face_rect(image, shape, Rect2i(white_left, white_top, 5, white_height), colors["eye_white"])
	var outer_x := center_x + outer_direction * 2
	var inner_x := center_x - outer_direction * 2
	if style == "hooded":
		_draw_face_span(image, shape, white_top - 2, white_left - 1, white_right + 1, colors["skin_shadow"])
	elif style == "upturned":
		_draw_face_pixel(image, shape, outer_x, white_top - 1, colors["eye_white"])
		_draw_face_pixel(image, shape, inner_x, white_top + white_height - 1, colors["eye_dark"])
	elif style == "downturned":
		_draw_face_pixel(image, shape, outer_x, white_top + white_height, colors["eye_white"])
		_draw_face_pixel(image, shape, inner_x, white_top, colors["eye_dark"])
	_draw_face_rect(image, shape, Rect2i(center_x - 1, white_top, 2, white_height), iris)
	_draw_face_rect(image, shape, Rect2i(center_x, white_top + 1, 1, maxi(1, white_height - 1)), colors["eye_dark"])
	_draw_face_pixel(image, shape, center_x - 1, white_top, colors["eye_white"])


static func _draw_nose(image: Image, style: String, colors: Dictionary) -> void:
	var shadow: Color = colors["skin_shadow"]
	var light: Color = colors["skin_highlight"]
	match style:
		"broad":
			_rect(image, NOSE_CENTER_X - 1, 29, 2, 5, light)
			_rect(image, NOSE_CENTER_X - 3, 34, 7, 2, shadow)
			_set_pixel(image, NOSE_CENTER_X + 3, 33, shadow)
		"short":
			_rect(image, NOSE_CENTER_X - 1, 30, 2, 3, light)
			_rect(image, NOSE_CENTER_X - 2, 33, 5, 2, shadow)
		"angular":
			_rect(image, NOSE_CENTER_X - 1, 29, 2, 5, light)
			_rect(image, NOSE_CENTER_X + 1, 32, 2, 2, shadow)
			_rect(image, NOSE_CENTER_X, 34, 4, 2, shadow)
		"hooked":
			_rect(image, NOSE_CENTER_X - 1, 28, 2, 7, light)
			_rect(image, NOSE_CENTER_X + 1, 33, 3, 2, shadow)
			_rect(image, NOSE_CENTER_X, 35, 5, 1, shadow)
			_set_pixel(image, NOSE_CENTER_X + 4, 34, shadow)
		"button":
			_rect(image, NOSE_CENTER_X - 1, 32, 2, 2, light)
			_rect(image, NOSE_CENTER_X - 2, 34, 5, 2, shadow)
			_set_pixel(image, NOSE_CENTER_X + 3, 33, shadow)
		_:
			_rect(image, NOSE_CENTER_X - 1, 29, 2, 6, light)
			_rect(image, NOSE_CENTER_X, 34, 4, 2, shadow)


static func _draw_mouth(image: Image, style: String, colors: Dictionary) -> void:
	var mouth: Color = colors["mouth"]
	if _luminance_delta(mouth, colors["skin_base"]) < 0.1:
		var best_delta := _luminance_delta(mouth, colors["skin_base"])
		for candidate: Color in [colors["outline"], colors["skin_rim"]]:
			var candidate_delta := _luminance_delta(candidate, colors["skin_base"])
			if candidate_delta > best_delta:
				mouth = candidate
				best_delta = candidate_delta
	match style:
		"smile":
			_set_pixel(image, MOUTH_CENTER_X - 6, 39, mouth)
			_rect(image, MOUTH_CENTER_X - 5, 40, 11, 1, mouth)
			_set_pixel(image, MOUTH_CENTER_X + 6, 39, mouth)
		"wide":
			_rect(image, MOUTH_CENTER_X - 6, 40, 12, 1, mouth)
		"serious":
			_rect(image, MOUTH_CENTER_X - 5, 40, 11, 1, mouth)
			_rect(image, MOUTH_CENTER_X + 5, 39, 2, 1, mouth)
		"grin":
			_rect(image, MOUTH_CENTER_X - 6, 38, 13, 2, mouth)
			_rect(image, MOUTH_CENTER_X - 5, 40, 11, 1, mouth)
			_rect(image, MOUTH_CENTER_X - 4, 38, 9, 1, colors["eye_white"])
		"smirk":
			_rect(image, MOUTH_CENTER_X - 5, 40, 9, 1, mouth)
			_rect(image, MOUTH_CENTER_X + 3, 39, 4, 1, mouth)
		"open":
			_rect(image, MOUTH_CENTER_X - 4, 39, 9, 2, mouth)
			_rect(image, MOUTH_CENTER_X - 3, 41, 7, 1, mouth)
			_rect(image, MOUTH_CENTER_X - 2, 39, 5, 1, colors["eye_white"])
		_:
			_rect(image, MOUTH_CENTER_X - 5, 40, 11, 1, mouth)


static func _draw_facial_hair(image: Image, shape: String, style: String, colors: Dictionary) -> void:
	var hair: Color = colors["hair_base"]
	var hair_shadow: Color = colors["hair_shadow"]
	if _luminance_delta(hair, colors["skin_base"]) < 0.12:
		var best_delta := _luminance_delta(hair, colors["skin_base"])
		for candidate: Color in [hair_shadow, colors["hair_highlight"], colors["outline"]]:
			var candidate_delta := _luminance_delta(candidate, colors["skin_base"])
			if candidate_delta > best_delta:
				hair = candidate
				best_delta = candidate_delta
			if candidate_delta >= 0.12:
				break
		if hair == colors["hair_shadow"]:
			hair_shadow = colors["outline"]
		elif hair == colors["hair_highlight"]:
			hair_shadow = colors["hair_base"]
	var stubble: Color = colors["hair_shadow"]
	if _luminance_delta(stubble, colors["skin_base"]) < 0.12:
		var best_delta := _luminance_delta(stubble, colors["skin_base"])
		for candidate: Color in [colors["hair_base"], colors["hair_highlight"], colors["outline"]]:
			var candidate_delta := _luminance_delta(candidate, colors["skin_base"])
			if candidate_delta > best_delta:
				stubble = candidate
				best_delta = candidate_delta
	match style:
		"stubble":
			_draw_stubble(image, shape, stubble)
		"moustache":
			_draw_moustache(image, shape, hair, 6)
		"goatee":
			_draw_face_span(image, shape, 42, MOUTH_CENTER_X - 1, MOUTH_CENTER_X + 1, hair)
			_draw_face_span(image, shape, 43, MOUTH_CENTER_X - 2, MOUTH_CENTER_X + 2, hair)
			_draw_face_span(image, shape, 44, MOUTH_CENTER_X - 2, MOUTH_CENTER_X + 2, hair_shadow)
		"short_beard":
			_draw_moustache(image, shape, hair, 5)
			_draw_jaw_beard(image, shape, 37, 2, 9, hair, hair_shadow)
		"full_beard":
			_draw_moustache(image, shape, hair, 5)
			_draw_jaw_beard(image, shape, 35, 3, 12, hair, hair_shadow)
		"chinstrap":
			_draw_chinstrap(image, shape, hair, hair_shadow)
		_:
			pass


static func _draw_moustache(image: Image, shape: String, color: Color, half_width: int) -> void:
	_draw_face_span(image, shape, 36, MOUTH_CENTER_X - half_width, MOUTH_CENTER_X - 2, color)
	_draw_face_span(image, shape, 36, MOUTH_CENTER_X + 1, MOUTH_CENTER_X + half_width - 1, color)
	_draw_face_span(image, shape, 37, MOUTH_CENTER_X - half_width + 1, MOUTH_CENTER_X - 2, color)
	_draw_face_span(image, shape, 37, MOUTH_CENTER_X + 1, MOUTH_CENTER_X + half_width - 2, color)


static func _draw_jaw_beard(image: Image, shape: String, start_y: int, side_width: int, lower_half_width: int, hair: Color, shadow: Color) -> void:
	for y in range(start_y, 45):
		var face := _face_span(shape, y)
		var inner_left := face.x + 2
		var inner_right := face.y - 2
		if inner_left > inner_right:
			continue
		if y <= 41:
			var width := mini(side_width + maxi(0, y - 39), maxi(1, int((inner_right - inner_left + 1) / 2)))
			var left_end := inner_left + width - 1
			var right_start := inner_right - width + 1
			if y >= 38 and y <= 39:
				left_end = mini(left_end, MOUTH_CENTER_X - 7)
				right_start = maxi(right_start, MOUTH_CENTER_X + 7)
			elif y == 40:
				left_end = mini(left_end, MOUTH_CENTER_X - 7)
				right_start = maxi(right_start, MOUTH_CENTER_X + 6)
			elif y == 41:
				left_end = mini(left_end, MOUTH_CENTER_X - 4)
				right_start = maxi(right_start, MOUTH_CENTER_X + 4)
			_draw_face_span(image, shape, y, inner_left, left_end, hair)
			_draw_face_span(image, shape, y, right_start, inner_right, hair)
		else:
			var taper := y - 42
			var half_width := maxi(2, lower_half_width - taper * 2)
			_draw_face_span(
				image,
				shape,
				y,
				maxi(inner_left, MOUTH_CENTER_X - half_width),
				mini(inner_right, MOUTH_CENTER_X + half_width),
				shadow if y == 44 else hair
			)


static func _draw_chinstrap(image: Image, shape: String, hair: Color, shadow: Color) -> void:
	for y in range(35, 43):
		var face := _face_span(shape, y)
		var inner_left := face.x + 2
		var inner_right := face.y - 2
		var left_end := inner_left + 1
		var right_start := inner_right - 1
		if y >= 38 and y <= 39:
			left_end = mini(left_end, MOUTH_CENTER_X - 7)
			right_start = maxi(right_start, MOUTH_CENTER_X + 7)
		elif y == 40:
			left_end = mini(left_end, MOUTH_CENTER_X - 7)
			right_start = maxi(right_start, MOUTH_CENTER_X + 6)
		elif y == 41:
			left_end = mini(left_end, MOUTH_CENTER_X - 4)
			right_start = maxi(right_start, MOUTH_CENTER_X + 4)
		_draw_face_span(image, shape, y, inner_left, left_end, hair)
		_draw_face_span(image, shape, y, right_start, inner_right, hair)
	var chin := _face_span(shape, 43)
	_draw_face_span(image, shape, 43, chin.x + 2, chin.y - 2, hair)
	var tip := _face_span(shape, 44)
	_draw_face_span(image, shape, 44, tip.x + 2, tip.y - 2, shadow)


static func _draw_stubble(image: Image, shape: String, color: Color) -> void:
	for y in [35, 37, 42]:
		var face := _face_span(shape, y)
		var inner_left := face.x + 3
		var inner_right := face.y - 3
		if inner_left > inner_right:
			continue
		var third := maxi(2, int((inner_right - inner_left) / 3))
		for x in [inner_left, inner_left + third, inner_right - third, inner_right]:
			_draw_face_pixel(image, shape, x, y, color)
	_draw_face_pixel(image, shape, MOUTH_CENTER_X, 44, color)


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
		_core_rect(core, 48, 16, 7, 18, colors["hair_base"])
		_core_rect(core, 51, 31, 6, 9, colors["hair_shadow"])
		_core_rect(core, 54, 38, 4, 7, colors["hair_base"])
	elif style == "locs":
		for x in [12, 16, 48, 52]:
			_core_rect(core, x, 17, 4, 27 if x in [12, 52] else 23, colors["hair_base"] if x < 48 else colors["hair_shadow"])
	elif style == "braids":
		for x in [13, 17, 48, 52]:
			for y in range(18, 44, 4):
				_core_rect(core, x + (2 if int(y / 4) % 2 else 0), y, 3, 3, colors["hair_base"])
	if not core.is_empty():
		_draw_core(image, core, colors["outline"], 2)


static func _draw_hair_front(image: Image, style: String, colors: Dictionary) -> void:
	if style == "bald":
		_rect(image, 24, 11, 4, 1, colors["skin_rim"])
		_set_pixel(image, 19, 17, colors["skin_highlight"])
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
			_core_rect(core, 45, 14, 6, 8, colors["hair_base"])
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
			_outline_rect_thin(image, Rect2i(FAR_EYE_CENTER_X - 5, 24, 10, 8), colors["accent"])
			_outline_rect_thin(image, Rect2i(NEAR_EYE_CENTER_X - 5, 24, 10, 8), colors["accent"])
			_rect(image, 29, 27, 7, 1, colors["accent"])
		"round_glasses":
			_round_frame(image, Vector2i(FAR_EYE_CENTER_X, 28), colors["metal"])
			_round_frame(image, Vector2i(NEAR_EYE_CENTER_X, 28), colors["metal"])
			_rect(image, 29, 27, 7, 1, colors["metal"])
		"earring":
			_set_pixel(image, 50, 32, colors["metal"])
			_rect(image, 50, 33, 2, 2, colors["metal"])
			_rect(image, 51, 35, 2, 2, colors["accent_light"])
		"headband":
			_rect(image, 16, 15, 34, 2, colors["accent"])
			_rect(image, 20, 15, 26, 1, colors["accent_light"])
		"hair_clip":
			_rect(image, 44, 13, 5, 2, colors["accent_light"])
			_rect(image, 46, 12, 2, 4, colors["metal"])
		_:
			pass


static func _outline_rect_thin(image: Image, rect: Rect2i, color: Color) -> void:
	_span(image, rect.position.y, rect.position.x, rect.end.x - 1, color)
	_span(image, rect.end.y - 1, rect.position.x, rect.end.x - 1, color)
	_rect(image, rect.position.x, rect.position.y + 1, 1, rect.size.y - 2, color)
	_rect(image, rect.end.x - 1, rect.position.y + 1, 1, rect.size.y - 2, color)


static func _round_frame(image: Image, center: Vector2i, color: Color) -> void:
	_span(image, center.y - 4, center.x - 3, center.x + 3, color)
	_span(image, center.y + 4, center.x - 3, center.x + 3, color)
	_rect(image, center.x - 4, center.y - 3, 1, 7, color)
	_rect(image, center.x + 4, center.y - 3, 1, 7, color)


static func _draw_core(image: Image, core: Dictionary, outline: Color, radius: int) -> void:
	for key: Variant in core.keys():
		var point := Vector2i(int(key) % IMAGE_SIZE, int(key) / IMAGE_SIZE)
		for offset_y in range(-radius, radius + 1):
			for offset_x in range(-radius, radius + 1):
				if absi(offset_x) + absi(offset_y) > radius:
					continue
				var neighbor := point + Vector2i(offset_x, offset_y)
				if not core.has(_key(neighbor.x, neighbor.y)):
					_set_pixel(image, neighbor.x, neighbor.y, outline)
	for key: Variant in core.keys():
		var point := Vector2i(int(key) % IMAGE_SIZE, int(key) / IMAGE_SIZE)
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


static func _luminance_delta(first: Color, second: Color) -> float:
	return absf(
		(first.r - second.r) * 0.2126
		+ (first.g - second.g) * 0.7152
		+ (first.b - second.b) * 0.0722
	)


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
