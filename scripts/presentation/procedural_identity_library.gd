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
static var _visual_resolutions: Dictionary = {}
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
	var key := vehicle_id
	if _car_payload_cache.has(key):
		return (_car_payload_cache[key] as Dictionary).duplicate(true)
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
	_car_payload_cache[key] = payload
	if not _visual_resolutions.has(key):
		_visual_resolutions[key] = {"vehicle_id": vehicle_id, "cosmetic": {}}
	return payload.duplicate(true)


static func car_texture(vehicle_id: String) -> Texture2D:
	var key := vehicle_id
	if _car_texture_cache.has(key):
		return _car_texture_cache[key]
	var payload := car_payload(key)
	if payload.is_empty():
		return null
	var texture := CAR_SPRITES.car_texture(payload, NATIVE_PIXEL_SCALE)
	if texture:
		_car_texture_cache[key] = texture
	return texture


static func car_motion_texture(vehicle_id: String, travel: float, steer: float) -> Texture2D:
	return car_motion_texture_for_key(vehicle_id, travel, steer)


static func _texture_for_spin_pose(key: String, spin: int, pose: int) -> Texture2D:
	if not _car_spin_cache.has(key):
		_car_spin_cache[key] = {}
	var per_spin: Dictionary = _car_spin_cache[key]
	if not per_spin.has(spin):
		var empty: Array = []
		empty.resize(5)
		per_spin[spin] = empty
	var textures: Array = per_spin[spin]
	pose = clampi(pose, 0, textures.size() - 1)
	if textures[pose] == null:
		if spin == 0 and pose == REST_STEER_POSE:
			textures[pose] = _get_car_texture(key)
			return textures[pose]
		var payload := car_payload_for_key(key) if _is_visual_key(key) else car_payload(key)
		if payload.is_empty():
			return null
		var image := CAR_SPRITES.car_pose_image(payload, spin, pose, NATIVE_PIXEL_SCALE)
		if image != null:
			textures[pose] = ImageTexture.create_from_image(image)
			motion_image_generations += 1
	return textures[pose]


static func motion_preparation_plan(vehicle_id: String) -> Dictionary:
	return motion_preparation_plan_for_key(vehicle_id)


static func render_motion_plan(plan: Dictionary) -> Dictionary:
	var images: Array[Image] = []
	for job: Vector2i in plan["jobs"]:
		images.append(CAR_SPRITES.car_pose_image(plan["payload"], job.x, job.y, NATIVE_PIXEL_SCALE))
	return {"jobs": plan["jobs"], "images": images}


static func install_motion_image(vehicle_id: String, frame: Vector2i, image: Image) -> bool:
	return install_motion_image_for_key(vehicle_id, frame, image)


static func install_motion_image_for_key(visual_key: String, frame: Vector2i, image: Image) -> bool:
	if image == null:
		return false
	var texture := ImageTexture.create_from_image(image)
	if not _car_spin_cache.has(visual_key):
		_car_spin_cache[visual_key] = {}
	var per_spin: Dictionary = _car_spin_cache[visual_key]
	if not per_spin.has(frame.x):
		var frames: Array = []
		frames.resize(5)
		per_spin[frame.x] = frames
	per_spin[frame.x][frame.y] = texture
	if frame.x == 0 and frame.y == REST_STEER_POSE:
		_car_texture_cache[visual_key] = texture
	motion_image_generations += 1
	return true


static func resolve_visual_key(vehicle_id: String, driver_id: String = "") -> String:
	if driver_id.is_empty():
		var key := vehicle_id
		if not _visual_resolutions.has(key):
			_visual_resolutions[key] = {"vehicle_id": vehicle_id, "cosmetic": {}}
		return key
	var driver := CATALOG.get_driver(driver_id)
	var livery: Dictionary = driver.get("car_livery", {})
	if livery.is_empty():
		var key := vehicle_id
		if not _visual_resolutions.has(key):
			_visual_resolutions[key] = {"vehicle_id": vehicle_id, "cosmetic": {}}
		return key
	var cosmetic := livery.duplicate()
	var sig := _livery_signature(cosmetic)
	var key := "%s|%s" % [vehicle_id, sig]
	if not _visual_resolutions.has(key):
		_visual_resolutions[key] = {"vehicle_id": vehicle_id, "cosmetic": cosmetic}
	return key


