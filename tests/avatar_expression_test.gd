extends SceneTree

const Art := preload("res://scripts/vendor/procedural_2d/procedural_avatar_art.gd")
const Generator := preload("res://scripts/vendor/procedural_2d/procedural_avatar_generator.gd")


func _initialize() -> void:
	call_deferred("_run_test")


func _run_test() -> void:
	var art := Art.new()

	var trait_ids: Dictionary = Generator.TRAIT_IDS
	var face_shapes: Array = trait_ids["face_shape"]

	var sym_seeds: Array[int] = [0, 13, 42, 99, 12345]
	var mirror_seeds: Array[int] = [1, 99, 1234, 7777]

	# 1. mirror sym head on face layer, every face_shape + seeds
	for fs: String in face_shapes:
		for sd: int in sym_seeds:
			var p: Dictionary = Generator.generate(sd, {"face_shape": fs, "facing": "right"})
			if not _expect(not p.is_empty(), "generate must succeed for face_shape=%s seed=%d" % [fs, sd]):
				return
			var layers: Dictionary = art.render(p, true)
			var face_layer: Image = layers["face"]
			var mismatches: int = _count_opaque_mirror_mismatches(face_layer, 0.05)
			# tol=90 (~0.55%) justified for subsample raster of _symmetric head in face layer (y 22-104 clip).
			# This and facing-mirror are the cheap fixture that would have failed on pre-GURI-1302 3/4-turned art.
			var tol: int = 90
			if not _expect(mismatches <= tol, "face_shape=%s seed=%d head not mirror sym (mismatches=%d > %d)" % [fs, sd, mismatches, tol]):
				return

	# sample every trait value
	var trait_count := 0
	for field: String in trait_ids.keys():
		if field == "facing": continue
		for val: String in trait_ids[field]:
			var opts: Dictionary = {field: val}
			if field == "facial_hair" and val != "none":
				opts["gender"] = "male"
			var p: Dictionary = Generator.generate(2000 + trait_count, opts)
			if p.is_empty() and field != "gender":
				p = Generator.generate(2000 + trait_count, {"gender": "male", field: val})
			if not _expect(not p.is_empty(), "must cover %s=%s" % [field, val]):
				return
			var layers: Dictionary = art.render(p, true)
			var eyes_layer: Image = layers["eyes"]
			var mouth_layer: Image = layers["mouth"]
			var portrait: Image = layers["portrait"]

			if field == "mouth_style":
				if not _check_no_drooping_mouth(mouth_layer, val): return
			if field == "brow_style":
				if not _check_no_worried_brows(eyes_layer, p, val): return
			if not _check_eyes_centred_clean(eyes_layer, p, portrait): return
			trait_count += 1

	# 5. facing left/right produce mirrors
	for sd: int in mirror_seeds:
		var pbase: Dictionary = Generator.generate(sd)
		var pr: Dictionary = pbase.duplicate(true); pr["facing"] = "right"
		var pl: Dictionary = pbase.duplicate(true); pl["facing"] = "left"
		var rp: Image = art.render(pr, true)["portrait"]
		var lp: Image = art.render(pl, true)["portrait"]
		var md: int = _count_facing_mirror_mismatches(rp, lp, 0.004)
		var mtol: int = 66
		if not _expect(md <= mtol, "facing not mirror seed=%d (mismatches=%d)" % [sd, md]): return

	print("AVATAR_EXPRESSION_TEST PASS")
	quit(0)


func _count_opaque_mirror_mismatches(img: Image, a_thresh: float) -> int:
	var cx: int = int(Art.CX)
	var mis: int = 0
	var h: int = Art.SIZE
	for y in range(22, 104):
		for d in range(1, cx):
			var xl: int = cx - d
			var xr: int = cx + d
			if xr >= h: break
			var al: bool = img.get_pixel(xl, y).a > a_thresh
			var ar: bool = img.get_pixel(xr, y).a > a_thresh
			if al != ar: mis += 1
	return mis


func _count_facing_mirror_mismatches(rp: Image, lp: Image, tol: float) -> int:
	var mis: int = 0
	var sz: int = Art.SIZE
	for y in range(sz):
		for x in range(sz):
			var cr := rp.get_pixel(x, y)
			var cl := lp.get_pixel(sz - 1 - x, y)
			if abs(cr.r - cl.r) > tol or abs(cr.g - cl.g) > tol or abs(cr.b - cl.b) > tol or abs(cr.a - cl.a) > tol:
				mis += 1
	return mis


