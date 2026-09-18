extends SceneTree

const TrackSeedGen = preload("res://scripts/race/track_seed_gen.gd")

func _init():
	print("Running variable width renders...")
	
	_render_shape("classic", "standard")
	_render_shape("long", "marathon")
	
	_print_affordability_table()
	
	print("PASS")
	quit()

func _render_shape(shape_name: String, tier: String):
	var amplitudes = [0.0, 40.0, 115.0]
	var rect = Rect2(0, 0, 4000, 4000)
	if shape_name == "marathon" or tier == "marathon":
		rect = Rect2(0, 0, 6000, 6000)
		
	var seeds = [1001, 1002]
	for current_seed in seeds:
		var params = {"room_shape": shape_name, "length_tier": tier}
		var res = TrackSeedGen.generate_with_retries(current_seed, rect, params)
		var centerline = res.get("points", PackedVector2Array())
		if centerline.is_empty():
			continue
			
		for A in amplitudes:
			var widths = TrackSeedGen.compute_width_profile(centerline, current_seed, A)
			_draw_svg_render(shape_name, current_seed, A, centerline, widths)
		print("Rendered shape ", shape_name, " with seed ", current_seed)


func _draw_svg_render(shape_name: String, seed: int, A: float, centerline: PackedVector2Array, widths: PackedFloat32Array):
	var n = centerline.size()
	var min_x = 99999.0
	var min_y = 99999.0
	var max_x = -99999.0
	var max_y = -99999.0
	
	for p in centerline:
		min_x = min(min_x, p.x - 300)
		max_x = max(max_x, p.x + 300)
		min_y = min(min_y, p.y - 300)
		max_y = max(max_y, p.y + 300)
		
	var w = max_x - min_x
	var h = max_y - min_y
	
	var file = FileAccess.open("/tmp/opencode/render_%s_%d_A%d.svg" % [shape_name, seed, int(A)], FileAccess.WRITE)
	file.store_string("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"%f %f %f %f\">\n" % [min_x, min_y, w, h])
	file.store_string("<rect x=\"%f\" y=\"%f\" width=\"%f\" height=\"%f\" fill=\"#222\"/>\n" % [min_x, min_y, w, h])
	
	for i in n:
		var i_next = (i + 1) % n
		var p1 = centerline[i]
		var p2 = centerline[i_next]
		var dir = (p2 - p1).normalized()
		var right = Vector2(-dir.y, dir.x)
		var w1 = widths[i]
		var w2 = widths[i_next]
		
		var v1 = p1 - right * w1
		var v2 = p2 - right * w2
		var v3 = p2 + right * w2
		var v4 = p1 + right * w1
		
		file.store_string("<polygon points=\"%f,%f %f,%f %f,%f %f,%f\" fill=\"#555\"/>\n" % [v1.x, v1.y, v2.x, v2.y, v3.x, v3.y, v4.x, v4.y])
	
	file.store_string("<polyline points=\"")
	for p in centerline:
		file.store_string("%f,%f " % [p.x, p.y])
	file.store_string("%f,%f\" fill=\"none\" stroke=\"#ff0\" stroke-width=\"4\"/>\n" % [centerline[0].x, centerline[0].y])
	file.store_string("</svg>")

func _print_affordability_table():
	print("\n--- Affordability Table ---")
	print("| Room Shape | Tier | Max Half-Width |")
	print("|------------|------|----------------|")
	var shapes = ["classic", "wide", "tall", "long", "square", "el"]
	var tiers = ["compact", "standard", "long"]
	for shape in shapes:
		for tier in tiers:
			if shape == "el" and tier == "long":
				continue
			var max_w = _find_max_affordable_width(shape, tier)
			print("| %s | %s | %d |" % [shape, tier, int(max_w)])
	print("---------------------------\n")

func _find_max_affordable_width(shape: String, tier: String) -> float:
	var w = 125.0
	var step = 10.0
	var success_w = 0.0
	var rect = Rect2(0, 0, 4000, 4000)
	if shape == "marathon" or tier == "marathon":
		rect = Rect2(0, 0, 6000, 6000)
		
	while w <= 400.0:
		var found = false
		for s in range(5):
			var params = {"room_shape": shape, "length_tier": tier, "forced_half_width": w}
			var res = TrackSeedGen.generate_with_retries(s * 100, rect, params)
			if not res.get("points", PackedVector2Array()).is_empty():
				found = true
				break
			else:
				print("Fail w=", w, " seed=", s*100, " reason=", res.get("reason", "unknown"))
		if found:
			success_w = w
			w += step
		else:
			break
	return success_w