static func resolve_visual_key_with_disambig(vehicle_id: String, driver_id: String, disambig: int = 0) -> String:
	var base_cosmetic := _effective_livery_for(vehicle_id, driver_id)
	var use_cosmetic := base_cosmetic if disambig <= 0 else _shift_cosmetic(base_cosmetic, disambig)
	var sig := _livery_signature(use_cosmetic)
	var key := vehicle_id
	if disambig > 0 or not use_cosmetic.is_empty():
		var dis_prefix := ("d%d_" % disambig) if disambig > 0 else ""
		key = "%s|%s%s" % [vehicle_id, dis_prefix, sig]
	if not _visual_resolutions.has(key):
		_visual_resolutions[key] = {"vehicle_id": vehicle_id, "cosmetic": use_cosmetic}
	return key


static func resolve_field_visual_keys(racers: Array[Dictionary]) -> Dictionary:
	# racers entries: {"vehicle_id": String, "driver_id": String, "slot": int (optional)}
	var result: Dictionary = {}
	var used: Dictionary = {}
	for i in racers.size():
		var r: Dictionary = racers[i]
		var vid := String(r.get("vehicle_id", "rustbug"))
		var did := String(r.get("driver_id", ""))
		var slot := int(r.get("slot", i))
		var ckey := resolve_visual_key(vid, did)
		var final := ckey
		var dis := 0
		if used.has(ckey):
			dis = slot if slot > 0 else (i + 1)
			final = resolve_visual_key_with_disambig(vid, did, dis)
			while used.has(final) and dis < 100:
				dis += 1
				final = resolve_visual_key_with_disambig(vid, did, dis)
		used[final] = true
		result[i] = final
	return result


static func car_payload_for_key(visual_key: String) -> Dictionary:
	if _car_payload_cache.has(visual_key):
		return (_car_payload_cache[visual_key] as Dictionary).duplicate(true)
	var cfg: Dictionary = _visual_resolutions.get(visual_key, {"vehicle_id": visual_key, "cosmetic": {}})
	var vid := String(cfg.get("vehicle_id", visual_key))
	var cosmetic: Dictionary = cfg.get("cosmetic", {})
	var vehicle := CATALOG.get_vehicle(vid)
	var art: Dictionary = vehicle.get("car_art", {})
	if art.is_empty():
		push_error("No procedural car art is configured for visual key '%s' (vehicle '%s')." % [visual_key, vid])
		return {}
	var base_opts: Dictionary = art.get("options", {}).duplicate(true)
	var merged := _merge_cosmetic(base_opts, cosmetic)
	var payload := CAR_GENERATOR.generate(int(art.get("seed", 0)), String(art.get("type", "")), merged)
	var payload_error := CAR_SPRITES.validate_payload(payload)
	if not payload_error.is_empty():
		push_error("Car art for visual key '%s' is invalid: %s" % [visual_key, payload_error])
		return {}
	_car_payload_cache[visual_key] = payload
	return payload.duplicate(true)


static func car_texture_for_key(visual_key: String) -> Texture2D:
	if _car_texture_cache.has(visual_key):
		return _car_texture_cache[visual_key]
	var payload := car_payload_for_key(visual_key)
	if payload.is_empty():
		return null
	var texture := CAR_SPRITES.car_texture(payload, NATIVE_PIXEL_SCALE)
	if texture:
		_car_texture_cache[visual_key] = texture
	return texture


