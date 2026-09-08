extends RefCounted
class_name ProceduralCarSprites

## Payload-only, hard-pixel 48x64 top-down toy car rendering.

const IMAGE_WIDTH := 48
const IMAGE_HEIGHT := 64
const NativeArt = preload("res://scripts/vendor/procedural_2d/procedural_car_art.gd")
const TYPES := ["compact", "coupe", "muscle", "buggy"]
const PALETTE_IDS := [
	"candy_red", "marina_blue", "citrus_pop", "midnight_teal", "desert_sage", "plum_soda",
]
const REQUIRED_FIELDS := [
	"schema_version", "seed", "type", "sprite_size", "palette_id", "palette", "parts",
	"collision_bounds", "anchors", "display_name", "tags",
]
const ALLOWED_FIELDS := [
	"schema_version", "seed", "type", "sprite_size", "palette_id", "palette", "parts",
	"collision_bounds", "anchors", "handling", "display_name", "tags",
]
const PALETTE_FIELDS := [
	"outline", "shadow", "tire", "tire_highlight", "hub", "hub_light", "body_dark",
	"body_mid", "body_light", "accent", "glass_dark", "glass_mid", "glass_light",
	"headlight", "taillight", "trim",
]
const PART_IDS := {
	"hood": ["smooth", "twin_vents", "power_scoop", "flat", "dual_scoop", "ridged"],
	"cabin": ["bubble", "angular", "panoramic", "low", "notched", "fastback", "cage"],
	"bumpers": ["chrome", "sport", "utility", "slim", "wide", "pipe"],
	"wheels": ["classic", "mesh", "rugged", "spoke", "disc", "open", "beadlock"],
	"spoiler": ["none", "lip", "wing", "tall", "winged", "hoop"],
	"livery": ["solid", "center_stripe", "twin_stripe", "side_flash", "checker", "sunburst", "hood_stripe", "side_swoosh", "two_tone", "racing_stripe", "dust_kick", "hash_marks"],
}
const COLLISION_BOUNDS := {
	"compact": {"x": 10, "y": 6, "width": 28, "height": 52},
	"coupe": {"x": 9, "y": 5, "width": 30, "height": 54},
	"muscle": {"x": 8, "y": 6, "width": 32, "height": 52},
	"buggy": {"x": 5, "y": 5, "width": 38, "height": 54},
}
const ANCHORS := {
	"pivot": {"x": 24, "y": 32},
	"front": {"x": 24, "y": 5},
	"rear": {"x": 24, "y": 59},
	"driver": {"x": 21, "y": 32},
}
## Number of wheel-spin frames. Each frame advances the hub motif by 90°.
const WHEEL_FRAME_COUNT := 4
## Nominal travel in pixels between wheel-spin frames. A full rotation is four
## frames, so the nominal rolling circumference is 64px (≈ a 20px wheel).
const WHEEL_ROLL_DISTANCE := 16.0
## Canonical tyre family. Every car shares one rubber colour, one rim highlight,
## one hub colour, and one hub-light colour; only the bounding wheel size varies
## by car type. The hub motif varies per wheels part ID (see `_hub_offsets`) while
## the rubber ring and edge treatment stay identical everywhere. The palette tyre
## fields remain in the frozen payload contract for byte-compatibility but no
## longer drive tyre pixels.
const TYRE_OUTLINE := Color("#17151A")
const TYRE_RUBBER := Color("#25272C")
const TYRE_HIGHLIGHT := Color("#555B63")
const TYRE_HUB := Color("#BFC7CE")
const TYRE_HUB_LIGHT := Color("#EEF2F3")


## Returns an empty string for a valid self-contained car payload.
static func validate_payload(payload: Dictionary) -> String:
	for field in REQUIRED_FIELDS:
		if not payload.has(field):
			return "payload.%s is required" % field
	for key: Variant in payload.keys():
		if not ALLOWED_FIELDS.has(key):
			return "payload.%s is not supported" % key
	if not _is_integer_value(payload["schema_version"]) or int(payload["schema_version"]) != 1:
		return "payload.schema_version must be the integer 1"
	if not _is_integer_value(payload["seed"]) or int(payload["seed"]) < 0:
		return "payload.seed must be a non-negative int"
	if typeof(payload["type"]) != TYPE_STRING or not TYPES.has(String(payload["type"])):
		return "payload.type must be compact, coupe, muscle, or buggy"
	if typeof(payload["sprite_size"]) != TYPE_DICTIONARY:
		return "payload.sprite_size must be a Dictionary"
	var error := _exact_fields_error(payload["sprite_size"], "payload.sprite_size", ["width", "height"])
	if not error.is_empty():
		return error
	if (
		not _is_integer_value(payload["sprite_size"]["width"])
		or not _is_integer_value(payload["sprite_size"]["height"])
		or int(payload["sprite_size"]["width"]) != IMAGE_WIDTH
		or int(payload["sprite_size"]["height"]) != IMAGE_HEIGHT
	):
		return "payload.sprite_size must be exactly 48 by 64"
	if typeof(payload["palette_id"]) != TYPE_STRING or not PALETTE_IDS.has(String(payload["palette_id"])):
		return "payload.palette_id must be a known palette ID"
	if typeof(payload["palette"]) != TYPE_DICTIONARY:
		return "payload.palette must be a Dictionary"
	error = _exact_fields_error(payload["palette"], "payload.palette", PALETTE_FIELDS)
	if not error.is_empty():
		return error
	for field in PALETTE_FIELDS:
		if typeof(payload["palette"][field]) != TYPE_STRING or not _is_hex_color(String(payload["palette"][field])):
			return "payload.palette.%s must be a #RRGGBB color" % field
	if typeof(payload["parts"]) != TYPE_DICTIONARY:
		return "payload.parts must be a Dictionary"
	var part_fields: Array = PART_IDS.keys()
	error = _exact_fields_error(payload["parts"], "payload.parts", part_fields)
	if not error.is_empty():
		return error
	for field: Variant in part_fields:
		if (
			typeof(payload["parts"][field]) != TYPE_STRING
			or not PART_IDS[field].has(String(payload["parts"][field]))
		):
			return "payload.parts.%s must be a known %s part ID" % [field, field]
	error = _validate_rect(payload["collision_bounds"], "payload.collision_bounds")
	if not error.is_empty():
		return error
	var bounds: Dictionary = payload["collision_bounds"]
	var expected_bounds: Dictionary = COLLISION_BOUNDS[String(payload["type"])]
	for field in ["x", "y", "width", "height"]:
		if int(bounds[field]) != int(expected_bounds[field]):
			return "payload.collision_bounds must match the fixed %s profile" % payload["type"]
	if typeof(payload["anchors"]) != TYPE_DICTIONARY:
		return "payload.anchors must be a Dictionary"
	error = _exact_fields_error(payload["anchors"], "payload.anchors", ["pivot", "front", "rear", "driver"])
	if not error.is_empty():
		return error
	for anchor in ["pivot", "front", "rear", "driver"]:
		error = _validate_point(payload["anchors"][anchor], "payload.anchors.%s" % anchor)
		if not error.is_empty():
			return error
		var actual_anchor: Dictionary = payload["anchors"][anchor]
		var expected_anchor: Dictionary = ANCHORS[anchor]
		if (
			int(actual_anchor["x"]) != int(expected_anchor["x"])
			or int(actual_anchor["y"]) != int(expected_anchor["y"])
		):
			return "payload.anchors.%s must match the fixed front-up profile" % anchor
	if payload.has("handling"):
		error = _validate_handling(payload["handling"])
		if not error.is_empty():
			return error
	if typeof(payload["display_name"]) != TYPE_STRING or String(payload["display_name"]).is_empty():
		return "payload.display_name must be a non-empty String"
	if typeof(payload["tags"]) != TYPE_ARRAY or payload["tags"].size() < 10:
		return "payload.tags must contain at least ten unique Strings"
	var seen_tags := {}
	for index in range(payload["tags"].size()):
		var tag: Variant = payload["tags"][index]
		if typeof(tag) != TYPE_STRING or String(tag).is_empty():
			return "payload.tags[%s] must be a non-empty String" % index
		if seen_tags.has(tag):
			return "payload.tags[%s] duplicates '%s'" % [index, tag]
		seen_tags[tag] = true
	return ""


