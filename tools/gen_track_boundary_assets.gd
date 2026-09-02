extends SceneTree

const OUTPUT_DIR := "res://assets/textures/track_boundary"


func _initialize() -> void:
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("TRACK_BOUNDARY_ASSET_GENERATOR FAIL: %s" % error_string(error))
		quit(1)
		return
	var assets := {
		"kitchen_folded_towel_rail": _kitchen_section(),
		"kitchen_mitt_corner": _kitchen_accent(),
		"workshop_paint_stirrer_rail": _workshop_section(),
		"workshop_tape_corner": _workshop_accent(),
		"office_pencil_rail": _office_section(),
		"office_sticky_corner": _office_accent(),
	}
	for asset_name: String in assets:
		var image := Image.new()
		var load_error := image.load_svg_from_buffer(_svg(String(assets[asset_name]), asset_name).to_utf8_buffer(), 2.0)
		if load_error != OK:
			push_error("TRACK_BOUNDARY_ASSET_GENERATOR FAIL: %s SVG: %s" % [asset_name, error_string(load_error)])
			quit(1)
			return
		var output_path := "%s/%s.png" % [OUTPUT_DIR, asset_name]
		var save_error := image.save_png(output_path)
		if save_error != OK:
			push_error("TRACK_BOUNDARY_ASSET_GENERATOR FAIL: %s: %s" % [output_path, error_string(save_error)])
			quit(1)
			return
		print("SAVE %s OK" % output_path)
	quit(0)


func _svg(body: String, title: String) -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="256" height="128" viewBox="0 0 256 128">
<title>%s</title>
<defs>
<linearGradient id="cloth" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#9ed8ec"/><stop offset="0.48" stop-color="#579bb9"/><stop offset="1" stop-color="#2f617b"/></linearGradient>
<linearGradient id="wood" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e0b471"/><stop offset="0.52" stop-color="#ad7542"/><stop offset="1" stop-color="#67452f"/></linearGradient>
<linearGradient id="pencil" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffd95b"/><stop offset="0.5" stop-color="#e9ad31"/><stop offset="1" stop-color="#a56b20"/></linearGradient>
</defs>%s</svg>""" % [title, body]


func _kitchen_section() -> String:
	return """
<path fill="#241f21" fill-opacity=".24" d="M10 48 Q25 35 44 42 Q63 31 83 42 Q103 31 124 42 Q145 30 166 42 Q188 30 210 42 Q234 34 248 49 L246 91 Q229 102 209 94 Q188 105 166 94 Q145 105 124 94 Q102 105 81 94 Q61 105 41 94 Q22 102 8 91 Z"/>
<path fill="url(#cloth)" stroke="#294f66" stroke-width="5" stroke-linejoin="round" d="M7 40 Q23 29 42 36 Q62 24 82 36 Q102 24 123 36 Q144 23 165 36 Q187 23 209 36 Q233 28 249 42 L247 83 Q229 94 208 87 Q187 98 165 87 Q144 98 123 87 Q101 98 80 87 Q60 98 40 87 Q20 95 6 84 Z"/>
<path fill="none" stroke="#fff0c8" stroke-width="4" stroke-dasharray="10 8" d="M18 52 Q62 42 104 51 T190 51 Q219 45 239 54 M17 73 Q62 63 104 72 T190 72 Q220 66 239 74"/>
<path fill="none" stroke="#27647f" stroke-width="3" stroke-opacity=".65" d="M47 35V90M89 34V91M132 34V91M175 34V91M218 35V88"/>"""


func _kitchen_accent() -> String:
	return """
<g transform="translate(38 3) rotate(-12 91 64)"><path fill="#2c2224" fill-opacity=".24" d="M43 13 Q70 2 91 23 L106 46 Q119 23 138 31 Q159 39 154 63 Q150 82 132 92 L143 116 Q113 130 77 116 Q49 106 42 84 L29 48 Q24 24 43 13 Z"/><path fill="#d95f51" stroke="#6c3032" stroke-width="6" d="M37 8 Q64 -3 85 18 L101 41 Q114 18 133 26 Q154 34 149 58 Q145 77 127 87 L138 111 Q108 125 72 111 Q44 101 37 79 L24 43 Q19 19 37 8 Z"/><path fill="none" stroke="#ffad91" stroke-width="4" d="M38 26L126 105M31 49L100 117M66 9L148 82M91 17L142 61"/></g>
<path fill="none" stroke="#d7e0e4" stroke-width="13" stroke-linecap="round" d="M151 91 Q190 68 234 78"/><path fill="none" stroke="#677a83" stroke-width="4" stroke-linecap="round" d="M151 91 Q190 68 234 78"/><ellipse fill="#b9c8ce" stroke="#5a6970" stroke-width="5" cx="226" cy="78" rx="22" ry="12"/>"""


func _workshop_section() -> String:
	return """
