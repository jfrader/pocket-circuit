extends RefCounted

const TEXTURES := "res://assets/textures/environment_pilot/"
const ALPHA_THRESHOLD := 0.5
const OUTLINE_EPSILON := 1.0
static var _geometry_cache: Dictionary = {}


static func measure(theme: String, asset: Dictionary) -> Dictionary:
	var path := TEXTURES + theme + "_" + String(asset["name"]) + ".png"
	if not _geometry_cache.has(path):
		var texture := load(path) as Texture2D
		var bitmap := BitMap.new()
		bitmap.create_from_image_alpha(texture.get_image(), ALPHA_THRESHOLD)
		var outlines := bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO, texture.get_size()), OUTLINE_EPSILON)
		var opaque_bounds := Rect2()
		for outline: PackedVector2Array in outlines:
			for point: Vector2 in outline:
				opaque_bounds = Rect2(point, Vector2.ZERO) if opaque_bounds == Rect2() else opaque_bounds.expand(point)
		_geometry_cache[path] = {"texture": texture, "outlines": outlines, "bounds": opaque_bounds}
	var geometry: Dictionary = _geometry_cache[path]
	var bounds: Rect2 = geometry["bounds"]
	var scale_factor := float(asset["length_mm"]) / maxf(bounds.size.x, bounds.size.y)
	return {"texture": geometry["texture"], "outlines": geometry["outlines"], "size": bounds.size * scale_factor, "scale": scale_factor}


static func add(parent: Node2D, manifest: Dictionary, theme: String, asset: Dictionary, placement: Dictionary) -> Dictionary:
	var role: Dictionary = manifest["roles"][placement["role"]]
	var geometry := measure(theme, asset)
	var texture: Texture2D = geometry["texture"]
	var physical_scale := float(geometry["scale"]) * float(manifest["units_per_mm"])
	var flat := String(asset.get("collision", "alpha")) == "flat"
	var body: Node2D = Node2D.new() if flat else StaticBody2D.new()
	body.name = String(asset["name"]).to_pascal_case() + str(parent.get_child_count())
	body.position = vector(placement["position"])
	body.rotation = float(placement["rotation"])
	body.z_index = -4 if flat else 0
	body.set_meta("asset_path", texture.resource_path)
	body.set_meta("pilot_theme", theme)
	body.set_meta("pilot_role", placement["role"])
	if body is StaticBody2D:
		body.collision_layer = 2
		body.collision_mask = 1
	parent.add_child(body)
	var shadow := Sprite2D.new()
	shadow.name = "ContactShadow"
	shadow.texture = texture
	shadow.scale = Vector2.ONE * physical_scale
	shadow.position = vector(role["shadow_offset"]).rotated(-body.rotation) * (0.3 if flat else 1.0)
	shadow.modulate = Color(manifest["shadow_color"])
	shadow.visible = bool(asset.get("shadow", true))
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	body.add_child(shadow)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.scale = Vector2.ONE * physical_scale
	sprite.modulate.a = float(asset.get("opacity", 1.0))
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	body.add_child(sprite)
	var world_outlines: Array[PackedVector2Array] = []
	for outline: PackedVector2Array in geometry["outlines"]:
		var local_points := PackedVector2Array()
		var global_points := PackedVector2Array()
		for point: Vector2 in outline:
			var local_point := (point - texture.get_size() * 0.5) * physical_scale
			local_points.append(local_point)
			global_points.append(body.to_global(local_point))
		if not flat:
			var collision := CollisionPolygon2D.new()
			collision.polygon = local_points
			body.add_child(collision)
		world_outlines.append(global_points)
	return {"role": placement["role"], "length_mm": asset["length_mm"], "outlines": world_outlines, "body": body, "flat": flat}


static func vector(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