## Renders a transparent RGBA8 image from payload data only.
static func car_image(payload: Dictionary, pixel_scale: int = 1) -> Image:
	return _render_car(payload, 0, 0, pixel_scale)


## Four full-car frames (48x64) with the hub motif rotated 90° per frame.
## Frame 0 is byte-identical to `car_image(payload)`.
static func car_frames(payload: Dictionary, pixel_scale: int = 1) -> Array[Image]:
	var frames: Array[Image] = []
	for rotation in range(WHEEL_FRAME_COUNT):
		frames.append(_render_car(payload, rotation, 0, pixel_scale))
	return frames


## Five steering poses (48x64) in steer order -2, -1, 0, +1, +2 (index 0..4).
## Only the two front wheels change: they angle (rotate around their own centres)
## by -24°, -12°, 0°, +12°, +24°, so the tyre reads as turned, never translated.
## The rear wheels, body, and every other pixel stay identical across all five
## poses. Pose 2 (0°) is byte-identical to `car_image(payload)`.
static func steer_frames(payload: Dictionary, pixel_scale: int = 1) -> Array[Image]:
	var frames: Array[Image] = []
	for steer in range(-2, 3):
		frames.append(_render_car(payload, 0, steer, pixel_scale))
	return frames


## Five steering poses composed with one wheel-spin frame. `spin_frame` indexes
## `car_frames(payload)` (0..3, wrapped); `steer_frames(payload)` is exactly
## `car_steer_frames(payload, 0)`.
static func car_steer_frames(payload: Dictionary, spin_frame: int = 0, pixel_scale: int = 1) -> Array[Image]:
	var rotation := posmod(spin_frame, WHEEL_FRAME_COUNT)
	var frames: Array[Image] = []
	for steer in range(-2, 3):
		frames.append(_render_car(payload, rotation, steer, pixel_scale))
	return frames


static func car_pose_image(payload: Dictionary, spin_frame: int, steer_pose: int, pixel_scale: int = 1) -> Image:
	return _render_car(payload, posmod(spin_frame, WHEEL_FRAME_COUNT), clampi(steer_pose, 0, 4) - 2, pixel_scale)


## Four wheel tiles (one per rotation state) sized to this car's wheel profile.
## Each tile is the tyre + hub motif in isolation, so a game can composite the
## spinning wheels onto its own chassis or drive an AnimatedSprite2D.
static func wheel_frames(payload: Dictionary, pixel_scale: int = 1) -> Array[Image]:
	var error := validate_payload(payload)
	if not error.is_empty():
		push_error("ProceduralCarSprites rejected payload: %s." % error)
		return []
	if pixel_scale == 2:
		return NativeArt.new().wheel_tiles(payload)
	if pixel_scale != 1:
		push_error("pixel_scale must be 1 (48x64) or 2 (native 96x128)")
		return []
	var rect := _wheel_rects(String(payload["type"]))[0]
	var tiles: Array[Image] = []
	for rotation in range(WHEEL_FRAME_COUNT):
		var tile := Image.create(rect.size.x, rect.size.y, false, Image.FORMAT_RGBA8)
		tile.fill(Color(0, 0, 0, 0))
		_draw_single_wheel(tile, Rect2i(Vector2i.ZERO, rect.size), rotation, String(payload["parts"]["wheels"]))
		tiles.append(tile)
	return tiles


## Static helper mapping motion to a wheel-spin frame. Returns 0 when stopped
## and cycles 0..3 while rolling: distance = speed_px * elapsed_s, and one frame
## advances every WHEEL_ROLL_DISTANCE pixels of travel. Drive an AnimatedSprite2D
## (set frame) or swap `car_frames(payload)[wheel_frame_index(...)]` manually.
static func wheel_frame_index(speed_px: float, elapsed_s: float) -> int:
	if speed_px <= 0.0 or elapsed_s <= 0.0:
		return 0
	var distance := speed_px * elapsed_s
	return posmod(int(distance / WHEEL_ROLL_DISTANCE), WHEEL_FRAME_COUNT)


## Maps a steering input in [-1, 1] to a steer pose index 0..4: -1 -> 0 (full
## left), 0 -> 2 (straight), +1 -> 4 (full right). Intermediate inputs round to
## the nearest pose and out-of-range values clamp.
static func steer_pose_index(steer: float) -> int:
	var clamped := clampf(steer, -1.0, 1.0)
	return clampi(int(round((clamped + 1.0) * 2.0)), 0, 4)


## Combined motion helper: returns `{spin: int, steer_pose: int}`. `spin` is the
## wheel-spin frame from `wheel_frame_index`; `steer_pose` is the steer pose from
## `steer_pose_index`. Index the pose set with
## `car_steer_frames(payload, spin)[steer_pose]`.
static func car_frame_index(speed_px: float, elapsed_s: float, steer: float = 0.0) -> Dictionary:
	return {
		"spin": wheel_frame_index(speed_px, elapsed_s),
		"steer_pose": steer_pose_index(steer),
	}


