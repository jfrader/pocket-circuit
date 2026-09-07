extends RefCounted

const SIZE := Vector2i(96, 128)
const INK := Color("102532")
const DEEP := Color("16425b")
const SHADE := Color("1b5980")
const PAINT := Color("247da7")
const LIGHT := Color("309cc4")
const EDGE := Color("6cc3da")
const GLASS := Color("15243b")
const GLASS_LIGHT := Color("253957")
const IVORY := Color("dbe9dc")

var outside_writes := 0
var _type := "coupe"
var _parts: Dictionary = {}
var _colors: Dictionary = {}
var _cabin := false
var _accent := Color("e7ba65")


func render(payload: Dictionary, spin: int = 0, steer: float = 0.0) -> Dictionary:
	_type = payload["type"]
	_parts = payload["parts"]
	var p: Dictionary = payload["palette"]
	var mid := Color(p["body_mid"])
	var light := Color(p["body_light"])
	var dark := Color(p["body_dark"])
	_accent = Color(p["accent"])
	_colors = {
		INK: Color(p["outline"]), DEEP: dark.darkened(0.17), SHADE: dark,
		PAINT: mid, LIGHT: mid.lerp(light, 0.65), EDGE: light.lerp(Color.WHITE, 0.25),
		GLASS: Color(p["glass_dark"]), GLASS_LIGHT: Color(p["glass_dark"]).lerp(Color(p["glass_mid"]), 0.55),
		Color("288ab3"): mid.lerp(light, 0.25), Color("48accd"): light,
		IVORY: Color(p["headlight"]), Color("f4f3df"): Color(p["headlight"]).lightened(0.12),
		Color("a7cbd0"): Color(p["trim"]), Color("db764f"): _accent,
		Color("bf4945"): Color(p["taillight"]), Color("ff8666"): Color(p["taillight"]).lightened(0.35),
	}
	outside_writes = 0
	_cabin = false
	var layers := _render(posmod(spin, 4), clampf(steer, -24.0, 24.0))
	if outside_writes != 0:
		push_error("Native car art exceeded canvas: %d writes" % outside_writes)
	return layers


func _point(x: float, y: float) -> Vector2:
	var px := x
	var py := y
	if _cabin:
		var cabin: String = _parts.get("cabin", "angular")
		var width: float = {"bubble": 0.94, "angular": 1.0, "panoramic": 1.10, "low": 0.85, "notched": 0.92, "fastback": 1.04, "cage": 1.0}[cabin]
		px = 47.5 + (px - 47.5) * width
		if cabin == "fastback" and py >= 67:
			py = 67 + (py - 67) * 1.10
		elif cabin == "low":
			py = 75 + (py - 75) * 0.85
		elif cabin == "bubble":
			py -= 3
		elif cabin == "notched" and py > 88:
			py -= 4
	if _type == "compact":
		px = 47.5 + (px - 47.5) * 1.06
		py = 14 + (py - 8) * 0.7 if py < 48 else (42 + (py - 48) * 1.05 if py < 104 else 101 + (py - 104) * 0.75)
	elif _type == "muscle":
		px = 47.5 + (px - 47.5) * 1.20
		if y < 22 or y > 108:
			px += signf(px - 47.5) * 3
		py = 10 + (py - 8) * 1.12 if py < 48 else 55 + (py - 48) * 0.85
	return Vector2(roundf(px), roundf(py))


func _blank() -> Image:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return image


func wheel_tiles(payload: Dictionary) -> Array[Image]:
	render(payload)
	var frames: Array[Image] = []
	for spin in range(4):
		var tile := _blank()
		_wheel(tile, Vector2(47,64), 0.0, spin)
		frames.append(tile.get_region(Rect2i(41,52,13,25)))
	return frames


