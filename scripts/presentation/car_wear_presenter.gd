extends RefCounted

const ART := preload("res://scripts/vendor/procedural_2d/procedural_car_art.gd")
const SPRITES := preload("res://scripts/vendor/procedural_2d/procedural_car_sprites.gd")
const STATE := preload("res://scripts/progression/run_state.gd")
const DETAIL_HEIGHT := 43
const MINIMUM_MARK_HEIGHT := 32
const MINIMUM_MARK_SIZE := Vector2i(24, MINIMUM_MARK_HEIGHT)
const SMALL_DUST_LIGHT := Color(0.98, 0.95, 0.82, 0.55)
const SMALL_DUST_DARK := Color(0.07, 0.05, 0.025, 0.55)
const SMALL_RUST := Color(0.72, 0.33, 0.09, 0.85)
const SMALL_RUST_RIM := Color(0.12, 0.05, 0.02, 0.85)
const SMALL_CRACK := Color(1.0, 0.97, 0.86, 1.0)
const SMALL_CRACK_OUTLINE := Color(0.025, 0.035, 0.04, 1.0)
const SMALL_DUST_DESATURATION := 0.18
const SMALL_RUST_TINT := Color(0.12, 0.035, 0.0, 0.22)
const SMALL_DENT_TINT := Color(0.0, 0.0, 0.0, 0.12)
const SMALL_RUST_PATCHES := [Rect2(8, 4, 8, 8), Rect2(8, 25, 8, 4)]
const SMALL_DUST_FLECKS := [
	Rect2(9, 4, 5, 2), Rect2(7, 8, 3, 3), Rect2(13, 10, 3, 2),
	Rect2(10, 18, 4, 3), Rect2(10, 26, 5, 2), Rect2(7, 23, 2, 2),
]
const SMALL_CRACKS := [
	[Vector2(9, 5), Vector2(13, 6), Vector2(11, 9)],
	[Vector2(10, 26), Vector2(14, 27), Vector2(11, 28)],
]
const LEGACY_COCKPIT_ROWS := Vector2i(24, 41)
const LEGACY_ACCENT_ROWS := Vector2i(8, 48)
const DUST := Color(0.82, 0.76, 0.60, 0.46)
const RUST := Color(0.25, 0.10, 0.04, 0.96)
const RUST_EDGE := Color(0.47, 0.23, 0.08, 0.90)
const DENT := Color(0.07, 0.09, 0.10, 1.0)
const BARE_METAL := Color(0.62, 0.68, 0.66, 0.92)
const PATCHES := [Rect2(17, 8, 14, 16), Rect2(20, 50, 10, 8)]
const DUST_FLECKS := [
	Rect2(13, 10, 21, 13), Rect2(14, 49, 20, 8), Rect2(18, 34, 12, 10),
	Rect2(12, 26, 5, 19), Rect2(32, 27, 4, 19),
]
const TOKEN_CREASES := [
	[Vector2(19, 9), Vector2(26, 11), Vector2(22, 14)],
	[Vector2(30, 50), Vector2(24, 53), Vector2(29, 56)],
]
const DETAIL_CREASES := [
	[Vector2(18, 9), Vector2(24, 11), Vector2(21, 13), Vector2(27, 14)],
	[Vector2(30, 50), Vector2(24, 52), Vector2(28, 54), Vector2(21, 56)],
	[Vector2(29, 12), Vector2(27, 15), Vector2(30, 18)],
	[Vector2(18, 50), Vector2(20, 53)],
]