static func _render_car(payload: Dictionary, wheel_rotation: int, steer: int = 0, pixel_scale: int = 1) -> Image:
	var error := validate_payload(payload)
	if not error.is_empty():
		push_error("ProceduralCarSprites rejected payload: %s." % error)
		return null
	if pixel_scale == 2:
		return NativeArt.new().render(payload, wheel_rotation, steer * 12.0)["car"]
	if pixel_scale != 1:
		push_error("pixel_scale must be 1 (48x64) or 2 (native 96x128)")
		return null
	var image := Image.create(IMAGE_WIDTH, IMAGE_HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var spans := _body_spans(String(payload["type"]), payload["parts"])
	_draw_contact_shadow(image, spans, String(payload["type"]), payload["palette"], steer)
	_draw_body(image, spans, payload["palette"])
	_draw_livery(image, spans, payload["parts"], payload["palette"])
	_draw_body_planes(image, spans, String(payload["type"]), payload["parts"], payload["palette"])
	_draw_hood_form(image, spans, String(payload["type"]), payload["palette"])
	_draw_cabin(image, String(payload["type"]), payload["parts"], payload["palette"])
	_draw_bumpers(image, String(payload["type"]), payload["parts"], payload["palette"])
	_draw_spoiler(image, String(payload["type"]), payload["parts"], payload["palette"])
	_draw_lights_and_trim(image, spans, String(payload["type"]), payload["palette"])
	_draw_wheels(image, String(payload["type"]), payload["parts"], payload["palette"], wheel_rotation, steer)
	return image



static func car_texture(payload: Dictionary, pixel_scale: int = 1) -> Texture2D:
	var image := car_image(payload, pixel_scale)
	return ImageTexture.create_from_image(image) if image != null else null


static func save_car_png(payload: Dictionary, output_path: String, pixel_scale: int = 1) -> Error:
	if output_path.is_empty():
		push_error("ProceduralCarSprites requires a non-empty PNG output path.")
		return ERR_INVALID_PARAMETER
	var image := car_image(payload, pixel_scale)
	if image == null:
		return ERR_INVALID_DATA
	var save_error := image.save_png(output_path)
	if save_error != OK:
		push_error("ProceduralCarSprites could not save %s: %s" % [output_path, error_string(save_error)])
	return save_error


static func _body_spans(car_type: String, parts: Dictionary = {}) -> Array[Vector2i]:
	var spans: Array[Vector2i] = []
	spans.resize(IMAGE_HEIGHT)
	spans.fill(Vector2i(-1, -1))
	var cabin := String(parts.get("cabin", "angular"))
	var hood := String(parts.get("hood", "smooth"))
	var spoiler := String(parts.get("spoiler", "none"))
	var bumpers := String(parts.get("bumpers", "sport"))
	var nose_pull := 0
	if hood in ["power_scoop", "dual_scoop"]:
		nose_pull = 3
	elif hood in ["twin_vents", "ridged"]:
		nose_pull = 1
	var mid_pad := 0
	match cabin:
		"panoramic", "bubble":
			mid_pad = 3
		"low", "cage":
			mid_pad = -3
		"fastback":
			mid_pad = -2
	var front_pad := 2 if bumpers in ["wide", "utility"] else (0 if bumpers != "slim" else -2)
	var tail_extra := 0
	if spoiler in ["wing", "tall", "winged", "hoop"]:
		tail_extra = 3
	elif spoiler == "lip":
		tail_extra = 1
	for y in range(IMAGE_HEIGHT):
		var left := -1
		var right := -1
		match car_type:
			"compact":
				if y in range(maxi(3, 8 - nose_pull), 14):
					var t := y - (8 - nose_pull)
					left = 18 - t - front_pad
					right = 29 + t + front_pad
				elif y in range(14, 48):
					left = 11 - mid_pad
					right = 36 + mid_pad
				elif y in range(48, 54 + tail_extra):
					left = 13
					right = 34
				elif y in range(54 + tail_extra, 59 + tail_extra):
					left = 16
					right = 31
			"coupe":
				if y in range(maxi(3, 4 - nose_pull), 16):
					var t := y - (4 - nose_pull)
					left = 22 - t
					right = 25 + t
				elif y in range(16, 28):
					left = 16 - mid_pad
					right = 31 + mid_pad
				elif y in range(28, 44):
					left = 9 - maxi(0, mid_pad)
					right = 38 + maxi(0, mid_pad)
				elif y in range(44, 52 + tail_extra):
					var taper := (y - 44) / (1 if cabin == "fastback" else 2)
					left = 12 + taper
					right = 35 - taper
				elif y in range(52 + tail_extra, 58 + tail_extra):
					left = 18 + (y - 52)
					right = 29 - (y - 52)
			"muscle":
				if y in range(maxi(3, 5 - nose_pull), 11):
					left = 7 - front_pad
					right = 40 + front_pad
				elif y in range(11, 54 + tail_extra):
					left = 4 - front_pad
					right = 43 + front_pad
				elif y in range(54 + tail_extra, 59 + tail_extra):
					left = 7
					right = 40
			"buggy":
				if y in range(maxi(3, 5 - nose_pull), 10):
					left = 20
					right = 27
				elif y in range(10, 24) or y in range(40, 54):
					left = 5
					right = 42
				elif y in range(24, 40):
					left = 20 + (1 if cabin == "cage" else 0)
					right = 27 - (1 if cabin == "cage" else 0)
				elif y in range(54, 60 + tail_extra):
					left = 19
					right = 28
		if left >= 0 and y <= 60:
			left = clampi(left, 3, 22)
			right = clampi(right, 25, 43)
			if right - left < 8:
				right = mini(43, left + 8)
			spans[y] = Vector2i(left, right)
	return spans


static func _draw_contact_shadow(image: Image, spans: Array[Vector2i], car_type: String, palette: Dictionary, steer: int = 0) -> void:
	var shadow := Color(palette["shadow"], 0.42)
	for y in range(IMAGE_HEIGHT - 6):
		var span := spans[y]
		if span.x < 0:
			continue
		for x in range(maxi(2, span.x - 2), mini(44, span.y + 3)):
			_set_pixel(image, x + 1, mini(61, y + 3), shadow)
	var wheel_rects := _wheel_rects(car_type)
	for index in range(wheel_rects.size()):
		var rect: Rect2i = wheel_rects[index]
		# A thin ground-contact strip under each tyre; the heavier shadow stays
		# under the center body so catalog-sheet sprites don't get muddy. The
		# front wheels carry their own strip with them when they steer (baked
		# into the angled wheel buffer), so the straight strip is only drawn here
		# for the never-steered rear wheels and for straight front wheels.
		if index < 2 and steer != 0:
			continue
		_fill_rect(image, Rect2i(Vector2i(rect.position.x + 1, rect.end.y), Vector2i(rect.size.x - 1, 1)), shadow)


static func _draw_wheels(image: Image, car_type: String, parts: Dictionary, palette: Dictionary, rotation: int, steer: int = 0) -> void:
	var wheels_id := String(parts.get("wheels", "classic"))
	var rects := _wheel_rects(car_type)
	for index in range(rects.size()):
		var rect: Rect2i = rects[index]
		if index < 2 and steer != 0:
			_draw_wheel_angled(image, rect, rotation, wheels_id, _steer_angle_deg(steer), Color(palette["shadow"], 0.42))
		else:
			_draw_single_wheel(image, rect, rotation, wheels_id)


## Draws one tyre (canonical rubber, rim, and per-wheels-ID hub motif) into
## `image` at `rect`. The hub motif rotates 90° clockwise per `rotation` step;
## the rubber ring and edge treatment are identical in every state and for every
## car.
static func _draw_single_wheel(image: Image, rect: Rect2i, rotation: int, wheels_id: String) -> void:
	_draw_wheel_tyre(image, rect)
	_draw_hub(image, rect.get_center(), rotation, wheels_id)


## Draws the canonical rubber ring, inner-rim key light, and corner rounding into
## `image` at `rect`. Shared by straight and angled wheels so both use identical
## tyre pixels.
static func _draw_wheel_tyre(image: Image, rect: Rect2i) -> void:
	var rubber_dark := TYRE_RUBBER.darkened(0.32)
	_fill_rect(image, rect, TYRE_OUTLINE)
	_fill_rect(image, Rect2i(rect.position + Vector2i(1, 1), rect.size - Vector2i(2, 2)), rubber_dark)
	# Round the four inner corners so wheels stop reading as square blocks.
	_set_pixel(image, rect.position.x + 1, rect.position.y + 1, TYRE_OUTLINE)
	_set_pixel(image, rect.end.x - 2, rect.position.y + 1, TYRE_OUTLINE)
	_set_pixel(image, rect.position.x + 1, rect.end.y - 2, TYRE_OUTLINE)
	_set_pixel(image, rect.end.x - 2, rect.end.y - 2, TYRE_OUTLINE)
	# Bright inner-rim key light across the top shoulder of the tyre.
	for x in range(rect.position.x + 2, rect.end.x - 2):
		_set_pixel(image, x, rect.position.y + 2, TYRE_HIGHLIGHT)


## Maps a steer pose (-2..+2) to the front-wheel angle in degrees: -24°, -12°,
## 0°, +12°, +24°. Negative angles turn left (counter-clockwise from the
## front-up orientation), positive angles turn right.
static func _steer_angle_deg(steer: int) -> float:
	return float(clampi(steer, -2, 2)) * 12.0


## Draws one front wheel rotated `angle_deg` around its own centre. The straight
## wheel (canonical rubber ring + tread/edge treatment + hub motif) is painted
## into a local buffer with the exact same `_draw_wheel_tyre` / `_draw_hub`
## painters used for straight wheels, plus its ground-contact strip one row below
## the tyre, then every destination pixel in a bounding box around the centre is
## inverse-rotated by -angle and sampled back from that buffer with
## nearest-neighbour rounding. This yields a crisp angled wheel (a rhombus /
## parallelogram read) rather than a shifted square, with the contact strip
## angling along with it so nothing straight remains beneath the turned tyre.
## Only opaque source pixels are written, so the body shows through wherever the
## rotated wheel no longer covers it.
static func _draw_wheel_angled(image: Image, rect: Rect2i, rotation: int, wheels_id: String, angle_deg: float, shadow_color: Color) -> void:
	var wheel_size := rect.size
	# One extra row below the tyre holds the ground-contact strip so the whole
	# wheel + strip composite rotates together instead of leaving a straight,
	# screen-aligned shadow bar under an angled wheel.
	var buffer := Image.create(wheel_size.x, wheel_size.y + 1, false, Image.FORMAT_RGBA8)
	buffer.fill(Color(0, 0, 0, 0))
	var local_rect := Rect2i(Vector2i.ZERO, wheel_size)
	_draw_wheel_tyre(buffer, local_rect)
	_draw_hub(buffer, local_rect.get_center(), rotation, wheels_id)
	_fill_rect(buffer, Rect2i(Vector2i(1, wheel_size.y), Vector2i(wheel_size.x - 1, 1)), shadow_color)

	var angle := deg_to_rad(angle_deg)
	var cosine := cos(angle)
	var sine := sin(angle)
	var center := Vector2(rect.position) + Vector2(wheel_size) * 0.5
	var half_w := wheel_size.x * 0.5
	var half_h := wheel_size.y * 0.5

	# Axis-aligned bounding box guaranteed to contain the rotated rectangle and
	# the contact strip one row below it.
	var radius_x := int(ceil(abs(half_w * cosine) + abs(half_h * sine))) + 2
	var radius_y := int(ceil(abs(half_w * sine) + abs(half_h * cosine))) + 3
	var min_x := maxi(0, int(floor(center.x)) - radius_x)
	var max_x := mini(IMAGE_WIDTH - 1, int(ceil(center.x)) + radius_x)
	var min_y := maxi(0, int(floor(center.y)) - radius_y)
	var max_y := mini(IMAGE_HEIGHT - 1, int(ceil(center.y)) + radius_y)

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var offset := Vector2(x, y) - center
			# Inverse rotation: rotate the destination offset by -angle to find
			# the un-rotated local wheel coordinate.
			var local_x := half_w + offset.x * cosine + offset.y * sine
			var local_y := half_h - offset.x * sine + offset.y * cosine
			var source_x := int(round(local_x))
			var source_y := int(round(local_y))
			if source_x < 0 or source_y < 0 or source_x >= wheel_size.x or source_y >= wheel_size.y + 1:
				continue
			var color := buffer.get_pixel(source_x, source_y)
			if color.a > 0.0:
				_set_pixel(image, x, y, color)


## Per-wheels-ID hub motif, drawn with the canonical hub colours. `hub` offsets
## use TYRE_HUB (silver) and `light` offsets use TYRE_HUB_LIGHT (bright). Every
## motif deliberately breaks 4-fold symmetry (by shape or by one off-centre lug)
## so the four wheel-spin frames are pairwise distinct while staying readable at
## 48x64 inside the 3x3 hub area.
static func _hub_offsets(wheels_id: String) -> Dictionary:
	match wheels_id:
		"disc":
			# Solid disc: a full 3x3 cap with a bright centre and one bright
			# off-centre lug so the spin is visible.
			return {
				"hub": [Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)],
				"light": [Vector2i(0, 0), Vector2i(-1, -1)],
			}
		"classic":
			# 5-lug ring: four corner lugs around a bright centre cap, plus a
			# bright top lug that orbits through the spin frames.
			return {
				"hub": [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)],
				"light": [Vector2i(0, 0), Vector2i(0, -1)],
			}
		"mesh":
			# Plus/cross mesh: four cardinal arms meet at a bright centre, with a
			# bright top-left lug for spin visibility.
			return {
				"hub": [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)],
				"light": [Vector2i(0, 0), Vector2i(-1, -1)],
			}
		"rugged":
			# Beadlock ring: a chunky hollow ring with a dark centre and a bright
			# top lug so the heavy beadlock reads as rolling.
			return {
				"hub": [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)],
				"light": [Vector2i(0, -1)],
			}
		"spoke":
			# 3-spoke: three radial arms (top, lower-left, lower-right) around a
			# bright centre; inherently asymmetric, so spin frames differ without
			# an extra lug.
			return {
				"hub": [Vector2i(0, -1), Vector2i(-1, 1), Vector2i(1, 1)],
				"light": [Vector2i(0, 0)],
			}
		"open":
			# Open hub: a bare bright centre with one bright lug; the dark tyre
			# body shows through for a minimal, see-through look.
			return {
				"hub": [],
				"light": [Vector2i(0, 0), Vector2i(-1, -1)],
			}
		"beadlock":
			# Beadlock bolts: four bright rim bolts around a silver centre, plus a
			# bright top lug that orbits through the spin frames.
			return {
				"hub": [Vector2i(0, 0)],
				"light": [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(0, -1)],
			}
	return {"hub": [Vector2i(0, 0)], "light": []}


