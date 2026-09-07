extends RefCounted
const SIZE := 128
const INK := Color("302b36")
const SKIN_DARK := Color("9a5e54")
const SKIN_SHADE := Color("c38366")
const SKIN := Color("e4a580")
const SKIN_LIGHT := Color("f0bc93")
const SKIN_EDGE := Color("f7d1a5")
const HAIR_DARK := Color("38242d")
const HAIR := Color("754036")
const HAIR_LIGHT := Color("aa6248")
const HAIR_EDGE := Color("cd9362")
var escaped_pixels := 0
var _traits: Dictionary
var _palette: Dictionary
var _colors: Dictionary
var _zone := "clothing"
var _gender := "legacy"


func render(payload: Dictionary, apply_facing: bool = true) -> Dictionary:
	_traits = payload["traits"]
	_gender = _traits.get("gender", "legacy")
	_palette = payload["palette"]
	_colors = {}
	escaped_pixels = 0
	_map_colors([INK], Color("11151c"), Color(_palette["outline"]))
	_map_colors([SKIN_DARK], Color("b97858"), Color(_palette["skin_shadow"]))
	_map_colors([SKIN_SHADE,Color("c18a70"),Color("b87860"),Color("cf8d70"),Color("a66a58"),Color("b97762")], Color("b97858"), Color(_palette["skin_shadow"]))
	_map_colors([SKIN,Color("d69777"),Color("d89375"),Color("c58b70")], Color("e9ae84"), Color(_palette["skin_base"]))
	_map_colors([SKIN_LIGHT,Color("ebb18b"),Color("f0b698")], Color("ffd0a7"), Color(_palette["skin_highlight"]))
	_map_colors([SKIN_EDGE], Color("ffe2c2"), Color(_palette["skin_rim"]))
	_map_hair([HAIR_DARK,Color("5b3233"),Color("563333")], Color("3b1814"), Color(_palette["hair_shadow"]))
	_map_hair([HAIR,Color("94503d")], Color("74321f"), Color(_palette["hair_base"]))
	_map_hair([HAIR_LIGHT,HAIR_EDGE,Color("ad7051"),Color("d5a373"),Color("b47750")], Color("b15f35"), Color(_palette["hair_highlight"]))
	_map_colors([Color("527783")], Color("3c5262"), Color(_palette["iris"]))
	_map_colors([Color("f2dfbd"),Color("ead6b7")], Color("f5f0e8"), Color(_palette["eye_white"]))
	_map_colors([Color("253b48")], Color("17212a"), Color(_palette["eye_dark"]))
	_colors[Color("fff0d1")] = Color(_palette["eye_white"]).lerp(Color(_palette["iris_light"]),0.18)
	_map_colors([Color("b86f63"),Color("784a48")], Color("783f49"), Color(_palette["mouth"]))
	_map_colors([Color("1d424c"),Color("173e49"),Color("183c47")], Color("292733"), Color(_palette["outfit_shadow"]))
	_map_colors([Color("306774"),Color("295966"),Color("47848b"),Color("417e89"),Color("589a9d"),Color("75a7a5"),Color("74b1b0")], Color("494558"), Color(_palette["outfit_base"]))
	_map_colors([Color("75a7a5"),Color("74b1b0")], Color("746d82"), Color(_palette["outfit_light"]))
	var accent := Color(_palette["accent"])
	var lagoon := Color("27b6a6")
	for ink in [Color("1d424c"),Color("173e49"),Color("183c47"),Color("306774"),Color("295966"),Color("47848b"),Color("417e89"),Color("589a9d"),Color("75a7a5"),Color("74b1b0")]:
		var c: Color = _colors[ink]
		_colors[ink] = Color.from_hsv(fposmod(c.h+accent.h-lagoon.h,1.0),clampf(c.s*accent.s/lagoon.s*0.78,0,1),c.v)
	_map_colors([Color("e6be75"),Color("dcbb78"),Color("fff0bd")], Color("c7d0d6"), Color(_palette["metal"]))
	_zone = "clothing"
	var layers := _portrait()
	if apply_facing and payload["facing"] == "left":
		for image: Image in layers.values():
			image.flip_x()
	if escaped_pixels:
		push_error("Avatar artwork exceeded its canvas: %d pixels" % escaped_pixels)
	return layers


func _map_colors(inks: Array, reference: Color, target: Color) -> void:
	for ink: Color in inks:
		_colors[ink] = Color(clampf(ink.r*target.r/reference.r,0,1),clampf(ink.g*target.g/reference.g,0,1),clampf(ink.b*target.b/reference.b,0,1),ink.a)


func _map_hair(inks: Array, reference: Color, target: Color) -> void:
	# HSV transfer keeps ash/silver neutral instead of amplifying blue channels.
	for ink: Color in inks:
		_colors[ink] = Color.from_hsv(fposmod(ink.h+target.h-reference.h,1.0),clampf(ink.s*target.s/reference.s,0,1),clampf(ink.v*target.v/reference.v,0,1),ink.a)


