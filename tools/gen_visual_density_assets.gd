extends SceneTree

const OUTPUT_DIR := "res://assets/textures/edge_dressing"
const GIANT_DIR := "res://assets/textures/giant_props"
const PATCH_DIR := "res://assets/textures/grip_patches"


func _initialize() -> void:
	for dir in [OUTPUT_DIR, GIANT_DIR, PATCH_DIR]:
		var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		if err != OK and err != ERR_ALREADY_EXISTS:
			push_error("VISUAL_DENSITY_GEN FAIL: could not create %s: %s" % [dir, error_string(err)])
			quit(1)
			return

	var assets: Array[Dictionary] = [
		# Edge / apron micro non-colliding decor (small crumbs, hardware, fibers)
		{"name": "crumb_micro_01", "dir": OUTPUT_DIR, "body": _crumb_micro()},
		{"name": "crumb_micro_02", "dir": OUTPUT_DIR, "body": _crumb_micro2()},
		{"name": "fiber_strand", "dir": OUTPUT_DIR, "body": _fiber_strand()},
		{"name": "screw_small", "dir": OUTPUT_DIR, "body": _screw_small()},
		{"name": "pencil_shaving", "dir": OUTPUT_DIR, "body": _pencil_shaving()},
		{"name": "paperclip_micro", "dir": OUTPUT_DIR, "body": _paperclip_micro()},
		{"name": "staple_bit", "dir": OUTPUT_DIR, "body": _staple_bit()},
		{"name": "blade_fragment", "dir": OUTPUT_DIR, "body": _blade_fragment()},
		{"name": "sawdust_bit", "dir": OUTPUT_DIR, "body": _sawdust_bit()},
		{"name": "droplet_micro", "dir": OUTPUT_DIR, "body": _droplet_micro()},
		# Corridor pattern overlays (subtle material inside track, low contrast)
		{"name": "wood_grain_faint", "dir": OUTPUT_DIR, "body": _wood_grain_faint()},
		{"name": "cork_bump", "dir": OUTPUT_DIR, "body": _cork_bump()},
		{"name": "desk_pad_grid", "dir": OUTPUT_DIR, "body": _desk_pad_grid()},
		# Grip patch readable decals (with collision surfaces)
		{"name": "soapy_spill", "dir": PATCH_DIR, "body": _soapy_spill()},
		{"name": "oil_slick_small", "dir": PATCH_DIR, "body": _oil_slick_small()},
		{"name": "paper_scatter", "dir": PATCH_DIR, "body": _paper_scatter()},
		{"name": "sawdust_patch", "dir": PATCH_DIR, "body": _sawdust_patch()},
		{"name": "coffee_ring", "dir": PATCH_DIR, "body": _coffee_ring()},
		# Empty boundary hints (worn floor / shadow strips for none sectors)
		{"name": "worn_floor_hint", "dir": OUTPUT_DIR, "body": _worn_floor_hint()},
		{"name": "shadow_strip", "dir": OUTPUT_DIR, "body": _shadow_strip()},
		# Giant landmarks (300-600+ world units; some may collide if safe)
		{"name": "giant_cereal_box", "dir": GIANT_DIR, "body": _giant_cereal_box()},
		{"name": "giant_mug", "dir": GIANT_DIR, "body": _giant_mug()},
		{"name": "giant_watermelon", "dir": GIANT_DIR, "body": _giant_watermelon()},
		{"name": "giant_fork", "dir": GIANT_DIR, "body": _giant_fork()},
		{"name": "giant_basketball", "dir": GIANT_DIR, "body": _giant_basketball()},
		{"name": "giant_toolbox", "dir": GIANT_DIR, "body": _giant_toolbox()},
		{"name": "giant_paint_can", "dir": GIANT_DIR, "body": _giant_paint_can()},
		{"name": "giant_keyboard", "dir": GIANT_DIR, "body": _giant_keyboard()},
		{"name": "giant_monitor", "dir": GIANT_DIR, "body": _giant_monitor()},
		{"name": "giant_paper_stack", "dir": GIANT_DIR, "body": _giant_paper_stack()},
		{"name": "giant_pen", "dir": GIANT_DIR, "body": _giant_pen()},
	]

	for asset: Dictionary in assets:
		var asset_name := String(asset["name"])
		var out_dir := String(asset["dir"])
		var image := Image.new()
		var load_error := image.load_svg_from_buffer(_svg(String(asset["body"]), asset_name).to_utf8_buffer(), 4.0)
		if load_error != OK:
			push_error("VISUAL_DENSITY_GEN FAIL: %s SVG: %s" % [asset_name, error_string(load_error)])
			quit(1)
			return
		if image.get_width() != 1024 or image.get_height() != 1024:
			push_error("VISUAL_DENSITY_GEN FAIL: %s rendered at %dx%d" % [asset_name, image.get_width(), image.get_height()])
			quit(1)
			return
		var output_path := "%s/%s.png" % [out_dir, asset_name]
		var save_error := image.save_png(output_path)
		if save_error != OK:
			push_error("VISUAL_DENSITY_GEN FAIL: %s: %s" % [output_path, error_string(save_error)])
			quit(1)
			return
		print("SAVE %s OK" % output_path)

	# Also ensure some existing are referenced; no-op
	quit(0)