## Shapes use the 48x64 identity coordinate space. Native component masks keep
## wear off hardware; the older scale-1 renderer uses a conservative paint mask.
static func overlay_image(payload: Dictionary, wear_level: String, pixel_scale: int, display_height: int = 32, paint_mask: Image = null) -> Image:
	if not supports_request(wear_level, pixel_scale):
		push_error("Unsupported car wear level or pixel scale: %s / %d" % [wear_level, pixel_scale])
		return null
	var overlay := Image.create(SPRITES.IMAGE_WIDTH * pixel_scale, SPRITES.IMAGE_HEIGHT * pixel_scale, false, Image.FORMAT_RGBA8)
	overlay.fill(Color.TRANSPARENT)
	if wear_level == "clean":
		return overlay
	var mask := paint_mask if paint_mask != null else make_paint_mask(payload, pixel_scale)
	if display_height <= MINIMUM_MARK_HEIGHT:
		return _minimum_overlay(payload, wear_level, mask)
	var detailed := display_height > DETAIL_HEIGHT
	for y in overlay.get_height():
		for x in overlay.get_width():
			if mask.get_pixel(x, y).r == 0.0:
				continue
			var point := (Vector2(x, y) + Vector2(0.5, 0.5)) / float(pixel_scale)
			var color := Color.TRANSPARENT
			if wear_level == "dusty":
				for fleck: Rect2 in DUST_FLECKS:
					var offset := (point - fleck.get_center()) / (fleck.size * 0.5)
					var edge := 1.0 + 0.18 * sin(point.y * 1.1) * cos(point.x * 1.3)
					if offset.length() < edge:
						color = DUST
			if wear_level in ["rusty", "dented"]:
				for patch: Rect2 in PATCHES:
					var offset := (point - patch.get_center()) / (patch.size * 0.5)
					var edge := 1.0 + 0.16 * sin(point.y * 2.4) + 0.12 * cos(point.x * 3.1)
					if offset.length() < edge:
						color = RUST if offset.length() < edge - 0.25 else RUST_EDGE
			if wear_level == "dented" and (point.y < 24.0 or point.y >= 49.0):
				var creases := DETAIL_CREASES if detailed else TOKEN_CREASES
				var width := 0.65 if detailed else 2.3
				if _crease_distance(point, Vector2(0, -2.5), creases) < width:
					color = BARE_METAL
				if _crease_distance(point, Vector2.ZERO, creases) < width:
					color = DENT
			overlay.set_pixel(x, y, color)
	return overlay


## Author token marks in a fixed 24x32 pixel grid, then expand without filtering.
## Clip after expansion so a chunky reference pixel cannot cover nearby hardware.
static func _minimum_overlay(payload: Dictionary, wear_level: String, mask: Image) -> Image:
	var reference := Image.create(MINIMUM_MARK_SIZE.x, MINIMUM_MARK_SIZE.y, false, Image.FORMAT_RGBA8)
	reference.fill(Color.TRANSPARENT)
	var sample_scale := 1 if mask.get_height() == SPRITES.IMAGE_HEIGHT else 2
	var body := SPRITES.car_image(payload, sample_scale) if wear_level == "dusty" else null
	for y in MINIMUM_MARK_SIZE.y:
		for x in MINIMUM_MARK_SIZE.x:
			var point := Vector2(x + 0.5, y + 0.5)
			var color := Color.TRANSPARENT
			if wear_level == "dusty":
				for fleck: Rect2 in SMALL_DUST_FLECKS:
					if ((point - fleck.get_center()) / (fleck.size * 0.5)).length() < 1.05:
						var paint := _sample_paint(body, mask, Vector2i(x, y), Color(payload["palette"]["body_mid"]))
						color = SMALL_DUST_LIGHT if paint.get_luminance() < 0.5 else SMALL_DUST_DARK
			elif wear_level == "rusty":
				for patch: Rect2 in SMALL_RUST_PATCHES:
					var distance := ((point - patch.get_center()) / (patch.size * 0.5)).length()
					if distance < 1.0:
						color = SMALL_RUST if distance < 0.68 else SMALL_RUST_RIM
			elif wear_level == "dented" and (point.y < 12.0 or point.y >= 24.5):
				var distance := _crease_distance(point, Vector2.ZERO, SMALL_CRACKS)
				if distance < 2.0:
					color = SMALL_CRACK_OUTLINE
				if distance < 1.0:
					color = SMALL_CRACK
			reference.set_pixel(x, y, color)
	reference.resize(mask.get_width(), mask.get_height(), Image.INTERPOLATE_NEAREST)
	var tint_base: Image = null
	if wear_level == "dusty":
		var source_scale := mask.get_height() / SPRITES.IMAGE_HEIGHT
		tint_base = body if source_scale == sample_scale else SPRITES.car_image(payload, source_scale)
	for y in mask.get_height():
		for x in mask.get_width():
			if mask.get_pixel(x, y).r == 0.0:
				reference.set_pixel(x, y, Color.TRANSPARENT)
				continue
			var mark := reference.get_pixel(x, y)
			var tint := SMALL_DENT_TINT
			if wear_level == "dusty":
				var painted := tint_base.get_pixel(x, y).blend(mark)
				var gray := painted.get_luminance()
				tint = Color(gray, gray, gray, SMALL_DUST_DESATURATION)
			elif wear_level == "rusty":
				tint = SMALL_RUST_TINT
			reference.set_pixel(x, y, mark.blend(tint))
	return reference


