extends SceneTree

const CATALOG := preload("res://data/championship/catalog.gd")
const IDENTITIES := preload("res://scripts/presentation/procedural_identity_library.gd")

const DRIVER_IDS: Array[String] = ["rae", "inez", "juniper", "milo", "tess", "cass"]
const VEHICLE_IDS: Array[String] = ["rustbug", "pinbolt", "scrapjaw", "flicker"]


func _initialize() -> void:
	if not _expect(IDENTITIES.SOURCE_REVISION == "f8eb03805f3fcc30fec56553033ad01988ef7857", "the vendored source revision should stay pinned"):
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
		if not _expect(texture != null and texture.get_size() == Vector2(64.0, 64.0), "%s should render a 64x64 portrait" % driver_id):
			return
		if not _expect(texture == IDENTITIES.avatar_texture(driver_id), "%s should reuse the avatar texture cache" % driver_id):
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
		if not _expect(texture != null and texture.get_size() == Vector2(48.0, 64.0), "%s should render a 48x64 race sprite" % vehicle_id):
			return
		if not _expect(texture == IDENTITIES.car_texture(vehicle_id), "%s should reuse the car texture cache" % vehicle_id):
			return
	print("PROCEDURAL_IDENTITY_LIBRARY_TEST PASS")
	quit(0)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("PROCEDURAL_IDENTITY_LIBRARY_TEST FAIL: " + message)
	quit(1)
	return false
