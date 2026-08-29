class_name TrackVariantPresenter
extends Node2D

const SURFACE_ZONE_SCRIPT := preload("res://scripts/race/surface_zone.gd")
const HAZARD_SCRIPT := preload("res://scripts/race/environmental_hazard.gd")
const ASPHALT_TEXTURE := preload("res://assets/textures/imagine/track_asphalt_tile.png")
const WOOD_TEXTURE := preload("res://assets/textures/imagine/counter_wood_tile.png")
const PAINT_CAN_TEXTURE := preload("res://assets/textures/imagine/workshop_paint_can.png")
const KEYCAP_TEXTURE := preload("res://assets/textures/imagine/office_keycap.png")

const INK := Color("172033")
const PAPER := Color("f2ead7")
const CREAM := Color("fff8e8")
const AMBER := Color("f4bf3a")
const STEEL := Color("8fa0aa")
const OFFICE_BLUE := Color("4c7195")

const TRACK_POLYGONS: Array[String] = ["BottomStraight", "RightTechnical", "TopSpeedSection", "LeftTechnical"]
const OBSTACLE_NAMES: Array[String] = ["MugA", "MugB", "CerealA", "CerealB", "Sponge", "Fork", "Ruler", "Apple", "Lime", "Cup", "Spoon"]

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
			_prepare_runtime_variant()
			_build_workshop_presentation()
			_configure_obstacles(_workshop_obstacles())
			_configure_labels("WORKSHOP NIGHT SHIFT", "PAINT-CAN CHICANE", "OIL / SAWDUST", "TOOL RUN", "←  METAL STRAIGHT")
		&"office":
			base_surface_name = &"desk mat"
			_prepare_runtime_variant()
			_build_office_presentation()
			_configure_obstacles(_office_obstacles())
			_configure_labels("OFFICE LAST LIGHT", "KEYCAP CHICANE", "PAPER CUT", "CABLE TURN", "←  DESK-MAT STRAIGHT")
		_:
			base_surface_name = &"polished counter"
	_apply_surface_textures()
	_create_surface_zones()
	_create_hazard()


func _apply_surface_textures() -> void:
	for path: String in TRACK_POLYGONS:
		_texture_polygon(path, ASPHALT_TEXTURE)
	_texture_polygon("Floor", WOOD_TEXTURE)
	_texture_polygon("CounterHighlight", WOOD_TEXTURE)
	_texture_polygon("InnerIsland", WOOD_TEXTURE)
	for sprite_path: String in ["ArtSurfaces/BottomTrack", "ArtSurfaces/RightTrack", "ArtSurfaces/TopTrack", "ArtSurfaces/LeftTrack"]:
		var sprite := _track.get_node_or_null(sprite_path) as Sprite2D
		if sprite:
			sprite.texture = ASPHALT_TEXTURE
	var counter := _track.get_node_or_null("ArtSurfaces/CounterSurface") as Sprite2D
	if counter:
		counter.texture = WOOD_TEXTURE


func _texture_polygon(path: String, texture: Texture2D) -> void:
	var polygon := _track.get_node_or_null(path) as Polygon2D
	if polygon == null or texture == null:
		return
	polygon.texture = texture


func _prepare_runtime_variant() -> void:
	for container_name: String in ["ArtSurfaces", "Dressing", "MicroDressing"]:
		var container := _track.get_node_or_null(container_name) as CanvasItem
		if container:
			container.visible = false

	_show_polygon("Floor", Color("31261f") if theme == &"workshop" else Color("26384f"))
	_show_polygon("CounterHighlight", Color("49372b") if theme == &"workshop" else Color("365473"))
	for path: String in TRACK_POLYGONS:
		_show_polygon(path, INK.lightened(0.04))
	_show_polygon("InnerIsland", Color("5a4636") if theme == &"workshop" else Color("29435f"))
	_show_polygon("StartFinishWhite", AMBER)
	_show_polygon("StartFinishBlack", INK)
	for wall_name: String in ["TopWall", "BottomWall", "LeftWall", "RightWall"]:
		var wall_visual := _track.get_node_or_null("%s/Visual" % wall_name) as Polygon2D
		if wall_visual:
			wall_visual.color = Color("0e1524")


