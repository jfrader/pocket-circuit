extends SceneTree

const OUTPUT := "res://assets/textures/world_materials"
const SIZE := 512


func _initialize() -> void:
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("WORLD_MATERIALS FAIL: cannot create output directory")
		quit(1)
		return
	var assets := [
		{"name": "kitchen_counter", "body": _counter()},
		{"name": "kitchen_board", "body": _board()},
		{"name": "workshop_bench", "body": _wood(64203, ["#876849", "#8d6e4f", "#826548", "#896a4b"], "#876849", "#493829", "#584432", "#c8aa7e")},
		{"name": "workshop_mat", "body": _mat("#3c6253", "#83a28b", 64204, true)},
		{"name": "office_desk", "body": _wood(64205, ["#b9b29e", "#b5ae9b", "#bdb5a0", "#b8b19c"], "#b9b29e", "#817967", "#928977", "#e3dcc8")},
		{"name": "office_pad", "body": _mat("#3b5063", "#8a9ba7", 64206, false)},
	]
	for item in assets:
		var image := Image.new()
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">%s</svg>' % item["body"]
		if image.load_svg_from_buffer(svg.to_utf8_buffer()) != OK or image.save_png(OUTPUT.path_join(String(item["name"]) + ".png")) != OK:
			push_error("WORLD_MATERIALS FAIL: cannot render " + String(item["name"]))
			quit(1)
			return
	print("WORLD_MATERIALS PASS six_materials")
	quit(0)


func _counter() -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = 64201
	var body := '<defs><radialGradient id="warm"><stop stop-color="#a99778" stop-opacity="0.09"/><stop offset="1" stop-color="#a99778" stop-opacity="0"/></radialGradient><radialGradient id="light"><stop stop-color="#fff9e8" stop-opacity="0.18"/><stop offset="1" stop-color="#fff9e8" stop-opacity="0"/></radialGradient></defs><rect width="512" height="512" fill="#cbc7b5"/>'
	for index in 18:
		var mark := '<ellipse cx="%.3f" cy="%.3f" rx="%.3f" ry="%.3f" fill="url(#%s)"/>' % [rng.randf_range(0, SIZE), rng.randf_range(0, SIZE), rng.randf_range(35, 125), rng.randf_range(30, 90), "warm" if index % 2 == 0 else "light"]
		body += _wrap(mark)
	for index in 750:
		var mark := '<ellipse cx="%.3f" cy="%.3f" rx="%.3f" ry="%.3f" fill="%s" fill-opacity="%.3f"/>' % [rng.randf_range(0, SIZE), rng.randf_range(0, SIZE), rng.randf_range(0.7, 1.8), rng.randf_range(0.5, 1.2), "#8f8979" if index % 3 == 0 else "#fff9e6", rng.randf_range(0.05, 0.16)]
		body += _wrap(mark)
	body += _wrap('<path d="M0 0H512M0 256H512M0 0V512M256 0V512" fill="none" stroke="#8f8979" stroke-opacity="0.22" stroke-width="1"/><path d="M1.5 1.5H512M1.5 257.5H512M1.5 1.5V512M257.5 1.5V512" fill="none" stroke="#fff9e6" stroke-opacity="0.22" stroke-width="0.7"/>')
	return body


func _board() -> String:
	return _wood(64202, ["#b48b51", "#bc955b", "#b78f53", "#b08a51"], "#b38a50", "#71522f", "#795a33", "#f2d5a0")


func _wood(seed_value: int, tones: Array, base: String, dark: String, joint: String, light: String) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var body := '<rect width="512" height="512" fill="%s"/>' % base
	for stave in 4:
		body += '<rect y="%d" width="512" height="128" fill="%s"/><path d="M0 %dH512" stroke="%s" stroke-opacity="0.24" stroke-width="1.2"/>' % [stave * 128, tones[stave], stave * 128, joint]
	for index in 160:
		var x := rng.randf_range(0, SIZE)
		var y := rng.randf_range(0, SIZE)
		var length := rng.randf_range(20, 190)
		var bend := rng.randf_range(-8, 8)
		var mark := '<path d="M%.3f %.3f c%.3f %.3f %.3f %.3f %.3f 0" fill="none" stroke="%s" stroke-opacity="%.3f" stroke-width="%.3f" stroke-linecap="round"/>' % [x, y, length * 0.3, bend, length * 0.7, -bend, length, dark if index % 3 else light, rng.randf_range(0.045, 0.15), rng.randf_range(0.4, 1.2)]
		body += _wrap(mark)
	for index in 16:
		var x := rng.randf_range(0, SIZE)
		var y := rng.randf_range(0, SIZE)
		body += _wrap('<path d="M%.3f %.3f l%.3f %.3f" stroke="%s" stroke-opacity="0.15" stroke-width="0.7"/>' % [x, y, rng.randf_range(8, 35), rng.randf_range(-12, 12), light])
	return body


func _mat(base: String, detail: String, seed_value: int, grid: bool) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var body := '<rect width="512" height="512" fill="%s"/>' % base
	for index in range(0, SIZE, 8):
		body += '<path d="M0 %dH512M%d 0V512" stroke="%s" stroke-opacity="0.035" stroke-width="0.6"/>' % [index, index, detail]
	if grid:
		for index in range(0, SIZE, 64):
			body += _wrap('<path d="M0 %dH512M%d 0V512" stroke="%s" stroke-opacity="0.2" stroke-width="0.8"/>' % [index, index, detail])
	for index in 180:
		body += _wrap('<circle cx="%.3f" cy="%.3f" r="%.3f" fill="%s" fill-opacity="0.08"/>' % [rng.randf_range(0, SIZE), rng.randf_range(0, SIZE), rng.randf_range(0.4, 1.0), detail])
	return body


func _wrap(mark: String) -> String:
	var result := ""
	for x in [-SIZE, 0, SIZE]:
		for y in [-SIZE, 0, SIZE]:
			result += '<g transform="translate(%d %d)">%s</g>' % [x, y, mark]
	return result