func _point(x: float, y: float) -> Vector2:
	var p := Vector2(x,y)
	if _zone == "clothing":
		if _gender != "legacy":
			p.x = 64+(p.x-64)*(1.04 if _gender == "male" else 0.96)
		return p
	if _zone == "brows" and _gender != "legacy":
		var center := Vector2(54,49) if x < 65 else Vector2(77,48)
		p = center+(p-center)*Vector2(1.08,1.25)+Vector2(0,1.0) if _gender == "male" else center+(p-center)*Vector2(0.96,0.70)
	if _zone == "mouth" and _gender != "legacy":
		p = Vector2(65,85)+(p-Vector2(65,85))*(Vector2(1.02,0.72) if _gender == "male" else Vector2(1.06,1.12))
	if _zone == "eyes":
		var center := Vector2(54,58) if x < 65 else Vector2(77,57.5)
		var factors: Vector2 = {"round":Vector2(0.96,1.20),"narrow":Vector2(1,0.80),"wide":Vector2(1.12,1.10),"hooded":Vector2(1,0.92),"upturned":Vector2.ONE,"downturned":Vector2.ONE}[_traits["eye_style"]]
		p = center + (p-center)*factors
		if _traits["eye_style"] == "downturned":
			p.y += (p.x-center.x)*0.09*(-1 if x < 65 else 1)
		if _gender == "female":
			p = center+(p-center)*Vector2(1.03,1.08)
		elif _gender == "male":
			p = center+(p-center)*Vector2(1.0,0.90)
	if _zone == "nose":
		var factors: Vector2 = {"straight":Vector2.ONE,"broad":Vector2(1.45,0.92),"short":Vector2(0.95,0.70),"angular":Vector2(0.78,1.05),"hooked":Vector2(1.06,1.10),"button":Vector2(0.80,0.62)}[_traits["nose_style"]]
		p = Vector2(65,65)+(p-Vector2(65,65))*factors
		if _traits["nose_style"] == "hooked" and y > 70:
			p.x += (y-70)*0.25
		if _gender == "female":
			p = Vector2(65,65)+(p-Vector2(65,65))*Vector2(0.91,0.94)
		elif _gender == "male":
			p.x = 65+(p.x-65)*1.10
	var width := 1.0
	match _traits["face_shape"]:
		"square": width = 1.0+clampf((y-66)/28.0,0,1)*0.30
		"round": width = 1.12+clampf((y-76)/22.0,0,1)*0.12
		"long": width = 0.86
		"diamond": width = 1.12 if y > 48 and y < 77 else (0.87 if y >= 77 else 0.96)
		"heart": width = 1.08 if y < 55 else (0.87 if y > 76 else 1.0)
		"soft_square": width = 1.06+clampf((y-68)/30.0,0,1)*0.13
		"tapered": width = 1.04 if y < 66 else 1.04-clampf((y-66)/34.0,0,1)*0.28
	if _gender == "male":
		width *= 1.01+clampf((y-68)/32.0,0,1)*0.06
	elif _gender == "female":
		width *= 0.99-clampf((y-68)/32.0,0,1)*0.10
	p.x = 64+(p.x-64)*width
	match _traits["face_shape"]:
		"square":
			if p.y > 70: p.y = 70+(p.y-70)*0.92
		"round":
			if p.y > 64: p.y = 64+(p.y-64)*0.88
		"long":
			if p.y > 68: p.y = 68+(p.y-68)*1.07
		"diamond":
			if p.y > 74: p.y = 74+(p.y-74)*0.94
		"heart":
			if p.y > 76: p.y = 76+(p.y-76)*0.95
		"soft_square":
			if p.y > 72: p.y = 72+(p.y-72)*0.96
		"tapered":
			if p.y > 72: p.y = 72+(p.y-72)*1.02
	if p.y > 74 and _gender != "legacy":
		p.y = 74+(p.y-74)*(1.03 if _gender == "male" else 0.97)
	return p


