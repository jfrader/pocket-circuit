extends Node2D

const GENERATOR := preload("res://scripts/vendor/procedural_2d/procedural_car_generator.gd")
const SPRITES := preload("res://scripts/vendor/procedural_2d/procedural_car_sprites.gd")
const PALETTES := ["citrus_pop", "marina_blue", "desert_sage", "plum_soda", "candy_red"]
const TYPES := ["compact", "coupe", "muscle"]
const PIXEL_SCALE := 2
const SPRITE_SCALE := 0.5
const TRUCK_STRETCH := Vector2(1.12, 1.35)
const HEADLIGHT_SIZE := Vector2(5.0, 3.0)
const ROOF_MARKER_SIZE := Vector2(4.0, 2.0)
const ROOF_MARKER_COLOR := Color("f4c65a")
const STEER_POSE_COUNT := 5
const MOTION_POSE_COUNT := SPRITES.WHEEL_FRAME_COUNT * STEER_POSE_COUNT

static var motion_image_generations := 0
static var motion_image_generation_usec := 0

var body_size := Vector2.ZERO
var _payload: Dictionary
var _sprite: Sprite2D
var _travel := 0.0
var _frames := {}
var _warmup_texture: Texture2D


func configure(vehicle_id: String, seed_value: int, truck: bool, oncoming: bool = false) -> void:
	var seed := (vehicle_id + ":" + str(seed_value)).hash() & 0x7fffffff
	var type: String = "muscle" if truck else TYPES[seed % TYPES.size()]
	_payload = GENERATOR.generate(seed, type, {"palette_id": PALETTES[seed % PALETTES.size()], "livery": "solid", "spoiler": "none", "bumpers": "utility"})
	var bounds: Dictionary = _payload["collision_bounds"]
	var stretch := TRUCK_STRETCH if truck else Vector2.ONE
	body_size = Vector2(bounds["width"], bounds["height"]) * stretch
	_sprite = Sprite2D.new()
	_sprite.name = "CivilianBody"
	_sprite.scale = Vector2.ONE * SPRITE_SCALE * stretch
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	animate(0.0, 0.0, 0.0)
	if truck:
		_build_cargo_box(stretch)
	if oncoming:
		for side in [-1.0, 1.0]:
			var position := Vector2(body_size.x * side * 0.30, -body_size.y * 0.46)
			_add_panel("OncomingLampLeft" if side < 0 else "OncomingLampRight", Rect2(position - HEADLIGHT_SIZE * 0.5, HEADLIGHT_SIZE), Color(_payload["palette"]["headlight"]))
			if truck:
				var roof := Vector2(body_size.x * side * 0.30, -body_size.y * 0.17)
				_add_panel("RoofMarkerLeft" if side < 0 else "RoofMarkerRight", Rect2(roof - ROOF_MARKER_SIZE * 0.5, ROOF_MARKER_SIZE), ROOF_MARKER_COLOR)


func animate(speed: float, steering: float, delta: float) -> void:
	_travel += speed * delta
	var spin := SPRITES.wheel_frame_index(1.0, _travel)
	var steer := SPRITES.steer_pose_index(steering)
	var key := spin * STEER_POSE_COUNT + steer
	if not _frames.has(key):
		var started := Time.get_ticks_usec()
		_frames[key] = ImageTexture.create_from_image(SPRITES.car_pose_image(_payload, spin, steer, PIXEL_SCALE))
		motion_image_generations += 1
		motion_image_generation_usec += Time.get_ticks_usec() - started
	_sprite.texture = _frames[key]


func motion_preparation_plan() -> Dictionary:
	var poses: Array[int] = []
	for pose in MOTION_POSE_COUNT:
		if not _frames.has(pose):
			poses.append(pose)
	return {"payload": _payload.duplicate(true), "poses": poses}


static func render_motion_plan(plan: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var images: Array[Image] = []
	for pose: int in plan["poses"]:
		images.append(SPRITES.car_pose_image(plan["payload"], pose / STEER_POSE_COUNT, pose % STEER_POSE_COUNT, PIXEL_SCALE))
	return {"poses": plan["poses"], "images": images, "usec": Time.get_ticks_usec() - started}


func install_motion_images(rendered: Dictionary) -> bool:
	if rendered.is_empty() or rendered["poses"].size() != rendered["images"].size():
		return false
	for index in rendered["poses"].size():
		if rendered["images"][index] == null:
			return false
		_frames[rendered["poses"][index]] = ImageTexture.create_from_image(rendered["images"][index])
	motion_image_generations += rendered["poses"].size()
	motion_image_generation_usec += int(rendered["usec"])
	return _frames.size() == MOTION_POSE_COUNT


func show_warmup_pose(pose: int) -> void:
	# Loading-only presentation: leave rolling distance and steering untouched.
	if _warmup_texture == null:
		_warmup_texture = _sprite.texture
	_sprite.texture = _frames[pose]


func restore_warmup_pose() -> void:
	if _warmup_texture != null:
		_sprite.texture = _warmup_texture
		_warmup_texture = null


func _build_cargo_box(stretch: Vector2) -> void:
	# The generated chassis retains its wheels, cab, lamps and contact shadow.
	# A raised ribbed load box makes this a delivery toy, not a scaled-up coupe.
	var palette: Dictionary = _payload["palette"]
	var box := Rect2(Vector2(-14.0, -5.0) * stretch, Vector2(28.0, 28.0) * stretch)
	_add_panel("BoxShadow", Rect2(box.position + Vector2(2.0, 2.0), box.size), Color(palette["body_dark"]))
	_add_panel("CargoBox", box, Color(palette["body_light"]))
	for rib in range(1, 5):
		_add_panel("CargoRib%d" % rib, Rect2(box.position + Vector2(2.0, box.size.y * rib / 5.0), Vector2(box.size.x - 4.0, 1.0)), Color(palette["body_mid"]))


func _add_panel(node_name: String, rect: Rect2, color: Color) -> void:
	var panel := Polygon2D.new()
	panel.name = node_name
	panel.polygon = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	panel.color = color
	add_child(panel)