<path fill="#292322" fill-opacity=".24" d="M8 43 L246 35 L252 88 L14 98 Z"/>
<path fill="url(#wood)" stroke="#5c3c29" stroke-width="6" stroke-linejoin="round" d="M5 34 L244 27 L249 80 L11 89 Z"/>
<path fill="none" stroke="#f0cc8c" stroke-width="4" stroke-opacity=".65" d="M19 48 Q68 35 117 45 T216 42 M20 68 Q73 55 122 66 T232 58"/>
<g fill="#52616a" stroke="#29343a" stroke-width="3"><circle cx="28" cy="58" r="8"/><circle cx="225" cy="52" r="8"/></g><path fill="none" stroke="#29343a" stroke-width="3" d="M22 58H34M28 52V64M219 52H231M225 46V58"/>"""


func _workshop_accent() -> String:
	return """
<ellipse fill="#272322" fill-opacity=".25" cx="126" cy="73" rx="82" ry="47"/><ellipse fill="#e7b533" stroke="#5f4a21" stroke-width="7" cx="120" cy="65" rx="74" ry="43"/><ellipse fill="#343b40" stroke="#1f2529" stroke-width="7" cx="120" cy="65" rx="45" ry="24"/><ellipse fill="#d8a82e" stroke="#685323" stroke-width="6" cx="120" cy="65" rx="19" ry="10"/><path fill="#e7b533" stroke="#5f4a21" stroke-width="6" d="M185 49 Q231 43 247 59 L244 84 Q216 94 177 79 Z"/><path fill="none" stroke="#fff0a0" stroke-width="5" stroke-dasharray="10 8" d="M177 58Q215 54 241 66"/><path fill="#bc493f" stroke="#5f2f2d" stroke-width="5" d="M24 80 Q49 56 75 73 L69 112 Q39 120 19 101 Z"/>"""


func _office_section() -> String:
	return """
<path fill="#28272b" fill-opacity=".24" d="M7 52 L214 42 L250 65 L227 93 L12 101 Z"/>
<path fill="url(#pencil)" stroke="#704722" stroke-width="6" stroke-linejoin="round" d="M5 43 L211 34 L244 56 L221 85 L9 92 Z"/>
<path fill="#f4b2a7" stroke="#8e5650" stroke-width="4" d="M10 42L43 41L47 91L9 93Z"/><path fill="#d4d7d5" stroke="#687075" stroke-width="4" d="M43 41L61 40L64 90L47 91Z"/>
<path fill="#ead9ad" stroke="#765a32" stroke-width="4" d="M211 34L244 56L221 85Z"/><path fill="#303139" d="M236 51L244 56L237 65Z"/><path fill="none" stroke="#fff1a0" stroke-width="4" d="M73 49L207 43M74 70L206 64"/>"""


func _office_accent() -> String:
	return """
<g transform="rotate(-8 94 62)"><rect fill="#29282c" fill-opacity=".2" x="21" y="20" width="119" height="92" rx="8"/><rect fill="#f6d455" stroke="#886b27" stroke-width="6" x="14" y="13" width="119" height="92" rx="8"/><path fill="#c9a62e" fill-opacity=".55" d="M14 83L36 105H14Z"/><path fill="none" stroke="#866d2d" stroke-width="5" stroke-linecap="round" d="M37 43H111M37 61H102M37 79H88"/></g>
<g transform="rotate(11 178 77)"><rect fill="#80c7c1" stroke="#477b78" stroke-width="6" x="124" y="34" width="111" height="84" rx="8"/><path fill="#509c96" fill-opacity=".5" d="M124 96L146 118H124Z"/><path fill="none" stroke="#3d716e" stroke-width="5" d="M146 62H213M146 80H204M146 98H218"/></g>"""