func _pixel(image: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		outside_writes += 1
		return
	image.set_pixel(x, y, _colors.get(color, color))


func _line(image: Image, points: Array, color: Color) -> void:
	for i in range(points.size() - 1):
		var a := _point(points[i][0], points[i][1])
		var b := _point(points[i + 1][0], points[i + 1][1])
		var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
		for j in range(steps + 1):
			var p := a.lerp(b, float(j) / float(maxi(steps, 1)))
			_pixel(image, roundi(p.x), roundi(p.y), color)


func _poly(image: Image, points: Array, color: Color) -> void:
	var polygon := PackedVector2Array()
	var bounds := Rect2(_point(points[0][0], points[0][1]), Vector2.ZERO)
	for point in points:
		var p := _point(point[0], point[1])
		polygon.append(p)
		bounds = bounds.expand(p)
	for y in range(int(bounds.position.y), int(bounds.end.y) + 1):
		for x in range(int(bounds.position.x), int(bounds.end.x) + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x, y), polygon):
				_pixel(image, x, y, color)
	var closed := points.duplicate()
	closed.append(points[0])
	_line(image, closed, color)


func _rect(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	_poly(image, [[x,y],[x+width-1,y],[x+width-1,y+height-1],[x,y+height-1]], color)


func _render(spin: int = 0, steer: float = 0.0) -> Dictionary:
	if _type == "buggy":
		return _buggy(spin, steer)
	var wheels := _blank()
	for cx in [22, 73]:
		for cy in [36, 98]:
			_wheel(wheels, _point(cx, cy), deg_to_rad(steer) if cy == 36 else 0.0, spin)

	var body := _blank()
	_poly(body, [[37,8],[58,8],[64,11],[69,18],[72,27],[72,41],[70,51],[70,86],[72,92],[72,107],[69,113],[64,116],[31,116],[26,113],[23,107],[23,92],[25,86],[25,51],[23,41],[23,27],[26,18],[31,11]], INK)
	_poly(body, [[37,9],[58,9],[63,12],[68,19],[71,27],[71,41],[69,51],[69,87],[71,93],[71,106],[68,112],[63,115],[32,115],[27,112],[24,106],[24,93],[26,87],[26,51],[24,41],[24,27],[27,19],[32,12]], SHADE)
	_poly(body, [[37,10],[57,10],[62,13],[66,20],[68,29],[68,41],[66,52],[66,86],[68,94],[68,105],[65,110],[61,112],[33,112],[28,107],[27,94],[29,86],[29,51],[27,40],[27,27],[30,19],[34,13]], PAINT)
	_poly(body, [[37,10],[57,10],[62,13],[64,17],[32,17],[34,13]], LIGHT)
	_poly(body, [[29,21],[32,18],[30,32],[31,44],[28,49],[26,40],[26,29]], LIGHT)
	_line(body, [[36,10],[32,13],[28,20],[25,29],[25,40]], EDGE)
	_line(body, [[27,53],[27,85]], EDGE)
	_line(body, [[29,54],[29,84]], LIGHT)
	_line(body, [[68,54],[68,86]], DEEP)
	_poly(body, [[27,90],[30,87],[31,101],[34,109],[30,109],[26,104],[26,95]], LIGHT)
	_line(body, [[25,94],[25,105],[28,111],[33,113]], EDGE)
	_line(body, [[70,94],[70,107],[67,112],[63,114]], DEEP)

	# The hood is its own inset panel, not a gradient across the entire car.
	_poly(body, [[36,18],[59,18],[63,23],[65,42],[61,47],[34,47],[30,42],[32,24]], SHADE)
	_poly(body, [[36,19],[58,19],[61,23],[63,41],[60,45],[35,45],[32,41],[34,24]], PAINT)
	_line(body, [[36,19],[34,24],[32,41]], LIGHT)
	_line(body, [[36,20],[35,26],[35,39]], Color("288ab3"))
	_rect(body, 46, 14, 2, 3, Color("db764f"))
	_line(body, [[35,46],[60,46]], DEEP)

	var glass := _blank()
	_cabin = true
	_poly(glass, [[35,48],[60,48],[67,53],[62,65],[60,67],[35,67],[33,65],[28,53]], INK)
	_poly(glass, [[36,49],[59,49],[65,54],[60,65],[35,65],[30,54]], GLASS)
	_poly(glass, [[36,49],[59,49],[65,54],[63,57],[32,60],[30,54]], GLASS_LIGHT)
	_line(glass, [[35,49],[30,54],[34,63]], Color("54758b"))
	_line(glass, [[38,50],[56,50]], Color("354e6a"))
	_line(glass, [[37,64],[57,64]], Color("1b2b43"))

	# Side glazing and pillars distinguish the cabin from a painted rectangle.
	_poly(glass, [[28,59],[33,67],[33,84],[29,90],[27,87]], INK)
	_poly(glass, [[28,65],[31,68],[31,80],[28,80]], GLASS_LIGHT)
	_poly(glass, [[28,82],[31,82],[31,85],[28,87]], GLASS)
	_poly(glass, [[67,59],[62,67],[62,84],[66,90],[68,87]], INK)
	_poly(glass, [[67,65],[64,68],[64,80],[67,80]], GLASS)
	_poly(glass, [[67,82],[64,82],[64,85],[67,87]], GLASS_LIGHT)
	_line(body, [[34,67],[34,85],[31,91]], EDGE)
	_line(body, [[61,67],[61,85],[64,91]], LIGHT)
	_poly(body, [[36,67],[59,67],[59,84],[56,87],[39,87],[36,84]], LIGHT)
	_poly(body, [[37,69],[58,69],[58,84],[55,86],[39,86],[37,83]], PAINT)
	_line(body, [[38,68],[56,68]], EDGE)
	_line(body, [[37,70],[37,81]], Color("48accd"))
	_poly(glass, [[35,89],[60,89],[64,93],[63,102],[60,104],[35,104],[32,102],[31,93]], INK)
	_poly(glass, [[36,90],[59,90],[62,93],[61,101],[59,102],[36,102],[34,100],[33,94]], GLASS)
	_poly(glass, [[36,90],[59,90],[62,93],[61,97],[34,95],[33,94]], GLASS_LIGHT)
	_line(glass, [[36,90],[34,93],[34,99]], Color("54758b"))
	_cabin = false
	_line(body, [[34,105],[61,105]], DEEP)
	_line(body, [[35,106],[60,106]], LIGHT)

	var trim := _blank()
	for right in [false, true]:
		var x := 62 if right else 28
		_poly(trim, [[x,17],[x+4,18],[x+4,23],[x-1,22]], INK)
		_rect(trim, x, 18, 3, 3, IVORY)
		_rect(trim, x, 18, 2, 1, Color("fff9e7"))
		_rect(trim, x, 22, 3, 1, Color("cc9153"))
		var mx := 70 if right else 20
		_rect(trim, mx, 58, 6, 2, INK)
		_rect(trim, mx+1, 56, 4, 3, DEEP)
		_rect(trim, mx+1, 56, 4, 1, LIGHT)
		_rect(trim, 67 if right else 25, 79, 2, 4, DEEP)
		_rect(trim, 67 if right else 25, 79, 1, 3, Color("9ab5bf"))
		var tx := 62 if right else 28
		_rect(trim, tx, 109, 6, 4, INK)
		_rect(trim, tx+1, 110, 4, 2, Color("bf4945"))
		_rect(trim, tx+1, 110, 3, 1, Color("ff8666"))
	_rect(trim, 40, 12, 15, 2, INK)
	_line(trim, [[39,15],[56,15]], LIGHT)
	_rect(trim, 39, 113, 17, 2, INK)
	_rect(trim, 44, 113, 7, 1, Color("94acb2"))
	_rect(trim, 31, 114, 7, 1, DEEP)
	_rect(trim, 57, 114, 7, 1, DEEP)

	_livery(body)
	_hood(trim)
	_accessories(trim)
	if _parts["cabin"] == "cage":
		_roll_cage(glass)
	return _composite(body, glass, wheels, trim)


func _composite(body: Image, glass: Image, wheels: Image, trim: Image) -> Dictionary:
	var shadow := _blank()
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if body.get_pixel(x, y).a > 0 or wheels.get_pixel(x, y).a > 0 or trim.get_pixel(x, y).a > 0:
				_pixel(shadow, x+1, y+2, Color(0.035,0.055,0.07,0.35))
	var car := _blank()
	for layer in [shadow, wheels, body, glass, trim]:
		car.blend_rect(layer, Rect2i(Vector2i.ZERO, SIZE), Vector2i.ZERO)
	return {"car": car, "body": body, "glass": glass, "wheels": wheels, "trim": trim}


func _wheel(image: Image, center: Vector2, angle: float, spin: int) -> void:
	var style: String = _parts.get("wheels", "classic")
	var half_width := 6 if _type == "buggy" else (5 if _type == "muscle" else 4)
	var half_height := 12 if _type == "buggy" else 10
	# Inverse sampling rotates one local tyre around a fixed axle without holes.
	for dy in range(-15, 16):
		for dx in range(-15, 16):
			var p := Vector2(dx, dy).rotated(-angle)
			var u := roundi(p.x)
			var v := roundi(p.y)
			if abs(u) > half_width or abs(v) > half_height or (abs(u) == half_width and abs(v) >= half_height-1):
				continue
			var color := Color("111a22")
			if abs(u) < half_width and abs(v) < half_height-1:
				color = Color("29333c")
			if abs(u) == half_width-1 and posmod(v + spin, 4) == 0:
				color = Color("48535c")
			if abs(u) <= 1 and abs(v) <= 5:
				color = Color("384b58")
			if u == -1 and abs(v) <= 4:
				color = Color("8fa5af")
			if abs(u) <= 2 and abs(v) <= 6:
				match style:
					"mesh":
						color = Color("7b8d98") if posmod(u+v, 2) == 0 else Color("253341")
					"rugged":
						color = Color("384b58") if abs(v) < 4 else Color("111a22")
					"spoke":
						color = Color("a2b8c2") if posmod(v, 3) == 0 else Color("263743")
					"disc":
						color = Color("718995") if u <= 0 else Color("4b6271")
					"open":
						color = Color("111a22") if abs(v) < 4 else Color("7b8d98")
					"beadlock":
						color = Color("b3b1a0") if abs(v) >= 5 or abs(u) == 2 else Color("283741")
			_pixel(image, int(center.x)+dx, int(center.y)+dy, color)


func _livery(body: Image) -> void:
	var paint := _blank()
	var style: String = _parts["livery"]
	match style:
		"center_stripe":
			_rect(paint, 43, 9, 8, 108, IVORY)
			_rect(paint, 44, 9, 1, 108, Color("f4f3df"))
		"twin_stripe":
			_rect(paint, 39, 9, 5, 108, _accent)
			_rect(paint, 51, 9, 5, 108, _accent)
		"side_flash":
			_poly(paint, [[24,25],[32,35],[31,57],[27,90],[23,98]], _accent)
			_poly(paint, [[71,25],[63,35],[64,57],[68,90],[72,98]], _accent)
		"checker":
			for y in range(22, 39, 4):
				for x in range(29, 67, 4):
					if (x/4 + y/4) % 2 == 0:
						_rect(paint, x, y, 4, 4, IVORY)
		"sunburst":
			for x in range(24, 74, 10):
				_poly(paint, [[47,45],[x,12],[x+4,12]], _accent)
		"hood_stripe":
			_rect(paint, 43, 17, 8, 27, _accent)
		"side_swoosh":
			_poly(paint, [[24,26],[31,51],[35,79],[28,104],[29,77],[26,55]], _accent)
			_poly(paint, [[71,26],[64,51],[60,79],[67,104],[66,77],[69,55]], _accent)
		"two_tone":
			_rect(paint, 20, 8, 23, 39, _accent)
			_rect(paint, 20, 103, 23, 14, _accent)
		"racing_stripe":
			_rect(paint, 36, 9, 6, 108, IVORY)
			_rect(paint, 33, 9, 1, 108, _accent)
		"dust_kick":
			for side in [23, 62]:
				for y in range(86, 114, 6):
					_poly(paint, [[side,y+3],[side+9,y],[side+9,y+2],[side,y+5]], _accent)
		"hash_marks":
			for y in [24, 32, 40]:
				_poly(paint, [[25,y],[37,y+5],[37,y+8],[25,y+3]], _accent)
	# Clip graphics to painted surfaces; glass and hardware are composited later.
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var c := body.get_pixel(x, y)
			if c.a == 0 or c == _colors[INK] or c == _colors[DEEP]:
				continue
			var graphic := paint.get_pixel(x, y)
			if graphic.a > 0:
				if c == _colors[SHADE]:
					graphic = graphic.darkened(0.20)
				body.set_pixel(x, y, graphic)


func _hood(trim: Image) -> void:
	match _parts["hood"]:
		"smooth":
			pass
		"flat":
			_line(trim, [[34,39],[61,39]], SHADE)
			_line(trim, [[35,40],[60,40]], LIGHT)
		"twin_vents":
			for x in [34, 58]:
				for y in range(29, 40, 3):
					_rect(trim, x, y, 4, 1, DEEP)
					_rect(trim, x, y+1, 4, 1, LIGHT)
		"power_scoop":
			_poly(trim, [[40,25],[55,25],[57,39],[38,39]], DEEP)
			_poly(trim, [[41,26],[54,26],[55,36],[40,36]], LIGHT)
			_rect(trim, 42, 28, 11, 4, INK)
			_line(trim, [[41,26],[54,26]], EDGE)
			_line(trim, [[41,37],[54,37]], PAINT)
		"dual_scoop":
			for x in [35, 52]:
				_poly(trim, [[x,26],[x+8,26],[x+9,39],[x-1,39]], DEEP)
				_rect(trim, x+1, 27, 6, 8, LIGHT)
				_rect(trim, x+1, 28, 6, 3, INK)
		"ridged":
			for x in [36, 41, 46, 51, 56]:
				_line(trim, [[x,25],[x,41]], SHADE)
				_line(trim, [[x+1,25],[x+1,41]], LIGHT)


func _accessories(trim: Image) -> void:
	var bumper: String = _parts["bumpers"]
	for y in [10, 115]:
		match bumper:
			"chrome":
				_rect(trim, 31, y, 33, 3, INK)
				_rect(trim, 32, y, 31, 1, Color("b9cbd0"))
				_rect(trim, 34, y+1, 27, 1, Color("728d99"))
			"sport":
				_rect(trim, 34, y, 27, 2, DEEP)
				_rect(trim, 36, y, 23, 1, _accent)
			"utility":
				_rect(trim, 29, y, 37, 3, INK)
				_rect(trim, 30, y, 35, 1, Color("6b7778"))
				_rect(trim, 35, y-1, 3, 5, Color("344451"))
				_rect(trim, 57, y-1, 3, 5, Color("344451"))
			"slim":
				_rect(trim, 36, y+1, 23, 1, INK)
			"wide":
				_rect(trim, 26, y, 43, 3, DEEP)
				_rect(trim, 27, y, 41, 1, LIGHT)
			"pipe":
				_rect(trim, 30, y, 35, 2, Color("667d86"))
				_rect(trim, 34, y+2 if y == 10 else y-2, 2, 2, INK)
				_rect(trim, 59, y+2 if y == 10 else y-2, 2, 2, INK)
	var spoiler: String = _parts["spoiler"]
	if spoiler == "none":
		return
	if spoiler == "lip":
		_rect(trim, 31, 108, 33, 3, DEEP)
		_rect(trim, 32, 108, 31, 1, LIGHT)
		return
	var y: int = {"wing": 108, "tall": 104, "winged": 106, "hoop": 108}[spoiler]
	_rect(trim, 35, y+2, 3, 8, INK)
	_rect(trim, 57, y+2, 3, 8, INK)
	_rect(trim, 27, y, 41, 4, INK)
	_rect(trim, 28, y, 39, 2, LIGHT if spoiler != "hoop" else Color("8fa5af"))
	if spoiler == "winged":
		_rect(trim, 26, y-2, 3, 8, DEEP)
		_rect(trim, 66, y-2, 3, 8, DEEP)


func _roll_cage(glass: Image) -> void:
	glass.fill(Color.TRANSPARENT)
	_poly(glass, [[34,51],[61,51],[64,88],[60,99],[35,99],[31,88]], INK)
	_poly(glass, [[36,53],[59,53],[61,88],[57,96],[38,96],[34,88]], GLASS)
	for x in [36, 51]:
		_rect(glass, x, 71, 9, 17, Color("354553"))
		_rect(glass, x+1, 71, 7, 4, Color("64747d"))
		_rect(glass, x+2, 78, 5, 7, Color("253341"))
	for x in [33, 60]:
		_rect(glass, x, 53, 3, 43, Color("647986"))
		_rect(glass, x, 53, 1, 43, Color("a7b9bc"))
	for y in [55, 91]:
		_rect(glass, 33, y, 30, 3, Color("647986"))
		_rect(glass, 33, y, 30, 1, Color("a7b9bc"))
	_line(glass, [[36,57],[59,90]], Color("718690"))
	_line(glass, [[59,57],[36,90]], Color("718690"))


func _buggy(spin: int, steer: float) -> Dictionary:
	var wheels := _blank()
	for x in [15, 80]:
		for y in [36, 98]:
			_wheel(wheels, Vector2(x,y), deg_to_rad(steer) if y == 36 else 0.0, spin)
	var body := _blank()
	for y in [36, 98]:
		_rect(body, 17, y-2, 62, 5, INK)
		_rect(body, 18, y-2, 60, 1, Color("7a8e94"))
		for x in [22, 67]:
			_poly(body, [[x,y-5],[x+6,y-8],[x+6,y+7],[x,y+3]], DEEP)
			_line(body, [[x+1,y-4],[x+5,y-6]], Color("9bacaf"))
	_poly(body, [[34,13],[61,13],[66,20],[67,43],[63,51],[65,87],[69,95],[67,112],[60,117],[35,117],[28,112],[26,95],[30,87],[32,51],[28,43],[29,20]], INK)
	_poly(body, [[35,15],[60,15],[64,21],[65,43],[60,51],[62,89],[67,96],[65,111],[59,115],[36,115],[30,110],[29,96],[33,89],[35,51],[30,43],[31,21]], SHADE)
	_poly(body, [[36,16],[59,16],[62,23],[61,44],[56,48],[38,48],[32,42],[33,23]], PAINT)
	_line(body, [[35,18],[32,24],[32,41],[38,47]], EDGE)
	_line(body, [[37,21],[58,21],[59,40]], LIGHT)
	_poly(body, [[34,93],[61,93],[65,100],[63,110],[59,113],[36,113],[32,108]], PAINT)
	_line(body, [[33,98],[33,108],[37,111]], LIGHT)
	for x in [30, 62]:
		_rect(body, x, 53, 4, 36, PAINT)
		_rect(body, x, 54, 1, 33, EDGE)
	_livery(body)
	var glass := _blank()
	_roll_cage(glass)
	# Cabin IDs alter real roof/cage hardware without closing the off-road chassis.
	match _parts["cabin"]:
		"bubble":
			_poly(glass, [[35,52],[60,52],[61,64],[34,64]], GLASS_LIGHT)
		"angular":
			_rect(glass, 34, 52, 28, 9, PAINT)
			_rect(glass, 34, 52, 28, 1, EDGE)
		"panoramic":
			_rect(glass, 37, 59, 21, 12, GLASS_LIGHT)
		"low":
			_rect(glass, 36, 57, 24, 3, _accent)
		"notched":
			_rect(glass, 34, 52, 9, 12, PAINT)
			_rect(glass, 53, 52, 9, 12, PAINT)
		"fastback":
			_poly(glass, [[34,53],[61,53],[57,72],[38,72]], PAINT)
			_line(glass, [[35,54],[60,54]], EDGE)
	var trim := _blank()
	_hood(trim)
	for x in [30, 60]:
		_rect(trim, x, 18, 6, 5, INK)
		_rect(trim, x+1, 19, 4, 3, IVORY)
		_rect(trim, x, 109, 5, 3, Color("bf4945"))
		_rect(trim, x, 109, 5, 1, Color("ff8666"))
	_accessories(trim)
	return _composite(body, glass, wheels, trim)
