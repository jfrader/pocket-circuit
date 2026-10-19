extends SceneTree

const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")
const SPRITES := preload("res://scripts/vendor/procedural_2d/procedural_car_sprites.gd")
const NATIVE := preload("res://scripts/vendor/procedural_2d/procedural_car_art.gd")
const HERO_IDS := ["rustbug", "pinbolt", "scrapjaw", "flicker"]
const PINS := {
	"rustbug": ["dc5bc5951e4de724ffabb337b549f1a1cdc1b84bb8e0e7f3369bb907854ac98c", "23149489cb30562ed0409fbe0e9138679568e56e6a681cfdd25b43ed42e80cc8"],
	"pinbolt": ["3d1bfe40d6cad86eda90e8e65405c0f7630183845f042adf9d468cb5509b0ca9", "1ad6709cc806cfb11147f847bfc5c401ae91275f01b314f28c27749f8cb9c7dc"],
	"scrapjaw": ["784edb28654c5c14240e0b5dd83c3c3b05c92bcbd306bfd0d39974422c43e291", "fd600305f1569b13e64f9cdadbbf7354ad0fd1d3196fcbc2608720e95f446647"],
	"flicker": ["c32079b685bab8725e79565a336a677a16ad6b9b6c24af6f1bacf6a8e0ead394", "baec8db694ede2c031127459afb774788853b5dd81532f7d99ca5163e9a19553"],
	"thimble": ["5892e91626a000c635429aa3e2ea63f09adf46296ba7ce8075c6ce87f3cf5896", "32615c231c4b9ba5d1cfbd442514a54061622c74e2fb33930eebc3fe3cbaa094"],
	"spindle": ["069c8d6369f056ea2520eadca8aef01aa1317f18f87db623d19d88a0651d5823", "ba00d040e021013be63a60a7faa80b5e161039971d4b6a59aac24d3472e54659"],
	"anvil": ["4347b0256740d23b2aefa4646c2b4d3a5c6081c04b9ab86e88381e9f17d81fc7", "5b3bdfe6edcd21cbc54881c3b07a0df1edc2bc268654704f630ec506e22c4bf8"],
	"dustmite": ["d7e6d1978bc483bdb927a07b0e6c0b4ad091b3812aa6cee2de7c3d351c14c420", "ea35a647402ed2b639595ed4100a97fa99a7c5e6500a7322ef894ae69b658b35"],
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for id: String in PINS:
		var payload := IDENTITIES.car_payload(id)
		for scale in [1, 2]:
			if not _expect(_hash(SPRITES.car_image(payload, scale)) == PINS[id][scale - 1], "existing scale %d pixels remain byte-identical for %s" % [scale, id]):
				return
	for id: String in HERO_IDS:
		var payload := IDENTITIES.car_payload(id)
		var native := SPRITES.car_image(payload, 2)
		for scale in [5, 6]:
			var renderer := NATIVE.new()
			var layers: Dictionary = renderer.render(payload, 0, 0.0, scale)
			var hero: Image = layers["car"]
			if not _expect(renderer.outside_writes == 0 and hero.get_size() == Vector2i(48 * scale, 64 * scale), "hero mode rasterizes full-sized layers within its canvas"):
				return
			var enlarged := native.duplicate() as Image
			enlarged.resize(hero.get_width(), hero.get_height(), Image.INTERPOLATE_NEAREST)
			if not _expect(_hash(hero) != _hash(enlarged), "hero art is genuinely rerasterized, not a resized native image"):
				return
			var ratio := float(scale) / 2.0
			var native_bounds := Rect2(native.get_used_rect())
			var hero_bounds := Rect2(hero.get_used_rect())
			if not _expect((hero_bounds.position / ratio - native_bounds.position).length() < 3 and (hero_bounds.size / ratio - native_bounds.size).length() < 4, "hero keeps the existing silhouette footprint"):
				return
			for layer: String in ["body", "glass", "wheels", "trim"]:
				if not _expect((layers[layer] as Image).get_size() == hero.get_size(), "all component layers rasterize at hero resolution"):
					return
		var posed := NATIVE.new().render(payload, 1, 12.0, 6)["car"] as Image
		if not _expect(_hash(posed) != _hash(SPRITES.car_image(payload, 6)), "hero mode preserves wheel and steering variation"):
			return
	print("RUN_CAR_HERO_RESOLUTION_TEST PASS legacy_hashes=%d silhouettes=%d scales=5,6 raster=native" % [PINS.size() * 2, HERO_IDS.size()])
	quit(0)


func _hash(image: Image) -> String:
	return image.get_data().hex_encode().sha256_text()


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error("RUN_CAR_HERO_RESOLUTION_TEST FAIL: " + message)
		quit(1)
	return condition