## Draws one hub motif at `center`, rotating every offset 90° clockwise per
## `rotation` step. Silver (`hub`) offsets draw first, bright (`light`) offsets
## on top, so the centre cap and lug stay crisp.
static func _draw_hub(image: Image, center: Vector2i, rotation: int, wheels_id: String) -> void:
	var motif := _hub_offsets(wheels_id)
	var hub_offsets: Array = motif["hub"]
	var light_offsets: Array = motif["light"]
	for offset: Vector2i in hub_offsets:
		var rotated := _rotate_offset(offset, rotation)
		_set_pixel(image, center.x + rotated.x, center.y + rotated.y, TYRE_HUB)
	for offset: Vector2i in light_offsets:
		var rotated := _rotate_offset(offset, rotation)
		_set_pixel(image, center.x + rotated.x, center.y + rotated.y, TYRE_HUB_LIGHT)


static func _rotate_offset(offset: Vector2i, turns: int) -> Vector2i:
	var result := offset
	for _index in range(turns % 4):
		result = Vector2i(-result.y, result.x)
	return result


static func _wheel_rects(car_type: String) -> Array[Rect2i]:
	var left_x := 5
	var right_x := 38
	var width := 5
	var front_y := 14
	var rear_y := 41
	var height := 12
	match car_type:
		"compact":
			left_x = 6
			right_x = 37
			front_y = 15
			rear_y = 40
			height = 11
		"coupe":
			left_x = 5
			right_x = 38
			front_y = 16
			rear_y = 42
			height = 11
		"muscle":
			left_x = 4
			right_x = 39
			width = 6
			front_y = 14
			rear_y = 41
			height = 13
		"buggy":
			left_x = 2
			right_x = 37
			width = 7
			front_y = 11
			rear_y = 41
			height = 14
	right_x = mini(right_x, 44 - width)
	left_x = mini(left_x, 20)
	return [
		Rect2i(left_x, front_y, width, height), Rect2i(right_x, front_y, width, height),
		Rect2i(left_x, rear_y, width, height), Rect2i(right_x, rear_y, width, height),
	]


