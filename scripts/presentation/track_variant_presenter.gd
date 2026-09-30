class_name TrackVariantPresenter
extends Node2D

const SURFACE_ZONE_SCRIPT := preload("res://scripts/race/surface_zone.gd")

const INK := Color("172033")
const PAPER := Color("f2ead7")
const CREAM := Color("fff8e8")
const AMBER := Color("f4bf3a")

var theme: StringName = &"kitchen"
var base_surface_name: StringName = &"polished counter"
var surface_zones: Array[SurfaceZone] = []

var _track: Node2D


func configure(track_root: Node2D, requested_theme: StringName) -> void:
	_track = track_root
	theme = requested_theme if requested_theme in [&"kitchen", &"workshop", &"office"] else &"kitchen"
	name = "TrackVariantPresenter"
	match theme:
		&"workshop":
			base_surface_name = &"workbench"
		&"office":
			base_surface_name = &"desktop"
		_:
			base_surface_name = &"polished counter"
			_build_kitchen_presentation()
	_create_surface_zones()


func _build_kitchen_presentation() -> void:
	# The builder's kitchen circuit already carries its own island, fill props,
	# and surface — no extra presentation art.
	pass


func _create_surface_zones() -> void:
	var definitions: Array[Dictionary]
	var generated: Variant = _track.get_meta("generated_surfaces") if is_instance_valid(_track) and _track.has_meta("generated_surfaces") else null
	if generated is Array and not (generated as Array).is_empty():
		for generated_definition: Dictionary in generated:
			var definition := generated_definition.duplicate(true)
			definition["label"] = ""
			definition["color"] = Color.TRANSPARENT
			definitions.append(definition)
	else:
		# Canonical static tracks keep their authored world-space zones.
		match theme:
			&"workshop":
				definitions = [
					{"name": &"oil slick", "label": "", "grip": 0.45, "speed": 0.92, "color": Color.TRANSPARENT, "points": PackedVector2Array([Vector2(610, -170), Vector2(860, -170), Vector2(860, 120), Vector2(610, 120)])},
					{"name": &"sawdust", "label": "", "grip": 0.78, "speed": 0.72, "color": Color.TRANSPARENT, "points": PackedVector2Array([Vector2(-600, 245), Vector2(-300, 245), Vector2(-300, 490), Vector2(-600, 490)])},
					{"name": &"spark strip", "label": "", "grip": 1.0, "speed": 1.2, "color": Color.TRANSPARENT, "points": PackedVector2Array([Vector2(300, 245), Vector2(600, 245), Vector2(600, 490), Vector2(300, 490)])},
				]
			&"office":
				definitions = [
					{"name": &"loose paper", "label": "", "grip": 0.84, "speed": 0.78, "color": Color.TRANSPARENT, "points": PackedVector2Array([Vector2(-520, 245), Vector2(-100, 245), Vector2(-100, 490), Vector2(-520, 490)])},
					{"name": &"keyboard", "label": "", "grip": 0.7, "speed": 0.64, "color": Color.TRANSPARENT, "points": PackedVector2Array([Vector2(610, 120), Vector2(860, 120), Vector2(860, 430), Vector2(610, 430)])},
					{"name": &"mail shoot", "label": "", "grip": 1.0, "speed": 1.18, "color": Color.TRANSPARENT, "points": PackedVector2Array([Vector2(300, 245), Vector2(600, 245), Vector2(600, 490), Vector2(300, 490)])},
				]
			_:
				definitions = [
					{"name": &"wet spill", "label": "", "grip": 0.58, "speed": 0.88, "color": Color.TRANSPARENT, "points": PackedVector2Array([Vector2(-70, -485), Vector2(350, -485), Vector2(350, -255), Vector2(-70, -255)])},
					{"name": &"polish strip", "label": "", "grip": 1.0, "speed": 1.18, "color": Color.TRANSPARENT, "points": PackedVector2Array([Vector2(-560, 245), Vector2(-260, 245), Vector2(-260, 490), Vector2(-560, 490)])},
				]
	for data: Dictionary in definitions:
		var zone := SURFACE_ZONE_SCRIPT.new() as SurfaceZone
		zone.name = "%sSurface" % String(data["name"]).to_pascal_case()
		add_child(zone)
		zone.configure(data["name"], data["points"], float(data["grip"]), float(data["speed"]), data["color"], String(data["label"]))
		for key: String in ["role", "lane", "centerline_index", "inside_sign", "ai_path_clear"]:
			if data.has(key):
				zone.set_meta(key, data[key])
		surface_zones.append(zone)


func _add_line(parent: Node2D, points: PackedVector2Array, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.default_color = color
	line.width = width
	line.antialiased = true
	parent.add_child(line)
	return line