func _svg(body: String, title: String) -> String:
	return """<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
<title>%s</title>
<defs>
<linearGradient id="wood" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8c6f55"/><stop offset="0.5" stop-color="#5c4638"/><stop offset="1" stop-color="#3f2a22"/></linearGradient>
<linearGradient id="cork" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#c3a777"/><stop offset="0.5" stop-color="#8c6f55"/><stop offset="1" stop-color="#5c4638"/></linearGradient>
<linearGradient id="pad" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#6a7180"/><stop offset="1" stop-color="#4a5060"/></linearGradient>
<linearGradient id="spill" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#2e8b57" stop-opacity="0.6"/><stop offset="1" stop-color="#1a5f3f" stop-opacity="0.35"/></linearGradient>
<linearGradient id="oil" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#111316" stop-opacity="0.75"/><stop offset="1" stop-color="#2a2f33" stop-opacity="0.55"/></linearGradient>
<linearGradient id="paper" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#f5f0e3"/><stop offset="1" stop-color="#c3a777"/></linearGradient>
<linearGradient id="giantBox" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f4c65a"/><stop offset="0.5" stop-color="#e85a2e"/><stop offset="1" stop-color="#c81e2e"/></linearGradient>
<linearGradient id="giantMug" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#4a8fb8"/><stop offset="1" stop-color="#f5f0e3"/></linearGradient>
<linearGradient id="shadow" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#111316" stop-opacity="0.6"/><stop offset="1" stop-color="#111316" stop-opacity="0.1"/></linearGradient>
</defs>
%s
</svg>""" % [title, body]


func _crumb_micro() -> String:
	return """
<circle cx="80" cy="90" r="18" fill="#f5f0e3" opacity="0.85"/>
<circle cx="110" cy="105" r="12" fill="#c3a777" opacity="0.7"/>
<ellipse cx="140" cy="82" rx="14" ry="9" fill="#8c6f55" opacity="0.6"/>
<path d="M70 115 Q95 130 125 118" fill="none" stroke="#5c4638" stroke-width="3" opacity="0.5"/>
"""

func _crumb_micro2() -> String:
	return """
<rect x="65" y="75" width="22" height="14" rx="3" fill="#ead6aa" opacity="0.8" transform="rotate(-18 76 82)"/>
<circle cx="105" cy="100" r="15" fill="#f5f0e3" opacity="0.75"/>
<rect x="130" y="88" width="18" height="11" rx="2" fill="#c3a777" opacity="0.65" transform="rotate(25 139 93)"/>
"""

func _fiber_strand() -> String:
	return """
<path d="M55 70 Q80 95 105 78 Q135 105 160 85 Q185 110 205 82" fill="none" stroke="#5c4638" stroke-width="2.5" opacity="0.55" stroke-linecap="round"/>
<path d="M62 88 Q88 72 115 95" fill="none" stroke="#8c6f55" stroke-width="1.5" opacity="0.4"/>
"""

func _screw_small() -> String:
	return """
<rect x="95" y="70" width="8" height="52" rx="1" fill="#4a8fb8" opacity="0.9"/>
<circle cx="99" cy="68" r="9" fill="#2a2f33"/>
<path d="M94 64 L104 72 M94 72 L104 64" fill="none" stroke="#f5f0e3" stroke-width="2"/>
"""

func _pencil_shaving() -> String:
	return """
<path d="M60 140 Q90 95 140 115 Q175 80 200 130" fill="none" stroke="#f4c65a" stroke-width="7" opacity="0.7"/>
<path d="M68 132 Q95 108 138 122" fill="none" stroke="#c81e2e" stroke-width="2" opacity="0.6"/>
<circle cx="195" cy="125" r="6" fill="#3f2a22" opacity="0.5"/>
"""

