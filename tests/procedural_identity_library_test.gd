extends SceneTree

const CATALOG := preload("res://data/championship/catalog.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")

const DRIVER_IDS: Array[String] = ["rae", "inez", "juniper", "milo", "tess", "cass"]
const VEHICLE_IDS: Array[String] = ["rustbug", "pinbolt", "scrapjaw", "flicker"]

# Byte-identity pins captured from explicit cast/vehicle art at the reconciled Procedural 2D revision.
# These protect against silent drift on future repins or catalog changes.
const PINNED_AVATAR_PAYLOADS: Dictionary = {
	"rae": "ba530833306e2f750a03f598f7b133c6de8bab3f5b29b51c24505289d521713c",
	"inez": "e8e9d1b20a1e6f1dd2bf76a326983ca8ed72e330ac2e503ea2f8e63cce5778fe",
	"juniper": "5741f2046792107f3b8b68e38dc97a5743857e7d647299e731d53f20dafff00e",
	"milo": "a9abddf4d647867a4e44d22d231eb920443a7f591568d46145b95555f3d83885",
	"tess": "1f4a41b05957760863a0bc5f4f041f6871427c384507e3f78c1f2a70603d473a",
	"cass": "5c3c13937a90eba243d0011179b3e0158ae4ea1b675d57bb7ef08ea59c11777e",
}
const PINNED_AVATAR_PIXELS: Dictionary = {
	"rae": "b59d5dd27637d2d4182c320bd241f62a3519474b25eef6f9de34d4f23359b371",
	"inez": "9dbdcd5edc0bc64eb9d460075abfcb39a4ca76c6e2debde8ea723090e642f3f0",
	"juniper": "1934a7fef2838f84085bc6460122d9d2f409f52a1d429c0ba3b6d0ac5379d7a0",
	"milo": "95040d3d6ee5b2bad1b6a5bc312c8810193ed402a7089a838b9bbae128079479",
	"tess": "77a64877bc83ed2314bdf120e5742ed2507f9b7f6d379d17ce3faa2f804ed9e9",
	"cass": "1280674140232dcf3984c136fbf35a1c288558915d48872e3fcdfb78692129de",
}
const PINNED_CAR_PAYLOADS: Dictionary = {
	"rustbug": "8c0f4560b370a657c9ddfd48bd482649541d556f4d9b686c4bb633b143c4ba5a",
	"pinbolt": "9696556dcd4a8b305af87836230c5d0eae3c6f3f059e277876582612d3d6d47a",
	"scrapjaw": "bf3dcd56c006369eb1f9c55c4082351c6aa7743d3efd6e0f6bb9954dfc8ce680",
	"flicker": "2410a1e21a60d599207c8717bdd2f227dbeddf3769752e2107355e1af72de2e2",
}
const PINNED_CAR_PIXELS: Dictionary = {
	"rustbug": "97fd1bf7966acc1b69231ee9759ca570e6431d811aa2d3afdf63cef6bfd150a3",
	"pinbolt": "fbb10e7fae5cd57f359d5157825f75410a6bd5ed0394b872ce9ffd12fc5de5d2",
	"scrapjaw": "6ec43665664dc554096741e062bb5bab3cd07e2b5ee61aa8108365f91499025e",
	"flicker": "fa5d62930b2df9bda5a08bc6d223131136c8c9eb0542cd502e8ad7b1f98faec7",
}


func _payload_hash(payload: Dictionary) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(payload, "", false).to_utf8_buffer())
	return context.finish().hex_encode()


func _texture_hash(texture: Texture2D) -> String:
	if texture == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(texture.get_image().save_png_to_buffer())
	return context.finish().hex_encode()


