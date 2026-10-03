extends RefCounted
## Front-facing layered portrait at the native 128 px. The art is drawn looking
## right; facing "left" mirrors the finished layers.

const SIZE := 128
const CX := 64.0
const EYE_Y := 60.0
const BROW_Y := 50.5
const MOUTH_Y := 82.0
const SKULL_Y := 44.0
const SKULL_RY := 25.0
const LIGHT := Vector2(-2.4, -1.8)
const SUBSAMPLES := [0.125, 0.375, 0.625, 0.875]
const LAYERS := ["hair_back", "clothing", "face", "eyes", "mouth", "hair", "accessories"]
## The pixels each facial choice may change; the smoke test holds the art to them.
const EYE_REGION := Rect2i(38, 42, 52, 26)
const NOSE_REGION := Rect2i(54, 58, 21, 22)
const MOUTH_REGION := Rect2i(46, 75, 36, 20)
## Right half-widths of the head at the temple, cheekbone, jaw and chin, and the
## jaw and chin rows.
const FACE_SHAPES := {
	"oval": {"temple": 25.0, "cheek": 25.5, "jaw": 20.5, "chin": 8.5, "jaw_y": 82.0, "chin_y": 96.0},
	"square": {"temple": 25.5, "cheek": 26.0, "jaw": 25.0, "chin": 14.0, "jaw_y": 85.0, "chin_y": 95.0},
	"round": {"temple": 26.0, "cheek": 28.0, "jaw": 24.5, "chin": 11.0, "jaw_y": 80.0, "chin_y": 93.0},
	"long": {"temple": 23.5, "cheek": 24.0, "jaw": 20.5, "chin": 9.0, "jaw_y": 85.0, "chin_y": 100.0},
	"diamond": {"temple": 22.5, "cheek": 27.5, "jaw": 19.5, "chin": 7.0, "jaw_y": 82.0, "chin_y": 96.0},
	"heart": {"temple": 26.5, "cheek": 25.5, "jaw": 18.5, "chin": 6.0, "jaw_y": 82.0, "chin_y": 95.0},
	"soft_square": {"temple": 25.0, "cheek": 26.0, "jaw": 23.5, "chin": 12.0, "jaw_y": 84.0, "chin_y": 96.0},
	"tapered": {"temple": 25.5, "cheek": 25.5, "jaw": 19.0, "chin": 7.5, "jaw_y": 81.0, "chin_y": 97.0},
}
const TEMPLATES := {
	"male": {"cheek": 0.5, "jaw": 1.5, "chin": 2.5, "chin_y": 2.0, "neck": 10.5, "shoulders": 1.04},
	"female": {"cheek": -0.3, "jaw": -1.5, "chin": -1.5, "chin_y": -1.0, "neck": 8.0, "shoulders": 0.94},
	"legacy": {"cheek": 0.0, "jaw": 0.0, "chin": 0.0, "chin_y": 0.0, "neck": 9.5, "shoulders": 1.0},
}
## Half-spacing, width, upper and lower lid heights, and outer-corner tilt.
const EYE_STYLES := {
	"round": {"spacing": 12.5, "width": 10.5, "upper": 4.3, "lower": 3.3, "tilt": 0.0},
	"narrow": {"spacing": 12.5, "width": 11.5, "upper": 2.7, "lower": 1.9, "tilt": 0.0},
	"wide": {"spacing": 13.5, "width": 12.0, "upper": 4.2, "lower": 3.0, "tilt": 0.0},
	"hooded": {"spacing": 12.5, "width": 11.0, "upper": 3.4, "lower": 2.7, "tilt": 0.3},
	"upturned": {"spacing": 12.5, "width": 11.0, "upper": 3.7, "lower": 2.5, "tilt": -1.6},
	"downturned": {"spacing": 12.5, "width": 11.0, "upper": 3.5, "lower": 2.8, "tilt": 0.9},
}
## Heights at the inner end, peak and outer end (positive is lower), where the
## peak sits, and thickness at each end. No inner end sits above its outer end,
## so no brow reads as worried.
const BROW_STYLES := {
	"straight": {"inner": 0.4, "peak": -0.4, "outer": 0.4, "at": 0.55, "thick": 2.4, "thin": 1.4},
	"arched": {"inner": 0.9, "peak": -1.9, "outer": 0.9, "at": 0.62, "thick": 2.2, "thin": 1.0},
	"thick": {"inner": 0.4, "peak": -0.8, "outer": 0.4, "at": 0.55, "thick": 3.6, "thin": 2.2},
	"soft": {"inner": 0.6, "peak": -1.1, "outer": 0.6, "at": 0.55, "thick": 1.7, "thin": 0.9},
	"angled": {"inner": 1.1, "peak": -1.4, "outer": 0.1, "at": 0.72, "thick": 2.6, "thin": 1.2},
	"unibrow": {"inner": 0.4, "peak": -0.5, "outer": 0.4, "at": 0.55, "thick": 2.6, "thin": 1.5},
}
## Half-width at the nostrils and the tip row.
const NOSE_STYLES := {
	"straight": {"width": 4.0, "tip": 72.0},
	"broad": {"width": 5.8, "tip": 72.0},
	"short": {"width": 3.8, "tip": 69.5},
	"angular": {"width": 3.4, "tip": 73.0},
	"hooked": {"width": 4.0, "tip": 73.5},
	"button": {"width": 3.5, "tip": 69.5},
}

var escaped_pixels := 0
var _traits: Dictionary
var _palette: Dictionary
var _gender := "legacy"
var _shape: Dictionary
var _head: PackedVector2Array


func render(payload: Dictionary, apply_facing: bool = true) -> Dictionary:
	_traits = payload["traits"]
	_gender = _traits.get("gender", "legacy")
	_palette = payload["palette"]
	escaped_pixels = 0
	_shape = _face_shape()
	_head = _head_outline()
	var layers := {}
	for name in LAYERS:
		layers[name] = _blank()
	_clothing(layers["clothing"])
	_face(layers["face"])
	_eyes(layers["eyes"])
	_brows(layers["eyes"])
	if _traits["marking"] == "brow_scar":
		_stroke(layers["eyes"], [Vector2(CX + 14.5, BROW_Y - 4.0), Vector2(CX + 13.0, BROW_Y + 3.5)], _c("skin_highlight"), 1.4)
	_mouth(layers["mouth"])
	_hair(layers["hair"], layers["hair_back"])
	_accessory(layers["accessories"])
	var portrait := _blank()
	for name in LAYERS:
		portrait.blend_rect(layers[name], Rect2i(0, 0, SIZE, SIZE), Vector2i.ZERO)
	layers["portrait"] = portrait
	if apply_facing and payload["facing"] == "left":
		for image: Image in layers.values():
			image.flip_x()
	if escaped_pixels:
		push_error("Avatar artwork exceeded its canvas: %d pixels" % escaped_pixels)
	return layers


# --- geometry -------------------------------------------------------------------

func _face_shape() -> Dictionary:
	var shape: Dictionary = FACE_SHAPES[_traits["face_shape"]].duplicate()
	var template: Dictionary = TEMPLATES[_gender]
	for key in ["cheek", "jaw", "chin", "chin_y"]:
		shape[key] += template[key]
	shape["neck"] = template["neck"]
	shape["shoulders"] = template["shoulders"]
	shape["skull"] = shape["temple"] + 1.2
	return shape


func _head_outline() -> PackedVector2Array:
	var s := _shape
	return _symmetric(_smooth([
		Vector2(0, 20), Vector2(12, 21.5), Vector2(20, 26), Vector2(s["temple"] - 1.5, 33),
		Vector2(s["temple"], 44), Vector2(s["temple"] + 0.3, 53), Vector2(s["cheek"], 64),
		Vector2(s["jaw"], s["jaw_y"]),
		Vector2(s["chin"] + (s["jaw"] - s["chin"]) * 0.4, s["jaw_y"] + (s["chin_y"] - s["jaw_y"]) * 0.7),
		Vector2(s["chin"], s["chin_y"] - 2.0), Vector2(s["chin"] * 0.5, s["chin_y"] - 0.3), Vector2(0, s["chin_y"]),
	]))