func _paperclip_micro() -> String:
	return """
<path d="M70 80 Q95 65 115 85 Q135 60 160 82" fill="none" stroke="#2a2f33" stroke-width="6" stroke-linecap="round"/>
<path d="M78 88 Q100 75 120 92 Q138 72 155 90" fill="none" stroke="#8c6f55" stroke-width="3" opacity="0.6"/>
"""

func _staple_bit() -> String:
	return """
<rect x="75" y="95" width="40" height="8" rx="2" fill="#5c4638"/>
<rect x="80" y="85" width="6" height="18" rx="1" fill="#3f2a22"/>
<rect x="105" y="85" width="6" height="18" rx="1" fill="#3f2a22"/>
"""

func _blade_fragment() -> String:
	return """
<polygon points="80,70 130,85 125,105 75,92" fill="#8c6f55" opacity="0.65"/>
<line x1="88" y1="78" x2="120" y2="90" stroke="#111316" stroke-width="1.5" opacity="0.4"/>
"""

func _sawdust_bit() -> String:
	return """
<circle cx="90" cy="90" r="22" fill="#c3a777" opacity="0.35"/>
<circle cx="115" cy="105" r="14" fill="#8c6f55" opacity="0.45"/>
<circle cx="140" cy="82" r="11" fill="#5c4638" opacity="0.3"/>
"""

func _droplet_micro() -> String:
	return """
<path d="M100 70 Q115 95 100 115 Q85 95 100 70" fill="#4a8fb8" opacity="0.45"/>
<circle cx="100" cy="100" r="6" fill="#f5f0e3" opacity="0.3"/>
"""

func _wood_grain_faint() -> String:
	return """
<rect width="256" height="256" fill="none"/>
<path d="M20 40 Q60 55 100 38 Q150 52 190 35 Q230 48 250 40" fill="none" stroke="#5c4638" stroke-width="3" opacity="0.18"/>
<path d="M15 90 Q70 78 110 95 Q160 80 205 92 Q240 78 255 88" fill="none" stroke="#3f2a22" stroke-width="2" opacity="0.15"/>
<path d="M25 150 Q55 165 95 148 Q145 162 185 150 Q225 163 248 152" fill="none" stroke="#5c4638" stroke-width="2.5" opacity="0.12"/>
"""

func _cork_bump() -> String:
	return """
<rect width="256" height="256" fill="#c3a777" opacity="0.08"/>
<circle cx="70" cy="70" r="18" fill="#8c6f55" opacity="0.12"/>
<circle cx="160" cy="90" r="14" fill="#5c4638" opacity="0.1"/>
<circle cx="100" cy="160" r="22" fill="#3f2a22" opacity="0.08"/>
<circle cx="190" cy="170" r="11" fill="#8c6f55" opacity="0.15"/>
"""

func _desk_pad_grid() -> String:
	return """
<rect width="256" height="256" fill="#4a5060" opacity="0.06"/>
<path d="M0 32 H256 M0 64 H256 M0 96 H256 M0 128 H256 M0 160 H256 M0 192 H256 M0 224 H256" fill="none" stroke="#f5f0e3" stroke-width="1" opacity="0.12"/>
<path d="M32 0 V256 M64 0 V256 M96 0 V256 M128 0 V256 M160 0 V256 M192 0 V256 M224 0 V256" fill="none" stroke="#f5f0e3" stroke-width="1" opacity="0.12"/>
"""

func _soapy_spill() -> String:
	return """
<ellipse cx="128" cy="128" rx="85" ry="55" fill="url(#spill)"/>
<ellipse cx="95" cy="105" rx="28" ry="18" fill="#f5f0e3" opacity="0.25"/>
<ellipse cx="155" cy="150" rx="22" ry="14" fill="#f5f0e3" opacity="0.2"/>
"""

func _oil_slick_small() -> String:
	return """
<ellipse cx="128" cy="130" rx="72" ry="38" fill="url(#oil)"/>
<ellipse cx="100" cy="115" rx="18" ry="10" fill="#2e8b57" opacity="0.15"/>
"""

func _paper_scatter() -> String:
	return """
<rect x="60" y="90" width="55" height="38" rx="3" fill="url(#paper)" opacity="0.55" transform="rotate(-12 87 104)"/>
<rect x="115" y="105" width="48" height="32" rx="2" fill="#f5f0e3" opacity="0.5" transform="rotate(18 139 121)"/>
<rect x="150" y="85" width="42" height="28" rx="2" fill="url(#paper)" opacity="0.45" transform="rotate(-8 171 99)"/>
"""


