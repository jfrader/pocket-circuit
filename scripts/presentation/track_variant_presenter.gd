class_name TrackVariantPresenter
extends Node2D

const SURFACE_ZONE_SCRIPT := preload("res://scripts/race/surface_zone.gd")
const HAZARD_SCRIPT := preload("res://scripts/race/environmental_hazard.gd")

const INK := Color("172033")
const PAPER := Color("f2ead7")
const CREAM := Color("fff8e8")
const AMBER := Color("f4bf3a")

var theme: StringName = &"kitchen"
var base_surface_name: StringName = &"polished counter"
var surface_zones: Array[SurfaceZone] = []
var hazard: EnvironmentalHazard

var _track: Node2D


func configure(track_root: Node2D, requested_theme: StringName) -> void:
	_track = track_root
	theme = requested_theme if requested_theme in [&"kitchen", &"workshop", &"office"] else &"kitchen"
	name = "TrackVariantPresenter"
	match theme:
		&"workshop":
			base_surface_name = &"workbench"
		&"office":
			base_surface_name = &"desk mat"
		_:
			base_surface_name = &"polished counter"
			_build_kitchen_presentation()
	_create_surface_zones()
	_create_hazard()


func _build_kitchen_presentation() -> void:
	var art := Node2D.new()
	art.name = "KitchenRuntimeArt"
	art.z_index = -17
	add_child(art)
	for y in range(-540, 541, 48):
		_add_line(art, PackedVector2Array([Vector2(-940, y), Vector2(940, y)]), Color(0.92, 0.78, 0.55, 0.08), 2.0)
	_add_line(art, PackedVector2Array([Vector2(-540, -205), Vector2(540, -205)]), Color(AMBER, 0.55), 6.0)
	_add_line(art, PackedVector2Array([Vector2(-540, 205), Vector2(540, 205)]), Color(AMBER, 0.35), 4.0)
	var plate_texture := load("res://assets/textures/kitchen/plate_large.png") as Texture2D
	if plate_texture:
		var plate := Sprite2D.new()
		plate.name = "IslandPlate"
		plate.texture = plate_texture
		plate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		plate.position = Vector2(90.0, 10.0)
		plate.scale = Vector2(1.9, 1.9)
		plate.z_index = -8
		add_child(plate)
	var board_texture := load("res://assets/textures/kitchen/cutting_board.png") as Texture2D
	if board_texture:
		var board := Sprite2D.new()
		board.name = "IslandBoard"
		board.texture = board_texture
		board.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		board.position = Vector2(-320.0, 30.0)
		board.rotation = -0.06
		board.scale = Vector2(1.15, 1.15)
		board.z_index = -8
		add_child(board)


func _create_surface_zones() -> void:
	var definitions: Array[Dictionary]
	match theme:
		&"workshop":
			definitions = [
				{"name": &"oil slick", "label": "", "grip": 0.45, "speed": 0.92, "color": Color(0.06, 0.08, 0.12, 0.58), "points": PackedVector2Array([Vector2(610, -170), Vector2(860, -170), Vector2(860, 120), Vector2(610, 120)])},
				{"name": &"sawdust", "label": "", "grip": 0.78, "speed": 0.72, "color": Color(0.76, 0.53, 0.24, 0.52), "points": PackedVector2Array([Vector2(-600, 245), Vector2(-300, 245), Vector2(-300, 490), Vector2(-600, 490)])},
				{"name": &"spark strip", "label": "", "grip": 1.0, "speed": 1.2, "color": Color(AMBER, 0.16), "points": PackedVector2Array([Vector2(300, 245), Vector2(600, 245), Vector2(600, 490), Vector2(300, 490)])},
			]
		&"office":
			definitions = [
				{"name": &"loose paper", "label": "", "grip": 0.84, "speed": 0.78, "color": Color(PAPER, 0.4), "points": PackedVector2Array([Vector2(-520, 245), Vector2(-100, 245), Vector2(-100, 490), Vector2(-520, 490)])},
				{"name": &"keyboard", "label": "", "grip": 0.7, "speed": 0.64, "color": Color(0.35, 0.5, 0.67, 0.56), "points": PackedVector2Array([Vector2(610, 120), Vector2(860, 120), Vector2(860, 430), Vector2(610, 430)])},
				{"name": &"mail shoot", "label": "", "grip": 1.0, "speed": 1.18, "color": Color(AMBER, 0.16), "points": PackedVector2Array([Vector2(300, 245), Vector2(600, 245), Vector2(600, 490), Vector2(300, 490)])},
			]
		_:
			definitions = [
				{"name": &"wet spill", "label": "", "grip": 0.58, "speed": 0.88, "color": Color.TRANSPARENT, "points": PackedVector2Array([Vector2(-70, -485), Vector2(350, -485), Vector2(350, -255), Vector2(-70, -255)])},
				{"name": &"polish strip", "label": "", "grip": 1.0, "speed": 1.18, "color": Color(AMBER, 0.16), "points": PackedVector2Array([Vector2(-560, 245), Vector2(-260, 245), Vector2(-260, 490), Vector2(-560, 490)])},
			]
	for data: Dictionary in definitions:
		var zone := SURFACE_ZONE_SCRIPT.new() as SurfaceZone
		zone.name = "%sSurface" % String(data["name"]).to_pascal_case()
		add_child(zone)
		zone.configure(data["name"], data["points"], float(data["grip"]), float(data["speed"]), data["color"], String(data["label"]))
		surface_zones.append(zone)


func _create_hazard() -> void:
	var travel_start: Vector2
	var travel_end: Vector2
	match theme:
		&"workshop":
			travel_start = Vector2(610.0, -40.0)
			travel_end = Vector2(850.0, -40.0)
		&"office":
			travel_start = Vector2(610.0, -40.0)
			travel_end = Vector2(850.0, -40.0)
		_:
			travel_start = Vector2(430.0, -185.0)
			travel_end = Vector2(430.0, -545.0)
	hazard = HAZARD_SCRIPT.new() as EnvironmentalHazard
	hazard.name = "%sHazard" % String(theme).to_pascal_case()
	add_child(hazard)
	hazard.configure(theme, travel_start, travel_end)


func _add_line(parent: Node2D, points: PackedVector2Array, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.default_color = color
	line.width = width
	line.antialiased = true
	parent.add_child(line)
	return line