## Right-half points from top centre to bottom centre, relative to CX, become a
## closed mirrored polygon.
func _symmetric(right: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in right:
		points.append(Vector2(CX + p.x, p.y))
	for i in range(right.size() - 2, 0, -1):
		points.append(Vector2(CX - right[i].x, right[i].y))
	return points


func _mirror(points: PackedVector2Array) -> PackedVector2Array:
	var mirrored := PackedVector2Array()
	for i in range(points.size() - 1, -1, -1):
		mirrored.append(Vector2(2.0 * CX - points[i].x, points[i].y))
	return mirrored


func _both(points: PackedVector2Array) -> Array:
	return [points, _mirror(points)]


## Catmull-Rom through the points, `steps` samples per span.
func _smooth(points: Array, steps: int = 5) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(points.size() - 1):
		var p0: Vector2 = points[maxi(i - 1, 0)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var p3: Vector2 = points[mini(i + 2, points.size() - 1)]
		for step in range(steps):
			var t := float(step) / steps
			result.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	result.append(points[points.size() - 1])
	return result


func _ellipse(center: Vector2, radius: Vector2, segments: int = 32) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments):
		var angle := TAU * i / segments
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return points


## Counter-clockwise on screen from `from` to `to` radians, zero pointing right.
func _arc(center: Vector2, radius: Vector2, from: float, to: float, segments: int = 16) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(segments + 1):
		var angle := lerpf(from, to, float(i) / segments)
		points.append(center + Vector2(cos(angle) * radius.x, -sin(angle) * radius.y))
	return points


func _moved(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var moved := PackedVector2Array()
	for p in points:
		moved.append(p + offset)
	return moved


func _band(upper: PackedVector2Array, lower: PackedVector2Array) -> PackedVector2Array:
	var band := upper.duplicate()
	for i in range(lower.size() - 1, -1, -1):
		band.append(lower[i])
	return band


func _grow(points: PackedVector2Array, amount: float) -> Array:
	return Geometry2D.offset_polygon(points, amount, Geometry2D.JOIN_ROUND)


func _within(points: PackedVector2Array, clip: PackedVector2Array) -> Array:
	return Geometry2D.intersect_polygons(points, clip)


## The outer boundary of overlapping shapes.
func _union(shapes: Array) -> PackedVector2Array:
	var merged: PackedVector2Array = shapes[0]
	for shape: PackedVector2Array in shapes.slice(1):
		var largest := 0.0
		for part: PackedVector2Array in Geometry2D.merge_polygons(merged, shape):
			var area := absf(_area(part))
			if area > largest:
				largest = area
				merged = part
	return merged


func _area(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(points.size()):
		total += points[i].cross(points[(i + 1) % points.size()])
	return total * 0.5


# --- colour ---------------------------------------------------------------------

func _c(role: String) -> Color:
	return Color(_palette[role])


func _contour(base: Color) -> Color:
	return base.darkened(0.5).lerp(_c("outline"), 0.35)


func _wardrobe(role: String) -> Color:
	return _c("outfit_" + role).lerp(_c("accent"), 0.32)


# --- rasterising ----------------------------------------------------------------

func _blank() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return image


## Even-odd scanline fill with exact horizontal and fourfold vertical coverage.
func _fill(image: Image, polygons: Variant, color: Color) -> void:
	var list: Array = [polygons] if polygons is PackedVector2Array else polygons
	var edges: Array[Vector4] = []
	var box := Rect2()
	var started := false
	for polygon: PackedVector2Array in list:
		for i in range(polygon.size()):
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			box = box.expand(a) if started else Rect2(a, Vector2.ZERO)
			started = true
			if a.y != b.y:
				edges.append(Vector4(a.x, a.y, b.x, b.y) if a.y < b.y else Vector4(b.x, b.y, a.x, a.y))
	if edges.is_empty():
		return
	var left := floori(box.position.x)
	var width := ceili(box.end.x) - left + 1
	var coverage := PackedFloat32Array()
	coverage.resize(width)
	for y in range(floori(box.position.y), ceili(box.end.y) + 1):
		coverage.fill(0.0)
		var any := false
		for offset: float in SUBSAMPLES:
			var row := y + offset
			var crossings := PackedFloat32Array()
			for edge in edges:
				if row >= edge.y and row < edge.w:
					crossings.append(edge.x + (row - edge.y) * (edge.z - edge.x) / (edge.w - edge.y))
			crossings.sort()
			for i in range(0, crossings.size() - 1, 2):
				var from := crossings[i]
				var to := crossings[i + 1]
				for x in range(floori(from), ceili(to)):
					var overlap := minf(to, x + 1.0) - maxf(from, float(x))
					if overlap > 0.0:
						coverage[x - left] += overlap * 0.25
						any = true
		if any:
			for i in range(width):
				if coverage[i] > 0.002:
					_put(image, left + i, y, color, minf(coverage[i], 1.0))


func _put(image: Image, x: int, y: int, color: Color, coverage: float) -> void:
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		escaped_pixels += 1
		return
	var source := color
	source.a = color.a * coverage
	image.set_pixel(x, y, image.get_pixel(x, y).blend(source))


## A closed loop comes back as an outline and its hole, so the parts fill together.
func _stroke(image: Image, points: Variant, color: Color, width: float = 1.0) -> void:
	_fill(image, Geometry2D.offset_polyline(PackedVector2Array(points), width * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND), color)


func _disc(image: Image, center: Vector2, radius: Vector2, color: Color, clip := PackedVector2Array()) -> void:
	var shape := _ellipse(center, radius)
	_fill(image, shape if clip.is_empty() else _within(shape, clip), color)


## A lit mass: contour, shadow colour, then the part the light reaches.
func _mass(image: Image, polygons: Variant, contour: Color, shadow: Color, base: Color, light := LIGHT) -> void:
	var list: Array = [polygons] if polygons is PackedVector2Array else polygons
	for polygon: PackedVector2Array in list:
		for grown: PackedVector2Array in _grow(polygon, 1.1):
			_fill(image, grown, contour)
	for polygon: PackedVector2Array in list:
		_fill(image, polygon, shadow)
		_fill(image, _within(polygon, _moved(polygon, light)), base)


# --- bust -----------------------------------------------------------------------

func _clothing(image: Image) -> void:
	var neck: float = _shape["neck"]
	var chin_y: float = _shape["chin_y"]
	var throat := _symmetric(PackedVector2Array([Vector2(0, chin_y - 16.0), Vector2(neck, chin_y - 16.0), Vector2(neck, 100), Vector2(neck + 4.0, 107), Vector2(0, 107)]))
	_mass(image, throat, _contour(_c("skin_shadow")), _c("skin_shadow"), _c("skin_base"), Vector2(-3.0, 0))
	_disc(image, Vector2(CX, chin_y + 1.5), Vector2(neck + 1.0, 4.5), _c("skin_shadow"), throat)
	var wide: float = _shape["shoulders"]
	var bust := _symmetric(PackedVector2Array([
		Vector2(0, 104), Vector2(neck + 2.0, 100.5), Vector2((neck + 13.0) * wide, 103.5), Vector2(38.0 * wide, 107.5),
		Vector2(46.0 * wide, 113.0), Vector2(50.0 * wide, 119.5), Vector2(51.0 * wide, 124.4), Vector2(0, 124.4),
	]))
	_mass(image, bust, _contour(_wardrobe("shadow")), _wardrobe("shadow"), _wardrobe("base"), Vector2(-3.5, -2.0))
	_stroke(image, [Vector2(CX - neck - 8.0, 105.0), Vector2(CX - 30.0 * wide, 108.0), Vector2(CX - 41.0 * wide, 113.0)], Color(_wardrobe("light"), 0.8), 1.6)
	_outfit(image, neck)


## Skin showing above a neckline of the given depth and half-width.
func _neckline(image: Image, depth: float, width: float) -> PackedVector2Array:
	var cut := _symmetric(PackedVector2Array([Vector2(0, 99), Vector2(width, 99), Vector2(width * 0.75, 101 + depth * 0.4), Vector2(0, 101 + depth)]))
	_fill(image, cut, _c("skin_shadow"))
	_fill(image, _within(cut, _moved(cut, Vector2(-2.5, -3.0))), _c("skin_base"))
	return cut


func _lapels(image: Image, right: PackedVector2Array, color: Color, lit: Color, light := Vector2(-1.2, -1.0)) -> void:
	for side: PackedVector2Array in _both(right):
		_mass(image, side, _contour(color), color, lit, light)


func _badge(image: Image, y: float) -> void:
	_stroke(image, [Vector2(CX - 31, y), Vector2(CX - 22, y)], _c("accent"), 1.8)


func _outfit(image: Image, neck: float) -> void:
	var light := _wardrobe("light")
	var shadow := _wardrobe("shadow")
	var base := _wardrobe("base")
	var shirt := _c("eye_white").lerp(_c("outfit_light"), 0.45)
	var accent := _c("accent")
	var metal := _c("metal")
	match _traits["outfit"]:
		"crew":
			var cut := _neckline(image, 5.0, neck + 1.5)
			var hem := cut.slice(1, cut.size())
			_stroke(image, hem, shadow, 2.6)
			_stroke(image, hem, light, 1.1)
			_badge(image, 117)
		"jacket":
			_fill(image, _symmetric(PackedVector2Array([Vector2(0, 99), Vector2(neck + 2.0, 99), Vector2(4, 118), Vector2(0, 119)])), shirt)
			_neckline(image, 3.5, neck - 1.0)
			_lapels(image, PackedVector2Array([Vector2(CX + neck + 1.0, 98), Vector2(CX + neck + 7.5, 100), Vector2(CX + 7.0, 121), Vector2(CX + 3.5, 121)]), shadow, base)
			_stroke(image, [Vector2(CX + 5.0, 112), Vector2(CX + 5.0, 117)], metal, 1.3)
			_badge(image, 118)
		"turtleneck":
			var collar := _symmetric(PackedVector2Array([Vector2(0, _shape["chin_y"] + 2.0), Vector2(neck + 1.5, _shape["chin_y"] + 2.0), Vector2(neck + 3.5, 104), Vector2(0, 105)]))
			_mass(image, collar, _contour(shadow), shadow, base, Vector2(-2.5, -1.0))
			for y in [_shape["chin_y"] + 5.5, 101.5]:
				_stroke(image, [Vector2(CX - neck - 1.0, y), Vector2(CX, y + 1.0), Vector2(CX + neck + 1.0, y)], shadow, 1.0)
			_badge(image, 117)
		"hoodie":
			_neckline(image, 4.0, neck)
			var hood := _symmetric(PackedVector2Array([Vector2(0, 104), Vector2(neck + 1.0, 97), Vector2(neck + 9.0, 97.5), Vector2(neck + 11.0, 103), Vector2(9, 108), Vector2(0, 108.5)]))
			_mass(image, hood, _contour(shadow), shadow, light, Vector2(-2.0, -1.5))
			_fill(image, _symmetric(PackedVector2Array([Vector2(0, 101.5), Vector2(neck + 1.5, 99.5), Vector2(neck + 5.0, 101), Vector2(7, 105), Vector2(0, 105)])), shadow.darkened(0.3))
			for x in [-4.5, 4.5]:
				_stroke(image, [Vector2(CX + x, 107), Vector2(CX + x * 1.1, 118)], shirt, 1.2)
				_disc(image, Vector2(CX + x * 1.1, 119), Vector2(0.9, 0.9), metal)
		"collared":
			_neckline(image, 5.0, neck - 0.5)
			_lapels(image, PackedVector2Array([Vector2(CX + 1.0, 104.5), Vector2(CX + neck + 1.0, 97), Vector2(CX + neck + 5.0, 101), Vector2(CX + 7.0, 108)]), shirt.darkened(0.12), shirt, Vector2(-1.0, -0.8))
			_stroke(image, [Vector2(CX, 108), Vector2(CX, 124)], shadow, 1.4)
			for y in [112.0, 118.0]:
				_disc(image, Vector2(CX + 1.2, y), Vector2(0.9, 0.9), shirt)
			_badge(image, 118)
		"armor":
			_mass(image, _symmetric(PackedVector2Array([Vector2(0, 101), Vector2(neck + 2.0, 98), Vector2(neck + 6.0, 103), Vector2(10, 109), Vector2(0, 110)])), _contour(shadow), shadow, light, Vector2(-1.5, -1.5))
			for pauldron: PackedVector2Array in _both(_ellipse(Vector2(CX + 37.0 * _shape["shoulders"], 111), Vector2(13, 8.5), 24)):
				_mass(image, pauldron, _contour(shadow), base, light, Vector2(-2.5, -2.0))
			_stroke(image, [Vector2(CX, 110), Vector2(CX, 124)], light, 1.4)
			_disc(image, Vector2(CX, 116), Vector2(2.2, 2.2), accent)
		"polo":
			_neckline(image, 6.5, neck - 1.0)
			_lapels(image, PackedVector2Array([Vector2(CX + 1.0, 101.5), Vector2(CX + neck, 97.5), Vector2(CX + neck + 4.0, 101.5), Vector2(CX + 5.0, 104.5)]), shadow, light, Vector2(-1.0, -0.8))
			_stroke(image, [Vector2(CX, 107), Vector2(CX, 115)], shadow, 1.3)
			for y in [109.5, 113.5]:
				_disc(image, Vector2(CX + 1.3, y), Vector2(0.7, 0.7), shirt)
			_badge(image, 117)
		"cardigan":
			_fill(image, _symmetric(PackedVector2Array([Vector2(0, 99), Vector2(neck + 3.0, 99), Vector2(3, 118), Vector2(0, 119)])), accent.lerp(shirt, 0.55))
			_neckline(image, 4.0, neck)
			for edge: PackedVector2Array in _both(PackedVector2Array([Vector2(CX + neck + 3.0, 99), Vector2(CX + neck + 5.5, 100), Vector2(CX + 3.0, 121), Vector2(CX + 1.0, 121), Vector2(CX + 2.0, 118)])):
				_fill(image, edge, light)
			for y in [113.0, 119.0]:
				_disc(image, Vector2(CX + 4.0, y), Vector2(0.9, 0.9), shirt)
			for x in range(-44, -28, 4):
				_stroke(image, [Vector2(CX + x, 118), Vector2(CX + x, 123)], shadow, 0.8)
		"blazer":
			_fill(image, _symmetric(PackedVector2Array([Vector2(0, 99), Vector2(neck + 2.0, 99), Vector2(5, 120), Vector2(0, 121)])), shirt)
			_neckline(image, 3.0, neck - 1.5)
			_fill(image, PackedVector2Array([Vector2(CX - 1.5, 104), Vector2(CX + 1.5, 104), Vector2(CX + 2.5, 117), Vector2(CX, 120), Vector2(CX - 2.5, 117)]), accent)
			_lapels(image, PackedVector2Array([Vector2(CX + neck + 1.0, 98.5), Vector2(CX + neck + 7.0, 100.5), Vector2(CX + neck + 4.0, 104), Vector2(CX + neck + 7.0, 106), Vector2(CX + 7.5, 121), Vector2(CX + 5.0, 121)]), shadow, base)
			_fill(image, PackedVector2Array([Vector2(CX - 33, 114.5), Vector2(CX - 25, 114.5), Vector2(CX - 26, 117), Vector2(CX - 32, 117)]), _c("accent_light"))
		"denim":
			_neckline(image, 5.0, neck - 0.5)
			_lapels(image, PackedVector2Array([Vector2(CX + 1.0, 104.5), Vector2(CX + neck + 1.0, 97), Vector2(CX + neck + 6.0, 101), Vector2(CX + 8.0, 107)]), shadow, light, Vector2(-1.0, -0.8))
			_stroke(image, [Vector2(CX, 108), Vector2(CX, 124)], light, 1.2)
			for x in [-22.0, 12.0]:
				var pocket := PackedVector2Array([Vector2(CX + x, 112), Vector2(CX + x + 10, 112), Vector2(CX + x + 9.5, 120), Vector2(CX + x + 5, 121.5), Vector2(CX + x + 0.5, 120), Vector2(CX + x, 112)])
				_stroke(image, pocket, shadow, 0.9)
				_stroke(image, [Vector2(CX + x, 114.5), Vector2(CX + x + 10, 114.5)], light, 0.9)
				_disc(image, Vector2(CX + x + 5, 116.5), Vector2(0.9, 0.9), metal.lerp(accent, 0.3))


# --- face -----------------------------------------------------------------------

func _face(image: Image) -> void:
	var ear_x: float = _shape["temple"] + 0.6
	for side in [-1.0, 1.0]:
		var ear := _ellipse(Vector2(CX + side * ear_x, 64.0), Vector2(3.8, 7.0), 24)
		var lit := _c("skin_base") if side < 0 else _c("skin_shadow").lerp(_c("skin_base"), 0.45)
		_mass(image, ear, _contour(_c("skin_shadow")), _c("skin_shadow"), lit)
		_stroke(image, _arc(Vector2(CX + side * (ear_x + 0.6), 64.0), Vector2(2.0, 4.2), PI * 0.5 - side * 1.2, PI * 0.5 + side * 2.3, 10), _c("skin_shadow").darkened(0.15), 0.9)
	_mass(image, _head, _contour(_c("skin_shadow")), _c("skin_shadow"), _c("skin_base"))
	for area: PackedVector2Array in _within(_head, _moved(_head, LIGHT)):
		_fill(image, _within(_ellipse(Vector2(CX - 7.0, 33.0), Vector2(12.0, 7.5)), area), Color(_c("skin_highlight"), 0.8))
		_fill(image, _within(_ellipse(Vector2(CX - 16.0, 67.0), Vector2(4.5, 2.6)), area), Color(_c("skin_highlight"), 0.55))
	_stroke(image, _smooth([Vector2(CX - _shape["temple"] + 1.5, 40), Vector2(CX - _shape["temple"] + 1.0, 52), Vector2(CX - _shape["cheek"] + 2.2, 63)]), Color(_c("skin_rim"), 0.55), 1.1)
	for side in [-1.0, 1.0]:
		_disc(image, Vector2(CX + side * 15.5, 73.5), Vector2(5.0, 2.8), Color(_c("skin_highlight").lerp(_c("mouth"), 0.55), 0.14))
	_marking(image)
	_nose(image)
	_facial_hair(image)


func _nose(image: Image) -> void:
	var style: Dictionary = NOSE_STYLES[_traits["nose_style"]]
	var width: float = style["width"] * (0.9 if _gender == "female" else (1.08 if _gender == "male" else 1.0))
	var tip: float = style["tip"] - (0.5 if _gender == "female" else 0.0)
	var side := PackedVector2Array([Vector2(CX + 1.2, EYE_Y + 2.0), Vector2(CX + 2.4, tip - 4.0), Vector2(CX + width, tip - 0.5), Vector2(CX + width - 1.0, tip + 1.2), Vector2(CX + 1.0, tip + 0.6)])
	if _traits["nose_style"] == "angular":
		side[3] = Vector2(CX + width + 0.5, tip + 0.8)
	_fill(image, side, Color(_c("skin_shadow"), 0.8))
	_stroke(image, [Vector2(CX - 1.4, EYE_Y + 1.5), Vector2(CX - 1.6, tip - 3.0)], Color(_c("skin_highlight"), 0.7), 1.1)
	if _traits["nose_style"] == "hooked":
		_stroke(image, [Vector2(CX + 1.4, EYE_Y + 3.0), Vector2(CX + 2.6, EYE_Y + 6.0), Vector2(CX + 2.0, EYE_Y + 9.0)], _c("skin_shadow"), 1.1)
	_stroke(image, _smooth([Vector2(CX - width, tip - 0.3), Vector2(CX - width * 0.45, tip + 1.6), Vector2(CX, tip + 2.0), Vector2(CX + width * 0.45, tip + 1.6), Vector2(CX + width, tip - 0.3)], 3), Color(_c("skin_shadow"), 0.9), 1.0)
	for x in [-1.0, 1.0]:
		_disc(image, Vector2(CX + x * (width - 1.4), tip + 0.8), Vector2(1.0, 0.6), _c("skin_shadow").darkened(0.35))
	var tip_size := 1.7 if _traits["nose_style"] == "button" else 1.2
	_disc(image, Vector2(CX - 0.8, tip - 1.6), Vector2(tip_size, tip_size * 0.8), Color(_c("skin_highlight"), 0.85))


func _eyes(image: Image) -> void:
	var style: Dictionary = EYE_STYLES[_traits["eye_style"]]
	var female := _gender == "female"
	var upper: float = style["upper"] + (0.3 if female else (-0.2 if _gender == "male" else 0.0))
	var lash := _c("outline").lerp(_c("hair_shadow"), 0.3)
	var radius := 3.1 if female else 2.9
	for side in [1.0, -1.0]:
		var center: float = CX + side * style["spacing"]
		var top := PackedVector2Array()
		var bottom := PackedVector2Array()
		for i in range(13):
			var t := float(i) / 12.0
			var point := Vector2(center + side * style["width"] * (t - 0.5), EYE_Y + style["tilt"] * t)
			top.append(point - Vector2(0, upper * sin(PI * pow(t, 0.8))))
			bottom.append(point + Vector2(0, style["lower"] * sin(PI * pow(t, 1.1))))
		var shape := top.duplicate()
		for i in range(bottom.size() - 2, 0, -1):
			shape.append(bottom[i])
		_stroke(image, _moved(top.slice(2, 11), Vector2(0, -upper * 0.45 - 1.6)), Color(_c("skin_shadow"), 0.6), 1.0)
		_fill(image, shape, _c("eye_white"))
		var iris := Vector2(center + 0.7, EYE_Y + 0.4 + style["tilt"] * 0.5)
		_disc(image, iris, Vector2(radius, radius), _c("iris").darkened(0.3), shape)
		_disc(image, iris, Vector2(radius - 0.8, radius - 0.8), _c("iris"), shape)
		_disc(image, iris + Vector2(0, 1.0), Vector2(radius - 1.2, radius - 1.8), Color(_c("iris_light"), 0.7), shape)
		_disc(image, iris, Vector2(radius * 0.45, radius * 0.45), _c("eye_dark"), shape)
		_disc(image, iris + Vector2(-1.0, -1.1), Vector2(0.8, 0.8), _c("eye_white").lightened(0.5), shape)
		if _traits["eye_style"] == "hooded":
			var lid := top.duplicate()
			for i in range(top.size() - 1, -1, -1):
				lid.append(top[i] + Vector2(0, 1.5 * sin(PI * i / 12.0)))
			_fill(image, lid, _c("skin_base"))
			_stroke(image, _moved(top, Vector2(0, 1.4)), Color(_c("skin_shadow"), 0.8), 0.9)
		_stroke(image, top, lash, 1.6 if female else 1.3)
		if female:
			var corner := top[top.size() - 1]
			_stroke(image, [corner, corner + Vector2(side * 1.8, -1.3)], lash, 1.1)


func _brows(image: Image) -> void:
	var style: Dictionary = BROW_STYLES[_traits["brow_style"]]
	var weight := 1.25 if _gender == "male" else (0.85 if _gender == "female" else 1.0)
	var arch := -0.4 if _gender == "female" else 0.0
	var color := _c("hair_base").lerp(_c("hair_shadow"), 0.4) if _traits["brow_style"] == "soft" else _c("hair_shadow").lerp(_c("hair_base"), 0.2)
	for side in [1.0, -1.0]:
		var upper := []
		var lower := []
		for i in range(11):
			var t := float(i) / 10.0
			var at: float = style["at"]
			var peak: float = style["peak"] + arch
			var rise: float = lerpf(style["inner"], peak, t / at) if t <= at else lerpf(peak, style["outer"], (t - at) / (1.0 - at))
			var half: float = lerpf(style["thick"], style["thin"], t) * weight * 0.5
			var point := Vector2(CX + side * (5.5 + 14.0 * t), BROW_Y + rise)
			upper.append(point - Vector2(0, half))
			lower.append(point + Vector2(0, half))
		_fill(image, _band(_smooth(upper, 2), _smooth(lower, 2)), color)
		_stroke(image, PackedVector2Array(upper.slice(1, 8)), Color(_c("hair_base"), 0.45), 0.7)
	if _traits["brow_style"] == "unibrow":
		_stroke(image, [Vector2(CX - 6.0, BROW_Y + 0.6), Vector2(CX, BROW_Y + 1.0), Vector2(CX + 6.0, BROW_Y + 0.6)], color, 1.6 * weight)


## A mouth line as a parabola: half-width, corner offset and centre offset from MOUTH_Y.
func _curve(half: float, corner: float, middle: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(11):
		var t := float(i) / 5.0 - 1.0
		points.append(Vector2(CX + t * half, MOUTH_Y + lerpf(middle, corner, t * t)))
	return points


func _mouth(image: Image) -> void:
	var female := _gender == "female"
	var line := _c("skin_shadow").darkened(0.4).lerp(_c("mouth"), 0.4)
	var lip := _c("skin_highlight").lerp(_c("mouth"), 0.55 if female else 0.4)
	var gloss := Color(_c("skin_highlight"), 0.75)
	var inside := _c("mouth").darkened(0.55)
	var teeth := _c("eye_white")
	var y := MOUTH_Y
	match _traits["mouth_style"]:
		"neutral":
			_lower_lip(image, 6.0, lip, female)
			_stroke(image, _smooth([Vector2(CX - 7.5, y - 0.6), Vector2(CX - 4.0, y + 0.2), Vector2(CX + 4.0, y + 0.2), Vector2(CX + 7.5, y - 0.6)], 3), line, 1.3)
		"smile":
			_lower_lip(image, 6.5, lip, female)
			_stroke(image, _curve(8.0, -1.4, 1.3), line, 1.4)
		"wide":
			var upper := _curve(10.0, -2.0, 1.4)
			_fill(image, _band(upper, _curve(8.5, -0.8, 4.0)), lip)
			_stroke(image, upper, line, 1.3)
			_stroke(image, _moved(_curve(4.5, 0.0, 0.3), Vector2(0, 4.8)), gloss, 0.9)
		"serious":
			_lower_lip(image, 5.5, lip, female)
			_stroke(image, [Vector2(CX - 7.0, y + 0.2), Vector2(CX + 7.0, y + 0.2)], line, 1.6)
		"grin":
			var upper := _curve(9.5, -2.0, 0.6)
			var lower := _curve(9.5, -2.0, 5.0)
			_fill(image, _band(upper, lower), inside)
			_fill(image, _band(upper, _moved(upper, Vector2(0, 2.2))), teeth)
			_stroke(image, upper, line, 1.3)
			_stroke(image, lower, line, 0.9)
		"smirk":
			_lower_lip(image, 6.0, lip, female)
			_stroke(image, _smooth([Vector2(CX - 7.0, y + 0.3), Vector2(CX - 2.0, y + 0.8), Vector2(CX + 4.0, y + 0.1), Vector2(CX + 8.0, y - 2.2)], 3), line, 1.4)
			_stroke(image, [Vector2(CX + 8.6, y - 3.0), Vector2(CX + 9.4, y - 1.6)], Color(_c("skin_shadow"), 0.7), 0.8)
		"open":
			var upper := _curve(7.5, -1.0, 0.2)
			var lower := _curve(7.0, -1.0, 6.0)
			var opening := _band(upper, lower)
			_fill(image, opening, inside)
			_fill(image, _band(upper, _moved(upper, Vector2(0, 1.8))), teeth)
			_disc(image, Vector2(CX, y + 4.3), Vector2(3.6, 1.6), lip.lerp(_c("mouth"), 0.5), opening)
			_stroke(image, upper, line, 1.2)
			_stroke(image, lower, line, 0.9)
		"closed_smile":
			var upper := _curve(8.5, -1.6, 1.0)
			_fill(image, _band(_moved(upper, Vector2(0, -1.6)), upper), lip)
			_fill(image, _band(upper, _curve(7.0, -0.6, 3.6)), lip)
			_stroke(image, upper, line, 1.1)
			_stroke(image, _moved(_curve(3.5, 0.0, 0.2), Vector2(0, 4.6)), gloss, 0.8)
		"skeptical":
			_lower_lip(image, 5.5, lip, female)
			_stroke(image, _smooth([Vector2(CX - 7.0, y + 0.6), Vector2(CX, y + 0.3), Vector2(CX + 5.0, y - 0.2), Vector2(CX + 7.5, y - 1.2)], 3), line, 1.4)


func _lower_lip(image: Image, half: float, lip: Color, female: bool) -> void:
	var depth := 3.2 if female else 2.4
	_fill(image, _band(_curve(half, 0.4, 1.2), _curve(half * 0.8, 0.8, 1.2 + depth)), Color(lip, 0.85))
	_stroke(image, _moved(_curve(half * 0.45, 0.0, 0.2), Vector2(0, depth + 2.4)), Color(_c("skin_highlight"), 0.6), 0.8)


func _marking(image: Image) -> void:
	match _traits["marking"]:
		"freckles":
			for p in [Vector2(-18, 68), Vector2(-14, 70.5), Vector2(-10, 68.5), Vector2(-16, 73), Vector2(-4, 66), Vector2(3, 66.5), Vector2(10, 68.5), Vector2(14, 70.5), Vector2(18, 68), Vector2(16, 73)]:
				_disc(image, Vector2(CX, 0) + p, Vector2(0.7, 0.6), _c("skin_shadow").darkened(0.15))
		"cheek_scar":
			_stroke(image, [Vector2(CX + 17, 66), Vector2(CX + 13.5, 74)], _c("skin_shadow"), 1.0)
			_stroke(image, [Vector2(CX + 17.8, 66.5), Vector2(CX + 14.3, 74.5)], _c("skin_highlight"), 0.7)
		"beauty_spot":
			_disc(image, Vector2(CX + 10.5, 78.5), Vector2(1.0, 0.9), _c("skin_shadow").darkened(0.45))
		"vitiligo":
			for patch in [[Vector2(CX - 22, 38), Vector2(CX - 16, 36), Vector2(CX - 13, 41), Vector2(CX - 17, 47), Vector2(CX - 23, 48)], [Vector2(CX + 16, 77), Vector2(CX + 21, 75), Vector2(CX + 22, 82), Vector2(CX + 17, 88), Vector2(CX + 13, 84)]]:
				_fill(image, _within(_smooth(patch), _head), Color(_c("skin_rim"), 0.9))
		"dimples":
			for side in [-1.0, 1.0]:
				_stroke(image, [Vector2(CX + side * 10.5, MOUTH_Y - 2.5), Vector2(CX + side * 11.2, MOUTH_Y), Vector2(CX + side * 10.6, MOUTH_Y + 2.0)], Color(_c("skin_shadow"), 0.8), 0.9)
		"smile_lines":
			for side in [-1.0, 1.0]:
				_stroke(image, _smooth([Vector2(CX + side * 6.5, 72), Vector2(CX + side * 9.5, 76.5), Vector2(CX + side * 10.5, 82)], 3), Color(_c("skin_shadow"), 0.65), 0.9)


## The lower face from a row downwards, reaching `below` pixels past the chin.
func _jaw_region(from_y: float, below: float) -> PackedVector2Array:
	var s := _shape
	return _symmetric(_smooth([
		Vector2(0, MOUTH_Y - 4.0), Vector2(8.0, MOUTH_Y - 5.0), Vector2(s["cheek"] - 4.0, from_y - 1.0),
		Vector2(s["cheek"] + 0.5, from_y), Vector2(s["jaw"] + 0.8, s["jaw_y"]),
		Vector2(s["chin"] + 1.0, s["chin_y"] - 1.0 + below * 0.6), Vector2(0, s["chin_y"] + below),
	], 3))


func _facial_hair(image: Image) -> void:
	if _gender == "female":
		return
	var shadow := _c("hair_shadow")
	var base := _c("hair_base")
	var s := _shape
	var mustache := _symmetric(PackedVector2Array([Vector2(0, 77.6), Vector2(3.5, 76.8), Vector2(7.5, 78.6), Vector2(9.0, 80.6), Vector2(4.0, 79.6), Vector2(0, 79.2)]))
	match _traits["facial_hair"]:
		"stubble", "heavy_stubble":
			var heavy: bool = _traits["facial_hair"] == "heavy_stubble"
			var jaw := _within(_jaw_region(70.0, 2.5), _head)
			_fill(image, jaw, Color(shadow, 0.34 if heavy else 0.2))
			for y in range(71, int(s["chin_y"]), 2):
				for x in range(int(CX - s["jaw"]), int(CX + s["jaw"]) + 1, 2):
					var p := Vector2(x + (y % 4) * 0.5, y)
					for area: PackedVector2Array in jaw:
						if Geometry2D.is_point_in_polygon(p, area):
							_disc(image, p, Vector2(0.5, 0.6), Color(shadow, 0.55 if heavy else 0.35))
		"moustache":
			_mass(image, mustache, _contour(shadow), shadow, base, Vector2(-1.0, -0.8))
		"goatee":
			_mass(image, mustache, _contour(shadow), shadow, base, Vector2(-1.0, -0.8))
			var chin := _symmetric(PackedVector2Array([Vector2(0, MOUTH_Y + 4.2), Vector2(5.5, MOUTH_Y + 4.8), Vector2(6.5, s["chin_y"] - 3.0), Vector2(3.5, s["chin_y"] + 1.5), Vector2(0, s["chin_y"] + 2.2)]))
			_mass(image, chin, _contour(shadow), shadow, base, Vector2(-1.2, -1.0))
		"soul_patch":
			_mass(image, _symmetric(PackedVector2Array([Vector2(0, MOUTH_Y + 4.2), Vector2(2.2, MOUTH_Y + 4.6), Vector2(1.6, MOUTH_Y + 8.0), Vector2(0, MOUTH_Y + 8.8)])), _contour(shadow), shadow, base, Vector2(-0.8, -0.6))
		"short_beard", "full_beard":
			var full: bool = _traits["facial_hair"] == "full_beard"
			var clear := _symmetric(PackedVector2Array([Vector2(0, MOUTH_Y - 3.0), Vector2(8.0, MOUTH_Y - 1.5), Vector2(9.5, MOUTH_Y + 2.0), Vector2(5.0, MOUTH_Y + 4.5), Vector2(0, MOUTH_Y + 4.5)]))
			_mass(image, Geometry2D.clip_polygons(_jaw_region(69.0 if full else 72.0, 7.0 if full else 1.8), clear), _contour(shadow), shadow, base, Vector2(-2.0, -1.6))
			_mass(image, mustache, _contour(shadow), shadow, base, Vector2(-1.0, -0.8))
			for x in [-12.0, -6.0, 6.0, 12.0]:
				_stroke(image, [Vector2(CX + x, MOUTH_Y + 6.0), Vector2(CX + x * 1.05, MOUTH_Y + 11.0)], Color(_c("hair_highlight"), 0.55), 0.8)
		"chinstrap":
			var strap := PackedVector2Array()
			for p in _head:
				if p.y >= 66.0:
					strap.append(p + Vector2(0, -0.2))
			_stroke(image, strap, shadow, 3.4)
			_stroke(image, _moved(strap, Vector2(-0.4, -0.6)), Color(base, 0.7), 1.0)


# --- hair -----------------------------------------------------------------------

## An arc over the skull from temple to temple, closed along the hairline. `part`
## moves the hairline's top point sideways, `tips` notches locks into the
## hairline, `lumps` breaks the outer silhouette into tufts and `flare` widens
## the hair at the temples so it does not sit on the head like a dome.
func _cap(thickness: float, hairline: float, temple_y: float = 53.0, part := 0.0, tips := 0.0, lumps := 0.0, flare := 2.0) -> PackedVector2Array:
	var skull: float = _shape["skull"]
	var ry := SKULL_RY + thickness
	var start := asin(clampf((SKULL_Y - temple_y) / ry, -0.95, 0.95))
	var points := PackedVector2Array()
	for i in range(33):
		var angle := lerpf(start, PI - start, i / 32.0)
		var tuft := lumps * (0.5 + 0.5 * cos(angle * 14.0))
		points.append(Vector2(CX + cos(angle) * (skull + thickness + tuft + flare * cos(angle) * cos(angle)), SKULL_Y - sin(angle) * (ry + tuft)))
	var side := skull - 1.0
	var line := _smooth([Vector2(CX - side, temple_y), Vector2(CX - side * 0.8, hairline + 7.0), Vector2(CX - side * 0.45, hairline + 2.0), Vector2(CX + part, hairline), Vector2(CX + side * 0.45, hairline + 2.0), Vector2(CX + side * 0.8, hairline + 7.0), Vector2(CX + side, temple_y)], 3)
	for i in range(line.size()):
		var inside := absf(line[i].x - CX) < side * 0.8
		points.append(line[i] + Vector2(0, tips if inside and i % 2 == 1 else 0.0))
	return points


## Hair gets its dark contour only against the background; over the face it
## casts a soft shadow instead.
func _hair_mass(image: Image, points: PackedVector2Array, light := Vector2(-2.2, -2.0)) -> void:
	for grown: PackedVector2Array in _grow(points, 1.1):
		_fill(image, Geometry2D.clip_polygons(grown, _head), _contour(_c("hair_shadow")))
	for fallen: PackedVector2Array in Geometry2D.clip_polygons(_moved(points, Vector2(0.4, 1.8)), points):
		_fill(image, _within(fallen, _head), Color(_c("skin_shadow").darkened(0.2), 0.55))
	_fill(image, points, _c("hair_shadow"))
	_fill(image, _within(points, _moved(points, light)), _c("hair_base"))


func _strands(image: Image, lines: Array, width: float = 1.2) -> void:
	for line: Array in lines:
		_stroke(image, _smooth(line, 3), Color(_c("hair_highlight"), 0.85), width)


## A zigzag hairline edge from `left` to `right`, dipping `depth` on even points.
func _fringe(left: float, right: float, y: float, depth: float, points: int = 9) -> PackedVector2Array:
	var edge := PackedVector2Array()
	for i in range(points):
		var x := lerpf(left, right, float(i) / (points - 1))
		edge.append(Vector2(x, y + (depth if i % 2 == 0 else 0.0) - absf(x - CX) * 0.05))
	return edge


func _hair(front: Image, back: Image) -> void:
	var rx: float = _shape["skull"]
	var style: String = _traits["hair_style"]
	match style:
		"bald":
			return
		"buzz":
			_buzz(front, 36.0, 0.85)
		"crop":
			_hair_mass(front, _cap(3.5, 38.5, 53.0, 0.0, 2.4, 1.0))
			_strands(front, [[Vector2(CX - 14, 28), Vector2(CX - 4, 23), Vector2(CX + 8, 24)], [Vector2(CX - 18, 34), Vector2(CX - 10, 30)]])
		"undercut":
			_buzz(front, 38.0, 0.7)
			_hair_mass(front, _smooth([Vector2(CX - rx + 5.0, 39), Vector2(CX - rx + 4.0, 27), Vector2(CX - 10, 16), Vector2(CX + 6, 14), Vector2(CX + rx - 3.0, 21), Vector2(CX + rx - 1.0, 31), Vector2(CX + rx - 4.0, 41), Vector2(CX + 12, 39), Vector2(CX, 37.5), Vector2(CX - 12, 38.5)], 3))
			_strands(front, [[Vector2(CX - 14, 27), Vector2(CX - 2, 20), Vector2(CX + 14, 22)], [Vector2(CX - 8, 33), Vector2(CX + 6, 28), Vector2(CX + 18, 31)]])
		"side_part":
			_hair_mass(front, _cap(3.5, 37.0, 54.0, -9.0, 0.0, 0.6))
			_lock(front, [Vector2(CX - 9.0, 29), Vector2(CX + 6.0, 27.5), Vector2(CX + rx + 1.5, 35), Vector2(CX + rx + 1.0, 47), Vector2(CX + rx - 4.0, 44), Vector2(CX + 14.0, 42.5), Vector2(CX + 11.0, 40.5), Vector2(CX + 3.0, 40.5), Vector2(CX - 1.0, 39.0), Vector2(CX - 8.5, 37.5)])
			_stroke(front, [Vector2(CX - 9.0, 25), Vector2(CX - 9.5, 36.5)], Color(_c("hair_shadow"), 0.9), 1.1)
			_strands(front, [[Vector2(CX - 5, 31), Vector2(CX + 7, 32), Vector2(CX + 19, 38)], [Vector2(CX - 5, 25), Vector2(CX + 8, 24), Vector2(CX + 20, 29)], [Vector2(CX - 20, 33), Vector2(CX - 13, 26)]])
		"curls", "afro":
			var afro := style == "afro"
			if afro:
				_hair_mass(back, _ellipse(Vector2(CX, 40), Vector2(rx + 15.0, 33.0), 40))
			var outer := rx + (9.0 if afro else 5.0)
			var ring: Array = []
			for i in range(15):
				var angle := PI * (-0.12 + 1.24 * i / 14.0)
				ring.append(Vector2(CX + cos(angle) * outer, SKULL_Y - 2.0 - sin(angle) * (SKULL_RY + (6.0 if afro else 3.0))))
			var shapes: Array = [_cap(3.0, 38.0, 54.0)]
			for p: Vector2 in ring:
				shapes.append(_ellipse(p, Vector2(6.5, 6.0) if afro else Vector2(5.2, 5.0), 16))
			for i in range(7):
				shapes.append(_ellipse(Vector2(CX - rx * 0.75 + rx * 1.5 * i / 6.0, 38.5 + (i % 2) * 1.5), Vector2(4.2, 3.8), 14))
			_hair_mass(front, _union(shapes))
			for p: Vector2 in ring:
				_stroke(front, _arc(p + Vector2(-0.5, 0.5), Vector2(2.6, 2.4), PI * 0.3, PI * 0.95, 6), Color(_c("hair_highlight"), 0.8), 1.0)
		"braids":
			for side in [-1.0, 1.0]:
				for i in range(8):
					_hair_mass(back, _ellipse(Vector2(CX + side * (rx + 2.0 + i * 0.8), 58.0 + i * 7.0), Vector2(3.8, 4.4), 14), Vector2(-1.2, -1.2))
			_hair_mass(front, _cap(3.0, 37.0, 55.0))
			for x in [-15.0, -7.5, 0.0, 7.5, 15.0]:
				var row := [Vector2(CX + x * 1.2, 37.5), Vector2(CX + x * 1.05, 28), Vector2(CX + x * 0.7, 20)]
				_stroke(front, _smooth(row, 3), Color(_c("hair_shadow").darkened(0.3), 0.9), 1.2)
				_stroke(front, _moved(_smooth(row, 3), Vector2(-1.8, 0)), Color(_c("hair_highlight"), 0.6), 0.8)
		"locs":
			for side in [-1.0, 1.0]:
				for i in range(7):
					_hair_mass(back, _ellipse(Vector2(CX + side * (rx + 2.0 + i * 0.8), 58.0 + i * 7.0), Vector2(3.0, 5.0), 14), Vector2(-1.2, -1.2))
			_hair_mass(front, _cap(3.5, 37.0, 55.0, 0.0, 2.0, 1.2))
			for side in [-1.0, 1.0]:
				for offset in [0.0, 4.5]:
					var x: float = CX + side * (rx - 1.0 + offset)
					_lock(front, [Vector2(x - 2.4, 42), Vector2(x + 2.4, 42), Vector2(x + 2.6, 78 - offset * 2.0), Vector2(x, 82 - offset * 2.0), Vector2(x - 2.6, 78 - offset * 2.0)], Vector2(-1.0, -1.0))
		"ponytail":
			_hair_mass(back, _smooth([Vector2(CX + rx - 6.0, 30), Vector2(CX + rx + 6.0, 36), Vector2(CX + rx + 10.0, 58), Vector2(CX + rx + 7.0, 84), Vector2(CX + rx + 1.0, 98), Vector2(CX + rx + 1.0, 80), Vector2(CX + rx + 2.0, 58), Vector2(CX + rx - 2.0, 42)], 3))
			_strands(back, [[Vector2(CX + rx + 5.0, 44), Vector2(CX + rx + 6.5, 62), Vector2(CX + rx + 4.0, 82)]])
			_hair_mass(front, _cap(3.0, 37.0, 54.0, 0.0, 0.0, 0.4))
			_strands(front, [[Vector2(CX - 16, 30), Vector2(CX - 2, 23), Vector2(CX + 14, 25)]])
			_stroke(front, [Vector2(CX + rx - 1.5, 30.5), Vector2(CX + rx + 2.5, 35)], _c("accent"), 3.0)
		"top_knot":
			_hair_mass(front, _cap(2.5, 36.5, 54.0, 0.0, 0.0, 0.4))
			_hair_mass(front, _ellipse(Vector2(CX, 15), Vector2(10.0, 8.0), 24))
			_strands(front, [[Vector2(CX - 5, 12), Vector2(CX, 9), Vector2(CX + 5, 11)], [Vector2(CX - 16, 30), Vector2(CX - 4, 24), Vector2(CX + 12, 26)]])
			_stroke(front, [Vector2(CX - 7, 21.5), Vector2(CX + 7, 21.5)], _c("accent"), 2.2)
		"long", "wavy":
			var wavy := style == "wavy"
			var outline := _arc(Vector2(CX, SKULL_Y), Vector2(rx + 5.0, SKULL_RY + 5.0), -0.2, PI + 0.2, 20)
			var fall := PackedVector2Array()
			for p: Vector2 in [Vector2(-rx - 7.0, 64), Vector2(-rx - 6.0, 84), Vector2(-rx - 9.0, 104), Vector2(-rx - 2.0, 113), Vector2(-rx + 7.0, 112), Vector2(-rx + 5.0, 90), Vector2(-rx + 2.0, 62)]:
				fall.append(Vector2(CX + p.x + (sin(p.y * 0.35) * 2.0 if wavy else 0.0), p.y))
			outline.append_array(fall)
			outline.append_array(_mirror(fall))
			_hair_mass(back, outline)
			_strands(back, [[Vector2(CX - rx - 4.0, 92), Vector2(CX - rx - 4.5, 100), Vector2(CX - rx - 3.0, 108)], [Vector2(CX + rx + 4.0, 92), Vector2(CX + rx + 4.5, 100), Vector2(CX + rx + 3.0, 108)]], 1.4)
			_hair_mass(front, _cap(4.0, 36.0, 58.0, 0.0 if wavy else -8.0, 0.0, 0.8))
			_frame(front, rx, 100.0, wavy)
			_strands(front, [[Vector2(CX - 18, 32), Vector2(CX - 8, 25), Vector2(CX + 2, 24)], [Vector2(CX + 18, 32), Vector2(CX + 8, 25)]])
		"mohawk":
			_buzz(front, 38.0, 0.45)
			_hair_mass(front, PackedVector2Array([Vector2(CX - 6.0, 38), Vector2(CX - 7.5, 24), Vector2(CX - 5.5, 12), Vector2(CX - 2.0, 16), Vector2(CX, 5), Vector2(CX + 3.0, 14), Vector2(CX + 6.5, 8), Vector2(CX + 6.5, 22), Vector2(CX + 6.0, 38)]), Vector2(-1.6, -1.0))
			_strands(front, [[Vector2(CX - 3, 34), Vector2(CX - 3.5, 22), Vector2(CX - 1, 12)]], 1.0)
		"quiff":
			var lift := _smooth([Vector2(CX - rx + 4.0, 34), Vector2(CX - 14, 18), Vector2(CX - 2, 9), Vector2(CX + 12, 9), Vector2(CX + 20, 16), Vector2(CX + 18, 24), Vector2(CX + 8, 32), Vector2(CX - 6, 36)], 3)
			_hair_mass(front, _union([_cap(3.5, 37.0, 53.0, 0.0, 0.0, 0.8), lift]))
			_strands(front, [[Vector2(CX - 12, 26), Vector2(CX - 2, 14), Vector2(CX + 12, 12)], [Vector2(CX - 6, 30), Vector2(CX + 4, 20), Vector2(CX + 16, 19)]])
		"curtains":
			_hair_mass(front, _cap(3.5, 32.0, 54.0, 0.0, 0.0, 0.6))
			for side in [-1.0, 1.0]:
				_lock(front, [Vector2(CX + side * 0.5, 27), Vector2(CX + side * 12.0, 29), Vector2(CX + side * (rx + 1.5), 38), Vector2(CX + side * (rx + 1.0), 51), Vector2(CX + side * (rx - 3.5), 46), Vector2(CX + side * 10.0, 39.5), Vector2(CX + side * 2.5, 34.5)])
			_strands(front, [[Vector2(CX - 3, 30), Vector2(CX - 12, 33), Vector2(CX - 21, 40)], [Vector2(CX + 3, 30), Vector2(CX + 12, 33), Vector2(CX + 21, 40)]])
		"bob":
			_hair_mass(back, _smooth([Vector2(CX, 17), Vector2(CX + rx + 4.0, 30), Vector2(CX + rx + 6.0, 56), Vector2(CX + rx + 5.0, 84), Vector2(CX + rx - 2.0, 90), Vector2(CX + rx - 3.0, 60), Vector2(CX - rx + 3.0, 60), Vector2(CX - rx + 2.0, 90), Vector2(CX - rx - 5.0, 84), Vector2(CX - rx - 6.0, 56), Vector2(CX - rx - 4.0, 30)], 3))
			var fringe := _fringe(CX - rx + 2.0, CX + rx - 2.0, 43.3, 1.2)
			_hair_mass(front, _union([_cap(4.0, 40.0, 58.0), _band(_moved(fringe, Vector2(0, -10)), fringe)]))
			_frame(front, rx, 88.0, false)
			_strands(front, [[Vector2(CX - 18, 32), Vector2(CX - 4, 25), Vector2(CX + 12, 27)], [Vector2(CX - 8, 36), Vector2(CX - 6, 43)], [Vector2(CX + 6, 36), Vector2(CX + 7, 43)]])
		"pixie":
			var sweep := _smooth([Vector2(CX - 12, 34), Vector2(CX + 2, 40), Vector2(CX + 12, 44), Vector2(CX + 20, 44.5), Vector2(CX + 16, 38), Vector2(CX + 4, 31)], 3)
			_hair_mass(front, _union([_cap(3.0, 37.0, 56.0, 0.0, 1.8, 1.0), sweep]))
			_strands(front, [[Vector2(CX - 14, 30), Vector2(CX, 25), Vector2(CX + 14, 28)], [Vector2(CX - 6, 36), Vector2(CX + 6, 39), Vector2(CX + 16, 42)]])
		"slick_back":
			_hair_mass(front, _cap(3.0, 33.5, 52.0))
			for x in [-14.0, -7.0, 0.0, 7.0, 14.0]:
				_stroke(front, [Vector2(CX + x, 35), Vector2(CX + x * 0.85, 27), Vector2(CX + x * 0.6, 20)], Color(_c("hair_highlight"), 0.7), 1.0)
		"messy_crop":
			_hair_mass(front, _cap(4.0, 38.5, 53.0, 0.0, 2.8, 2.6))
			_strands(front, [[Vector2(CX - 14, 30), Vector2(CX - 6, 22)], [Vector2(CX, 30), Vector2(CX + 4, 20)], [Vector2(CX + 12, 32), Vector2(CX + 18, 24)]])


## Close-cropped hair: a thin cap with a stipple of shadow.
func _buzz(image: Image, hairline: float, strength: float) -> void:
	var rx: float = _shape["skull"]
	var cap := _cap(0.8, hairline, 52.0)
	_fill(image, cap, Color(_c("hair_base"), strength))
	for y in range(24, 50, 3):
		for x in range(int(CX - rx) + 2, int(CX + rx) - 1, 3):
			var p := Vector2(x + (y % 2) * 1.5, y)
			if Geometry2D.is_point_in_polygon(p, cap):
				_disc(image, p, Vector2(0.55, 0.55), Color(_c("hair_shadow"), 0.6 * strength))


## A separate lock laid over the cap, so layers read through their cast shadow.
func _lock(image: Image, points: Array, light := Vector2(-1.6, -1.4)) -> void:
	_hair_mass(image, _smooth(points + [points[0]], 3), light)


## Side hair falling in front of the ears down to `bottom`, framing the face.
func _frame(image: Image, rx: float, bottom: float, wavy: bool) -> void:
	for side in [-1.0, 1.0]:
		var points := []
		for p: Vector2 in [Vector2(rx - 5.0, 40), Vector2(rx + 4.0, 44), Vector2(rx + 5.0, 68), Vector2(rx + 4.0, bottom - 7.0), Vector2(rx + 1.5, bottom), Vector2(rx - 1.5, bottom - 9.0), Vector2(rx - 2.5, 68), Vector2(rx - 4.0, 52)]:
			points.append(Vector2(CX + side * (p.x + (sin(p.y * 0.3) * 2.5 if wavy else 0.0)), p.y))
		_lock(image, points, Vector2(-1.2, -1.0))


# --- accessories ----------------------------------------------------------------

func _accessory(image: Image) -> void:
	var metal := _c("metal")
	var frame := metal.darkened(0.35)
	var spacing: float = EYE_STYLES[_traits["eye_style"]]["spacing"]
	var ear_x: float = _shape["temple"] + 1.2
	match _traits["accessory"]:
		"glasses":
			for side in [-1.0, 1.0]:
				var x: float = CX + side * spacing
				_stroke(image, [Vector2(x - 7.5, 55.5), Vector2(x + 7.5, 55.5), Vector2(x + 7.0, 64.5), Vector2(x - 7.0, 64.5), Vector2(x - 7.5, 55.5)], frame, 1.3)
				_stroke(image, [Vector2(CX + side * (spacing + 7.5), 57), Vector2(CX + side * ear_x, 58)], frame, 1.1)
			_stroke(image, [Vector2(CX - spacing + 7.5, 58), Vector2(CX, 57), Vector2(CX + spacing - 7.5, 58)], frame, 1.1)
		"round_glasses":
			for side in [-1.0, 1.0]:
				var ring := _ellipse(Vector2(CX + side * spacing, EYE_Y), Vector2(7.0, 6.2), 28)
				ring.append(ring[0])
				_stroke(image, ring, metal, 1.1)
				_stroke(image, [Vector2(CX + side * (spacing + 7.0), 58.5), Vector2(CX + side * ear_x, 59)], metal, 1.0)
			_stroke(image, [Vector2(CX - spacing + 7.0, 58.5), Vector2(CX, 57.5), Vector2(CX + spacing - 7.0, 58.5)], metal, 1.0)
		"aviators":
			for side in [-1.0, 1.0]:
				var x: float = CX + side * spacing
				var lens := _smooth([Vector2(x - side * 7.5, 55.0), Vector2(x + side * 7.5, 55.0), Vector2(x + side * 7.0, 61.0), Vector2(x + side * 2.0, 66.5), Vector2(x - side * 5.0, 64.0), Vector2(x - side * 7.5, 59.0), Vector2(x - side * 7.5, 55.0)], 3)
				_fill(image, lens, Color(_c("outline").lerp(_c("accent"), 0.25), 0.35))
				_stroke(image, lens, metal, 1.0)
				_stroke(image, [Vector2(x - side * 4.5, 57.0), Vector2(x - side * 1.5, 56.5)], Color(_c("eye_white"), 0.6), 0.8)
			_stroke(image, [Vector2(CX - spacing + 7.5, 56), Vector2(CX + spacing - 7.5, 56)], metal, 1.0)
		"earring":
			var hoop := _ellipse(Vector2(CX + ear_x + 0.5, 73.5), Vector2(2.3, 2.6), 16)
			hoop.append(hoop[0])
			_stroke(image, hoop, metal.lerp(_c("accent_light"), 0.3), 1.1)
		"stud":
			_disc(image, Vector2(CX + ear_x + 0.3, 70.5), Vector2(1.3, 1.3), metal)
			_disc(image, Vector2(CX + ear_x, 70.1), Vector2(0.5, 0.5), _c("eye_white"))
		"headband":
			var band := _arc(Vector2(CX, SKULL_Y + 6.0), Vector2(_shape["skull"] + 2.5, SKULL_RY + 1.0), 0.45, PI - 0.45, 18)
			_stroke(image, band, _c("accent"), 3.4)
			_stroke(image, _moved(band, Vector2(0, -0.9)), _c("accent_light"), 0.9)
		"hair_clip":
			_stroke(image, [Vector2(CX - 20.0, 36.0), Vector2(CX - 13.0, 33.0)], metal, 2.4)
			_stroke(image, [Vector2(CX - 19.0, 35.0), Vector2(CX - 14.0, 33.0)], _c("accent_light"), 1.2)