func _sawdust_patch() -> String:
	return """
<ellipse cx="128" cy="130" rx="82" ry="46" fill="#c3a777" opacity="0.34"/>
<circle cx="88" cy="118" r="13" fill="#8c6f55" opacity="0.46"/>
<circle cx="116" cy="142" r="10" fill="#5c4638" opacity="0.32"/>
<circle cx="151" cy="112" r="15" fill="#ead6aa" opacity="0.42"/>
<circle cx="177" cy="139" r="9" fill="#8c6f55" opacity="0.38"/>
"""


func _coffee_ring() -> String:
	return """
<ellipse cx="128" cy="128" rx="72" ry="48" fill="none" stroke="#3f2a22" stroke-width="11" opacity="0.46"/>
<ellipse cx="128" cy="128" rx="58" ry="36" fill="none" stroke="#8c6f55" stroke-width="4" opacity="0.34"/>
<path d="M185 145 Q204 153 210 171" fill="none" stroke="#3f2a22" stroke-width="8" opacity="0.28" stroke-linecap="round"/>
"""

func _worn_floor_hint() -> String:
	return """
<rect x="30" y="100" width="196" height="28" rx="4" fill="#3f2a22" opacity="0.12"/>
<path d="M40 108 Q90 115 140 106 Q190 114 220 107" fill="none" stroke="#5c4638" stroke-width="4" opacity="0.18"/>
"""

func _shadow_strip() -> String:
	return """
<rect x="20" y="110" width="216" height="16" rx="2" fill="#111316" opacity="0.22"/>
<rect x="25" y="115" width="200" height="6" rx="1" fill="#000000" opacity="0.1"/>
"""

func _giant_cereal_box() -> String:
	return """
<rect x="40" y="30" width="176" height="200" rx="8" fill="url(#giantBox)" stroke="#1a1f23" stroke-width="8"/>
<rect x="55" y="55" width="146" height="40" fill="#f5f0e3" opacity="0.3"/>
<text x="128" y="82" font-size="22" fill="#1a1f23" text-anchor="middle" font-family="sans-serif" font-weight="bold">CRISP</text>
<rect x="70" y="110" width="116" height="90" fill="#f5f0e3" opacity="0.15"/>
<line x1="70" y1="140" x2="186" y2="140" stroke="#1a1f23" stroke-width="3" opacity="0.4"/>
<line x1="70" y1="165" x2="186" y2="165" stroke="#1a1f23" stroke-width="3" opacity="0.4"/>
"""

func _giant_mug() -> String:
	return """
<ellipse cx="115" cy="80" rx="55" ry="25" fill="url(#giantMug)" stroke="#1a1f23" stroke-width="6"/>
<rect x="65" y="75" width="100" height="120" rx="12" fill="url(#giantMug)" stroke="#1a1f23" stroke-width="6"/>
<ellipse cx="115" cy="195" rx="55" ry="18" fill="#2a2f33" opacity="0.3"/>
<ellipse cx="155" cy="115" rx="18" ry="32" fill="#4a8fb8" stroke="#1a1f23" stroke-width="5"/>
"""

func _giant_watermelon() -> String:
	return """
<ellipse cx="128" cy="128" rx="105" ry="78" fill="#c81e2e" stroke="#1a1f23" stroke-width="7"/>
<ellipse cx="128" cy="128" rx="82" ry="58" fill="#2e8b57"/>
<path d="M50 90 Q80 70 110 95 Q140 65 175 92 Q200 75 215 105" fill="none" stroke="#f5f0e3" stroke-width="4" opacity="0.6"/>
<path d="M45 130 Q75 115 105 138 Q135 112 170 135 Q195 118 220 142" fill="none" stroke="#f5f0e3" stroke-width="3" opacity="0.45"/>
"""

func _giant_fork() -> String:
	return """
<rect x="118" y="30" width="20" height="180" rx="3" fill="#8c6f55" stroke="#1a1f23" stroke-width="4"/>
<rect x="70" y="35" width="16" height="55" rx="2" fill="#5c4638"/>
<rect x="105" y="25" width="16" height="65" rx="2" fill="#5c4638"/>
<rect x="140" y="35" width="16" height="55" rx="2" fill="#5c4638"/>
<rect x="175" y="28" width="16" height="60" rx="2" fill="#5c4638"/>
"""

