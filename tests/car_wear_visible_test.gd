extends SceneTree

const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const SPRITES := preload("res://scripts/vendor/procedural_2d/procedural_car_sprites.gd")
const ART := preload("res://scripts/vendor/procedural_2d/procedural_car_art.gd")
const STATE := preload("res://scripts/progression/run_state.gd")
const WEAR := preload("res://scripts/presentation/car_wear_presenter.gd")
const IDS := ["rustbug", "pinbolt", "scrapjaw", "flicker", "thimble", "spindle", "anvil", "dustmite"]
const NATIVE_PINS := {
	43: "13ec32495f5ae132b07c874687e605a6d7a446e50c0199ccbaf6e9422e6c961d",
	55: "88010d6fbb9da46d3d26a9fa23180562081a4fd495921be169ba9742f6eafd58",
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _test_small_body_tint():
		return
	if not _test_minimum_marks() or not _test_native_pins():
		return
	if not _test_patterns():
		return
	for id: String in IDS:
		var payload := IDENTITIES.car_payload(id)
		var original := IDENTITIES.car_texture(id).get_image().get_data()
		for scale in range(1, SPRITES.MAX_PIXEL_SCALE + 1):
			var base := SPRITES.car_image(payload, scale)
			var layers := ART.new().render(payload, 0, 0.0, scale)
			var earlier: Array[String] = []
			for level: String in STATE.WEAR_LEVELS:
				var texture := IDENTITIES.car_texture_with_wear(id, level, scale)
				var image := texture.get_image()
				var overlay := IDENTITIES.car_wear_overlay_for_key(id, level, scale)
				var marks := overlay.get_image()
				if scale == 2 and not _expect(WEAR.overlay_image(payload, level, scale).get_data() == marks.get_data(), "fresh wear rendering is deterministic"):
					return
				if not _expect(image.get_size() == base.get_size(), "wear respects requested pixel scale"):
					return
				for y in base.get_height():
					for x in base.get_width():
						if marks.get_pixel(x, y).a == 0.0:
							continue
						var allowed := (layers["body"] as Image).get_pixel(x, y).a > 0.0 and (layers["glass"] as Image).get_pixel(x, y).a == 0.0 and (layers["wheels"] as Image).get_pixel(x, y).a == 0.0 and (layers["trim"] as Image).get_pixel(x, y).a == 0.0 and base.get_pixel(x, y).a == 1.0
						if scale == 1:
							allowed = _legacy_body_pixel(base.get_pixel(x, y), payload)
						if not allowed:
							_expect(false, "wear stays on opaque body, off glass/wheels/trim/shadow")
							return
				if level == "clean":
					if not _expect(image.get_data() == base.get_data() and marks.get_used_rect().size == Vector2i.ZERO, "clean leaves legacy pixels untouched"):
						return
				else:
					for previous: String in earlier:
						for height in [28, 32, 43, 55]:
							var sized := IDENTITIES.car_texture_with_wear(id, level, scale, height).get_image()
							var small := sized.duplicate() as Image
							var prior := IDENTITIES.car_texture_with_wear(id, previous, scale, height).get_image().duplicate() as Image
							var width := roundi(float(height) * image.get_width() / image.get_height())
							small.resize(width, height, Image.INTERPOLATE_NEAREST)
							prior.resize(width, height, Image.INTERPOLATE_NEAREST)
							var difference := _visible_difference(small, prior)
							var minimum_difference := 12 if scale == 2 and height <= 32 and id in ["pinbolt", "scrapjaw"] else 6
							if not _expect(difference >= minimum_difference, "%s %s scale %d visibly changes at %dpx (pixels=%d)" % [id, level, scale, height, difference]):
								return
				var repeated := IDENTITIES.car_texture_with_wear(id, level, scale)
				if not _expect(repeated == texture, "wear requests reuse cached deterministic textures"):
					return
				earlier.append(level)
		if not _expect(IDENTITIES.car_texture(id).get_image().get_data() == original, "wear never mutates base cache"):
			return
		if not _test_dent_sizes(id):
			return
	var key := IDENTITIES.resolve_visual_key("rustbug", "rae")
	var cosmetic_base := IDENTITIES.car_texture_for_key(key).get_image().get_data()
	var cosmetic_worn := IDENTITIES.car_texture_with_wear_for_key(key, "dented")
	if not _expect(cosmetic_worn.get_image().get_data() != cosmetic_base and IDENTITIES.car_texture_for_key(key).get_image().get_data() == cosmetic_base, "resolved race livery receives separate wear"):
		return
	print("CAR_WEAR_VISIBLE_TEST PASS vehicles=8 scales=1..6 levels=4 heights=28,32,43,55 minimum_marks=32px body_tint=small_only native_43_55=unchanged body_clip=native_exact legacy=unchanged")
	quit(0)


func _test_patterns() -> bool:
	for id: String in ["rustbug", "scrapjaw"]:
		var dust := IDENTITIES.car_wear_overlay_for_key(id, "dusty", 2, 43).get_image()
		var rust := IDENTITIES.car_wear_overlay_for_key(id, "rusty", 2, 43).get_image()
		var dusty_pixels := 0
		var rusty_pixels := 0
		for y in dust.get_height():
			for x in dust.get_width():
				var fleck := dust.get_pixel(x, y)
				if fleck.a > 0.0:
					dusty_pixels += 1
					if not _expect(fleck.a <= 0.5, "dust is low-contrast flecks, without bright scratches"):
						return false
				if rust.get_pixel(x, y).a > 0.0:
					rusty_pixels += 1
		if not _expect(dusty_pixels > rusty_pixels * 2 and rusty_pixels > 0, "gold/red dust has broad coverage; rust is sparse patches, not a recolor"):
			return false
	return true


func _test_small_body_tint() -> bool:
	# This roof pixel is painted but outside every authored minimum-size mark.
	var roof := Vector2i(48, 85)
	for id: String in ["scrapjaw", "spindle"]:
		var base := IDENTITIES.car_texture(id).get_image().get_pixelv(roof)
		for height in [28, 32]:
			for level: String in ["dusty", "rusty", "dented"]:
				var overlay := IDENTITIES.car_wear_overlay_for_key(id, level, 2, height).get_image().get_pixelv(roof)
				if not _expect(overlay.a > 0.0, "small wear tints painted pixels outside its patterns"):
					return false
				var actual := IDENTITIES.car_texture_with_wear(id, level, 2, height).get_image().get_pixelv(roof)
				if level == "dusty":
					var before := maxf(base.r, maxf(base.g, base.b)) - minf(base.r, minf(base.g, base.b))
					var after := maxf(actual.r, maxf(actual.g, actual.b)) - minf(actual.r, minf(actual.g, actual.b))
					if not _expect(absf(after - before * 0.82) < 0.01, "dust desaturates unmarked paint by 18 percent"):
						return false
				elif level == "rusty":
					if not _expect(actual.get_luminance() < base.get_luminance() and actual.r / actual.b > base.r / base.b, "rust globally darkens and warms unmarked paint"):
						return false
				elif not _expect(absf(actual.get_luminance() - base.get_luminance() * 0.88) < 0.01, "dents darken unmarked paint by 12 percent"):
					return false
	return true


func _test_minimum_marks() -> bool:
	for id: String in ["pinbolt", "scrapjaw", "rustbug", "spindle"]:
		var base := IDENTITIES.car_texture(id).get_image()
		for level: String in ["dusty", "rusty", "dented"]:
			var minimum := IDENTITIES.car_wear_overlay_for_key(id, level, 2, 28)
			var reference := IDENTITIES.car_wear_overlay_for_key(id, level, 2, 32)
			if not _expect(minimum == reference, "28px and 32px reuse the minimum-sized reference marks"):
				return false
			if not _expect(minimum != IDENTITIES.car_wear_overlay_for_key(id, level, 2, 43), "minimum marks have a separate cache entry from native wear"):
				return false
			var image := minimum.get_image()
			var light_pixels := 0
			var dark_pixels := 0
			var pattern_pixels := 0
			var tint_pixels := 0
			var lightened_paint := 0
			var darkened_paint := 0
			var tint_alpha := 0.18 if level == "dusty" else (0.22 if level == "rusty" else 0.12)
			var pattern_alpha := 0.55 if level == "dusty" else (0.85 if level == "rusty" else 1.0)
			var combined_alpha := tint_alpha + pattern_alpha * (1.0 - tint_alpha)
			for y in image.get_height():
				for x in image.get_width():
					var mark := image.get_pixel(x, y)
					if mark.a == 0.0:
						continue
					var on_pattern := absf(mark.a - combined_alpha) < 0.01
					var on_tint := absf(mark.a - tint_alpha) < 0.01
					if not _expect(on_pattern or on_tint, "small body tint composes over the existing pattern alpha"):
						return false
					pattern_pixels += int(on_pattern)
					tint_pixels += int(on_tint)
					if on_pattern:
						var paint := base.get_pixel(x, y)
						var final_luminance := paint.blend(mark).get_luminance()
						lightened_paint += int(final_luminance > paint.get_luminance())
						darkened_paint += int(final_luminance < paint.get_luminance())
					light_pixels += int(mark.get_luminance() > 0.7)
					dark_pixels += int(mark.get_luminance() < 0.15)
			if not _expect(pattern_pixels > 0 and tint_pixels > 0, "global tint and authored patterns both remain visible"):
				return false
			if level == "dented" and not _expect(light_pixels > 0 and dark_pixels > 0, "small cracks have a bright core and a dark outline"):
				return false
			if level == "dusty" and id == "rustbug" and not _expect(darkened_paint > 0, "dust flecks darken sampled light paint"):
				return false
			if level == "dusty" and id == "spindle" and not _expect(lightened_paint > 0, "dust flecks brighten sampled dark paint"):
				return false
			if level == "dented" and id in ["pinbolt", "scrapjaw"]:
				image = image.duplicate() as Image
				image.resize(21, 28, Image.INTERPOLATE_NEAREST)
				var visible_core := 0
				var visible_outline := 0
				for y in image.get_height():
					for x in image.get_width():
						var pixel := image.get_pixel(x, y)
						if pixel.a > 0.99:
							visible_core += int(pixel.get_luminance() > 0.7)
							visible_outline += int(pixel.get_luminance() < 0.15)
				if not _expect(visible_core >= 4 and visible_outline >= 4, "blue/red 28px cracks retain a visible light core and dark outline"):
					return false
	return true


func _test_native_pins() -> bool:
	for height: int in NATIVE_PINS:
		var bytes := PackedByteArray()
		for id: String in ["pinbolt", "scrapjaw", "rustbug", "spindle"]:
			for level: String in ["dusty", "rusty", "dented"]:
				bytes.append_array(IDENTITIES.car_texture_with_wear(id, level, 2, height).get_image().get_data())
		if not _expect(bytes.hex_encode().sha256_text() == NATIVE_PINS[height], "43px+ wear remains byte-identical"):
			return false
	return true


func _test_dent_sizes(id: String) -> bool:
	var small := IDENTITIES.car_wear_overlay_for_key(id, "dented", 2, 28).get_image()
	var large := IDENTITIES.car_wear_overlay_for_key(id, "dented", 2, 55).get_image()
	if not _expect(small.get_data() != large.get_data(), "dent shapes adapt to display size, not raster scale"):
		return false
	var layers := ART.new().render(IDENTITIES.car_payload(id), 0, 0.0, 2)
	for image: Image in [small, large]:
		for y in image.get_height():
			for x in image.get_width():
				if image.get_pixel(x, y).a == 0.0:
					continue
				for layer: String in ["glass", "wheels", "trim"]:
					for offset: Vector2i in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
						if (layers[layer] as Image).get_pixelv(Vector2i(x, y) + offset).a > 0.0:
							return _expect(false, "both dent sizes leave a clear safety gap around glass/wheels/trim")
				var stroke := image.get_pixel(x, y)
				if stroke.r > 0.5 and stroke.g > 0.5 and stroke.b > 0.5 and y >= 48 and y < 92:
					return _expect(false, "bright dent strokes never enter the cabin band")
	return true


func _legacy_body_pixel(pixel: Color, payload: Dictionary) -> bool:
	if pixel.a != 1.0:
		return false
	for field: String in ["outline", "shadow", "tire", "tire_highlight", "hub", "hub_light", "glass_dark", "glass_mid", "glass_light", "headlight", "taillight", "trim"]:
		if pixel.is_equal_approx(Color(payload["palette"][field])):
			return false
	for rubber: Color in [SPRITES.TYRE_OUTLINE, SPRITES.TYRE_RUBBER, SPRITES.TYRE_HIGHLIGHT, SPRITES.TYRE_HUB, SPRITES.TYRE_HUB_LIGHT]:
		if pixel.is_equal_approx(rubber):
			return false
	return true


func _visible_difference(a: Image, b: Image) -> int:
	var changed := 0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if maxf(absf(ca.r - cb.r), maxf(absf(ca.g - cb.g), absf(ca.b - cb.b))) > 0.12:
				changed += 1
	return changed


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("CAR_WEAR_VISIBLE_TEST FAIL: " + message)
		quit(1)
	return condition