static func _draw_body(image: Image, spans: Array[Vector2i], palette: Dictionary) -> void:
	var outline := Color(palette["outline"])
	var body_dark := Color(palette["body_dark"])
	var body_mid := Color(palette["body_mid"])
	var body_light := Color(palette["body_light"])
	for y in range(IMAGE_HEIGHT):
		var span := spans[y]
		if span.x < 0:
			continue
		for x in range(span.x - 1, span.y + 2):
			if not _inside_body(spans, x, y) and _touches_body(spans, x, y):
				_set_pixel(image, x, y, outline)
	var shades := [body_light, body_mid, body_dark]
	var front_y := -1
	var rear_y := -1
	for y in range(IMAGE_HEIGHT):
		if spans[y].x >= 0:
			if front_y < 0:
				front_y = y
			rear_y = y
	var ramp_height := maxi(1, rear_y - front_y)
	for y in range(IMAGE_HEIGHT):
		var span := spans[y]
		if span.x < 0:
			continue
		var rel := float(y - front_y) / float(ramp_height)
		for x in range(span.x, span.y + 1):
			# Front-to-rear ramp: hood catches the key light, trunk falls away.
			var shade := _ramp_shade(rel, x, y, 0.34, 0.68)
			# Cylindrical cross-shade from the top-left key light: the left flank
			# stays lit near the front while the right flank falls into shadow.
			if x <= span.x + 1:
				# Lit only for the front ~half so the key light concentrates in
				# the top-left corner instead of washing down the whole flank.
				shade = 0 if rel < 0.55 else mini(2, shade + 1)
			elif x >= span.y:
				shade = mini(2, shade + 1)
			_set_pixel(image, x, y, shades[shade])


static func _draw_livery(image: Image, spans: Array[Vector2i], parts: Dictionary, palette: Dictionary) -> void:
	var accent := Color(palette["accent"])
	var dark := Color(palette["body_dark"])
	match parts["livery"]:
		"solid":
			return
		"center_stripe":
			for y in range(7, 58):
				for x in range(23, 25):
					_paint_inside(image, spans, x, y, accent)
		"twin_stripe":
			for y in range(7, 58):
				for x in [20, 27]:
					_paint_inside(image, spans, x, y, accent)
		"side_flash":
			for y in range(12, 55):
				var x := 13 + (y - 12) / 5
				for offset in range(3):
					_paint_inside(image, spans, x + offset, y, accent)
		"checker":
			for y in range(45, 50):
				for x in range(13, 36):
					if ((x - 13) / 4 + (y - 45) / 3) % 2 == 0:
						_paint_inside(image, spans, x, y, accent)
		"sunburst":
			for y in range(8, 22):
				var half_width := maxi(1, (y - 7) / 3)
				for x in range(24 - half_width, 25 + half_width):
					if x == 24 or (x + y) % 3 == 0:
						_paint_inside(image, spans, x, y, accent)
			for x in range(17, 32):
				_paint_inside(image, spans, x, 21, dark)
		"hood_stripe":
			for y in range(7, 20):
				for x in range(19, 29):
					_paint_inside(image, spans, x, y, accent)
		"side_swoosh":
			for y in range(14, 50):
				var x := 12 + (y - 14) / 4
				_paint_inside(image, spans, x, y, accent)
				_paint_inside(image, spans, x + 1, y, accent)
				if y % 5 == 0:
					_paint_inside(image, spans, x + 2, y, accent)
		"two_tone":
			for y in range(10, 55):
				for x in range(12, 24):
					_paint_inside(image, spans, x, y, accent)
		"racing_stripe":
			for y in range(6, 58):
				if y >= 17 and y <= 44:
					continue
				_paint_inside(image, spans, 22, y, accent)
				_paint_inside(image, spans, 25, y, accent)
		"dust_kick":
			for y in range(47, 55):
				for x in range(12, 36):
					if ((x - 12) / 4 + (y - 47) / 4) % 2 == 0:
						_paint_inside(image, spans, x, y, accent)
		"hash_marks":
			for y in [16, 24, 32, 40]:
				for x in range(14, 20):
					_paint_inside(image, spans, x, y, accent)
					_paint_inside(image, spans, x, y + 1, accent)
					_paint_inside(image, spans, x + 14, y, accent)
					_paint_inside(image, spans, x + 14, y + 1, accent)


