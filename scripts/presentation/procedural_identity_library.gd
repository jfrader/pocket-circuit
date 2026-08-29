class_name ProceduralIdentityLibrary
extends RefCounted

const SOURCE_REVISION := "f8eb03805f3fcc30fec56553033ad01988ef7857"
const CATALOG := preload("res://data/championship/catalog.gd")
const AVATAR_GENERATOR := preload("res://scripts/vendor/procedural_2d/procedural_avatar_generator.gd")
const AVATAR_SPRITES := preload("res://scripts/vendor/procedural_2d/procedural_avatar_sprites.gd")
const CAR_GENERATOR := preload("res://scripts/vendor/procedural_2d/procedural_car_generator.gd")
const CAR_SPRITES := preload("res://scripts/vendor/procedural_2d/procedural_car_sprites.gd")

static var _avatar_payload_cache: Dictionary = {}
static var _avatar_texture_cache: Dictionary = {}
static var _car_payload_cache: Dictionary = {}
static var _car_texture_cache: Dictionary = {}


static func avatar_payload(driver_id: String) -> Dictionary:
	if _avatar_payload_cache.has(driver_id):
		return (_avatar_payload_cache[driver_id] as Dictionary).duplicate(true)
	var driver := CATALOG.get_driver(driver_id)
	var art: Dictionary = driver.get("avatar_art", {})
	if art.is_empty():
		push_error("No procedural avatar art is configured for driver '%s'." % driver_id)
		return {}
	var payload := AVATAR_GENERATOR.generate(int(art["seed"]), art.get("options", {}))
	var payload_error := AVATAR_SPRITES.validate_payload(payload)
	if not payload_error.is_empty():
		push_error("Avatar art for '%s' is invalid: %s" % [driver_id, payload_error])
		return {}
	_avatar_payload_cache[driver_id] = payload
	return payload.duplicate(true)


static func avatar_texture(driver_id: String) -> Texture2D:
	if _avatar_texture_cache.has(driver_id):
		return _avatar_texture_cache[driver_id]
	var payload := avatar_payload(driver_id)
	if payload.is_empty():
		return null
	var texture := AVATAR_SPRITES.avatar_texture(payload)
	if texture:
		_avatar_texture_cache[driver_id] = texture
	return texture


static func car_payload(vehicle_id: String) -> Dictionary:
	if _car_payload_cache.has(vehicle_id):
		return (_car_payload_cache[vehicle_id] as Dictionary).duplicate(true)
	var vehicle := CATALOG.get_vehicle(vehicle_id)
	var art: Dictionary = vehicle.get("car_art", {})
	if art.is_empty():
		push_error("No procedural car art is configured for vehicle '%s'." % vehicle_id)
		return {}
	var payload := CAR_GENERATOR.generate(int(art["seed"]), String(art["type"]), art.get("options", {}))
	var payload_error := CAR_SPRITES.validate_payload(payload)
	if not payload_error.is_empty():
		push_error("Car art for '%s' is invalid: %s" % [vehicle_id, payload_error])
		return {}
	_car_payload_cache[vehicle_id] = payload
	return payload.duplicate(true)


static func car_texture(vehicle_id: String) -> Texture2D:
	if _car_texture_cache.has(vehicle_id):
		return _car_texture_cache[vehicle_id]
	var payload := car_payload(vehicle_id)
	if payload.is_empty():
		return null
	var texture := CAR_SPRITES.car_texture(payload)
	if texture:
		_car_texture_cache[vehicle_id] = texture
	return texture