func _blank() -> Image:
	var image := Image.create(SIZE,SIZE,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	return image


func _put(image: Image, x: int, y: int, color: Color, coverage: float = 1.0) -> void:
	if coverage <= 0:
		return
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		escaped_pixels += 1
		return
	var src: Color = _colors.get(Color(color,1.0),color)
	src.a = color.a*coverage
	image.set_pixel(x,y,image.get_pixel(x,y).blend(src))


func _poly(image: Image, coordinates: Array, color: Color) -> void:
	var points := PackedVector2Array()
	var box := Rect2(_point(coordinates[0][0],coordinates[0][1]),Vector2.ZERO)
	for pair in coordinates:
		var point := _point(pair[0],pair[1])
		points.append(point)
		box = box.expand(point)
	# Coverage is evaluated at the target pixel, not by enlarging a smaller face.
	for y in range(floori(box.position.y),ceili(box.end.y)+1):
		for x in range(floori(box.position.x),ceili(box.end.x)+1):
			var count := 0
			for offset in [Vector2(0.25,0.25),Vector2(0.75,0.25),Vector2(0.25,0.75),Vector2(0.75,0.75)]:
				if Geometry2D.is_point_in_polygon(Vector2(x,y)+offset,points):
					count += 1
			_put(image,x,y,color,float(count)*0.25)


func _line(image: Image, coordinates: Array, color: Color, width: float = 1.0) -> void:
	if _zone == "brows" and _gender != "legacy":
		width *= 1.35 if _gender == "male" else 0.85
	for i in range(coordinates.size()-1):
		var a := _point(coordinates[i][0],coordinates[i][1])
		var b := _point(coordinates[i+1][0],coordinates[i+1][1])
		var margin := width*0.5+1.0
		for y in range(floori(minf(a.y,b.y)-margin),ceili(maxf(a.y,b.y)+margin)+1):
			for x in range(floori(minf(a.x,b.x)-margin),ceili(maxf(a.x,b.x)+margin)+1):
				var p := Vector2(x+0.5,y+0.5)
				var nearest := Geometry2D.get_closest_point_to_segment(p,a,b)
				var coverage := clampf(width*0.5+0.5-p.distance_to(nearest),0.0,1.0)
				_put(image,x,y,color,coverage)


func _portrait() -> Dictionary:
	var clothing := _blank()
	_clothing(clothing)
	var face := _blank()
	_zone = "face"
	_face(face)
	_marking(face)
	var eyes := _blank()
	_zone = "eyes"
	_eyes(eyes)
	_zone = "brows"
	_brows(eyes)
	_zone = "nose"
	_nose(face)
	_zone = "face"
	_facial_hair(face)
	var mouth := _blank()
	_zone = "mouth"
	_mouth(mouth)
	_zone = "face"
	var hair_back := _blank()
	var hair := _blank()
	_hair(hair,hair_back)
	var accessories := _blank()
	_accessory(accessories)
	var portrait := _blank()
	for layer in [hair_back,clothing,face,eyes,mouth,hair,accessories]:
		portrait.blend_rect(layer,Rect2i(0,0,SIZE,SIZE),Vector2i.ZERO)
	return {"portrait":portrait,"face":face,"eyes":eyes,"mouth":mouth,"hair":hair,"hair_back":hair_back,"clothing":clothing,"accessories":accessories}


func _clothing(clothing: Image) -> void:
	_poly(clothing,[[14,124],[17,113],[26,106],[45,99],[55,94],[74,94],[84,100],[103,106],[112,113],[115,124]],INK)
	_poly(clothing,[[16,123],[20,114],[29,108],[47,102],[57,98],[74,98],[84,103],[101,108],[109,115],[112,123]],Color("1d424c"))
	_poly(clothing,[[19,122],[23,114],[31,109],[45,105],[54,109],[53,124]],Color("306774"))
	_poly(clothing,[[73,107],[84,104],[99,110],[105,116],[109,124],[76,124]],Color("295966"))
	_poly(clothing,[[24,115],[31,110],[43,106],[46,109],[31,114],[28,122],[20,123]],Color("47848b"))
	_line(clothing,[[24,116],[29,111],[43,106]],Color("74b1b0"))
	_line(clothing,[[98,111],[103,117],[105,123]],Color("417e89"),1.4)
	_poly(clothing,[[56,94],[74,94],[77,111],[66,119],[54,110]],SKIN_DARK)
	_poly(clothing,[[57,96],[71,99],[72,110],[65,115],[56,108]],SKIN_SHADE)
	if _traits["outfit"] != "jacket":
		_outfit_details(clothing)
		return
	_poly(clothing,[[48,99],[56,97],[58,110],[66,119],[55,117],[45,105]],Color("d4cbb3"))
	_poly(clothing,[[74,98],[82,101],[80,111],[68,121],[70,111]],Color("a9b9ae"))
	_line(clothing,[[48,101],[55,110],[61,115]],Color("f0e4c3"),1.4)
	_poly(clothing,[[43,104],[47,107],[51,119],[61,124],[51,124],[39,111]],Color("173e49"))
	_poly(clothing,[[83,104],[88,108],[80,117],[79,122],[72,124],[76,112]],Color("173e49"))
	_line(clothing,[[43,105],[47,110],[51,119]],Color("589a9d"))
	_line(clothing,[[88,108],[84,117],[85,123]],Color("417e89"),1.2)
	_ellipse(clothing,83,119,0.9,0.9,Color("a9b9ae"))
	_line(clothing,[[32,118],[43,118]],Color("183c47"))
	_line(clothing,[[32,117],[42,117]],Color("75a7a5"))
	_line(clothing,[[34,120],[40,120]],Color(_palette["accent"]),1.4)


func _face(face: Image) -> void:
	_poly(face,[[36,52],[41,55],[42,68],[39,73],[34,68],[32,60],[33,54]],SKIN_DARK)
	_poly(face,[[35,55],[39,57],[40,65],[38,69],[35,65],[34,59]],SKIN)
	_line(face,[[36,59],[38,58],[39,63],[37,65]],SKIN_DARK)
	_poly(face,[[87,53],[93,54],[95,59],[93,69],[88,73],[85,67]],SKIN_DARK)
	_poly(face,[[89,56],[92,57],[92,63],[90,68],[88,68]],SKIN_SHADE)
	if _gender == "male":
		_male_face(face)
		return
	_poly(face,[[45,30],[57,24],[72,25],[83,31],[89,42],[90,59],[88,74],[84,86],[77,95],[69,100],[59,99],[49,92],[43,83],[39,72],[37,56],[39,41]],INK)
	_poly(face,[[46,31],[57,26],[72,27],[82,33],[87,43],[88,58],[86,74],[82,85],[75,94],[68,98],[60,97],[51,91],[45,82],[41,71],[39,56],[41,42]],SKIN_SHADE)
	_poly(face,[[47,32],[58,27],[71,28],[80,34],[82,43],[82,59],[80,75],[77,86],[70,94],[60,95],[51,88],[46,78],[42,65],[41,51],[43,40]],SKIN)
	_poly(face,[[48,34],[58,30],[69,30],[76,35],[79,44],[74,49],[59,48],[46,51],[43,45]],SKIN_LIGHT)
	_poly(face,[[45,66],[51,65],[57,67],[59,73],[55,76],[49,74],[46,71]],Color("ebb18b"))
	_poly(face,[[76,66],[81,64],[84,66],[82,76],[77,80],[73,76]],Color("cf8d70"))
	_poly(face,[[45,75],[49,80],[55,86],[64,90],[72,89],[77,86],[72,93],[62,96],[54,92],[48,85]],Color("d69777"))
	_line(face,[[41,47],[40,56],[42,65]],SKIN_EDGE,1.1)
	_line(face,[[53,89],[60,93],[66,94]],SKIN_LIGHT,1.3)


func _male_face(face: Image) -> void:
	_poly(face,[[46,28],[58,23],[73,24],[84,30],[89,40],[90,58],[88,72],[87,85],[79,96],[73,101],[56,101],[46,94],[40,82],[38,62],[39,43]],INK)
	_poly(face,[[47,30],[58,25],[72,26],[82,32],[87,41],[88,58],[85,73],[84,84],[77,94],[72,99],[57,99],[48,92],[42,80],[40,61],[41,43]],SKIN_SHADE)
	_poly(face,[[48,31],[59,27],[71,28],[80,34],[83,44],[82,60],[78,70],[80,80],[76,90],[70,96],[58,96],[50,89],[46,78],[43,66],[42,49],[44,39]],SKIN)
	_poly(face,[[48,34],[58,29],[70,30],[77,36],[80,44],[72,48],[59,47],[46,50],[44,43]],SKIN_LIGHT)
	_poly(face,[[43,65],[50,64],[57,67],[53,71],[46,70]],SKIN_LIGHT)
	_poly(face,[[45,73],[52,73],[57,79],[54,86],[49,83]],Color("d69777"))
	_poly(face,[[77,65],[84,64],[85,70],[80,79],[76,81],[74,75]],Color("cf8d70"))
	_poly(face,[[53,90],[60,91],[70,90],[76,88],[73,96],[58,97],[52,94]],SKIN)
	_line(face,[[51,86],[56,90]],SKIN_SHADE,1.0)
	_line(face,[[59,96],[70,96]],SKIN_SHADE,1.3)
	_line(face,[[41,47],[41,59],[43,66]],SKIN_EDGE,1.0)


func _eyes(face: Image) -> void:
	_poly(face,[[47,51],[55,49],[61,52],[60,56],[48,56]],Color("c18a70"))
	_poly(face,[[69,51],[77,49],[83,51],[84,55],[72,56]],Color("b87860"))
	_poly(face,[[47,58],[52,55],[57,56],[61,58],[57,61],[51,61],[48,60]],Color("754b47"))
	_poly(face,[[48,58],[52,56],[56,56.5],[60,58],[56,60],[51,60]],Color("f2dfbd"))
	_poly(face,[[53,56],[57,57],[57,59],[55,61],[52,59]],Color("527783"))
	_poly(face,[[54,56],[56,57],[56,60],[54,60]],Color("253b48"))
	_ellipse(face,54.5,57.5,0.6,0.6,Color("fff0d1"))
	_line(face,[[47,58],[52,55],[57,56],[61,58]],Color("47313a"),1.2)
	_line(face,[[50,62],[56,63],[60,61]],Color("d89375"))
	_poly(face,[[70,57],[75,54.5],[79,55],[83,57],[80,60],[75,61],[71,59]],Color("754b47"))
	_poly(face,[[71,57],[75,55.5],[79,56],[82,57],[79,59],[75,60]],Color("ead6b7"))
	_poly(face,[[76,55.5],[79,56],[79,59],[77,60],[75,58]],Color("527783"))
	_poly(face,[[77,55.5],[79,56],[78,59],[76,59]],Color("253b48"))
	_ellipse(face,77.5,56.5,0.6,0.6,Color("fff0d1"))
	_line(face,[[70,57],[75,54.5],[79,55],[83,57]],Color("47313a"),1.3)
	_line(face,[[73,61],[78,62],[82,60]],Color("b97762"))


func _brows(face: Image) -> void:
	if _traits["brow_style"] != "arched":
		for side in [0,1]:
			var x := 47 if side == 0 else 71
			var y := 49 if side == 0 else 48
			match _traits["brow_style"]:
				"straight": _line(face,[[x,y],[x+12,y]],HAIR_DARK,1.8)
				"thick": _poly(face,[[x,y-2],[x+10,y-2],[x+13,y+1],[x+2,y+2]],HAIR_DARK)
				"soft": _line(face,[[x,y+1],[x+5,y-1],[x+11,y]],HAIR_LIGHT,1.2)
				"angled": _line(face,[[x,y-2],[x+11,y+2]],HAIR_DARK,2.0)
				"unibrow": _line(face,[[x,y],[x+12,y]],HAIR_DARK,2.0)
		if _traits["brow_style"] == "unibrow":
			_line(face,[[58,49],[66,50],[72,48]],HAIR_DARK,1.6)
		return
	_poly(face,[[46,50],[51,47],[57,48],[61,50],[60,52],[54,50],[49,51]],HAIR_DARK)
	_poly(face,[[70,49],[76,46],[82,47],[84,50],[80,49],[75,49],[71,51]],HAIR_DARK)
	_line(face,[[50,48],[54,48],[58,49]],HAIR_LIGHT)
	_line(face,[[74,47],[79,47]],HAIR_LIGHT)


func _nose(face: Image) -> void:
	_poly(face,[[64,54],[67,56],[68,65],[71,73],[68,77],[62,76],[61,74],[64,71]],SKIN_SHADE)
	_poly(face,[[64,58],[66,60],[66,68],[68,72],[65,74],[62,73],[64,68]],SKIN_LIGHT)
	_line(face,[[63,59],[63,65]],SKIN_EDGE)
	_line(face,[[61,74],[64,76],[68,76],[71,74]],Color("a66a58"),0.8)
	_line(face,[[63,77],[66,78]],SKIN_EDGE)


func _mouth(face: Image) -> void:
	if _traits["mouth_style"] != "smirk":
		_mouth_variant(face)
		return
	_poly(face,[[57,83],[63,82],[66,83],[69,82],[75,81],[72,85],[65,87],[60,86]],Color("b86f63"))
	_line(face,[[57,83],[62,84],[67,84],[73,82],[75,80]],Color("784a48"),1.1)
	_line(face,[[62,87],[67,88],[71,86]],Color("f0b698"))
	_line(face,[[61,90],[69,90]],Color("c58b70"))


func _side_part(hair: Image) -> void:
	_poly(hair,[[34,57],[31,47],[32,32],[29,29],[35,22],[34,18],[44,13],[56,9],[65,11],[74,10],[86,15],[91,22],[97,29],[95,40],[94,50],[90,59],[86,61],[85,46],[81,37],[75,32],[66,35],[55,36],[46,40],[41,48],[40,62],[36,67]],HAIR_DARK)
	_poly(hair,[[33,43],[34,31],[38,25],[37,20],[46,16],[56,12],[65,14],[74,13],[84,17],[89,24],[92,30],[86,34],[78,28],[70,30],[59,33],[47,37],[40,43],[37,53],[35,58]],HAIR)
	_poly(hair,[[38,25],[45,19],[56,15],[67,17],[78,17],[84,21],[78,22],[65,22],[53,26],[43,33],[37,39],[36,33]],HAIR_LIGHT)
	_poly(hair,[[44,23],[53,19],[63,19],[54,22],[45,27],[39,33],[39,29]],HAIR_EDGE)
	_poly(hair,[[49,32],[57,27],[69,24],[80,24],[86,28],[82,29],[75,27],[64,30],[55,33]],Color("94503d"))
	_poly(hair,[[84,35],[89,32],[93,33],[92,43],[89,53],[87,52],[87,43]],Color("5b3233"))
	_line(hair,[[86,36],[89,34],[89,41],[87,47]],HAIR_LIGHT,1.2)
	_line(hair,[[36,44],[39,35],[48,29]],Color("ad7051"),1.2)
	_line(hair,[[49,17],[55,15],[63,16]],Color("d5a373"))
	_line(hair,[[58,29],[68,25],[77,24]],Color("b47750"),1.0)
	_line(hair,[[37,54],[38,47],[42,41]],Color("563333"),1.4)


func _ellipse(image: Image, x: float, y: float, rx: float, ry: float, color: Color) -> void:
	var points: Array = []
	for i in range(24):
		var angle := TAU*float(i)/24.0
		points.append([x+cos(angle)*rx,y+sin(angle)*ry])
	_poly(image,points,color)


func _outfit_details(image: Image) -> void:
	var accent := Color(_palette["accent"])
	match _traits["outfit"]:
		"crew":
			_line(image,[[48,104],[53,111],[64,116],[74,112],[80,105]],Color("173e49"),5)
			_line(image,[[49,104],[55,110],[64,113],[73,110],[79,104]],Color("74b1b0"),1.4)
		"turtleneck":
			_poly(image,[[52,93],[76,93],[79,110],[72,117],[59,118],[50,110]],Color("1d424c"))
			_line(image,[[53,98],[65,101],[76,98]],Color("47848b"),2)
			_line(image,[[52,104],[64,107],[77,104]],Color("295966"),2)
		"hoodie":
			_poly(image,[[37,87],[48,86],[53,98],[48,106],[57,114],[48,113],[32,105],[27,95]],Color("1d424c"))
			_poly(image,[[81,86],[92,89],[102,102],[84,113],[75,116],[82,105],[78,97]],Color("295966"))
			_line(image,[[33,97],[38,90],[46,90],[49,98]],Color("74b1b0"),2)
			_line(image,[[82,92],[89,93],[95,102],[83,108]],Color("47848b"),2)
			_line(image,[[51,108],[53,121]],Color("d4cbb3"),1.5)
			_line(image,[[78,108],[76,121]],Color("d4cbb3"),1.5)
		"collared":
			_poly(image,[[48,100],[56,97],[64,112],[52,111]],Color("d4cbb3"))
			_poly(image,[[74,97],[82,101],[75,112],[66,111]],Color("a9b9ae"))
			_line(image,[[65,113],[65,124]],Color("173e49"),2)
			for y in [115,121]:
				_ellipse(image,67,y,0.8,0.8,Color("d4cbb3"))
		"armor":
			_poly(image,[[19,111],[33,103],[45,106],[42,119],[22,121]],Color("173e49"))
			_poly(image,[[21,111],[33,105],[42,108],[39,115],[24,118]],Color("74b1b0"))
			_poly(image,[[83,105],[99,104],[112,114],[108,121],[88,118]],Color("173e49"))
			_poly(image,[[86,107],[99,107],[108,115],[104,118],[91,115]],Color("47848b"))
			_poly(image,[[48,111],[62,115],[79,110],[75,124],[49,124]],Color("306774"))
			_line(image,[[50,115],[61,119],[75,115]],Color("74b1b0"),1.5)
		"polo":
			_poly(image,[[49,101],[56,100],[63,110],[53,109]],Color("47848b"))
			_poly(image,[[73,100],[80,102],[73,110],[66,109]],Color("295966"))
			_line(image,[[64,110],[64,120]],Color("173e49"),2.5)
			for y in [112,117]: _ellipse(image,65,y,0.6,0.6,Color("d4cbb3"))
		"cardigan":
			_poly(image,[[51,100],[63,112],[76,100],[72,122],[59,124]],Color("d4cbb3"))
			_poly(image,[[44,103],[50,102],[64,116],[64,124],[52,124]],Color("295966"))
			_poly(image,[[78,101],[84,105],[71,123],[64,124],[64,116]],Color("306774"))
			_line(image,[[49,104],[61,117],[63,124]],Color("74b1b0"),1.4)
			for y in [117,122]: _ellipse(image,67,y,1,1,Color("d4cbb3"))
		"blazer":
			_poly(image,[[51,101],[63,110],[77,100],[71,124],[59,124]],Color("d4cbb3"))
			_poly(image,[[44,101],[51,102],[55,111],[61,114],[55,119],[49,124],[40,109]],Color("173e49"))
			_poly(image,[[79,101],[86,106],[81,111],[75,112],[77,117],[68,124],[67,114]],Color("295966"))
			_line(image,[[44,103],[50,110],[58,114],[52,120]],Color("74b1b0"),1.2)
			_poly(image,[[63,112],[67,112],[69,124],[62,124]],accent)
		"denim":
			_poly(image,[[48,100],[56,100],[61,112],[52,110]],Color("47848b"))
			_poly(image,[[74,100],[82,102],[75,111],[68,111]],Color("306774"))
			_line(image,[[63,111],[63,124]],Color("74b1b0"),2)
			for x in [31,83]:
				_poly(image,[[x,113],[x+11,113],[x+10,121],[x+5,123],[x,120]],Color("295966"))
				_line(image,[[x,114],[x+11,114]],Color("a9b9ae"),0.8)
				_ellipse(image,x+5,116,0.65,0.65,Color("dcbb78"))
	_line(image,[[31,118],[42,118]],accent,2)


func _mouth_variant(image: Image) -> void:
	var ink := Color("784a48")
	match _traits["mouth_style"]:
		"neutral":
			_line(image,[[58,84],[65,85],[72,84]],ink,1.2)
			_line(image,[[62,87],[68,87]],Color("f0b698"))
		"smile":
			_line(image,[[56,81],[60,85],[67,86],[74,82]],ink,1.3)
			_line(image,[[61,88],[67,89],[71,87]],Color("f0b698"))
		"wide":
			_poly(image,[[55,83],[63,82],[68,83],[77,82],[74,86],[62,88],[57,86]],Color("b86f63"))
			_line(image,[[55,83],[65,85],[77,82]],ink,1.2)
		"serious":
			_line(image,[[58,86],[63,83],[69,83],[74,85]],ink,1.6)
			_line(image,[[63,86],[69,86]],Color("f0b698"))
		"grin":
			_poly(image,[[55,81],[64,84],[76,80],[73,88],[65,91],[59,88]],ink)
			_poly(image,[[57,82],[65,85],[74,81],[72,85],[64,87],[59,85]],Color("f2dfbd"))
			_line(image,[[60,91],[66,92],[71,90]],Color("f0b698"))
		"open":
			_ellipse(image,66,85,5,6,ink)
			_ellipse(image,67,88,3,1.8,Color("b86f63"))
			_line(image,[[62,81],[69,81]],Color("f2dfbd"),1.5)
		"closed_smile":
			_poly(image,[[57,82],[64,84],[74,81],[70,85],[64,87],[59,85]],Color("b86f63"))
			_line(image,[[57,82],[63,84],[68,84],[74,81]],ink,0.9)
			_line(image,[[61,88],[66,89],[70,87]],Color("f0b698"),0.8)
		"skeptical":
			_line(image,[[56,85],[62,85],[71,82],[75,83]],ink,1.3)
			_line(image,[[61,88],[67,87]],Color("f0b698"),1.1)


func _marking(image: Image) -> void:
	match _traits["marking"]:
		"freckles":
			for p in [[47,67],[52,69],[57,67],[49,72],[74,68],[79,67],[81,71]]:
				_ellipse(image,p[0],p[1],0.65,0.55,SKIN_DARK)
		"cheek_scar":
			_line(image,[[77,68],[74,73],[76,78]],SKIN_DARK,1.0)
			_line(image,[[78,68],[75,73],[77,77]],SKIN_LIGHT,0.8)
		"brow_scar":
			_line(image,[[77,43],[75,51]],SKIN_LIGHT,1.8)
		"beauty_spot":
			_ellipse(image,75,76,1,0.8,SKIN_DARK)
		"vitiligo":
			_poly(image,[[43,41],[48,40],[49,45],[46,49],[44,56],[41,55],[41,47]],SKIN_EDGE)
			_poly(image,[[77,70],[82,69],[83,75],[79,82],[75,80],[74,76]],SKIN_EDGE)
		"dimples":
			_line(image,[[52,81],[51,83],[53,85]],SKIN_SHADE,1)
			_line(image,[[78,80],[79,82],[77,84]],SKIN_SHADE,1)
		"smile_lines":
			_line(image,[[59,75],[55,78],[54,83]],SKIN_SHADE,0.9)
			_line(image,[[72,75],[77,77],[80,82]],SKIN_SHADE,0.9)
			_line(image,[[58,76],[56,79]],SKIN_LIGHT,0.7)


func _facial_hair(image: Image) -> void:
	if _gender == "female":
		return
	match _traits["facial_hair"]:
		"stubble":
			for y in range(78,95,3):
				for x in range(49,83,3):
					if (x < 56 or x > 76 or y > 91) and (y < 88 or (x > 54 and x < 77)):
						_ellipse(image,x,y,0.5,0.6,Color(HAIR,0.42))
		"moustache":
			_poly(image,[[65,77],[60,77],[57,81],[62,81],[66,79],[70,81],[76,79],[71,76],[67,77]],HAIR_DARK)
			_line(image,[[60,78],[64,78]],HAIR_LIGHT)
		"goatee":
			_poly(image,[[60,90],[66,92],[73,89],[73,99],[68,104],[61,102],[58,96]],HAIR_DARK)
			_poly(image,[[62,93],[68,95],[70,93],[69,101],[64,101]],HAIR)
		"short_beard", "full_beard":
			var full: bool = _traits["facial_hair"] == "full_beard"
			var bottom := 108 if full else 101
			_poly(image,[[42,73],[47,79],[52,82],[57,79],[65,81],[74,78],[82,74],[85,70],[84,86],[78,99],[70,bottom],[61,bottom-1],[51,99],[45,88]],HAIR_DARK)
			_poly(image,[[46,79],[51,86],[57,85],[63,90],[73,87],[80,81],[77,96],[68,bottom-3],[59,bottom-5],[51,95]],HAIR)
			for x in [51,56,73,78]:
				_line(image,[[x,88],[x+1,95]],HAIR_LIGHT,0.75)
		"chinstrap":
			_line(image,[[43,72],[47,85],[54,94],[63,99],[72,97],[79,90],[84,76]],HAIR_DARK,3.5)
			_line(image,[[49,87],[56,94],[64,97]],HAIR,1.2)
		"soul_patch":
			_poly(image,[[63,90],[68,90],[69,94],[66,97],[63,95]],HAIR_DARK)
			_line(image,[[65,92],[66,95]],HAIR,1.1)
		"heavy_stubble":
			_poly(image,[[44,75],[50,80],[56,82],[64,89],[73,83],[83,75],[81,88],[73,97],[63,100],[53,94],[47,85]],Color(HAIR_DARK,0.30))
			for x in [49,53,76,80]:
				for y in [84,88]: _ellipse(image,x,y,0.55,0.8,Color(HAIR,0.55))


func _cap(image: Image) -> void:
	_poly(image,[[35,53],[33,37],[36,25],[46,18],[62,15],[78,18],[89,27],[94,40],[91,56],[87,49],[85,37],[76,30],[63,32],[49,35],[41,43],[39,56]],HAIR_DARK)
	_poly(image,[[36,38],[39,27],[49,21],[63,18],[77,21],[86,28],[88,35],[78,27],[65,28],[51,32],[42,39],[38,49]],HAIR)
	_line(image,[[41,29],[50,24],[63,22],[76,24]],HAIR_LIGHT,2.0)


func _hair(front: Image, back: Image) -> void:
	var style: String = _traits["hair_style"]
	match style:
		"bald":
			return
		"side_part":
			_side_part(front)
		"curtains":
			_cap(front)
			_poly(front,[[35,35],[38,24],[50,17],[63,17],[63,25],[54,29],[47,37],[43,48],[36,52]],HAIR_DARK)
			_poly(front,[[39,34],[43,25],[53,21],[60,21],[58,25],[50,30],[44,42],[40,45]],HAIR)
			_poly(front,[[66,17],[79,19],[89,26],[94,40],[90,51],[85,43],[81,31],[70,25],[66,25]],HAIR_DARK)
			_poly(front,[[69,21],[78,23],[85,28],[90,41],[88,44],[81,30],[71,26]],HAIR)
			_line(front,[[43,33],[49,26],[57,23]],HAIR_LIGHT,2)
			_line(front,[[72,23],[81,28],[86,38]],HAIR_LIGHT,1.5)
		"bob":
			_poly(back,[[36,30],[48,19],[76,18],[91,29],[98,52],[96,89],[88,96],[80,86],[42,87],[33,94],[27,88],[29,49]],HAIR_DARK)
			_poly(back,[[32,47],[39,31],[43,42],[38,81],[33,89],[30,84]],HAIR)
			_poly(back,[[88,30],[94,47],[92,83],[88,90],[83,81],[84,44]],HAIR)
			_side_part(front)
			_line(back,[[34,53],[34,78],[32,85]],HAIR_LIGHT,2)
			_line(back,[[91,54],[89,80]],HAIR_LIGHT,1.3)
		"wavy":
			_poly(back,[[35,30],[50,19],[77,19],[91,31],[97,49],[94,62],[99,75],[95,88],[101,103],[91,111],[84,104],[80,86],[43,86],[38,108],[26,111],[23,99],[28,86],[25,73],[29,59],[27,47]],HAIR_DARK)
			for side in [0,1]:
				var x := 34 if side == 0 else 90
				_line(back,[[x,39],[x-3,52],[x+2,65],[x-2,80],[x+3,94],[x,105]],HAIR,6)
				_line(back,[[x-1,43],[x-3,52],[x+1,65],[x-2,79],[x+2,93]],HAIR_LIGHT,1.7)
			_cap(front)
			_poly(front,[[39,27],[48,20],[59,20],[67,25],[80,21],[87,28],[83,33],[70,30],[58,34],[48,32],[40,39]],HAIR)
			_line(front,[[44,27],[54,24],[63,27],[73,26],[81,25]],HAIR_LIGHT,2)
		"pixie":
			_poly(front,[[36,49],[34,37],[38,25],[48,18],[67,16],[82,22],[90,32],[92,45],[88,53],[85,38],[78,32],[70,35],[59,33],[50,39],[42,45],[40,56]],HAIR_DARK)
			_poly(front,[[38,36],[42,27],[53,21],[67,20],[80,26],[85,32],[78,29],[68,31],[57,29],[47,38],[39,45]],HAIR)
			_line(front,[[44,29],[54,25],[65,24],[75,27]],HAIR_LIGHT,2)
			_line(front,[[48,35],[57,31]],HAIR_EDGE,1)
		"slick_back":
			_poly(front,[[35,53],[33,38],[36,25],[46,17],[61,14],[78,17],[89,25],[94,38],[92,53],[88,56],[85,41],[78,34],[65,32],[51,35],[43,42],[40,57]],HAIR_DARK)
			_poly(front,[[37,37],[40,27],[49,20],[62,18],[77,21],[86,28],[89,38],[80,31],[66,28],[51,31],[42,38],[38,48]],HAIR)
			for x in [44,52,60,68,76,84]:
				_line(front,[[x,32],[x-2,26],[x+1,22]],HAIR_LIGHT,1.2)
		"messy_crop":
			_cap(front)
			_poly(front,[[35,31],[39,20],[47,23],[49,13],[60,18],[68,12],[74,19],[84,18],[91,30],[87,37],[80,34],[74,39],[63,35],[54,41],[44,36],[38,43]],HAIR_DARK)
			_poly(front,[[40,29],[43,23],[50,26],[53,19],[61,23],[68,18],[73,24],[82,23],[87,30],[77,29],[70,33],[61,29],[53,35],[45,31]],HAIR)
			_line(front,[[44,27],[50,29],[55,23],[62,27]],HAIR_LIGHT,1.8)
			_line(front,[[68,23],[73,28],[80,27]],HAIR_LIGHT,1.8)
		"buzz":
			_poly(front,[[38,48],[38,37],[44,28],[57,23],[72,24],[83,30],[89,42],[88,50],[84,39],[77,32],[64,30],[51,32],[43,40]],HAIR)
			_line(front,[[45,30],[55,26],[66,26],[77,29]],HAIR_LIGHT,1.5)
			for x in range(43,85,4):
				_line(front,[[x,32],[x+1,34]],HAIR_DARK,0.7)
		"crop":
			_cap(front)
			_poly(front,[[40,28],[51,20],[68,20],[84,27],[86,37],[80,36],[77,40],[69,37],[63,40],[56,37],[48,41],[41,40]],HAIR)
			_line(front,[[44,28],[53,25],[65,25],[77,29]],HAIR_LIGHT,2.2)
			for x in [48,59,70,80]:
				_line(front,[[x,31],[x-2,37]],HAIR_DARK,0.8)
		"undercut":
			_poly(front,[[35,47],[37,35],[43,29],[45,48],[40,58],[36,60]],Color("5b3233"))
			_poly(front,[[41,31],[43,20],[58,13],[77,16],[89,24],[93,35],[86,44],[83,33],[76,28],[66,29],[54,35],[44,41]],HAIR_DARK)
			_poly(front,[[46,25],[59,17],[75,19],[85,26],[87,32],[76,24],[64,25],[49,35]],HAIR)
			_line(front,[[49,24],[60,20],[73,22],[81,25]],HAIR_LIGHT,2.4)
			_line(front,[[37,43],[38,52]],HAIR_LIGHT,0.8)
		"quiff":
			_cap(front)
			_poly(front,[[37,30],[41,16],[51,8],[67,7],[80,13],[89,24],[87,32],[80,25],[69,21],[55,26],[42,37]],HAIR_DARK)
			_poly(front,[[43,26],[47,17],[56,12],[68,11],[78,17],[81,22],[69,17],[57,21],[47,30]],HAIR)
			_line(front,[[49,21],[57,16],[66,15],[74,18]],HAIR_EDGE,2)
		"curls", "afro":
			var afro := style == "afro"
			_ellipse(back,64,39,36 if afro else 30,31 if afro else 25,HAIR_DARK)
			for i in range(10):
				var angle := PI+float(i)*PI/9.0
				var x := 64+cos(angle)*(29 if afro else 23)
				var y := 36+sin(angle)*(22 if afro else 16)
				_ellipse(front,x,y,9 if afro else 7,9 if afro else 7,HAIR_DARK)
				_ellipse(front,x-1,y-1,7 if afro else 5.5,7 if afro else 5.5,HAIR)
				_line(front,[[x-4,y-2],[x-1,y-4],[x+2,y-3]],HAIR_LIGHT,1.1)
			for i in range(5):
				var x := 42+i*11
				_ellipse(front,x,31+(i%2)*4,7,7,HAIR)
				_line(front,[[x-3,31],[x-1,28],[x+2,29]],HAIR_LIGHT,1.1)
		"long":
			_poly(back,[[36,28],[47,18],[75,16],[90,26],[99,50],[96,78],[102,112],[87,114],[82,78],[42,79],[38,115],[25,110],[30,77],[29,51]],HAIR_DARK)
			_poly(back,[[33,48],[40,33],[43,64],[36,105],[30,108]],HAIR)
			_poly(back,[[88,33],[95,51],[92,82],[97,109],[89,107],[84,68]],HAIR)
			_side_part(front)
			_line(back,[[34,61],[34,85],[31,104]],HAIR_LIGHT,2)
			_line(back,[[92,64],[90,87],[94,105]],HAIR_LIGHT,1.2)
		"ponytail":
			_poly(back,[[85,29],[99,31],[109,43],[112,61],[105,84],[98,105],[89,109],[96,83],[99,61],[94,48],[85,43]],HAIR_DARK)
			_poly(back,[[94,37],[104,45],[107,59],[101,81],[96,93],[99,69],[98,51]],HAIR)
			_line(back,[[101,44],[103,59],[98,78]],HAIR_LIGHT,2)
			_cap(front)
			_line(front,[[87,32],[94,36]],Color(_palette["accent"]),3)
		"top_knot":
			_ellipse(back,65,15,11,10,HAIR_DARK)
			_ellipse(back,64,14,8,7,HAIR)
			_line(back,[[59,13],[63,9],[69,10]],HAIR_LIGHT,1.8)
			_cap(front)
			_line(front,[[58,22],[69,22]],Color(_palette["accent"]),2)
		"mohawk":
			_poly(front,[[37,49],[39,37],[46,29],[47,35],[42,42],[40,56]],HAIR)
			_poly(front,[[82,29],[90,40],[91,53],[88,58],[86,42],[80,36]],HAIR_DARK)
			_poly(front,[[54,37],[55,16],[59,7],[62,13],[66,5],[70,12],[74,9],[79,18],[77,32],[71,39]],HAIR_DARK)
			_poly(front,[[59,31],[60,18],[65,13],[68,18],[71,14],[74,21],[72,32],[66,36]],HAIR)
			_line(front,[[62,29],[65,19],[69,27]],HAIR_EDGE,2)
		"braids", "locs":
			var braided := style == "braids"
			for side in [0,1]:
				var x := 32 if side == 0 else 91
				_poly(back,[[x-3,35],[x+8,35],[x+10,90],[x+6,111],[x-2,105],[x-5,69]],HAIR_DARK)
				for i in range(8):
					var y := 45+i*8
					_poly(back,[[x,y],[x+6,y-3],[x+8,y+4],[x+2,y+9],[x-2,y+3]],HAIR)
					_line(back,[[x,y],[x+4,y+3],[x+1,y+6]],HAIR_LIGHT,1.3 if braided else 2.0)
			_cap(front)
			if braided:
				for x in [43,51,59,67,75,83]:
					_line(front,[[x,26],[x-3,32],[x-3,37]],HAIR_LIGHT,1.2)
			else:
				for i in range(7):
					var x := 38+i*7
					_poly(front,[[x,24],[x+5,22],[x+8,38],[x+3,45],[x-1,42]],HAIR_DARK)
					_line(front,[[x+2,26],[x+4,37],[x+2,42]],HAIR_LIGHT,2)


func _accessory(image: Image) -> void:
	var metal := Color(_palette["metal"])
	match _traits["accessory"]:
		"stud":
			_ellipse(image,90,70,1.3,1.3,metal)
			_ellipse(image,89.6,69.7,0.55,0.55,Color("fff0bd"))
		"aviators":
			for x in [45,69]:
				_line(image,[[x,54],[x+13,53],[x+16,56],[x+14,61],[x+9,65],[x+3,63],[x,59],[x,54]],metal,1.1)
			_line(image,[[60,55],[65,53],[70,55]],metal,1)
			_line(image,[[60,58],[69,58]],metal,0.8)
		"earring":
			_line(image,[[90,68],[90,74]],Color("e6be75"),1.8)
			_ellipse(image,89.5,70.5,0.6,0.6,Color("fff0bd"))
		"glasses":
			for x in [46,69]:
				_line(image,[[x,54],[x+15,54],[x+14,63],[x+2,63],[x,54]],metal,1.1)
			_line(image,[[61,56],[65,55],[69,56]],metal,1)
			_line(image,[[45,55],[40,54]],metal,1)
			_line(image,[[84,55],[89,53]],metal,1)
		"round_glasses":
			for x in [54,77]:
				var points: Array = []
				for i in range(25):
					var angle := TAU*float(i)/24.0
					points.append([x+8*cos(angle),58+6.5*sin(angle)])
				_line(image,points,metal,1.2)
			_line(image,[[62,57],[66,56],[69,57]],metal,1)
		"headband":
			_poly(image,[[38,35],[53,30],[73,30],[88,37],[87,41],[72,34],[53,34],[38,39]],Color(_palette["accent"]))
			_line(image,[[40,35],[54,31],[72,31],[85,36]],Color(_palette["accent_light"]),1)
		"hair_clip":
			_line(image,[[83,32],[89,37]],metal,2.4)
			_line(image,[[82,35],[87,39]],Color(_palette["accent_light"]),1.5)
