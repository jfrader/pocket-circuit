extends Node2D

const DRESSING_TEXTURES: Dictionary = {
	&"Plate": preload("res://assets/textures/kitchen/plate_large.png"),
	&"CuttingBoard": preload("res://assets/textures/kitchen/cutting_board.png"),
	&"ToasterEdge": preload("res://assets/textures/kitchen/toaster_edge.png"),
	&"Napkin": preload("res://assets/textures/kitchen/napkin.png"),
	&"CerealScatter": preload("res://assets/textures/kitchen/cereal_scatter.png"),
}

const MICRO_TEXTURES: Dictionary = {
	&"Crumb01": preload("res://assets/textures/kitchen/crumb_cluster_01.png"),
	&"Crumb02": preload("res://assets/textures/kitchen/crumb_cluster_02.png"),
	&"Scratch": preload("res://assets/textures/kitchen/wood_scratch.png"),
	&"Droplet01": preload("res://assets/textures/kitchen/water_droplet_01.png"),
	&"Droplet02": preload("res://assets/textures/kitchen/water_droplet_02.png"),
	&"Spill": preload("res://assets/textures/kitchen/spill_decal.png"),
	&"Skid": preload("res://assets/textures/kitchen/skid_mark.png"),
}

var _ambient_time: float = 0.0
var _droplet_a: Sprite2D
var _droplet_b: Sprite2D
var _droplet_a_scale: Vector2
var _droplet_b_scale: Vector2


func _ready() -> void:
	_assign_dressing_textures()
	_assign_micro_textures()
	_droplet_a = get_node_or_null("MicroDressing/Droplet01A") as Sprite2D
	_droplet_b = get_node_or_null("MicroDressing/Droplet02C") as Sprite2D
	if _droplet_a:
		_droplet_a_scale = _droplet_a.scale
	if _droplet_b:
		_droplet_b_scale = _droplet_b.scale


func _process(delta: float) -> void:
	if _reduced_motion_enabled():
		if _droplet_a:
			_droplet_a.scale = _droplet_a_scale
		if _droplet_b:
			_droplet_b.scale = _droplet_b_scale
		return
	_ambient_time += delta
	if _droplet_a:
		_droplet_a.scale = _droplet_a_scale * (1.0 + sin(_ambient_time * 1.8) * 0.035)
	if _droplet_b:
		_droplet_b.scale = _droplet_b_scale * (1.0 + sin(_ambient_time * 1.45 + 1.2) * 0.03)


func _reduced_motion_enabled() -> bool:
	var app := get_node_or_null("/root/App")
	return bool(app.get("reduced_motion")) if app else false


func _assign_dressing_textures() -> void:
	var dressing := get_node_or_null("Dressing")
	if dressing == null:
		return
	for child in dressing.get_children():
		if child is Sprite2D and DRESSING_TEXTURES.has(child.name):
			(child as Sprite2D).texture = DRESSING_TEXTURES[child.name]


func _assign_micro_textures() -> void:
	var micro := get_node_or_null("MicroDressing")
	if micro == null:
		return
	for child in micro.get_children():
		if child is not Sprite2D:
			continue
		for prefix: StringName in MICRO_TEXTURES:
			if child.name.begins_with(prefix):
				(child as Sprite2D).texture = MICRO_TEXTURES[prefix]
				break
