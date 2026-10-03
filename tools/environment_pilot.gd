extends Node2D
## Isolated native art review; the shipping track generator never loads this fixture.

const MANIFEST_PATH := "res://tools/environment_pilot.json"
const TEXTURES := "res://assets/textures/environment_pilot/"
const VEHICLE := preload("res://scenes/vehicles/rustbug.tscn")
const PROPS := preload("res://tools/environment_pilot_props.gd")
const THEMES := ["kitchen", "workshop", "office"]
const FLOOR_EXTENT := 2000.0
const FLOOR_PERIOD := 700.0
const REVIEW_CENTER := Vector2(0, 35)

var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
var theme := "kitchen"
var ready_for_review := false
var world: Node2D
var camera: Camera2D
var vehicle: VehicleController
var route_points := PackedVector2Array()
var placement_metrics: Array[Dictionary] = []
var follow_vehicle := false
var runtime_fps := 0.0


func _ready() -> void:
	await show_theme(theme)


func _process(_delta: float) -> void:
	runtime_fps = Engine.get_frames_per_second()
	if ready_for_review and follow_vehicle:
		camera.position = vehicle.position


func show_theme(next_theme: String) -> void:
	if next_theme not in THEMES:
		push_error("Unknown pilot theme: " + next_theme)
		return
	ready_for_review = false
	follow_vehicle = false
	if is_instance_valid(world):
		world.free()
	placement_metrics.clear()
	theme = next_theme
	var definition: Dictionary = manifest["themes"][theme]
	world = Node2D.new()
	world.name = "Composition"
	add_child(world)
	_add_floor()
	_add_route(definition)
	for placement: Dictionary in definition["placements"]:
		_add_prop(definition["assets"][placement["role"]], placement)
		await get_tree().process_frame
	vehicle = VEHICLE.instantiate() as VehicleController
	vehicle.name = "PilotCar"
	vehicle.position = _vector(definition["car"])
	vehicle.rotation = PI * 0.5
	world.add_child(vehicle)
	vehicle.configure_visual_identity("rustbug")
	camera = Camera2D.new()
	camera.name = "PilotCamera"
	camera.zoom = Vector2.ONE * float(manifest["zoom"])
	camera.position = REVIEW_CENTER
	world.add_child(camera)
	camera.make_current()
	camera.force_update_scroll()
	ready_for_review = true
	print("ENVIRONMENT_PILOT_READY theme=%s props=%d zoom=%.2f" % [theme, placement_metrics.size(), camera.zoom.x])


func _unhandled_key_input(event: InputEvent) -> void:
	if not ready_for_review or not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	if key >= KEY_1 and key <= KEY_3:
		await show_theme(THEMES[key - KEY_1])
	elif key == KEY_R:
		await show_theme(theme)
	elif key == KEY_F:
		follow_vehicle = not follow_vehicle
		camera.position = vehicle.position if follow_vehicle else REVIEW_CENTER
		camera.force_update_scroll()


func _add_floor() -> void:
	var floor := Polygon2D.new()
	floor.name = "FloorMaterial"
	floor.polygon = PackedVector2Array([
		Vector2(-FLOOR_EXTENT, -FLOOR_EXTENT), Vector2(FLOOR_EXTENT, -FLOOR_EXTENT),
		Vector2(FLOOR_EXTENT, FLOOR_EXTENT), Vector2(-FLOOR_EXTENT, FLOOR_EXTENT)])
	floor.texture = load(TEXTURES + theme + "_floor.png") as Texture2D
	floor.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	floor.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	floor.uv = _material_uv(floor.polygon, floor.texture)
	floor.z_index = -20
	world.add_child(floor)


func _add_route(definition: Dictionary) -> void:
	var curve := Curve2D.new()
	var controls: Array = definition["route"]
	for index in controls.size():
		var point := _vector(controls[index])
		var previous := _vector(controls[maxi(index - 1, 0)])
		var next := _vector(controls[mini(index + 1, controls.size() - 1)])
		var tangent := (next - previous) * 0.16
		curve.add_point(point, -tangent, tangent)
	route_points = curve.get_baked_points()
	var route := Polygon2D.new()
	route.name = "RacingSurface"
	var outline := Geometry2D.offset_polyline(route_points, float(manifest["route_width_mm"]) * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_BUTT)
	route.polygon = outline[0]
	route.color = Color(definition["route_tint"])
	route.texture = load(TEXTURES + theme + "_floor.png") as Texture2D
	route.uv = _material_uv(route.polygon, route.texture)
	route.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	route.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	route.antialiased = true
	route.z_index = -19
	world.add_child(route)


func _material_uv(points: PackedVector2Array, texture: Texture2D) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	for point: Vector2 in points:
		uvs.append(point / FLOOR_PERIOD * texture.get_size())
	return uvs


func _add_prop(asset: Dictionary, placement: Dictionary) -> void:
	placement_metrics.append(PROPS.add(world, manifest, theme, asset, placement))


func _vector(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