static func _draw_body_planes(image: Image, spans: Array[Vector2i], car_type: String, parts: Dictionary, palette: Dictionary) -> void:
	var dark := Color(palette["body_dark"])
	var light := Color(palette["body_light"])
	var outline := Color(palette["outline"])
	var hood_end := 21 if car_type != "buggy" else 23
	for x in range(14, 34):
		_paint_inside(image, spans, x, hood_end, dark)
		_paint_inside(image, spans, x, 44, dark)
	for y in range(10, hood_end):
		_paint_inside(image, spans, 16, y, light)
		_paint_inside(image, spans, 31, y, dark)
	match parts["hood"]:
		"smooth":
			for x in range(20, 28):
				_paint_inside(image, spans, x, 11, light)
		"twin_vents":
			for y in [14, 16]:
				for x in range(17, 23):
					_paint_inside(image, spans, x, y, outline)
				for x in range(25, 31):
					_paint_inside(image, spans, x, y, outline)
		"power_scoop":
			_fill_clipped_rect(image, spans, Rect2i(20, 12, 8, 7), outline)
			_fill_clipped_rect(image, spans, Rect2i(21, 13, 6, 5), dark)
			_fill_clipped_rect(image, spans, Rect2i(22, 13, 4, 1), light)
		"flat":
			for x in range(18, 30):
				_paint_inside(image, spans, x, 12, outline)
		"dual_scoop":
			_fill_clipped_rect(image, spans, Rect2i(17, 11, 5, 5), outline)
			_fill_clipped_rect(image, spans, Rect2i(18, 12, 3, 3), dark)
			_fill_clipped_rect(image, spans, Rect2i(26, 11, 5, 5), outline)
			_fill_clipped_rect(image, spans, Rect2i(27, 12, 3, 3), dark)
		"ridged":
			for y in [12, 14, 16, 18]:
				for x in range(17, 31):
					_paint_inside(image, spans, x, y, light if y % 4 == 0 else dark)
	for y in range(47, 54):
		_paint_inside(image, spans, 17, y, dark)
		_paint_inside(image, spans, 30, y, dark)
	if car_type == "muscle":
		for x in range(10, 15):
			_paint_inside(image, spans, x, 22, light)
		for x in range(33, 38):
			_paint_inside(image, spans, x, 22, dark)
	if car_type == "coupe":
		for y in range(38, 48):
			_paint_inside(image, spans, 11, y, light)
			_paint_inside(image, spans, 36, y, dark)
	if car_type == "buggy":
		for x in range(12, 36):
			_paint_inside(image, spans, x, 15, outline)
			_paint_inside(image, spans, x, 42, outline)


## Class-specific hood form language so each body shape reads as a distinct
## silhouette rather than a generic slab. Kept to a few deliberate pixels.
static func _draw_hood_form(image: Image, spans: Array[Vector2i], car_type: String, palette: Dictionary) -> void:
	var dark := Color(palette["body_dark"])
	var light := Color(palette["body_light"])
	var outline := Color(palette["outline"])
	match car_type:
		"compact":
			# Short front crease: one darker horizontal just before the windshield.
			for x in range(15, 33):
				_paint_inside(image, spans, x, 17, dark)
		"coupe":
			# Thin hood channels running forward from the cowl.
			for y in range(14, 28):
				_paint_inside(image, spans, 17, y, dark)
				_paint_inside(image, spans, 30, y, dark)
		"muscle":
			# Center seam with a single 1px top-left key highlight.
			for y in range(8, 23):
				_paint_inside(image, spans, 24, y, dark)
			_paint_inside(image, spans, 23, 8, light)
		"buggy":
			# One dominant 2px central spine over the front pod, flanked by
			# shorter, darker secondary bars.
			for y in range(12, 23):
				_paint_inside(image, spans, 23, y, dark)
				_paint_inside(image, spans, 24, y, dark)
			for x in range(17, 21):
				_paint_inside(image, spans, x, 17, outline)
			for x in range(26, 30):
				_paint_inside(image, spans, x, 21, outline)


static func _draw_cabin(image: Image, car_type: String, parts: Dictionary, palette: Dictionary) -> void:
	var cabin_spans := _cabin_spans(car_type, String(parts["cabin"]))
	var outline := Color(palette["outline"])
	var glass_dark := Color(palette["glass_dark"])
	var glass_mid := Color(palette["glass_mid"])
	var glass_light := Color(palette["glass_light"])
	var top_y := -1
	var bottom_y := -1
	for y in range(IMAGE_HEIGHT):
		var span := cabin_spans[y]
		if span.x < 0:
			continue
		if top_y < 0:
			top_y = y
		bottom_y = y + 1
		for x in range(span.x - 1, span.y + 2):
			if not _inside_body(cabin_spans, x, y) and _touches_body(cabin_spans, x, y):
				_set_pixel(image, x, y, outline)
	if car_type != "buggy":
		var glass_shades := [glass_light, glass_mid, glass_dark]
		var cabin_height := maxi(1, bottom_y - top_y)
		for y in range(IMAGE_HEIGHT):
			var span := cabin_spans[y]
			if span.x < 0:
				continue
			var rel := float(y - top_y) / float(cabin_height)
			for x in range(span.x, span.y + 1):
				# Glossy glass: sky reflection fades from light at the top edge
				# down to dark at the roof line. A narrow blend keeps the glass
				# smooth instead of dithering into a visible checker.
				var shade := _ramp_shade(rel, x, y, 0.32, 0.70, 0.045)
				# Top-left key light: the left edge catches light, the right falls off.
				if x <= span.x + 1:
					shade = maxi(0, shade - 1)
				elif x >= span.y:
					shade = mini(2, shade + 1)
				_set_pixel(image, x, y, glass_shades[shade])
		# A few crisp specular glints on the windshield (top-left reflection).
		if top_y >= 0:
			var mid_y := top_y + (bottom_y - top_y) / 2
			if mid_y < IMAGE_HEIGHT:
				var mid_span := cabin_spans[mid_y]
				if mid_span.x >= 0:
					var start_x := mid_span.x + maxi(2, (mid_span.y - mid_span.x) / 2 - 1)
					for i in range(3):
						var glint_x := start_x + i
						var glint_y := mid_y + i
						if _inside_body(cabin_spans, glint_x, glint_y):
							_set_pixel(image, glint_x, glint_y, glass_light)
	else:
		# Buggy cockpit: one clean tub + seat frame so the center stays readable.
		var trim := Color(palette["trim"])
		for y in range(26, 40):
			_set_pixel(image, 17, y, outline)
			_set_pixel(image, 30, y, outline)
		for x in range(17, 31):
			_set_pixel(image, x, 26, outline)
			_set_pixel(image, x, 39, outline)
		_fill_rect(image, Rect2i(20, 31, 8, 7), Color(palette["body_dark"]))
		_fill_rect(image, Rect2i(21, 32, 6, 5), trim)
		_set_pixel(image, 24, 30, outline)
	for x in range(15, 33):
		if _inside_body(cabin_spans, x, top_y + 5):
			_set_pixel(image, x, top_y + 5, outline)
		if _inside_body(cabin_spans, x, bottom_y - 4):
			_set_pixel(image, x, bottom_y - 4, outline)
	if car_type != "buggy":
		for y in range(top_y + 3, bottom_y - 2):
			if _inside_body(cabin_spans, 24, y):
				_set_pixel(image, 24, y, glass_dark)
	if parts["cabin"] == "panoramic":
		for y in range(top_y + 2, bottom_y - 2):
			if _inside_body(cabin_spans, 27, y):
				_set_pixel(image, 27, y, glass_light)
	if parts["cabin"] == "low":
		for y in range(top_y + 4, bottom_y - 3):
			if _inside_body(cabin_spans, 24, y):
				_set_pixel(image, 24, y, glass_dark)
	if parts["cabin"] == "notched":
		for x in range(17, 31):
			if _inside_body(cabin_spans, x, top_y + 6):
				_set_pixel(image, x, top_y + 6, outline)
	if parts["cabin"] == "fastback":
		for y in range(top_y + 5, bottom_y - 3):
			if _inside_body(cabin_spans, 29, y):
				_set_pixel(image, 29, y, glass_light)
	if parts["cabin"] == "cage":
		for y in range(top_y + 2, bottom_y - 2, 3):
			for x in range(16, 32):
				if _inside_body(cabin_spans, x, y):
					_set_pixel(image, x, y, outline)
		_set_pixel(image, 18, top_y + 3, outline)
		_set_pixel(image, 29, top_y + 3, outline)
	if car_type == "buggy":
		# Single roll-cage hoop plus per-cabin glints, instead of the old dense
		# double frame, so suspension/chassis stay readable at 48x64.
		for x in range(15, 33):
			_set_pixel(image, x, 25, outline)
			_set_pixel(image, x, 40, outline)
		for y in range(25, 41):
			_set_pixel(image, 15, y, outline)
			_set_pixel(image, 32, y, outline)
		if parts["cabin"] == "bubble":
			_set_pixel(image, 18, 28, glass_light)
			_set_pixel(image, 29, 28, glass_light)
			_set_pixel(image, 18, 38, glass_dark)
			_set_pixel(image, 29, 38, glass_dark)
		elif parts["cabin"] == "angular":
			_set_pixel(image, 18, 28, outline)
			_set_pixel(image, 29, 28, outline)
		elif parts["cabin"] == "low":
			_set_pixel(image, 18, 29, glass_mid)
			_set_pixel(image, 29, 29, glass_mid)
		elif parts["cabin"] == "fastback":
			_set_pixel(image, 28, 30, glass_light)
			_set_pixel(image, 19, 37, glass_dark)


