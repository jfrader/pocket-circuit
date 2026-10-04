extends Node2D

const GENERATOR := preload("res://scripts/vendor/procedural_2d/procedural_car_generator.gd")
const SPRITES := preload("res://scripts/vendor/procedural_2d/procedural_car_sprites.gd")
const PALETTES := ["citrus_pop", "marina_blue", "desert_sage", "plum_soda", "candy_red"]
const TYPES := ["compact", "coupe", "muscle"]
const PIXEL_SCALE := 2
const SPRITE_SCALE := 0.5
const TRUCK_STRETCH := Vector2(1.12, 1.35)

var body_size := Vector2.ZERO
var _payload: Dictionary
var _sprite: Sprite2D
var _travel := 0.0
var _frames := {}


func configure(vehicle_id: String, seed_value: int, truck: bool) -> void:
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


func animate(speed: float, steering: float, delta: float) -> void:
	_travel += speed * delta
	var spin := SPRITES.wheel_frame_index(1.0, _travel)
	var steer := SPRITES.steer_pose_index(steering)
	var key := spin * 5 + steer
	if not _frames.has(key):
		_frames[key] = ImageTexture.create_from_image(SPRITES.car_pose_image(_payload, spin, steer, PIXEL_SCALE))
	_sprite.texture = _frames[key]


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