func _build_workshop_presentation() -> void:
	var art := Node2D.new()
	art.name = "WorkshopRuntimeArt"
	art.z_index = -17
	add_child(art)
	for x in range(-900, 901, 150):
		_add_line(art, PackedVector2Array([Vector2(x, -540), Vector2(x, 540)]), Color(AMBER, 0.12), 2.0)
	for y in range(-510, 511, 120):
		_add_line(art, PackedVector2Array([Vector2(-940, y), Vector2(940, y)]), Color(PAPER, 0.1), 2.0)
	_add_polygon(art, "SteelInset", PackedVector2Array([
		Vector2(-520.0, -185.0), Vector2(520.0, -185.0),
		Vector2(520.0, 185.0), Vector2(-520.0, 185.0),
	]), Color(STEEL, 0.22), 1)
	_add_line(art, PackedVector2Array([Vector2(-540, -205), Vector2(540, -205)]), Color(AMBER, 0.72), 8.0)
	_add_line(art, PackedVector2Array([Vector2(-540, 205), Vector2(540, 205)]), Color(AMBER, 0.45), 5.0)
	for fastener_position: Vector2 in [Vector2(-430, -90), Vector2(-260, 70), Vector2(360, -70), Vector2(470, 95)]:
		_add_polygon(art, "Fastener", _regular_polygon(fastener_position, 18.0, 6), Color("c9d0d2"), 2)
	

func _build_office_presentation() -> void:
	var art := Node2D.new()
	art.name = "OfficeRuntimeArt"
	art.z_index = -17
	add_child(art)
	_add_polygon(art, "DeskMat", PackedVector2Array([
		Vector2(-610.0, -230.0), Vector2(610.0, -230.0),
		Vector2(610.0, 230.0), Vector2(-610.0, 230.0),
	]), Color("1e3048"), 0)
	for row in 3:
		for column in 9:
			var key_position := Vector2(-430.0 + column * 102.0, -130.0 + row * 94.0)
			var key_color := Color("7594b0") if (row + column) % 3 else Color("e7dfc9")
			_add_polygon(art, "Key", _rect_points(key_position, Vector2(72.0, 58.0)), Color(key_color, 0.5), 1)
	_add_polygon(art, "StickyAmber", _rect_points(Vector2(-420.0, 80.0), Vector2(150.0, 130.0)), Color(AMBER, 0.86), 3)
	_add_polygon(art, "StickyCream", _rect_points(Vector2(420.0, -80.0), Vector2(145.0, 125.0)), Color(PAPER, 0.84), 3)
	_add_line(art, PackedVector2Array([Vector2(-535, -185), Vector2(-440, -95), Vector2(-330, -165)]), Color("6f91b8"), 11.0)
	_add_line(art, PackedVector2Array([Vector2(300, 175), Vector2(540, 85)]), Color("d7e1eb"), 18.0)
	

func _configure_obstacles(definitions: Dictionary) -> void:
	for obstacle_name: String in OBSTACLE_NAMES:
		var obstacle := _track.get_node_or_null(obstacle_name) as StaticBody2D
		if obstacle == null or not definitions.has(obstacle_name):
			continue
		var data: Dictionary = definitions[obstacle_name]
		obstacle.position = data["position"]
		obstacle.rotation = float(data.get("rotation", 0.0))
		var visual := obstacle.get_node_or_null("Visual") as Polygon2D
		if visual:
			visual.visible = false
		var stripe := obstacle.get_node_or_null("Stripe") as Polygon2D
		if stripe:
			stripe.visible = false
		for child_name: String in ["Coffee", "Handle", "Scrub"]:
			var child := obstacle.get_node_or_null(child_name) as CanvasItem
			if child:
				child.visible = false
		var sprite := obstacle.get_node_or_null("Sprite") as Sprite2D
		if sprite:
			sprite.visible = true
			if theme == &"workshop" and obstacle_name.begins_with("Mug"):
				sprite.texture = PAINT_CAN_TEXTURE
			elif theme == &"office" and obstacle_name.begins_with("Cereal"):
				sprite.texture = KEYCAP_TEXTURE