static func _cabin_spans(car_type: String, cabin: String) -> Array[Vector2i]:
	var spans: Array[Vector2i] = []
	spans.resize(IMAGE_HEIGHT)
	spans.fill(Vector2i(-1, -1))
	var top := 18
	var bottom := 44
	match car_type:
		"coupe":
			top = 28
			bottom = 48
		"muscle":
			top = 24
			bottom = 38
		"buggy":
			top = 24
			bottom = 40
	if cabin == "low":
		top += 3
		bottom -= 3
	elif cabin == "notched":
		bottom -= 3
	elif cabin == "bubble" or cabin == "panoramic":
		top -= 2
	elif cabin == "cage":
		top += 1
		bottom -= 1
	for y in range(top, bottom):
		var left := 14
		var right := 33
		match cabin:
			"bubble":
				var taper := 3 if y in [top, bottom - 1] else (1 if y in [top + 1, bottom - 2] else 0)
				left = 14 + taper
				right = 33 - taper
			"angular":
				var half := y - top
				left = 16 - mini(3, half / 2)
				right = 31 + mini(3, half / 2)
				if y > bottom - 5:
					left += y - (bottom - 5)
					right -= y - (bottom - 5)
			"panoramic":
				left = 13 + (2 if y in [top, bottom - 1] else 0)
				right = 34 - (2 if y in [top, bottom - 1] else 0)
			"low":
				left = 15 + (1 if y == top or y == bottom - 1 else 0)
				right = 32 - (1 if y == top or y == bottom - 1 else 0)
			"notched":
				left = 14 + mini(2, (y - top) / 4)
				right = 33 - mini(2, (y - top) / 4)
				if y >= bottom - 3:
					left += 3
					right -= 3
			"fastback":
				left = 14 + (y - top) / 4
				right = 33 - (y - top) / 5
				if y > bottom - 6:
					left += 2
					right -= 2
			"cage":
				left = 15
				right = 32
				if y == top or y == bottom - 1:
					left = 17
					right = 30
		if car_type == "coupe":
			left += 1 + maxi(0, y - (top + 10)) / 4
			right -= 1 + maxi(0, y - (top + 10)) / 4
		if car_type == "buggy":
			left = maxi(16, left)
			right = mini(31, right)
		spans[y] = Vector2i(left, right)
	return spans


static func _draw_lights_and_trim(image: Image, spans: Array[Vector2i], car_type: String, palette: Dictionary) -> void:
	var headlight := Color(palette["headlight"])
	var taillight := Color(palette["taillight"])
	var trim := Color(palette["trim"])
	var outline := Color(palette["outline"])
	var front_y := 9 if car_type != "buggy" else 11
	var rear_y := 54
	if car_type == "buggy":
		rear_y = 52
	elif car_type == "coupe":
		rear_y = 48
	for y in range(58, 40, -1):
		var span := spans[y]
		if span.x >= 0 and span.y - span.x >= 14:
			rear_y = y
			break
	var front_span := spans[front_y]
	var rear_span := spans[rear_y]
	if front_span.x < 0:
		front_span = Vector2i(16, 31)
	if rear_span.x < 0:
		rear_span = Vector2i(16, 31)
	var front_mid := (front_span.x + front_span.y) / 2
	var rear_mid := (rear_span.x + rear_span.y) / 2
	for x in range(front_mid - 7, front_mid - 3):
		_paint_inside(image, spans, x, front_y, headlight)
		_paint_inside(image, spans, front_mid * 2 - x, front_y, headlight)
	for x in range(rear_mid - 8, rear_mid - 4):
		_paint_inside(image, spans, x, rear_y, taillight)
		_paint_inside(image, spans, rear_mid * 2 - x, rear_y, taillight)
	for x in range(front_mid - 3, front_mid + 4):
		_paint_inside(image, spans, x, front_y, trim)
	for x in range(rear_mid - 3, rear_mid + 4):
		_paint_inside(image, spans, x, rear_y, outline)
	for y in range(17, 49):
		var span := spans[y]
		if span.x >= 0 and y % 3 != 0:
			_set_pixel(image, span.x + 1, y, outline)
			# Keep the metal rim glint only on the lit front flank; the lower
			# right flank falls into shadow so the key light stays top-left.
			if y < 30:
				_set_pixel(image, span.y - 1, y, trim)
	if car_type == "muscle":
		# Horizontal slat grilles with darker negative space instead of solid
		# intake blocks.
		for gx in [10, 34]:
			for row in range(3):
				for x in range(gx, gx + 4):
					_set_pixel(image, x, 11 + row * 2, trim)
	elif car_type == "buggy":
		_fill_rect(image, Rect2i(19, 7, 10, 2), trim)


