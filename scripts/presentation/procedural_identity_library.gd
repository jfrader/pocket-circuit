class_name ProceduralIdentityLibrary
extends RefCounted

const SOURCE_REVISION := "9fc832c9638471739a61aeac1e84fe44408212f5"
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
static var motion_image_generations := 0


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
		var empty: Array = []
		empty.resize(5)
		per_spin[spin] = empty
	var textures: Array = per_spin[spin]
	pose = clampi(pose, 0, textures.size() - 1)
	if textures[pose] == null:
		if spin == 0 and pose == REST_STEER_POSE:
			textures[pose] = car_texture(vehicle_id)
			return textures[pose]
		var payload := car_payload(vehicle_id)
		if payload.is_empty():
			return null
		var image := CAR_SPRITES.car_pose_image(payload, spin, pose, NATIVE_PIXEL_SCALE)
		if image != null:
			textures[pose] = ImageTexture.create_from_image(image)
			motion_image_generations += 1
	return textures[pose]


static func motion_preparation_plan(vehicle_id: String) -> Dictionary:
	if not _car_spin_cache.has(vehicle_id):
		_car_spin_cache[vehicle_id] = {}
	var per_spin: Dictionary = _car_spin_cache[vehicle_id]
	var jobs: Array[Vector2i] = []
	for spin in CAR_SPRITES.WHEEL_FRAME_COUNT:
		if not per_spin.has(spin):
			var frames: Array = []
			frames.resize(5)
			per_spin[spin] = frames
		for pose in 5:
			if spin == 0 and pose == REST_STEER_POSE and _car_texture_cache.has(vehicle_id):
				per_spin[spin][pose] = _car_texture_cache[vehicle_id]
			if per_spin[spin][pose] == null:
				jobs.append(Vector2i(spin, pose))
	return {"payload": car_payload(vehicle_id), "jobs": jobs}


static func render_motion_plan(plan: Dictionary) -> Dictionary:
	var images: Array[Image] = []
	for job: Vector2i in plan["jobs"]:
		images.append(CAR_SPRITES.car_pose_image(plan["payload"], job.x, job.y, NATIVE_PIXEL_SCALE))
	return {"jobs": plan["jobs"], "images": images}


static func install_motion_image(vehicle_id: String, frame: Vector2i, image: Image) -> bool:
	if image == null:
		return false
	var texture := ImageTexture.create_from_image(image)
	_car_spin_cache[vehicle_id][frame.x][frame.y] = texture
	if frame.x == 0 and frame.y == REST_STEER_POSE:
		_car_texture_cache[vehicle_id] = texture
	motion_image_generations += 1
	return true