func _giant_basketball() -> String:
	return """
<circle cx="128" cy="128" r="105" fill="#e85a2e" stroke="#1a1f23" stroke-width="8"/>
<circle cx="128" cy="128" r="92" fill="none" stroke="#3f2a22" stroke-width="4" opacity="0.5"/>
<path d="M30 70 Q128 128 225 70" fill="none" stroke="#1a1f23" stroke-width="5"/>
<path d="M30 185 Q128 128 225 185" fill="none" stroke="#1a1f23" stroke-width="5"/>
<path d="M70 25 Q128 128 70 230" fill="none" stroke="#1a1f23" stroke-width="5"/>
<path d="M185 25 Q128 128 185 230" fill="none" stroke="#1a1f23" stroke-width="5"/>
"""

func _giant_toolbox() -> String:
	return """
<rect x="35" y="70" width="186" height="110" rx="6" fill="#2a2f33" stroke="#1a1f23" stroke-width="7"/>
<rect x="50" y="85" width="156" height="55" rx="3" fill="#5c4638"/>
<rect x="55" y="45" width="30" height="30" rx="2" fill="#4a8fb8"/>
<rect x="170" y="45" width="30" height="30" rx="2" fill="#4a8fb8"/>
<line x1="50" y1="115" x2="205" y2="115" stroke="#f4c65a" stroke-width="4" opacity="0.6"/>
"""

func _giant_paint_can() -> String:
	return """
<rect x="55" y="55" width="146" height="130" rx="10" fill="#c81e2e" stroke="#1a1f23" stroke-width="7"/>
<ellipse cx="128" cy="55" rx="73" ry="18" fill="#e85a2e"/>
<ellipse cx="128" cy="185" rx="73" ry="14" fill="#3f2a22"/>
<rect x="75" y="80" width="106" height="30" fill="#f5f0e3" opacity="0.25"/>
"""

func _giant_keyboard() -> String:
	return """
<rect x="25" y="55" width="206" height="145" rx="8" fill="#2a2f33" stroke="#1a1f23" stroke-width="6"/>
<g fill="#f5f0e3" opacity="0.85">
<rect x="38" y="68" width="18" height="16" rx="2"/><rect x="60" y="68" width="18" height="16" rx="2"/><rect x="82" y="68" width="18" height="16" rx="2"/><rect x="104" y="68" width="18" height="16" rx="2"/>
<rect x="38" y="90" width="18" height="16" rx="2"/><rect x="60" y="90" width="18" height="16" rx="2"/><rect x="82" y="90" width="18" height="16" rx="2"/><rect x="104" y="90" width="18" height="16" rx="2"/>
<rect x="38" y="112" width="18" height="16" rx="2"/><rect x="60" y="112" width="18" height="16" rx="2"/><rect x="82" y="112" width="18" height="16" rx="2"/><rect x="104" y="112" width="18" height="16" rx="2"/>
<rect x="130" y="68" width="32" height="16" rx="2"/><rect x="130" y="90" width="32" height="16" rx="2"/><rect x="130" y="112" width="32" height="16" rx="2"/>
<rect x="38" y="138" width="166" height="12" rx="2"/>
</g>
"""

func _giant_monitor() -> String:
	return """
<rect x="45" y="40" width="166" height="120" rx="4" fill="#1a1f23" stroke="#4a8fb8" stroke-width="8"/>
<rect x="55" y="50" width="146" height="100" fill="#f5f0e3" opacity="0.15"/>
<rect x="85" y="165" width="86" height="18" rx="2" fill="#2a2f33"/>
<rect x="105" y="183" width="46" height="8" rx="1" fill="#5c4638"/>
"""

func _giant_paper_stack() -> String:
	return """
<rect x="50" y="45" width="156" height="22" rx="2" fill="#f5f0e3" stroke="#1a1f23" stroke-width="3"/>
<rect x="45" y="70" width="166" height="22" rx="2" fill="#ead6aa" stroke="#1a1f23" stroke-width="3"/>
<rect x="55" y="95" width="146" height="22" rx="2" fill="#c3a777" stroke="#1a1f23" stroke-width="3"/>
<rect x="48" y="120" width="160" height="22" rx="2" fill="#f5f0e3" stroke="#1a1f23" stroke-width="3"/>
<rect x="42" y="145" width="172" height="22" rx="2" fill="#ead6aa" stroke="#1a1f23" stroke-width="3"/>
<line x1="60" y1="55" x2="195" y2="55" stroke="#5c4638" stroke-width="1" opacity="0.3"/>
"""

func _giant_pen() -> String:
	return """
<rect x="115" y="25" width="26" height="200" rx="4" fill="#e85a2e" stroke="#1a1f23" stroke-width="5"/>
<ellipse cx="128" cy="30" rx="13" ry="8" fill="#f4c65a"/>
<rect x="118" y="210" width="20" height="18" rx="2" fill="#2a2f33"/>
"""