static func _draw_bumpers(image: Image, car_type: String, parts: Dictionary, palette: Dictionary) -> void:
	var outline := Color(palette["outline"])
	var trim := Color(palette["trim"])
	var accent := Color(palette["accent"])
	var front_y := 4 if car_type in ["compact", "muscle"] else 3
	var rear_y := 59
	match parts["bumpers"]:
		"chrome":
			_fill_rect(image, Rect2i(17, front_y, 14, 2), outline)
			_fill_rect(image, Rect2i(18, front_y, 12, 1), trim)
			_fill_rect(image, Rect2i(15, rear_y, 18, 2), outline)
			_fill_rect(image, Rect2i(16, rear_y, 16, 1), trim)
		"sport":
			_fill_rect(image, Rect2i(19, front_y, 10, 2), outline)
			_fill_rect(image, Rect2i(21, front_y, 6, 1), accent)
			_fill_rect(image, Rect2i(18, rear_y, 12, 2), outline)
		"utility":
			_fill_rect(image, Rect2i(14, front_y, 20, 3), outline)
			_fill_rect(image, Rect2i(16, front_y, 4, 1), trim)
			_fill_rect(image, Rect2i(28, front_y, 4, 1), trim)
			_fill_rect(image, Rect2i(12, rear_y, 24, 3), outline)
			_fill_rect(image, Rect2i(15, rear_y, 18, 1), trim)
		"slim":
			_fill_rect(image, Rect2i(20, front_y, 8, 2), outline)
			_fill_rect(image, Rect2i(21, front_y, 6, 1), accent)
			_fill_rect(image, Rect2i(19, rear_y, 10, 2), outline)
		"wide":
			_fill_rect(image, Rect2i(13, front_y, 22, 3), outline)
			_fill_rect(image, Rect2i(15, front_y, 5, 1), trim)
			_fill_rect(image, Rect2i(28, front_y, 5, 1), trim)
			_fill_rect(image, Rect2i(11, rear_y, 26, 3), outline)
			_fill_rect(image, Rect2i(14, rear_y, 20, 1), trim)
		"pipe":
			_fill_rect(image, Rect2i(18, front_y, 12, 1), outline)
			_fill_rect(image, Rect2i(18, front_y + 2, 12, 1), outline)
			_fill_rect(image, Rect2i(16, rear_y, 16, 1), outline)
			_fill_rect(image, Rect2i(16, rear_y + 2, 16, 1), accent)


static func _draw_spoiler(image: Image, car_type: String, parts: Dictionary, palette: Dictionary) -> void:
	if parts["spoiler"] == "none":
		return
	var outline := Color(palette["outline"])
	var accent := Color(palette["accent"])
	var y := 56 if car_type != "buggy" else 57
	if parts["spoiler"] == "lip":
		_fill_rect(image, Rect2i(14, y, 20, 2), outline)
		_fill_rect(image, Rect2i(16, y, 16, 1), accent)
	elif parts["spoiler"] == "tall":
		_fill_rect(image, Rect2i(13, y - 3, 3, 7), outline)
		_fill_rect(image, Rect2i(32, y - 3, 3, 7), outline)
		_fill_rect(image, Rect2i(12, y + 1, 24, 3), outline)
		_fill_rect(image, Rect2i(14, y + 1, 20, 1), accent)
	elif parts["spoiler"] == "winged":
		_fill_rect(image, Rect2i(11, y - 3, 4, 5), outline)
		_fill_rect(image, Rect2i(33, y - 3, 4, 5), outline)
		_fill_rect(image, Rect2i(9, y, 30, 3), outline)
		_fill_rect(image, Rect2i(11, y, 26, 1), accent)
		_set_pixel(image, 13, y - 2, accent)
		_set_pixel(image, 34, y - 2, accent)
	elif parts["spoiler"] == "hoop":
		_fill_rect(image, Rect2i(16, y - 8, 2, 10), outline)
		_fill_rect(image, Rect2i(30, y - 8, 2, 10), outline)
		_fill_rect(image, Rect2i(16, y - 8, 16, 2), outline)
		_fill_rect(image, Rect2i(18, y - 7, 12, 1), accent)
	else:
		_fill_rect(image, Rect2i(12, y - 2, 3, 4), outline)
		_fill_rect(image, Rect2i(33, y - 2, 3, 4), outline)
		_fill_rect(image, Rect2i(10, y, 28, 3), outline)
		_fill_rect(image, Rect2i(12, y, 24, 1), accent)


static func _inside_body(spans: Array[Vector2i], x: int, y: int) -> bool:
	if x < 0 or x >= IMAGE_WIDTH or y < 0 or y >= IMAGE_HEIGHT:
		return false
	var span := spans[y]
	return span.x >= 0 and x >= span.x and x <= span.y


static func _touches_body(spans: Array[Vector2i], x: int, y: int) -> bool:
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			if _inside_body(spans, x + offset_x, y + offset_y):
				return true
	return false


static func _paint_inside(image: Image, spans: Array[Vector2i], x: int, y: int, color: Color) -> void:
	if _inside_body(spans, x, y):
		_set_pixel(image, x, y, color)


static func _fill_clipped_rect(image: Image, spans: Array[Vector2i], rect: Rect2i, color: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_paint_inside(image, spans, x, y, color)


static func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_set_pixel(image, x, y, color)


static func _set_pixel(image: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < IMAGE_WIDTH and y >= 0 and y < IMAGE_HEIGHT:
		image.set_pixel(x, y, color)


## Maps a 0..1 vertical position to a three-step light/mid/dark ramp (0 = light,
## 2 = dark). A dithered blend zone around each cut keeps the ramp reading as
## soft painted metal instead of hard horizontal bands that reveal the grid.
## `blend` controls the width of the dither zone; glass passes a narrower value
## so the windshield keeps its gloss without turning into a checker pattern.
static func _ramp_shade(rel: float, x: int, y: int, light_cut: float, dark_cut: float, blend: float = 0.07) -> int:
	var checker := (x + y) & 1
	if rel < light_cut - blend:
		return 0
	if rel < light_cut + blend:
		return 0 if checker == 0 else 1
	if rel < dark_cut - blend:
		return 1
	if rel < dark_cut + blend:
		return 1 if checker == 0 else 2
	return 2


static func _validate_rect(value: Variant, path: String) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "%s must be a Dictionary" % path
	var error := _exact_fields_error(value, path, ["x", "y", "width", "height"])
	if not error.is_empty():
		return error
	for field in ["x", "y", "width", "height"]:
		if not _is_integer_value(value[field]):
			return "%s.%s must be an int" % [path, field]
	if int(value["x"]) < 0 or int(value["y"]) < 0 or int(value["width"]) <= 0 or int(value["height"]) <= 0:
		return "%s must contain non-negative coordinates and positive dimensions" % path
	return ""


static func _validate_point(value: Variant, path: String) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "%s must be a Dictionary" % path
	var error := _exact_fields_error(value, path, ["x", "y"])
	if not error.is_empty():
		return error
	if not _is_integer_value(value["x"]) or not _is_integer_value(value["y"]):
		return "%s must contain integer x/y coordinates" % path
	if int(value["x"]) not in range(IMAGE_WIDTH) or int(value["y"]) not in range(IMAGE_HEIGHT):
		return "%s must fit inside the sprite" % path
	return ""


static func _validate_handling(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "payload.handling must be a Dictionary"
	var fields := ["identity", "display_name", "description", "traits"]
	var error := _exact_fields_error(value, "payload.handling", fields)
	if not error.is_empty():
		return error
	for field in ["identity", "display_name", "description"]:
		if typeof(value[field]) != TYPE_STRING or String(value[field]).is_empty():
			return "payload.handling.%s must be a non-empty String" % field
	if typeof(value["traits"]) != TYPE_ARRAY or value["traits"].size() < 3:
		return "payload.handling.traits must contain at least three Strings"
	var seen := {}
	for index in range(value["traits"].size()):
		var trait_value: Variant = value["traits"][index]
		if typeof(trait_value) != TYPE_STRING or String(trait_value).is_empty() or seen.has(trait_value):
			return "payload.handling.traits must contain unique non-empty Strings"
		seen[trait_value] = true
	return ""


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