static func car_motion_texture_for_key(visual_key: String, travel: float, steer: float) -> Texture2D:
	var spin := 0
	if travel > 0.0:
		spin = posmod(int(floor(travel / RACE_WHEEL_ROLL_DISTANCE)), CAR_SPRITES.WHEEL_FRAME_COUNT)
	return _texture_for_spin_pose(visual_key, spin, CAR_SPRITES.steer_pose_index(steer))


static func motion_preparation_plan_for_key(visual_key: String) -> Dictionary:
	if not _car_spin_cache.has(visual_key):
		_car_spin_cache[visual_key] = {}
	var per_spin: Dictionary = _car_spin_cache[visual_key]
	var jobs: Array[Vector2i] = []
	for spin in CAR_SPRITES.WHEEL_FRAME_COUNT:
		if not per_spin.has(spin):
			var frames: Array = []
			frames.resize(5)
			per_spin[spin] = frames
		for pose in 5:
			if spin == 0 and pose == REST_STEER_POSE and _car_texture_cache.has(visual_key):
				per_spin[spin][pose] = _car_texture_cache[visual_key]
			if per_spin[spin][pose] == null:
				jobs.append(Vector2i(spin, pose))
	return {"payload": car_payload_for_key(visual_key), "jobs": jobs}


static func _is_visual_key(key: String) -> bool:
	return key.find("|") != -1 or _visual_resolutions.has(key)


static func _get_car_texture(key: String) -> Texture2D:
	if _is_visual_key(key):
		return car_texture_for_key(key)
	return car_texture(key)


static func _merge_cosmetic(base_options: Dictionary, cosmetic: Dictionary) -> Dictionary:
	if cosmetic.is_empty():
		return base_options.duplicate(true)
	var opts := base_options.duplicate(true)
	if cosmetic.has("palette"):
		opts["palette"] = cosmetic["palette"]
	var parts: Dictionary = (opts.get("parts", {}) as Dictionary).duplicate(true)
	for slot in ["livery", "wheels", "spoiler"]:
		if cosmetic.has(slot):
			parts[slot] = cosmetic[slot]
	opts["parts"] = parts
	# chassis invariants untouched: type/hood/cabin/bumpers
	return opts


static func _effective_livery_for(vehicle_id: String, driver_id: String) -> Dictionary:
	var drv_liv: Dictionary = CATALOG.get_driver(driver_id).get("car_livery", {})
	if not drv_liv.is_empty():
		return drv_liv.duplicate()
	var veh := CATALOG.get_vehicle(vehicle_id)
	var art: Dictionary = veh.get("car_art", {})
	var opts: Dictionary = art.get("options", {})
	var parts: Dictionary = opts.get("parts", {})
	return {
		"palette": String(opts.get("palette", "")),
		"livery": String(parts.get("livery", "")),
		"wheels": String(parts.get("wheels", "")),
		"spoiler": String(parts.get("spoiler", "")),
	}


static func _shift_cosmetic(livery: Dictionary, shift: int) -> Dictionary:
	if shift <= 0:
		return livery.duplicate()
	var res := livery.duplicate()
	var pals: Array = CAR_GENERATOR.available_palette_ids()
	if res.has("palette") and pals.size() > 0:
		var cur := String(res["palette"])
		var idx := pals.find(cur)
		res["palette"] = pals[(idx if idx >= 0 else 0 + shift) % pals.size()]
	var part_map: Dictionary = CAR_GENERATOR.available_parts()
	for f in ["livery", "wheels", "spoiler"]:
		if res.has(f):
			var allowed: Array = part_map.get(f, []) as Array
			if allowed.size() > 0:
				var cur := String(res[f])
				var idx := allowed.find(cur)
				res[f] = allowed[(idx if idx >= 0 else 0 + shift) % allowed.size()]
	return res


static func _livery_signature(livery: Dictionary) -> String:
	if livery.is_empty():
		return ""
	var p := String(livery.get("palette", ""))
	var ly := String(livery.get("livery", ""))
	var w := String(livery.get("wheels", ""))
	var s := String(livery.get("spoiler", ""))
	return "p%s_l%s_w%s_s%s" % [p, ly, w, s]
