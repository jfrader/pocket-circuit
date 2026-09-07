class_name ProceduralIdentityLibrary
extends RefCounted

const SOURCE_REVISION := "d60ed1f95dc7154f7870c62d6058ed440ed3eb09"
const NATIVE_PIXEL_SCALE := 2
const CATALOG := preload("res://data/championship/catalog.gd")
const AVATAR_GENERATOR := preload("res://scripts/vendor/procedural_2d/procedural_avatar_generator.gd")
const AVATAR_SPRITES := preload("res://scripts/vendor/procedural_2d/procedural_avatar_sprites.gd")
const CAR_GENERATOR := preload("res://scripts/vendor/procedural_2d/procedural_car_generator.gd")
const CAR_SPRITES := preload("res://scripts/vendor/procedural_2d/procedural_car_sprites.gd")

const REST_STEER_POSE := 2
const RACE_WHEEL_ROLL_DISTANCE := 64.0

static var _avatar_payload_cache: Dictionary = {}
static var _avatar_texture_cache: Dictionary = {}
static var _car_payload_cache: Dictionary = {}
static var _car_texture_cache: Dictionary = {}
static var _car_spin_cache: Dictionary = {}


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
	var texture := AVATAR_SPRITES.avatar_texture(payload, NATIVE_PIXEL_SCALE)
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
	var texture := CAR_SPRITES.car_texture(payload, NATIVE_PIXEL_SCALE)
	if texture:
		_car_texture_cache[vehicle_id] = texture
	return texture


static func car_motion_texture(vehicle_id: String, travel: float, steer: float) -> Texture2D:
	var spin := 0
	if travel > 0.0:
		spin = posmod(int(floor(travel / RACE_WHEEL_ROLL_DISTANCE)), CAR_SPRITES.WHEEL_FRAME_COUNT)
	return _texture_for_spin_pose(vehicle_id, spin, CAR_SPRITES.steer_pose_index(steer))


static func _texture_for_spin_pose(vehicle_id: String, spin: int, pose: int) -> Texture2D:
	if not _car_spin_cache.has(vehicle_id):
		_car_spin_cache[vehicle_id] = {}
	var per_spin: Dictionary = _car_spin_cache[vehicle_id]
	if not per_spin.has(spin):
		var payload := car_payload(vehicle_id)
		if payload.is_empty():
			return null
		var images: Array[Image] = CAR_SPRITES.car_steer_frames(payload, spin, NATIVE_PIXEL_SCALE)
		var textures: Array = []
		for pose_index in range(images.size()):
			if spin == 0 and pose_index == REST_STEER_POSE:
				textures.append(car_texture(vehicle_id))
			elif images[pose_index] == null:
				textures.append(null)
			else:
				textures.append(ImageTexture.create_from_image(images[pose_index]))
		per_spin[spin] = textures
	var frames: Array = per_spin[spin]
	if frames.is_empty():
		return car_texture(vehicle_id)
	return frames[clampi(pose, 0, frames.size() - 1)]