func _initialize() -> void:
	if not _expect(IDENTITIES.SOURCE_REVISION == "9fc832c9638471739a61aeac1e84fe44408212f5", "the vendored source revision should stay pinned"):
		return
	for driver_id: String in DRIVER_IDS:
		var mapping: Dictionary = CATALOG.get_driver(driver_id).get("avatar_art", {})
		var payload := IDENTITIES.avatar_payload(driver_id)
		var texture := IDENTITIES.avatar_texture(driver_id)
		if not _expect(not mapping.is_empty(), "%s should define explicit avatar art" % driver_id):
			return
		if not _expect(int(payload.get("seed", -1)) == int(mapping.get("seed", -2)), "%s should keep its stable avatar seed" % driver_id):
			return
		for option: String in mapping.get("options", {}).keys():
			var actual: Variant = payload.get("facing", "") if option == "facing" else payload.get("traits", {}).get(option)
			if not _expect(actual == mapping["options"][option], "%s should keep its mapped avatar %s" % [driver_id, option]):
				return
		if not _expect(int(payload.get("schema_version", 0)) == 2, "%s should use the current gendered avatar payload" % driver_id):
			return
		if not _expect(texture != null and texture.get_size() == Vector2(128.0, 128.0), "%s should render a native 128x128 portrait" % driver_id):
			return
		if not _expect(texture == IDENTITIES.avatar_texture(driver_id), "%s should reuse the avatar texture cache" % driver_id):
			return
		if not _expect(_payload_hash(payload) == PINNED_AVATAR_PAYLOADS[driver_id], "%s avatar payload must stay byte-identical after any Procedural 2D repin" % driver_id):
			return
		if not _expect(_texture_hash(texture) == PINNED_AVATAR_PIXELS[driver_id], "%s avatar pixels must stay byte-identical after any Procedural 2D repin" % driver_id):
			return
	for vehicle_id: String in VEHICLE_IDS:
		var mapping: Dictionary = CATALOG.get_vehicle(vehicle_id).get("car_art", {})
		var payload := IDENTITIES.car_payload(vehicle_id)
		var texture := IDENTITIES.car_texture(vehicle_id)
		if not _expect(not mapping.is_empty(), "%s should define explicit car art" % vehicle_id):
			return
		if not _expect(int(payload.get("seed", -1)) == int(mapping.get("seed", -2)), "%s should keep its stable car seed" % vehicle_id):
			return
		if not _expect(String(payload.get("type", "")) == String(mapping.get("type", "")), "%s should keep its catalog silhouette" % vehicle_id):
			return
		var options: Dictionary = mapping.get("options", {})
		if not _expect(String(payload.get("palette_id", "")) == String(options.get("palette", "")), "%s should keep its mapped palette" % vehicle_id):
			return
		for part: String in options.get("parts", {}).keys():
			if not _expect(payload.get("parts", {}).get(part) == options["parts"][part], "%s should keep its mapped car %s" % [vehicle_id, part]):
				return
		if not _expect(texture != null and texture.get_size() == Vector2(96.0, 128.0), "%s should render a native 96x128 race sprite" % vehicle_id):
			return
		if not _expect(texture == IDENTITIES.car_texture(vehicle_id), "%s should reuse the car texture cache" % vehicle_id):
			return
		if not _expect(_payload_hash(payload) == PINNED_CAR_PAYLOADS[vehicle_id], "%s car payload must stay byte-identical after any Procedural 2D repin" % vehicle_id):
			return
		if not _expect(_texture_hash(texture) == PINNED_CAR_PIXELS[vehicle_id], "%s car pixels must stay byte-identical after any Procedural 2D repin" % vehicle_id):
			return
		if not _expect(IDENTITIES.car_motion_texture(vehicle_id, 0.0, 0.0) == texture, "%s rest motion frame should reuse the static car texture" % vehicle_id):
			return
		var rolling := IDENTITIES.car_motion_texture(vehicle_id, IDENTITIES.RACE_WHEEL_ROLL_DISTANCE, 0.0)
		var steered := IDENTITIES.car_motion_texture(vehicle_id, 0.0, 1.0)
		if not _expect(rolling != null and rolling.get_size() == Vector2(96.0, 128.0), "%s rolling frame should stay native 96x128" % vehicle_id):
			return
		if not _expect(steered != null and steered.get_size() == Vector2(96.0, 128.0), "%s steered frame should stay native 96x128" % vehicle_id):
			return
		if not _expect(rolling != texture, "%s rolling tyres should change the sprite" % vehicle_id):
			return
		if not _expect(steered != texture, "%s steered front wheels should change the sprite" % vehicle_id):
			return
	# base chassis payloads remain byte-identical (pins protect GURI-659)
	for vehicle_id: String in VEHICLE_IDS:
		var base_payload := IDENTITIES.car_payload(vehicle_id)
		if not _expect(_payload_hash(base_payload) == PINNED_CAR_PAYLOADS[vehicle_id], "%s base payload must remain byte-identical via car_payload" % vehicle_id):
			return
	# per-driver cosmetic overlays produce distinct looks for shared chassis
	var rustbug_rae_key := IDENTITIES.resolve_visual_key("rustbug", "rae")
	var rustbug_inez_key := IDENTITIES.resolve_visual_key("rustbug", "inez")
	if not _expect(rustbug_rae_key != rustbug_inez_key, "rae/inez must resolve distinct visual keys on rustbug"):
		return
	var rae_tex := IDENTITIES.car_texture_for_key(rustbug_rae_key) if rustbug_rae_key.find("|") != -1 else IDENTITIES.car_texture(rustbug_rae_key)
	var inez_tex := IDENTITIES.car_texture_for_key(rustbug_inez_key) if rustbug_inez_key.find("|") != -1 else IDENTITIES.car_texture(rustbug_inez_key)
	if not _expect(rae_tex != null and inez_tex != null and _texture_hash(rae_tex) != _texture_hash(inez_tex), "rae and inez must have distinct generated car textures on shared chassis"):
		return
	var flicker_tess_key := IDENTITIES.resolve_visual_key("flicker", "tess")
	var flicker_cass_key := IDENTITIES.resolve_visual_key("flicker", "cass")
	if not _expect(flicker_tess_key != flicker_cass_key, "tess/cass must resolve distinct visual keys on flicker"):
		return
	var tess_tex := IDENTITIES.car_texture_for_key(flicker_tess_key) if flicker_tess_key.find("|") != -1 else IDENTITIES.car_texture(flicker_tess_key)
	var cass_tex := IDENTITIES.car_texture_for_key(flicker_cass_key) if flicker_cass_key.find("|") != -1 else IDENTITIES.car_texture(flicker_cass_key)
	if not _expect(tess_tex != null and cass_tex != null and _texture_hash(tess_tex) != _texture_hash(cass_tex), "tess and cass must have distinct generated car textures on shared chassis"):
		return
	# per-driver motion frames are native size
	for driver_id: String in DRIVER_IDS:
		var vid := String(CATALOG.get_driver(driver_id).get("vehicle_id", "rustbug"))
		var dkey := IDENTITIES.resolve_visual_key(vid, driver_id)
		var m0 := IDENTITIES.car_motion_texture_for_key(dkey, 0.0, 0.0) if dkey.find("|") != -1 else IDENTITIES.car_motion_texture(vid, 0.0, 0.0)
		var mroll := IDENTITIES.car_motion_texture_for_key(dkey, IDENTITIES.RACE_WHEEL_ROLL_DISTANCE, 0.0) if dkey.find("|") != -1 else IDENTITIES.car_motion_texture(vid, IDENTITIES.RACE_WHEEL_ROLL_DISTANCE, 0.0)
		if not _expect(m0 != null and m0.get_size() == Vector2(96.0, 128.0), "%s driver motion rest must be 96x128" % driver_id):
			return
		if not _expect(mroll != null and mroll.get_size() == Vector2(96.0, 128.0), "%s driver motion roll must be 96x128" % driver_id):
			return
	# within-field uniqueness + determinism (including shared chassis)
	var field_a: Array[Dictionary] = [
		{"vehicle_id": "flicker", "driver_id": "cass", "slot": 1},
		{"vehicle_id": "flicker", "driver_id": "tess", "slot": 2},
		{"vehicle_id": "rustbug", "driver_id": "rae", "slot": 0},
	]
	var keys_a := IDENTITIES.resolve_field_visual_keys(field_a)
	if not _expect(String(keys_a[0]) != String(keys_a[1]), "field must disambiguate cass vs tess"):
		return
	var keys_a2 := IDENTITIES.resolve_field_visual_keys(field_a)
	if not _expect(keys_a[0] == keys_a2[0] and keys_a[1] == keys_a2[1], "same field input must produce identical visual keys"):
		return
	# different order but same members should still unique (stable by process order + slot)
	var field_b: Array[Dictionary] = [
		{"vehicle_id": "flicker", "driver_id": "tess", "slot": 2},
		{"vehicle_id": "flicker", "driver_id": "cass", "slot": 1},
	]
	var keys_b := IDENTITIES.resolve_field_visual_keys(field_b)
	if not _expect(String(keys_b[0]) != String(keys_b[1]), "field_b must still produce distinct keys"):
		return
	# duplicate entries resolve to the same look and must still separate visually
	var field_dup: Array[Dictionary] = [
		{"vehicle_id": "flicker", "driver_id": "tess", "slot": 1},
		{"vehicle_id": "flicker", "driver_id": "tess", "slot": 2},
	]
	var keys_dup := IDENTITIES.resolve_field_visual_keys(field_dup)
	if not _expect(String(keys_dup[0]) != String(keys_dup[1]), "duplicate field entries must resolve distinct keys"):
		return
	var dup_texture_a := IDENTITIES.car_texture_for_key(String(keys_dup[0]))
	var dup_texture_b := IDENTITIES.car_texture_for_key(String(keys_dup[1]))
	if not _expect(dup_texture_a != null and dup_texture_b != null, "duplicate field entries must render"):
		return
	if not _expect(_texture_hash(dup_texture_a) != _texture_hash(dup_texture_b), "duplicate field entries must render distinct cars, not just distinct keys"):
		return
	print("PROCEDURAL_IDENTITY_LIBRARY_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("PROCEDURAL_IDENTITY_LIBRARY_TEST FAIL: " + message)
	quit(1)
	return false