func _check_no_drooping_mouth(mimg: Image, ms: String) -> bool:
	var reg := Art.MOUTH_REGION
	var th := 0.08
	var my := _bottom_ink_y(mimg, 64, reg, th)
	var ly := _bottom_ink_y(mimg, reg.position.x + 4, reg, th)
	var ry := _bottom_ink_y(mimg, reg.end.x - 5, reg, th)
	var tol := 2
	if not _expect(ly <= my + tol, "mouth %s left corner y lower than mid" % ms): return false
	if not _expect(ry <= my + tol, "mouth %s right corner y lower than mid" % ms): return false
	return true


func _bottom_ink_y(img: Image, x: int, reg: Rect2i, th: float) -> int:
	for yy in range(reg.end.y - 1, reg.position.y - 1, -1):
		if img.get_pixel(x, yy).a > th: return yy
	return reg.position.y


func _check_no_worried_brows(eimg: Image, pay: Dictionary, bs: String) -> bool:
	var s: Dictionary = Art.BROW_STYLES[bs]
	if not _expect(float(s["inner"]) >= float(s["outer"]) - 0.001, "BROW_STYLES.%s declares inner above outer" % bs): return false
	var cols: Array[int] = [int(Art.CX - 19), int(Art.CX - 7), int(Art.CX + 7), int(Art.CX + 19)]
	var tys: Array = []
	for col in cols:
		var fy := -1
		for yy in range(44, 58):
			var c := eimg.get_pixel(col, yy)
			if c.a > 0.15 and (c.r + c.g + c.b) / 3.0 < 0.55:
				fy = yy
				break
		tys.append(fy)
	if tys[0] >= 0 and tys[1] >= 0:
		if not _expect(tys[1] >= tys[0] - 3, "left brow rendered inner end above outer for %s" % bs): return false
	if tys[2] >= 0 and tys[3] >= 0:
		if not _expect(tys[2] >= tys[3] - 3, "right brow rendered inner end above outer for %s" % bs): return false
	return true


func _check_eyes_centred_clean(eimg: Image, pay: Dictionary, port: Image) -> bool:
	var reg := Art.EYE_REGION
	var ew := Color(pay["palette"]["eye_white"])
	var ic := Color(pay["palette"]["iris"])
	var wl := 0
	var wr := 0
	var il: Array[Vector2] = []
	var ir: Array[Vector2] = []
	for y in range(reg.position.y, reg.end.y):
		for x in range(reg.position.x, reg.end.x):
			var c := eimg.get_pixel(x, y)
			if c.a < 0.25: continue
			if abs(c.r - ew.r) < 0.09 and abs(c.g - ew.g) < 0.09 and abs(c.b - ew.b) < 0.09:
				if x < 64:
					wl += 1
				else:
					wr += 1
			if abs(c.r - ic.r) < 0.12 and abs(c.g - ic.g) < 0.12 and abs(c.b - ic.b) < 0.12:
				if x < 64:
					il.append(Vector2(x, y))
				else:
					ir.append(Vector2(x, y))
	if not _expect(abs(wl - wr) <= 12, "eye white not symmetric L=%d R=%d" % [wl, wr]): return false
	var cl := _centroid(il)
	var cr := _centroid(ir)
	if cl.x >= 0.0 and cr.x >= 0.0:
		var md := absf(cl.x + cr.x - 128.0)
		# tol=4.0 justified: iris disc (r~3) + tilt + fixed +0.7 gaze bias (art drawn "looking right")
		# yields md up to 3.6 across styles; irises remain inside their eye whites and the face is friendly front.
		if not _expect(md <= 4.0, "iris centroids not mirror within art bias (L=%.1f R=%.1f md=%.1f)" % [cl.x, cr.x, md]): return false
	# no bags below the eye: sample immediately under eye (y~66-70); intended lower lid lash is darker by design,
	# "no bags" means no extra dark band on skin further under. tol relaxed for grazing lid edge.
	var btol := 0.15
	for sgn in [-1.0, 1.0]:
		var ex: int = int(64.0 + sgn * 12.5)
		for by in range(66, 71):
			var lidc := port.get_pixel(ex, by)
			var skc := port.get_pixel(ex, by + 1)
			if lidc.a > 0.15 and skc.a > 0.15:
				var ll := _lum(lidc)
				var sl := _lum(skc)
				if ll < sl - btol:
					if not _expect(false, "possible bag (darker line) under eye x=%d y=%d" % [ex, by]): return false
	return true


func _centroid(pts: Array[Vector2]) -> Vector2:
	if pts.is_empty(): return Vector2(-1.0, -1.0)
	var sx := 0.0
	var sy := 0.0
	for p: Vector2 in pts:
		sx += p.x
		sy += p.y
	return Vector2(sx / pts.size(), sy / pts.size())


func _lum(c: Color) -> float:
	return c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722


func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("AVATAR_EXPRESSION_TEST FAIL: " + message)
	quit(1)
	return false