static func _sample_paint(body: Image, mask: Image, cell: Vector2i, fallback: Color) -> Color:
	var cell_size := mask.get_size() / MINIMUM_MARK_SIZE
	var origin := cell * cell_size
	var sum := Color(0, 0, 0, 0)
	var count := 0
	var stride := maxi(1, mask.get_height() / body.get_height())
	for y in range(origin.y, origin.y + cell_size.y, stride):
		for x in range(origin.x, origin.x + cell_size.x, stride):
			if mask.get_pixel(x, y).r > 0.0:
				var source := Vector2i(Vector2(x, y) * Vector2(body.get_size()) / Vector2(mask.get_size()))
				sum += body.get_pixelv(source)
				count += 1
	return sum / float(count) if count > 0 else fallback


static func supports_request(wear_level: String, pixel_scale: int) -> bool:
	return STATE.WEAR_LEVELS.has(wear_level) and pixel_scale >= 1 and pixel_scale <= SPRITES.MAX_PIXEL_SCALE


static func make_paint_mask(payload: Dictionary, pixel_scale: int) -> Image:
	var layers := ART.new().render(payload, 0, 0.0, pixel_scale)
	var base: Image = SPRITES.car_image(payload, pixel_scale) if pixel_scale == 1 else layers["car"]
	var mask := _paint_mask(layers, base, payload, pixel_scale)
	var margin := pixel_scale / 2
	if margin == 0:
		return mask
	var inset := Image.create(mask.get_width(), mask.get_height(), false, Image.FORMAT_L8)
	inset.fill(Color.BLACK)
	for y in mask.get_height():
		for x in mask.get_width():
			if mask.get_pixel(x, y).r > 0.0 and _inside_paint(mask, Vector2i(x, y), margin):
				inset.set_pixel(x, y, Color.WHITE)
	return inset


static func _paint_mask(layers: Dictionary, base: Image, payload: Dictionary, pixel_scale: int) -> Image:
	var body: Image = layers["body"]
	var mask := Image.create(base.get_width(), base.get_height(), false, Image.FORMAT_L8)
	mask.fill(Color.BLACK)
	# Scale 1 has different cabin geometry, so native component masks do not
	# apply. Mid/light paint excludes its glass, dark cockpit, trim and wheels.
	# Accent is paint only between the bumper and the earliest spoiler row.
	var legacy_paint: Array[Color] = []
	for name: String in ["body_mid", "body_light"]:
		legacy_paint.append(Color(payload["palette"][name]))
	for y in base.get_height():
		for x in base.get_width():
			if pixel_scale == 1:
				var pixel := base.get_pixel(x, y)
				var painted_accent := y >= LEGACY_ACCENT_ROWS.x and y < LEGACY_ACCENT_ROWS.y and pixel.is_equal_approx(Color(payload["palette"]["accent"]))
				var dark_panel := (y < LEGACY_COCKPIT_ROWS.x or y > LEGACY_COCKPIT_ROWS.y) and pixel.is_equal_approx(Color(payload["palette"]["body_dark"]))
				if _matches_paint(pixel, legacy_paint) or painted_accent or dark_panel:
					mask.set_pixel(x, y, Color.WHITE)
				continue
			if body.get_pixel(x, y).a == 0.0 or base.get_pixel(x, y).a < 1.0:
				continue
			var blocked := false
			for layer: String in ["glass", "wheels", "trim"]:
				if (layers[layer] as Image).get_pixel(x, y).a > 0.0:
					blocked = true
					break
			if not blocked:
				mask.set_pixel(x, y, Color.WHITE)
	return mask


static func _matches_paint(color: Color, paints: Array[Color]) -> bool:
	for paint: Color in paints:
		if color.is_equal_approx(paint):
			return true
	return false


static func _inside_paint(mask: Image, point: Vector2i, margin: int) -> bool:
	for dy in [-margin, 0, margin]:
		for dx in [-margin, 0, margin]:
			var sample := point + Vector2i(dx, dy)
			if sample.x < 0 or sample.y < 0 or sample.x >= mask.get_width() or sample.y >= mask.get_height() or mask.get_pixelv(sample).r == 0.0:
				return false
	return true


static func _crease_distance(point: Vector2, offset: Vector2, creases: Array) -> float:
	var nearest := INF
	for crease: Array in creases:
		for i in range(crease.size() - 1):
			var a: Vector2 = crease[i] + offset
			var b: Vector2 = crease[i + 1] + offset
			nearest = minf(nearest, point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)))
	return nearest