func _create_surface_zones() -> void:
	var definitions: Array[Dictionary]
	match theme:
		&"workshop":
			definitions = [
				{"name": &"oil slick", "label": "", "grip": 0.45, "speed": 0.92, "color": Color(0.06, 0.08, 0.12, 0.58), "points": PackedVector2Array([Vector2(610, -170), Vector2(860, -170), Vector2(860, 120), Vector2(610, 120)])},
				{"name": &"sawdust", "label": "", "grip": 0.78, "speed": 0.72, "color": Color(0.76, 0.53, 0.24, 0.52), "points": PackedVector2Array([Vector2(-120, 245), Vector2(330, 245), Vector2(330, 490), Vector2(-120, 490)])},
			]
		&"office":
			definitions = [
				{"name": &"loose paper", "label": "", "grip": 0.84, "speed": 0.78, "color": Color(PAPER, 0.56), "points": PackedVector2Array([Vector2(-520, -490), Vector2(-100, -490), Vector2(-100, -245), Vector2(-520, -245)])},
				{"name": &"keyboard", "label": "", "grip": 0.7, "speed": 0.64, "color": Color(0.35, 0.5, 0.67, 0.56), "points": PackedVector2Array([Vector2(610, 120), Vector2(860, 120), Vector2(860, 430), Vector2(610, 430)])},
			]
		_:
			definitions = [
				{"name": &"wet spill", "label": "", "grip": 0.58, "speed": 0.88, "color": Color.TRANSPARENT, "points": PackedVector2Array([Vector2(-70, -485), Vector2(350, -485), Vector2(350, -255), Vector2(-70, -255)])},
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
			travel_start = Vector2(330.0, 535.0)
			travel_end = Vector2(330.0, 185.0)
		&"office":
			travel_start = Vector2(555.0, -40.0)
			travel_end = Vector2(910.0, -40.0)
		_:
			travel_start = Vector2(430.0, -185.0)
			travel_end = Vector2(430.0, -545.0)
	hazard = HAZARD_SCRIPT.new() as EnvironmentalHazard
	hazard.name = "%sHazard" % String(theme).to_pascal_case()
	add_child(hazard)
	hazard.configure(theme, travel_start, travel_end)


func _configure_labels(_title: String, _chicane: String, _shortcut: String, _technical: String, _speed: String) -> void:
	var labels := _track.get_node_or_null("Labels") as CanvasItem
	if labels:
		labels.visible = false


func _show_polygon(path: String, color: Color) -> void:
	var polygon := _track.get_node_or_null(path) as Polygon2D
	if polygon:
		polygon.visible = true
		polygon.color = color


func _add_obstacle_label(obstacle: StaticBody2D, text: String) -> void:
	var label := Label.new()
	label.name = "RuntimeLabel"
	label.position = Vector2(-80.0, -24.0)
	label.size = Vector2(160.0, 48.0)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", CREAM)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 4)
	obstacle.add_child(label)


func _add_world_sign(parent: Node2D, sign_position: Vector2, text: String, paper_color: Color, text_color: Color) -> void:
	_add_polygon(parent, "PaperSign", _rect_points(sign_position, Vector2(250.0, 105.0)), paper_color, 4)
	var label := Label.new()
	label.position = sign_position - Vector2(125.0, 48.0)
	label.size = Vector2(250.0, 96.0)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", text_color)
	parent.add_child(label)


func _add_polygon(parent: Node2D, node_name: String, points: PackedVector2Array, color: Color, z: int) -> Polygon2D:
	var polygon := Polygon2D.new()
	polygon.name = node_name
	polygon.z_index = z
	polygon.polygon = points
	polygon.color = color
	parent.add_child(polygon)
	return polygon


func _add_line(parent: Node2D, points: PackedVector2Array, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.default_color = color
	line.width = width
	line.antialiased = true
	parent.add_child(line)
	return line


func _regular_polygon(center: Vector2, radius: float, sides: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in sides:
		points.append(center + Vector2.RIGHT.rotated(TAU * float(index) / float(sides)) * radius)
	return points


func _rect_points(center: Vector2, size: Vector2) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([
		center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y), center + Vector2(-half.x, half.y),
	])


func _workshop_obstacles() -> Dictionary:
	return {
		"MugA": {"label": "PAINT CAN", "position": Vector2(60, 275), "color": Color("d8d2bd")},
		"MugB": {"label": "PAINT CAN", "position": Vector2(265, 130), "color": Color("54778f")},
		"CerealA": {"label": "TOOLBOX", "position": Vector2(500, 85), "rotation": -0.08, "color": Color("c9563f"), "accent": AMBER},
		"CerealB": {"label": "PARTS BIN", "position": Vector2(825, -125), "rotation": 0.08, "color": Color("456b5b"), "accent": PAPER},
		"Sponge": {"label": "SANDING BLOCK", "position": Vector2(120, -150), "color": Color("c78a3a")},
		"Fork": {"label": "WRENCH", "position": Vector2(-315, -515), "rotation": 0.08, "color": STEEL},
		"Ruler": {"label": "STEEL RULER", "position": Vector2(-360, 185), "rotation": -0.04, "color": STEEL},
		"Apple": {"label": "HEX NUT", "position": Vector2(-515, -75), "color": Color("b8c1c5")},
		"Lime": {"label": "WASHER", "position": Vector2(-845, -310), "color": Color("87989f")},
		"Cup": {"label": "FASTENERS", "position": Vector2(-510, 510), "color": Color("78566b")},
		"Spoon": {"label": "LONG WRENCH", "position": Vector2(-905, 10), "rotation": 1.48, "color": STEEL},
	}


func _office_obstacles() -> Dictionary:
	return {
		"MugA": {"label": "CABLE REEL", "position": Vector2(-120, 125), "color": Color("7696b0")},
		"MugB": {"label": "PEN CUP", "position": Vector2(250, 150), "color": Color("d9d2be")},
		"CerealA": {"label": "KEYBOARD", "position": Vector2(820, 300), "rotation": -0.08, "color": Color("536e8b"), "accent": CREAM},
		"CerealB": {"label": "KEYCAPS", "position": Vector2(820, -210), "rotation": 0.06, "color": Color("6e88a1"), "accent": AMBER},
		"Sponge": {"label": "STICKY NOTES", "position": Vector2(55, -155), "color": AMBER},
		"Fork": {"label": "FOUNTAIN PEN", "position": Vector2(-300, -515), "rotation": 0.05, "color": Color("d9e1e7")},
		"Ruler": {"label": "DESK RULER", "position": Vector2(420, 520), "rotation": -0.03, "color": Color("7ba3bf")},
		"Apple": {"label": "BINDER CLIP", "position": Vector2(-500, 35), "color": Color("44566a")},
		"Lime": {"label": "TAPE ROLL", "position": Vector2(-390, 120), "color": Color("a8bbc8")},
		"Cup": {"label": "PAPER CLIPS", "position": Vector2(-510, 510), "color": Color("6b5b84")},
		"Spoon": {"label": "CHARGING CABLE", "position": Vector2(-905, -35), "rotation": 1.48, "color": INK.lightened(0.18)},
	}
